<div align="center">
  <a href="https://github.com/cockpit-dev/cockpit">
    <img src="https://raw.githubusercontent.com/cockpit-dev/cockpit/main/assets/brand/cockpit-mark.svg" width="128" alt="Cockpit logo">
  </a>
  <h1>cockpit</h1>
  <p><strong>Flutter development control plane and headless black-box E2E runner.</strong></p>
  <p>
    <a href="https://pub.dev/packages/cockpit"><img src="https://img.shields.io/pub/v/cockpit?logo=dart&amp;label=pub.dev" alt="cockpit version on pub.dev"></a>
    <a href="https://pub.dev/packages/cockpit/score"><img src="https://img.shields.io/pub/points/cockpit?logo=dart" alt="cockpit pub points"></a>
    <a href="https://pub.dev/packages/cockpit/score"><img src="https://img.shields.io/pub/likes/cockpit?logo=dart" alt="cockpit likes on pub.dev"></a>
    <a href="https://pub.dev/packages/cockpit/score"><img src="https://img.shields.io/pub/popularity/cockpit?logo=dart" alt="cockpit popularity on pub.dev"></a>
  </p>
  <p>
    <a href="https://github.com/cockpit-dev/cockpit/actions/workflows/example-e2e.yml"><img src="https://github.com/cockpit-dev/cockpit/actions/workflows/example-e2e.yml/badge.svg?branch=main" alt="CI"></a>
    <a href="https://dart.dev"><img src="https://img.shields.io/badge/Dart-%E2%89%A53.8.0-0175C2?logo=dart&amp;logoColor=white" alt="Dart 3.8.0 or newer"></a>
    <a href="https://github.com/cockpit-dev/cockpit#black-box-targets"><img src="https://img.shields.io/badge/platforms-6%20supported-2E7D32" alt="Android, iOS, macOS, Linux, Windows, and web"></a>
    <a href="https://github.com/cockpit-dev/cockpit/blob/main/packages/cockpit/LICENSE"><img src="https://img.shields.io/github/license/cockpit-dev/cockpit" alt="MIT license"></a>
  </p>
  <p><a href="https://github.com/cockpit-dev/cockpit/blob/main/packages/cockpit/README.md">English</a> · <a href="https://github.com/cockpit-dev/cockpit/blob/main/packages/cockpit/README.zh-CN.md">简体中文</a></p>
</div>

`cockpit` is the authenticated host control plane for Flutter/Dart development
and headless black-box E2E. It contains the Supervisor daemon, isolated
workspace worker, resource-oriented CLI, MCP server, and public REST/SSE API.

## Install

Cockpit requires Dart 3.8.0 or newer. Flutter workspaces require Flutter 3.32.0
or newer.

```bash
dart pub global activate cockpit any
cockpit --help
```

Run `cockpit update` to update the CLI and running Supervisor to the latest
verified Pub release while preserving local authorization and durable state.

The package publishes four executables:

- `cockpit`: interactive resource commands
- `cockpit_mcp`: MCP stdio server
- `cockpitd`: Supervisor daemon and foreground CI runner
- `cockpit_worker`: private workspace worker process

### Install For AI Agents

Preferred: ask the current AI host to install the CLI, complete Skill, native
adapter, and MCP surface. Copy this prompt:

```text
First fetch and read the complete Cockpit installation guide with `curl -fsSL https://raw.githubusercontent.com/cockpit-dev/cockpit/main/skills/cockpit/INSTALL.md`, then install or update the CLI, complete cockpit Skill, native adapter, and cockpit_mcp for the current AI host exactly as that guide directs.
```

Complete host-specific installation and verification instructions live in
[`skills/cockpit/INSTALL.md`](https://github.com/cockpit-dev/cockpit/blob/main/skills/cockpit/INSTALL.md).
Native adapter and MCP details are documented in the
[agent integration guide](https://github.com/cockpit-dev/cockpit/blob/main/docs/agent-integrations.md).

## Flutter Fast Path

Run from inside the intended Flutter project. From a monorepo common ancestor,
pass the entrypoint explicitly. Cockpit owns discovery, the Supervisor,
workspace/target registration, the app process, ports, and bridge state.
Before the first start, the project must already contain the development-only
`cockpit/main.dart` bridge shell described in the
[`flutter_cockpit` integration guide](https://pub.dev/packages/flutter_cockpit#recommended-integration):

```bash
cockpit dev start
cockpit dev status
cockpit dev inspect "Save"
cockpit dev tree
cockpit dev tap "Save"
cockpit dev open "myapp://tasks/42"
cockpit dev wait
cockpit dev screenshot
cockpit dev recover
cockpit dev reload
cockpit dev diagnose --view more
```

Omit the entrypoint and platform when they are inferable. Cockpit stores one
active short lowercase base-36 handle per canonical Flutter project, guarded
by checkout identity; the same project may keep separate platform/target
handles. Use `cockpit session list`, `cockpit session show HANDLE`, and
`cockpit dev use HANDLE` when identity needs confirmation or selection.
Explicit `--session` targets one command without changing the saved active
handle; a returned recovery `next` keeps that exact handle. `dev` starts its
local Supervisor in process-scoped yolo mode. Cockpit does not read a keychain
or secret store, and `--env` values are process-only.

Flutter inspection walks mounted Elements and RenderObjects without requiring
developer-authored `Semantics`. Use `dev inspect QUERY` for a bounded search;
it returns a directly executable `sel`, for example `#save` or
`Dialog >> FilledButton["Continue"]`. Conditions intersect, and ambiguous targets
fail instead of guessing. Without a query, `dev inspect` returns the mounted
control surface in visual order with compact live `:REF` selectors plus `can`,
`state`, and `value`. Copy a live ref directly into its advertised command and
re-inspect after the control surface changes; keep targeted stable selectors in
durable cases and suites. Disabled and selected controls remain visible without
exposing obscured values. Interaction ownership stays explicit: merged ancestor
`Semantics` never makes passive descendants actionable, and descendants below
`IgnorePointer(ignoring: true)` or `AbsorbPointer(absorbing: true)` advertise no
mutation actions. When
one actionable outer row delegates selection to exactly one blocked control,
the outer target carries that control's state; multiple delegated controls
leave state unresolved instead of guessing. `dev tree` returns a compact
selector index; use
an explicit source-derived selector such as
`CompanyButton >> Text["Save"]` directly with `dev tap`, `dev hold`, or
`dev double` for a unique visible custom control that the bounded control surface
cannot classify. Cockpit uses its known actionable owner or a hit-tested gesture.
Use
`dev tree --view more` or `dev tree --view full` only for structural context.
Both structural views write the tree to an artifact and print only its verified path.
Use `dev open URI` to test a custom deep link, Android app link, iOS universal
link, or HTTP(S) URL through the selected target, then verify the expected route
or anchor with `dev wait` and `dev inspect`.
Use `dev recover` only after a system capture proves a native blocker. It safely
does nothing when the selected app already has focus.

`dev scroll TARGET` mounts lazy targets, ranks scroll containers, searches the
requested initial direction before reversing at its boundary, and reveals nested
ancestors from inner to outer. Default `nearest` placement verifies the hit test
and can scroll a target away from a fixed Flutter overlay. A successful
`dev reload` starts a new runtime-diagnostic generation, so previous errors no
longer fail current evidence while new errors remain reportable.

## Explicit Resource Workspaces

`cockpit dev start` automatically registers its canonical Flutter project, so
routine development never needs these commands. The CLI also starts the
per-user Supervisor when required.

For lower-level API, black-box, or resource workflows that do not begin with a
development session, register each checkout once:

```bash
cockpit daemon start
cockpit root add --path /work/projects --label projects
cockpit workspace register --root-id <rootId> --path /work/projects/app-a
cockpit workspace register --root-id <rootId> --path /work/projects/app-b
cockpit workspace list
```

## CLI Output

The default is brief canonical LON. Use `--view more` for additional context and
`--view full` for the complete response. `--format` supports
`lon|json|yaml|jsonl|path|none`; JSON is intended for `jq`, JSON-only consumers,
and wire inspection. `--output` and `artifact read` return the verified output
path.

Workspace commands accept `--workspace-id`. When it is omitted, Cockpit
resolves the current directory against registered active workspaces and
requires exactly one match. It never selects a global latest run, active
session, or unrelated checkout. From a common ancestor with several Flutter
projects, `op list --session HANDLE` resolves the exact session's workspace
without requiring a long workspace ID.

```bash
cd /work/projects/app-a
cockpit op list
cockpit case list
cockpit op list --kind system.action --session 2
```

`op run` accepts typed LON, JSON, or YAML and executes an advertised operation.
The descriptor controls scope, idempotency, and transport. Its advertised timeout
is the default; pass `--timeout`
only for a deliberate override within the advertised maximum.

```bash
cockpit op run analyze.workspace \
  --workspace-id <workspaceId>
```

## Authorization Policy

Dangerous operation kinds, operation safety effects, test safety effects, and
production targets require explicit authority.
The strict policy document is stored at `COCKPIT_HOME/authorization.json` and
is loaded once when the daemon starts.

```bash
cockpit daemon policy validate --file authorization.json
cockpit daemon policy apply --file authorization.json --restart
cockpit daemon policy show
```

Use `cockpit daemon start --yolo` (or `daemon restart --yolo`) for an
explicitly unrestricted local daemon. The mode lasts only for that daemon
process. An unflagged start or restart preserves a healthy running daemon's
current mode; when no daemon is running, it starts with the persisted restricted
policy. Stop first when an explicit return to restricted mode is required. The
effective `auth` is exposed by daemon status and recorded in attempt and suite
reports.

Applying without `--restart` requires a stopped daemon. The default policy
denies dangerous operations and sensitive test effects; it does not authorize
production or unknown target environments.

Quarantined leases remain blocked by default. Use the advertised `lease.list`
operation to obtain the exact identity, then a `reset`-authorized
`lease.recover` request to retry verified cleanup. `forceRelease: true` is
limited to explicitly matched logical resources; forwarded ports can only be
released after verified cleanup.

## Canonical Case Replay

Validate a case document. Run the local file directly while developing it, or
submit an indexed case using its canonical document digest for durable shared
and CI replay.

```bash
cockpit case validate \
  --workspace-id <workspaceId> \
  --file example/cases/flutter_login.yaml

cockpit case run \
  --file example/cases/flutter_login.yaml \
  --idempotency-key local-login-001

cockpit case run \
  --workspace-id <workspaceId> \
  --document-id <documentId> \
  --case-id flutter-login \
  --idempotency-key ci-login-001

cockpit run get --run-id <runId>
cockpit run events --run-id <runId> --after-sequence 0
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
alternatives. Flutter `dev inspect` emits the shortest unique stable selector,
preferring identity or exact text, then ancestor scope, path, and finally a
stable ordered index. Native black-box targets additionally support state, hierarchy,
and spatial constraints when their inspected accessibility capability reports
them. Unsupported constraints fail explicitly.
Text and label matching defaults to `exact`; use an explicit `matchMode` of
`contains`, typo-tolerant `fuzzy`, or `regex` for broader matching. A unique best candidate is selected
by route and match quality. Equal best candidates fail as `ambiguousTarget`;
use more signals, a relation, or 0-based `index` to select a list item.

```bash
cockpit suite validate --file example/suites/regression.yaml
cockpit suite run \
  --file example/suites/regression.yaml \
  --idempotency-key local-regression-001
cockpit suite run \
  --workspace-id <workspaceId> \
  --document-id <documentId> \
  --suite-id regression \
  --idempotency-key ci-regression-001
cockpit suite report --run-id <runId> \
  --output-dir cockpit-report
```

The local `--file` and indexed `--suite-id` forms are mutually exclusive.

Register installed native applications and other system-controlled surfaces as
workspace-owned targets. Put the stable platform app/package id on the target;
a case may override it in its target requirements when necessary. Android uses
ADB accessibility and device controls. iOS uses WebDriverAgent for
accessibility and interaction; assign a distinct WDA endpoint when multiple
devices or workspaces run concurrently.
Linux tree inspection uses the active AT-SPI accessibility bus. Generic
Chromium pages use a target-scoped CDP endpoint; Flutter Web development keeps
using its in-app Flutter tree.

An installed Flutter app or native/Flutter mixed stack uses `targetKind:
flutterApp`, a real `appId`, no entrypoint, and a `native`-plane case. It is
launched and driven through system accessibility with Flutter-aware duplicate
semantics normalization. Native screens and embedded platform views remain in
the same tree. Entrypoint-backed targets use the optional bridge and semantic
plane for development-only Widget, route, and runtime inspection.

```bash
cockpit target register \
  --workspace-id <workspaceId> \
  --platform android \
  --device-id emulator-5554 \
  --target-kind nativeApp \
  --app-id com.example.app \
  --environment test \
  --mode automation \
  --idempotency-key android-target-001

cockpit target register \
  --workspace-id <workspaceId> \
  --platform ios \
  --device-id <deviceUdid> \
  --target-kind nativeApp \
  --app-id com.example.app \
  --wda-url http://127.0.0.1:8101 \
  --environment test \
  --mode automation \
  --idempotency-key ios-target-001

cockpit target register \
  --workspace-id <workspaceId> \
  --platform web \
  --device-id chrome \
  --target-kind browserPage \
  --cdp-url ws://127.0.0.1:<port>/devtools/page/<pageId> \
  --environment test \
  --mode automation \
  --idempotency-key web-target-001
```

Use `target list` and `target get` to recover registered resources, `target
launch` to activate one, and `target inspect` to read its live capabilities.
For a launched Flutter or mixed-stack target, `cockpit target inspect` returns
the secondary native driver profile as `system`.

Flutter target launches accept repeatable `--dart-define`,
`--dart-define-from-file`, `--flutter-arg`, and `--env KEY=VALUE` options plus a
`--timeout` budget (20 minutes by default, 31 minutes maximum). MCP and generic
operations use the
same nested `launchConfiguration` fields: `dartDefines`,
`dartDefineFromFiles`, `flutterArgs`, and `environment`. Cockpit-managed launch
arguments cannot be overridden, and configuration values are not returned.
On Android and iOS, `environment` configures the Flutter build process; mobile
application processes do not inherit arbitrary host variables. Use Dart defines
or an application-owned configuration channel for values the app must read.

Operation descriptors publish `executionMode`, `defaultTimeoutMs`, and
`maximumTimeoutMs`. Synchronous operations block to a result and accept a
single `--timeout` duration such as `90s` or `20m`. Case and suite submissions
are asynchronous durable jobs that return `runId`; `--timeout` controls the
overall run budget (case: 30 minutes by default,
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
profile. Dimension mismatches indicate a wrong profile or a layout regression.
Use suite
fixtures, case `setup`/`finally`, step `evidence`, and explicit recording
operations to express pre/post capture at the scope that owns it.

## Foreground CI

CI uses the same HTTP API and worker boundary as interactive mode. Foreground
mode owns the daemon lifetime, registers the supplied checkout, submits the
provided `CockpitRunSubmission` JSON, waits for terminal run truth, and exits
with a process status derived from the run outcome.

```bash
cockpitd \
  --home=/tmp/cockpit-ci \
  --foreground-workspace=/workspace/app \
  --foreground-submission=/workspace/run-submission.json
```

The submission contains the canonical case source, idempotency key, inputs,
and required features. Foreground mode fills the registered `workspaceId`.

## API Discovery

`CockpitDaemonLifecycleClient.ensure()` initializes the Cockpit home, validates
process identity, and returns the current discovery record. Production clients
then:

1. send its bearer token only to the discovered loopback endpoint;
2. read `GET /api/v2/server`;
3. negotiate API major/minor and required features;
4. decode public foundation DTOs strictly;
5. use only advertised `/api/v2` resources and operations.

The generic operation-control sequence uses:

```text
GET  /api/v2/server
GET  /api/v2/capabilities
GET  /api/v2/operations
GET  /api/v2/workspaces/{workspaceId}/operations
GET  /api/v2/operations/schema
POST /api/v2/operations
POST /api/v2/workspaces/{workspaceId}/operations
GET  /api/v2/runs/{runId}/events
```

REST owns commands and resources. Authenticated SSE owns durable resumable run
events. WebSocket is reserved for the internal Flutter Web bridge and is not a
public client command transport. The operation invocation envelope owns scope,
idempotency, and deadline; `input` contains only fields from the selected live
request schema.

The shared `CockpitSupervisorApiClient` implements this flow for the CLI and
MCP server, including 1 MiB response limits, bounded pagination, SSE resume,
structured API errors, and artifact integrity checks.

## MCP

Run the CLI command or the dedicated executable:

```bash
cockpit serve-mcp
cockpit_mcp
cockpit serve-mcp --profile dart
```

```json
{
  "mcpServers": {
    "cockpit": {
      "command": "cockpit_mcp",
      "args": []
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
integrity contract are the only client boundary. Cockpit Console and
third-party SDKs use that protocol and must not link Supervisor application
services in-process.

Exported `cockpit-report/` directories are complete offline run artifacts, not
server UI. `suite report --output-dir cockpit-report` downloads the manifest
and every declared report artifact with verified size and SHA-256, then commits
the directory only after it is complete. The destination may be absent or an
existing real empty directory. `index.html` embeds its CSS, JavaScript, and
canonical report data while media uses bundle-relative paths. `report.json` is the stable
single-file rendering input, and root `manifest.json` covers every exported
file with ownership, size, media type, and SHA-256. Clients must preserve the
directory structure and verify the manifest; no HTML route in `cockpitd` is
required. Summary, Coverage, Executions, Evidence, Diagnostics, and
Environment/files are task views over one fact graph, not persona-specific
copies.

See [`../../docs/contracts`](../../docs/contracts) for protocol material and
[`example/cases`](example/cases) for canonical YAML and JSON cases.
