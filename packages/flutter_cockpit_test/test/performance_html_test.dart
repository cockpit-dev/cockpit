import 'package:flutter_cockpit_test/flutter_cockpit_test.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('renders a self-contained multi-report performance document', () {
    final first = _report(step: 'open-list');
    final second = _report(step: 'scroll-list');

    final html = CockpitPerformanceHtml.renderMany(
      <CockpitPerformanceReport>[first, second],
      title: 'QA <flow>',
      startup: CockpitStartupReport(appMs: 6, firstFrameMs: 18, readyMs: 31),
    );

    expect(html, startsWith('<!doctype html>'));
    expect(html, contains('<title>QA &lt;flow&gt;</title>'));
    expect(html, contains('id="cockpit-performance-data"'));
    expect(html, contains('Frame pacing'));
    expect(html, contains('Memory, cache and GC'));
    expect(html, contains('Capture comparison'));
    expect(html, contains('Timeline events'));
    expect(html, contains('Cold start milestones'));
    expect(html, contains('open-list'));
    expect(html, contains('scroll-list'));
    expect(html, contains(r'\u003cscript\u003e'));
    expect(html, isNot(contains('<script>tracked</script>')));
  });

  test('rejects an empty report collection', () {
    expect(
      () =>
          CockpitPerformanceHtml.renderMany(const <CockpitPerformanceReport>[]),
      throwsArgumentError,
    );
  });

  test('round-trips startup milestones', () {
    final report = CockpitStartupReport(
      appMs: 4,
      firstFrameMs: 15,
      readyMs: 27,
    );
    expect(
      CockpitStartupReport.fromJson(report.toJson()).readyMs,
      report.readyMs,
    );
  });
}

CockpitPerformanceReport _report({required String step}) {
  return CockpitPerformanceReport.fromJson(<String, Object?>{
    'schema': 'cockpit.performance/v2',
    'started': '2026-08-31T00:00:00.000Z',
    'finished': '2026-08-31T00:00:01.000Z',
    'durationUs': 1000000,
    'durationMs': 1000,
    'platform': 'macos',
    'build': 'debug',
    'mode': 'profile',
    'step': step,
    'source': 'vm',
    'summary': <String, Object?>{
      'frames': 2,
      'jank': 1,
      'fps': 60,
      'build': <String, Object?>{
        'n': 2,
        'bud': 16667,
        'avg': 4000,
        'p50': 4000,
        'p90': 5000,
        'p99': 5000,
        'max': 5000,
        'miss': 0,
      },
      'raster': <String, Object?>{
        'n': 2,
        'bud': 16667,
        'avg': 10000,
        'p50': 10000,
        'p90': 12000,
        'p99': 12000,
        'max': 12000,
        'miss': 1,
      },
      'vsync': <String, Object?>{
        'n': 2,
        'bud': 16667,
        'avg': 500,
        'p50': 500,
        'p90': 600,
        'p99': 600,
        'max': 600,
        'miss': 0,
      },
      'total': <String, Object?>{
        'n': 2,
        'bud': 16667,
        'avg': 16050,
        'p50': 14500,
        'p90': 17600,
        'p99': 17600,
        'max': 17600,
        'miss': 1,
      },
      'layerCache': <String, Object?>{'count': 3, 'bytes': 4096},
      'pictureCache': <String, Object?>{'count': 4, 'bytes': 8192},
      'gc': <String, Object?>{'new': 2, 'old': 1},
    },
    'memory': <String, Object?>{
      'source': 'processInfo',
      'intervalMs': 100,
      'summary': <String, Object?>{
        'n': 2,
        'start': 100000000,
        'end': 102000000,
        'min': 100000000,
        'max': 102000000,
        'avg': 101000000,
        'peak': 102000000,
        'delta': 2000000,
      },
      'samples': <Object?>[
        <String, Object?>{'t': 0, 'rss': 100000000, 'peak': 100000000},
        <String, Object?>{'t': 1000000, 'rss': 102000000, 'peak': 102000000},
      ],
    },
    'frames': <Object?>[
      <String, Object?>{
        'i': 0,
        't': 0,
        'w': 0,
        'b': 4000,
        'r': 10000,
        'v': 500,
        's': 14500,
        'l': 2,
        'lb': 1024,
        'p': 3,
        'pb': 4096,
        'n': 10,
      },
      <String, Object?>{
        'i': 1,
        't': 16667,
        'w': 16667,
        'b': 5000,
        'r': 12000,
        'v': 600,
        's': 17600,
        'l': 3,
        'lb': 4096,
        'p': 4,
        'pb': 8192,
        'n': 11,
      },
    ],
    'events': <Object?>[
      <String, Object?>{
        'n': 'BuildOwner.buildScope',
        'c': 'Dart',
        't': 100,
        'd': 4000,
        'p': 'B',
        'a': <String, Object?>{'payload': '<script>tracked</script>'},
      },
    ],
  });
}
