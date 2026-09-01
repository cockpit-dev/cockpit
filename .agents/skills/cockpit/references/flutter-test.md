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
import 'package:flutter_test/flutter_test.dart';

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
await cockpit.hover('More options');
await cockpit.tap('Dialog >> FilledButton["Continue"]');
await cockpit.type('hello', into: '@message');
await cockpit.focus('@message');
await cockpit.selectText('@message', start: 0, end: 5);
await cockpit.copy(from: '@message');
await cockpit.paste('@message');
await cockpit.clear('@message');
await cockpit.scroll('Settings >> Text["Advanced"]', align: 'center');
await cockpit.wheel(
  target: '#list',
  delta: const Offset(0, 120),
  steps: 2,
);
```

Available facade methods cover `tap`, `hover`, `longPress`, `doubleTap`, `drag`, `fling`,
`swipe`, `pinch`, `rotate`, `panZoom`, `multiTouch`, `type`, `clear`, `copy`,
`paste`, `focus`, `setTextEditingValue`, `selectText`, `keyDown`, `keyUp`,
`press`, `increase`, `decrease`, `showOnScreen`, `scroll`,
`wheel`,
`waitFor`, `waitForUi`, `waitForRoute`, `back`, `dismiss`,
`dismissKeyboard`, `expectVisible`, `expectText`, `screenshot`, `snapshot`,
`watch`, and `execute`. `scroll` reveals through every mounted nested scrollable
ancestor; pass `direction`, `align` (`start|center|end`), `offset`, an
explicit `scrollable` selector, or `maxScrolls` only when the default search
does not express the required placement. Do not add sleeps.

Gestures use real hit-tested pointer events. A target is optional only when an
explicit `at` point is supplied; source-owned tests should prefer a selector.
`pinch` uses a scale greater than 1 to spread and less than 1 to pinch. `rotate`
uses radians. `multiTouch` accepts a validated `CockpitMultiTouchSequence` and
always releases every pointer, cancelling active pointers if a sequence fails.
`wheel` dispatches real `PointerScrollEvent` signals rather than a drag, so
scrollables and custom `Listener(onPointerSignal: ...)` widgets receive the
same input as a mouse or trackpad. Its `delta` is per event; use `steps` and
`interval` for a bounded sequence, `device` for device-kind-sensitive code,
and `at` only when the signal owner is not discoverable as a mounted target.

```dart
await cockpit.longPress('#card', duration: const Duration(milliseconds: 900));
await cockpit.doubleTap('#card', interval: const Duration(milliseconds: 120));
await cockpit.drag(target: '#slider', delta: const Offset(120, 0));
await cockpit.swipe(target: '#list', direction: AxisDirection.up);
await cockpit.pinch(target: '#map', scale: 1.5);
await cockpit.rotate(target: '#canvas', radians: 1.5708);
await cockpit.panZoom(target: '#canvas', pan: const Offset(40, 0));
await cockpit.wheel(
  target: '#list',
  delta: const Offset(0, 120),
  steps: 3,
  interval: const Duration(milliseconds: 40),
  device: PointerDeviceKind.trackpad,
);
await cockpit.setTextEditingValue(
  '@message',
  text: 'hello',
  selectionBase: 0,
  selectionExtent: 5,
);
await cockpit.keyDown('ControlLeft');
await cockpit.keyUp('ControlLeft');
await cockpit.multiTouch(
  const CockpitMultiTouchSequence(
    steps: <CockpitMultiTouchStep>[
      CockpitMultiTouchStep(
        pointer: 1,
        phase: CockpitMultiTouchPhase.down,
        atMs: 0,
        dx: -24,
        dy: 0,
      ),
      CockpitMultiTouchStep(
        pointer: 2,
        phase: CockpitMultiTouchPhase.down,
        atMs: 0,
        dx: 24,
        dy: 0,
      ),
      CockpitMultiTouchStep(
        pointer: 1,
        phase: CockpitMultiTouchPhase.up,
        atMs: 220,
        dx: -72,
        dy: 0,
      ),
      CockpitMultiTouchStep(
        pointer: 2,
        phase: CockpitMultiTouchPhase.up,
        atMs: 220,
        dx: 72,
        dy: 0,
      ),
    ],
  ),
  target: '#canvas',
);
```

For animation verification, trigger the mutation without settling it, then use
`cockpit.watch` for bounded layout/control/text deltas and finish with
`await cockpit.waitForUi()`. Use `cockpit.snapshot()` with
`flutter.pump`/`pumpFrames` only when a named intermediate checkpoint needs a
custom assertion. This separates process evidence from the final idle proof and
never retains every full animation frame.

```dart
await cockpit.flutter.tap(find.text('Expand'));
await cockpit.flutter.pump();
final motion = await cockpit.watch(
  query: 'Details',
  duration: const Duration(milliseconds: 600),
  interval: const Duration(milliseconds: 50),
);
expect(motion.changed, isTrue);
await cockpit.waitForUi();
```

`cockpit.flutter` remains the underlying `WidgetTester` for custom matchers,
goldens, pump control, or Flutter APIs intentionally outside Cockpit.

## VM debugger loop

When a native debug/profile harness exposes the Dart VM Service, use the lazy
`cockpit.debugger` session for the common Dart-Code debugger operations instead
of opening a second socket or guessing raw RPC payloads:

```dart
final state = await cockpit.debugger.status(stackLimit: 32);
if (state.runnable == true) await cockpit.debugger.pause();
final paused = await cockpit.debugger.status();
final value = await cockpit.debugger.evaluateInFrame(0, 'cart.length');
await cockpit.debugger.resume();
```

The facade also exposes `stack`, `evaluate`, `getObject`, source
`addBreakpoint`/`removeBreakpoint`, `setBreakpointEnabled`, `setPauseMode`,
`setLibraryDebuggable`, `reloadSources`, and explicit `callServiceExtension`
for Flutter inspector or app extensions. Results are
bounded summaries with verified frame variables and source locations; object
collections are paged only by an explicit `getObject(offset:, count:)`. Use
`available` for a side-effect-free capability probe. Web or a release harness
without VM Service returns an unavailable debugger error; it never fabricates
stack, pause, or evaluation data.

## Performance profiling

Use `cockpit.profile` for a bounded action-level performance capture:

```dart
final report = await cockpit.profile(
  () async {
    await cockpit.tap('#open-list');
    await cockpit.scroll('#list');
  },
  name: 'open-list',
  streams: const <String>['Dart', 'GC', 'Embedder'],
);
```

For rebuild attribution, opt in explicitly; normal captures leave the extra
framework instrumentation off:

```dart
final report = await cockpit.profile(
  () => cockpit.tap('#refresh'),
  name: 'refresh-rebuilds',
  trackRebuilds: true,
  maxRebuildFrames: 2000,
);
```

The collector listens to Flutter's original `FrameTiming` stream and records
raw vsync and raster-finish wall-time timestamps, build/raster/vsync/total
durations, cache peaks, jank budget, percentiles, and valid frame timestamps.
Native targets additionally use the official
integration-test VM timeline for bounded events and GC counts. Use
`sampleEvery` for native RSS frequency, `streams` and `timeline` to select VM
tracing, `memory: false` to disable RSS, and `maxEvents` to cap retained VM
events. CPU sampling and heap allocation profiling are enabled by default when
the VM service is available; tune `cpu`, `heap`, `maxCpuSamples`, and
`maxHeapClasses` for long captures. Web reports these as unavailable and never
substitutes fake values. A local `flutter test` process without a VM Service URI still runs
the action and records `unavailable:vm`; `flutter drive --profile --no-dds` and
native instrumentation keep the official VM timeline. The non-web Flutter
Driver does not support `flutter drive --release` and Flutter exits before the
test starts; do not use release with the VM-backed driver. For a true release
artifact, use the platform-native integration harness (XCTest, Android
instrumentation, or a device lab) and treat VM timeline, CPU, heap, GC, and
DevTools metrics as unavailable unless that harness provides an equivalent
collector. The
complete report is under `cockpit.performance.<name>` in
`IntegrationTestWidgetsFlutterBinding.reportData`, while the normal Cockpit
result keeps only summary metrics. `dropped` is explicit when a retention
bound is reached; those aggregates describe the retained sample only. Empty
phases omit duration aggregates rather than reporting a fabricated zero, and
`fps` is omitted unless the original timestamps establish a strictly increasing
cadence. Never interpret omitted or unavailable metrics as zero.
The same VM capture also retains the data behind the DevTools runtime views:
`devtools.heap.samples` is a bounded used/capacity/external heap timeline;
`devtools.isolate` contains the selected isolate plus all-isolate before/after
health snapshots and bounded VM Isolate-stream lifecycle events; and
`devtools.timeline` records the VM timeline recorder, available streams, and
recorded streams. `devtools.vm` keeps VM identity and isolate inventory, while
`devtools.vmem` keeps bounded before/after process-memory trees with explicit
child drops. These are part of the strongly typed `CockpitDevToolsProfile`, not
ad-hoc HTML fields. Compact test output reports counts and availability;
`performanceJson()`, `exportPerformanceJson()`, and standalone HTML retain the
complete bounded data. `allocationClassIds` is explicit opt-in for selected
class allocation stacks, and `perfetto: true` is explicit opt-in for exact VM
CPU/timeline proto files because both add capture overhead.

Short captures can keep the complete report in memory. For a journey that can
run for hours, choose the streaming path and write records to JSONL chunks
instead of letting `traceTimeline` build one giant in-memory result:

```dart
final archive = await cockpit.openPerformanceArchive(name: 'overnight-flow');
await cockpit.profile(
  () => runOvernightJourney(),
  name: 'overnight-flow',
  archive: archive,
);
```

The archive writes frames, VM/plugin events, RSS and heap samples, logs, and
debug records incrementally. It rotates 64 MiB JSONL chunks and updates one
manifest path. The default `lossless` mode leaves the pending queue uncapped
and preserves every accepted record. If a constrained runner needs a hard
queue bound, choose `CockpitPerformanceArchiveMode.low` and set
`maxPendingBytes`; drops are counted rather than hidden. Chunk size, flush and
poll intervals, and the queue limit are configurable. Use
`exportPerformanceJsonl()` for completed reports. The HTML viewer displays
archive metadata and paths, not the entire multi-gigabyte stream.
`devtools.display` records the Flutter engine's effective refresh rate, derived
frame budget, and selected Flutter view. Set `trackRebuilds: true` only when
you need DevTools-compatible `Flutter.RebuiltWidgets` frame counts and source
mappings; `devtools.rebuild` retains per-frame entries, aggregate widget
totals, unresolved locations, and bounded drops. This stream is separate from
Cockpit's in-process rebuild tracker and is never enabled implicitly.
The VM capture also listens to `Logging` and `Debug` by default. `devtools.log`
keeps only metadata already present in each log notification (message, level,
logger, zone, error, and stack), while `devtools.dbg` keeps pause/resume/exception/
reload context and verified frame locations. Both streams are bounded and do
not trigger object evaluation; set `logs: false` or `debug: false` for a
capture that must exclude them. Use `maxLogs` and `maxDebug` only for very long
captures that need a different retention bound. Isolate snapshots retain
new/old generation heap spaces and breakpoint counts when the VM exposes those
fields.
Reports include the Flutter build mode. Debug timings are diagnostic only;
profile timings are suitable for performance decisions. Release timings are
valid only when collected by a native release harness, never by `flutter drive`.
The
standalone HTML report converts engine timestamps to relative capture time,
exposes hover details for every chart, includes jank/cadence/raster-cache,
startup milestones, memory/cache/GC, VM category cost, Operation hotspots, and
duration-based flame views, and shows source evidence only when a VM event
argument contains a file, URL, symbol, or line. Operation hotspots aggregate
actual VM event category/name pairs into count, timed count, total duration, p90,
and longest span; the source column stays evidence-only. It never guesses a
code location or CPU call stack from a frame timing.
For a targeted diagnostic capture, set `trackBuilds`, `trackUserBuilds`,
`trackLayouts`, or `trackPaints` to enable Flutter's real per-widget or
per-render-object timeline spans. These DevTools-equivalent switches are off by
default because instrumentation changes timings, and Cockpit restores their
previous global values after the capture. The same facade exposes the visual
DevTools switches directly:

```dart
cockpit.debug.apply(
  paintSize: true,
  repaintRainbow: true,
  performanceOverlay: true,
  timeScale: 5,
);
```

The harness restores every global switch at tear-down. GPU/shader values in the
HTML report come only from real matching VM timeline events.
Use `cockpit.performanceJson()` for the complete canonical JSON bundle or
`cockpit.exportPerformanceJson()` to write it to an artifact path. These export
APIs retain every completed capture and all retained frames, VM events and
arguments, memory samples, startup milestones, explicit drop counts, and the
bounded `analysis.hotspots` projection; they
are intentionally more detailed than the compact integration-test result.
The HTML viewer also includes a DevTools coverage panel: FrameTiming, raster
cache, VM timeline, GC, process RSS, cold-start milestones, CPU samples,
heap/allocation classes, display refresh, widget rebuilds, and matching GPU/shader signals are marked available
only when the capture contains verified data; unsupported values remain
unavailable. Use Cockpit network evidence for HTTP/SSE/WebSocket traffic. Its
`Download timeline` action exports retained VM events as Chrome trace-compatible
`traceEvents` JSON; FrameTiming and memory measurements remain in the canonical
report and their dedicated charts. Host drivers can generate the same timeline
with `CockpitPerformanceHtml.timelineJson(report)`. Compact events omit async /
flow IDs, so those phases are lowered to self-contained instant or duration
events to keep the exported trace importable.

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

For VM timeline/performance integration, use Flutter's profile build and driver
with DDS disabled so the device isolate connects to the forwarded VM Service
endpoint directly:

```bash
flutter drive --profile --no-dds --driver=integration_test/driver.dart \
  --target=integration_test/performance_profile_test.dart -d emulator-5554
flutter drive --profile --no-dds --driver=integration_test/driver.dart \
  --target=integration_test/performance_profile_test.dart -d <ios-simulator-udid>
flutter drive --profile --no-dds --driver=integration_test/driver.dart \
  --target=integration_test/performance_profile_test.dart -d macos
```

`flutter test integration_test/...` always uses debug mode and does not accept
`--profile` or `--release`. `flutter drive --release` is not a fallback: the
non-web Flutter Driver rejects release mode. Build release integration artifacts
only for a native XCTest, Android instrumentation, or device-lab runner when
release correctness or real production startup is the decision; expect
Cockpit's VM-backed timeline and DevTools panels to be unavailable in that
harness.

Without `--no-dds`, recent Flutter toolchains can advertise a host-only DDS
port and make `integration_test` timeline capture fail with a connection error.
This flag is only needed for `flutter drive`; ordinary `flutter test` does not
need it. Start one simulator at a time when resources are limited and shut it
down after the run.

Use `cockpit dev` around a development shell when the same steps must be
visible in a live session timeline. Use `cockpit case`/`cockpit suite` for
black-box, matrix, CI, or cross-technology journeys. The Dart facade and the
document runner share selectors and command semantics, but they do not share
an implicit session: select the exact Cockpit session when the host bridge
controls another app.
