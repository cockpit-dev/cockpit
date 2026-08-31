# Changelog

## 4.0.50

- Added a self-contained offline performance report with an embedded Cockpit
  SVG mark, relative timestamps, aligned comparison tables, and hover details.
- Added jank distribution, frame cadence, raster-cache trend, VM category cost,
  cold-start, memory, cache/GC, duration-based flame, and source-evidence views.
- Added configurable VM-event retention with `maxEvents`; RSS sampling remains
  configurable with `sampleEvery` and missing source evidence is never guessed.
- Added a DevTools coverage panel and Chrome trace-compatible timeline export;
  host drivers can call `CockpitPerformanceHtml.timelineJson(report)`.
- Added VM CPU sampling, Dart heap/allocation profiling, and evidence-only
  GPU/shader signal panels to performance captures when the VM service supports
  them.
- Added VM heap trend sampling, isolate health/lifecycle snapshots,
  isolate-group memory points, and timeline recorder/stream metadata to every
  supported performance capture, with bounded HTML charts and detail dialogs.
- Added bounded VM Isolate stream lifecycle events and all-isolate before/after
  snapshots, including explicit started/ended and retention-drop evidence.
- Added VM runtime identity, target/host CPU, architecture, process start, and
  isolate inventory to the HTML runtime panel and full export.
- Added bounded VM Service process-memory trees before and after each capture,
  with compact JSON, coverage status, comparison chart, and detail export.
- Added `CockpitTester.debug` for DevTools visual switches, performance overlay,
  rebuild logging, and animation time scaling with automatic restoration.
- Added a jank/stall evidence panel that correlates slow frames with overlapping
  retained VM spans and shows source locations only when supplied by the VM.
- The coverage panel marks every profiler only when verified data is present;
  unsupported platform counters remain unavailable instead of being guessed.
- Hardened Chrome trace export by pairing valid VM `B/E` spans and lowering
  unmatched markers; unavailable cache, GC, and phase values stay unavailable
  in the HTML viewer instead of appearing as zero.
- Added complete canonical JSON export through `performanceJson()`,
  `exportPerformanceJson()`, and `CockpitPerformanceHtml.fullJson(...)`; the
  HTML full-download now includes every capture in the report bundle.
- Added opt-in VM allocation call-stack traces for selected heap class ids and
  exact Perfetto CPU/timeline exports, while keeping compact results metadata-only.
- Added opt-in DevTools-equivalent `trackBuilds`, `trackUserBuilds`,
  `trackLayouts`, and `trackPaints` instrumentation for real per-widget and
  per-render-object timeline spans, with automatic restoration of prior flags.
- Added an evidence-only Operation hotspots analysis and chart, aggregating
  retained VM operations by category/name with count, p90, total, longest span,
  and optional source locations; the bounded projection is included in full JSON.
- Avoided treating an absent local VM Service as a test failure: profiling still
  runs the action and records `unavailable:vm` when official timeline capture is
  not reachable.

## 4.0.49

- Added bounded native process RSS sampling, total-frame percentiles, memory
  summaries, and HTML capture comparison/resource charts.
- Added a pure-Dart public report entrypoint for host integration drivers,
  keeping report export available without loading Flutter UI libraries.
- Synchronized the integration-test facade with the current Cockpit release.
- Added `CockpitTester.profile` for action-level FrameTiming and native VM
  timeline/GC reports with compact summaries and bounded full report data.
- Profile reports now preserve wall-time frame timestamps and distinguish
  retained samples from observed frames.
- Reports also identify the Flutter build mode for safe interpretation of
  performance data.

## 4.0.48

- Synchronized the integration-test facade with the current Flutter gesture
  runtime and command-lab coverage.

## 4.0.47

- Synchronized the integration-test facade with the Flutter gesture runtime
  fixes in the current Cockpit release.

## 4.0.46

- Synchronized the integration-test facade with the Flutter-first gesture,
  animation, native-action, and live-watch capabilities.

## 4.0.45

- Synchronized the integration-test facade with the current Cockpit release.
- Completed the Flutter gesture facade with real hover, wheel, coordinate
  input, and device/button-aware pointer actions; animation watch remains
  bounded to compact deltas.

## 4.0.44

- Synchronized the integration-test facade with the current Cockpit release.

## 4.0.43

- Use the native timeout default for explicit host/system actions in the
  integration-test facade.
- Added the `flutter_cockpit_test` integration-test facade.
- Reused Cockpit's in-app Element selectors, hit-tested commands, reveal, waits,
  assertions, snapshots, and evidence paths.
- Added explicit native capture, recording, viewport, and host-action helpers.
- Added common long-press, double-tap, increment/decrement, reveal, wait, and
  live-capability helpers; acceptance screenshots now follow Cockpit's platform
  routing policy by default.
- Added bounded defaults and per-call timeout overrides to the integration-test
  facade, including native capture, recording, viewport, and host actions.
- Applied the default timeout to direct `execute` calls and cancel pending
  native recording startup after a timeout.
