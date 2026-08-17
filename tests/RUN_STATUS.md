# VALIDATION RUN STATUS

| Suite | Environment | Current status | Latest attempt | Latest pass | Source/deployment | Run ID | Evidence | Active finding |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| inferred attention recovery | local | PASS | 2026-07-28T16:50:31Z | 2026-07-28T16:50:31Z | GH-7 working tree | 20260728T165027Z-4fc343c6 | `tmp/2026-07-28/inferred-attention-live-scan.sh/3/` | live Ollama enrichment unobserved because no model is configured; deterministic recovery passed |
| agent sessions bridge | local | PASS | 2026-08-17T21:27:45Z | 2026-08-17T21:27:45Z | GH-47 working tree | 20260817T212743Z-db3aca03 | `tmp/2026-08-17/agent-session-bridge-live.sh/6/` | strict raw-object identity and allowlist validation, exact socket/action/disconnect/child cleanup, and metadata-only 20-profile inventory passed |
| agent sessions provider/display acceptance | local | PARTIAL | 2026-08-17T22:06:49Z | none | GH-47 working tree | 20260817T220649Z-5b643be8 | `tmp/2026-08-17/agent-session-ui-manual/5/` | deterministic notchless hide/hover/expanded policy and exact packaged cleanup passed; the current host exposed a physical notch, so live notchless hover, the complete physical-notch journey, and real lifecycle/action proof for every frozen provider remain unobserved |
| application deployment | production | NOT_APPLICABLE | 2026-07-28 | not applicable | local desktop application | none | none | Hyperlite has no deployed production environment |
