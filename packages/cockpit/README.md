<p align="center">
  <img src="https://raw.githubusercontent.com/cockpit-dev/cockpit/main/assets/brand/cockpit-mark.svg" width="128" alt="Cockpit logo">
</p>

# cockpit

[![pub package](https://img.shields.io/pub/v/cockpit?logo=dart&label=pub.dev)](https://pub.dev/packages/cockpit)
[![License](https://img.shields.io/github/license/cockpit-dev/cockpit)](https://github.com/cockpit-dev/cockpit/blob/main/packages/cockpit/LICENSE)

[简体中文](https://github.com/cockpit-dev/cockpit/blob/main/packages/cockpit/README.zh-CN.md)

`cockpit` is the authenticated host client and headless execution package for
Cockpit 2.0. It contains the Supervisor daemon, isolated workspace worker,
resource-oriented CLI, and a thin MCP server. It does not bundle a GUI or a web
dashboard.

## Install

Cockpit requires Dart 3.8.0 or newer. Flutter workspaces require Flutter 3.32.0
or newer.

```yaml
dev_dependencies:
  cockpit: ^2.1.0
```

The package publishes four executables:

- `cockpit`: interactive resource commands
- `cockpit_mcp`: MCP stdio server
- `cockpitd`: Supervisor daemon and foreground CI runner
- `cockpit_worker`: private workspace worker process

### AI agent setup

Paste this prompt into the coding agent that should use Cockpit:

```text
Install Cockpit 2.1 for this coding agent from https://github.com/cockpit-dev/cockpit. Read docs/agent-integrations.md from that repository, detect the current agent host, and use its native adapter or project configuration when available. Otherwise install the complete skills/cockpit directory, including agents, assets, and references, into the host's user-level skill directory. Do not install only SKILL.md and do not leave links to a temporary clone or source checkout. Install the runtime with `dart pub global activate cockpit ^2.1.0`, ensure Dart's global executable directory is on PATH, and register the `cockpit_mcp` stdio server when the host supports MCP. Reload the host, verify that it discovers the cockpit skill, then run `cockpit help`, `cockpit daemon status`, and `cockpit target discover`. Report the exact installed paths, MCP configuration, and any unsupported host capability.
```

The repository includes host-native assets and a portable Agent Skill. See the
[agent integration guide](https://github.com/cockpit-dev/cockpit/blob/main/docs/agent-integrations.md)
for supported hosts and verification.

## Interactive Workspaces

The CLI starts the per-user Supervisor when an interactive API command needs
it. Register every project root and checkout explicitly:

```bash
dart run cockpit daemon start
dart run cockpit root add --path /work/projects --label projects
dart run cockpit workspace register --root-id <rootId> --path /work/projects/app-a
dart run cockpit workspace register --root-id <rootId> --path /work/projects/app-b
dart run cockpit workspace list
```

## CLI Output

The default `auto` format is compact semantic text for agent loops. Select
`--detail minimal|standard|full`, explicit lossless `--stdout-format json`, or
streaming `jsonl` for `run events`. `--output <file>` atomically writes complete
JSON and prints a bounded path/size/SHA-256 receipt. `artifact read` requires
`--output` and never emits binary or Base64 data.

Workspace commands accept `--workspace-id`. When it is omitted, Cockpit
resolves the current directory against registered active workspaces and
requires exactly one match. It never selects a global latest run, active
session, or unrelated checkout.

```bash
cd /work/projects/app-a
dart run cockpit operation list
dart run cockpit case list
```

`operation run` accepts typed JSON only and executes an advertised operation.
The descriptor controls scope and idempotency; there is no arbitrary URL or
HTTP method transport.

```bash
dart run cockpit operation run \
  --kind analyze.workspace \
  --workspace-id <workspaceId> \
  --input-json '{}'
```

## Authorization Policy

Dangerous operation kinds, operation safety effects, test safety effects,
production targets, and worker environment secrets require explicit authority.
The strict policy document is stored at `COCKPIT_HOME/authorization.json` and
is loaded once when the daemon starts.

```bash
dart run cockpit daemon policy validate --file authorization.json
dart run cockpit daemon policy apply --file authorization.json --restart
dart run cockpit daemon policy show
```

Use `dart run cockpit daemon start --yolo` (or `daemon restart --yolo`) for an
explicitly unrestricted local daemon. The mode lasts only for that daemon
process; starting without the flag returns to the persisted restricted policy.
The effective `authorizationMode` is exposed by daemon status and recorded in
attempt and suite reports.

Applying without `--restart` requires a stopped daemon. The default policy
denies dangerous operations and sensitive test effects; it does not authorize
production or unknown target environments.

Quarantined leases remain blocked by default. Use the advertised `lease.list`
operation to obtain the exact identity, then a `reset`-authorized
`lease.recover` request to retry verified cleanup. `forceRelease: true` is
limited to explicitly matched logical resources; forwarded ports can only be
released after verified cleanup.

## Canonical Case Replay

Validate a case document, then submit an indexed case using its canonical
document digest. Replays use explicit workspace, document, case, and
idempotency identities.

```bash
dart run cockpit case validate \
  --workspace-id <workspaceId> \
  --file example/cases/flutter_login.yaml

dart run cockpit case run \
  --workspace-id <workspaceId> \
  --document-id <documentId> \
  --case-id flutter-login \
  --idempotency-key ci-login-001 \
  --inputs-json '{}'

dart run cockpit run get --run-id <runId>
dart run cockpit run events --run-id <runId> --after-sequence 0
```

Run events use authenticated SSE with `afterSequence` and `Last-Event-ID`
resume support. Gap, terminal, and disconnect states are explicit. Artifacts
are read with expected size and SHA-256 values and are rejected when response
metadata or bytes differ.

## Suites And Black-Box Targets

Suites reuse indexed cases and add dependency DAGs, scoped fixtures, matrix
rows, concurrency, retries, fail-fast behavior, recovery, and aggregate
JSON/JUnit/HTML/Markdown reports.

Recovery persists node and attempt checkpoints plus exact fixture/row session
bindings. An attempt active at worker termination becomes `interrupted` and is
retried only when the suite policy allows it. A missing bound session is an
explicit environment failure, never a silent replacement.

The default `restartApp` isolation runs before each case's attempt fixtures.
Use `resetAppData` only when the selected driver advertises it, and choose
`sharedSession` explicitly only when state sharing is part of the suite design.

Fields in one locator are an intersection; `fallbacks` are ordered
alternatives. Native black-box targets additionally support state, hierarchy,
and spatial constraints when their inspected accessibility capability reports
them. A runtime rejects unsupported constraints instead of dropping them.
Text and label matching defaults to `exact`; use an explicit `matchMode` of
`contains`, typo-tolerant `fuzzy`, or `regex` for broader matching. A unique best candidate is selected
by route and match quality. Equal best candidates fail as `ambiguousTarget`;
use more signals, a relation, or 0-based `index` to select a list item.

```bash
dart run cockpit suite validate --file example/suites/regression.yaml
dart run cockpit suite run \
  --workspace-id <workspaceId> \
  --document-id <documentId> \
  --suite-id regression \
  --idempotency-key ci-regression-001
dart run cockpit suite report --run-id <runId> \
  --output-dir cockpit-report
```

Register installed native applications and other system-controlled surfaces as
workspace-owned targets. Put the stable platform app/package id on the target;
a case may override it in its target requirements when necessary. Android uses
ADB accessibility and device controls. iOS uses WebDriverAgent for
accessibility and interaction; assign a distinct WDA endpoint when multiple
devices or workspaces run concurrently.

An installed Flutter app or native/Flutter mixed stack uses `targetKind:
flutterApp`, a real `appId`, no entrypoint, and a `native`-plane case. It is
launched and driven through system accessibility with Flutter-aware duplicate
semantics normalization. Native screens and embedded platform views remain in
the same tree. Entrypoint-backed targets use the optional bridge and semantic
plane for development-only Widget, route, and runtime inspection.

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

dart run cockpit target register \
  --workspace-id <workspaceId> \
  --platform ios \
  --device-id <deviceUdid> \
  --target-kind nativeApp \
  --app-id com.example.app \
  --wda-url http://127.0.0.1:8101 \
  --environment test \
  --mode automation \
  --idempotency-key ios-target-001
```

Use `target list` and `target get` to recover registered resources, `target
launch` to activate one, and `target inspect` to read its live capabilities.
For a launched Flutter or mixed-stack target, the sanitized
`output.systemControl` profile in the `target.inspect` operation result is the
authority for its secondary native driver. Do not reconstruct it from
`app.get`, which intentionally redacts platform app and process identities.

Flutter target launches accept repeatable `--dart-define`,
`--dart-define-from-file`, `--flutter-arg`, and `--env KEY=VALUE` options plus a
`--launch-timeout-ms` budget up to 1800000. MCP and generic operations use the
same nested `launchConfiguration` fields: `dartDefines`,
`dartDefineFromFiles`, `flutterArgs`, and `environment`. Cockpit-managed launch
arguments cannot be overridden, and configuration values are not returned.
On Android and iOS, `environment` configures the Flutter build process; mobile
application processes do not inherit arbitrary host variables. Use Dart defines
or an application-owned configuration channel for values the app must read.

Operation descriptors publish `executionMode`, `defaultTimeoutMs`, and
`maximumTimeoutMs`. Synchronous operations block to a result and accept a
relative `--timeout-ms` or absolute `--deadline`. Case and suite submissions
are asynchronous durable jobs that return `runId`; their optional
`--timeout-ms` controls the overall run budget (case: 30 minutes by default,
6 hours maximum; suite: 2 hours by default, 24 hours maximum).

Case `setup`, main steps, `finally`, and suite fixtures can use `type: system`
with an advertised system action name and parameters. This keeps install,
activation, permissions, device state, and cleanup inside the same safety,
timeout, event, and report pipeline as UI actions.

A step-level `plane` may override the case default with `semantic`, `native`,
`visual`, or `coordinate`. The runtime otherwise derives the plane from the
action and locator. Flutter bridge sessions retain a system driver for the same
target, allowing semantic Widget steps and native, visual, or coordinate steps
to run in one case. Conditions and nested fragment/if/retry/loop steps inherit
the effective plane unless they override it.

Text control includes `copyText`, `eraseText`, and `pasteText`. `travel` applies
a bounded sequence of latitude/longitude points with per-route or per-point
delays. A visual locator names a workspace-confined template file; an
`assertScreenshot` names a workspace-confined baseline and emits the actual,
baseline, and deterministic diff files into the attempt evidence. Select each
baseline by a stable platform/device/viewport, pixel-ratio, and orientation
profile. Dimension mismatches are not auto-resized because they indicate a
wrong profile or a layout regression. Use suite
fixtures, case `setup`/`finally`, step `evidence`, and explicit recording
operations to express pre/post capture at the scope that owns it.

## Foreground CI

CI uses the same HTTP API and worker boundary as interactive mode. Foreground
mode owns the daemon lifetime, registers the supplied checkout, submits the
provided `CockpitRunSubmission` JSON, waits for terminal run truth, and exits
with a process status derived from the run outcome.

```bash
dart run cockpitd \
  --home=/tmp/cockpit-ci \
  --foreground-workspace=/workspace/app \
  --foreground-submission=/workspace/run-submission.json
```

The submission contains the canonical case source, idempotency key, inputs,
and required features. Foreground mode fills the registered `workspaceId`.

The repository release gate runs formatting, analysis, every package and
example test suite, publication dry-runs, and real Android, iOS, macOS, Linux,
web, and Windows regressions in parallel. Android and iOS must prove native
locator/action/assertion control rather than screenshot fallback. Publication requires every
job to reach a successful terminal state. Each platform regression proves a
business mutation, the complete Flutter gesture/text/keyboard/semantics command
surface, suite control flow, evidence, and the offline report bundle through
observable assertions. Wait for the complete matrix, then diagnose from its
reports, events, artifacts, and daemon logs in one pass.

## API Discovery

`CockpitDaemonLifecycleClient.ensure()` initializes the Cockpit home, validates
process identity, and returns the current discovery record. Production clients
then:

1. send its bearer token only to the discovered loopback endpoint;
2. read `GET /api/v2/server`;
3. negotiate API major/minor and required features;
4. decode public foundation DTOs strictly;
5. use only advertised `/api/v2` resources and operations.

The shared `CockpitSupervisorApiClient` implements this flow for the CLI and
MCP server, including 1 MiB response limits, bounded pagination, SSE resume,
structured API errors, and artifact integrity checks.

## MCP

Run the CLI command or the dedicated executable:

```bash
dart run cockpit serve-mcp
dart run cockpit_mcp
dart run cockpit serve-mcp --profile dart
```

```json
{
  "mcpServers": {
    "cockpit": {
      "command": "dart",
      "args": ["run", "cockpit_mcp"]
    }
  }
}
```

MCP exposes bounded resources for server, capabilities, roots, workspaces,
operations, targets, documents, cases, suites, runs, and artifacts. Its tools
cover root/workspace lifecycle, advertised operations, target lifecycle,
case/suite validation and execution, run get/cancel/events, artifact listing,
and verified artifact downloads to explicit files.
Every tool crosses the authenticated Supervisor HTTP boundary; the MCP process
does not construct application services.

Profiles keep tool injection intentional: `core` is the default, while `dart`,
`flutter`, `app`, `e2e`, and `all` add their capability domains. `flutter`
includes `dart`; `e2e` includes `app`. Use repeatable `--enable` and `--disable`
overrides for exact feature names or categories. The Dart profile provides
analyze, format, fix, test, LSP, pub, package URI/search, and project creation
without embedding or forwarding the official Dart MCP server.

## Client Boundary

The public `/api/v2` resources, SSE stream, foundation DTOs, and artifact
integrity contract are the only client boundary. A future Flutter GUI or
third-party SDK must use that protocol and must not link Supervisor application
services in-process.

Exported `cockpit-report/` directories are complete offline run artifacts, not
server UI. `suite report --output-dir cockpit-report` downloads the manifest
and every declared report artifact with verified size and SHA-256, then commits
the directory only after it is complete; the destination must not already
exist. `index.html` embeds its CSS, JavaScript, and canonical report
data while media uses bundle-relative paths. `report.json` is the stable
single-file rendering input, and root `manifest.json` covers every exported
file with ownership, size, media type, and SHA-256. Clients must preserve the
directory structure and verify the manifest; no HTML route in `cockpitd` is
required. Summary, Coverage, Executions, Evidence, Diagnostics, and
Environment/files are task views over one fact graph, not persona-specific
copies.

See [`../../docs/contracts`](../../docs/contracts) for protocol material and
[`example/cases`](example/cases) for canonical YAML and JSON cases.
