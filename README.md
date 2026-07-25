<p align="center">
  <img src="assets/brand/cockpit-mark.svg" width="128" alt="Cockpit logo">
</p>

# Cockpit 2.0

[![E2E](https://github.com/cockpit-dev/cockpit/actions/workflows/example-e2e.yml/badge.svg)](https://github.com/cockpit-dev/cockpit/actions/workflows/example-e2e.yml)
[![License](https://img.shields.io/github/license/cockpit-dev/cockpit)](https://github.com/cockpit-dev/cockpit/blob/main/LICENSE)

[简体中文](README.zh-CN.md)

Cockpit is a production E2E automation and verification stack for AI,
CI, and local development. Cockpit 2.0 controls installed Android and iOS
applications as black boxes, drives Flutter applications through their richer
semantic bridge, and exposes the same typed resources to CLI, MCP, and future
independent clients.

It provides:

- standalone YAML or JSON cases and suites;
- semantic, native accessibility, system, visual, and coordinate planes;
- target discovery, registration, launch, inspection, and capability truth;
- dependency DAGs, fixtures, matrices, retries, bounded concurrency, and
  fail-fast suites;
- durable run events, restart-safe suite checkpoints, exact session affinity,
  cancellation, artifacts, and JSON/JUnit/HTML/AI reports;
- a per-user authenticated Supervisor with isolated per-workspace workers;
- resource-oriented CLI, HTTP/SSE API, and MCP clients without a bundled GUI.

## Packages

- [`cockpit_protocol`](packages/cockpit_protocol) owns platform-neutral DTOs,
  the test DSL, JSON Schema, and OpenAPI contract.
- [`cockpit`](packages/cockpit) owns the Supervisor, workspace workers, drivers,
  CLI, MCP server, reports, and artifacts.
- [`flutter_cockpit`](packages/flutter_cockpit) is the optional in-app Flutter
  semantic, observation, capture, and recording bridge.

Minimum versions are Dart 3.8.0 and Flutter 3.32.0. Add only what the project
uses:

```yaml
dev_dependencies:
  cockpit: ^2.0.0
  flutter_cockpit: ^2.0.0 # Optional Flutter semantic bridge.
```

Keep Cockpit development-only. Native black-box testing does not require an
application source dependency or a Flutter integration.
Do not add `flutter_cockpit` imports to production `lib/` code.

## Runtime Model

`cockpit` commands discover or start one daemon under `COCKPIT_HOME`. The daemon
owns authentication, workspace identity, authorization, admissions, leases,
ports, run projections, and artifacts. It starts an isolated worker for each
active workspace and engine version. No command relies on a global "latest"
project or session.

```text
CLI / MCP / third-party client
          |
    authenticated HTTP/SSE
          |
    per-user Supervisor
          |
  workspace-scoped worker
          |
 Flutter bridge / Android ADB / iOS WDA / host driver
```

Register multiple projects once, then address them explicitly or run a command
from inside exactly one registered workspace:

```bash
dart run cockpit daemon start
dart run cockpit root add --path /work/projects --label projects
dart run cockpit workspace register --root-id <rootId> --path /work/projects/app-a
dart run cockpit workspace register --root-id <rootId> --path /work/projects/app-b
dart run cockpit workspace list
```

## CLI Output

The default `auto` format is compact semantic text designed for agent terminal
loops. Use `--detail minimal|standard|full` to control projection size,
`--stdout-format json` for an exact protocol envelope, and `jsonl` for live run
events. `--output <file>` atomically writes the complete JSON response and
prints only a path, byte count, and SHA-256 receipt. Artifact bytes are always
downloaded to `--output`; Cockpit never emits them as Base64.

## Authorization

Dangerous operations and test safety effects are denied unless explicitly
authorized. Persist policy under `COCKPIT_HOME/authorization.json`; validate and
apply it through the CLI. A running daemon must be restarted so one process
cannot change authority mid-run.

```json
{
  "schemaVersion": "cockpit.supervisor.authorization/v2",
  "allowedDangerousOperations": [
    "app.launch",
    "app.restart",
    "app.stop",
    "command.batch",
    "command.run",
    "evidence.screenshot.capture",
    "lease.recover",
    "recording.start",
    "recording.stop",
    "system.action",
    "target.launch"
  ],
  "allowedOperationSafetyEffects": [
    "capture",
    "externalSideEffect",
    "permission",
    "recording",
    "reset",
    "system"
  ],
  "allowedTargetEnvironments": [
    "development",
    "test",
    "staging",
    "production"
  ],
  "allowedSafetyEffects": [
    "communication",
    "credentialSensitive",
    "destructive",
    "externalNavigation",
    "financial",
    "permissionChange"
  ],
  "allowedEnvironmentSecretNames": ["E2E_PASSWORD"]
}
```

```bash
dart run cockpit daemon policy validate --file authorization.json
dart run cockpit daemon policy apply --file authorization.json --restart
dart run cockpit daemon policy show
```

Only named environment secrets are copied into workspace workers. A policy may
explicitly authorize `production` or `unknown`; the default policy does not.
Quarantined leases remain blocked until verified cleanup succeeds. The
Supervisor advertises `lease.list` and the `reset`-authorized `lease.recover`
operation for exact lease/workspace/resource/holder identities. An explicit
`forceRelease: true` may release an unverified logical resource; forwarded
ports always require verified cleanup and can never be force released.

## Black-Box Targets

Register an installed application without changing its source:

```bash
dart run cockpit target register \
  --workspace-id <workspaceId> \
  --platform android \
  --device-id emulator-5554 \
  --target-kind nativeApp \
  --app-id com.example.app \
  --environment test \
  --mode automation \
  --idempotency-key android-target-001

dart run cockpit target launch --workspace-id <workspaceId> --target-id <targetId> \
  --idempotency-key android-launch-001
dart run cockpit target inspect --workspace-id <workspaceId> --target-id <targetId>
```

Android uses ADB and native accessibility. iOS Simulator uses `simctl`; native
iOS UI interaction uses a reachable WebDriverAgent endpoint. Physical iOS
installation and lifecycle use `devicectl` where available. Cockpit reports
unsupported or unavailable capabilities instead of claiming control it cannot
prove.

## Cases And Suites

Cases and suites use `schemaVersion: cockpit.test/v2`. Validate documents before
submitting them, and use stable idempotency keys for replay:

```bash
dart run cockpit case validate --workspace-id <workspaceId> --file cases/login.yaml
dart run cockpit case run --workspace-id <workspaceId> \
  --document-id <documentId> --case-id login \
  --idempotency-key login-2026-07-24 --inputs-json '{}'

dart run cockpit suite validate --workspace-id <workspaceId> --file suites/regression.yaml
dart run cockpit suite run --workspace-id <workspaceId> \
  --document-id <documentId> --suite-id regression \
  --idempotency-key regression-2026-07-24
dart run cockpit suite report --run-id <runId>
```

After worker termination, completed nodes stay complete, an active attempt
becomes `interrupted`, and the suite continues only when its retry policy allows
it. Persisted fixture and row bindings must resolve to the same healthy session;
Cockpit fails explicitly when that session can no longer be proven.

## MCP And Clients

Start the MCP stdio client with either command:

```bash
dart run cockpit serve-mcp
dart run cockpit_mcp
```

MCP is a thin authenticated Supervisor client. It does not construct drivers or
application services in-process. It exposes bounded roots, workspaces,
operations, targets, documents, cases, suites, runs, and artifacts. Official
and third-party GUI clients should use `/api/v2`, authenticated SSE run events,
public foundation DTOs, and digest-checked artifact downloads. Cockpit 2.0
intentionally ships no Flutter GUI and no embedded HTML dashboard; generated
HTML reports are portable run artifacts.

Agent host setup, including the OpenCode/OMP skill, is documented in the
[agent integration guide](docs/agent-integrations.md).

## Foreground CI

Foreground mode owns an isolated daemon, registers one checkout, submits a
`CockpitRunSubmission`, waits for terminal truth, and exits from the run outcome:

```bash
dart run cockpitd \
  --home=/tmp/cockpit-ci \
  --foreground-workspace=/workspace/app \
  --foreground-submission=/workspace/run-submission.json
```

## Documentation

Detailed package and protocol documentation:

- [`packages/cockpit/README.md`](packages/cockpit/README.md)
- [`packages/flutter_cockpit/README.md`](packages/flutter_cockpit/README.md)
- [`packages/cockpit_protocol/README.md`](packages/cockpit_protocol/README.md)
- [`docs/agent-integrations.md`](docs/agent-integrations.md)
- [`docs/architecture/cockpit-2.0-foundation-migration-inventory.md`](docs/architecture/cockpit-2.0-foundation-migration-inventory.md)
