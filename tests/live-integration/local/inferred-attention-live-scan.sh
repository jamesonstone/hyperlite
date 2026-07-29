#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  printf 'usage: %s <r2-path> <event-sink-path>\n' "$0" >&2
  exit 2
fi

for dependency in git gh jq uuidgen; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    printf 'required command is unavailable: %s\n' "$dependency" >&2
    exit 2
  fi
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_dir/../../.." && pwd)"
r2_path="$(cd "$1" && pwd)"
event_sink_path="$(cd "$2" && pwd)"
test_id="inferred-attention-live-scan.sh"
utc_date="$(date -u +%Y-%m-%d)"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
started_epoch="$(date -u +%s)"
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$(uuidgen | tr '[:upper:]' '[:lower:]' | cut -c1-8)"
run_root="$repository_root/tmp/$utc_date/$test_id"
run_number=1

mkdir -p "$run_root"
while ! mkdir "$run_root/$run_number" 2>/dev/null; do
  run_number=$((run_number + 1))
done

run_dir="$run_root/$run_number"
output_path="$run_dir/output.txt"
scan_path="$run_dir/scan.json"
state_path="$run_dir/threads.json"
result_path="$run_dir/result.json"
source_commit="$(git -C "$repository_root" rev-parse HEAD)"
result="FAIL"
assertion_summary="live scan did not complete"

finish() {
  exit_code="$?"
  finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  finished_epoch="$(date -u +%s)"
  duration_seconds=$((finished_epoch - started_epoch))
  if [[ "$exit_code" -eq 0 ]]; then
    result="PASS"
  fi
  jq -n \
    --arg result "$result" \
    --arg run_id "$run_id" \
    --arg started_at "$started_at" \
    --arg finished_at "$finished_at" \
    --arg source_commit "$source_commit" \
    --arg target_identity "$r2_path,$event_sink_path" \
    --arg assertion_summary "$assertion_summary" \
    --argjson exit_code "$exit_code" \
    --argjson run_number "$run_number" \
    --argjson duration_seconds "$duration_seconds" \
    '{
      schema_version: 1,
      project: "hyperlite",
      suite: "inferred attention recovery",
      stable_test_id: "inferred-attention-live-scan.sh",
      environment: "local",
      run_id: $run_id,
      run_number: $run_number,
      started_at: $started_at,
      finished_at: $finished_at,
      duration_seconds: $duration_seconds,
      result: $result,
      exit_code: $exit_code,
      source_commit: $source_commit,
      deployed_version: null,
      target_identity: $target_identity,
      assertion_summary: $assertion_summary,
      cleanup_status: "not applicable; read-only scan",
      artifacts: ["output.txt", "scan.json", "threads.json"]
    }' >"$result_path"
}
trap finish EXIT

exec > >(tee "$output_path") 2>&1

make -C "$repository_root" build
HYPERLITE_STATE_PATH="$state_path" \
  "$repository_root/bin/hyperlite" scan --json --no-refresh \
  "$r2_path" "$event_sink_path" >"$scan_path"

jq -e '
  (.errors | length) == 0 and
  ([.threads[].artifacts[].id] | length) ==
    ([.threads[].artifacts[].id] | unique | length) and
  all(
    .threads[].artifacts[];
    .evidence_id != "" and ((.url // .path // "") != "")
  ) and
  ([.threads[] | select(.id == "issue:lsmc-bio/r2#21")] | length) == 1 and
  ([.threads[] | select(.id == "issue:lsmc-bio/event-sink#26")] | length) == 1 and
  all(
    .threads[]
    | select(
        .id == "issue:lsmc-bio/r2#21" or
        .id == "issue:lsmc-bio/event-sink#26"
      );
    .active == true and
    any(.artifacts[]; .kind == "pull_request" and .state == "open") and
    (.obligations | length) > 0 and
    (.implications | length) > 0 and
    any(
      .dependencies[];
      .basis == "hypothesis" and (.evidence_ids | length) > 0
    )
  )
' "$scan_path" >/dev/null

assertion_summary="separate R2 #21 and Event Sink #26 threads include open PRs, obligations, implications, and cited relationships"
jq '{
  summary,
  threads: [
    .threads[]
    | select(
        .id == "issue:lsmc-bio/r2#21" or
        .id == "issue:lsmc-bio/event-sink#26"
      )
    | {
        id,
        phase,
        artifacts: [.artifacts[] | {kind, state, evidence_id, pointer: (.url // .path)}],
        obligations,
        dependencies,
        implications,
        attention
      }
  ]
}' "$scan_path"
