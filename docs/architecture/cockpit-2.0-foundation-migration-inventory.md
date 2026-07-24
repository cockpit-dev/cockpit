# Cockpit 2.0 Architecture And Release Inventory

## Scope

This document records the final 2.0 ownership model and release gates. It is no
longer a migration task list. Cockpit 2.0 has no runtime compatibility layer for
the 1.x host workflow API.

## Package Graph

```text
cockpit -> cockpit_protocol
flutter_cockpit -> cockpit_protocol
```

`cockpit_protocol` is platform-neutral. `cockpit` is a pure Dart host package.
`flutter_cockpit` is the optional Flutter in-app bridge. The retired
`flutter_cockpit_protocol` package is not part of the production graph.

Published executables from `cockpit`:

| Executable | Role |
| --- | --- |
| `cockpit` | resource-oriented CLI client |
| `cockpit_mcp` | MCP stdio client |
| `cockpitd` | authenticated per-user Supervisor and foreground CI host |
| `cockpit_worker` | private workspace worker process |

## Ownership

| Owner | Responsibilities |
| --- | --- |
| protocol | public DTOs, test DSL, foundation schema, OpenAPI, strict codecs |
| Supervisor | daemon discovery/authentication, authorization policy, roots, workspaces, admissions, leases, ports, worker lifecycle, run/event projections, artifacts, public HTTP/SSE |
| root operation | project creation and package search |
| workspace worker | documents, targets, apps, sessions, analysis, formatting, tests, LSP, package reads, shell/system control, capture, recording, case/suite execution, worker event truth |
| Flutter bridge | semantic UI, route/runtime observation, remote Flutter automation, app-side capture and recording |

No resource has two authoritative owners. Every workspace operation carries a
`workspaceId`; run, target, session, lease, and artifact references are checked
against that authority.

## Runtime Boundaries

Clients use only the loopback `/api/v2` HTTP API, authenticated SSE, and public
foundation DTOs. CLI and MCP are thin clients and do not construct application
services or platform drivers. A future official Flutter GUI or third-party
client uses the same protocol.

The daemon owns one worker pool keyed by workspace and engine version. This
supports concurrent projects without global latest-project or latest-session
state. Worker process environments are minimized; only explicitly allowed
environment secret names are forwarded.

The old embedded DevTools dashboard and browser assets are deleted. There is no
HTML route in `cockpitd`. Generated suite `report.html` files are immutable,
portable artifacts rather than a server UI.

## Execution Model

`cockpit.test/v2` is the only production case/suite format. YAML and JSON decode
to the same strict protocol model.

Case execution includes:

- typed inputs, variables, secrets, conditions, and locators;
- setup, main steps, and guaranteed cleanup;
- semantic/native/system/visual/coordinate lowering;
- safety preflight and dispatch authorization;
- evidence, cancellation, immutable attempt bundles, and structured failures.

Suite execution adds:

- dependency DAGs and matrix expansion;
- suite and case-attempt fixtures;
- `sharedSession`, `restartApp`, and `resetAppData` isolation;
- bounded concurrency, retries, fail-fast, and always-run teardown;
- JSON, JUnit, HTML, and AI summary reports;
- durable node, attempt, session-affinity, event, and artifact state.

On worker recovery, completed nodes are reused. An active attempt becomes an
`interrupted` attempt and enters the declared retry policy. Persisted fixture
and row session bindings must resolve to the same healthy resource. Cockpit
does not replay a completed fixture or silently replace its session.

## Target Model

Targets are workspace-owned resources. The public surface supports discover,
list, get, register, launch, and inspect through HTTP, CLI, and MCP.

Supported target families include Flutter apps, native mobile apps, desktop
apps, browser pages, and system surfaces. App-like targets require a platform
app id. Real-time availability comes from `target.inspect`; persisted target
records do not claim a synthetic live state.

Android black-box execution uses ADB and accessibility/system adapters. iOS
Simulator uses `simctl`; native iOS UI uses WebDriverAgent, with per-target WDA
URLs for concurrent devices/workspaces. Physical-device lifecycle uses
`devicectl` where available. Unsupported capabilities remain explicit.

## Authorization

`COCKPIT_HOME/authorization.json` uses schema
`cockpit.supervisor.authorization/v2`. The document contains complete
allowlists for dangerous operation kinds, operation safety effects, target
environments, test safety effects, and environment secret names.

The default document denies dangerous operations and test safety effects while
allowing development, test, and staging target environments. Production and
unknown environments can be authorized only by an explicit policy. Policy
replacement is atomic and a running daemon must restart before the new policy
takes effect.

## Deleted 1.x Surfaces

The following are not production 2.0 routes:

- implicit latest app/session/task selection;
- in-process CLI/MCP service construction;
- legacy `run-task`, `validate-task`, and control-workflow execution;
- the old `/api/*` DevTools server and dashboard;
- global mutable session and task stores;
- a compatibility forwarding package or alternative runner.

The offline importer may read supported 1.x workflow documents for explicit
migration. It never exposes a 1.x runtime route.

## Release Gates

The release candidate must satisfy all of the following:

1. `dart fix --apply` produces no changes.
2. The repository formatting command exits successfully.
3. `dart analyze` reports no errors or warnings.
4. Protocol schema/OpenAPI contract tests pass.
5. Suite checkpoint/store tests and real worker process integration pass.
6. Real daemon, CLI, MCP, HTTP authentication, policy persistence, SSE, target,
   run, and artifact smoke tests pass.
7. Source scans find no production `flutter_cockpit_protocol`, old DevTools
   routes, direct CLI/MCP application-service construction, or retired design
   artifacts.
8. Package dry-run publication succeeds in dependency order.

Release order is `cockpit_protocol`, `flutter_cockpit`, then `cockpit`, all at
version `2.0.0`.
