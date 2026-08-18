#!/usr/bin/env bash

set -euo pipefail
umask 077

for dependency in awk date git go jq lsof ps uuidgen; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    printf 'required command is unavailable: %s\n' "$dependency" >&2
    exit 2
  fi
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_dir/../../.." && pwd)"
utc_date="$(date -u +%Y-%m-%d)"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$(uuidgen | tr '[:upper:]' '[:lower:]' | cut -c1-8)"
run_root="$repository_root/tmp/$utc_date/agent-session-resource-live.sh"
run_number=1
mkdir -p "$run_root"
while ! mkdir "$run_root/$run_number" 2>/dev/null; do
  run_number=$((run_number + 1))
done
result_path="$run_root/$run_number/result.json"
source_commit="$(git -C "$repository_root" rev-parse HEAD)"
duration_seconds="${HYPERLITE_RESOURCE_DURATION_SECONDS:-1800}"
sample_seconds="${HYPERLITE_RESOURCE_SAMPLE_SECONDS:-5}"
soak_seconds="${HYPERLITE_RESOURCE_SOAK_SECONDS:-0}"
warmup_seconds="${HYPERLITE_RESOURCE_WARMUP_SECONDS:-30}"
app_pid="${HYPERLITE_APP_PID:-}"

case "$duration_seconds:$sample_seconds" in
  *[!0-9:]*|0:*|*:0)
    printf 'resource durations must be bounded non-negative integers\n' >&2
    exit 2
    ;;
esac
for optional_duration in "$soak_seconds" "$warmup_seconds"; do
  case "$optional_duration" in
    ''|*[!0-9]*)
      printf 'resource durations must be bounded non-negative integers\n' >&2
      exit 2
      ;;
  esac
done

temp_root="$(mktemp -d /tmp/hyperlite-agent-resource.XXXXXX)"
home="$temp_root/home"
runtime="$temp_root/runtime"
input_fifo="$temp_root/input"
output="$temp_root/output.jsonl"
errors="$temp_root/error.log"
socket="$runtime/agent.sock"
helper_pid=""
average_cpu=""
peak_rss=""
rss_growth=""
final_descriptors=""
final_threads=""
samples=0

cleanup() {
  exit_code="$?"
  exec 3>&- || true
  if [[ -n "$helper_pid" ]]; then
    for _ in {1..50}; do
      if ! kill -0 "$helper_pid" 2>/dev/null; then break; fi
      sleep 0.1
    done
    if kill -0 "$helper_pid" 2>/dev/null; then
      kill -TERM "$helper_pid" 2>/dev/null || true
    fi
    wait "$helper_pid" 2>/dev/null || true
  fi
  if [[ -e "$socket" ]]; then
    printf 'owned socket remained after helper shutdown\n' >&2
    exit_code=1
  fi
  result="FAIL"
  if [[ "$exit_code" -eq 0 ]]; then result="PASS"; fi
  jq -n \
    --arg result "$result" \
    --arg run_id "$run_id" \
    --arg started_at "$started_at" \
    --arg finished_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg source_commit "$source_commit" \
    --arg average_cpu "$average_cpu" \
    --arg peak_rss_kib "$peak_rss" \
    --arg rss_growth_percent "$rss_growth" \
    --arg descriptors "$final_descriptors" \
    --arg threads "$final_threads" \
    --argjson run_number "$run_number" \
    --argjson samples "$samples" \
    --argjson duration_seconds "$duration_seconds" \
    --argjson soak_seconds "$soak_seconds" \
    '{schema_version:1, project:"hyperlite", suite:"agent session resources", environment:"local",
      result:$result, run_id:$run_id, run_number:$run_number, started_at:$started_at,
      finished_at:$finished_at, source_commit:$source_commit, duration_seconds:$duration_seconds,
      soak_seconds:$soak_seconds, samples:$samples, average_cpu:$average_cpu,
      peak_rss_kib:$peak_rss_kib, rss_growth_percent:$rss_growth_percent,
      descriptors:$descriptors, threads:$threads,
      assertion_summary:"bounded 32-watcher and 100-session resource profile",
      cleanup_status:"owner EOF and socket cleanup checked"}' >"$result_path"
  rm -r "$temp_root"
  exit "$exit_code"
}
trap cleanup EXIT

mkdir -p "$home" "$runtime"
session_dir="$home/.codex/sessions/$(date +%Y/%m/%d)"
mkdir -p "$session_dir"
timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
for index in $(seq 1 32); do
  printf '{"timestamp":"%s","type":"session_meta","payload":{"id":"rollout-%s"}}\n' "$timestamp" "$index" >"$session_dir/rollout-$index.jsonl"
  printf '{"timestamp":"%s","type":"response_item","payload":{"type":"function_call","call_id":"wait-%s","name":"request_user_input"}}\n' "$timestamp" "$index" >>"$session_dir/rollout-$index.jsonl"
  chmod 600 "$session_dir/rollout-$index.jsonl"
done

cd "$repository_root"
make build >/dev/null
mkfifo "$input_fifo"
exec 3<>"$input_fifo"
HOME="$home" PATH="/usr/bin:/bin" \
  "$repository_root/bin/hyperlite" agent sessions serve --socket "$socket" \
  3>&- <"$input_fifo" >"$output" 2>"$errors" &
helper_pid="$!"

for _ in {1..100}; do
  if [[ -S "$socket" ]]; then break; fi
  sleep 0.05
done
[[ -S "$socket" ]] || { printf 'agent socket did not start\n' >&2; exit 1; }

for index in $(seq 1 68); do
  printf '{"event":"session_start","session_id":"synthetic-%s","status":"processing"}\n' "$index" |
    HOME="$home" PATH="/usr/bin:/bin" "$repository_root/bin/hyperlite" agent hook \
      --profile claude-code --socket "$socket" --wait-seconds 1 >/dev/null
done

for _ in {1..200}; do
  ready="$(jq -s '
    ([.[] | select(.schema == "agent_session_snapshot.v2")] | last | .sessions | length) == 100 and
    ([.[] | select(.schema == "agent_integration_health.v1" and .profile == "codex")] | last | .watchers_used) == 32
  ' "$output" 2>/dev/null || true)"
  if [[ "$ready" == "true" ]]; then break; fi
  sleep 0.05
done
[[ "$ready" == "true" ]] || { printf 'bounded synthetic runtime did not settle\n' >&2; exit 1; }

sleep "$warmup_seconds"

rss_kib() { ps -o rss= -p "$1" | awk '{print $1 + 0}'; }
cpu_percent() { ps -o %cpu= -p "$1" | awk '{print $1 + 0}'; }
descriptor_count() { lsof -p "$1" 2>/dev/null | awk 'NR > 1 {count++} END {print count + 0}'; }
thread_count() { ps -M -p "$1" | awk 'NR > 1 {count++} END {print count + 0}'; }

baseline_rss="$(rss_kib "$helper_pid")"
baseline_descriptors="$(descriptor_count "$helper_pid")"
baseline_threads="$(thread_count "$helper_pid")"
samples=0
cpu_sum=0
peak_rss="$baseline_rss"
deadline=$((SECONDS + duration_seconds))
while (( SECONDS < deadline )); do
  helper_cpu="$(cpu_percent "$helper_pid")"
  combined_cpu="$helper_cpu"
  if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then
    combined_cpu="$(awk -v left="$helper_cpu" -v right="$(cpu_percent "$app_pid")" 'BEGIN {printf "%.4f", left + right}')"
  fi
  cpu_sum="$(awk -v total="$cpu_sum" -v value="$combined_cpu" 'BEGIN {printf "%.4f", total + value}')"
  current_rss="$(rss_kib "$helper_pid")"
  if (( current_rss > peak_rss )); then peak_rss="$current_rss"; fi
  samples=$((samples + 1))
  sleep "$sample_seconds"
done

if (( soak_seconds > 0 )); then
  soak_deadline=$((SECONDS + soak_seconds))
  while (( SECONDS < soak_deadline )); do sleep "$sample_seconds"; done
fi

average_cpu="$(awk -v total="$cpu_sum" -v count="$samples" 'BEGIN {if (count == 0) print 0; else printf "%.4f", total / count}')"
final_rss="$(rss_kib "$helper_pid")"
final_descriptors="$(descriptor_count "$helper_pid")"
final_threads="$(thread_count "$helper_pid")"
rss_growth="$(awk -v first="$baseline_rss" -v last="$final_rss" 'BEGIN {if (first == 0) print 0; else printf "%.4f", ((last - first) / first) * 100}')"

awk -v value="$average_cpu" 'BEGIN {exit !(value <= 1.0)}' || { printf 'idle CPU exceeded 1%%: %s\n' "$average_cpu" >&2; exit 1; }
(( peak_rss <= 76800 )) || { printf 'helper RSS exceeded 75 MiB: %s KiB\n' "$peak_rss" >&2; exit 1; }
(( final_descriptors <= baseline_descriptors )) || { printf 'descriptor count grew: %s to %s\n' "$baseline_descriptors" "$final_descriptors" >&2; exit 1; }
(( final_threads <= baseline_threads )) || { printf 'thread count grew: %s to %s\n' "$baseline_threads" "$final_threads" >&2; exit 1; }
awk -v value="$rss_growth" 'BEGIN {exit !(value < 10.0)}' || { printf 'RSS growth reached 10%%: %s\n' "$rss_growth" >&2; exit 1; }

printf 'PASS average_cpu=%s peak_rss_kib=%s rss_growth_percent=%s descriptors=%s threads=%s samples=%s duration_seconds=%s soak_seconds=%s\n' \
  "$average_cpu" "$peak_rss" "$rss_growth" "$final_descriptors" "$final_threads" "$samples" "$duration_seconds" "$soak_seconds"
