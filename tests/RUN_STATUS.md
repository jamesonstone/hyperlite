# VALIDATION RUN STATUS

| Suite | Environment | Current status | Latest attempt | Latest pass | Source/deployment | Run ID | Evidence | Active finding |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| inferred attention recovery | local | PASS | 2026-07-28T16:50:31Z | 2026-07-28T16:50:31Z | GH-7 working tree | 20260728T165027Z-4fc343c6 | `tmp/2026-07-28/inferred-attention-live-scan.sh/3/` | live Ollama enrichment unobserved because no model is configured; deterministic recovery passed |
| agent sessions bridge | local | PASS | 2026-08-17T17:54:35Z | 2026-08-17T17:54:35Z | GH-47 working tree | 20260817T175432Z-0ee2f48d | `tmp/2026-08-17/agent-session-bridge-live.sh/3/` | exact socket/action/disconnect/child cleanup and metadata-only 20-profile inventory passed |
| agent sessions provider/display acceptance | local | PARTIAL | 2026-08-17T17:45:47Z | none | GH-47 working tree | 20260817T174547Z-topedge | `tmp/2026-08-17/agent-session-ui-manual/1/` | top-edge and synthetic Claude-compatible response passed; physical-notch hardware and real lifecycle/action proof for every frozen provider remain unavailable |
| application deployment | production | NOT_APPLICABLE | 2026-07-28 | not applicable | local desktop application | none | none | Hyperlite has no deployed production environment |
