---
name: cockpit
description: Use when application development or black-box application E2E work must inspect, control, or prove live mobile, desktop, web, native, Flutter, or mixed-stack behavior with Cockpit 2.0.
---

# Cockpit 2.0

Use the authenticated Supervisor as the single control plane. Resolve explicit
workspace, target, and run identities; inspect capabilities before acting; and
judge results from terminal state plus evidence rather than command success.

This skill is self-contained. Resolve every linked resource relative to this
`SKILL.md`; never search for Cockpit's source repository. The installed
`cockpit` CLI/MCP, its `help` output, and live capability descriptors are the
runtime authorities.

All examples use the globally installed `cockpit` executable. Install it with
`dart pub global activate cockpit any` when absent. Inside a Dart/Flutter
project that declares `cockpit` as a development dependency, `dart run cockpit`
is equivalent. Never assume the Cockpit source repository is available.

## Flutter Is The Primary Development Path

When Flutter source is available, use the managed Flutter development session
as an independent first-class development path. It exposes the widget and
semantics tree, route and focus state, logs, framework/runtime errors, network
activity, rebuild signals, screenshots, hot reload/restart, and typed UI
commands while keeping production code untouched. This is not black-box E2E.
Do not register the app as `nativeApp` for normal Flutter implementation work.
Use the system/native plane only at real OS, plugin, WebView, or native-shell
boundaries; use a black-box target only for an installed production binary or
when source integration is unavailable.

Use this fast path for the common development loop:

```bash
cockpit daemon restart --yolo
cockpit root add --path /absolute/project-parent
cockpit workspace register --root-id <rootId> --path /absolute/checkout
cockpit workspace documents \
  --workspace-id <workspaceId> --kind source \
  --relative-path apps/mobile/cockpit/main.dart
cockpit target register \
  --workspace-id <workspaceId> --platform <platform> --device-id <deviceId> \
  --target-kind flutterApp --environment development --mode development \
  --entrypoint-document-id <documentId> --idempotency-key <uniqueKey>
cockpit target launch \
  --workspace-id <workspaceId> --target-id <targetId> --mode development \
  --dart-define API_URL=https://example.test \
  --dart-define-from-file config/development.json \
  --env BUILD_TOKEN=<authorizedValue> \
  --flutter-arg=--track-widget-creation \
  --launch-timeout-ms 900000 --idempotency-key <uniqueKey>
cockpit target inspect --target-id <targetId> --profile minimal
cockpit operation list --workspace-id <workspaceId> --kind <neededKind>
cockpit operation run --workspace-id <workspaceId> --kind ui.inspect \
  --input-json '{"sessionId":"<sessionId>","profile":"minimal"}'
cockpit operation run --workspace-id <workspaceId> --kind errors.read \
  --input-json '{"sessionId":"<sessionId>","maxErrors":8}'
cockpit operation run --workspace-id <workspaceId> --kind network.read \
  --input-json '{"sessionId":"<sessionId>","onlyFailures":true}'
cockpit operation run --workspace-id <workspaceId> --kind app.reload \
  --input-json '{"sessionId":"<sessionId>"}' \
  --idempotency-key <uniqueKey>
cockpit operation run \
  --workspace-id <workspaceId> --kind <advertisedKind> \
  --input-file /absolute/path/to/input.json --idempotency-key <uniqueKey>
cockpit target inspect --target-id <targetId> --profile minimal
```

Register the checkout or monorepo root once. Cockpit binds a Flutter target to
the nearest `pubspec.yaml` containing its indexed entrypoint, so
`apps/mobile/cockpit/main.dart` launches from `apps/mobile` without a second
workspace. Paths passed to `workspace documents` always remain relative to the
registered workspace root. Read [flutter.md](references/flutter.md) before
creating the development-only shell.

## Select The Smallest Workflow

| Goal | Workflow | Read |
| --- | --- | --- |
| Implement or debug quickly | inspect -> edit -> focused operation -> inspect | [dev.md](references/dev.md) |
| Add the optional Flutter semantic bridge | create a development-only shell, register its indexed entrypoint | [flutter.md](references/flutter.md) |
| Validate one user journey | author and run one `cockpit.test/v2` case | [e2e.md](references/e2e.md) |
| Regression, CI, or release | run a suite, verify the offline bundle | [e2e.md](references/e2e.md), [reporting.md](references/reporting.md) |
| A platform, driver, permission, or tool is unavailable | diagnose and repair the host before retrying | [environments.md](references/environments.md) |
| Exact command or contract is uncertain | inspect live help, then local protocol map | [protocol.md](references/protocol.md) |

Do not pay suite/report cost during every edit. Do not use a focused development
probe as release proof.

## Use YOLO For Local Development

When the user asks Cockpit to develop or validate a local `development` or
`test` target, use the YOLO daemon path by default unless the user requests a
restricted policy. This removes authorization round-trips from reloads, UI
control, screenshots, recordings, environment injection, and system actions.

```bash
cockpit daemon status
cockpit daemon start --yolo
# If a daemon is already running without YOLO:
cockpit daemon restart --yolo
```

Confirm `authorizationMode` from `daemon status`. YOLO belongs to that daemon
process only. Never silently extend it to a production/unknown target, shared
device, financial/destructive flow, communication with real users, or other
external side effect.

## Bootstrap Once Per Workspace

```bash
cockpit daemon status
cockpit root add --path /absolute/project/root
cockpit workspace register --root-id <rootId> --path /absolute/checkout
cockpit target discover
```

Read and reuse returned IDs. The current directory may infer a workspace only
when it belongs to exactly one active workspace. Each checkout has its own
workspace and worker state, so unrelated projects can run concurrently.

For installed black-box applications, register the discovered device and real
platform app identifier. Black-box control is non-invasive; it does not require
application source changes or a Cockpit SDK in the production app.

```bash
cockpit target register \
  --workspace-id <workspaceId> \
  --platform <discoveredPlatform> \
  --device-id <discoveredDeviceId> \
  --target-kind nativeApp \
  --environment test \
  --app-id <bundleOrApplicationId> \
  --idempotency-key <uniqueKey>
cockpit target launch \
  --workspace-id <workspaceId> \
  --target-id <targetId> \
  --idempotency-key <uniqueKey>
cockpit target inspect --target-id <targetId> --profile minimal
```

For Flutter source development, use the development shell and adapter by
default. Keep bridge wiring outside production `lib/`; production Flutter code must not import the bridge package.
A shell target is registered from its indexed entrypoint: resolve it with
`workspace documents`, then pass the returned ID to
`target register --entrypoint-document-id`. Follow [flutter.md](references/flutter.md)
for the complete setup.
A Flutter session retains a secondary system driver for native and OS
boundaries, but its primary development state and control come from the Flutter
adapter. An installed Flutter app remains controllable as a fully black-box
`nativeApp` when no bridge is present.

## Rapid Development Validation

Use this loop for active implementation:

`resolve -> baseline -> edit -> execute -> observe -> judge -> repeat`

1. Resolve the workspace, target, and advertised operations once.
2. Inspect a minimal baseline before the first mutation.
3. Make one coherent code change.
4. Run the smallest analysis, reload, action, or assertion that exercises it.
5. Inspect resulting UI/state and bounded runtime errors.
6. Capture a screenshot only for a visible claim and record only for motion or
   reproduction.
7. Keep the daemon and target alive and repeat without relaunching unless the
   target is unhealthy or the change requires a clean start.

Each cycle should answer one missing fact. Do not run a suite, generate a full
report, or open large artifacts during every edit. Follow
[dev.md](references/dev.md) for common UI, route, network,
black-box, mixed-stack, locator, timeout, and recovery workflows.

## Inspect Before Acting

```bash
cockpit operation list --workspace-id <workspaceId>
cockpit operation list --workspace-id <workspaceId> --kind <neededKind>
cockpit target inspect --target-id <targetId> --profile minimal
```

Treat each advertised operation's input contract, `executionMode`,
`defaultTimeoutMs`, and `maximumTimeoutMs` as authoritative. Synchronous
operations block to a result. Job operations return a durable `runId`.
Use either `--timeout-ms` or `--deadline` for a synchronous operation, never
both. Give each authored step its own `timeoutMs` when its cost differs from
the case default.

Run focused development actions with typed file input:

```bash
cockpit operation run \
  --workspace-id <workspaceId> \
  --kind <advertisedKind> \
  --input-file /absolute/path/to/input.json \
  --idempotency-key <uniqueKey>
```

After a mutation, inspect the resulting UI/state/errors. After timeout or
transport loss, read state before retrying non-idempotent work.

## Author And Run E2E

Copy and adapt a local template; do not execute a template unchanged:

- [black-box-login.case.yaml](assets/templates/e2e/cases/black-box-login.case.yaml)
- [black-box-settings.case.yaml](assets/templates/e2e/cases/black-box-settings.case.yaml)
- [flutter-mixed-stack.case.yaml](assets/templates/e2e/cases/flutter-mixed-stack.case.yaml)
- [regression.suite.yaml](assets/templates/e2e/suites/regression.suite.yaml)

Use the bundled [cockpit.test.v2.schema.json](references/cockpit.test.v2.schema.json)
for exact fields. Keep case and suite files inside the registered workspace,
validate them, list them to refresh the document index, and then run by the
reported authored identity.

```bash
cockpit case validate --file cockpit/e2e/cases/login.case.yaml --format yaml
cockpit suite validate --file cockpit/e2e/suites/regression.suite.yaml --format yaml
cockpit case list --workspace-id <workspaceId>
cockpit suite list --workspace-id <workspaceId>
cockpit case run \
  --workspace-id <workspaceId> \
  --case-id <caseId> \
  --target-id <targetId> \
  --idempotency-key <uniqueKey> \
  --timeout-ms <overallCaseBudget>
cockpit suite run \
  --workspace-id <workspaceId> \
  --suite-id <suiteId> \
  --target-id <targetId> \
  --idempotency-key <uniqueKey> \
  --timeout-ms <overallSuiteBudget>
cockpit run events --run-id <runId> --after-sequence 0
cockpit run get --run-id <runId>
cockpit suite report --run-id <runId> --output-dir cockpit-report
```

Use semantic/native/visual/coordinate planes only when advertised. Locator
signals in one locator are conjunctive. Prefer stable IDs or labels, add
ordered `fallbacks` for alternate representations, and use 0-based `index`
only after stronger signals still match a list. Exact text is the default;
select `contains`, `fuzzy`, or `regex` deliberately.

Compose lifecycle behavior with suite fixtures, case `setup`/`finally`, step
`evidence`, and explicit recording boundaries. Use `if`, bounded `retry`,
bounded `loop`, and `call` fragments for flow control. Do not invent client-only
pre/post hooks that cannot appear in the canonical report.

## Output And Evidence

CLI stdout defaults to AI semantic text at `--detail minimal`. Keep this for
normal loops: it emits one copy of each identity/state, compact collection
rows, decision-critical counts, failures, and the next action. Use
`--detail standard` only for diagnostic context and `--detail full` only when
the complete object is required. The same levels apply to
`--stdout-format json`; JSON changes encoding, not information density. Use
`--detail full --stdout-format json --output <file>` for a complete structured
response without putting it in terminal context. Binary artifacts always go
to files and are never printed or expanded as Base64.

A pass requires terminal run state, required assertions, no disqualifying
runtime errors, and readable required evidence. For suites, export the whole
offline directory with `suite report --output-dir <newDirectory>`; the CLI
downloads manifest-declared files, verifies their size and SHA-256, and leaves
no partial destination on failure. Use `summary.md` for a bounded
handoff, `report.json` as the complete rendering fact graph, `index.html` for
offline task-focused exploration, and `junit.xml` for CI interchange.

## Authorization And Recovery

Inspect policy with `daemon policy show`. Production/unknown targets,
dangerous operations, safety effects, and secret names require policy
authority. Use the local development YOLO rule above only within its stated
boundary. Confirm `authorizationMode` in daemon status and the report.

Resume run events by sequence and reuse the original idempotency key. For
quarantined resources, read exact identities with the advertised `lease.list`
operation and use policy-authorized `lease.recover`; never guess or blindly
force release resources.

## Completion Rules

- A visible claim needs a current screenshot; motion or reproduction needs a
  recording when that capability is available and required.
- A business flow needs an observable assertion after its mutation.
- Unsupported capability is blocked/unavailable, never a simulated pass.
- A release requires the complete quality gate and every supported platform
  regression, not one local run or one passing device.
- Wait for an entire CI matrix before triage; diagnose terminal reports,
  events, artifacts, and logs together.
