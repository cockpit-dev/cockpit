import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:json_schema/json_schema.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final packageRoot = _packageRoot();
  final schemaPath = p.join(
    packageRoot.path,
    'schema',
    'cockpit.performance.v2.schema.json',
  );
  final schemaJson =
      jsonDecode(File(schemaPath).readAsStringSync()) as Map<String, Object?>;
  final schema = JsonSchema.create(schemaJson);

  test('published schema is valid JSON Schema 2020-12 with a stable id', () {
    expect(
      schemaJson[r'$schema'],
      'https://json-schema.org/draft/2020-12/schema',
    );
    expect(
      schemaJson[r'$id'],
      'https://github.com/cockpit-dev/cockpit/packages/cockpit_protocol/schema/cockpit.performance.v2.schema.json',
    );
    expect(schema.schemaVersion, SchemaVersion.draft2020_12);
    expect(
      p.relative(schemaPath, from: packageRoot.path),
      p.join('schema', 'cockpit.performance.v2.schema.json'),
    );
  });

  test('minimal capture validates without inventing unavailable metrics', () {
    final report = _report(<String, Object?>{
      'summary': _emptySummary(),
      'dropped': null,
      'stream': null,
      'plugins': null,
      'step': null,
      'source': null,
      'memory': null,
      'devtools': null,
      'frames': null,
      'events': null,
    });
    final json = report.toJson();
    expect(json.containsKey('frames'), isFalse);
    expect(json.containsKey('events'), isFalse);
    expect(
      (json['summary']! as Map<String, Object?>)['build'],
      containsPair('n', 0),
    );
    expect(_validate(schema, json).isValid, isTrue);
  });

  test('complete capture validates in compact and raw export projections', () {
    final report = _report();
    for (final includeRaw in <bool>[false, true]) {
      final json = report.toJson(includeRaw: includeRaw);
      final result = _validate(schema, json);
      expect(result.isValid, isTrue, reason: result.errors.join('\n'));
    }
  });

  test('exported JSON round-trips through the Dart model', () {
    final report = _report();
    final json = report.toJson(includeRaw: true);
    final roundTripped = CockpitPerformanceReport.fromJson(
      json,
    ).toJson(includeRaw: true);
    expect(roundTripped, json);
    expect(_validate(schema, roundTripped).isValid, isTrue);
  });

  test('bundle shape validates as the complete export document', () {
    final report = _report();
    final bundle = <String, Object?>{
      'title': 'Cockpit performance',
      'startup': <String, Object?>{
        'kind': 'cold',
        'source': 'harness',
        'appMs': 6,
        'firstMs': 18,
        'readyMs': 31,
      },
      'reports': <Object?>[
        <String, Object?>{
          'id': 'p0',
          'label': 'open-list',
          'report': report.toJson(includeRaw: true),
          'analysis': <String, Object?>{
            'hotspots': <Object?>[
              <String, Object?>{
                'c': 'Dart',
                'n': 'BuildOwner.buildScope',
                'count': 1,
                'timed': 1,
                'total': 4000,
                'p90': 4000,
                'max': 4000,
              },
            ],
            'gc': <String, Object?>{
              'count': 2,
              'timed': 2,
              'new': 1,
              'old': 1,
              'total': 700,
              'p50': 160,
              'p90': 540,
              'max': 540,
            },
          },
        },
      ],
    };
    final result = _validate(schema, bundle);
    expect(result.isValid, isTrue, reason: result.errors.join('\n'));
  });

  test('schema rejects documents the Dart model rejects', () {
    final base = _report().toJson();

    final wrongSchema = _mutate(base, 'schema', 'cockpit.performance/v1');
    expect(_validate(schema, wrongSchema).isValid, isFalse);

    final unknownKey = <String, Object?>{...base, 'framesTotal': 2};
    expect(_validate(schema, unknownKey).isValid, isFalse);

    final missingAggregates = _mutateNested(
      base,
      <String>['summary', 'build'],
      <String, Object?>{'n': 3, 'bud': 16667},
    );
    expect(_validate(schema, missingAggregates).isValid, isFalse);

    final zeroSampleAggregates = _mutateNested(
      base,
      <String>['summary', 'vsync'],
      <String, Object?>{'n': 0, 'bud': 16667, 'avg': 0},
    );
    expect(_validate(schema, zeroSampleAggregates).isValid, isFalse);

    final emptyDropped = _mutate(base, 'dropped', <String, Object?>{});
    expect(_validate(schema, emptyDropped).isValid, isFalse);

    final badBundle = <String, Object?>{'title': 'Cockpit performance'};
    expect(_validate(schema, badBundle).isValid, isFalse);
  });
}

ValidationResults _validate(JsonSchema schema, Object? document) {
  return schema.validate(document);
}

Map<String, Object?> _mutate(
  Map<String, Object?> source,
  String key,
  Object? value,
) {
  final copy = <String, Object?>{...source};
  if (value == null) {
    copy.remove(key);
  } else {
    copy[key] = value;
  }
  return copy;
}

Map<String, Object?> _mutateNested(
  Map<String, Object?> source,
  List<String> path,
  Map<String, Object?> value,
) {
  final copy = <String, Object?>{...source};
  var cursor = copy;
  for (final segment in path.take(path.length - 1)) {
    final nested = Map<String, Object?>.from(cursor[segment]! as Map);
    cursor[segment] = nested;
    cursor = nested;
  }
  cursor[path.last] = value;
  return copy;
}

Map<String, Object?> _emptySummary() => <String, Object?>{
  'frames': 0,
  'jank': 0,
  'build': <String, Object?>{'n': 0, 'bud': 16667},
  'raster': <String, Object?>{'n': 0, 'bud': 16667},
  'vsync': <String, Object?>{'n': 0, 'bud': 16667},
  'total': <String, Object?>{'n': 0, 'bud': 16667},
  'layerCache': <String, Object?>{'count': 0, 'bytes': 0},
  'pictureCache': <String, Object?>{'count': 0, 'bytes': 0},
};

/// One capture that exercises every optional field of the report contract.
CockpitPerformanceReport _report([
  Map<String, Object?> overrides = const <String, Object?>{},
]) {
  final document = <String, Object?>{
    'schema': 'cockpit.performance/v2',
    'started': '2026-08-31T00:00:00.000Z',
    'finished': '2026-08-31T00:00:01.000Z',
    'durationUs': 1000000,
    'durationMs': 1000,
    'platform': 'macos',
    'build': 'debug',
    'mode': 'profile',
    'step': 'open-list',
    'source': 'vm',
    'dropped': <String, Object?>{
      'frames': 1,
      'events': 2,
      'badFrames': 3,
      'badEvents': 4,
    },
    'stream': <String, Object?>{
      'fmt': 'jsonl',
      'mode': 'lossless',
      'state': 'done',
      'manifest': '/tmp/cockpit/performance/manifest.json',
      'chunks': <Object?>[
        '/tmp/cockpit/performance/chunk-000.jsonl',
        '/tmp/cockpit/performance/chunk-001.jsonl',
      ],
      'events': 12,
      'frames': 3,
      'records': 15,
      'bytes': 4096,
      'drop': 0,
      'errors': 0,
    },
    'plugins': <Object?>[
      <String, Object?>{
        'id': 'checkout-aop',
        'state': 'available',
        'ver': '1.0.0',
        'n': 3,
        'span': 2,
        'instant': 1,
        'counter': 0,
        'drop': 1,
        'bad': 0,
        'trunc': 0,
        'dur': 1200,
        'max': 900,
        'cat': <String, Object?>{'business': 3},
      },
      <String, Object?>{
        'id': 'broken-aop',
        'state': 'failed',
        'why': 'setup timeout',
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
    'events': <Object?>[
      <String, Object?>{
        'n': 'BuildOwner.buildScope',
        'c': 'Dart',
        't': 100,
        'd': 4000,
        'p': 'X',
        'pid': 1,
        'tid': 2,
        'id': 'async-1',
        'scope': 'build',
        'bid': 'flow-1',
        'a': <String, Object?>{
          'file': 'package:demo/main.dart',
          'line': 42,
          'nested': <Object?>[1, true, 'kept'],
        },
      },
      <String, Object?>{
        'n': 'checkout.fetch',
        'c': 'business',
        't': 500,
        'd': 1200,
        'src': 'checkout-aop',
        'iso': 'isolates/1',
        'u': 'package:checkout/checkout.dart',
        'l': 42,
        'col': 7,
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
        'dropF': 1,
        'dropE': 1,
        'unknown': 1,
      },
      'cpu': <String, Object?>{
        'period': 1000,
        'depth': 32,
        'n': 1,
        'start': 0,
        'span': 1000,
        'pid': 42,
        'f': <Object?>[
          <String, Object?>{
            'n': 'main',
            'in': 1,
            'ex': 1,
            'k': 'Dart',
            'u': 'package:demo/main.dart',
            'l': 12,
            'c': 4,
          },
        ],
        's': <Object?>[
          <String, Object?>{
            't': 10,
            'tid': 2,
            's': <Object?>[0],
            'vm': 'Dart',
            'user': 'user-tag',
            'trunc': true,
          },
        ],
        'dropped': 1,
      },
      'heap': <String, Object?>{
        'before': <String, Object?>{'use': 10, 'cap': 20, 'ext': 1},
        'after': <String, Object?>{'use': 12, 'cap': 24, 'ext': 2},
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
        'dropped': 1,
        'samples': <Object?>[
          <String, Object?>{'t': 0, 'use': 10, 'cap': 20, 'ext': 1},
          <String, Object?>{'t': 100000, 'use': 12, 'cap': 24, 'ext': 2},
        ],
        'interval': 100,
        'drop': 1,
        'gb': <String, Object?>{'use': 20, 'cap': 30, 'ext': 3},
        'ga': <String, Object?>{'use': 22, 'cap': 32, 'ext': 4},
        'reset': 1700000000000,
        'gcAt': 1700000000123,
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
          'num': '1',
          'group': 'groups/1',
          'run': true,
          'ports': 2,
          'libs': 12,
          'ext': 1,
          'rpcs': <Object?>['ext.cockpit'],
          'start': 1700000000000,
          'sys': false,
          'pause': 'PauseStart',
          'pauseT': 1700000000001,
          'async': false,
          'error': null,
          'exit': false,
          'ex': 'Unhandled',
          'root': 'package:demo/main.dart',
          'bp': 1,
          'new': <String, Object?>{'use': 1, 'cap': 2, 'ext': 0},
          'old': <String, Object?>{'use': 9, 'cap': 20, 'ext': 1},
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
        'dropB': 1,
        'dropA': 1,
        'events': <Object?>[
          <String, Object?>{
            'k': 'IsolateStart',
            't': 1700000000100,
            'id': 'isolates/3',
            'name': 'worker-2',
            'group': 'groups/1',
            'rpc': 'ext.cockpit',
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
          'status': 'paused',
          'details': 'unhandled exception',
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
        'ext': <Object?>['ext.cockpit'],
      },
      'vmem': <String, Object?>{
        'before': <String, Object?>{
          't': 0,
          'root': <String, Object?>{
            'n': 'Process',
            's': 1024,
            'c': <Object?>[
              <String, Object?>{
                'n': 'Dart heap',
                's': 768,
                'c': <Object?>[
                  <String, Object?>{'n': 'new', 's': 256},
                ],
              },
              <String, Object?>{'n': 'Native', 's': 256, 'drop': 2},
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
    ...overrides,
  };
  overrides.forEach((key, value) {
    if (value == null) {
      document.remove(key);
    }
  });
  return CockpitPerformanceReport.fromJson(document);
}

Directory _packageRoot() {
  final current = Directory.current;
  final directSchema = File(
    p.join(current.path, 'schema', 'cockpit.performance.v2.schema.json'),
  );
  if (directSchema.existsSync()) {
    return current;
  }
  final workspacePackage = Directory(
    p.join(current.path, 'packages', 'cockpit_protocol'),
  );
  if (File(
    p.join(
      workspacePackage.path,
      'schema',
      'cockpit.performance.v2.schema.json',
    ),
  ).existsSync()) {
    return workspacePackage;
  }
  throw StateError('Cannot locate the cockpit_protocol package root.');
}
