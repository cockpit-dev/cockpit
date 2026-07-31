# Flutter Development Shell

Use this reference for Flutter source development. The managed Flutter session
is independent from black-box E2E and exposes structured application state and
typed control. Installed production applications can still be tested without
the adapter through the native black-box path in [dev.md](dev.md).

## Contents

- [Keep production untouched](#keep-production-untouched)
- [Add the development dependency](#add-the-development-dependency)
- [Create the development entrypoint](#create-the-development-entrypoint)
- [Register and launch the target](#register-and-launch-the-target)
- [Use the Flutter control plane](#use-the-flutter-control-plane)
- [Dart and Flutter tooling](#dart-and-flutter-tooling)
- [Router integration](#router-integration)

## Keep Production Untouched

Keep all Cockpit imports and wiring under `cockpit/`. Do not import
`flutter_cockpit` from production `lib/` code and do not replace the production
entrypoint. The shell imports the application's existing public root widget or
bootstrap.

```text
cockpit/
  main.dart
  cockpit_bootstrap.dart
lib/
  ... unchanged production code ...
```

## Add The Development Dependency

Add the bridge only as a development dependency, then resolve packages:

```yaml
dev_dependencies:
  flutter_cockpit: any
```

```bash
flutter pub get
```

The standalone `cockpit` CLI may be globally installed. It does not need to be
added to the application when the global executable is used.

## Create The Development Entrypoint

`cockpit/main.dart`:

```dart
import 'package:flutter/widgets.dart';

import 'cockpit_bootstrap.dart';

void main() {
  runApp(buildCockpitDevelopmentApp());
}
```

`cockpit/cockpit_bootstrap.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';

import 'package:your_app/app.dart';

Widget buildCockpitDevelopmentApp() {
  const enableDiagnostics = bool.fromEnvironment(
    'FLUTTER_COCKPIT_ENABLE_DEBUG_DIAGNOSTICS',
  );
  const enableTapFeedback = bool.fromEnvironment(
    'FLUTTER_COCKPIT_ENABLE_TAP_FEEDBACK',
  );

  return FlutterCockpitApp(
    config: FlutterCockpitConfig.production(
      remoteSession: CockpitRemoteSessionConfiguration.resolveFromEnvironment(
        fallback: const CockpitRemoteSessionConfiguration(
          enabled: true,
          host: '127.0.0.1',
          port: 47331,
        ),
      ),
      diagnostics: CockpitDiagnosticsConfig(
        enableRebuildTracking: enableDiagnostics,
        enableTapFeedback: enableTapFeedback,
      ),
    ),
    child: YourExistingApp(
      navigatorObservers: <NavigatorObserver>[
        FlutterCockpit.createNavigatorObserver(),
      ],
    ),
  );
}
```

Replace only the application import, root widget, and its observer parameter
with the application's real public API. Each Navigator needs its own
`FlutterCockpit.createNavigatorObserver()` instance.

## Register And Launch The Target

Register the checkout or monorepo root once. Document indexing is refreshed by
`workspace documents`; select the exact workspace-relative source path and
reuse its `documentId`. Cockpit walks upward from that entrypoint to the nearest
`pubspec.yaml`, launches from that Flutter project directory, and rewrites the
entrypoint relative to it. Do not register every monorepo package as another
workspace.

```bash
cockpit workspace documents \
  --workspace-id <workspaceId> \
  --kind source \
  --relative-path apps/mobile/cockpit/main.dart
cockpit target register \
  --workspace-id <workspaceId> \
  --platform <platformFromDiscovery> \
  --device-id <deviceIdFromDiscovery> \
  --target-kind flutterApp \
  --environment development \
  --mode development \
  --entrypoint-document-id <documentId> \
  --idempotency-key <uniqueKey>
cockpit target launch \
  --workspace-id <workspaceId> \
  --target-id <targetId> \
  --mode development \
  --launch-timeout-ms 900000 \
  --idempotency-key <uniqueKey>
cockpit target inspect \
  --workspace-id <workspaceId> \
  --target-id <targetId> \
  --profile minimal
```

Add repeatable `--dart-define`, `--dart-define-from-file`, `--env`,
`--flutter-arg`, and `--flavor` values only when the application needs them.
Cockpit owns the entrypoint, device, mode, machine, and remote-control flags.
On Android/iOS, `--env` configures the Flutter build process; it is not an
arbitrary mobile application runtime environment. Use Dart defines or an
application-owned configuration channel for values the mobile app must read.

## Use The Flutter Control Plane

The adapter is the source of truth for app-internal development state. It
provides widget/semantics targets and relationships, visible text, route and
focus state, framework/runtime errors, app logs, HTTP activity and failures,
rebuild signals, screenshots, recording requests, and command results with
locator resolution, selected plane, fallback trail, UI delta, and artifact
references. `target.inspect` summarizes target readiness; use the focused
session reads for current application state:

```bash
cockpit operation run --workspace-id <workspaceId> --kind ui.inspect \
  --input-json '{"sessionId":"<sessionId>","profile":"minimal"}'
cockpit operation run --workspace-id <workspaceId> --kind logs.read \
  --input-json '{"sessionId":"<sessionId>","maxLines":40}'
cockpit operation run --workspace-id <workspaceId> --kind errors.read \
  --input-json '{"sessionId":"<sessionId>","maxErrors":8}'
cockpit operation run --workspace-id <workspaceId> --kind network.read \
  --input-json '{"sessionId":"<sessionId>","onlyFailures":true}'
cockpit operation run --workspace-id <workspaceId> --kind app.reload \
  --input-json '{"sessionId":"<sessionId>"}' \
  --idempotency-key <uniqueKey>
```

Use `command.run` for one typed action/assertion and `command.batch` for an
ordered local development interaction. Use `development.probe.collect` before
and after a change only when a durable UI/runtime/network comparison is useful.
The secondary native/system driver is for system dialogs, permissions,
notifications, platform views, WebViews, and native-shell screens; it is not a
replacement for Flutter state inspection.

## Dart And Flutter Tooling

Cockpit provides the Dart/Flutter development surface even when a separate Dart
MCP server is not installed:

| Need | Advertised operation |
| --- | --- |
| Analyze selected indexed files or the workspace | `analyze.files`, `analyze.workspace` |
| Apply fixes, format, or run focused tests | `fix.workspace`, `format.workspace`, `test.workspace` |
| Hover, definition, signature, document/workspace symbols | `lsp.request` |
| Search pub.dev or run pub dependency commands | `package.search`, `package.pub` |
| Read or search dependency source | `package.uris.read`, `package.uris.grep` |
| Discover, launch, list, inspect, reload, restart, stop | target/app/session operations |
| Inspect widgets, routes, logs, errors, network, and rebuild state | Flutter session operations above |

Resolve file paths through `workspace documents` and pass opaque document IDs
to worker operations. Use the descriptor's timeout and execution mode. The
Supervisor owns process, workspace, session, device, port, authorization, and
artifact isolation, so these capabilities work consistently from CLI, MCP, and
future protocol clients.

## Router Integration

If the shell creates the Navigator, supply its Cockpit observer as above. If
the existing application owns `MaterialApp`, `GoRouter`, or another Router and
does not accept observers, keep production code unchanged and bind route state
from a development-only adapter in `cockpit/`:

```dart
FlutterCockpit.bindRouteInformationProvider(router.routeInformationProvider);
```

When no public provider is exposed, update the route from a development-only
listener:

```dart
FlutterCockpit.setCurrentRouteName(currentRouteName);
```

Do not create a second production navigation model solely for automation.
