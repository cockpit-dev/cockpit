import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'cockpit_native_tester.dart';
import 'cockpit_debug_tools.dart';
import 'cockpit_devtools_profiler.dart';
import 'cockpit_performance_html.dart';
import 'cockpit_performance_archive.dart';
import 'cockpit_performance_html_io.dart'
    if (dart.library.html) 'cockpit_performance_html_web.dart';
import 'cockpit_performance_memory_sampler.dart';
import 'cockpit_startup_report.dart';
import 'cockpit_timeline_analysis.dart';
import 'cockpit_test_options.dart';
import 'cockpit_watch.dart';
import 'cockpit_vm_debugger.dart';

/// Registers an integration test that runs the real Cockpit in-app executor.
///
/// The application is mounted inside [FlutterCockpitApp], so production code
/// does not need to import Cockpit. The official integration_test binding is
/// initialized automatically and remains the owner of device lifecycle and
/// test result transport.
void cockpitTestWidgets(
  String description, {
  required CockpitTestAppBuilder app,
  required Future<void> Function(CockpitTester tester) body,
  CockpitTestOptions options = const CockpitTestOptions(),
}) {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(description, (flutterTester) async {
    final rootKey = GlobalKey<FlutterCockpitRootState>();
    final startupClock = Stopwatch()..start();
    final application = app();
    final appBuildMs = startupClock.elapsed.inMilliseconds;
    FlutterCockpit.ensureInitialized(options.config);
    final ownsRuntime =
        application is! FlutterCockpitApp && application is! FlutterCockpitRoot;
    await flutterTester.pumpWidget(
      ownsRuntime
          ? FlutterCockpitApp(
              config: options.config,
              ownsRuntime: true,
              rootKey: rootKey,
              child: application,
            )
          : application,
    );
    await flutterTester.pump();
    final firstFrameMs = startupClock.elapsed.inMilliseconds;
    if (options.initialPump > Duration.zero) {
      await flutterTester.runAsync(
        () => Future<void>.delayed(options.initialPump),
      );
      await flutterTester.pump();
    }
    final startup = CockpitStartupReport(
      appMs: appBuildMs,
      firstFrameMs: firstFrameMs,
      readyMs: startupClock.elapsed.inMilliseconds,
    );

    final root = rootKey.currentState ?? _findRoot(flutterTester);
    if (root == null) {
      fail(
        'Cockpit test app did not mount FlutterCockpitRoot. '
        'Return a FlutterCockpitApp or a Flutter widget that the helper can '
        'wrap.',
      );
    }

    final cockpit = CockpitTester._(
      flutter: flutterTester,
      root: root,
      options: options,
      startup: startup,
    );
    addTearDown(() async {
      _publishIntegrationReport(cockpit.report);
      await cockpit._closePerformanceArchives();
      await cockpit.debugger.close();
      cockpit.debug.restore();
      await cockpit.native.close();
      await flutterTester.pumpWidget(const SizedBox.shrink());
      await flutterTester.pump();
      if (!ownsRuntime) {
        FlutterCockpit.dispose();
      }
    });

    await body(cockpit);
  });
}

FlutterCockpitRootState? _findRoot(WidgetTester tester) {
  final finder = find.byType(FlutterCockpitRoot);
  if (finder.evaluate().length != 1) return null;
  return tester.state<FlutterCockpitRootState>(finder);
}

void _publishIntegrationReport(Map<String, Object?> report) {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final existing = binding.reportData ?? <String, dynamic>{};
  binding.reportData = <String, dynamic>{...existing, 'cockpit': report};
}

/// A compact, selector-first facade over Cockpit's in-app command executor.
final class CockpitTester {
  CockpitTester._({
    required this.flutter,
    required this.root,
    required this.options,
    required this.startup,
  }) : native = CockpitNativeTester(
         root,
         defaultTimeout: options.nativeTimeout,
       ) {
    _validateTimeout(options.commandTimeout, name: 'commandTimeout');
    _validateTimeout(options.nativeTimeout, name: 'nativeTimeout');
  }

  /// The underlying official Flutter tester for advanced widget assertions.
  final WidgetTester flutter;

  /// The mounted Cockpit root used by this test.
  final FlutterCockpitRootState root;

  /// The options used to bootstrap this test.
  final CockpitTestOptions options;

  /// App build, first-frame, and initial-ready milestones captured by the
  /// harness before the test body starts.
  final CockpitStartupReport startup;

  /// Supported app-native capture, recording, and viewport controls.
  final CockpitNativeTester native;

  /// Flutter visual, timeline, overlay, and animation switches mirrored from
  /// the DevTools controls.
  late final CockpitDebugTools debug = CockpitDebugTools();

  /// Lazy Dart VM debugger session for source-aware pause, stack, evaluate,
  /// breakpoint, and Flutter service-extension operations. It is inert unless
  /// a test explicitly calls it and is closed automatically at tear-down.
  late final CockpitVmDebugger debugger = CockpitVmDebugger(
    timeout: options.commandTimeout,
  );

  /// Explicit host/system-plane action facade.
  late final CockpitHostTester host = CockpitHostTester._(this);

  final List<CockpitCommandResult> _results = <CockpitCommandResult>[];
  final List<CockpitWatchResult> _watches = <CockpitWatchResult>[];
  final List<CockpitPerformanceReport> _performances =
      <CockpitPerformanceReport>[];
  final Set<CockpitPerformanceArchive> _performanceArchives =
      <CockpitPerformanceArchive>{};

  /// All captures completed by this tester, in capture order.
  List<CockpitPerformanceReport> get performanceReports =>
      List<CockpitPerformanceReport>.unmodifiable(_currentPerformanceReports());

  /// Opens a JSONL archive for captures that may run longer than an in-memory
  /// report can safely retain. The archive is closed automatically with this
  /// tester; call [CockpitPerformanceArchive.close] early when desired.
  Future<CockpitPerformanceArchive> openPerformanceArchive({
    String? directory,
    String name = 'performance',
    CockpitPerformanceArchiveOptions options =
        const CockpitPerformanceArchiveOptions(),
  }) async {
    final archive = await CockpitPerformanceArchive.open(
      directory: directory,
      name: name,
      options: options,
    );
    _performanceArchives.add(archive);
    return archive;
  }

  Future<void> _closePerformanceArchives() async {
    for (final archive in List<CockpitPerformanceArchive>.of(
      _performanceArchives,
    )) {
      try {
        await archive.close();
      } on Object {
        // The test result already contains the archive error metadata.
      }
    }
    _performanceArchives.clear();
  }

  /// Renders the captures completed by this tester as one offline HTML file.
  ///
  /// The returned string is self-contained and can be written by a custom
  /// host. Use [exportPerformanceHtml] when the test runs on a native target
  /// and a path is more convenient.
  String performanceHtml({String title = 'Cockpit performance'}) {
    final reports = _currentPerformanceReports();
    if (reports.isEmpty) {
      throw StateError('No performance capture has completed.');
    }
    return CockpitPerformanceHtml.renderMany(
      reports,
      title: title,
      startup: startup,
    );
  }

  /// Writes the captures completed by this tester to one standalone HTML
  /// report and returns its absolute path.
  ///
  /// With no [path], a unique file is created under
  /// `build/cockpit/performance/`. The file contains the complete retained
  /// frame and VM timeline data, while the normal integration-test output
  /// remains compact.
  Future<String> exportPerformanceHtml({
    String? path,
    String title = 'Cockpit performance',
  }) async {
    final html = performanceHtml(title: title);
    return writeCockpitPerformanceHtml(html, path: path, title: title);
  }

  /// Returns the complete canonical JSON export for all captures completed by
  /// this tester. This is intentionally separate from [report], whose compact
  /// shape is used for normal integration-test output.
  String performanceJson({String title = 'Cockpit performance'}) {
    final reports = _currentPerformanceReports();
    if (reports.isEmpty) {
      throw StateError('No performance capture has completed.');
    }
    return CockpitPerformanceHtml.fullJson(
      reports,
      title: title,
      startup: startup,
    );
  }

  /// Writes the complete canonical JSON export and returns its absolute path.
  ///
  /// The file keeps every retained frame, event, argument, memory sample,
  /// startup milestone, and explicit retention count. It never writes the
  /// compact normal test result shape.
  Future<String> exportPerformanceJson({
    String? path,
    String title = 'Cockpit performance',
  }) async {
    final json = performanceJson(title: title);
    return writeCockpitPerformanceJson(json, path: path, title: title);
  }

  /// Exports completed captures as a chunked JSONL archive and returns the
  /// manifest path. Use this for multi-hour suites or any report set that is
  /// too large to keep as one JSON document.
  Future<String> exportPerformanceJsonl({
    String? directory,
    String title = 'Cockpit performance',
    CockpitPerformanceArchiveOptions options =
        const CockpitPerformanceArchiveOptions(),
  }) => CockpitPerformanceArchive.exportReports(
    _performances,
    directory: directory,
    name: title,
    options: options,
  );

  /// Writes all retained Perfetto CPU/timeline traces as standalone files and
  /// returns only their absolute paths. A capture must opt into [perfetto].
  Future<List<String>> exportPerformancePerfetto({
    String? directory,
    String title = 'Cockpit performance',
  }) async {
    if (_performances.isEmpty) {
      throw StateError('No performance capture has completed.');
    }
    return writeCockpitPerformancePerfetto(
      _performances,
      directory: directory,
      title: title,
    );
  }

  var _sequence = 0;
  late final InAppCockpitCommandExecutor _executor = root.createCommandExecutor(
    platform: options.platform,
    transportType: 'inAppTest',
    // Flutter's test binding needs an explicit frame pump for route pushes,
    // animations, lazy lists, and async state changes. Supplying these hooks
    // keeps the executor's commit/reveal logic identical to the live bridge
    // while making Dart integration tests advance the test clock correctly.
    postActionSettler: flutter.pump,
    waitTickHandler: flutter.pump,
    gestureDelay: flutter.pump,
  );

  /// Describes the live in-app commands and locator strategies available to
  /// this test. The result is generated from the same executor used by the
  /// Cockpit bridge, so platform-specific capabilities stay truthful.
  Future<CockpitCapabilities> describeCapabilities() {
    return _executor.describeCapabilities();
  }

  /// A compact report suitable for integration_test's JSON result payload.
  Map<String, Object?> get report {
    final failures = _results.where((result) => !result.success).toList();
    final performances = _currentPerformanceReports();
    return <String, Object?>{
      'commands': _results.length,
      'startup': startup.toJson(),
      if (failures.isNotEmpty) 'failures': failures.length,
      if (_results.isNotEmpty)
        'steps': _results
            .map(
              (result) => <String, Object?>{
                'id': result.commandId,
                'type': result.commandType.name,
                'ms': result.durationMs,
                if (!result.success && result.error != null)
                  'error': result.error!.code,
                if (result.artifacts.isNotEmpty)
                  'artifacts': result.artifacts
                      .map((artifact) => artifact.relativePath)
                      .toList(growable: false),
              },
            )
            .toList(growable: false),
      if (_watches.isNotEmpty)
        'watches': _watches
            .map(
              (watch) => <String, Object?>{
                'samples': watch.samples,
                'changes': watch.changes.length,
                'endedBy': watch.endedBy,
                'ms': watch.elapsed.inMilliseconds,
              },
            )
            .toList(growable: false),
      if (performances.isNotEmpty)
        'performance': performances
            .map(
              (performance) => <String, Object?>{
                if (performance.stepId != null) 'step': performance.stepId,
                'mode': performance.mode.jsonValue,
                'build': performance.buildMode,
                'summary': performance.summary.toJson(),
                'frames': performance.frames.length,
                'events': performance.events.length,
                if (performance.archive != null)
                  'stream': performance.archive!.toJson(),
                if (performance.memory != null)
                  'memory': <String, Object?>{
                    'source': performance.memory!.source,
                    'samples': performance.memory!.samples.length,
                    'peak': performance.memory!.summary.processPeakBytes,
                    'delta': performance.memory!.summary.deltaRssBytes,
                    if (performance.memory!.droppedSamples > 0)
                      'dropped': performance.memory!.droppedSamples,
                  },
                if (performance.droppedFrames > 0 ||
                    performance.droppedEvents > 0 ||
                    performance.invalidFrames > 0 ||
                    performance.invalidEvents > 0)
                  'dropped': <String, Object?>{
                    if (performance.droppedFrames > 0)
                      'frames': performance.droppedFrames,
                    if (performance.droppedEvents > 0)
                      'events': performance.droppedEvents,
                    if (performance.invalidFrames > 0)
                      'badFrames': performance.invalidFrames,
                    if (performance.invalidEvents > 0)
                      'badEvents': performance.invalidEvents,
                  },
                if (performance.timelineSource != null)
                  'source': performance.timelineSource,
                if (performance.devTools != null)
                  'devtools': <String, Object?>{
                    'state': performance.devTools!.state,
                    if (performance.devTools!.cpu != null)
                      'cpu': performance.devTools!.cpu!.sampleCount,
                    if (performance.devTools!.heap != null)
                      'heap': performance.devTools!.heap!.classes.length,
                    if (performance.devTools!.gc != null)
                      'gc': <String, Object?>{
                        'n': performance.devTools!.gc!.eventCount,
                        if (performance.devTools!.gc!.timedCount > 0)
                          'timed': performance.devTools!.gc!.timedCount,
                        if (performance.devTools!.gc!.p90PauseUs > 0)
                          'p90': performance.devTools!.gc!.p90PauseUs,
                      },
                    if (performance.devTools!.gpu != null)
                      'gpu': performance.devTools!.gpu!.events,
                    if (performance.devTools!.isolate != null)
                      'isolate': <String, Object?>{
                        if (performance.devTools!.isolate!.beforeAll.isNotEmpty)
                          'before':
                              performance.devTools!.isolate!.beforeAll.length,
                        if (performance.devTools!.isolate!.afterAll.isNotEmpty)
                          'after':
                              performance.devTools!.isolate!.afterAll.length,
                        if (performance.devTools!.isolate!.events.isNotEmpty)
                          'events':
                              performance.devTools!.isolate!.events.length,
                        if (performance.devTools!.isolate!.droppedBefore > 0 ||
                            performance.devTools!.isolate!.droppedAfter > 0 ||
                            performance.devTools!.isolate!.droppedEvents > 0)
                          'dropped': <String, Object?>{
                            if (performance.devTools!.isolate!.droppedBefore >
                                0)
                              'before':
                                  performance.devTools!.isolate!.droppedBefore,
                            if (performance.devTools!.isolate!.droppedAfter > 0)
                              'after':
                                  performance.devTools!.isolate!.droppedAfter,
                            if (performance.devTools!.isolate!.droppedEvents >
                                0)
                              'events':
                                  performance.devTools!.isolate!.droppedEvents,
                          },
                      },
                    if (performance.devTools!.timeline != null)
                      'timeline': <String, Object?>{
                        'recorder': performance.devTools!.timeline!.recorder,
                        if (performance
                            .devTools!
                            .timeline!
                            .availableStreams
                            .isNotEmpty)
                          'available': performance
                              .devTools!
                              .timeline!
                              .availableStreams
                              .length,
                        if (performance
                            .devTools!
                            .timeline!
                            .recordedStreams
                            .isNotEmpty)
                          'recorded': performance
                              .devTools!
                              .timeline!
                              .recordedStreams
                              .length,
                      },
                    if (performance.devTools!.display != null)
                      'display': <String, Object?>{
                        if (performance.devTools!.display!.refreshRateHz !=
                            null)
                          'hz': performance.devTools!.display!.refreshRateHz,
                        if (performance.devTools!.display!.frameBudgetUs !=
                            null)
                          'bud': performance.devTools!.display!.frameBudgetUs,
                      },
                    if (performance.devTools!.rebuild != null)
                      'rebuild': <String, Object?>{
                        'frames': performance.devTools!.rebuild!.frames.length,
                        'widgets': performance.devTools!.rebuild!.totals.length,
                        if (performance.devTools!.rebuild!.unresolvedLocations >
                            0)
                          'unknown': performance
                              .devTools!
                              .rebuild!
                              .unresolvedLocations,
                        if (performance.devTools!.rebuild!.droppedFrames > 0 ||
                            performance.devTools!.rebuild!.droppedEntries > 0)
                          'dropped': <String, Object?>{
                            if (performance.devTools!.rebuild!.droppedFrames >
                                0)
                              'frames':
                                  performance.devTools!.rebuild!.droppedFrames,
                            if (performance.devTools!.rebuild!.droppedEntries >
                                0)
                              'entries':
                                  performance.devTools!.rebuild!.droppedEntries,
                          },
                      },
                    if (performance.devTools!.vm != null)
                      'vm': <String, Object?>{
                        if (performance.devTools!.vm!.operatingSystem != null)
                          'os': performance.devTools!.vm!.operatingSystem,
                        if (performance.devTools!.vm!.targetCpu != null)
                          'cpu': performance.devTools!.vm!.targetCpu,
                        if (performance.devTools!.vm!.isolateCount != null)
                          'isolates': performance.devTools!.vm!.isolateCount,
                      },
                    if (performance.devTools!.vmMemory != null)
                      'vmem': <String, Object?>{
                        if (performance.devTools!.vmMemory!.before != null)
                          'before': performance
                              .devTools!
                              .vmMemory!
                              .before!
                              .root
                              .sizeBytes,
                        if (performance.devTools!.vmMemory!.after != null)
                          'after': performance
                              .devTools!
                              .vmMemory!
                              .after!
                              .root
                              .sizeBytes,
                      },
                    if (performance.devTools!.allocationTraces.isNotEmpty)
                      'alloc': performance.devTools!.allocationTraces.length,
                    if (performance.devTools!.logs.isNotEmpty ||
                        performance.devTools!.droppedLogs > 0)
                      'logs': <String, Object?>{
                        if (performance.devTools!.logs.isNotEmpty)
                          'n': performance.devTools!.logs.length,
                        if (performance.devTools!.droppedLogs > 0)
                          'dropped': performance.devTools!.droppedLogs,
                      },
                    if (performance.devTools!.debug.isNotEmpty ||
                        performance.devTools!.droppedDebug > 0)
                      'debug': <String, Object?>{
                        if (performance.devTools!.debug.isNotEmpty)
                          'n': performance.devTools!.debug.length,
                        if (performance.devTools!.droppedDebug > 0)
                          'dropped': performance.devTools!.droppedDebug,
                      },
                    if (performance.devTools!.perfetto != null)
                      'perfetto': <String, Object?>{
                        if (performance.devTools!.perfetto!.cpu != null)
                          'cpu': true,
                        if (performance.devTools!.perfetto!.timeline != null)
                          'timeline': true,
                      },
                  },
                if (performance.plugins.isNotEmpty)
                  'plugins': performance.plugins
                      .map(
                        (plugin) => <String, Object?>{
                          'id': plugin.id,
                          'state': plugin.state,
                          if (plugin.reason != null) 'why': plugin.reason,
                          if (plugin.eventCount > 0) 'n': plugin.eventCount,
                          if (plugin.spanCount > 0) 'span': plugin.spanCount,
                          if (plugin.durationUs > 0) 'dur': plugin.durationUs,
                          if (plugin.dropped > 0) 'drop': plugin.dropped,
                          if (plugin.invalid > 0) 'bad': plugin.invalid,
                          if (plugin.truncated > 0) 'trunc': plugin.truncated,
                        },
                      )
                      .toList(growable: false),
              },
            )
            .toList(growable: false),
    };
  }

  /// Refreshes archive metadata without copying any retained event arrays.
  ///
  /// A profile attaches the archive snapshot that was available when that
  /// capture ended. The writer may still be flushing at that point, so report
  /// exports resolve the current state by manifest path before rendering or
  /// serializing. This keeps an HTML/JSON export truthful after a caller
  /// explicitly closes an archive.
  List<CockpitPerformanceReport> _currentPerformanceReports() {
    if (_performances.isEmpty || _performanceArchives.isEmpty) {
      return List<CockpitPerformanceReport>.of(_performances, growable: false);
    }
    final current = <String, CockpitPerformanceArchiveInfo>{};
    for (final archive in _performanceArchives) {
      final info = archive.info;
      current[info.manifest] = info;
    }
    return <CockpitPerformanceReport>[
      for (final report in _performances)
        if (report.archive case final archived?)
          report.copyWithArchive(current[archived.manifest] ?? archived)
        else
          report,
    ];
  }

  /// Profiles one action using Flutter's engine frame timings and, when
  /// supported by the platform, the official integration-test VM timeline.
  /// Native targets also collect low-overhead process RSS samples by default;
  /// web keeps the metric unavailable instead of substituting a fake value.
  /// [sampleEvery] controls native RSS sampling frequency. [streams] and
  /// [timeline] control VM timeline collection, while [maxEvents] bounds
  /// retained VM events so long captures stay predictable in memory.
  /// [vmMemory] collects the VM Service process-memory tree before and after
  /// the action. It is independent from [memory], which samples platform RSS.
  /// [allocationClassIds] enables real VM allocation call-stack tracing for
  /// selected class ids from a previous heap profile. It is intentionally
  /// opt-in because tracing allocations changes VM profiling overhead.
  /// [perfetto] retains the VM's original Perfetto CPU/timeline payload for a
  /// complete offline export. The compact test result contains metadata only.
  /// Set [trackBuilds], [trackUserBuilds], [trackLayouts], or [trackPaints]
  /// only for diagnostic captures that need per-widget or per-render-object
  /// timeline spans. These flags add measurable tracing overhead and are
  /// restored to their previous values when the capture ends.
  /// [trackRebuilds] enables Flutter's real `Flutter.RebuiltWidgets` VM
  /// extension event stream. It retains frame-level counts and source
  /// locations, and restores the extension state after the capture. Use it
  /// when rebuild attribution is needed; it is intentionally opt-in because
  /// the framework instrumentation has measurable overhead.
  /// [maxRebuildFrames] and [maxRebuildEntries] bound rebuild retention while
  /// keeping the newest frame evidence available.
  /// [logs] and [debug] retain bounded VM Logging and Debug stream events. They
  /// are enabled by default because the VM already emits these notifications;
  /// set them to false for a capture that must exclude runtime event evidence.
  ///
  /// The complete bounded report is placed in [IntegrationTestWidgetsFlutterBinding.reportData]
  /// under `cockpit.performance.<name>`. The value returned to normal test
  /// output is the compact summary exposed by [report].
  Future<CockpitPerformanceReport> profile(
    Future<void> Function() action, {
    String name = 'performance',
    CockpitPerformanceMode mode = CockpitPerformanceMode.profile,
    List<String> streams = const <String>['all'],
    bool timeline = true,
    bool memory = true,
    bool vmMemory = true,
    bool cpu = true,
    bool heap = true,
    List<String> allocationClassIds = const <String>[],
    bool perfetto = false,
    Duration sampleEvery = const Duration(milliseconds: 100),
    int maxEvents = 200000,
    int maxCpuSamples = 50000,
    int maxHeapClasses = 200,
    int maxHeapSamples = 10000,
    bool trackBuilds = false,
    bool trackUserBuilds = false,
    bool trackLayouts = false,
    bool trackPaints = false,
    bool trackRebuilds = false,
    bool logs = true,
    bool debug = true,
    int maxRebuildFrames = 10000,
    int maxRebuildEntries = 100000,
    int maxLogs = 2000,
    int maxDebug = 2000,
    List<CockpitPerformancePlugin> plugins = const <CockpitPerformancePlugin>[],
    CockpitPerformanceArchive? archive,
    Duration? timeout,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Must not be empty.');
    }
    if (streams.isEmpty) {
      throw ArgumentError.value(streams, 'streams', 'Must not be empty.');
    }
    if (sampleEvery <= Duration.zero || sampleEvery.inMilliseconds < 1) {
      throw ArgumentError.value(
        sampleEvery,
        'sampleEvery',
        'Must be positive.',
      );
    }
    if (maxEvents < 1 || maxEvents > 200000) {
      throw ArgumentError.value(
        maxEvents,
        'maxEvents',
        'Must be between 1 and 200000.',
      );
    }
    if (maxCpuSamples < 1 || maxCpuSamples > 50000) {
      throw ArgumentError.value(
        maxCpuSamples,
        'maxCpuSamples',
        'Must be between 1 and 50000.',
      );
    }
    if (maxHeapClasses < 1 || maxHeapClasses > 1000) {
      throw ArgumentError.value(
        maxHeapClasses,
        'maxHeapClasses',
        'Must be between 1 and 1000.',
      );
    }
    if (maxHeapSamples < 1 || maxHeapSamples > 10000) {
      throw ArgumentError.value(
        maxHeapSamples,
        'maxHeapSamples',
        'Must be between 1 and 10000.',
      );
    }
    if (maxRebuildFrames < 1 || maxRebuildFrames > 10000) {
      throw ArgumentError.value(
        maxRebuildFrames,
        'maxRebuildFrames',
        'Must be between 1 and 10000.',
      );
    }
    if (maxRebuildEntries < 1 || maxRebuildEntries > 1000000) {
      throw ArgumentError.value(
        maxRebuildEntries,
        'maxRebuildEntries',
        'Must be between 1 and 1000000.',
      );
    }
    if (maxLogs < 1 || maxLogs > 100000) {
      throw ArgumentError.value(
        maxLogs,
        'maxLogs',
        'Must be between 1 and 100000.',
      );
    }
    if (maxDebug < 1 || maxDebug > 100000) {
      throw ArgumentError.value(
        maxDebug,
        'maxDebug',
        'Must be between 1 and 100000.',
      );
    }
    final normalizedAllocationClassIds = allocationClassIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedAllocationClassIds.length > 20) {
      throw ArgumentError.value(
        allocationClassIds,
        'allocationClassIds',
        'Must contain no more than 20 class ids.',
      );
    }
    final effectiveTimeout = timeout ?? options.commandTimeout;
    _validateTimeout(effectiveTimeout, name: 'timeout');
    final collector = FlutterCockpit.binding.performanceCollector;
    if (collector.isRunning) {
      throw StateError('Another performance capture is already running.');
    }
    final collectTimeline = timeline || perfetto;
    var canTraceTimeline = collectTimeline && !kIsWeb;
    if (canTraceTimeline) {
      canTraceTimeline = await _hasVmService();
    }
    final retainedTimelineEvents = <CockpitPerformanceEvent>[];
    var timelineDroppedEvents = 0;
    var timelineInvalidEvents = 0;
    var timelineNewGcCount = 0;
    var timelineOldGcCount = 0;
    dynamic timelineData;
    Timer? timelineTimer;
    Future<void>? timelinePoll;
    String? archiveCaptureId;
    CockpitPerformanceFrameListener? frameListener;
    final instrumentation = _PerformanceInstrumentation();
    final pluginCapture = FlutterCockpit.binding.performancePlugins.capture(
      additional: plugins,
      maxEvents: maxEvents,
      onEvent: archive?.addEvent,
    );
    late final CockpitDevToolsProfiler devToolsProfiler;
    Future<void> drainTimeline() async {
      if (archive == null || !canTraceTimeline) return;
      final raw = await devToolsProfiler.drainTimeline();
      if (raw.isEmpty) return;
      final parsed = _parsePerformanceTimeline(raw, maxEvents: raw.length);
      timelineInvalidEvents += parsed.invalidEvents;
      timelineNewGcCount += parsed.newGenGcCount ?? 0;
      timelineOldGcCount += parsed.oldGenGcCount ?? 0;
      for (final event in parsed.events) {
        archive.addEvent(event);
        if (retainedTimelineEvents.length < maxEvents) {
          retainedTimelineEvents.add(event);
        } else {
          timelineDroppedEvents += 1;
        }
      }
    }

    Future<void> pollTimeline() async {
      final current = timelinePoll;
      if (current != null) return current;
      final operation = drainTimeline();
      timelinePoll = operation;
      try {
        await operation;
      } finally {
        if (identical(timelinePoll, operation)) timelinePoll = null;
      }
    }

    devToolsProfiler = CockpitDevToolsProfiler(
      timeout: effectiveTimeout < const Duration(seconds: 3)
          ? effectiveTimeout
          : const Duration(seconds: 3),
      maxCpuSamples: maxCpuSamples,
      maxHeapClasses: maxHeapClasses,
      maxHeapSamples: maxHeapSamples,
      maxRebuildFrames: maxRebuildFrames,
      maxRebuildEntries: maxRebuildEntries,
      maxLogEvents: maxLogs,
      maxDebugEvents: maxDebug,
      onIsolateEvent: archive?.addIsolate,
      onLogEvent: archive?.addLog,
      onDebugEvent: archive?.addDebug,
      onHeapSample: archive?.addHeap,
    );
    try {
      await pluginCapture.start();
      instrumentation.enable(
        trackBuilds: trackBuilds,
        trackUserBuilds: trackUserBuilds,
        trackLayouts: trackLayouts,
        trackPaints: trackPaints,
      );
      collector.start(mode: mode);
      void onFrame(CockpitPerformanceFrame frame) {
        archive?.addFrame(frame);
      }

      if (archive != null) {
        frameListener = onFrame;
        collector.addFrameListener(onFrame);
        archiveCaptureId = archive.beginCapture(
          id: normalizedName,
          startedAt: collector.startedAt,
        );
      }
      pluginCapture.beginWindow();
      final memorySampler = memory
          ? createCockpitPerformanceMemorySampler(
              interval: sampleEvery,
              onSample: archive?.addMemory,
            )
          : null;
      memorySampler?.start();
      await devToolsProfiler.start(
        cpu: cpu,
        heap: heap,
        timeline: timeline || perfetto,
        vmMemory: vmMemory,
        perfetto: perfetto,
        trackRebuilds: trackRebuilds,
        logs: logs,
        debug: debug,
        allocationClassIds: normalizedAllocationClassIds,
        heapSampleEvery: sampleEvery,
        timelineStreams: List<String>.unmodifiable(streams),
        streamTimeline: archive != null && canTraceTimeline,
      );
      var timelineSource = collectTimeline
          ? kIsWeb
                ? 'unavailable:web'
                : canTraceTimeline
                ? 'vm'
                : 'unavailable:vm'
          : null;
      if (archive != null && canTraceTimeline) {
        timelineTimer = Timer.periodic(
          archive.options.pollEvery,
          (_) => unawaited(pollTimeline()),
        );
      }
      try {
        if (canTraceTimeline) {
          if (archive != null) {
            final run = action();
            try {
              await run.timeout(effectiveTimeout);
            } on TimeoutException {
              await run;
              rethrow;
            }
          } else {
            final integrationBinding =
                IntegrationTestWidgetsFlutterBinding.ensureInitialized();
            final traced = integrationBinding.traceTimeline(
              action,
              streams: List<String>.unmodifiable(streams),
            );
            try {
              timelineData = await traced.timeout(effectiveTimeout);
            } on TimeoutException {
              // Future.timeout cannot cancel the VM-service action. Wait for
              // the owned action to finish before detaching callbacks.
              await traced;
              rethrow;
            }
          }
          timelineSource = 'vm';
        } else {
          final run = action();
          try {
            await run.timeout(effectiveTimeout);
          } on TimeoutException {
            // Futures are not cancellable. Drain the owned action before
            // detaching the collector so late frames cannot leak into the next
            // profile.
            await run;
            rethrow;
          }
        }
      } finally {
        timelineTimer?.cancel();
        timelineTimer = null;
        await pollTimeline();
        collector.endWindow();
        pluginCapture.endWindow();
        final memoryReport = memorySampler?.stop();
        await devToolsProfiler.endWindow();
        final parsed = archive != null && canTraceTimeline
            ? _ParsedPerformanceTimeline(
                events: retainedTimelineEvents,
                invalidEvents: timelineInvalidEvents,
                droppedEvents: timelineDroppedEvents,
                newGenGcCount: timelineNewGcCount == 0
                    ? null
                    : timelineNewGcCount,
                oldGenGcCount: timelineOldGcCount == 0
                    ? null
                    : timelineOldGcCount,
              )
            : _parsePerformanceTimeline(timelineData, maxEvents: maxEvents);
        final pluginEvents = await pluginCapture.stop(
          maxEvents: maxEvents - parsed.events.length,
        );
        final mergedEvents = <CockpitPerformanceEvent>[
          ...parsed.events,
          ...pluginEvents,
        ]..sort((left, right) => left.timestampUs.compareTo(right.timestampUs));
        final devTools = await devToolsProfiler.finish(
          cpu: cpu,
          heap: heap,
          timeline: collectTimeline,
          vmMemory: vmMemory,
          perfetto: perfetto,
          events: mergedEvents,
        );
        final report = collector.stop(
          events: mergedEvents,
          timelineSource: timelineSource,
          stepId: normalizedName,
          newGenGcCount: parsed.newGenGcCount,
          oldGenGcCount: parsed.oldGenGcCount,
          droppedEvents: parsed.droppedEvents + pluginCapture.retentionDrops,
          invalidEvents: parsed.invalidEvents,
          memory: memoryReport,
          devTools: devTools,
          plugins: pluginCapture.stats(),
        );
        var completedReport = report;
        if (archive != null && archiveCaptureId != null) {
          archive.endCapture(archiveCaptureId, report);
          await archive.flush();
          completedReport = report.copyWithArchive(archive.info);
        }
        _performances.add(completedReport);
        final binding =
            IntegrationTestWidgetsFlutterBinding.ensureInitialized();
        final existing = binding.reportData ?? <String, dynamic>{};
        binding.reportData = <String, dynamic>{
          ...existing,
          'cockpit.performance.$normalizedName': completedReport.toJson(),
        };
      }
    } finally {
      final listener = frameListener;
      if (listener != null) collector.removeFrameListener(listener);
      instrumentation.restore();
      if (pluginCapture.isRunning) {
        await pluginCapture.stop();
      }
    }
    return _performances.last;
  }

  Future<bool> _hasVmService() async {
    try {
      final info = await developer.Service.getInfo();
      return info.serverUri != null;
    } catch (_) {
      return false;
    }
  }

  /// Executes a fully specified Cockpit command.
  Future<CockpitCommandExecution> execute(
    CockpitCommand command, {
    bool? check,
  }) async {
    final effectiveCommand = _withTimeout(command);
    final execution = await _executor.executeWithArtifacts(effectiveCommand);
    _results.add(execution.result);
    FlutterCockpit.binding.sessionController.recordCommandResult(
      effectiveCommand,
      execution.result,
    );
    if (options.pumpAfterCommand) {
      await flutter.pump();
    }
    if (check ?? options.failFast) {
      _checkSuccess(effectiveCommand, execution.result);
    }
    return execution;
  }

  Future<CockpitCommandExecution> tap(
    Object? target, {
    Offset? at,
    PointerDeviceKind device = PointerDeviceKind.touch,
    int buttons = kPrimaryButton,
    Duration? timeout,
    CockpitCapturePolicy capture = CockpitCapturePolicy.none,
  }) {
    _validateTargetOrPoint(target, at, 'tap');
    _validateOptionalOffset(at, 'at');
    _validateButtons(buttons);
    return _run(
      CockpitCommandType.tap,
      target: target,
      timeout: timeout,
      capturePolicy: capture,
      parameters: <String, Object?>{
        ..._pointerParameters(device: device, buttons: buttons),
        'x': ?at?.dx,
        'y': ?at?.dy,
      },
    );
  }

  /// Moves a mouse pointer into a target without pressing a button. This is
  /// useful for desktop/web hover menus, tooltips, and hover animations.
  Future<CockpitCommandExecution> hover(
    Object? target, {
    Offset? at,
    PointerDeviceKind device = PointerDeviceKind.mouse,
    Duration? timeout,
  }) {
    _validateTargetOrPoint(target, at, 'hover');
    _validateOptionalOffset(at, 'at');
    return _run(
      CockpitCommandType.hover,
      target: target,
      timeout: timeout,
      parameters: <String, Object?>{
        ..._pointerParameters(device: device),
        'x': ?at?.dx,
        'y': ?at?.dy,
      },
    );
  }

  /// Dispatches real mouse or trackpad wheel signals at a target position.
  ///
  /// [delta] is applied once per event. Use [steps] for a bounded sequence of
  /// wheel ticks; this keeps continuous scrolling deterministic without
  /// retaining an unbounded event stream.
  Future<CockpitCommandExecution> wheel({
    Object? target,
    required Offset delta,
    int steps = 1,
    Duration interval = Duration.zero,
    Offset? at,
    PointerDeviceKind device = PointerDeviceKind.mouse,
    Duration? timeout,
  }) {
    _validateMovement(delta, 'delta');
    if (steps < 1 || steps > 1000) {
      throw ArgumentError.value(steps, 'steps', 'Must be between 1 and 1000.');
    }
    if (interval < Duration.zero) {
      throw ArgumentError.value(interval, 'interval', 'Must not be negative.');
    }
    _validateOptionalOffset(at, 'at');
    return _run(
      CockpitCommandType.wheel,
      target: target,
      timeout: timeout,
      parameters: <String, Object?>{
        'dx': delta.dx,
        'dy': delta.dy,
        if (steps != 1) 'steps': steps,
        if (interval > Duration.zero) 'intervalMs': interval.inMilliseconds,
        'x': ?at?.dx,
        'y': ?at?.dy,
        'deviceKind': device.name,
      },
    );
  }

  Future<CockpitCommandExecution> type(
    String value, {
    required Object into,
    Duration? timeout,
  }) => _run(
    CockpitCommandType.enterText,
    target: into,
    timeout: timeout,
    parameters: <String, Object?>{'text': value},
  );

  Future<CockpitCommandExecution> clear(Object target, {Duration? timeout}) =>
      _run(CockpitCommandType.eraseText, target: target, timeout: timeout);

  /// Copies the selected or complete value from an editable target. When no
  /// target is supplied, Cockpit uses the currently focused text input.
  Future<CockpitCommandExecution> copy({Object? from, Duration? timeout}) =>
      _run(CockpitCommandType.copyText, target: from, timeout: timeout);

  /// Pastes the platform/in-app clipboard value into an editable target.
  Future<CockpitCommandExecution> paste(Object target, {Duration? timeout}) =>
      _run(CockpitCommandType.pasteText, target: target, timeout: timeout);

  /// Gives focus to an editable target without changing its value.
  Future<CockpitCommandExecution> focus(Object target, {Duration? timeout}) =>
      _run(CockpitCommandType.focusTextInput, target: target, timeout: timeout);

  /// Sets text, selection, and/or the IME composing range using the same
  /// editing path as the live Cockpit bridge. Omit [text] to change only
  /// selection or composing state.
  Future<CockpitCommandExecution> setTextEditingValue(
    Object target, {
    String? text,
    int? selectionBase,
    int? selectionExtent,
    int? composingBase,
    int? composingExtent,
    bool requestFocus = true,
    bool clearExisting = false,
    Duration? timeout,
  }) {
    if (text == null &&
        selectionBase == null &&
        selectionExtent == null &&
        composingBase == null &&
        composingExtent == null &&
        !clearExisting) {
      throw ArgumentError(
        'setTextEditingValue requires text, selection, or clearExisting.',
      );
    }
    if (selectionBase != null && selectionBase < 0) {
      throw ArgumentError.value(selectionBase, 'selectionBase');
    }
    if (selectionExtent != null && selectionExtent < 0) {
      throw ArgumentError.value(selectionExtent, 'selectionExtent');
    }
    if (composingBase != null && composingBase < 0) {
      throw ArgumentError.value(composingBase, 'composingBase');
    }
    if (composingExtent != null && composingExtent < 0) {
      throw ArgumentError.value(composingExtent, 'composingExtent');
    }
    return _run(
      CockpitCommandType.setTextEditingValue,
      target: target,
      timeout: timeout,
      parameters: <String, Object?>{
        'text': ?text,
        'selectionBase': ?selectionBase,
        'selectionExtent': ?selectionExtent,
        'composingBase': ?composingBase,
        'composingExtent': ?composingExtent,
        'requestFocus': requestFocus,
        'clearExisting': clearExisting,
      },
    );
  }

  /// Selects a UTF-16 range in an editable target.
  Future<CockpitCommandExecution> selectText(
    Object target, {
    required int start,
    required int end,
    Duration? timeout,
  }) {
    if (start < 0 || end < 0) {
      throw ArgumentError('Text selection offsets must be non-negative.');
    }
    return setTextEditingValue(
      target,
      selectionBase: start,
      selectionExtent: end,
      timeout: timeout,
    );
  }

  /// Sends a key-down event to the focused Flutter focus tree.
  Future<CockpitCommandExecution> keyDown(
    String logicalKey, {
    String? physicalKey,
    String? character,
    bool allowUnhandled = false,
    Duration? timeout,
  }) => _keyEvent(
    CockpitCommandType.sendKeyDownEvent,
    logicalKey,
    physicalKey: physicalKey,
    character: character,
    allowUnhandled: allowUnhandled,
    timeout: timeout,
  );

  /// Sends a key-up event to the focused Flutter focus tree.
  Future<CockpitCommandExecution> keyUp(
    String logicalKey, {
    String? physicalKey,
    String? character,
    bool allowUnhandled = false,
    Duration? timeout,
  }) => _keyEvent(
    CockpitCommandType.sendKeyUpEvent,
    logicalKey,
    physicalKey: physicalKey,
    character: character,
    allowUnhandled: allowUnhandled,
    timeout: timeout,
  );

  /// Sends a keyboard chord while keeping modifier keys pressed.
  ///
  /// All keys except the last are sent as key-down events, the last key is
  /// sent as a complete key event, and modifiers are released in reverse
  /// order even when one step fails. This mirrors a real shortcut such as
  /// `ControlLeft+KeyS` without requiring callers to manage pressed state.
  Future<List<CockpitCommandExecution>> hotkey(
    Iterable<String> keys, {
    Duration? timeout,
  }) async {
    final normalized = keys
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty)
        .toList(growable: false);
    if (normalized.length < 2) {
      throw ArgumentError.value(
        keys,
        'keys',
        'A hotkey requires at least one modifier and one key.',
      );
    }

    final results = <CockpitCommandExecution>[];
    final pressed = <String>[];
    try {
      for (final key in normalized.take(normalized.length - 1)) {
        final result = await _keyEvent(
          CockpitCommandType.sendKeyDownEvent,
          key,
          timeout: timeout,
          allowUnhandled: true,
          check: false,
        );
        results.add(result);
        if (!result.result.success) break;
        pressed.add(key);
      }
      if (pressed.length == normalized.length - 1) {
        results.add(
          await _keyEvent(
            CockpitCommandType.sendKeyEvent,
            normalized.last,
            timeout: timeout,
            check: false,
          ),
        );
      }
    } finally {
      for (final key in pressed.reversed) {
        results.add(
          await _keyEvent(
            CockpitCommandType.sendKeyUpEvent,
            key,
            timeout: timeout,
            allowUnhandled: true,
            check: false,
          ),
        );
      }
    }
    if (options.failFast) {
      final failed = results.where((result) => !result.result.success);
      if (failed.isNotEmpty) {
        final result = failed.first.result;
        fail(
          'Cockpit hotkey failed'
          '${result.error == null ? '' : ': ${result.error!.message}'}',
        );
      }
    }
    return List.unmodifiable(results);
  }

  Future<CockpitCommandExecution> _keyEvent(
    CockpitCommandType type,
    String logicalKey, {
    String? physicalKey,
    String? character,
    Duration? timeout,
    bool allowUnhandled = false,
    bool? check,
  }) {
    final key = logicalKey.trim();
    if (key.isEmpty) {
      throw ArgumentError.value(logicalKey, 'logicalKey');
    }
    return _run(
      type,
      timeout: timeout,
      check: check,
      parameters: <String, Object?>{
        'logicalKey': key,
        'physicalKey': ?physicalKey,
        'character': ?character,
        if (allowUnhandled) 'allowUnhandled': true,
      },
    );
  }

  /// Performs a real long-press on a resolved Flutter target.
  Future<CockpitCommandExecution> longPress(
    Object? target, {
    Duration duration = const Duration(milliseconds: 600),
    Offset? at,
    PointerDeviceKind device = PointerDeviceKind.touch,
    int buttons = kPrimaryButton,
    Duration? timeout,
  }) {
    _validateTargetOrPoint(target, at, 'longPress');
    _validateGestureDuration(duration, 'duration');
    _validateOptionalOffset(at, 'at');
    _validateButtons(buttons);
    return _run(
      CockpitCommandType.longPress,
      target: target,
      timeout: timeout,
      parameters: <String, Object?>{
        'durationMs': duration.inMilliseconds,
        ..._pointerParameters(device: device, buttons: buttons),
        'x': ?at?.dx,
        'y': ?at?.dy,
      },
    );
  }

  /// Performs a real double-tap on a resolved Flutter target.
  Future<CockpitCommandExecution> doubleTap(
    Object? target, {
    Duration interval = const Duration(milliseconds: 90),
    Offset? at,
    PointerDeviceKind device = PointerDeviceKind.touch,
    int buttons = kPrimaryButton,
    Duration? timeout,
  }) {
    _validateTargetOrPoint(target, at, 'doubleTap');
    _validateGestureDuration(interval, 'interval');
    _validateOptionalOffset(at, 'at');
    _validateButtons(buttons);
    return _run(
      CockpitCommandType.doubleTap,
      target: target,
      timeout: timeout,
      parameters: <String, Object?>{
        'intervalMs': interval.inMilliseconds,
        ..._pointerParameters(device: device, buttons: buttons),
        'x': ?at?.dx,
        'y': ?at?.dy,
      },
    );
  }

  /// Performs a real drag with hit-tested pointer events.
  Future<CockpitCommandExecution> drag({
    Object? target,
    required Offset delta,
    Offset? at,
    Duration duration = const Duration(milliseconds: 220),
    Duration? hold,
    int? moveEvents,
    PointerDeviceKind device = PointerDeviceKind.touch,
    int buttons = kPrimaryButton,
    Duration? timeout,
  }) {
    _validateTargetOrPoint(target, at, 'drag');
    _validateMovement(delta, 'delta');
    _validateOptionalOffset(at, 'at');
    _validateGestureDuration(duration, 'duration');
    if (hold != null) _validateGestureDuration(hold, 'hold');
    _validateMoveEvents(moveEvents);
    _validateButtons(buttons);
    return _run(
      CockpitCommandType.drag,
      target: target,
      timeout: timeout,
      parameters: <String, Object?>{
        'dx': delta.dx,
        'dy': delta.dy,
        'x': ?at?.dx,
        'y': ?at?.dy,
        'durationMs': duration.inMilliseconds,
        'holdDurationMs': ?hold?.inMilliseconds,
        'moveEventCount': ?moveEvents,
        ..._pointerParameters(device: device, buttons: buttons),
      },
    );
  }

  /// Performs a fling-like drag using the requested velocity profile.
  Future<CockpitCommandExecution> fling({
    Object? target,
    required Offset delta,
    required double velocity,
    Offset? at,
    Duration? duration,
    int? moveEvents,
    PointerDeviceKind device = PointerDeviceKind.touch,
    int buttons = kPrimaryButton,
    Duration? timeout,
  }) {
    _validateTargetOrPoint(target, at, 'fling');
    _validateMovement(delta, 'delta');
    _validateOptionalOffset(at, 'at');
    if (!velocity.isFinite || velocity <= 0) {
      throw ArgumentError.value(velocity, 'velocity', 'Must be positive.');
    }
    final effectiveDuration =
        duration ??
        Duration(
          milliseconds: (delta.distance / velocity * 1000).round().clamp(
            16,
            1200,
          ),
        );
    _validateGestureDuration(effectiveDuration, 'duration');
    _validateMoveEvents(moveEvents);
    _validateButtons(buttons);
    return _run(
      CockpitCommandType.fling,
      target: target,
      timeout: timeout,
      parameters: <String, Object?>{
        'dx': delta.dx,
        'dy': delta.dy,
        'velocity': velocity,
        'x': ?at?.dx,
        'y': ?at?.dy,
        'durationMs': effectiveDuration.inMilliseconds,
        'moveEventCount': ?moveEvents,
        ..._pointerParameters(device: device, buttons: buttons),
      },
    );
  }

  /// Swipes in one direction across the selected target.
  Future<CockpitCommandExecution> swipe({
    Object? target,
    required AxisDirection direction,
    double distance = 0.82,
    Duration duration = const Duration(milliseconds: 200),
    Offset? at,
    int? moveEvents,
    PointerDeviceKind device = PointerDeviceKind.touch,
    int buttons = kPrimaryButton,
    Duration? timeout,
  }) {
    _validateTargetOrPoint(target, at, 'swipe');
    _validateOptionalOffset(at, 'at');
    if (!distance.isFinite || distance < 0.15 || distance > 0.95) {
      throw ArgumentError.value(
        distance,
        'distance',
        'Must be between 0.15 and 0.95.',
      );
    }
    _validateGestureDuration(duration, 'duration');
    _validateMoveEvents(moveEvents);
    _validateButtons(buttons);
    return _run(
      CockpitCommandType.swipe,
      target: target,
      timeout: timeout,
      parameters: <String, Object?>{
        'direction': direction.name,
        'distanceFactor': distance,
        'durationMs': duration.inMilliseconds,
        'x': ?at?.dx,
        'y': ?at?.dy,
        'moveEventCount': ?moveEvents,
        ..._pointerParameters(device: device, buttons: buttons),
      },
    );
  }

  /// Performs a two-pointer pinch or spread gesture.
  Future<CockpitCommandExecution> pinch({
    Object? target,
    required double scale,
    double startSpan = 56,
    Offset? at,
    Duration duration = const Duration(milliseconds: 220),
    int? moveEvents,
    PointerDeviceKind device = PointerDeviceKind.touch,
    Duration? timeout,
  }) {
    _validateTargetOrPoint(target, at, 'pinch');
    _validateOptionalOffset(at, 'at');
    if (!scale.isFinite || scale <= 0 || scale == 1) {
      throw ArgumentError.value(
        scale,
        'scale',
        'Must be positive and different from 1.',
      );
    }
    _validatePositiveFinite(startSpan, 'startSpan');
    _validateGestureDuration(duration, 'duration');
    _validateMoveEvents(moveEvents);
    return _run(
      CockpitCommandType.pinchZoom,
      target: target,
      timeout: timeout,
      parameters: <String, Object?>{
        'scale': scale,
        'startSpan': startSpan,
        'durationMs': duration.inMilliseconds,
        'x': ?at?.dx,
        'y': ?at?.dy,
        'moveEventCount': ?moveEvents,
        ..._pointerParameters(device: device),
      },
    );
  }

  /// Rotates a target by [radians] using two pointers.
  Future<CockpitCommandExecution> rotate({
    Object? target,
    required double radians,
    double startSpan = 56,
    Offset? at,
    Duration duration = const Duration(milliseconds: 220),
    int? moveEvents,
    PointerDeviceKind device = PointerDeviceKind.touch,
    Duration? timeout,
  }) {
    _validateTargetOrPoint(target, at, 'rotate');
    _validateOptionalOffset(at, 'at');
    if (!radians.isFinite || radians == 0) {
      throw ArgumentError.value(radians, 'radians', 'Must be non-zero.');
    }
    _validatePositiveFinite(startSpan, 'startSpan');
    _validateGestureDuration(duration, 'duration');
    _validateMoveEvents(moveEvents);
    return _run(
      CockpitCommandType.rotate,
      target: target,
      timeout: timeout,
      parameters: <String, Object?>{
        'rotationRadians': radians,
        'startSpan': startSpan,
        'durationMs': duration.inMilliseconds,
        'x': ?at?.dx,
        'y': ?at?.dy,
        'moveEventCount': ?moveEvents,
        ..._pointerParameters(device: device),
      },
    );
  }

  /// Performs a one-pointer pan, optionally combined with scale and rotation.
  Future<CockpitCommandExecution> panZoom({
    Object? target,
    Offset pan = Offset.zero,
    double scale = 1,
    double rotation = 0,
    Offset? at,
    Duration duration = const Duration(milliseconds: 180),
    int? moveEvents,
    PointerDeviceKind device = PointerDeviceKind.touch,
    Duration? timeout,
  }) {
    _validateTargetOrPoint(target, at, 'panZoom');
    _validateOptionalOffset(at, 'at');
    if (!pan.dx.isFinite || !pan.dy.isFinite) {
      throw ArgumentError.value(pan, 'pan', 'Must contain finite coordinates.');
    }
    if (!scale.isFinite || scale <= 0) {
      throw ArgumentError.value(scale, 'scale', 'Must be positive.');
    }
    if (pan == Offset.zero && scale == 1 && rotation == 0) {
      throw ArgumentError('panZoom requires pan, scale, or rotation.');
    }
    if (!rotation.isFinite) {
      throw ArgumentError.value(rotation, 'rotation', 'Must be finite.');
    }
    _validateGestureDuration(duration, 'duration');
    _validateMoveEvents(moveEvents);
    return _run(
      CockpitCommandType.panZoom,
      target: target,
      timeout: timeout,
      parameters: <String, Object?>{
        'panDx': pan.dx,
        'panDy': pan.dy,
        'scale': scale,
        'rotationRadians': rotation,
        'durationMs': duration.inMilliseconds,
        'x': ?at?.dx,
        'y': ?at?.dy,
        'moveEventCount': ?moveEvents,
        ..._pointerParameters(device: device),
      },
    );
  }

  /// Executes an explicit pointer sequence. Every pointer must be released.
  Future<CockpitCommandExecution> multiTouch(
    CockpitMultiTouchSequence sequence, {
    Object? target,
    Offset? at,
    Duration? timeout,
  }) {
    _validateTargetOrPoint(target, at, 'multiTouch');
    _validateOptionalOffset(at, 'at');
    _validateMultiTouch(sequence);
    return _run(
      CockpitCommandType.multiTouch,
      target: target,
      timeout: timeout,
      parameters: <String, Object?>{
        'sequence': sequence.toJson(),
        'x': ?at?.dx,
        'y': ?at?.dy,
      },
    );
  }

  /// Moves a slider or other incrementable control forward by one step.
  Future<CockpitCommandExecution> increase(
    Object target, {
    Duration? timeout,
  }) => _run(CockpitCommandType.increase, target: target, timeout: timeout);

  /// Moves a slider or other decrementable control backward by one step.
  Future<CockpitCommandExecution> decrease(
    Object target, {
    Duration? timeout,
  }) => _run(CockpitCommandType.decrease, target: target, timeout: timeout);

  /// Reveals a target through every mounted scrollable ancestor without
  /// invoking a mutation action.
  Future<CockpitCommandExecution> showOnScreen(
    Object target, {
    Duration? timeout,
  }) => _run(CockpitCommandType.showOnScreen, target: target, timeout: timeout);

  Future<CockpitCommandExecution> press(
    CockpitTextInputAction action, {
    Object? target,
    Duration? timeout,
  }) => _run(
    CockpitCommandType.sendTextInputAction,
    target: target,
    timeout: timeout,
    parameters: <String, Object?>{'inputAction': action.name},
  );

  Future<CockpitCommandExecution> scroll(
    Object target, {
    String? direction,
    String? align,
    double? offset,
    Object? scrollLocator,
    int? maxScrolls,
    Duration? timeout,
  }) {
    final parameters = <String, Object?>{};
    if (direction != null) parameters['direction'] = direction;
    if (align != null) parameters['revealAlignment'] = align;
    if (offset != null) parameters['revealOffsetPx'] = offset;
    if (scrollLocator != null) {
      parameters['scrollLocator'] = _locator(scrollLocator)!.toJson();
    }
    if (maxScrolls != null) parameters['maxScrolls'] = maxScrolls;
    return _run(
      CockpitCommandType.scrollUntilVisible,
      target: target,
      timeout: timeout,
      parameters: parameters,
    );
  }

  Future<CockpitCommandExecution> waitForUi({
    bool network = false,
    Duration? timeout,
  }) => _run(
    network
        ? CockpitCommandType.waitForNetworkIdle
        : CockpitCommandType.waitForUiIdle,
    timeout: timeout,
  );

  /// Waits until a target is present, or absent when [absent] is true.
  Future<CockpitCommandExecution> waitFor(
    Object target, {
    bool absent = false,
    Duration? timeout,
  }) => _run(
    CockpitCommandType.waitFor,
    target: target,
    timeout: timeout,
    parameters: <String, Object?>{if (absent) 'absent': true},
  );

  /// Waits for a named route and its route-ready targets to be mounted.
  Future<CockpitCommandExecution> waitForRoute(
    String route, {
    Duration? timeout,
  }) => _run(
    CockpitCommandType.waitFor,
    target: CockpitLocator(route: route),
    timeout: timeout,
  );

  Future<CockpitCommandExecution> back({Duration? timeout}) =>
      _run(CockpitCommandType.back, timeout: timeout);

  Future<CockpitCommandExecution> dismiss({Duration? timeout}) =>
      _run(CockpitCommandType.dismiss, timeout: timeout);

  Future<CockpitCommandExecution> dismissKeyboard({Duration? timeout}) =>
      _run(CockpitCommandType.dismissKeyboard, timeout: timeout);

  Future<CockpitCommandExecution> expectVisible(
    Object target, {
    Duration? timeout,
  }) =>
      _run(CockpitCommandType.assertVisible, target: target, timeout: timeout);

  Future<CockpitCommandExecution> expectText(
    Object target,
    String value, {
    CockpitTextMatchMode match = CockpitTextMatchMode.exact,
    Duration? timeout,
  }) => _run(
    CockpitCommandType.assertText,
    target: target,
    timeout: timeout,
    parameters: <String, Object?>{
      'text': value,
      if (match != CockpitTextMatchMode.exact) 'matchMode': match.name,
    },
  );

  Future<CockpitCommandExecution> screenshot({
    String name = 'integration_test',
    CockpitCaptureProfile profile = CockpitCaptureProfile.acceptance,
    bool includeSnapshot = true,
    bool allowFallback = true,
    Duration? timeout,
  }) {
    final request = CockpitScreenshotRequest(
      reason: CockpitScreenshotReason.acceptance,
      name: name,
      includeSnapshot: includeSnapshot,
      attachToStep: true,
      profile: profile,
      allowFallback: allowFallback,
    );
    return execute(
      CockpitCommand(
        commandId: _nextId('screenshot'),
        commandType: CockpitCommandType.captureScreenshot,
        timeoutMs: _timeoutMs(timeout),
        screenshotRequest: request,
      ),
    );
  }

  CockpitSnapshot snapshot({
    CockpitSnapshotOptions options = const CockpitSnapshotOptions(),
  }) => root.snapshot(options: options);

  /// Samples the mounted surface at bounded intervals and returns only
  /// compact changes. Use this for animation checkpoints and pages whose
  /// content changes over time; it never retains a full snapshot history.
  Future<CockpitWatchResult> watch({
    String? query,
    Duration duration = const Duration(seconds: 5),
    Duration interval = const Duration(milliseconds: 200),
    int maxChanges = 64,
    Duration? quiet,
    Duration? timeout,
    CockpitSnapshotOptions options = const CockpitSnapshotOptions.baseline(),
  }) async {
    if (duration <= Duration.zero || interval <= Duration.zero) {
      throw ArgumentError('duration and interval must be positive.');
    }
    if (maxChanges < 1 || maxChanges > 1000) {
      throw ArgumentError.value(
        maxChanges,
        'maxChanges',
        'Must be between 1 and 1000.',
      );
    }
    if (quiet != null && (quiet <= Duration.zero || quiet >= duration)) {
      throw ArgumentError.value(
        quiet,
        'quiet',
        'Must be positive and shorter than duration.',
      );
    }
    final effectiveTimeout = timeout ?? this.options.commandTimeout;
    _validateTimeout(effectiveTimeout, name: 'timeout');
    if (effectiveTimeout < duration) {
      throw ArgumentError.value(
        effectiveTimeout,
        'timeout',
        'Must be at least as long as duration.',
      );
    }

    final normalizedQuery = query?.trim();
    final watchOptions = options.copyWith(
      profile: CockpitSnapshotProfile.baseline,
      query: normalizedQuery?.isEmpty == true ? null : normalizedQuery,
      clearQuery: normalizedQuery?.isEmpty == true,
      maxTargets: options.maxTargets.clamp(1, 160).toInt(),
      maxAncestorsPerTarget: 0,
      // A watch must see paint-only transitions (opacity, animated colors,
      // inherited text styles, and transforms) in addition to layout changes.
      // The projection keeps this bounded to compact style fields and emits
      // them only in deltas, so continuous UI monitoring remains cheap.
      includeStyleDetails: true,
      includeDiagnosticProperties: false,
      includeRebuildActivity: false,
      includeNetworkActivity: false,
      includeRuntimeActivity: false,
      includeAccessibilitySummary: false,
    );

    var logicalElapsed = Duration.zero;
    final wallClock = Stopwatch()..start();
    var samples = 1;
    var endedBy = 'duration';
    var lastChangeAt = Duration.zero;
    var hasChange = false;
    var previous = cockpitWatchProjection(root.snapshot(options: watchOptions));
    final changes = <CockpitWatchChange>[];

    while (logicalElapsed < duration) {
      final remainingTimeout = effectiveTimeout - wallClock.elapsed;
      if (remainingTimeout <= Duration.zero) {
        endedBy = 'timeout';
        break;
      }
      final remaining = duration - logicalElapsed;
      final step = interval < remaining ? interval : remaining;
      try {
        await flutter.pump(step).timeout(remainingTimeout);
      } on TimeoutException {
        endedBy = 'timeout';
        break;
      }
      logicalElapsed += step;
      samples += 1;
      final current = cockpitWatchProjection(
        root.snapshot(options: watchOptions),
      );
      if (jsonEncode(previous) != jsonEncode(current)) {
        hasChange = true;
        lastChangeAt = logicalElapsed;
        changes.add(cockpitWatchChange(previous, current, at: logicalElapsed));
        if (changes.length >= maxChanges) {
          endedBy = 'eventLimit';
          break;
        }
      }
      previous = current;
      if (quiet != null &&
          hasChange &&
          logicalElapsed - lastChangeAt >= quiet) {
        endedBy = 'quiet';
        break;
      }
    }
    if (endedBy == 'duration' && logicalElapsed < duration) {
      endedBy = 'timeout';
    }

    final result = CockpitWatchResult(
      samples: samples,
      changes: List.unmodifiable(changes),
      endedBy: endedBy,
      elapsed: logicalElapsed,
    );
    _watches.add(result);
    return result;
  }

  Future<CockpitCommandExecution> _run(
    CockpitCommandType type, {
    Object? target,
    Map<String, Object?> parameters = const <String, Object?>{},
    Duration? timeout,
    CockpitCapturePolicy capturePolicy = CockpitCapturePolicy.none,
    bool? check,
  }) => execute(
    CockpitCommand(
      commandId: _nextId(type.name),
      commandType: type,
      locator: _locator(target),
      parameters: parameters,
      timeoutMs: _timeoutMs(timeout),
      capturePolicy: capturePolicy,
    ),
    check: check,
  );

  Future<CockpitCommandExecution> _executeHost(CockpitCommand command) async {
    final handler = options.hostCommand;
    if (handler == null) {
      throw StateError(
        'No host command handler is configured. Pass hostCommand in '
        'CockpitTestOptions to enable native/system-plane actions.',
      );
    }
    final effectiveCommand = command.timeoutMs == null
        ? command.copyWith(timeoutMs: _nativeTimeoutMs(null))
        : _withTimeout(command);
    final timeout = Duration(milliseconds: effectiveCommand.timeoutMs!);
    final stopwatch = Stopwatch()..start();
    final execution = await handler(effectiveCommand).timeout(
      timeout,
      onTimeout: () => CockpitCommandExecution(
        result: CockpitCommandResult(
          success: false,
          commandId: effectiveCommand.commandId,
          commandType: effectiveCommand.commandType,
          durationMs: stopwatch.elapsedMilliseconds,
          error: CockpitCommandError.timeout(
            message:
                'Host command ${effectiveCommand.commandId} exceeded its '
                '${timeout.inMilliseconds}ms timeout.',
            details: <String, Object?>{
              'commandId': effectiveCommand.commandId,
              'commandType': effectiveCommand.commandType.name,
              'timeoutMs': timeout.inMilliseconds,
            },
          ),
        ),
      ),
    );
    stopwatch.stop();
    _results.add(execution.result);
    FlutterCockpit.binding.sessionController.recordCommandResult(
      effectiveCommand,
      execution.result,
    );
    if (options.pumpAfterCommand) {
      await flutter.pump();
    }
    if (options.failFast) {
      _checkSuccess(effectiveCommand, execution.result);
    }
    return execution;
  }

  CockpitCommand _withTimeout(CockpitCommand command) {
    final timeoutMs = command.timeoutMs;
    if (timeoutMs == null) {
      return command.copyWith(timeoutMs: _timeoutMs(null));
    }
    _validateTimeout(
      Duration(milliseconds: timeoutMs),
      name: 'command.timeoutMs',
    );
    return command;
  }

  CockpitLocator? _locator(Object? target) {
    if (target == null) return null;
    if (target is CockpitLocator) return target;
    if (target is String) return CockpitSelector.parse(target);
    throw ArgumentError.value(
      target,
      'target',
      'A target must be a selector String or CockpitLocator.',
    );
  }

  String _nextId(String type) => 'dart-${++_sequence}-$type';

  int _timeoutMs(Duration? timeout) {
    final effective = timeout ?? options.commandTimeout;
    _validateTimeout(effective, name: 'timeout');
    return effective.inMilliseconds;
  }

  int _nativeTimeoutMs(Duration? timeout) {
    final effective = timeout ?? options.nativeTimeout;
    _validateTimeout(effective, name: 'timeout');
    return effective.inMilliseconds;
  }

  static void _validateTimeout(Duration timeout, {required String name}) {
    if (timeout <= Duration.zero ||
        timeout > cockpitIntegrationTestMaximumTimeout) {
      throw ArgumentError.value(
        timeout,
        name,
        'Timeout must be between 1ms and '
        '${cockpitIntegrationTestMaximumTimeout.inMilliseconds}ms.',
      );
    }
  }

  void _checkSuccess(CockpitCommand command, CockpitCommandResult result) {
    if (result.success) return;
    final error = result.error;
    fail(
      'Cockpit command ${command.commandType.name} failed'
      '${error == null ? '' : ': ${error.message}'}',
    );
  }
}

/// Explicit bridge for host/device automation that cannot run inside the
/// Flutter process, such as OS dialogs, app links, and native UI actions.
final class CockpitHostTester {
  CockpitHostTester._(this._tester);

  final CockpitTester _tester;

  /// Executes a host command supplied through [CockpitTestOptions.hostCommand].
  Future<CockpitCommandExecution> execute(CockpitCommand command) =>
      _tester._executeHost(command);

  /// Runs one named system action through the configured host bridge.
  Future<CockpitCommandExecution> action(
    String name, {
    Map<String, Object?> parameters = const <String, Object?>{},
    Duration? timeout,
  }) => _tester._executeHost(
    CockpitCommand(
      commandId: _tester._nextId('system'),
      commandType: CockpitCommandType.system,
      parameters: <String, Object?>{'action': name, ...parameters},
      timeoutMs: _tester._nativeTimeoutMs(timeout),
    ),
  );
}

Map<String, Object?> _pointerParameters({
  required PointerDeviceKind device,
  int? buttons,
}) {
  final parameters = <String, Object?>{};
  if (device != PointerDeviceKind.touch) {
    parameters['deviceKind'] = device.name;
  }
  if (buttons != null && buttons != kPrimaryButton) {
    parameters['buttons'] = buttons;
  }
  return parameters;
}

void _validateTargetOrPoint(Object? target, Offset? at, String action) {
  if (target == null && at == null) {
    throw ArgumentError('$action requires a target or explicit at point.');
  }
}

void _validateButtons(int buttons) {
  if (buttons <= 0) {
    throw ArgumentError.value(buttons, 'buttons', 'Must be positive.');
  }
}

void _validateGestureDuration(Duration value, String name) {
  if (value <= Duration.zero) {
    throw ArgumentError.value(value, name, 'Must be positive.');
  }
}

void _validateMovement(Offset value, String name) {
  if (!value.dx.isFinite || !value.dy.isFinite) {
    throw ArgumentError.value(value, name, 'Must contain finite coordinates.');
  }
  if (value == Offset.zero) {
    throw ArgumentError.value(value, name, 'Must not be zero.');
  }
}

void _validateOptionalOffset(Offset? value, String name) {
  if (value != null && (!value.dx.isFinite || !value.dy.isFinite)) {
    throw ArgumentError.value(value, name, 'Must contain finite coordinates.');
  }
}

void _validatePositiveFinite(double value, String name) {
  if (!value.isFinite || value <= 0) {
    throw ArgumentError.value(value, name, 'Must be positive and finite.');
  }
}

void _validateMoveEvents(int? value) {
  if (value != null && (value < 0 || value > 10000)) {
    throw ArgumentError.value(
      value,
      'moveEvents',
      'Must be between 0 and 10000.',
    );
  }
}

void _validateMultiTouch(CockpitMultiTouchSequence sequence) {
  if (sequence.steps.isEmpty) {
    throw ArgumentError.value(
      sequence,
      'sequence',
      'Must contain at least one step.',
    );
  }
  if (sequence.steps.length > 10000) {
    throw ArgumentError.value(
      sequence.steps.length,
      'sequence',
      'Must contain no more than 10000 steps.',
    );
  }
  final active = <int>{};
  for (final step in sequence.steps) {
    if (step.pointer <= 0) {
      throw ArgumentError.value(
        step.pointer,
        'sequence',
        'Pointer IDs must be positive.',
      );
    }
    if (step.atMs < 0 || !step.dx.isFinite || !step.dy.isFinite) {
      throw ArgumentError.value(
        step,
        'sequence',
        'Steps require non-negative timestamps and finite coordinates.',
      );
    }
    switch (step.phase) {
      case CockpitMultiTouchPhase.down:
        if (!active.add(step.pointer)) {
          throw ArgumentError.value(
            step.pointer,
            'sequence',
            'A pointer cannot go down twice without an up event.',
          );
        }
      case CockpitMultiTouchPhase.move:
        if (!active.contains(step.pointer)) {
          throw ArgumentError.value(
            step.pointer,
            'sequence',
            'A pointer must be down before it moves.',
          );
        }
      case CockpitMultiTouchPhase.up:
        if (!active.remove(step.pointer)) {
          throw ArgumentError.value(
            step.pointer,
            'sequence',
            'A pointer must be down before it is released.',
          );
        }
    }
  }
  if (active.isNotEmpty) {
    throw ArgumentError.value(
      sequence,
      'sequence',
      'Every pointer must end with an up event.',
    );
  }
}

/// Temporarily enables the same per-build/layout/paint timeline switches that
/// Flutter DevTools exposes. The switches are process-global debug state, so
/// every capture must restore the exact values it found on entry.
final class _PerformanceInstrumentation {
  final bool _builds = debugProfileBuildsEnabled;
  final bool _userBuilds = debugProfileBuildsEnabledUserWidgets;
  final bool _layouts = debugProfileLayoutsEnabled;
  final bool _paints = debugProfilePaintsEnabled;
  var _enabled = false;

  void enable({
    required bool trackBuilds,
    required bool trackUserBuilds,
    required bool trackLayouts,
    required bool trackPaints,
  }) {
    if (kReleaseMode) return;
    if (trackBuilds) debugProfileBuildsEnabled = true;
    if (trackUserBuilds) debugProfileBuildsEnabledUserWidgets = true;
    if (trackLayouts) debugProfileLayoutsEnabled = true;
    if (trackPaints) debugProfilePaintsEnabled = true;
    _enabled = trackBuilds || trackUserBuilds || trackLayouts || trackPaints;
  }

  void restore() {
    if (!_enabled) return;
    debugProfileBuildsEnabled = _builds;
    debugProfileBuildsEnabledUserWidgets = _userBuilds;
    debugProfileLayoutsEnabled = _layouts;
    debugProfilePaintsEnabled = _paints;
    _enabled = false;
  }
}

_ParsedPerformanceTimeline _parsePerformanceTimeline(
  dynamic timeline, {
  int maxEvents = 200000,
}) {
  if (timeline == null) {
    return const _ParsedPerformanceTimeline();
  }
  final Object? rawEvents;
  try {
    rawEvents = (timeline as dynamic).traceEvents;
  } catch (_) {
    return const _ParsedPerformanceTimeline(invalidEvents: 1);
  }
  if (rawEvents == null) {
    return const _ParsedPerformanceTimeline();
  }
  if (rawEvents is! Iterable) {
    return const _ParsedPerformanceTimeline(invalidEvents: 1);
  }
  final events = <CockpitPerformanceEvent>[];
  var invalid = 0;
  var dropped = 0;
  for (final rawEvent in rawEvents) {
    final Object? json;
    try {
      json = rawEvent is Map ? rawEvent : (rawEvent as dynamic).json;
    } catch (_) {
      invalid += 1;
      continue;
    }
    if (json is! Map) {
      invalid += 1;
      continue;
    }
    final name = _timelineString(json['name']);
    final category = _timelineCategory(json['cat']);
    final timestampUs = _timelineInt(json['ts']);
    final durationUs = json['dur'] == null ? 0 : _timelineInt(json['dur']);
    final processId = json['pid'] == null ? null : _timelineInt(json['pid']);
    final threadId = json['tid'] == null ? null : _timelineInt(json['tid']);
    final eventId = _timelineId(json['id']);
    final scope = _timelineString(json['s']);
    final bindId = _timelineId(json['bind_id'] ?? json['bindId']);
    if (name == null ||
        category == null ||
        timestampUs == null ||
        durationUs == null ||
        durationUs < 0 ||
        processId == null && json['pid'] != null ||
        threadId == null && json['tid'] != null ||
        eventId == null && json['id'] != null ||
        scope == null && json['s'] != null ||
        bindId == null && (json['bind_id'] != null || json['bindId'] != null)) {
      invalid += 1;
      continue;
    }
    final args = json['args'];
    if (args is Map && !_isJsonValue(args)) {
      invalid += 1;
      continue;
    }
    if (events.length >= maxEvents) {
      dropped += 1;
      continue;
    }
    events.add(
      CockpitPerformanceEvent(
        name: name,
        category: category,
        timestampUs: timestampUs,
        durationUs: durationUs,
        phase: _timelineString(json['ph']),
        processId: processId,
        threadId: threadId,
        eventId: eventId,
        scope: scope,
        bindId: bindId,
        args: args is Map
            ? <String, Object?>{
                for (final entry in args.entries)
                  if (entry.key is String && _isJsonValue(entry.value))
                    entry.key as String: entry.value,
              }
            : const <String, Object?>{},
      ),
    );
  }
  var newGc = 0;
  var oldGc = 0;
  visitCockpitTimelineMeasurements(events, (event, _, _) {
    final kind = cockpitGcEventKind(event);
    if (kind == 'new') newGc += 1;
    if (kind == 'old') oldGc += 1;
  });
  return _ParsedPerformanceTimeline(
    events: events,
    invalidEvents: invalid,
    droppedEvents: dropped,
    newGenGcCount: newGc == 0 ? null : newGc,
    oldGenGcCount: oldGc == 0 ? null : oldGc,
  );
}

String? _timelineString(Object? value) {
  if (value is String && value.isNotEmpty) return value;
  return null;
}

String? _timelineCategory(Object? value) {
  if (value is String && value.isNotEmpty) return value;
  if (value is List) {
    final values = value.whereType<String>().where((value) => value.isNotEmpty);
    return values.isEmpty ? null : values.first;
  }
  return null;
}

int? _timelineInt(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.round()) {
    return value.toInt();
  }
  return null;
}

String? _timelineId(Object? value) {
  if (value is String && value.isNotEmpty) return value;
  if (value is int) return value.toString();
  if (value is num && value.isFinite && value == value.round()) {
    return value.toInt().toString();
  }
  return null;
}

bool _isJsonValue(Object? value) {
  if (value == null || value is String || value is bool) {
    return true;
  }
  if (value is num) return value.isFinite;
  if (value is List) return value.every(_isJsonValue);
  if (value is Map) {
    return value.entries.every(
      (entry) => entry.key is String && _isJsonValue(entry.value),
    );
  }
  return false;
}

final class _ParsedPerformanceTimeline {
  const _ParsedPerformanceTimeline({
    this.events = const <CockpitPerformanceEvent>[],
    this.invalidEvents = 0,
    this.droppedEvents = 0,
    this.newGenGcCount,
    this.oldGenGcCount,
  });

  final List<CockpitPerformanceEvent> events;
  final int invalidEvents;
  final int droppedEvents;
  final int? newGenGcCount;
  final int? oldGenGcCount;
}
