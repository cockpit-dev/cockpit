import 'dart:async';
import 'dart:ui';

import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('collector preserves valid timings and reports bounded drops', (
    tester,
  ) async {
    final collector = CockpitPerformanceCollector(
      platform: 'test',
      frameBudgetUs: 1000,
      maxFrames: 1,
      now: () => DateTime.utc(2026, 1, 1),
    );
    addTearDown(collector.dispose);

    collector.start(mode: CockpitPerformanceMode.profile);
    collector.record(
      FrameTiming(
        vsyncStart: 0,
        buildStart: 100,
        buildFinish: 500,
        rasterStart: 500,
        rasterFinish: 900,
        rasterFinishWallTime: 900,
        layerCacheCount: 2,
        layerCacheBytes: 10,
        pictureCacheCount: 3,
        pictureCacheBytes: 20,
        frameNumber: 1,
      ),
    );
    collector.record(
      FrameTiming(
        vsyncStart: 1000,
        buildStart: 1100,
        buildFinish: 2500,
        rasterStart: 2500,
        rasterFinish: 2900,
        rasterFinishWallTime: 2900,
        frameNumber: -1,
      ),
    );

    final report = collector.stop(stepId: 'scroll');

    expect(report.mode, CockpitPerformanceMode.profile);
    expect(report.summary.frameCount, report.frames.length);
    expect(report.frames, hasLength(1));
    expect(report.droppedFrames, 1);
    // The second frame is intentionally beyond the one-frame retention bound;
    // the summary is therefore for the retained sample and the report's
    // dropped count makes that boundary explicit.
    expect(report.summary.jankCount, 0);
    expect(report.frames.single.frameNumber, 1);
    expect(report.frames.single.timestampUs, 0);
    expect(report.frames.single.wallTimeUs, 900);
    expect(
      report.durationMs,
      report.finishedAt.difference(report.startedAt).inMilliseconds,
    );
  });

  testWidgets('invalid frame timings are excluded instead of skewing metrics', (
    tester,
  ) async {
    final collector = CockpitPerformanceCollector(
      platform: 'test',
      frameBudgetUs: 1000,
      now: () => DateTime.utc(2026, 1, 1),
    );
    addTearDown(collector.dispose);
    collector.start();
    collector.record(
      FrameTiming(
        vsyncStart: 0,
        buildStart: 100,
        buildFinish: 50,
        rasterStart: 50,
        rasterFinish: 90,
        rasterFinishWallTime: 90,
      ),
    );

    final report = collector.stop();

    expect(report.summary.frameCount, 0);
    expect(report.invalidFrames, 1);
    expect(report.frames, isEmpty);
    expect(report.summary.fps, isNull);
  });

  testWidgets('capture timeout detaches without waiting for a hung action', (
    tester,
  ) async {
    final collector = CockpitPerformanceCollector(platform: 'test');
    addTearDown(collector.dispose);
    final release = Completer<void>();
    final action = collector.capture(
      () => release.future,
      timeout: const Duration(milliseconds: 1),
    );
    final expectation = expectLater(action, throwsA(isA<TimeoutException>()));

    // Advance the test clock through the public timeout and finite grace
    // period. This keeps the test deterministic without real sleeping.
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await expectation;
    expect(collector.isRunning, isFalse);
  });
}
