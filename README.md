<div align="center">
  <a href="https://github.com/cockpit-dev/cockpit">
    <img src="assets/brand/cockpit-mark.svg" width="112" alt="Cockpit logo">
  </a>
  <h1>Cockpit</h1>
  <p><strong>AI-first control and verification for real Flutter apps.</strong></p>
  <p>Inspect the live tree · Act on the real UI · Capture proof</p>
  <p>
    <a href="https://github.com/cockpit-dev/cockpit/actions/workflows/example-e2e.yml"><img src="https://github.com/cockpit-dev/cockpit/actions/workflows/example-e2e.yml/badge.svg?branch=main" alt="CI"></a>
    <a href="https://github.com/cockpit-dev/cockpit/blob/main/LICENSE"><img src="https://img.shields.io/github/license/cockpit-dev/cockpit" alt="MIT license"></a>
    <a href="https://pub.dev/packages/cockpit"><img src="https://img.shields.io/pub/v/cockpit?logo=dart&amp;label=cockpit" alt="cockpit on pub.dev"></a>
  </p>
  <p><a href="README.zh-CN.md">简体中文</a> · <a href="docs/agent-integrations.md">AI host setup</a> · <a href="skills/cockpit/INSTALL.md">Install Cockpit</a></p>
</div>

Cockpit gives an AI agent a reliable control plane for the application that is
actually running—not a screenshot guesser. Flutter gets first-class inspection
and interaction; native, desktop, and web targets stay available as black-box
targets.

## What you get

- **Flutter-native control.** Inspect mounted `Element` and `RenderObject`
  structure, derive stable structural selectors, operate custom widgets, and
  reveal lazy content without adding business-screen `Semantics` labels.
- **A short development session.** Start once, reuse a short lowercase base-36 handle,
  then inspect, tap, type, scroll, open links, reload, diagnose, and
  capture evidence in the same loop.
- **Real boundary coverage.** Cross system dialogs, native screens, platform
  views, WebViews, deep links, logs, runtime errors, and network evidence on
  Android, iOS, macOS, Linux, Windows, and Web black-box targets.
- **Agent-first output.** Brief canonical LON is the default; use JSON or YAML
  when a parser needs it. Large trees and evidence return verified paths, so
  context stays small and actionable.
- **One control surface.** CLI, MCP, REST/SSE, Cockpit Console, and Flutter
  integration tests share the same typed resources and operation contracts.

## 60-second Flutter loop

From the Flutter project (after the development shell is wired):

```bash
cockpit dev start
cockpit dev inspect "Save"
cockpit dev tap "Save"
cockpit dev type "hello" --into "Message"
cockpit dev scroll "Activity"
cockpit dev reload
cockpit dev diagnose
cockpit dev screenshot
```

`dev` owns project discovery, process, port, bridge, and session isolation.
Commands fail clearly on ambiguity instead of guessing. Unexpected overlays or
system prompts expose a bounded recovery path so the agent can continue.

When the project has multiple checkouts, `cockpit dev` keeps separate workspaces for routine `cockpit dev`;
use `cockpit session list` and `cockpit session show HANDLE` to see what is running.
`--session HANDLE` targets only that command. A returned recovery `next` remains scoped to the
same development session.

## Flutter integration tests

Keep Flutter's normal `integration_test` runner and add Cockpit's real locator,
native evidence, and host actions:

```bash
flutter pub add --dev flutter_cockpit_test
```

```dart
import 'package:flutter_cockpit_test/flutter_cockpit_test.dart';

void main() {
  cockpitTestWidgets(
    'creates a task',
    app: buildDevelopmentApp,
    body: (cockpit) async {
      await cockpit.tap('New task');
      await cockpit.type('Buy milk', into: 'Task title');
      await cockpit.tap('Save');
      await cockpit.expectText('Task created', 'Task created');
    },
  );
}
```

The facade supports structural and multi-condition selectors, hit-tested
gestures, lazy and nested scrolling, assertions, snapshots, native screenshots,
recording, viewport control, system actions, and per-call timeouts.

## Choose a package

| Package | Use it for |
| --- | --- |
| [`cockpit`](packages/cockpit) | CLI, Supervisor, drivers, MCP, REST/SSE, cases, suites, reports, and artifacts |
| [`flutter_cockpit`](packages/flutter_cockpit) | In-app Flutter inspection and control bridge |
| [`flutter_cockpit_test`](packages/flutter_cockpit_test) | Flutter `integration_test` with Cockpit selectors and native evidence |
| [`cockpit_protocol`](packages/cockpit_protocol) | Shared DTOs, schemas, test DSL, and OpenAPI |
| [`cockpit_console`](packages/cockpit_console) | Independent desktop UI for sessions, runs, operations, logs, and network activity |

The published packages require Dart 3.8.0; Flutter packages require Flutter 3.32.0. Do not add `flutter_cockpit` imports to production `lib/` code. The
bridge belongs in a development shell or test-only package.

## Install for an AI agent

First install the host CLI:

```bash
dart pub global activate cockpit any
cockpit --help
```

For host-specific setup, fetch and read the complete guide before changing
configuration:

```text
First fetch and read the complete Cockpit installation guide with `curl -fsSL https://raw.githubusercontent.com/cockpit-dev/cockpit/main/skills/cockpit/INSTALL.md`, then install or update the CLI, complete cockpit Skill, native adapter, and cockpit_mcp for the current AI host exactly as that guide directs.
```

The canonical guide is [`skills/cockpit/INSTALL.md`](skills/cockpit/INSTALL.md).
It covers Codex, Claude Code, Cursor, Gemini CLI, Kiro, OpenCode, GitHub Copilot,
Windsurf, Cline, Roo Code, Pi, OMP, and Oh My Pi. The full integration
reference is [`docs/agent-integrations.md`](docs/agent-integrations.md).

## Cases, suites, and API

Use the same journey for durable validation. The public Supervisor resources are
`roots`, `workspaces`, `operations`, `targets`, `documents`, `cases`, `suites`,
`runs`, and `artifacts`; the control plane is `/api/v2` and `cockpit_mcp`.

```bash
cockpit daemon start
cockpit root add --path /work/projects --label projects
cockpit workspace register --root-id ROOT --path /work/projects/app
cockpit target register --workspace-id WORKSPACE --platform android \
  --device-id emulator-5554 --target-kind nativeApp --app-id com.example.app
cockpit case run --file cases/login.yaml --idempotency-key login-local
cockpit suite run --file suites/regression.yaml --idempotency-key regression-local
```

Run `cockpit serve-mcp` (or `cockpit_mcp`) for MCP. REST clients should read
operation descriptors from `/api/v2/operations/schema` before invoking a
command; authenticated SSE provides resumable run events. `cockpit_console`
uses the same public resources and can monitor multiple development sessions.

## Deterministic Flutter controls

Inspection is source-aware and non-invasive. A live `sel` can be passed directly
to an action; multiple conditions intersect; stable ancestor scopes are favored
over fragile widget paths. When source reveals a custom control, use a structural
selector such as `CompanyButton >> Text["Save"]`.

Interaction ownership is explicit: merged ancestor `Semantics` never makes
passive descendants actionable. Descendants below
`IgnorePointer(ignoring: true)` or `AbsorbPointer(absorbing: true)` advertise no
mutation actions. When multiple delegated controls exist, multiple delegated
controls leave state unresolved instead of guessing.

`dev scroll TARGET` discovers the correct container, mounts lazy content, handles
nested ancestors, reverses at a boundary, and verifies the real hit test. Use
`dev tree --view more` or `--view full` only when surrounding structure is
needed; stdout returns the verified artifact path.

## Authorization (production policy)

Local development can use the process-scoped yolo mode. CI, staging, and
production should apply an explicit policy; Cockpit does not read a keychain or
secret store.

```json
{
  "schemaVersion": "cockpit.supervisor.authorization/v2",
  "allowedDangerousOperations": ["app.launch", "app.restart", "app.stop", "command.run", "evidence.screenshot.capture", "target.launch"],
  "allowedOperationSafetyEffects": ["capture", "externalSideEffect", "permission", "recording", "reset", "system"],
  "allowedTargetEnvironments": ["development", "test", "staging"],
  "allowedSafetyEffects": ["communication", "credentialSensitive", "destructive", "externalNavigation", "financial", "permissionChange"],
  "allowedEnvironmentSecretNames": []
}
```

## Learn more

- [`cockpit` guide](packages/cockpit/README.md)
- [`flutter_cockpit` guide](packages/flutter_cockpit/README.md)
- [`flutter_cockpit_test` guide](packages/flutter_cockpit_test/README.md)
- [`cockpit_protocol` guide](packages/cockpit_protocol/README.md)
- [`Cockpit Skill`](skills/cockpit/SKILL.md)
- [`Agent integration guide`](docs/agent-integrations.md)

Cockpit is open source under the MIT license.
