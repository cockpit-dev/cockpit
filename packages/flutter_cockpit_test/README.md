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
import 'package:flutter/gestures.dart';
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
await cockpit.hover('More options');
await cockpit.tap(null, at: const Offset(400, 300),
    device: PointerDeviceKind.mouse, buttons: kSecondaryButton);
await cockpit.tap('Dialog >> FilledButton["Continue"]');
await cockpit.type('hello', into: '@message');
await cockpit.scroll('Settings >> Text["Advanced"]', align: 'center');
await cockpit.wheel(
  target: '#list',
  delta: const Offset(0, 120),
  steps: 2,
);
```

Plain text is exact. Use `#id`, `@key`, widget type, ancestor chains, and
multiple conditions when source context gives you a stronger locator. No
business `Key` or `Semantics` changes are required for Cockpit's Element plane.

The facade covers the complete Flutter interaction loop directly: pointer
gestures (`tap`, `hover`, `longPress`, `doubleTap`, `drag`, `fling`, `swipe`,
`pinch`, `rotate`, `panZoom`, `multiTouch`, `wheel`), text and keyboard input
(`type`, `clear`, `copy`, `paste`, `focus`, `setTextEditingValue`, `selectText`,
`keyDown`, `keyUp`, `hotkey`, `press`), controls and navigation (`increase`,
`decrease`, `showOnScreen`, `scroll`, `waitFor`, `waitForUi`, `waitForRoute`,
`back`, `dismiss`, `dismissKeyboard`), assertions and evidence (`expectVisible`,
`expectText`, `screenshot`, `snapshot`, `watch`, `execute`).
Each command advances Flutter's test clock through the same commit and reveal
logic used by the live bridge, so route pushes and async UI updates do not need
hand-written sleeps. Use `cockpit.flutter` when a test intentionally needs a
Flutter-only matcher or custom pump.

All gestures are real hit-tested pointer events. Coordinate input is available
as `at` when a target is not discoverable; `device` and `buttons` cover mouse,
stylus, and touch-sensitive behavior without changing the app. `wheel` sends
real `PointerScrollEvent` signals to `Scrollable`, custom
`Listener(onPointerSignal: ...)`, and trackpad-aware widgets. Its `delta` is
applied per event; use `steps`, `interval`, `device`, or `at` only when the
scenario needs them.

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

## Performance profiling

Profile an interaction with the same test clock and frame pipeline used by the
app. Cockpit records raw vsync and raster-finish wall-time timestamps together
with engine `FrameTiming` values (build, raster, vsync, total span, raster-cache
usage, jank budget, and p50/p90/p99/worst values). On native
Flutter targets it also captures the official integration-test VM timeline and
GC events plus bounded process RSS samples; web reports the timeline and memory
as unavailable instead of fabricating data. If a local `flutter test` process
does not expose a VM Service URI, the action still runs normally and the report
records `unavailable:vm`; native `flutter drive`/instrumentation runs keep the
official VM timeline:

```dart
final report = await cockpit.profile(
  () async {
    await cockpit.tap('#open-list');
    await cockpit.scroll('#list');
  },
  name: 'open-list',
  streams: const <String>['Dart', 'GC', 'Embedder'],
);
expect(report.summary.jankCount, 0);
```

Native captures also sample process RSS every 100ms by default and retain the
start/end/min/max/average/peak/delta summary plus the bounded sample timeline.
Set `memory: false` when the extra process metric is irrelevant; use
`sampleEvery` to trade sampling overhead for temporal resolution, `streams` and
`timeline` to choose VM tracing, and `maxEvents` to bound retained timeline
events. Unsupported targets leave memory unavailable rather than reporting zero.
For a diagnostic capture, `trackBuilds`, `trackUserBuilds`, `trackLayouts`, and
`trackPaints` enable Flutter's real per-widget/per-render-object timeline spans,
matching the corresponding DevTools switches. They are off by default because
the extra instrumentation changes timings, and Cockpit restores the previous
global flags after the capture.

The capture also requests the VM Service `getProcessMemoryUsage` tree by
default (`vmMemory: true`). This is separate from platform RSS: it retains the
VM's before/after process buckets, sizes, top children, and explicit dropped
child counts under `devtools.vmem`. The tree is bounded to keep test memory and
exports predictable; set `vmMemory: false` when a VM memory map is not part of
the investigation. Unsupported runtimes report the metric as unavailable.

`profile()` also samples the VM data behind DevTools' CPU Profiler and Memory
views when a VM service is available. CPU stacks and bounded allocation classes
are retained in the complete report; the compact test result keeps only sample
counts. The same capture also records VM heap samples over time, isolate health
snapshots for every discovered isolate, the VM Isolate stream's bounded
lifecycle events (start, runnable, update, reload, exit, and extension
registration), and timeline recorder stream metadata. New/ended isolates and
retention drops are visible in the HTML runtime panel and complete JSON; the
compact result keeps only counts. Use `cpu: false` or
`heap: false` for a frame-only capture, and tune `maxCpuSamples`,
`maxHeapClasses`, or `maxHeapSamples` for long scenarios:

For a class-specific allocation investigation, first obtain its VM class id
from the heap report, then opt in to call-stack tracing for at most 20 classes.
This extra VM stream is intentionally disabled by default because it changes
allocation profiling overhead:

```dart
final report = await cockpit.profile(
  () => runScenario(),
  allocationClassIds: <String>['classes/123'],
);
// report.devTools?.allocationTraces contains only the selected classes.
```

Set `perfetto: true` when the exact VM CPU/timeline proto is needed for an
offline Perfetto viewer. Regular results keep only bounded metadata; complete
HTML/JSON exports retain the base64 payload, and native hosts can write
standalone `.pftrace` files for every capture with
`exportPerformancePerfetto()`:

```dart
final report = await cockpit.profile(
  () => runScenario(),
  perfetto: true,
);
final tracePaths = await cockpit.exportPerformancePerfetto();
```

Perfetto is best-effort and recorder/platform dependent. If the VM does not
support the RPC or the active recorder writes directly to the OS/file, the
capture remains valid and coverage marks that trace unavailable.

When the VM exposes an isolate group, the heap report also keeps group-level
before/after memory points. This covers multi-isolate apps without sampling
every group on every tick.

```dart
final report = await cockpit.profile(
  () => runScenario(),
  cpu: true,
  heap: true,
  maxCpuSamples: 20000,
  maxHeapClasses: 100,
);
```

The same facade exposes DevTools' visual diagnostics without changing the
production app:

```dart
cockpit.debug.apply(
  paintSize: true,
  repaintRainbow: true,
  performanceOverlay: true,
  timeScale: 5,
);
// The test harness restores every switch at tear-down.
```

GPU/shader values are evidence-only: Cockpit reports matching VM timeline
signals when Flutter emits them and clearly marks platform counters as
unavailable otherwise. It never substitutes guessed GPU numbers.

The complete bounded report is stored under
`cockpit.performance.open-list` in `IntegrationTestWidgetsFlutterBinding.reportData`;
the normal Cockpit result contains only the compact summary. `dropped` counts
are explicit when a configured retention bound is reached; aggregates then
describe the retained sample only. Empty phases omit duration aggregates rather
than reporting a fabricated zero, and `fps` is omitted when the original engine
timestamps cannot establish a strictly increasing cadence. The
phase budget is derived from the target display refresh rate when Flutter
exposes it, otherwise the report records the exact rounded 60Hz fallback
interval (16,667µs).
The report also records `debug`, `profile`, or `release`; debug timings are
diagnostic and must not be used as release performance evidence.
Never treat a missing or unavailable metric as zero.

The HTML report adds source evidence only when VM event arguments contain a
file, URL, symbol, or line. Frame timings alone do not identify Dart code, so
the report never invents a source location.

The DevTools section includes a VM heap trend chart, CPU/heap/GPU summaries,
VM identity and isolate inventory, all-isolate lifecycle snapshots/events, and
recorder/stream metadata. Each section has a
compact **Details** action that opens a native dialog with bounded JSON
previews. The full retained arrays remain in the JSON download, so opening a
dialog does not freeze the report. CPU details also include verified sample
stack paths aggregated from VM function indexes, without inventing source code.

The report also includes **Operation hotspots**, aggregating each actual VM
event category/name into event count, timed-event count, total duration, p90,
and longest span. This answers “what is slow?” before opening the raw timeline.
The source column is evidence-only and appears only when the VM event arguments
provide a location. The same bounded projection is included in `fullJson()`
under each capture's `analysis` field; original events remain unchanged.
The same analysis records GC event count, timed pause total, p50, p90, and max
when the retained timeline contains real GC markers. The HTML cache panel shows
these pause metrics alongside new/old collection counts.

Each `cockpitTestWidgets` run also records cold-start milestones in the compact
`cockpit.startup` entry and in the HTML report: app build/mount, first pumped
frame, and initial-ready time. The clock begins immediately before the app
builder, so the values are honest Dart-harness measurements. Native process
launch time is not inferred when the host cannot provide it.

Host-side `integration_test_driver.dart` files should import
`package:flutter_cockpit_test/flutter_cockpit_test_report.dart`; this pure-Dart
entrypoint exports the report models and HTML renderer without loading
`dart:ui`.

### Open a complete offline HTML report

`CockpitTester.exportPerformanceHtml()` writes one self-contained file for the
captures completed by the current test. It includes a report switcher, frame
pacing and budget chart, VM timeline lanes, phase percentiles, cache/GC
pressure, searchable event arguments, paged frame/event tables, and the exact
raw JSON payload. It works without a server or external assets:

```dart
final htmlPath = await cockpit.exportPerformanceHtml(
  title: 'Task flow performance',
  // path: 'build/reports/task-flow.html', // optional
);
// Pass htmlPath to a human or CI artifact collector.
```

For a machine-readable artifact, use `performanceJson()` or
`exportPerformanceJson()`. This is the full canonical bundle for every
completed capture, not the compact `integration_test` result:

```dart
final jsonPath = await cockpit.exportPerformanceJson(
  title: 'Task flow performance',
  // path: 'build/reports/task-flow.json', // optional
);
```

Both export methods preserve all retained frames, VM events and arguments,
memory samples, VM heap samples, allocation classes, isolate snapshots,
timeline stream lists, startup milestones, and explicit retention/drop counts. The
terminal/report output remains compact; exports retain the complete recorded
detail. The only limits are the capture retention settings (`maxEvents`, frame
retention, and memory sampling), and those limits are recorded in the export.

The default path is a unique file under `build/cockpit/performance/`. For a
custom host, `CockpitPerformanceHtml.render(report)` or
`CockpitPerformanceHtml.renderMany(reports)` returns the HTML string without
touching the file system. `CockpitPerformanceHtml.fullJson(reports)` returns
the same complete canonical bundle as a JSON string. JSON remains the
canonical machine-readable export;
the HTML is the human-facing view with relative-time hover charts, jank
distribution, frame cadence, raster-cache trend, VM category cost, a jank/stall
evidence table, operation hotspots, separate memory/cache/GC views, and a duration-based VM flame view when spans are
available. When startup data is supplied it also renders the app-build,
first-frame, and ready milestones as a chart.

The report includes a **DevTools coverage** panel so unavailable data is obvious:
FrameTiming, raster cache, VM timeline, GC, process RSS, and harness cold-start
milestones are marked only when the capture actually contains them. CPU sampling,
heap/allocation profiling, and matching GPU/shader timeline signals are marked
only when the VM actually returns them; unsupported platform counters remain
unavailable rather than being fabricated. Use Cockpit's network evidence for
HTTP/SSE/WebSocket traffic. The top-bar **Download timeline** action
exports the retained VM events as a Chrome trace-compatible `traceEvents` JSON
file for timeline viewers; the complete FrameTiming and memory data remains in
the report JSON and HTML charts. You can also generate that file from a host
driver with `CockpitPerformanceHtml.timelineJson(report)`. Compact reports do
not retain async/flow event IDs, so those phases are lowered to self-contained
instant or duration events to keep the exported trace importable.

This intentionally mirrors the evidence that can be collected without attaching
an interactive DevTools session:

| DevTools/VS Code view | Cockpit capture | Where to inspect |
| --- | --- | --- |
| Performance timeline and frame chart | FrameTiming, jank, cadence, VM events | HTML report and report JSON |
| Slow-frame attribution | Overlapping retained VM spans, with evidence-only source labels | Jank & stalls panel |
| Raster cache | Layer/picture cache counts and bytes | Cache charts and frame explorer |
| Memory and GC | Native RSS samples and VM GC events | Memory and cache/GC charts |
| CPU profiler | VM CPU samples and bounded stacks | CPU sampling panel and full report |
| Memory heap/allocation | VM heap points, bounded class counters, and opt-in selected-class call stacks | Heap & allocation panel and full report |
| Perfetto CPU/timeline | Exact VM proto payload when the recorder supports retrieval | Perfetto download button or `exportPerformancePerfetto()` |
| VM runtime health | Heap trend, isolate snapshots, recorder/stream metadata, VM process-memory tree | VM runtime and VM process memory panels, details dialog |
| GPU/shader | Matching VM timeline signals only | GPU / Shader signals panel |
| Network profiler | Separate Cockpit network evidence | `cockpit dev network` artifacts |

The normal test output is intentionally compact; export is not. The HTML and
JSON downloads contain every retained frame, VM event, memory sample, argument,
startup milestone, and explicit drop count. The exported trace is a faithful
VM-event projection for Chrome/DevTools timeline import. It does not invent CPU
stacks, GPU counters, thread identity, or source locations that the captured data
does not contain. `maxEvents`, frame retention, and memory sampling are the only
bounded limits, and their drops remain visible in the export.

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
