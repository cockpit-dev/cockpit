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
| Lease recovery | `operation run --kind lease.list`, `operation run --kind lease.recover` |
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

- Read `executionMode`, `defaultTimeoutMs`, and `maximumTimeoutMs` from the
  advertised operation descriptor. Synchronous operations block to a result;
  job operations return a durable `runId` for later observation.
- A synchronous invocation may set one relative `timeoutMs` or absolute
  `deadline`. Case and suite submissions use `timeoutMs` as their overall run
  budget; step, command, cleanup, and launch budgets remain independent inner
  limits.
- Submission and mutation idempotency keys are stable per logical action.
- SSE sequence numbers are monotonic and resumable.
- Suite checkpoints preserve completed nodes, attempts, fixture state, and
  session affinity across worker recovery.
- A cancelled suite still runs eligible always-run teardown within bounded
  grace, then publishes terminal events and reports.
- List run artifacts first, then download by run/artifact identity to an
  explicit `--output` file. Cockpit verifies media type, size, and SHA-256
  before committing the file; binary bytes never belong in terminal output.
- Quarantined resources remain blocked until cleanup is verified. The
  `reset`-authorized `lease.recover` requires exact lease, workspace, resource,
  and holder identities. Only logical resources allow explicit force release;
  forwarded ports always require verified cleanup.

## Output Selection

CLI `auto` output is compact semantic text. Use `--detail minimal|standard|full`
to control its projection, `--stdout-format json` for an exact response,
`jsonl` for streaming run events, and `--output <file>` for lossless JSON plus
a bounded receipt. Use `minimal` target inspection for routine loops and
`inspect`/`evidence` only when the additional runtime state proves the claim.

## Release Gate

Repository publication requires formatting, analysis, every package and
example test, publication dry-runs, and successful Android, iOS, macOS, Linux,
web, and Windows regressions. Wait for the whole matrix to reach terminal state
before triage, then inspect its reports, event streams, verified artifacts, and
daemon logs together. One local run or one passing platform is not release
evidence.
