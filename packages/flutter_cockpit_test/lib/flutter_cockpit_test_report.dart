/// Pure-Dart performance report APIs for integration-test host drivers.
///
/// Import this library from an `integration_test_driver.dart` entrypoint when
/// the driver runs in the host Dart VM. It intentionally does not load
/// `dart:ui` or any Flutter widget runtime code.
library;

export 'package:cockpit_protocol/cockpit_protocol.dart'
    show
        CockpitPerformanceEvent,
        CockpitPerformanceFrame,
        CockpitPerformanceMemoryReport,
        CockpitPerformanceMemorySample,
        CockpitPerformanceMemorySummary,
        CockpitPerformanceMode,
        CockpitPerformancePhaseSummary,
        CockpitPerformanceReport,
        CockpitPerformanceSummary;
export 'package:cockpit_protocol/cockpit_protocol.dart'
    show
        CockpitCpuFunction,
        CockpitCpuSample,
        CockpitCpuProfile,
        CockpitDevToolsProfile,
        CockpitAllocationTrace,
        CockpitGpuProfile,
        CockpitHeapClass,
        CockpitHeapPoint,
        CockpitHeapProfile,
        CockpitHeapSample,
        CockpitIsolateEvent,
        CockpitIsolateProfile,
        CockpitIsolateStats,
        CockpitTimelineProfile,
        CockpitVmMemoryNode,
        CockpitVmMemoryProfile,
        CockpitVmMemorySnapshot,
        CockpitVmRuntimeProfile,
        CockpitPerfettoProfile,
        CockpitPerfettoTrace;
export 'src/cockpit_performance_html.dart';
export 'src/cockpit_startup_report.dart';
