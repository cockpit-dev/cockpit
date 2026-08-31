<div align="center">
  <a href="https://github.com/cockpit-dev/cockpit">
    <img src="https://raw.githubusercontent.com/cockpit-dev/cockpit/main/assets/brand/cockpit-mark.svg" width="128" alt="Cockpit logo">
  </a>
  <h1>flutter_cockpit</h1>
  <p><strong>The first-class Flutter development adapter for Cockpit.</strong></p>
  <p>
    <a href="https://pub.dev/packages/flutter_cockpit"><img src="https://img.shields.io/pub/v/flutter_cockpit?logo=flutter&amp;label=pub.dev" alt="flutter_cockpit version on pub.dev"></a>
    <a href="https://pub.dev/packages/flutter_cockpit/score"><img src="https://img.shields.io/pub/points/flutter_cockpit?logo=flutter" alt="flutter_cockpit pub points"></a>
    <a href="https://pub.dev/packages/flutter_cockpit/score"><img src="https://img.shields.io/pub/likes/flutter_cockpit?logo=flutter" alt="flutter_cockpit likes on pub.dev"></a>
    <a href="https://pub.dev/packages/flutter_cockpit/score"><img src="https://img.shields.io/pub/popularity/flutter_cockpit?logo=flutter" alt="flutter_cockpit popularity on pub.dev"></a>
  </p>
  <p>
    <a href="https://github.com/cockpit-dev/cockpit/actions/workflows/example-e2e.yml"><img src="https://github.com/cockpit-dev/cockpit/actions/workflows/example-e2e.yml/badge.svg?branch=main" alt="CI"></a>
    <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-%E2%89%A53.32.0-02569B?logo=flutter&amp;logoColor=white" alt="Flutter 3.32.0 or newer"></a>
    <a href="https://github.com/cockpit-dev/cockpit#black-box-targets"><img src="https://img.shields.io/badge/platforms-6%20supported-2E7D32" alt="Android, iOS, macOS, Linux, Windows, and web"></a>
    <a href="https://github.com/cockpit-dev/cockpit/blob/main/packages/flutter_cockpit/LICENSE"><img src="https://img.shields.io/github/license/cockpit-dev/cockpit" alt="MIT license"></a>
  </p>
  <p><a href="https://github.com/cockpit-dev/cockpit/blob/main/packages/flutter_cockpit/README.md">English</a> · <a href="https://github.com/cockpit-dev/cockpit/blob/main/packages/flutter_cockpit/README.zh-CN.md">简体中文</a></p>
</div>

`flutter_cockpit` is Cockpit's first-class in-app adapter for AI-driven Flutter
development, inspection, and control. It is independent from the black-box
path used for installed production applications.

It provides:

- runtime bootstrap through `FlutterCockpit.runApp` or `FlutterCockpitApp`
- command execution for taps, hover, text input, real wheel/trackpad input, gestures, waits, assertions, screenshots, and snapshots
- remote session transport over HTTP on VM platforms and the Cockpit WebSocket
  bridge on web
- structured Widget, Element, RenderObject, semantics, route, focus, log,
  runtime error, HTTP/SSE/WebSocket network, and rebuild state
- snapshot, artifact, recording, and bundle models
- an explicit bounded `CockpitPerformanceCollector` for engine frame timings,
  display-aware budgets, cache peaks, and action-level profiling
- target, plane, surface, and fallback-aware runtime models for AI-first summaries

## Install

Requires Flutter 3.32.0 or newer.

```yaml
# cockpit/pubspec.yaml
dev_dependencies:
  flutter_cockpit: any
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
production `lib/` code. Flutter-view screenshots, Element-based inspection and
control, network signals, runtime diagnostics, and remote sessions work in-app
without requiring application-authored `Semantics`. System dialogs,
notifications, host screenshots, and host recordings should still be driven by
`cockpit` system actions so capability discovery and platform fallbacks remain
truthful.

### Install For AI Agents

Ask the current AI host to install the CLI, complete Skill, native adapter, and
MCP surface:

```text
First fetch and read the complete Cockpit installation guide with `curl -fsSL https://raw.githubusercontent.com/cockpit-dev/cockpit/main/skills/cockpit/INSTALL.md`, then install or update the CLI, complete cockpit Skill, native adapter, and cockpit_mcp for the current AI host exactly as that guide directs.
```

The guide covers Codex, Claude Code, Cursor, Gemini CLI, Kiro, OpenCode, Pi,
Oh My Pi, Cline, GitHub Copilot, Windsurf, Roo Code, and portable fallback
installation.

## Recommended Integration

Create a non-published Flutter package under `cockpit/`. It depends locally on
the real application and keeps `flutter_cockpit` in the shell's
`dev_dependencies`; neither dependency enters the production package graph.
The globally installed `cockpit` CLI is not an application dependency. Keep
the normal production entrypoint and production `lib/` untouched.
Do not add `flutter_cockpit` imports to production `lib/` code.

```yaml
# cockpit/pubspec.yaml
name: your_app_cockpit
publish_to: none

environment:
  sdk: '>=3.8.0 <4.0.0'
  flutter: '>=3.32.0'

dependencies:
  flutter:
    sdk: flutter
  your_app:
    path: ..

dev_dependencies:
  flutter_cockpit: any
```

Replace `your_app` with the actual application package name and run
`flutter pub get` inside `cockpit/`.

If the application uses a Pub workspace, add `cockpit/` to the root
`workspace` list, add `resolution: workspace` to the shell manifest, and use a
compatible application version constraint instead of `path: ..`. Run
`flutter pub get` from the workspace root. This keeps the shell locally
resolved without adding Cockpit to the production package dependencies.

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
- UI snapshots with live, baseline, investigate, and forensic diagnostic
  profiles, including bounded mounted Element trees
- accessibility, network, runtime, and rebuild signals
- screenshot and recording requests
- remote session status and command endpoints

### Frame timing capture

Performance collection is opt-in. The runtime keeps no timing callback attached
until a caller starts a collector, and stopping it returns a bounded report with
the original engine timestamps rather than a wall-clock approximation:

```dart
final collector = FlutterCockpit.performanceCollector;
collector.start();
// exercise the app through Cockpit
final report = collector.stop(stepId: 'open-list');
```

The report includes raw vsync and raster-finish wall-time timestamps,
build/raster/vsync/total durations, p50/p90/p99/worst values, jank counts,
cache peaks, and an explicit `dropped` count when the retention limit is
reached. Aggregates describe retained frames only; when `dropped.frames` is
present they are a bounded sample, not whole-capture percentiles. Empty phases
omit duration aggregates instead of reporting a fabricated zero. `fps` is
omitted unless the source frame timestamps prove a strictly increasing cadence.
Every report records the Flutter build mode; debug timings are diagnostic only,
while profile or release timings are suitable for performance decisions.
For VM timeline events and GC counts, use
`flutter_cockpit_test`'s `cockpit.profile`; unsupported platforms are reported
as unavailable instead of receiving guessed values.

Interaction ownership stays explicit: merged ancestor `Semantics` never makes
passive descendants actionable, and descendants below `IgnorePointer(ignoring:
true)` or `AbsorbPointer(absorbing: true)` advertise no mutation actions. When
one actionable outer row
delegates selection to exactly one blocked control, the outer target carries
that control's state; multiple delegated controls leave state unresolved
instead of guessing.

HTTP diagnostics mask credential values with `*` by default while retaining
useful structure such as authorization schemes, cookie names, query keys, and JSON
field names. A development-only entrypoint can explicitly use
`CockpitHttpNetworkObserverConfiguration(redact: false)` when raw bounded
payloads are required; never enable raw capture in a production entrypoint or
an evidence-producing CI run.

`FlutterCockpitRoot` treats Flutter hot reload as a runtime-diagnostic generation
boundary. Errors and unconsumed recorded steps from the previous generation are
cleared during reassembly; errors raised by the reloaded application are captured
normally.

For Dart-authored Flutter integration tests, use
[`flutter_cockpit_test`](https://pub.dev/packages/flutter_cockpit_test). It keeps
the official `integration_test` runner while reusing Cockpit's selector-first
commands, native evidence helpers, and compact session reporting. This package
is a development dependency and does not add Cockpit to the production app.

Host-side orchestration, MCP, workspace tooling, and delivery validation live in [`cockpit`](https://pub.dev/packages/cockpit).
The runtime bundle models now preserve `targetKind`, `primaryExecutionPlane`, `planesUsed`, `surfaceKindsUsed`, `fallbackCount`, plus per-step and per-observation plane metadata so host-side tooling can explain when Flutter control stayed on-plan versus when it had to degrade to another surface.
On web, the runtime supports the Flutter Element and Flutter-view control path directly, while the method channels are registered as explicit unavailable stubs so capability checks stay truthful instead of failing through missing-plugin noise. On mobile and desktop, native method-channel recording and capture register through the package plugin entries and are used as app-window evidence fallbacks; prefer system or host evidence through `cockpit` when the goal is to prove system dialogs, notifications, host windows, or cross-app behavior.

Package page: [pub.dev/packages/flutter_cockpit](https://pub.dev/packages/flutter_cockpit)
