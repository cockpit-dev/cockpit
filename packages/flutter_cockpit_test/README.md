<div align="center">
  <a href="https://github.com/cockpit-dev/cockpit">
    <img src="https://raw.githubusercontent.com/cockpit-dev/cockpit/main/assets/brand/cockpit-mark.svg" width="128" alt="Cockpit logo">
  </a>
  <h1>flutter_cockpit_test</h1>
  <p><strong>Write normal Flutter integration tests with Cockpit's real locator, control, evidence, and diagnostics engine.</strong></p>
  <p>
    <a href="https://pub.dev/packages/flutter_cockpit_test"><img src="https://img.shields.io/pub/v/flutter_cockpit_test?logo=flutter&amp;label=pub.dev" alt="flutter_cockpit_test version on pub.dev"></a>
    <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-%E2%89%A53.32.0-02569B?logo=flutter&amp;logoColor=white" alt="Flutter 3.32.0 or newer"></a>
    <a href="https://github.com/cockpit-dev/cockpit/blob/main/packages/flutter_cockpit_test/LICENSE"><img src="https://img.shields.io/github/license/cockpit-dev/cockpit" alt="MIT license"></a>
  </p>
  <p><a href="https://github.com/cockpit-dev/cockpit/blob/main/packages/flutter_cockpit_test/README.md">English</a> · <a href="https://github.com/cockpit-dev/cockpit/blob/main/packages/flutter_cockpit_test/README.zh-CN.md">简体中文</a></p>
</div>

`flutter_cockpit_test` is a development-only test facade. It keeps Flutter's
official `integration_test` runner and adds the parts that `flutter_test` cannot
provide by itself: Cockpit's source-friendly Element selectors, real hit-tested
actions, lazy-list reveal, compact snapshots, native screenshots, recording,
viewport control, and explicit host/system actions.

## Install

Add it to the development shell or test-only package, never to production
application code:

```bash
flutter pub add --dev flutter_cockpit_test
```

The package is intended for a non-published `cockpit/` shell that already uses
`flutter_cockpit`. It does not depend on the Cockpit CLI, daemon, MCP server, or
any secret store.

## Quick start

```dart
import 'package:flutter/material.dart';
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

Widget buildDevelopmentApp() {
  return const MaterialApp(home: TaskEditorScreen());
}
```

The helper wraps a plain Flutter widget in `FlutterCockpitApp`. If the builder
already returns `FlutterCockpitApp`, it is mounted as-is and its existing
Cockpit root is reused. This makes migration from an existing development
shell incremental.

Selectors use the same syntax as `cockpit dev`:

```dart
await cockpit.tap('#save');
await cockpit.tap('Dialog >> FilledButton["Continue"]');
await cockpit.type('hello', into: '@message');
await cockpit.scroll('Settings >> Text["Advanced"]', align: 'center');
```

Plain text is exact. Use `#id`, `@key`, widget type, ancestor chains, and
multiple conditions when source context gives you a stronger locator. No
business `Key` or `Semantics` changes are required for Cockpit's Element plane.

The facade covers the common interaction loop directly:
`tap`, `longPress`, `doubleTap`, `type`, `clear`, `press`, `increase`,
`decrease`, `showOnScreen`, `scroll`, `waitFor`, `back`, `dismiss`,
`dismissKeyboard`, `expectVisible`, `expectText`, `screenshot`, and `snapshot`.
Each command advances Flutter's test clock through the same commit and reveal
logic used by the live bridge, so route pushes and async UI updates do not need
hand-written sleeps. Use `cockpit.flutter` when a test intentionally needs a
Flutter-only matcher or custom pump.

Every facade command has a 10-second default timeout. Override one known-slow
call with `timeout`; the value must be positive and no longer than one hour:

```dart
await cockpit.waitForRoute('/reports', timeout: const Duration(seconds: 30));
await cockpit.tap('Refresh', timeout: const Duration(seconds: 5));
```

`CockpitTestOptions.commandTimeout` changes the default for all in-app commands.
Native capture, recording, viewport, and capability calls use a separate
two-minute default through `nativeTimeout`, and each native method also accepts
its own `timeout`. A timed-out recording start requests cancellation before the
timeout is reported.

## Native and host capabilities

Flutter's test binding controls Flutter widgets. Cockpit's native facade covers
the app-window capabilities exposed by the installed plugin:

```dart
final available = await cockpit.native.queryCaptureAvailability();
if (available) {
  final capture = await cockpit.native.captureScreenshot(
    name: 'task-created',
    timeout: const Duration(seconds: 30),
  );
  // capture.screenshot.artifact.relativePath identifies the evidence artifact.
}

final recording = await cockpit.native.queryRecordingCapabilities();
if (recording.supportsNativeRecording) {
  await cockpit.native.startRecording(
    name: 'task-flow',
    timeout: const Duration(minutes: 2),
  );
  // exercise the flow
  final result = await cockpit.native.stopRecording(
    timeout: const Duration(seconds: 30),
  );
  // result.artifact or result.sourceFilePath identifies the recording.
}

final resized = await cockpit.native.resizeViewport(width: 800, height: 600);
```

OS dialogs, app links, accessibility controls, and other host actions belong to
Cockpit's system plane. They are intentionally explicit and supplied by the
test host:

```dart
await cockpit.host.action(
  'openUri',
  parameters: {'uri': 'myapp://tasks/42'},
);
```

Configure `CockpitTestOptions.hostCommand` with a host adapter that forwards
the command to Cockpit's public control API. Without that callback, host
actions fail immediately with a useful configuration error; no external side
effect is guessed or hidden.

## Flutter APIs remain available

`CockpitTester.flutter` is the original `WidgetTester`. Use it for custom
matchers, golden assertions, pump control, or APIs that are intentionally
outside Cockpit's command surface. `CockpitTester.execute` accepts a complete
`CockpitCommand` when a test needs a lower-level operation.

Every executed command is recorded into the in-app Cockpit session and a
compact `cockpit` entry is merged into `integration_test`'s `reportData`. Large
snapshots and binary evidence are kept as artifacts; they are not dumped into
test output.

## Run

Run with Flutter's normal integration-test commands:

```bash
flutter test integration_test/task_flow_test.dart -d <device>
```

For Cockpit-managed development sessions, the same test can run from the
development shell and its steps remain visible in the session timeline and
artifacts. Case/Suite documents remain available for AI-generated, black-box,
matrix, and cross-platform journeys; this package is the ergonomic Dart layer
for Flutter source projects.
