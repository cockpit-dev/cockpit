import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_cockpit_test/flutter_cockpit_test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_cockpit_test/src/cockpit_devtools_profiler.dart';

void main() {
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
      final report = await cockpit.profile(
        () => cockpit.tap('#increment'),
        name: 'increment',
        timeline: false,
      );

      expect(report.stepId, 'increment');
      expect(report.timelineSource, isNull);
      expect(report.buildMode, 'debug');
      expect(report.summary.frameCount, report.frames.length);
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
