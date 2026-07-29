# Flutter Development Shell

Use this reference when Flutter semantic inspection, hot reload, route/runtime
errors, network evidence, or mixed Flutter/native control is required. Installed
Flutter applications can still be tested without this bridge through the native
black-box path in [dev.md](dev.md).

## Contents

- [Keep production untouched](#keep-production-untouched)
- [Add the development dependency](#add-the-development-dependency)
- [Create the development entrypoint](#create-the-development-entrypoint)
- [Register and launch the target](#register-and-launch-the-target)
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
  flutter_cockpit: ^2.1.0
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

Register the workspace first. Document indexing is refreshed by
`workspace documents`; select the exact source path and reuse its `documentId`:

```bash
cockpit workspace documents \
  --workspace-id <workspaceId> \
  --kind source \
  --relative-path cockpit/main.dart
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
