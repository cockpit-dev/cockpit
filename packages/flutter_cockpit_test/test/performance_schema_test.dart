import 'dart:convert';
import 'dart:io';

import 'package:flutter_cockpit_test/flutter_cockpit_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:json_schema/json_schema.dart';

void main() {
  final schemaFile = _locateSchema();
  final schema = JsonSchema.create(
    jsonDecode(schemaFile.readAsStringSync()) as Map<String, Object?>,
  );

  test('canonical fullJson export validates against the published schema', () {
    final report = _richReport();
    final bundle =
        jsonDecode(
              CockpitPerformanceHtml.fullJson(
                <CockpitPerformanceReport>[report],
                startup: CockpitStartupReport(
                  appMs: 6,
                  firstFrameMs: 18,
                  readyMs: 31,
                ),
              ),
            )
            as Map<String, Object?>;
    final result = schema.validate(bundle);
    expect(result.isValid, isTrue, reason: result.errors.join('\n'));
    // The embedded capture is the raw-inclusive projection of the same report.
    final embedded =
        (bundle['reports']! as List<Object?>).single! as Map<String, Object?>;
    expect(embedded['report'], equals(report.toJson(includeRaw: true)));
  });

  test('multi-capture bundle without startup still validates', () {
    final first = _richReport(step: 'open-list');
    final second = _richReport(step: 'gc-only', gcOnly: true);
    final bundle =
        jsonDecode(
              CockpitPerformanceHtml.fullJson(<CockpitPerformanceReport>[
                first,
                second,
              ], title: 'Two captures'),
            )
            as Map<String, Object?>;
    final result = schema.validate(bundle);
    expect(result.isValid, isTrue, reason: result.errors.join('\n'));
    final captures = bundle['reports']! as List<Object?>;
    expect((captures[0]! as Map<String, Object?>)['label'], 'open-list');
    expect((captures[1]! as Map<String, Object?>)['label'], 'gc-only');
    // The GC-free capture keeps the explicit zero branch of the analysis.
    final analysis =
        (captures[1]! as Map<String, Object?>)['analysis']!
            as Map<String, Object?>;
    expect(analysis['gc'], <String, Object?>{'count': 0});
  });
}

/// A capture that exercises the report, retention, plugin, DevTools, and
/// Perfetto branches of the export contract.
CockpitPerformanceReport _richReport({
  String step = 'rich',
  bool gcOnly = false,
}) {
  final events = <Object?>[
    <String, Object?>{
      'n': 'BuildOwner.buildScope',
      'c': 'Dart',
      't': 100,
      'd': 4000,
      'p': 'X',
      'a': <String, Object?>{'file': 'package:demo/main.dart'},
    },
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
  ];
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
    'dropped': <String, Object?>{'frames': 1, 'events': 2},
    'stream': <String, Object?>{
      'fmt': 'jsonl',
      'mode': 'lossless',
      'state': 'done',
      'manifest': '/tmp/cockpit/performance/manifest.json',
      'records': 15,
      'bytes': 4096,
    },
    'plugins': <Object?>[
      <String, Object?>{
        'id': 'checkout-aop',
        'state': 'available',
        'ver': '1.0.0',
        'n': 3,
        'span': 2,
        'instant': 1,
        'dur': 1200,
        'max': 900,
        'cat': <String, Object?>{'business': 3},
      },
    ],
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
      'dropped': 1,
    },
    'frames': <Object?>[
      <String, Object?>{
        'i': 0,
        't': 0,
        'w': 14500,
        'b': 4000,
        'r': 10000,
        'v': 500,
        's': 14500,
        'l': 2,
        'lb': 1024,
        'p': 3,
        'pb': 4096,
        'n': 10,
        'bs': 100,
        'bf': 4100,
        'rs': 4200,
        'rf': 14200,
      },
      <String, Object?>{
        'i': 1,
        't': 16667,
        'w': 34267,
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
    'events': gcOnly ? events.take(1).toList(growable: false) : events,
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
            'id': 'classes/1',
            'lib': 'package:demo/main.dart',
            'bytes': 8,
            'count': 2,
            'allocBytes': 10,
            'allocCount': 3,
          },
        ],
      },
      'gc': <String, Object?>{
        'n': 3,
        'timed': 2,
        'new': 2,
        'old': 1,
        'total': 700,
        'p50': 160,
        'p90': 540,
        'max': 540,
        'newUs': 160,
        'oldUs': 540,
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
          'root': <String, Object?>{'n': 'Process', 's': 1280},
        },
      },
      'alloc': <Object?>[
        <String, Object?>{
          'id': 'classes/1',
          'name': 'Foo',
          'trace': <String, Object?>{
            'period': 1000,
            'depth': 8,
            'n': 1,
            'start': 0,
            'span': 1000,
            'f': <Object?>[
              <String, Object?>{'n': 'Foo.', 'in': 1, 'ex': 1},
            ],
            's': <Object?>[
              <String, Object?>{
                't': 10,
                's': <Object?>[0],
              },
            ],
          },
        },
      ],
      'perfetto': <String, Object?>{
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
        'timeline': <String, Object?>{
          'kind': 'timeline',
          'start': 0,
          'span': 1000,
          'n': 2,
        },
      },
    },
  });
}

File _locateSchema() {
  var directory = Directory.current;
  for (var depth = 0; depth < 8; depth++) {
    final candidates = <File>[
      File('${directory.path}/schema/cockpit.performance.v2.schema.json'),
      File(
        '${directory.path}/packages/cockpit_protocol/schema/'
        'cockpit.performance.v2.schema.json',
      ),
    ];
    for (final file in candidates) {
      if (file.existsSync()) {
        return file;
      }
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      break;
    }
    directory = parent;
  }
  throw StateError(
    'Cannot locate cockpit.performance.v2.schema.json from '
    '${Directory.current.path}.',
  );
}
