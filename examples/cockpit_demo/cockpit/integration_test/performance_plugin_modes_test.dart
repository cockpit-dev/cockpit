import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit_demo/src/cockpit_demo_app.dart';
import 'package:cockpit_demo/src/data/cockpit_demo_database.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:drift/drift.dart'
    show TableUpdate, TableUpdateQuery, UpdateKind;
import 'package:flutter/foundation.dart';
import 'package:flutter_cockpit_test/flutter_cockpit_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const String dbWatcherPluginId = 'demo-db-watcher';
const String milestonePluginId = 'demo-ui-milestones';
const String notes = 'Streaming and in-memory captures must agree.';

/// Database created by the app builder and shared with the capture plugins.
CockpitDemoDatabase? appDatabase;

/// Sink installed by [milestonePlugin] for the currently running capture.
CockpitPerformanceSink? milestoneSink;

/// Emits an event whenever drift persists a task row, mirroring how a
/// repository observer would instrument the business layer of a real app.
final class DatabaseActivityPlugin extends CockpitPerformancePlugin {
  DatabaseActivityPlugin(this.database)
    : super(id: dbWatcherPluginId, version: '1.0.0');

  final CockpitDemoDatabase database;

  @override
  CockpitPerformancePluginRun open(CockpitPerformancePluginContext context) =>
      _DatabaseActivityRun(database, context);
}

final class _DatabaseActivityRun extends CockpitPerformancePluginRun {
  _DatabaseActivityRun(this.database, this.context);

  final CockpitDemoDatabase database;
  final CockpitPerformancePluginContext context;
  StreamSubscription<Set<TableUpdate>>? subscription;

  @override
  Future<void> start() async {
    subscription = database
        .tableUpdates(TableUpdateQuery.onTableName('tasks'))
        .listen((updates) {
          if (updates.isEmpty) return;
          final sink = context.sink;
          sink.instant(
            'demo.db.tasks.changed',
            category: 'business',
            args: <String, Object?>{
              'kinds': <String>[
                for (final TableUpdate update in updates)
                  if (update.kind case final UpdateKind nonNullKind)
                    nonNullKind.name,
              ],
            },
          );
          sink.counter('demo.db.task_change_batches', 1, category: 'business');
        });
  }

  @override
  Future<void> stop(CockpitPerformancePluginStats stats) async {
    await subscription?.cancel();
    subscription = null;
  }
}

/// Milestone plugin used by both captures; the definition is reused, capture
/// state lives in the per-capture sink handed to [setup].
final CockpitPerformancePlugin milestonePlugin =
    CockpitPerformancePlugin.callbacks(
      id: milestonePluginId,
      version: '1.0.0',
      setup: (CockpitPerformancePluginContext context) {
        milestoneSink = context.sink;
      },
    );

/// Runs the complex editor workflow with plugin milestones interleaved.
///
/// [taskTitle] must be unique across captures so inbox lookups stay
/// unambiguous.
Future<void> runComplexFlow(CockpitTester cockpit, String taskTitle) async {
  final CockpitPerformanceSink sink = milestoneSink!;
  await cockpit.expectVisible('New task');

  await sink.trace('ui.open-editor', () async {
    await cockpit.tap('New task');
    await cockpit.waitForRoute('/editor');
  }, category: 'business');
  sink.instant('ui.editor.opened', category: 'business');

  await cockpit.type(taskTitle, into: 'Task title');
  await cockpit.type(notes, into: 'Notes');
  sink.counter('ui.notes.characters', notes.length, category: 'business');

  await cockpit.scroll('HIGH', align: 'center');
  await cockpit.tap('HIGH');
  await cockpit.scroll('Today', align: 'center');
  await cockpit.tap('Today');

  await cockpit.scroll('Create tag', align: 'center');
  await cockpit.tap('Create tag');
  await cockpit.type('Instrumented', into: 'Tag name');
  await cockpit.press(CockpitTextInputAction.done, target: 'Tag name');
  await cockpit.scroll('Save task', align: 'center');

  final int pinchStartUs = sink.nowUs;
  await sink.trace(
    'ui.save-task',
    () => cockpit.tap('Save task'),
    category: 'business',
  );
  await cockpit.waitForRoute('/inbox');
  await cockpit.expectVisible(taskTitle);
  sink.span(
    'ui.task.saved',
    startUs: pinchStartUs,
    endUs: sink.nowUs,
    category: 'business',
    args: <String, Object?>{'title': taskTitle},
  );

  await cockpit.tap('Dismiss latest update');

  await cockpit.scroll('Planning surface', align: 'center');
  await cockpit.pinch(target: '@planning-surface-gesture', scale: 1.2);
  await cockpit.tap('Reset');

  const String taskAction = '[type="TaskListItem"] >> [type="InkWell"]';
  await cockpit.scroll(taskAction, align: 'center');
  await cockpit.longPress(taskAction);
  await cockpit.expectVisible('1 selected');
  await cockpit.tap('Priority');
  await cockpit.tap('Urgent priority');
  await cockpit.waitForUi();
}

/// Asserts the plugin telemetry contract shared by both capture modes.
void expectPluginTelemetry(CockpitPerformanceReport report, String taskTitle) {
  final CockpitPerformancePluginStats dbStats = report.plugins.singleWhere(
    (CockpitPerformancePluginStats stats) => stats.id == dbWatcherPluginId,
  );
  final CockpitPerformancePluginStats uiStats = report.plugins.singleWhere(
    (CockpitPerformancePluginStats stats) => stats.id == milestonePluginId,
  );
  expect(dbStats.state, 'available');
  expect(uiStats.state, 'available');
  expect(dbStats.dropped + dbStats.invalid, 0);
  expect(uiStats.dropped + uiStats.invalid, 0);
  expect(dbStats.eventCount, greaterThan(0));
  expect(uiStats.instantCount, greaterThan(0));
  expect(uiStats.spanCount, greaterThan(0));
  expect(uiStats.counterCount, greaterThan(0));

  final List<CockpitPerformanceEvent> dbEvents = report.events
      .where(
        (CockpitPerformanceEvent event) => event.source == dbWatcherPluginId,
      )
      .toList(growable: false);
  final List<CockpitPerformanceEvent> uiEvents = report.events
      .where(
        (CockpitPerformanceEvent event) => event.source == milestonePluginId,
      )
      .toList(growable: false);
  expect(dbEvents, isNotEmpty);
  expect(uiEvents, isNotEmpty);
  expect(
    dbEvents.every(
      (CockpitPerformanceEvent event) =>
          event.phase == 'i' || event.phase == 'C',
    ),
    isTrue,
  );
  expect(
    uiEvents.any(
      (CockpitPerformanceEvent event) =>
          event.phase == 'X' && event.name == 'ui.save-task',
    ),
    isTrue,
  );
  expect(
    uiEvents.any(
      (CockpitPerformanceEvent event) =>
          event.phase == 'X' &&
          event.name == 'ui.task.saved' &&
          event.args['title'] == taskTitle,
    ),
    isTrue,
  );
}

/// Validates the canonical single-report JSON export of one capture.
Future<Map<String, Object?>> expectBundleExport(
  CockpitTester cockpit, {
  required String title,
  required String step,
  required bool streamed,
  String? Function(Map<String, Object?> report)? extraReportChecks,
}) async {
  // A device integration-test process may have `/` as its current directory;
  // use its writable temp area instead of relying on a relative `build/` path.
  final exportPath =
      '${Directory.systemTemp.path}/cockpit-${title.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '-')}-$pid-${DateTime.now().microsecondsSinceEpoch}.json';
  final String writtenPath = await cockpit.exportPerformanceJson(
    title: title,
    path: exportPath,
  );
  final Map<String, Object?> bundle =
      jsonDecode(File(writtenPath).readAsStringSync()) as Map<String, Object?>;
  final List<Map<String, Object?>> bundleReports =
      (bundle['reports']! as List<Object?>).cast<Map<String, Object?>>();
  expect(bundleReports, hasLength(1));
  final Map<String, Object?> report =
      bundleReports.single['report']! as Map<String, Object?>;
  expect(report['schema'], 'cockpit.performance/v2');
  expect(report['step'], step);
  expect(report.containsKey('stream'), streamed);
  final List<String> pluginIds = (report['plugins']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .map((Map<String, Object?> plugin) => plugin['id']! as String)
      .toList(growable: false);
  expect(
    pluginIds,
    containsAll(<String>[dbWatcherPluginId, milestonePluginId]),
  );
  expect(
    (report['events']! as List<Object?>).cast<Map<String, Object?>>().any(
      (Map<String, Object?> event) => event['src'] == dbWatcherPluginId,
    ),
    isTrue,
  );
  final Object? extraError = extraReportChecks?.call(report);
  expect(extraError, isNull, reason: extraError?.toString());
  return report;
}

void main() {
  final IntegrationTestWidgetsFlutterBinding binding =
      IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  cockpitTestWidgets(
    'captures plugin telemetry in memory and exports the canonical bundle',
    app: () {
      appDatabase = CockpitDemoDatabase.inMemory();
      addTearDown(appDatabase!.close);
      return CockpitDemoApp(database: appDatabase!);
    },
    body: (CockpitTester cockpit) async {
      final taskTitle = 'Plugin instrumented flow - memory';
      final CockpitPerformanceReport report = await cockpit.profile(
        () => runComplexFlow(cockpit, taskTitle),
        name: 'plugin-inmemory',
        streams: const <String>['Dart', 'GC', 'Embedder'],
        plugins: <CockpitPerformancePlugin>[
          DatabaseActivityPlugin(appDatabase!),
          milestonePlugin,
        ],
        timeout: const Duration(minutes: 2),
      );

      expect(report.stepId, 'plugin-inmemory');
      expect(report.durationUs, greaterThan(0));
      expect(report.frames, isNotEmpty);
      expect(report.archive, isNull);
      expectPluginTelemetry(report, taskTitle);

      await expectBundleExport(
        cockpit,
        title: 'plugin-modes-memory',
        step: 'plugin-inmemory',
        streamed: false,
      );
      expect(
        binding.reportData?['cockpit.performance.plugin-inmemory'],
        isA<Map<Object?, Object?>>(),
      );
    },
  );

  cockpitTestWidgets(
    'streams plugin telemetry into a JSONL archive with a valid manifest',
    app: () {
      appDatabase = CockpitDemoDatabase.inMemory();
      addTearDown(appDatabase!.close);
      return CockpitDemoApp(database: appDatabase!);
    },
    body: (CockpitTester cockpit) async {
      final taskTitle = 'Plugin instrumented flow - streamed';
      final CockpitPerformanceArchive
      archive = await cockpit.openPerformanceArchive(
        directory:
            '${Directory.systemTemp.path}/cockpit-plugin-modes-$pid-${DateTime.now().microsecondsSinceEpoch}',
        name: 'plugin-modes',
      );
      final CockpitPerformanceReport report = await cockpit.profile(
        () => runComplexFlow(cockpit, taskTitle),
        name: 'plugin-streamed',
        streams: const <String>['Dart', 'GC', 'Embedder'],
        plugins: <CockpitPerformancePlugin>[
          DatabaseActivityPlugin(appDatabase!),
          milestonePlugin,
        ],
        archive: archive,
        // Keep the in-memory report deliberately small so the streamed path
        // proves plugin events are retained independently of a full VM
        // timeline. The archive still contains the complete event stream.
        maxEvents: 32,
        timeout: const Duration(minutes: 2),
      );

      expect(report.stepId, 'plugin-streamed');
      expect(report.archive, isNotNull);
      expect(report.events.length, lessThanOrEqualTo(32));
      final CockpitPerformanceArchiveInfo activeInfo = report.archive!;
      expect(activeInfo.errors, 0);
      expect(activeInfo.events, greaterThan(0));
      expect(activeInfo.frames, greaterThan(0));
      expectPluginTelemetry(report, taskTitle);

      final CockpitPerformanceArchiveInfo closedInfo = await archive.close();
      expect(closedInfo.state, 'done');
      expect(closedInfo.errors, 0);
      expect(closedInfo.dropped, 0);
      expect(closedInfo.chunks, isNotEmpty);
      debugPrint('PLUGIN_MODES_MANIFEST=${closedInfo.manifest}');

      final Map<String, Object?> manifest =
          jsonDecode(File(closedInfo.manifest).readAsStringSync())
              as Map<String, Object?>;
      expect(manifest['schema'], 'cockpit.performance.stream/v1');
      expect(manifest['format'], 'jsonl');
      expect(manifest['mode'], 'lossless');
      expect(manifest['state'], 'done');
      expect(manifest['records'], closedInfo.records);
      expect(manifest['events'], closedInfo.events);
      expect(manifest['frames'], closedInfo.frames);
      expect(manifest['bytes'], closedInfo.bytes);
      final List<String> chunkPaths = (manifest['chunks']! as List<Object?>)
          .cast<String>()
          .map(
            (path) => File(path).isAbsolute
                ? File(path).absolute.path
                : File(
                    '${File(closedInfo.manifest).parent.path}/$path',
                  ).absolute.path,
          )
          .toList(growable: false);
      expect(
        chunkPaths,
        closedInfo.chunks
            .map((path) => File(path).absolute.path)
            .toList(growable: false),
      );

      final Map<String, int> kindCounts = <String, int>{};
      final List<Map<String, Object?>> streamEvents = <Map<String, Object?>>[];
      final List<Map<String, Object?>> captureStarts = <Map<String, Object?>>[];
      final List<Map<String, Object?>> captureEnds = <Map<String, Object?>>[];
      var recordCount = 0;
      for (final String path in chunkPaths) {
        for (final String line in File(path).readAsLinesSync()) {
          if (line.trim().isEmpty) continue;
          final Map<String, Object?> record =
              jsonDecode(line) as Map<String, Object?>;
          final String kind = record['q']! as String;
          kindCounts[kind] = (kindCounts[kind] ?? 0) + 1;
          recordCount += 1;
          switch (kind) {
            case 'e':
              streamEvents.add(record);
            case 's':
              captureStarts.add(record);
            case 'x':
              captureEnds.add(record);
          }
        }
      }
      expect(recordCount, closedInfo.records);
      expect(kindCounts['e'], closedInfo.events);
      expect(kindCounts['f'], closedInfo.frames);
      expect(
        kindCounts.keys,
        everyElement(
          isIn(const <String>['s', 'e', 'f', 'm', 'h', 'i', 'l', 'd', 'x']),
        ),
      );
      expect(captureStarts, hasLength(1));
      expect(captureStarts.single['id'], 'plugin-streamed');
      expect(captureEnds, hasLength(1));
      final Map<String, Object?> endRecord = captureEnds.single;
      expect(endRecord['id'], 'plugin-streamed');
      expect(endRecord['step'], 'plugin-streamed');
      expect(endRecord['build'], report.buildMode);
      expect(endRecord['mode'], report.mode.jsonValue);
      expect(
        (endRecord['retained']! as Map<String, Object?>)['events'],
        report.events.length,
      );
      expect(
        (endRecord['retained']! as Map<String, Object?>)['frames'],
        report.frames.length,
      );
      expect(
        streamEvents.any(
          (Map<String, Object?> event) => event['src'] == dbWatcherPluginId,
        ),
        isTrue,
      );
      expect(
        streamEvents.any(
          (Map<String, Object?> event) =>
              event['src'] == milestonePluginId &&
              event['n'] == 'ui.save-task' &&
              event['p'] == 'X',
        ),
        isTrue,
      );

      // Regression guard for the streaming timeline parser: VM timeline
      // events must reach the archive, not only plugin-sourced events.
      if (report.timelineSource == 'vm') {
        final int pluginStreamed = streamEvents
            .where((Map<String, Object?> event) => event['src'] != null)
            .length;
        expect(streamEvents.length - pluginStreamed, greaterThan(0));
        expect(
          report.summary.toJson()['gc'],
          isNotNull,
          reason: 'streamed capture must derive GC counts from the timeline',
        );
      }

      final Map<String, Object?> exported = await expectBundleExport(
        cockpit,
        title: 'plugin-modes-streamed',
        step: 'plugin-streamed',
        streamed: true,
        extraReportChecks: (Map<String, Object?> reportJson) {
          final Map<String, Object?> streamJson =
              reportJson['stream']! as Map<String, Object?>;
          return streamJson['state'] == 'done' &&
                  streamJson['records'] == closedInfo.records &&
                  streamJson['events'] == closedInfo.events
              ? null
              : 'stream metadata mismatch: $streamJson';
        },
      );
      expect(exported, isNotNull);
      expect(
        binding.reportData?['cockpit.performance.plugin-streamed'],
        isA<Map<Object?, Object?>>(),
      );
    },
  );
}
