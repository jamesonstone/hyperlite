#!/usr/bin/env bash

set -euo pipefail

for dependency in git go jq rg uuidgen; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    printf 'required command is unavailable: %s\n' "$dependency" >&2
    exit 2
  fi
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_dir/../../.." && pwd)"
test_id="agent-session-bridge-live.sh"
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
integrations_path="$run_dir/integrations.json"
result_path="$run_dir/result.json"
source_commit="$(git -C "$repository_root" rev-parse HEAD)"
result="FAIL"
assertion_summary="agent-session bridge validation did not complete"

finish() {
  exit_code="$?"
  finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  finished_epoch="$(date -u +%s)"
  duration_seconds=$((finished_epoch - started_epoch))
  if [[ "$exit_code" -eq 0 ]]; then result="PASS"; fi
  jq -n \
    --arg result "$result" \
    --arg run_id "$run_id" \
    --arg started_at "$started_at" \
    --arg finished_at "$finished_at" \
    --arg source_commit "$source_commit" \
    --arg assertion_summary "$assertion_summary" \
    --argjson exit_code "$exit_code" \
    --argjson run_number "$run_number" \
    --argjson duration_seconds "$duration_seconds" \
    '{
      schema_version: 1,
      project: "hyperlite",
      suite: "agent sessions bridge",
      stable_test_id: "agent-session-bridge-live.sh",
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
      target_identity: "isolated local Unix socket and detected-client inventory",
      assertion_summary: $assertion_summary,
      cleanup_status: "PASS; tests verify owner EOF and socket cleanup",
      artifacts: ["output.txt", "integrations.json"]
    }' >"$result_path"
}
trap finish EXIT

exec > >(tee "$output_path") 2>&1

cd "$repository_root"

make -C "$repository_root" build
go test ./internal/agentsession \
  -run 'TestServiceRoundTripUsesExactLiveResponseChannel|TestServiceStopsWhenOwningAppClosesInput|TestServiceRetractsActionWhenProviderDisconnects|TestOwnerEOFStopsOwnedCodexProcess|TestRuntimeSocketIsUserOnly' \
  -v -count=1 -timeout 30s
go test ./internal/cli \
  -run 'TestAgentIntegrationsListDoesNotRequireProjectConfig|TestAgentHookFailsOpenWhenAppIsUnavailable' \
  -v -count=1 -timeout 30s

"$repository_root/bin/hyperlite" agent integrations list |
  jq -e '
    def allowed_keys:
      ["action_mode", "detected", "enabled", "id", "name", "provider", "schema", "target"];
    if type == "array" and length == 20 and
      all(.[];
        type == "object" and ((keys - allowed_keys) | length == 0) and
        (.id | type == "string" and length > 0) and
        (.name | type == "string" and length > 0))
    then [.[] | {id, name, detected, enabled, action_mode}]
    else error("integration inventory contains an unexpected field")
    end
  ' >"$integrations_path"
jq -e 'length == 20 and all(.[]; .id != "" and .name != "")' "$integrations_path" >/dev/null
if rg -n '(prompt|response|transcript|raw_payload|authorization|cookie|password|secret|token)' "$integrations_path"; then
  printf 'integration inventory contains a forbidden content-bearing field\n' >&2
  exit 1
fi

assertion_summary="private socket permissions, exact live action round trip, disconnect retraction, owner EOF cleanup including Codex child termination, fail-open hook delivery, and 20-profile metadata-only inventory passed"
printf '%s\n' "$assertion_summary"
