# Cockpit 2.0 Reference

## Authorities

| Need | Source |
| --- | --- |
| HTTP and SSE | `packages/cockpit_protocol/openapi/cockpit.v2.openapi.json` |
| Foundation DTOs | `packages/cockpit_protocol/schema/cockpit.foundation.v2.schema.json` |
| Case/suite/project documents | `packages/cockpit_protocol/schema/cockpit.test.v2.schema.json` |
| Architecture and ownership | `docs/contracts/cockpit-protocol.md` |
| AI execution policy | `docs/contracts/ai-development-protocol.md` |
| Authorization policy | `COCKPIT_HOME/authorization.json` |

Use schemas or tool metadata for exact fields. Do not infer payload keys from
examples.

## Command Map

| Need | Command |
| --- | --- |
| Daemon health | `cockpit daemon status`, `cockpit daemon doctor` |
| Roots/workspaces | `cockpit root ...`, `cockpit workspace ...` |
| Target discovery/liveness | `cockpit target discover`, `target inspect` |
| Typed development action | `cockpit operation list`, `operation run` |
| Validate/run case | `cockpit case validate`, `case run` |
| Validate/run suite | `cockpit suite validate`, `suite run` |
| Observe/cancel | `cockpit run get`, `run events`, `run cancel` |
| Report/artifact | `cockpit suite report`, `artifact list`, `artifact read` |
| MCP | `cockpit serve-mcp` or the `cockpit_mcp` executable |

Run `cockpit help <command> <subcommand>` for current options.

## Target Rules

- `nativeApp`, `desktopApp`, and `browserPage` require a nonblank `appId`.
- A Flutter target uses an indexed entrypoint document and never requires
  production code to depend on the bridge.
- System/native capabilities are target and platform specific. Trust only
  operations advertised as available.
- Use one WDA URL per iOS target when multiple devices or workspaces run.
- Persisted `registered`/`launched` metadata is not live state; inspect it.

## Run Rules

- Submission and mutation idempotency keys are stable per logical action.
- SSE sequence numbers are monotonic and resumable.
- Suite checkpoints preserve completed nodes, attempts, fixture state, and
  session affinity across worker recovery.
- A cancelled suite still runs eligible always-run teardown within bounded
  grace, then publishes terminal events and reports.
- List run artifacts first; use the returned artifact ID, size, and SHA-256 for
  every bounded artifact read.

## Output Selection

Use `minimal` target inspection for routine loops, `standard` for debugging,
and `inspect`/`evidence` only when the additional state proves the claim. Prefer
structured report and error data before opening large artifacts.
