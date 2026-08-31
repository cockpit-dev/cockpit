import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  final frames = <CockpitPerformanceFrame>[
    const CockpitPerformanceFrame(
      index: 0,
      timestampUs: 100,
      wallTimeUs: 900,
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
      wallTimeUs: 17900,
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
    expect(summary.build.sampleCount, 2);
    expect(summary.jankCount, 1);
    expect(summary.fps, closeTo(58.8235, 0.001));
    expect(summary.build.missedBudget, 1);
    expect(summary.total.p90Us, 24400);
    expect(summary.total.missedBudget, 1);
    expect(summary.build.budgetUs, 16667);
    expect(summary.layerCacheMax, <String, int>{'count': 4, 'bytes': 40});
    expect(summary.pictureCacheMax, <String, int>{'count': 5, 'bytes': 50});
    expect(summary.toJson()['build'], containsPair('n', 2));
  });

  test('jank uses total span and repeated timestamps do not fabricate fps', () {
    final summary =
        CockpitPerformanceSummary.fromFrames(<CockpitPerformanceFrame>[
          const CockpitPerformanceFrame(
            index: 0,
            timestampUs: 0,
            wallTimeUs: 0,
            buildUs: 1000,
            rasterUs: 1000,
            vsyncUs: 1000,
            totalUs: 20000,
            layerCount: 0,
            layerBytes: 0,
            pictureCount: 0,
            pictureBytes: 0,
          ),
          const CockpitPerformanceFrame(
            index: 1,
            timestampUs: 0,
            wallTimeUs: 16000,
            buildUs: 1000,
            rasterUs: 1000,
            vsyncUs: 1000,
            totalUs: 1000,
            layerCount: 0,
            layerBytes: 0,
            pictureCount: 0,
            pictureBytes: 0,
          ),
        ], frameBudgetUs: 16667);

    expect(summary.jankCount, 1);
    expect(summary.fps, isNull);
  });

  test('empty summary does not invent fps', () {
    final summary = CockpitPerformanceSummary.fromFrames(
      const <CockpitPerformanceFrame>[],
      frameBudgetUs: 16667,
    );

    expect(summary.frameCount, 0);
    expect(summary.fps, isNull);
    expect(summary.toJson().containsKey('fps'), isFalse);
    expect(summary.toJson()['build'], <String, Object?>{'n': 0, 'bud': 16667});
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
        buildMode: 'profile',
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
        buildMode: 'profile',
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
      buildMode: 'profile',
      mode: CockpitPerformanceMode.profile,
      summary: summary,
      frames: frames,
      events: <CockpitPerformanceEvent>[
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
    expect(decoded.frames.first.wallTimeUs, 900);
    expect(decoded.buildMode, 'profile');
    expect(decoded.events.single.timestampUs, -2);
    expect(decoded.summary.build.toJson(), containsPair('bud', 16667));
  });

  test('rejects incomplete populated phases and timezone-free reports', () {
    expect(
      () => CockpitPerformancePhaseSummary.fromJson(<String, Object?>{
        'n': 1,
        'bud': 16667,
        'avg': 1,
      }),
      throwsFormatException,
    );

    final summary = CockpitPerformanceSummary.fromFrames(
      const <CockpitPerformanceFrame>[],
      frameBudgetUs: 16667,
    );
    expect(
      () => CockpitPerformanceReport.fromJson(<String, Object?>{
        'schema': 'cockpit.performance/v2',
        'started': '2026-01-01T00:00:00',
        'finished': '2026-01-01T00:00:00Z',
        'durationUs': 0,
        'durationMs': 0,
        'platform': 'test',
        'mode': 'light',
        'summary': summary.toJson(),
      }),
      throwsFormatException,
    );
  });

  test('event arguments are snapshotted instead of remaining mutable', () {
    final nested = <String, Object?>{
      'items': <Object?>[
        <String, Object?>{'value': 1},
      ],
    };
    final event = CockpitPerformanceEvent(
      name: 'work',
      category: 'Dart',
      timestampUs: 1,
      durationUs: 2,
      args: nested,
    );
    (nested['items']! as List<Object?>).clear();

    expect(event.args['items'], hasLength(1));
    expect(
      () => (event.args['items']! as List<Object?>).clear(),
      throwsUnsupportedError,
    );
  });

  test('memory report preserves bounded RSS samples and summary', () {
    final report = CockpitPerformanceMemoryReport(
      intervalMs: 100,
      samples: const <CockpitPerformanceMemorySample>[
        CockpitPerformanceMemorySample(
          timestampUs: 0,
          rssBytes: 100,
          processPeakBytes: 100,
        ),
        CockpitPerformanceMemorySample(
          timestampUs: 100000,
          rssBytes: 160,
          processPeakBytes: 180,
        ),
      ],
      droppedSamples: 2,
    );

    final decoded = CockpitPerformanceMemoryReport.fromJson(report.toJson());
    expect(decoded.samples, report.samples);
    expect(decoded.summary.averageRssBytes, 130);
    expect(decoded.summary.deltaRssBytes, 60);
    expect(decoded.droppedSamples, 2);
  });

  test('memory report rejects a forged summary', () {
    final report = <String, Object?>{
      'source': 'processInfo',
      'intervalMs': 100,
      'summary': <String, Object?>{
        'n': 1,
        'start': 100,
        'end': 100,
        'min': 100,
        'max': 100,
        'avg': 100,
        'peak': 100,
        'delta': 1,
      },
      'samples': <Object?>[
        <String, Object?>{'t': 0, 'rss': 100, 'peak': 100},
      ],
    };
    expect(
      () => CockpitPerformanceMemoryReport.fromJson(report),
      throwsFormatException,
    );
  });
}
