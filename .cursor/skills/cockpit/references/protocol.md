# Cockpit 3.0 Protocol Map

This is the skill-local authority map. Do not resolve any contract through a
Cockpit source checkout.

## Contents

- [Runtime authorities](#runtime-authorities)
- [Command map](#command-map)
- [Resource model](#resource-model)
- [Execution rules](#execution-rules)
- [Output rules](#output-rules)
- [MCP and third-party clients](#mcp-and-third-party-clients)

## Runtime Authorities

| Need | Authority |
| --- | --- |
| Current CLI flags | `cockpit help <command> <subcommand>` |
| Available operation and input | `op list --kind KIND`, then the returned descriptor |
| Live target capability | `target inspect --profile minimal|inspect` |
| Case/suite/project syntax | [`cockpit.test.v2.schema.json`](cockpit.test.v2.schema.json) |
| Authorization | `daemon policy show` and `daemon status` |
| Run truth | `run events`, `run get`, canonical report, verified artifacts |

Static prose explains decisions; live descriptors decide what the installed
version and current target can actually do.

## Command Map

| Need | Command |
| --- | --- |
| Supervisor | `daemon start|status|doctor|logs|restart|stop`, `server` |
| Authorization | `daemon policy show|validate|apply` |
| Roots/workspaces | `root add|list|remove`, `workspace register|list|documents|rebind|unregister` |
| Targets | `target discover|register|list|get|launch|inspect` |
| Operations | `op list|run` |
| Cases | `case validate|list|run` |
| Suites | `suite validate|list|run|report` |
| Runs | `run get|events|cancel` |
| Artifacts | `artifact list|read` |
| MCP | `serve-mcp` or the installed `cockpit_mcp` executable |

Run `cockpit help` when a command is absent or an option is unclear.
Never infer flags from an older Cockpit release.

## Resource Model

```text
Supervisor
  root
    workspace
      document
      target
      operation
      case / suite
  run
    case attempt
      step
      artifact
    event stream
    report
```

Every workspace-owned resource carries a workspace identity. Run and artifact
lookups use explicit IDs, never implicit "latest" global state. The Supervisor
isolates workers by workspace and engine version, allowing multiple projects
and checkouts to execute without sharing state or blocking unrelated work.

Targets cover Flutter apps, installed native/mobile apps, desktop apps,
browser pages, system surfaces, devices, and host workspaces. App-like
black-box targets use their real platform app identifier. An iOS WDA endpoint
is target-scoped so concurrent devices do not overwrite each other.

## Execution Rules

- Inspect the target and operation catalog before choosing an action.
- Trust advertised `executionMode`, `defaultTimeoutMs`, and
  `maximumTimeoutMs`.
- Synchronous operations block. Job operations return a durable `runId`.
- Omit the CLI `--timeout` default. Override it only with a bounded duration
  such as `90s`, `20m`, or `2h`; Cockpit derives the operation deadline.
- Case and suite `--timeout` values are overall run budgets. Step, command,
  cleanup, launch, and operation budgets remain independent inner limits.
- Submission and mutation idempotency keys are stable per logical action.
- SSE sequence numbers are monotonic and resumable.
- Suite checkpoints retain completed nodes, attempts, and fixtures.
- Suite checkpoints preserve session affinity across worker recovery.
- Cancellation still permits eligible always-run teardown within its bounded
  grace period, then publishes terminal events and reports.

The target has a default execution plane; a case step can select `semantic`,
`native`, `visual`, or `coordinate`. A Flutter target may combine semantic and
secondary native drivers. Read the sanitized secondary driver profile from
`target inspect` output; never reconstruct redacted app/process identities.

## Output Rules

Minimal LON is the normal low-token output. Omit `--verbosity minimal` and
`--format lon`; defaults never belong in normal commands. Command-specific
presenters remove repeated identities and share collection field headers.
LON, JSON, YAML, and JSONL all honor `--verbosity minimal|standard|full`;
verbosity changes information density, not operation accuracy. Select `full`
only for the complete object. For a complete non-binary response, use
`--verbosity full --format json --output <path>` so stdout is only the verified
path.

`artifact read` requires `--output`; it verifies media type, byte size, and
SHA-256 internally before committing the file, but stdout contains only the
path. Never place binary data, Base64, hashes, or decision-irrelevant byte
counts in terminal output.

## MCP And Third-Party Clients

CLI and MCP are clients of the same authenticated Supervisor API. MCP tools
should be selected from their live schemas exactly as CLI operations are
selected from descriptors. Start stdio MCP with:

```bash
cockpit serve-mcp
```

When building another client, use the installed `cockpit_protocol` package for
OpenAPI/schema/Dart contracts. The skill is operational guidance, not a
replacement transport specification. Preserve resource IDs, authentication,
timeouts, idempotency, SSE resume, artifact digest checks, and canonical report
semantics across every client.
