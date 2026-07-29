<p align="center">
  <img src="https://raw.githubusercontent.com/cockpit-dev/cockpit/main/assets/brand/cockpit-mark.svg" width="128" alt="Cockpit logo">
</p>

# flutter_cockpit

[![pub package](https://img.shields.io/pub/v/flutter_cockpit?logo=dart&label=pub.dev)](https://pub.dev/packages/flutter_cockpit)
[![pub points](https://img.shields.io/pub/points/flutter_cockpit?logo=dart)](https://pub.dev/packages/flutter_cockpit/score)
[![likes](https://img.shields.io/pub/likes/flutter_cockpit?logo=dart)](https://pub.dev/packages/flutter_cockpit/score)
[![E2E](https://github.com/cockpit-dev/cockpit/actions/workflows/example-e2e.yml/badge.svg)](https://github.com/cockpit-dev/cockpit/actions/workflows/example-e2e.yml)
[![License](https://img.shields.io/github/license/cockpit-dev/cockpit)](https://github.com/cockpit-dev/cockpit/blob/main/packages/flutter_cockpit/LICENSE)

[简体中文](https://github.com/cockpit-dev/cockpit/blob/main/packages/flutter_cockpit/README.zh-CN.md)

`flutter_cockpit` is the optional in-app semantic bridge for Cockpit 2.0 E2E
automation and AI-driven Flutter development.

It provides:

- runtime bootstrap through `FlutterCockpit.runApp` or `FlutterCockpitApp`
- command execution for taps, text input, gestures, waits, assertions, screenshots, and snapshots
- remote session serving over HTTP
- snapshot, artifact, recording, and bundle models
- target, plane, surface, and fallback-aware runtime models for AI-first summaries

## Install

Requires Flutter 3.32.0 or newer.

```yaml
dev_dependencies:
  flutter_cockpit: ^2.0.0
```

Keep the runtime development-only. Put every `flutter_cockpit` import and all
integration code under `cockpit/`; production `lib/` code and production
entrypoints remain unchanged.

Darwin integration supports both CocoaPods and Swift Package Manager. The
package includes an iOS and macOS `.podspec` as well as `Package.swift`
manifests backed by the same native sources and privacy manifests. Flutter uses
the integration selected by the host project, so CocoaPods projects do not
need to migrate to SwiftPM.

The runtime package declares native plugin entries for Android, iOS, macOS,
Linux, Windows, and web. That lets app-window screenshots and recording
fallbacks register consistently whenever the cockpit entrypoint is compiled.
Keep the integration isolated by importing it only from `cockpit/`, never from
production `lib/` code. Flutter-view screenshots, semantic control, network signals,
runtime diagnostics, and remote sessions work in-app. System dialogs,
notifications, host screenshots, and host recordings should still be driven by
`cockpit` system actions so capability discovery and platform fallbacks remain
truthful.

## Recommended Integration

Create a standalone `cockpit/` development project with `main.dart`, and keep
`flutter_cockpit` and `cockpit` in that shell's `dev_dependencies`. Keep the
normal production entrypoint, production `lib/`, and production release
dependency graph untouched. Do not add `flutter_cockpit` imports to production `lib/` code.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';

import 'package:your_app/app_shell.dart';

Future<void> main() async {
  runApp(buildCockpitDevelopmentApp());
}

Widget buildCockpitDevelopmentApp() {
  return FlutterCockpitApp(
    config: FlutterCockpitConfig.production(
      remoteSession: CockpitRemoteSessionConfiguration.resolveFromEnvironment(
        fallback: const CockpitRemoteSessionConfiguration(
          enabled: true,
          host: '127.0.0.1',
          port: 47331,
        ),
      ),
    ),
    child: MaterialApp(
      navigatorObservers: <NavigatorObserver>[
        FlutterCockpit.navigatorObserver,
      ],
      home: const AppShell(),
    ),
  );
}
```

Replace `package:your_app/app_shell.dart` with the import that already exposes
your app root widget or bootstrap. Cockpit's target launch operation injects
the `FLUTTER_COCKPIT_REMOTE_*` dart-defines, so
`resolveFromEnvironment(...)` enables the remote surface without taking over
the production bootstrap.
Only wire `FlutterCockpit.navigatorObserver` from the standalone shell entrypoint. `FlutterCockpitApp` automatically discovers the public `RouteInformationProvider` used by Flutter Router, `RouterConfig`, `go_router`, and other Router-based libraries, so an app-owned router normally needs no additional route bridge.

For nested navigators, create one observer per navigator so route state can return to the parent stack after a nested pop:

```dart
Navigator(
  observers: <NavigatorObserver>[
    FlutterCockpit.createNavigatorObserver(),
  ],
  onGenerateRoute: buildRoute,
)
```

The same factory works with router libraries that expose navigator observers, including root and shell navigators. For dynamically created routers that cannot be discovered from the mounted tree, bind their public provider from `cockpit/` with `FlutterCockpit.bindRouteInformationProvider(...)`. Use `FlutterCockpit.setCurrentRouteName(...)` only when a router exposes neither a provider nor observers; `flutter_cockpit` does not depend on any third-party router package.

Run it with:

```bash
cd cockpit
flutter run --target main.dart
```

## What The Runtime Exposes

- low-intrusion root bootstrap
- command routing and execution
- UI snapshots with bounded diagnostics
- accessibility, network, runtime, and rebuild signals
- screenshot and recording requests
- remote session status and command endpoints

Host-side orchestration, MCP, workspace tooling, and delivery validation live in [`cockpit`](https://pub.dev/packages/cockpit).
The runtime bundle models now preserve `targetKind`, `primaryExecutionPlane`, `planesUsed`, `surfaceKindsUsed`, `fallbackCount`, plus per-step and per-observation plane metadata so host-side tooling can explain when Flutter control stayed on-plan versus when it had to degrade to another surface.
On web, the runtime supports the Flutter semantic and Flutter-view control path directly, while the method channels are registered as explicit unavailable stubs so capability checks stay truthful instead of failing through missing-plugin noise. On mobile and desktop, native method-channel recording and capture register through the package plugin entries and are used as app-window evidence fallbacks; prefer system or host evidence through `cockpit` when the goal is to prove system dialogs, notifications, host windows, or cross-app behavior.

Package page: [pub.dev/packages/flutter_cockpit](https://pub.dev/packages/flutter_cockpit)
