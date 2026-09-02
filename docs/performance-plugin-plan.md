# Performance Plugin And AOP Timeline Plan

**Goal:** Let development-only Flutter instrumentation and AOP adapters add
accurate, attributable events to the existing Cockpit performance timeline.

**Architecture:** Keep `CockpitPerformanceEvent` as the only canonical event
model. Add a runtime plugin definition and a bounded sink owned by the existing
collector; plugins are explicitly registered on the Flutter Cockpit
configuration and are active only during an explicit `profile()` capture.
`open` creates a fresh `CockpitPerformancePluginRun` for every capture. The Run
owns mutable subscriptions, timers, counters, and buffers, while the registered
plugin definition remains reusable and safe for repeated or concurrent captures.
The sink supplies Cockpit's monotonic timestamp, preserves source metadata, and
isolates plugin failures. Compact reports retain counts and summaries; complete
JSON, Chrome trace, and HTML retain the bounded plugin events.

**Tech Stack:** Dart/Flutter, `cockpit_protocol` DTOs, `flutter_cockpit`
runtime binding, `flutter_cockpit_test` profiling facade, self-contained HTML.

## Implementation batches

1. **Protocol facts**
   - Add immutable plugin metadata and capture statistics models.
   - Extend `CockpitPerformanceEvent` with compact plugin/source fields while
     preserving truthful omission when unavailable.
   - Validate, serialize, deserialize, and export through the public protocol.

2. **Runtime sink and collector**
   - Add an extensible plugin base class and per-capture Run lifecycle with
     `instant`, `begin/end`, `span`, `counter`, and `sample` helpers. Keep a
     callback factory for small stateless hooks without making callback state
     part of a reusable plugin definition.
   - Use per-plugin limits plus the profile's global event budget, category
     filters, sampling, payload limits, lifecycle deadlines, and
     drop/truncation counters. Close the measured window before plugin cleanup;
     trim before shutdown callbacks so statistics always match retained events.
   - Create one Run per capture, start/stop it around the existing capture
     window, and always attempt Run cleanup after setup failure. Never let a
     plugin exception fail the app action.

3. **Flutter facade integration**
   - Allow `FlutterCockpitConfig` to register plugins once in a development
     shell and allow `profile()` to add temporary plugins for one capture.
   - Merge sink events with VM/FrameTiming events on the same monotonic axis;
     preserve Isolate identity where the runtime provides it.

4. **Analysis and HTML**
   - Add plugin category/source aggregates, event counts, drop warnings,
     duration percentiles, and source-location details to the complete report.
   - Add plugin filtering and hover detail to the existing timeline viewer.

5. **Validation and release**
   - Run focused Dart/Flutter tests, the full melos suite, and performance HTML
     export checks; then verify iOS simulator, Android emulator, and macOS.
   - Re-run CI across all configured platforms, fix regressions, and release the
     next SemVer version only after the current gate is green.
