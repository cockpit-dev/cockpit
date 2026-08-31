import 'dart:convert';

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
    expect(html, contains('Memory trend'));
    expect(html, contains('Cache &amp; GC pressure'));
    expect(html, contains('Jank &amp; stalls'));
    expect(html, contains('id="stall-body"'));
    expect(html, contains('stallAnalysis'));
    expect(html, contains('DevTools coverage'));
    expect(html, contains('id="coverage-grid"'));
    expect(html, contains('CPU sampling'));
    expect(html, contains('Heap &amp; allocation'));
    expect(html, contains('GPU / Shader signals'));
    expect(html, contains('id="cpu-chart"'));
    expect(html, contains('id="heap-chart"'));
    expect(html, contains('Network profiler'));
    expect(html, contains('Download timeline'));
    expect(html, contains('Download full JSON'));
    expect(html, contains('JSON.stringify(data)]'));
    expect(html, contains('JSON.stringify(timelinePayload())]'));
    expect(html, contains('padding: 6px 8px'));
    expect(html, contains('margin-top: 15px; }'));
    expect(html, contains('traceEvents'));
    expect(html, contains('timelinePayload'));
    expect(html, contains('Jank distribution'));
    expect(html, contains('Timeline flame view'));
    expect(html, contains('id="flame-chart"'));
    expect(html, contains('align-items: start'));
    expect(html, contains('.chart-grid { margin-top: 15px; }'));
    expect(html, contains('fitChartRows'));
    expect(
      html,
      contains(
        "setChartHeight('flame-chart', clamp(48 + maxDepth * 22, 84, 360))",
      ),
    );
    expect(
      html,
      contains(
        'var total = Math.max(1, list.length); var left = 116, right = 84',
      ),
    );
    expect(html, contains('Frame cadence'));
    expect(html, contains('Raster cache trend'));
    expect(html, contains('VM category cost'));
    expect(html, contains('Operation hotspots'));
    expect(html, contains('id="hotspot-chart"'));
    expect(html, contains('hotspotRows'));
    expect(html, contains('id="cadence-chart"'));
    expect(html, contains('id="cache-trend-chart"'));
    expect(html, contains('id="category-cost-chart"'));
    expect(html, contains('overflow-wrap: anywhere'));
    expect(html, contains('.coverage-grid > :last-child:nth-child(odd)'));
    expect(html, contains("window.addEventListener('scroll', hideTooltip"));
    expect(html, contains('Capture comparison'));
    expect(html, contains('Timeline events'));
    expect(html, contains('Code evidence'));
    expect(html, contains('<svg viewBox="0 0 1024 1024"'));
    expect(html, contains('id="chart-tooltip"'));
    expect(html, contains('relativeUs'));
    expect(html, contains('"t":0'));
    expect(html, contains('Cold start milestones'));
    expect(html, contains('id="startup-chart"'));
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

  test('exports retained VM events as a trace timeline', () {
    final report = _report(step: 'trace');
    final encoded = CockpitPerformanceHtml.timelineJson(report);
    expect(encoded, isNot(contains('\n')));
    final trace = jsonDecode(encoded);

    expect(trace, isA<Map<String, dynamic>>());
    final events = (trace as Map<String, dynamic>)['traceEvents'];
    expect(events, hasLength(1));
    expect(events.single, <String, Object?>{
      'name': 'BuildOwner.buildScope',
      'cat': 'Dart',
      'ph': 'X',
      'ts': 100,
      'pid': 1,
      'tid': 1,
      'args': <String, Object?>{'payload': '<script>tracked</script>'},
      'dur': 4000,
    });
  });

  test('full JSON export keeps every capture and retained detail', () {
    final first = _report(step: 'open-list');
    final second = _report(step: 'scroll-list').copyWithEvents(<Object?>[
      <String, Object?>{
        'n': 'Rasterize',
        'c': 'Embedder',
        't': 500,
        'd': 250,
        'a': <String, Object?>{
          'file': 'lib/screens/list.dart',
          'line': 42,
          'payload': <Object?>[1, true, 'kept'],
        },
      },
    ]);
    final encoded = CockpitPerformanceHtml.fullJson(
      <CockpitPerformanceReport>[first, second],
      title: 'Complete capture',
      startup: CockpitStartupReport(appMs: 6, firstFrameMs: 18, readyMs: 31),
    );
    expect(encoded, isNot(contains('\n')));
    final decoded = jsonDecode(encoded) as Map<String, dynamic>;

    expect(decoded['title'], 'Complete capture');
    expect(decoded['startup']['readyMs'], 31);
    final reports = decoded['reports'] as List;
    expect(reports, hasLength(2));
    expect(reports[0]['report']['frames'], isNotEmpty);
    expect(reports[0]['report']['events'], isNotEmpty);
    expect(reports[0]['report']['memory']['samples'], isNotEmpty);
    expect(reports[1]['report']['events'][0]['a']['payload'], <Object?>[
      1,
      true,
      'kept',
    ]);
    expect(reports[1]['analysis']['hotspots'], hasLength(1));
    expect(reports[1]['analysis']['hotspots'][0]['n'], 'Rasterize');
    expect(reports[1]['analysis']['hotspots'][0]['p90'], 250);
  });

  test('closes begin/end spans and lowers unmatched markers', () {
    final report = _report(step: 'spans').copyWithEvents(<Object?>[
      <String, Object?>{
        'n': 'Build',
        'c': 'Dart',
        't': 100,
        'p': 'B',
        'a': <String, Object?>{'owner': 'root'},
      },
      <String, Object?>{'n': 'Build', 'c': 'Dart', 't': 5100, 'p': 'E'},
      <String, Object?>{'n': 'Unfinished', 'c': 'Dart', 't': 7000, 'p': 'B'},
      <String, Object?>{'n': 'Orphan end', 'c': 'Dart', 't': 8000, 'p': 'E'},
    ]);
    final trace = jsonDecode(CockpitPerformanceHtml.timelineJson(report));
    final events = (trace as Map<String, dynamic>)['traceEvents'] as List;

    expect(
      events,
      contains(
        predicate<Map<String, dynamic>>((event) {
          return event['name'] == 'Build' &&
              event['cat'] == 'Dart' &&
              event['ph'] == 'X' &&
              event['ts'] == 100 &&
              event['pid'] == 1 &&
              event['tid'] == 1 &&
              event['args'] is Map &&
              (event['args'] as Map)['owner'] == 'root' &&
              event['dur'] == 5000;
        }),
      ),
    );
    expect(
      events,
      contains(
        predicate<Map<String, dynamic>>((event) {
          return event['name'] == 'Unfinished' && event['ph'] == 'i';
        }),
      ),
    );
    expect(
      events,
      contains(
        predicate<Map<String, dynamic>>((event) {
          return event['name'] == 'Orphan end' && event['ph'] == 'i';
        }),
      ),
    );
    expect(
      events.where((event) => event['ph'] == 'B' || event['ph'] == 'E'),
      isEmpty,
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
    'devtools': <String, Object?>{
      'source': 'vm',
      'state': 'available',
      'cpu': <String, Object?>{
        'period': 1000,
        'depth': 32,
        'n': 1,
        'start': 0,
        'span': 1000,
        'f': <Object?>[
          <String, Object?>{'n': 'main', 'in': 1, 'ex': 1},
        ],
        's': <Object?>[
          <String, Object?>{
            't': 10,
            's': <Object?>[0],
          },
        ],
      },
      'heap': <String, Object?>{
        'before': <String, Object?>{'use': 10, 'cap': 20, 'ext': 1},
        'after': <String, Object?>{'use': 12, 'cap': 24, 'ext': 2},
        'classes': <Object?>[
          <String, Object?>{
            'n': 'Foo',
            'bytes': 8,
            'count': 2,
            'allocBytes': 10,
            'allocCount': 3,
          },
        ],
      },
      'gpu': <String, Object?>{
        'source': 'vmTimeline',
        'events': 2,
        'shaders': 1,
        'time': 400,
      },
    },
  });
}

extension on CockpitPerformanceReport {
  CockpitPerformanceReport copyWithEvents(Iterable<Object?> values) {
    final json = toJson();
    json['events'] = values.toList(growable: false);
    return CockpitPerformanceReport.fromJson(json);
  }
}
