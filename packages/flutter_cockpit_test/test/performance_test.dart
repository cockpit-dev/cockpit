import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_cockpit_test/flutter_cockpit_test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_cockpit_test/src/cockpit_devtools_profiler.dart';

void main() {
  test(
    'registered plugins emit attributable bounded timeline events',
    () async {
      late CockpitPerformanceSink sink;
      final registry = CockpitPerformancePluginRegistry(
        plugins: <CockpitPerformancePlugin>[
          CockpitPerformancePlugin.callbacks(
            id: 'checkout-aop',
            version: '1.0.0',
            setup: (context) {
              sink = context.sink;
            },
          ),
        ],
      );
      final capture = registry.capture();
      await capture.start();
      capture.beginWindow();
      sink.instant(
        'checkout.open',
        category: 'business',
        location: const CockpitPerformanceLocation(
          uri: 'package:checkout/checkout.dart',
          line: 42,
        ),
      );
      final span = sink.begin('checkout.fetch', category: 'network');
      span.end(args: const <String, Object?>{'status': 200});
      sink.counter('checkout.items', 3, category: 'business');
      final events = await capture.stop();
      final stats = capture.stats().single;

      expect(events, hasLength(3));
      expect(events.every((event) => event.source == 'checkout-aop'), isTrue);
      expect(events.first.uri, 'package:checkout/checkout.dart');
      expect(events[1].phase, 'X');
      expect(events[1].durationUs, greaterThanOrEqualTo(0));
      expect(events[2].phase, 'C');
      expect(stats.eventCount, 3);
      expect(stats.spanCount, 1);
      expect(stats.instantCount, 1);
      expect(stats.counterCount, 1);
      expect(stats.categories['business'], 2);
      expect(stats.categories['network'], 1);
    },
  );

  test(
    'subclasses receive an isolated stateful run for each capture',
    () async {
      final plugin = _StatefulPlugin();
      final registry = CockpitPerformancePluginRegistry(
        plugins: <CockpitPerformancePlugin>[plugin],
      );

      final first = registry.capture();
      await first.start();
      first.beginWindow();
      _firstSink(plugin).instant('first.capture');
      await first.stop();

      final second = registry.capture();
      await second.start();
      second.beginWindow();
      _firstSink(plugin).instant('second.capture');
      await second.stop();

      expect(plugin.runs, hasLength(2));
      expect(plugin.runs[0], isNot(same(plugin.runs[1])));
      expect(plugin.runs[0].stopped, isTrue);
      expect(plugin.runs[1].stopped, isTrue);
    },
  );

  test('plugin failures do not block capture and are reported', () async {
    final registry = CockpitPerformancePluginRegistry(
      plugins: <CockpitPerformancePlugin>[
        CockpitPerformancePlugin.callbacks(
          id: 'broken',
          setup: (_) => throw StateError('instrumentation unavailable'),
        ),
      ],
    );
    final capture = registry.capture();
    await capture.start();
    capture.beginWindow();
    final events = await capture.stop();
    final stats = capture.stats().single;
    expect(events, isEmpty);
    expect(stats.state, 'failed');
    expect(stats.reason, contains('instrumentation unavailable'));
  });

  test(
    'plugin lifecycle is bounded and cleanup is attempted after startup failure',
    () async {
      final cleanup = Completer<void>();
      final registry = CockpitPerformancePluginRegistry(
        plugins: <CockpitPerformancePlugin>[
          CockpitPerformancePlugin.callbacks(
            id: 'slow',
            setup: (_) => Completer<void>().future,
            cleanup: (_) => cleanup.complete(),
            options: const CockpitPerformancePluginOptions(
              lifecycleTimeout: Duration(milliseconds: 1),
            ),
          ),
        ],
      );
      final capture = registry.capture();
      await capture.start();
      expect(capture.stats().single.state, 'failed');
      await capture.stop();
      expect(cleanup.isCompleted, isTrue);
      expect(
        capture.stats().single.reason,
        contains('Plugin lifecycle exceeded'),
      );
    },
  );

  test(
    'global plugin retention is enforced while events are recorded',
    () async {
      late CockpitPerformanceSink sink;
      final capture = CockpitPerformancePluginRegistry(
        plugins: <CockpitPerformancePlugin>[
          CockpitPerformancePlugin.callbacks(
            id: 'bounded-live',
            setup: (context) => sink = context.sink,
          ),
        ],
      ).capture(maxEvents: 1);
      await capture.start();
      capture.beginWindow();
      sink.instant('first');
      sink.instant('second');
      final events = await capture.stop();
      expect(events, hasLength(1));
      expect(capture.stats().single.eventCount, 1);
      expect(capture.stats().single.dropped, 1);
    },
  );

  test(
    'plugin policy is snapshotted and invalid payloads are rejected',
    () async {
      final categories = <String>{'business'};
      final plugin = CockpitPerformancePlugin.callbacks(
        id: 'bounded',
        setup: (_) {},
        options: CockpitPerformancePluginOptions(categories: categories),
      );
      categories.add('network');
      expect(plugin.options.categories, <String>{'business'});

      late CockpitPerformanceSink sink;
      final capture = CockpitPerformancePluginRegistry(
        plugins: <CockpitPerformancePlugin>[
          CockpitPerformancePlugin.callbacks(
            id: 'payload',
            setup: (context) => sink = context.sink,
          ),
        ],
      ).capture();
      await capture.start();
      capture.beginWindow();
      sink.instant(
        'invalid',
        args: <String, Object?>{'value': double.infinity},
      );
      sink.instant(
        'invalid-key',
        args: <String, Object?>{
          'nested': <Object?, Object?>{1: 'not a JSON object key'},
        },
      );
      final events = await capture.stop();
      expect(events, isEmpty);
      expect(capture.stats().single.invalid, 2);
    },
  );

  test('global plugin retention keeps events and stats consistent', () async {
    late CockpitPerformanceSink sink;
    final capture = CockpitPerformancePluginRegistry(
      plugins: <CockpitPerformancePlugin>[
        CockpitPerformancePlugin.callbacks(
          id: 'bounded',
          setup: (context) => sink = context.sink,
        ),
      ],
    ).capture();
    await capture.start();
    capture.beginWindow();
    sink.instant('first');
    sink.instant('second');
    final events = await capture.stop(maxEvents: 1);
    final stats = capture.stats().single;
    expect(events, hasLength(1));
    expect(stats.eventCount, 1);
    expect(stats.instantCount, 1);
    expect(stats.dropped, 1);
    expect(capture.retentionDrops, 1);
  });

  test('VM event retention limits are explicit and bounded', () {
    expect(() => CockpitDevToolsProfiler(maxLogEvents: 0), throwsArgumentError);
    expect(
      () => CockpitDevToolsProfiler(maxDebugEvents: 100001),
      throwsArgumentError,
    );
  });

  test('profiler derives GC pauses from completed timeline spans', () async {
    final profile = await CockpitDevToolsProfiler().finish(
      cpu: false,
      heap: false,
      timeline: false,
      vmMemory: false,
      perfetto: false,
      events: <CockpitPerformanceEvent>[
        CockpitPerformanceEvent(
          name: 'CollectNewGeneration',
          category: 'GC',
          timestampUs: 100,
          durationUs: 0,
          phase: 'B',
        ),
        CockpitPerformanceEvent(
          name: 'CollectNewGeneration',
          category: 'GC',
          timestampUs: 260,
          durationUs: 0,
          phase: 'E',
        ),
      ],
    );

    expect(profile, isNotNull);
    expect(profile!.gc!.eventCount, 1);
    expect(profile.gc!.timedCount, 1);
    expect(profile.gc!.totalPauseUs, 160);
    expect(profile.gc!.maxPauseUs, 160);
  });

  cockpitTestWidgets(
    'profiles an action without requiring VM timeline',
    app: () => const MaterialApp(home: _ProfilePage()),
    body: (cockpit) async {
      await expectLater(
        cockpit.profile(() async {}, maxEvents: 0),
        throwsArgumentError,
      );
      late CockpitPerformanceSink sink;
      final report = await cockpit.profile(
        () async {
          sink.instant('increment.requested', category: 'business');
          await cockpit.tap('#increment');
        },
        name: 'increment',
        timeline: false,
        plugins: <CockpitPerformancePlugin>[
          CockpitPerformancePlugin.callbacks(
            id: 'profile-test',
            setup: (context) => sink = context.sink,
          ),
        ],
      );

      expect(report.stepId, 'increment');
      expect(report.timelineSource, isNull);
      expect(report.buildMode, 'debug');
      expect(report.summary.frameCount, report.frames.length);
      expect(report.plugins.single.id, 'profile-test');
      expect(report.plugins.single.eventCount, 1);
      expect(
        report.events
            .singleWhere((event) => event.source == 'profile-test')
            .name,
        'increment.requested',
      );
      if (kIsWeb) {
        expect(report.memory, isNull);
      } else {
        expect(report.memory, isNotNull);
        expect(report.memory!.summary.sampleCount, greaterThan(0));
      }
      expect(cockpit.report['performance'], isA<List<Object?>>());
      expect(
        cockpit.startup.firstFrameMs,
        greaterThanOrEqualTo(cockpit.startup.appMs),
      );
      expect(cockpit.report['startup'], isA<Map<String, Object?>>());

      final beforeBuilds = debugProfileBuildsEnabled;
      final beforeUserBuilds = debugProfileBuildsEnabledUserWidgets;
      final beforeLayouts = debugProfileLayoutsEnabled;
      final beforePaints = debugProfilePaintsEnabled;
      await cockpit.profile(
        () => cockpit.flutter.pump(),
        name: 'instrumented',
        timeline: false,
        trackBuilds: true,
        trackUserBuilds: true,
        trackLayouts: true,
        trackPaints: true,
      );
      expect(debugProfileBuildsEnabled, beforeBuilds);
      expect(debugProfileBuildsEnabledUserWidgets, beforeUserBuilds);
      expect(debugProfileLayoutsEnabled, beforeLayouts);
      expect(debugProfilePaintsEnabled, beforePaints);
    },
  );
}

CockpitPerformanceSink _firstSink(_StatefulPlugin plugin) =>
    plugin.runs.last.sink;

final class _StatefulPlugin extends CockpitPerformancePlugin {
  _StatefulPlugin() : super(id: 'stateful');

  final List<_StatefulRun> runs = <_StatefulRun>[];

  @override
  CockpitPerformancePluginRun open(CockpitPerformancePluginContext context) {
    final run = _StatefulRun(context.sink);
    runs.add(run);
    return run;
  }
}

final class _StatefulRun extends CockpitPerformancePluginRun {
  _StatefulRun(this.sink);

  final CockpitPerformanceSink sink;
  var stopped = false;

  @override
  Future<void> stop(CockpitPerformancePluginStats stats) async {
    stopped = true;
  }
}

final class _ProfilePage extends StatefulWidget {
  const _ProfilePage();

  @override
  State<_ProfilePage> createState() => _ProfilePageState();
}

final class _ProfilePageState extends State<_ProfilePage> {
  var _count = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: <Widget>[
          Text('Count $_count'),
          ElevatedButton(
            key: const ValueKey<String>('increment'),
            onPressed: () => setState(() => _count += 1),
            child: const Text('Increment'),
          ),
        ],
      ),
    );
  }
}
