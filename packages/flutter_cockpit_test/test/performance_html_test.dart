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
    expect(html, contains('Widget rebuilds'));
    expect(html, contains('id="rebuild-chart"'));
    expect(html, contains('Flutter.RebuiltWidgets'));
    expect(html, contains('VM runtime health'));
    expect(html, contains('heap-trend-chart'));
    expect(html, contains('VM process memory'));
    expect(html, contains('vm-memory-chart'));
    expect(html, contains('data-details="vmMemory"'));
    expect(html, contains('Frame pipeline'));
    expect(html, contains('pipeline-chart'));
    expect(html, contains('GC pauses'));
    expect(html, contains('gc-chart'));
    expect(html, contains('Isolate health'));
    expect(html, contains('VM logs'));
    expect(html, contains('VM debug events'));
    expect(html, contains('VM runtime'));
    expect(html, contains('Timeline streams'));
    expect(html, contains('details-dialog'));
    expect(html, contains('data-details="cpu"'));
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
    expect(html, contains('Instrumentation plugins'));
    expect(html, contains('id="plugin-body"'));
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
    expect(reports[0]['report']['devtools']['heap']['samples'], isNotEmpty);
    expect(
      reports[0]['report']['devtools']['isolate']['before']['run'],
      isTrue,
    );
    expect(
      reports[0]['report']['devtools']['isolate']['allA'][1]['id'],
      'isolates/3',
    );
    expect(
      reports[0]['report']['devtools']['isolate']['events'][0]['k'],
      'IsolateStart',
    );
    expect(reports[0]['report']['devtools']['timeline']['recorded'], <Object?>[
      'Dart',
    ]);
    expect(reports[0]['report']['devtools']['vm']['target'], 'arm64');
    expect(reports[0]['report']['devtools']['vm']['isolates'], 2);
    expect(reports[0]['report']['devtools']['display']['hz'], 120);
    expect(reports[0]['report']['devtools']['rebuild']['frames'], isNotEmpty);
    expect(
      reports[0]['report']['devtools']['vmem']['after']['root']['s'],
      1280,
    );
    expect(reports[1]['report']['events'][0]['a']['payload'], <Object?>[
      1,
      true,
      'kept',
    ]);
    expect(reports[1]['analysis']['hotspots'], hasLength(1));
    expect(reports[1]['analysis']['hotspots'][0]['n'], 'Rasterize');
    expect(reports[1]['analysis']['hotspots'][0]['p90'], 250);
    expect(reports[1]['analysis']['gc']['count'], 0);
  });

  test(
    'renders plugin attribution and source metadata in the timeline view',
    () {
      final report = CockpitPerformanceReport.fromJson(<String, Object?>{
        ..._report(step: 'plugin').toJson(),
        'plugins': <Object?>[
          <String, Object?>{
            'id': 'checkout-aop',
            'state': 'available',
            'ver': '1.0.0',
            'n': 2,
            'span': 1,
            'instant': 1,
            'dur': 1200,
            'cat': <String, Object?>{'business': 2},
          },
        ],
        'events': <Object?>[
          <String, Object?>{
            'n': 'checkout.fetch',
            'c': 'business',
            't': 500,
            'd': 1200,
            'p': 'X',
            'src': 'checkout-aop',
            'iso': 'isolates/1',
            'u': 'package:checkout/checkout.dart',
            'l': 42,
            'a': <String, Object?>{'status': 200},
          },
        ],
      });
      final html = CockpitPerformanceHtml.render(report);
      expect(html, contains('checkout-aop'));
      expect(html, contains('Source'));
      expect(html, contains('event.src'));
      expect(html, contains('plugin-body'));
    },
  );

  test(
    'Perfetto stays metadata-only in compact output and is retained in HTML',
    () {
      final report = _report(step: 'perfetto').copyWithPerfetto();
      final compact = report.toJson();
      expect(
        ((compact['devtools'] as Map)['perfetto'] as Map)['cpu'],
        isNot(contains('data')),
      );

      final html = CockpitPerformanceHtml.render(report);
      expect(html, contains('id="perfetto-button"'));
      expect(html, contains('AQID'));

      final full = jsonDecode(CockpitPerformanceHtml.fullJson([report]));
      expect(
        (((full as Map)['reports'] as List)
            .single['report']['devtools']['perfetto']['cpu']['data']),
        'AQID',
      );
    },
  );

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

  test('pairs GC markers for accurate pause and hotspot analysis', () {
    final report = _report(step: 'gc').copyWithEvents(<Object?>[
      <String, Object?>{
        'n': 'CollectNewGeneration',
        'c': 'GC',
        't': 100,
        'p': 'B',
      },
      <String, Object?>{
        'n': 'CollectNewGeneration',
        'c': 'GC',
        't': 260,
        'p': 'E',
      },
      <String, Object?>{
        'n': 'CollectOldGeneration',
        'c': 'GC',
        't': 400,
        'p': 'B',
      },
      <String, Object?>{
        'n': 'CollectOldGeneration',
        'c': 'GC',
        't': 940,
        'p': 'E',
      },
    ]);
    final payload =
        jsonDecode(CockpitPerformanceHtml.fullJson([report]))
            as Map<String, dynamic>;
    final analysis =
        (payload['reports'] as List).single['analysis'] as Map<String, dynamic>;
    expect(analysis['gc'], <String, Object?>{
      'count': 2,
      'timed': 2,
      'new': 1,
      'old': 1,
      'total': 700,
      'p50': 160,
      'p90': 540,
      'max': 540,
    });
    expect(analysis['hotspots'], hasLength(2));
    expect(analysis['hotspots'][0]['count'], 1);
    expect(analysis['hotspots'][0]['total'], 540);
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
      'display': <String, Object?>{'hz': 120, 'bud': 8333, 'view': 'view-1'},
      'rebuild': <String, Object?>{
        'frames': <Object?>[
          <String, Object?>{
            'n': 10,
            'e': <Object?>[2, 3],
          },
        ],
        'loc': <Object?>[
          <String, Object?>{
            'id': 2,
            'u': 'package:demo/main.dart',
            'l': 12,
            'c': 4,
            'n': 'HomePage',
          },
        ],
        'tot': <Object?>[
          <String, Object?>{'id': 2, 'n': 3},
        ],
      },
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
        'interval': 100,
        'samples': <Object?>[
          <String, Object?>{'t': 0, 'use': 10, 'cap': 20, 'ext': 1},
          <String, Object?>{'t': 100000, 'use': 12, 'cap': 24, 'ext': 2},
        ],
        'drop': 1,
        'gb': <String, Object?>{'use': 20, 'cap': 30, 'ext': 3},
        'ga': <String, Object?>{'use': 22, 'cap': 32, 'ext': 4},
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
      'isolate': <String, Object?>{
        'before': <String, Object?>{
          'id': 'isolates/1',
          'name': 'main',
          'group': 'groups/1',
          'run': true,
          'ports': 2,
          'libs': 12,
          'ext': 1,
          'start': 1700000000000,
        },
        'after': <String, Object?>{
          'id': 'isolates/1',
          'name': 'main',
          'group': 'groups/1',
          'run': true,
          'ports': 2,
          'libs': 12,
          'ext': 1,
          'start': 1700000000000,
        },
        'allB': <Object?>[
          <String, Object?>{'id': 'isolates/1', 'name': 'main', 'run': true},
          <String, Object?>{'id': 'isolates/2', 'name': 'worker', 'run': true},
        ],
        'allA': <Object?>[
          <String, Object?>{'id': 'isolates/1', 'name': 'main', 'run': true},
          <String, Object?>{
            'id': 'isolates/3',
            'name': 'worker-2',
            'run': true,
          },
        ],
        'events': <Object?>[
          <String, Object?>{
            'k': 'IsolateStart',
            't': 1700000000100,
            'id': 'isolates/3',
          },
        ],
        'dropE': 1,
      },
      'log': <Object?>[
        <String, Object?>{
          't': 1700000000300,
          'lvl': 900,
          'seq': 4,
          'msg': 'slow request',
          'logger': 'app.network',
          'zone': 'request-zone',
          'err': 'timeout',
          'stack': 'package:demo/main.dart:12',
          'iso': 'isolates/1',
        },
      ],
      'dropLog': 2,
      'dbg': <Object?>[
        <String, Object?>{
          'k': 'PauseException',
          't': 1700000000400,
          'iso': 'isolates/1',
          'name': 'main',
          'async': true,
          'fn': 'main',
          'uri': 'package:demo/main.dart',
          'line': 12,
          'col': 2,
          'err': 'StateError',
          'bp': 2,
        },
      ],
      'dropDbg': 1,
      'timeline': <String, Object?>{
        'recorder': 'ring',
        'available': <Object?>['Dart', 'GC'],
        'recorded': <Object?>['Dart'],
      },
      'vm': <String, Object?>{
        'name': 'vm',
        'ver': '3.8.0',
        'os': 'macos',
        'host': 'arm64',
        'target': 'arm64',
        'arch': 64,
        'pid': 42,
        'start': 1700000000000,
        'isolates': 2,
        'groups': 1,
        'sys': 1,
      },
      'vmem': <String, Object?>{
        'before': <String, Object?>{
          't': 0,
          'root': <String, Object?>{
            'n': 'Process',
            's': 1024,
            'c': <Object?>[
              <String, Object?>{'n': 'Dart heap', 's': 768},
              <String, Object?>{'n': 'Native', 's': 256},
            ],
          },
        },
        'after': <String, Object?>{
          't': 100000,
          'root': <String, Object?>{
            'n': 'Process',
            's': 1280,
            'c': <Object?>[
              <String, Object?>{'n': 'Dart heap', 's': 896},
              <String, Object?>{'n': 'Native', 's': 384},
            ],
          },
        },
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

  CockpitPerformanceReport copyWithPerfetto() {
    final json = toJson();
    final devtools = Map<String, Object?>.from(
      json['devtools']! as Map<Object?, Object?>,
    );
    devtools['perfetto'] = <String, Object?>{
      'cpu': <String, Object?>{
        'kind': 'cpu',
        'start': 0,
        'span': 1000,
        'period': 1000,
        'depth': 8,
        'n': 1,
        'pid': 42,
        'data': 'AQID',
      },
    };
    json['devtools'] = devtools;
    return CockpitPerformanceReport.fromJson(json);
  }
}
