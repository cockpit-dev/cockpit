import 'dart:convert';
import 'dart:io';

import 'package:flutter_cockpit_test/flutter_cockpit_test.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults to lossless streaming and validates bounded mode', () {
    const defaults = CockpitPerformanceArchiveOptions();
    expect(defaults.mode, CockpitPerformanceArchiveMode.lossless);
    expect(defaults.maxPendingBytes, isNull);
    expect(
      () => const CockpitPerformanceArchiveOptions(
        mode: CockpitPerformanceArchiveMode.low,
      ).validate(),
      throwsArgumentError,
    );
    const bounded = CockpitPerformanceArchiveOptions(
      mode: CockpitPerformanceArchiveMode.low,
      maxPendingBytes: 64 * 1024,
    );
    expect(() => bounded.validate(), returnsNormally);
  });

  test('writes bounded JSONL chunks and an indexed manifest', () async {
    final temp = await Directory.systemTemp.createTemp('cockpit-archive-');
    addTearDown(() => temp.delete(recursive: true));

    final archive = await CockpitPerformanceArchive.open(
      directory: temp.path,
      name: 'long-flow',
      options: const CockpitPerformanceArchiveOptions(
        chunkBytes: 1024 * 1024,
        flushEvery: Duration(milliseconds: 10),
        pollEvery: Duration(milliseconds: 100),
      ),
    );
    final capture = archive.beginCapture(
      id: 'a',
      startedAt: DateTime.utc(2026, 1, 1),
    );
    archive.addFrame(
      const CockpitPerformanceFrame(
        index: 0,
        timestampUs: 0,
        wallTimeUs: 0,
        buildUs: 100,
        rasterUs: 200,
        vsyncUs: 0,
        totalUs: 300,
        layerCount: 1,
        layerBytes: 2,
        pictureCount: 1,
        pictureBytes: 2,
      ),
    );
    archive.addEvent(
      CockpitPerformanceEvent(
        name: 'flow.step',
        category: 'test',
        timestampUs: 10,
        durationUs: 20,
      ),
    );
    final report = CockpitPerformanceReport.fromJson(<String, Object?>{
      'schema': 'cockpit.performance/v2',
      'started': '2026-01-01T00:00:00.000Z',
      'finished': '2026-01-01T00:00:00.001Z',
      'durationUs': 1000,
      'durationMs': 1,
      'platform': 'test',
      'build': 'debug',
      'mode': 'profile',
      'summary': <String, Object?>{
        'frames': 0,
        'jank': 0,
        'build': <String, Object?>{'n': 0, 'bud': 16667},
        'raster': <String, Object?>{'n': 0, 'bud': 16667},
        'vsync': <String, Object?>{'n': 0, 'bud': 16667},
        'total': <String, Object?>{'n': 0, 'bud': 16667},
        'layerCache': <String, Object?>{'count': 0, 'bytes': 0},
        'pictureCache': <String, Object?>{'count': 0, 'bytes': 0},
      },
      'step': 'long-flow',
    });
    archive.endCapture(capture, report);
    await archive.flush();
    final info = await archive.close();

    expect(info.state, 'done');
    expect(info.format, 'jsonl');
    expect(info.events, 1);
    expect(info.frames, 1);
    expect(info.records, greaterThanOrEqualTo(3));
    expect(info.chunks, isNotEmpty);
    expect(await File(info.manifest).exists(), isTrue);
    final manifest = jsonDecode(await File(info.manifest).readAsString());
    expect(manifest['schema'], 'cockpit.performance.stream/v1');
    expect(manifest['state'], 'done');
    expect(manifest['mode'], 'lossless');
    expect(manifest['pending'], isNull);
    final lines = await File(info.chunks.single).readAsLines();
    expect(lines, isNotEmpty);
    expect(jsonDecode(lines.first)['q'], 's');
    expect(lines.map((line) => jsonDecode(line)['q']), contains('f'));
    expect(lines.map((line) => jsonDecode(line)['q']), contains('e'));
  });

  test(
    'keeps lossless records while writes, flushes, and rotation overlap',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'cockpit-archive-race-',
      );
      addTearDown(() => temp.delete(recursive: true));

      final archive = await CockpitPerformanceArchive.open(
        directory: temp.path,
        name: 'race-flow',
        options: const CockpitPerformanceArchiveOptions(
          chunkBytes: 1024 * 1024,
          flushEvery: Duration(milliseconds: 1),
          pollEvery: Duration(milliseconds: 100),
        ),
      );
      final capture = archive.beginCapture(
        id: 'race',
        startedAt: DateTime.utc(2026, 1, 1),
      );
      const eventCount = 3000;
      final namePrefix = 'race.${List<String>.filled(500, 'x').join()}.';
      final producer = Future<void>(() async {
        for (var index = 0; index < eventCount; index += 1) {
          archive.addEvent(
            CockpitPerformanceEvent(
              name: '$namePrefix$index',
              category: 'stress',
              timestampUs: index,
              durationUs: 0,
            ),
          );
          if (index % 17 == 0) await Future<void>.delayed(Duration.zero);
        }
      });
      final flushers = <Future<void>>[
        for (var index = 0; index < 12; index += 1)
          Future<void>(() async {
            await Future<void>.delayed(Duration(milliseconds: index % 3));
            await archive.flush();
          }),
      ];

      await Future.wait(<Future<void>>[producer, ...flushers]);
      final report = CockpitPerformanceReport.fromJson(<String, Object?>{
        'schema': 'cockpit.performance/v2',
        'started': '2026-01-01T00:00:00.000Z',
        'finished': '2026-01-01T00:00:00.001Z',
        'durationUs': 1000,
        'durationMs': 1,
        'platform': 'test',
        'build': 'debug',
        'mode': 'profile',
        'summary': <String, Object?>{
          'frames': 0,
          'jank': 0,
          'build': <String, Object?>{'n': 0, 'bud': 16667},
          'raster': <String, Object?>{'n': 0, 'bud': 16667},
          'vsync': <String, Object?>{'n': 0, 'bud': 16667},
          'total': <String, Object?>{'n': 0, 'bud': 16667},
          'layerCache': <String, Object?>{'count': 0, 'bytes': 0},
          'pictureCache': <String, Object?>{'count': 0, 'bytes': 0},
        },
        'step': 'race-flow',
      });
      archive.endCapture(capture, report);
      final info = await archive.close();

      expect(info.state, 'done');
      expect(info.events, eventCount);
      expect(info.dropped, 0);
      expect(info.errors, 0);
      final records = <Map<String, Object?>>[];
      for (final chunk in info.chunks) {
        for (final line in await File(chunk).readAsLines()) {
          records.add((jsonDecode(line) as Map).cast<String, Object?>());
        }
      }
      expect(
        records.where((record) => record['q'] == 'e'),
        hasLength(eventCount),
      );
    },
  );
}
