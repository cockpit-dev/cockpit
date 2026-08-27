# `flutter_cockpit_test`

Use this package when the test owns Flutter source and should run through the
official `integration_test` runner while sharing Cockpit's live control and
evidence behavior. Use `cockpit case`/`suite` instead when the journey is
black-box, generated from a document, or targets an app without source access.

## Install and bootstrap

Add the package only to a development shell or test-only package:

```bash
flutter pub add --dev flutter_cockpit_test
```

The package does not start a daemon, read a keychain, or add a production
runtime dependency. `cockpitTestWidgets` initializes
`IntegrationTestWidgetsFlutterBinding`, wraps a normal app in
`FlutterCockpitApp`, and records a compact `cockpit` entry in
`integration_test`'s `reportData`. If the builder already returns a
`FlutterCockpitApp` or `FlutterCockpitRoot`, it is mounted as-is.

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
      await cockpit.tap('#save');
      await cockpit.expectText('Task created', 'Task created');
    },
  );
}
```

The app builder must return the real application root. Do not create a second
fake screen just to make a selector pass.

## Locators and actions

The facade uses the same selector grammar as `cockpit dev` and traverses the
mounted Element tree, so business widgets do not need Cockpit keys or
Semantics labels. In source-known code prefer, in order: `#id`, `@key`, exact
text, widget type, ancestor scope, then multiple conditions. Re-inspect or
re-read source after navigation, filtering, reorder, overlays, or keyboard
changes; live refs are not durable test data.

```dart
await cockpit.tap('#save');
await cockpit.tap('Dialog >> FilledButton["Continue"]');
await cockpit.type('hello', into: '@message');
await cockpit.scroll('Settings >> Text["Advanced"]', align: 'center');
```

Available facade methods cover `tap`, `longPress`, `doubleTap`, `type`,
`clear`, `press`, `increase`, `decrease`, `showOnScreen`, `scroll`,
`waitFor`, `waitForUi`, `waitForRoute`, `back`, `dismiss`,
`dismissKeyboard`, `expectVisible`, `expectText`, `screenshot`, `snapshot`,
and `execute`. `scroll` reveals through every mounted nested scrollable
ancestor; pass `direction`, `align` (`start|center|end`), `offset`, an
explicit `scrollable` selector, or `maxScrolls` only when the default search
does not express the required placement. Do not add sleeps.

`cockpit.flutter` remains the underlying `WidgetTester` for custom matchers,
goldens, pump control, or Flutter APIs intentionally outside Cockpit.

## Timeouts and waiting

Each in-app command defaults to 10 seconds. Native evidence, recording,
viewport, and host-boundary calls default to 2 minutes. Override a single
known-slow call with `timeout`, or set `CockpitTestOptions.commandTimeout` and
`nativeTimeout` for the test. Every timeout must be positive and no longer
than one hour.

```dart
await cockpit.waitForRoute('/reports', timeout: const Duration(seconds: 30));
await cockpit.tap('Refresh', timeout: const Duration(seconds: 5));
await cockpit.waitForUi(network: true);
```

Use `waitForUi(network: true)` only when the assertion depends on network
completion. A timeout is not permission to repeat a mutation; inspect the
postcondition first.

## Native evidence and host actions

`cockpit.native` is for app-window capabilities exposed by the installed
Flutter plugin:

```dart
if (await cockpit.native.queryCaptureAvailability()) {
  await cockpit.native.captureScreenshot(name: 'task-created');
}
final caps = await cockpit.native.queryRecordingCapabilities();
if (caps.supportsNativeRecording) {
  await cockpit.native.startRecording(name: 'task-flow');
  // exercise the flow
  await cockpit.native.stopRecording();
}
await cockpit.native.resizeViewport(width: 800, height: 600);
```

System dialogs, permissions, app links, accessibility controls, and other
cross-process effects belong to the host/system plane. They are explicit:

```dart
await cockpit.host.action(
  'openUri',
  parameters: {'uri': 'myapp://tasks/42'},
);
```

Configure `CockpitTestOptions.hostCommand` with a handler that forwards to
Cockpit's public control API. Without it, host actions fail immediately; the
test never guesses or hides an external side effect. Query the target's live
capabilities before requesting a platform action. For example, iOS has no
stable global `pressBack`; return to an app-defined UI control instead.

Screenshots and large snapshots are artifacts. Keep test output compact and
pass artifact paths to the caller; never print image bytes, Base64, hashes, or
full tree contents.

## Run and choose the layer

Run with Flutter's normal command for the actual target:

```bash
flutter test integration_test/task_flow_test.dart -d emulator-5554
flutter test integration_test/task_flow_test.dart -d <ios-simulator-udid>
flutter test integration_test/task_flow_test.dart -d macos
```

Use `cockpit dev` around a development shell when the same steps must be
visible in a live session timeline. Use `cockpit case`/`cockpit suite` for
black-box, matrix, CI, or cross-technology journeys. The Dart facade and the
document runner share selectors and command semantics, but they do not share
an implicit session: select the exact Cockpit session when the host bridge
controls another app.
