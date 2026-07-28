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
  cancellation, artifacts, and complete offline regression report bundles;
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

For an explicitly unrestricted local session, start the Supervisor with
`dart run cockpit daemon start --yolo` (or `daemon restart --yolo`). YOLO
applies only to that daemon process; a start or restart without the flag uses
the persisted restricted policy. `daemon status`, attempt manifests, and suite
`report.json` record the effective `authorizationMode`.

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

For an installed Flutter app or a native app embedding Flutter, register
`targetKind: flutterApp` with an `appId` and no entrypoint, then author the case
on the `native` plane. Cockpit launches it through system control and drives the
complete native accessibility tree without an application dependency. The
Flutter-aware resolver locally collapses duplicate ancestor semantics and
prefers actionable matches while leaving native screens, platform views,
WebViews, and distinct list rows intact. Use an entrypoint-backed Flutter target
and the `semantic` plane only when the optional development bridge is required.

Flutter targets accept a structured launch configuration across CLI, MCP, and
`operation run`. Cockpit owns the entrypoint, device, mode, flavor, and remote
control flags; callers can supply repeatable dart defines, define files,
additional safe Flutter arguments, process environment values, and a launch
budget up to 30 minutes:

```bash
dart run cockpit target launch \
  --workspace-id <workspaceId> \
  --target-id <flutterTargetId> \
  --dart-define API_URL=https://api.example.test \
  --dart-define-from-file config/staging.json \
  --env LOG_LEVEL=debug \
  --flutter-arg=--track-widget-creation \
  --launch-timeout-ms 1800000 \
  --idempotency-key flutter-launch-001
```

The equivalent operation input uses a `launchConfiguration` object with
`dartDefines`, `dartDefineFromFiles`, `flutterArgs`, and `environment`. Launch
configuration values are not returned in operation output. Do not pass Flutter
launch fields to installed black-box targets.

Every advertised operation includes `executionMode`, `defaultTimeoutMs`, and
`maximumTimeoutMs`. Synchronous operations block until their result and accept
`operation run --timeout-ms <value>` or an absolute `--deadline` (not both).
Case and suite runs are durable jobs: submission returns a `runId` immediately,
then clients consume events and the terminal report. `case run --timeout-ms`
defaults to 30 minutes and allows up to 6 hours; `suite run --timeout-ms`
defaults to 2 hours and allows up to 24 hours. Step and cleanup timeouts remain
independent inner budgets.

Each step may explicitly select `semantic`, `native`, `visual`, or `coordinate`
with `plane`. Without an override, Cockpit routes screenshot assertions to the
visual plane, system and location-travel actions to native control, visual and
coordinate locators to their matching planes, and native-only constraints to
native accessibility. Other steps inherit the case plane. An entrypoint-backed
Flutter session keeps the semantic driver and a secondary system driver for the
same app/device, so one case can inspect Widgets and then cross a native screen,
platform view, permission dialog, or visual-only surface without changing the
application under test.
The authoritative secondary capability profile is the sanitized
`target.inspect` operation result at `output.systemControl`; clients must not
reconstruct it from `app.get`, whose platform app and process identities are
intentionally redacted.

The shared action vocabulary includes `copyText`, `eraseText`, `pasteText`, and
bounded `travel` routes in addition to gestures, editing, keyboard, wait,
assertion, capture, recording, and system actions. Visual locators use a
workspace-confined image file and an optional similarity threshold.
`assertScreenshot` compares a live capture with a workspace-confined baseline
and records actual, baseline, and diff images as offline artifacts; image bytes
never enter terminal output. Baselines must be selected by a stable visual
profile such as platform, device or viewport, pixel ratio, and orientation.
A dimension mismatch is a profile mismatch or layout regression; Cockpit does
not resize either image to manufacture a comparison.

## Cases And Suites

Cases and suites use `schemaVersion: cockpit.test/v2`. Validate documents before
submitting them, and use stable idempotency keys for replay:

```bash
dart run cockpit case validate --workspace-id <workspaceId> --file cases/login.yaml
dart run cockpit case run --workspace-id <workspaceId> \
  --document-id <documentId> --case-id login \
  --idempotency-key login-2026-07-24 --inputs-json '{}' \
  --timeout-ms 1800000

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

Lifecycle composition uses the smallest existing scope: suite fixtures for
campaign or attempt setup/teardown, case `setup`/`finally` for case ownership,
step `evidence` for before/after/failure capture policy, and explicit
`startRecording`/`stopRecording` steps around the exact interval that needs
video. `if`, bounded `retry`/`loop`, and fragments compose normally inside
these scopes, so a second generic pre/post hook model is unnecessary.

Every finalized suite exports one portable `cockpit-report/` directory. Open
`index.html` offline to move from release summary and coverage through
executions, evidence, diagnostics, and environment/files. Search, filters,
deep links, and responsive/print layouts work without a server or network.
`report.json` is the canonical single-file fact graph containing suite
and case definitions, attempts, detailed steps, assertions, and evidence
references. `manifest.json` declares every other file with semantic ownership,
size, media type, and SHA-256. `summary.md`, `junit.xml`, `run/events.jsonl`,
semantic case directories, screenshots, recordings, logs, and snapshots are
derived portable views of the same facts. Clients must preserve relative paths
and verify the manifest before trusting any file.

## MCP And Clients

Start the MCP stdio client with either command:

```bash
dart run cockpit serve-mcp
dart run cockpit_mcp
dart run cockpit serve-mcp --profile dart
```

MCP is a thin authenticated Supervisor client. It does not construct drivers or
application services in-process. It exposes bounded roots, workspaces,
operations, targets, documents, cases, suites, runs, and artifacts. Official
and third-party GUI clients should use `/api/v2`, authenticated SSE run events,
public foundation DTOs, and digest-checked artifact downloads. Cockpit 2.0
intentionally ships no Flutter GUI and no embedded HTML dashboard; generated
HTML reports are portable run artifacts.

The default `core` profile keeps the control plane small. Optional profiles are
`dart`, `flutter` (`dart` plus Flutter), `app`, `e2e` (`app` plus E2E), and
`all`; `--enable <name>` and `--disable <name>` provide exact overrides. The
Dart profile supplies analyze, format, fix, test, LSP, pub, package URI/search,
and project creation tools through the same workspace-isolated Supervisor. It
is a complete Cockpit-side alternative when the official Dart MCP server is not
installed; Cockpit neither embeds nor proxies that server.

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

## Release Gate

`.github/workflows/example-e2e.yml` is the required Cockpit 2.0 publication
gate. Parallel jobs verify formatting, static analysis, repository contracts,
every package and example test suite, dry-run publication for all three public
packages, and real Android, iOS, macOS, Linux, web, and Windows regressions.
Android and iOS must prove native locator/action/assertion control; screenshot
fallback is not sufficient for either core platform. Each platform runs a complex suite
covering fixtures, setup/finally, fragment calls, branches, bounded retry and
loop control, per-step timeouts, matrix rows, bounded concurrency, a complete
create/read/delete business flow, every Flutter gesture/text/keyboard/semantics
command, screenshots, capability-aware recording, and offline bundle integrity.
Each command is accepted only when its visible UI effect is asserted in the
canonical report. A release is eligible only when the quality job and every
platform job complete successfully with terminal reports and verified
artifacts. Wait for the whole matrix before diagnosing failures; use the
uploaded report, event stream, artifacts, and daemon log as authority.

## Documentation

Detailed package and protocol documentation:

- [`packages/cockpit/README.md`](packages/cockpit/README.md)
- [`packages/flutter_cockpit/README.md`](packages/flutter_cockpit/README.md)
- [`packages/cockpit_protocol/README.md`](packages/cockpit_protocol/README.md)
- [`docs/agent-integrations.md`](docs/agent-integrations.md)
- [`skills/cockpit/references/environments.md`](skills/cockpit/references/environments.md)
- [`docs/architecture/cockpit-2.0-foundation-migration-inventory.md`](docs/architecture/cockpit-2.0-foundation-migration-inventory.md)
