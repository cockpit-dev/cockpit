import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  final frames = <CockpitPerformanceFrame>[
    const CockpitPerformanceFrame(
      index: 0,
      timestampUs: 100,
      buildUs: 4000,
      rasterUs: 5000,
      vsyncUs: 1000,
      totalUs: 10000,
      layerCount: 2,
      layerBytes: 10,
      pictureCount: 3,
      pictureBytes: 20,
      frameNumber: 7,
    ),
    const CockpitPerformanceFrame(
      index: 1,
      timestampUs: 17100,
      buildUs: 20000,
      rasterUs: 3000,
      vsyncUs: 1000,
      totalUs: 26000,
      layerCount: 4,
      layerBytes: 40,
      pictureCount: 5,
      pictureBytes: 50,
    ),
  ];

  test('summary derives jank, percentiles, cache peaks, and observed fps', () {
    final summary = CockpitPerformanceSummary.fromFrames(
      frames,
      frameBudgetUs: 16667,
    );

    expect(summary.frameCount, 2);
    expect(summary.jankCount, 1);
    expect(summary.fps, closeTo(58.8235, 0.001));
    expect(summary.build.missedBudget, 1);
    expect(summary.build.budgetUs, 16667);
    expect(summary.layerCacheMax, <String, int>{'count': 4, 'bytes': 40});
    expect(summary.pictureCacheMax, <String, int>{'count': 5, 'bytes': 50});
  });

  test('empty summary does not invent fps', () {
    final summary = CockpitPerformanceSummary.fromFrames(
      const <CockpitPerformanceFrame>[],
      frameBudgetUs: 16667,
    );

    expect(summary.frameCount, 0);
    expect(summary.fps, isNull);
    expect(summary.toJson().containsKey('fps'), isFalse);
  });

  test('report rejects inconsistent duration and frame counts', () {
    final summary = CockpitPerformanceSummary.fromFrames(
      frames,
      frameBudgetUs: 16667,
    );
    final start = DateTime.utc(2026, 1, 1);

    expect(
      () => CockpitPerformanceReport(
        startedAt: start,
        finishedAt: start.add(const Duration(milliseconds: 10)),
        durationUs: 10000,
        durationMs: 9,
        platform: 'test',
        mode: CockpitPerformanceMode.light,
        summary: summary,
        frames: frames,
      ),
      throwsFormatException,
    );
    expect(
      () => CockpitPerformanceReport(
        startedAt: start,
        finishedAt: start,
        durationUs: 0,
        durationMs: 0,
        platform: 'test',
        mode: CockpitPerformanceMode.light,
        summary: summary,
        frames: const <CockpitPerformanceFrame>[],
      ),
      throwsFormatException,
    );
  });

  test('round trip preserves raw frame timestamps and compact fields', () {
    final summary = CockpitPerformanceSummary.fromFrames(
      frames,
      frameBudgetUs: 16667,
    );
    final start = DateTime.utc(2026, 1, 1);
    final report = CockpitPerformanceReport(
      startedAt: start,
      finishedAt: start.add(const Duration(milliseconds: 10)),
      durationUs: 10000,
      durationMs: 10,
      platform: 'test',
      mode: CockpitPerformanceMode.profile,
      summary: summary,
      frames: frames,
      events: const <CockpitPerformanceEvent>[
        CockpitPerformanceEvent(
          name: 'build',
          category: 'Dart',
          timestampUs: -2,
          durationUs: 3,
        ),
      ],
    );
    final decoded = CockpitPerformanceReport.fromJson(report.toJson());

    expect(decoded.frames, frames);
    expect(decoded.events.single.timestampUs, -2);
    expect(decoded.summary.build.toJson(), containsPair('bud', 16667));
  });
}
