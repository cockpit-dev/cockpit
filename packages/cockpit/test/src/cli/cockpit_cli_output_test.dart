import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:cockpit/src/cli/cockpit_cli_output.dart';
import 'package:cockpit/src/cli/cockpit_cli_runtime.dart';
import 'package:cockpit/src/cli/cockpit_command_runner.dart';
import 'package:cockpit/src/cli/commands/explain_command.dart';
import 'package:lon/lon.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('CockpitCliOutputSelection', () {
    test('defaults to AI brief output', () {
      final parser = ArgParser();
      cockpitAddCliOutputOptions(parser);

      final selection = CockpitCliOutputSelection.fromArguments(
        parser.parse(const <String>[]),
      );

      expect(selection.format, CockpitCliFormat.lon);
      expect(selection.view, CockpitCliOutputView.brief);
      expect(parser.usage, contains('lon by default'));
      expect(
        parser.usage,
        contains('json only for jq or a JSON-only consumer'),
      );
      expect(parser.usage, contains('--format'));
      expect(parser.usage, isNot(contains('--stdout-format')));
      expect(parser.usage, contains('--view'));
      expect(parser.usage, isNot(contains('--verbosity')));
      expect(parser.usage, isNot(contains('--detail')));
      expect(
        () => parser.parse(const <String>['--verbosity', 'full']),
        throwsA(isA<ArgParserException>()),
      );
      expect(
        () => parser.parse(const <String>['--view', 'minimal']),
        throwsA(isA<ArgParserException>()),
      );
      expect(
        () => parser.parse(const <String>['--view', 'standard']),
        throwsA(isA<ArgParserException>()),
      );
      expect(selection.outputPath, isNull);
    });

    test('reads explicit output controls', () {
      final parser = ArgParser();
      cockpitAddCliOutputOptions(parser);

      final selection = CockpitCliOutputSelection.fromArguments(
        parser.parse(const <String>[
          '--format',
          'none',
          '--view',
          'more',
          '--output',
          'result.json',
        ]),
      );

      expect(selection.format, CockpitCliFormat.none);
      expect(selection.view, CockpitCliOutputView.more);
      expect(selection.outputPath, 'result.json');
    });

    test('pre-scans output controls before command parsing', () {
      final selection = CockpitCliOutputSelection.fromRawArguments(
        const <String>['daemon', 'stop', '--format=json', '--view', 'full'],
      );

      expect(selection.format, CockpitCliFormat.json);
      expect(selection.view, CockpitCliOutputView.full);
    });
  });

  test('structured CLI input accepts JSON and LON objects', () {
    final runtime = CockpitCliRuntime(
      stdoutSink: StringBuffer(),
      stderrSink: StringBuffer(),
    );

    expect(runtime.structuredObject('{"width":800}', null), <String, Object?>{
      'width': 800,
    });
    expect(
      runtime.structuredObject('{width:800 height:600}', null),
      <String, Object?>{'width': 800, 'height': 600},
    );
    expect(
      runtime.structuredObject('width: 800\nheight: 600', null),
      <String, Object?>{'width': 800, 'height': 600},
    );
    expect(
      () => runtime.structuredObject('{}', 'input.lon'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('--input and --input-file'),
        ),
      ),
    );
  });

  test('operation examples omit empty input', () {
    expect(
      cockpitOperationCommandExample(
        'target.discover',
        null,
        const <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{},
        },
        sessionAvailable: true,
      ),
      'cockpit op run target.discover',
    );
  });

  test('interactive progress is isolated to stderr', () {
    final stdout = StringBuffer();
    final stderr = StringBuffer();
    final runtime = CockpitCliRuntime(
      stdoutSink: stdout,
      stderrSink: stderr,
      interactive: true,
    );

    runtime.configureOutput(
      command: 'dev.start',
      selection: const CockpitCliOutputSelection(),
    );
    runtime.progress('Building and launching Flutter...');

    expect(stdout, isEmpty);
    expect(stderr.toString(), '[cockpit] Building and launching Flutter...\n');
  });

  test('progress stays silent outside interactive terminals', () {
    final stderr = StringBuffer();
    final runtime = CockpitCliRuntime(
      stdoutSink: StringBuffer(),
      stderrSink: stderr,
    );

    runtime.configureOutput(
      command: 'dev.start',
      selection: const CockpitCliOutputSelection(),
    );
    runtime.progress('Preparing Flutter target...');

    expect(stderr, isEmpty);
  });

  test('none format suppresses interactive progress', () {
    final stderr = StringBuffer();
    final runtime = CockpitCliRuntime(
      stdoutSink: StringBuffer(),
      stderrSink: stderr,
      interactive: true,
    );

    runtime.configureOutput(
      command: 'dev.start',
      selection: const CockpitCliOutputSelection(format: CockpitCliFormat.none),
    );
    runtime.progress('Resolving checkout...');

    expect(stderr, isEmpty);
  });

  test('LON, JSON, and YAML preserve one semantic projection', () {
    const renderer = CockpitCliOutputRenderer();
    const data = <String, Object?>{
      'ok': true,
      'action': 'status',
      'session': '1',
      'state': <String, Object?>{
        'lifecycle': 'ready',
        'runtimeErrors': <Object?>[],
      },
    };

    final lonValue = lon.decode(
      renderer.renderAi(
        command: 'dev.status',
        data: data,
        view: CockpitCliOutputView.brief,
      ),
    );
    final jsonValue = jsonDecode(
      renderer.renderJson(
        command: 'dev.status',
        data: data,
        view: CockpitCliOutputView.brief,
      ),
    );
    final yamlValue = jsonDecode(
      jsonEncode(
        loadYaml(
          renderer.renderYaml(
            command: 'dev.status',
            data: data,
            view: CockpitCliOutputView.brief,
          ),
        ),
      ),
    );

    expect(jsonValue, lonValue);
    expect(yamlValue, lonValue);
  });

  test('failed operations share one concise brief error projection', () {
    const renderer = CockpitCliOutputRenderer();
    const data = <String, Object?>{
      'operationId': 'operation-1',
      'kind': 'target.launch',
      'lifecycle': 'completed',
      'outcome': 'failed',
      'failure': <String, Object?>{
        'code': 'androidDeviceUnavailable',
        'message': 'Android device emulator-5554 is unavailable.',
        'retryable': false,
        'category': 'application',
        'responsibleLayer': 'worker',
      },
    };

    final lonValue = lon.decode(
      renderer.renderAi(
        command: 'target.launch',
        data: data,
        view: CockpitCliOutputView.brief,
      ),
    );
    final jsonValue = jsonDecode(
      renderer.renderJson(
        command: 'target.launch',
        data: data,
        view: CockpitCliOutputView.brief,
      ),
    );
    final yamlValue = jsonDecode(
      jsonEncode(
        loadYaml(
          renderer.renderYaml(
            command: 'target.launch',
            data: data,
            view: CockpitCliOutputView.brief,
          ),
        ),
      ),
    );

    expect(lonValue, <Object?, Object?>{
      'op': 'operation-1',
      'error': <Object?, Object?>{
        'code': 'androidDeviceUnavailable',
        'message': 'Android device emulator-5554 is unavailable.',
      },
    });
    expect(jsonValue, lonValue);
    expect(yamlValue, lonValue);

    final more =
        lon.decode(
              renderer.renderAi(
                command: 'target.launch',
                data: data,
                view: CockpitCliOutputView.more,
              ),
            )!
            as Map<Object?, Object?>;
    final error = more['error']! as Map<Object?, Object?>;
    expect(more['outcome'], 'failed');
    expect(error['category'], 'application');
    expect(error['layer'], 'worker');
    expect(error, isNot(contains('retry')));
  });

  test('session output omits the internal checkout identity hash', () {
    const renderer = CockpitCliOutputRenderer();
    final hash = 'c' * 64;
    final value =
        jsonDecode(
              renderer.renderJson(
                command: 'session.list',
                data: <String, Object?>{
                  'items': <Object?>[
                    <String, Object?>{
                      'handleId': '1',
                      'projectPath': '/workspace/app',
                      'entrypoint': 'cockpit/main.dart',
                      'platform': 'macos',
                      'deviceId': 'macos',
                      'lastState': 'ready',
                      'checkoutPath': '/workspace',
                      'checkoutIdentity': hash,
                    },
                  ],
                  'totalCount': 1,
                },
                view: CockpitCliOutputView.more,
              ),
            )
            as Map<String, Object?>;
    final item =
        (value['items']! as List<Object?>).single as Map<String, Object?>;

    expect(item['checkout'], '/workspace');
    expect(item, isNot(contains('checkoutId')));
    expect(jsonEncode(value), isNot(contains(hash)));
  });

  test('session brief distinguishes app liveness from bridge readiness', () {
    const renderer = CockpitCliOutputRenderer();
    final value =
        lon.decode(
              renderer.renderAi(
                command: 'session.show',
                data: const <String, Object?>{
                  'handleId': '9',
                  'lifecycle': 'connecting',
                  'ready': false,
                  'reachable': false,
                  'live': <String, Object?>{
                    'status': <String, Object?>{
                      'state': 'starting',
                      'appReachable': true,
                      'remoteSessionReachable': false,
                    },
                  },
                },
                view: CockpitCliOutputView.brief,
              ),
            )!
            as Map<Object?, Object?>;

    expect(value['session'], 9);
    expect(value['lifecycle'], 'connecting');
    expect(value['ready'], isFalse);
    expect(value['state'], 'starting');
    expect(value['appLive'], isTrue);
    expect(value['bridgeLive'], isFalse);
    expect(value, isNot(contains('reachable')));
  });

  test('dev status brief preserves reconnecting app and bridge state', () {
    const renderer = CockpitCliOutputRenderer();
    final value =
        lon.decode(
              renderer.renderAi(
                command: 'dev.status',
                data: const <String, Object?>{
                  'action': 'status',
                  'session': '9',
                  'state': <String, Object?>{
                    'status': <String, Object?>{
                      'state': 'starting',
                      'appReachable': true,
                      'remoteSessionReachable': false,
                    },
                  },
                },
                view: CockpitCliOutputView.brief,
              ),
            )!
            as Map<Object?, Object?>;

    expect(value['session'], 9);
    expect(value['state'], 'starting');
    expect(value['appLive'], isTrue);
    expect(value['bridgeLive'], isFalse);
  });

  test('dev status brief omits unknown app reachability', () {
    const renderer = CockpitCliOutputRenderer();
    final value =
        lon.decode(
              renderer.renderAi(
                command: 'dev.status',
                data: const <String, Object?>{
                  'action': 'status',
                  'session': '9',
                  'state': <String, Object?>{
                    'status': <String, Object?>{
                      'state': 'starting',
                      'appReachable': null,
                      'remoteSessionReachable': false,
                    },
                  },
                },
                view: CockpitCliOutputView.brief,
              ),
            )!
            as Map<Object?, Object?>;

    expect(value, isNot(contains('appLive')));
    expect(value['bridgeLive'], isFalse);
  });

  test('dev inspect brief keeps bounded mounted context only on a miss', () {
    const renderer = CockpitCliOutputRenderer();
    final value =
        lon.decode(
              renderer.renderAi(
                command: 'dev.inspect',
                data: const <String, Object?>{
                  'action': 'inspect',
                  'session': '5',
                  'state': <String, Object?>{
                    'route': '/editor',
                    'query': 'missing',
                    'count': 0,
                    'matches': <Object?>[],
                    'mounted': <Object?>[
                      <String, Object?>{'sel': '@title', 'can': 'tap|type'},
                      <String, Object?>{'sel': 'Save', 'can': 'tap'},
                    ],
                    'partial': true,
                  },
                },
                view: CockpitCliOutputView.brief,
              ),
            )!
            as Map<Object?, Object?>;

    expect(value['count'], 0);
    expect(value['mounted'], hasLength(2));
  });

  test('dev status does not invent diagnostics that were not collected', () {
    const renderer = CockpitCliOutputRenderer();

    final value =
        lon.decode(
              renderer.renderAi(
                command: 'dev.status',
                data: const <String, Object?>{
                  'ok': true,
                  'action': 'status',
                  'session': '1',
                  'state': <String, Object?>{
                    'lifecycle': 'ready',
                    'projectPath': '/workspace/app',
                    'entrypoint': 'lib/main.dart',
                  },
                },
                view: CockpitCliOutputView.brief,
              ),
            )!
            as Map<Object?, Object?>;
    expect(value, isNot(contains('ok')));
    expect(value, isNot(contains('state')));
    expect(value, isNot(contains('errors')));
    expect(value, isNot(contains('netFailures')));
  });

  test('dev more status reports diagnostic zeroes when collected', () {
    const renderer = CockpitCliOutputRenderer();

    final value =
        lon.decode(
              renderer.renderAi(
                command: 'dev.status',
                data: const <String, Object?>{
                  'ok': true,
                  'action': 'status',
                  'session': '1',
                  'state': <String, Object?>{
                    'lifecycle': 'ready',
                    'runtimeErrors': <String, Object?>{
                      'summary': <String, Object?>{'errorCount': 0},
                    },
                    'network': <String, Object?>{
                      'summary': <String, Object?>{'failureCount': 0},
                    },
                  },
                },
                view: CockpitCliOutputView.more,
              ),
            )!
            as Map<Object?, Object?>;
    expect(value['errors'], 0);
    expect(value['netFailures'], 0);
  });

  test('dev diagnose more omits routine healthy projection noise', () {
    const renderer = CockpitCliOutputRenderer();

    final value =
        lon.decode(
              renderer.renderAi(
                command: 'dev.diagnose',
                data: const <String, Object?>{
                  'ok': true,
                  'action': 'diagnose',
                  'session': '4',
                  'state': <String, Object?>{
                    'lifecycle': 'ready',
                    'platform': 'macos',
                    'ui': <String, Object?>{
                      'diagnosticLevel': 'investigate',
                      'truncated': true,
                      'uiSummary': <String, Object?>{
                        'visibleTargetCount': 32,
                        'targetsWithCockpitIdCount': 14,
                        'targetsWithTextCount': 20,
                        'accessibilityTargetCount': 22,
                        'accessibilityTraversalCount': 22,
                        'textPreviews': <String>['Dashboard'],
                      },
                    },
                    'target': <String, Object?>{
                      'platform': 'macos',
                      'targetKind': 'flutterApp',
                      'foregroundSurface': 'desktopWindow',
                      'selectedPlane': 'flutterSemanticPlane',
                      'currentRouteName': '/',
                      'whatMatters': 'Current route is /.',
                      'recommendedNextStep': 'runNextCommand',
                      'capabilityProfile': <String, Object?>{
                        'surfaceKinds': <String>['flutterSemantic'],
                        'supportedCommands': <String>[],
                        'actionCapabilities': <String>['tap'],
                        'evidenceCapabilities': <String>['screenshot'],
                        'qualityFlags': <String>[],
                      },
                    },
                    'runtimeErrors': <String, Object?>{
                      'summary': <String, Object?>{'errorCount': 0},
                    },
                    'network': <String, Object?>{
                      'available': true,
                      'summary': <String, Object?>{
                        'totalEntryCount': 56,
                        'capturedEntryCount': 56,
                        'failureCount': 0,
                        'inFlightCount': 0,
                      },
                      'endpointSummaries': <Object?>[
                        <String, Object?>{
                          'method': 'GET',
                          'uriPattern': '/healthy',
                          'requestCount': 56,
                        },
                      ],
                    },
                    'logs': <String, Object?>{
                      'appId': 'internal-app-id',
                      'available': true,
                      'lines': <Object?>[],
                    },
                  },
                },
                view: CockpitCliOutputView.more,
              ),
            )!
            as Map<Object?, Object?>;

    final ui = value['ui']! as Map<Object?, Object?>;
    final target = value['target']! as Map<Object?, Object?>;
    final capabilities = target['caps']! as Map<Object?, Object?>;
    expect(ui, isNot(contains('profile')));
    expect(ui, isNot(contains('partial')));
    expect(ui, isNot(contains('a11yOrder')));
    expect(target, isNot(contains('route')));
    expect(target, isNot(contains('note')));
    expect(target, isNot(contains('next')));
    expect(capabilities, isNot(contains('commands')));
    expect(capabilities, isNot(contains('quality')));
    expect(value, isNot(contains('network')));
    expect(value, isNot(contains('logs')));
  });

  test('dev diagnose more keeps actionable health evidence', () {
    const renderer = CockpitCliOutputRenderer();

    final value =
        lon.decode(
              renderer.renderAi(
                command: 'dev.diagnose',
                data: const <String, Object?>{
                  'action': 'diagnose',
                  'session': '4',
                  'state': <String, Object?>{
                    'target': <String, Object?>{
                      'currentRouteName': '/loading',
                      'whatMatters': 'No visible Flutter targets were found.',
                      'recommendedNextStep': 'captureScreenshot',
                    },
                    'runtimeErrors': <String, Object?>{
                      'summary': <String, Object?>{'errorCount': 0},
                    },
                    'network': <String, Object?>{
                      'available': true,
                      'summary': <String, Object?>{
                        'failureCount': 1,
                        'inFlightCount': 1,
                      },
                      'recentFailures': <Object?>[
                        <String, Object?>{
                          'requestId': 9,
                          'method': 'GET',
                          'uri': '/failed',
                          'statusCode': 500,
                          'state': 'completed',
                        },
                      ],
                    },
                    'logs': <String, Object?>{
                      'available': true,
                      'lines': <String>['A useful warning'],
                    },
                  },
                },
                view: CockpitCliOutputView.more,
              ),
            )!
            as Map<Object?, Object?>;

    final target = value['target']! as Map<Object?, Object?>;
    final network = value['network']! as Map<Object?, Object?>;
    final logs = value['logs']! as Map<Object?, Object?>;
    expect(target['note'], 'No visible Flutter targets were found.');
    expect(target['next'], 'captureScreenshot');
    expect(network['failures'], 1);
    expect(network['active'], 1);
    expect(network['recent'], hasLength(1));
    expect(logs['lines'], <Object?>['A useful warning']);
  });

  test('dev brief output keeps only decision fields', () {
    const renderer = CockpitCliOutputRenderer();
    final value =
        lon.decode(
              renderer.renderAi(
                command: 'dev.tap',
                data: const <String, Object?>{
                  'ok': true,
                  'action': 'tap',
                  'session': '2',
                  'changed': 'observed',
                  'state': <String, Object?>{
                    'command': <String, Object?>{
                      'command': <String, Object?>{
                        'success': true,
                        'commandId': 'verbose-id',
                        'durationMs': 123,
                        'locator': <String, Object?>{
                          'matchedKind': 'text',
                          'matchedValue': 'Documents',
                        },
                        'effectiveSnapshotOptions': <String, Object?>{
                          'profile': 'baseline',
                        },
                      },
                    },
                    'postcondition': <String, Object?>{
                      'effectiveSnapshotOptions': <String, Object?>{
                        'profile': 'live',
                      },
                    },
                  },
                },
                view: CockpitCliOutputView.brief,
              ),
            )!
            as Map<Object?, Object?>;

    expect(value, isNot(contains('ok')));
    expect(value['session'], 2);
    expect(value['changed'], 'observed');
    expect(value, isNot(contains('action')));
    expect(value, isNot(contains('state')));
    expect(value, isNot(contains('_meta')));
  });

  test('dev scroll brief output confirms that the target is visible', () {
    const renderer = CockpitCliOutputRenderer();
    final value =
        lon.decode(
              renderer.renderAi(
                command: 'dev.scroll',
                data: const <String, Object?>{
                  'ok': true,
                  'action': 'scroll',
                  'session': '5',
                  'state': <String, Object?>{},
                },
                view: CockpitCliOutputView.brief,
              ),
            )!
            as Map<Object?, Object?>;

    expect(value['visible'], isTrue);
    expect(value['session'], 5);
    expect(value, isNot(contains('ok')));
    expect(value, isNot(contains('action')));
    expect(value, isNot(contains('state')));
  });

  test('dev tree brief output keeps the compact selector index', () {
    const renderer = CockpitCliOutputRenderer();
    final value =
        lon.decode(
              renderer.renderAi(
                command: 'dev.tree',
                data: <String, Object?>{
                  'ok': true,
                  'action': 'tree',
                  'session': '5',
                  'state': <String, Object?>{
                    'profile': 'brief',
                    'route': '/home',
                    'count': 1,
                    'targets': <Object?>[
                      <String, Object?>{'sel': '#new-task', 'can': 'tap'},
                    ],
                  },
                },
                view: CockpitCliOutputView.brief,
              ),
            )!
            as Map<Object?, Object?>;

    expect(value['route'], '/home');
    expect(value['count'], 1);
    expect(value['targets'], <Object?>[
      <String, Object?>{'sel': '#new-task', 'can': 'tap'},
    ]);
  });

  test('dev tree brief output counts every omitted target', () {
    const renderer = CockpitCliOutputRenderer();
    final value =
        lon.decode(
              renderer.renderAi(
                command: 'dev.tree',
                data: <String, Object?>{
                  'ok': true,
                  'action': 'tree',
                  'session': '5',
                  'state': <String, Object?>{
                    'profile': 'brief',
                    'route': '/home',
                    'count': 24,
                    'targets': <Object?>[
                      for (var index = 0; index < 12; index += 1)
                        <String, Object?>{
                          'sel': '#target-$index',
                          'label': 'Target $index',
                          'can': 'tap',
                        },
                    ],
                    'more': 12,
                    'partial': true,
                  },
                },
                view: CockpitCliOutputView.brief,
              ),
            )!
            as Map<Object?, Object?>;
    final targets = value['targets']! as List<Object?>;

    expect(value['count'], 24);
    expect(value['more'], 24 - targets.length);
  });

  test(
    'dev screenshot exposes capture source only when diagnostic or degraded',
    () {
      const renderer = CockpitCliOutputRenderer();
      const data = <String, Object?>{
        'ok': true,
        'action': 'screenshot',
        'session': '1',
        'state': <String, Object?>{
          'capture': 'flutterView',
          'fallback': false,
          'degraded': 'systemSurfaceMismatch',
          'surface': <String, Object?>{
            'relation': 'differentApp',
            'app': 'dev.cockpit.demo',
            'front': 'com.example.other',
          },
          'plane': 'flutterSemanticPlane',
          'width': 800,
          'height': 600,
        },
        'evidence': <String, Object?>{
          'actual': <String, Object?>{'path': '/tmp/current.png'},
        },
      };

      final minimal =
          lon.decode(
                renderer.renderAi(
                  command: 'dev.screenshot',
                  data: data,
                  view: CockpitCliOutputView.brief,
                ),
              )!
              as Map<Object?, Object?>;
      expect(minimal['capture'], 'flutterView');
      expect(minimal['fallback'], isFalse);
      expect(minimal['degraded'], 'systemSurfaceMismatch');
      expect(minimal['surface'], containsPair('relation', 'differentApp'));
      expect(minimal['path'], '/tmp/current.png');
      expect(minimal, isNot(contains('state')));

      final standard =
          lon.decode(
                renderer.renderAi(
                  command: 'dev.screenshot',
                  data: data,
                  view: CockpitCliOutputView.more,
                ),
              )!
              as Map<Object?, Object?>;
      expect(standard['capture'], 'flutterView');
      expect(standard['surface'], containsPair('front', 'com.example.other'));
      expect(standard['plane'], 'flutterSemanticPlane');
      expect(standard['width'], 800);
      expect(standard['height'], 600);
    },
  );

  test('dev network keeps a bounded index and body paths only', () {
    const renderer = CockpitCliOutputRenderer();
    const data = <String, Object?>{
      'ok': true,
      'action': 'network',
      'session': '1',
      'state': <String, Object?>{
        'available': true,
        'summary': <String, Object?>{
          'totalEntryCount': 42,
          'capturedEntryCount': 80,
          'failureCount': 2,
          'inFlightCount': 1,
          'truncated': true,
          'query': <String, Object?>{},
        },
        'endpointSummaries': <Object?>[
          <String, Object?>{
            'method': 'GET',
            'uriPattern': '/api/items',
            'requestCount': 10,
            'failureCount': 1,
            'averageDurationMs': 24,
            'lastStatusCode': 500,
          },
        ],
        'entries': <Object?>[
          <String, Object?>{
            'requestId': '37',
            'method': 'GET',
            'uri': 'https://example.test/api/items',
            'protocol': 'http',
            'state': 'receiving',
            'statusCode': 200,
            'durationMs': 24,
            'responseBodyBytes': 1024,
            'responseHeaders': <String, String>{'authorization': '********'},
            'responseBodyPreview': 'large preview must not be minimal',
            'sha256': 'unused-digest',
          },
        ],
        'body': <String, String>{'response': '/tmp/network-37-response.json'},
        'absent': <String>['request'],
        'continuing': true,
      },
      'evidence': <String, String>{'response': '/tmp/network-37-response.json'},
      'next': 'cockpit dev network 37 --body response',
    };

    final rendered = renderer.renderAi(
      command: 'dev.network',
      data: data,
      view: CockpitCliOutputView.brief,
    );

    expect(rendered, contains('id:"37"'));
    expect(rendered, contains('active:1'));
    expect(rendered, contains('response:/tmp/network-37-response.json'));
    expect(rendered, contains('absent:[request]'));
    expect(
      RegExp(
        RegExp.escape('/tmp/network-37-response.json'),
      ).allMatches(rendered),
      hasLength(1),
    );
    expect(rendered, contains('continuing:true'));
    expect(rendered, isNot(contains('bytes')));
    expect(rendered, isNot(contains('responseHeaders')));
    expect(rendered, isNot(contains('large preview')));
    expect(rendered, isNot(contains('sha256')));
    expect(rendered, isNot(contains('unused-digest')));

    final standard = renderer.renderAi(
      command: 'dev.network',
      data: data,
      view: CockpitCliOutputView.more,
    );
    expect(standard, isNot(contains('responseHeaders')));
    expect(standard, isNot(contains('large preview')));
    expect(standard, isNot(contains('unused-digest')));
  });

  test('dev network summarizes real WebSocket frame activity', () {
    const renderer = CockpitCliOutputRenderer();
    const data = <String, Object?>{
      'ok': true,
      'action': 'network',
      'session': '3',
      'state': <String, Object?>{
        'entries': <Object?>[
          <String, Object?>{
            'requestId': '9',
            'method': 'GET',
            'uri': 'wss://example.test/live',
            'protocol': 'webSocket',
            'state': 'open',
            'requestBodyBytes': 12,
            'responseBodyBytes': 28,
            'webSocket': <String, Object?>{
              'sentFrames': 2,
              'receivedFrames': 1,
              'sentBytes': 12,
              'receivedBytes': 28,
              'framesTruncated': true,
              'recentFrames': <Object?>[
                <String, Object?>{
                  'sequence': 3,
                  'direction': 'received',
                  'kind': 'text',
                  'at': '2026-08-11T00:00:00Z',
                  'payloadBytes': 28,
                  'finalFragment': true,
                  'compressed': false,
                  'preview': 'pong',
                },
              ],
            },
          },
        ],
      },
    };

    final brief =
        lon.decode(
              renderer.renderAi(
                command: 'dev.network',
                data: data,
                view: CockpitCliOutputView.brief,
              ),
            )!
            as Map<Object?, Object?>;
    final briefEntry =
        (brief['entries']! as List<Object?>).single as Map<Object?, Object?>;
    final briefSocket = briefEntry['socket']! as Map<Object?, Object?>;
    expect(briefSocket['sent'], 2);
    expect(briefSocket['received'], 1);
    expect(briefSocket['partial'], isTrue);
    expect(briefSocket, isNot(contains('recvBytes')));
    expect(briefSocket['last'], containsPair('preview', 'pong'));

    final more =
        lon.decode(
              renderer.renderAi(
                command: 'dev.network',
                data: data,
                view: CockpitCliOutputView.more,
              ),
            )!
            as Map<Object?, Object?>;
    final moreEntry =
        (more['entries']! as List<Object?>).single as Map<Object?, Object?>;
    final moreSocket = moreEntry['socket']! as Map<Object?, Object?>;
    expect(moreEntry['reqBytes'], 12);
    expect(moreEntry['resBytes'], 28);
    expect(moreSocket['recvBytes'], 28);
    expect(moreSocket['frames'], hasLength(1));
  });

  test('structured command flags do not encode JSON in their names', () {
    final runner = CockpitCommandRunner(
      runtime: CockpitCliRuntime(
        stdoutSink: StringBuffer(),
        stderrSink: StringBuffer(),
      ),
    );

    final op = runner.commands['op']!.subcommands['run']!;
    expect(op.argParser.options, contains('input'));
    expect(op.argParser.options, contains('session'));
    expect(op.argParser.options, isNot(contains('input-json')));
    expect(op.argParser.options, isNot(contains('kind')));
    expect(op.argParser.options['timeout']!.defaultsTo, isNull);
    expect(
      op.argParser.options['timeout']!.help,
      contains('advertised budget'),
    );
    expect(op.invocation, 'cockpit op run KIND [arguments]');
    expect(op.argParser.parse(const <String>['viewport.set']).rest, <String>[
      'viewport.set',
    ]);
    expect(runner.commands, isNot(contains('operation')));
    expect(runner.commands, isNot(contains('exec')));
    expect(runner.commands, isNot(contains('raw')));
    expect(
      runner.commands['explain']!.invocation,
      'cockpit explain KIND [arguments]',
    );

    for (final commandName in <String>['case', 'suite']) {
      final command = runner.commands[commandName]!;
      final runOptions = command.subcommands['run']!.argParser.options;
      expect(runOptions, contains('inputs'));
      expect(runOptions, contains('file'));
      expect(runOptions, contains('input-format'));
      expect(runOptions, isNot(contains('inputs-json')));
      expect(
        command.subcommands['validate']!.argParser.options,
        contains('input-format'),
      );
    }
  });

  test('usage errors honor an explicitly requested JSON format', () async {
    final stderr = StringBuffer();
    final runner = CockpitCommandRunner(
      runtime: CockpitCliRuntime(
        stdoutSink: StringBuffer(),
        stderrSink: stderr,
      ),
    );

    final exitCode = await runner.run(const <String>[
      'daemon',
      'stop',
      '--mode',
      'immediate',
      '--format',
      'json',
    ]);

    expect(exitCode, cockpitUsageExitCode);
    final envelope = jsonDecode(stderr.toString()) as Map<String, Object?>;
    expect(envelope, isNot(contains('ok')));
    expect((envelope['error']! as Map<String, Object?>)['code'], 'usage');
  });

  test('workspace exposes indexed documents to CLI-only clients', () {
    final runner = CockpitCommandRunner(
      runtime: CockpitCliRuntime(
        stdoutSink: StringBuffer(),
        stderrSink: StringBuffer(),
      ),
    );

    final workspace = runner.commands['workspace'];
    expect(workspace, isNotNull);
    expect(workspace!.subcommands, contains('documents'));
    final documents = workspace.subcommands['documents'];
    expect(documents, isNotNull);
    expect(documents!.argParser.options, contains('workspace-id'));
    expect(documents.argParser.options, contains('kind'));
    expect(documents.argParser.options, contains('relative-path'));
  });

  test('E2E commands expose focused discovery and session selection', () {
    final runner = CockpitCommandRunner(
      runtime: CockpitCliRuntime(
        stdoutSink: StringBuffer(),
        stderrSink: StringBuffer(),
      ),
    );

    for (final commandName in const <String>['case', 'suite']) {
      final command = runner.commands[commandName]!;
      final list = command.subcommands['list']!;
      final run = command.subcommands['run']!;

      expect(list.argParser.options.keys, containsAll(<String>['id', 'path']));
      expect(run.argParser.options['session']!.abbr, 's');
      expect(run.argParser.options, contains('target-id'));
    }
  });

  test('brief target listings retain the entrypoint identity', () {
    const renderer = CockpitCliOutputRenderer();
    final output = renderer.renderAi(
      command: 'target.list',
      data: const <String, Object?>{
        'items': <Object?>[
          <String, Object?>{
            'targetId': 'target-1',
            'platform': 'macos',
            'targetKind': 'flutterApp',
            'entrypoint': 'cockpit/main.dart',
          },
        ],
      },
      view: CockpitCliOutputView.brief,
    );

    expect(output, contains('cockpit/main.dart'));
  });

  test('target inspect unwraps operation output at every useful density', () {
    const renderer = CockpitCliOutputRenderer();
    const data = <String, Object?>{
      'kind': 'target.inspect',
      'outcome': 'succeeded',
      'output': <String, Object?>{
        'targetId': 'target-1',
        'platform': 'android',
        'targetKind': 'flutterApp',
        'foregroundSurface': 'flutterSemantic',
        'selectedPlane': 'flutterSemanticPlane',
        'currentRouteName': '/inbox',
        'recommendedNextStep': 'runNextCommand',
        'capabilityProfile': <String, Object?>{
          'surfaceKinds': <String>['flutterSemantic', 'nativeUi'],
          'actionCapabilities': <String>['tap', 'typeText'],
          'evidenceCapabilities': <String>['nativeScreenshot'],
        },
        'systemControl': <String, Object?>{
          'adapter': 'android.adb',
          'preferredPlane': 'flutterSemanticPlane',
          'availableActions': <String>['tap'],
          'blockedActions': <String>['dumpUiTree'],
        },
      },
    };

    final minimal =
        lon.decode(
              renderer.renderAi(
                command: 'target.inspect',
                data: data,
                view: CockpitCliOutputView.brief,
              ),
            )!
            as Map<Object?, Object?>;
    expect(minimal['platform'], 'android');
    expect(minimal['route'], '/inbox');
    expect(minimal, isNot(contains('targetId')));
    expect(minimal['caps'], containsPair('actions', 2));
    expect(minimal['system'], containsPair('blocked', 1));

    final standard =
        lon.decode(
              renderer.renderAi(
                command: 'target.inspect',
                data: data,
                view: CockpitCliOutputView.more,
              ),
            )!
            as Map<Object?, Object?>;
    expect(standard['target'], 'target-1');
    expect(standard['targetType'], 'flutterApp');
    expect(
      standard['caps'],
      containsPair('actions', <Object?>['tap', 'typeText']),
    );
  });

  test('more and full listings omit integrity digests', () {
    const renderer = CockpitCliOutputRenderer();
    const data = <String, Object?>{
      'items': <Object?>[
        <String, Object?>{
          'documentId': 'document-1',
          'relativePath': 'cases/login.yaml',
          'sha256': 'unused-digest',
          'modifiedAt': '2026-08-05T00:00:00Z',
        },
      ],
    };

    final standard = renderer.renderAi(
      command: 'workspace.documents',
      data: data,
      view: CockpitCliOutputView.more,
    );
    expect(standard, contains('modified'));
    expect(standard, isNot(contains('sha256')));
    expect(standard, isNot(contains('unused-digest')));
    expect(
      renderer.renderJson(
        command: 'workspace.documents',
        data: data,
        view: CockpitCliOutputView.full,
      ),
      isNot(contains('unused-digest')),
    );
  });

  test('artifact listings omit hashes and byte counts', () {
    const renderer = CockpitCliOutputRenderer();
    const data = <String, Object?>{
      'items': <Object?>[
        <String, Object?>{
          'artifactId': 'artifact-1',
          'kind': 'attempt.screenshot',
          'relativePath': 'artifacts/screenshot.png',
          'mediaType': 'image/png',
          'sizeBytes': 140965,
          'sha256': 'unused-digest',
        },
      ],
    };

    final output = renderer.renderAi(
      command: 'artifact.list',
      data: data,
      view: CockpitCliOutputView.more,
    );

    expect(output, contains('artifacts/screenshot.png'));
    expect(output, isNot(contains('140965')));
    expect(output, isNot(contains('sha256')));
    expect(output, isNot(contains('unused-digest')));
  });

  test('run listings keep the bounded page compact and scannable', () {
    const renderer = CockpitCliOutputRenderer();
    final data = <String, Object?>{
      'items': <Object?>[
        for (var index = 0; index < 7; index += 1)
          <String, Object?>{
            'runId': 'r$index',
            'documentId': 'case-$index',
            'lifecycle': 'completed',
            'outcome': index == 1 ? 'failed' : 'passed',
            'stability': 'stable',
            'submittedAt': '2026-08-14T04:0$index:00Z',
            if (index == 1)
              'failure': <String, Object?>{
                'primary': <String, Object?>{
                  'code': 'assertionFailed',
                  'message': 'A deliberately verbose failure message.',
                },
              },
          },
      ],
      'totalCount': 7,
    };

    final value =
        lon.decode(
              renderer.renderAi(
                command: 'run.list',
                data: data,
                view: CockpitCliOutputView.brief,
              ),
            )!
            as Map<Object?, Object?>;
    final items = value['items']! as List<Object?>;

    expect(items, hasLength(7));
    expect(items.first, <Object?, Object?>{
      'run': 'r0',
      'doc': 'case-0',
      'state': 'passed',
      'submitted': '2026-08-14T04:00:00Z',
    });
    expect(value['total'], 7);
    expect(value, isNot(contains('failure')));
    expect(value, isNot(contains('error')));
    expect(value, isNot(contains('more')));
  });

  test('run events keep terminal state and failures in brief output', () {
    const renderer = CockpitCliOutputRenderer();
    final data = <String, Object?>{
      'items': <Object?>[
        for (var sequence = 1; sequence <= 8; sequence += 1)
          <String, Object?>{
            'type': 'event',
            'event': <String, Object?>{
              'sequence': sequence,
              'kind': 'step.passed',
              'stepExecutionId': 'main/step-$sequence',
              'status': 'passed',
            },
          },
        <String, Object?>{
          'type': 'event',
          'event': <String, Object?>{
            'sequence': 9,
            'kind': 'step.failed',
            'stepExecutionId': 'main/capture',
            'status': 'failed',
            'failure': <String, Object?>{
              'primary': <String, Object?>{
                'code': 'evidenceFailed',
                'message': 'Screenshot failed.',
                'retryable': true,
              },
            },
          },
        },
        <String, Object?>{
          'type': 'event',
          'event': <String, Object?>{
            'sequence': 10,
            'kind': 'run.completed',
            'lifecycle': 'completed',
            'outcome': 'failed',
            'stability': 'stable',
          },
        },
        <String, Object?>{'type': 'terminal', 'afterSequence': 10},
      ],
    };

    final value =
        lon.decode(
              renderer.renderAi(
                command: 'run.events',
                data: data,
                view: CockpitCliOutputView.brief,
              ),
            )!
            as Map<Object?, Object?>;
    final failures = value['failures']! as List<Object?>;
    final failure = failures.single as Map<Object?, Object?>;
    final finalEvent = value['final']! as Map<Object?, Object?>;

    expect(value['stream'], 'terminal');
    expect(value['after'], 10);
    expect(value['events'], 10);
    expect(failure['step'], 'main/capture');
    expect(
      (failure['error']! as Map<Object?, Object?>)['code'],
      'evidenceFailed',
    );
    expect(finalEvent['outcome'], 'failed');
    expect(value, isNot(contains('_meta')));
  });

  test('streaming run events apply JSONL view projection per line', () {
    final stdout = StringBuffer();
    final runtime =
        CockpitCliRuntime(stdoutSink: stdout, stderrSink: StringBuffer())
          ..configureOutput(
            command: 'run.events',
            selection: const CockpitCliOutputSelection(
              format: CockpitCliFormat.jsonl,
            ),
          );

    runtime.jsonLine(const <String, Object?>{
      'type': 'event',
      'event': <String, Object?>{
        'sequence': 7,
        'kind': 'step.passed',
        'stepExecutionId': 'main/capture',
        'status': 'passed',
        'artifacts': <Object?>[
          <String, Object?>{
            'artifactId': 'artifact-1',
            'sha256': 'unused-digest',
            'sizeBytes': 140965,
          },
        ],
      },
    });

    final line = jsonDecode(stdout.toString()) as Map<String, Object?>;
    final event = line['event']! as Map<String, Object?>;
    expect(line['type'], 'event');
    expect(event['sequence'], 7);
    expect(event['artifacts'], 1);
    expect(stdout.toString(), isNot(contains('sha256')));
    expect(stdout.toString(), isNot(contains('unused-digest')));
    expect(stdout.toString(), isNot(contains('140965')));
  });

  test('full streaming run events omit integrity digests', () {
    final stdout = StringBuffer();
    final runtime =
        CockpitCliRuntime(stdoutSink: stdout, stderrSink: StringBuffer())
          ..configureOutput(
            command: 'run.events',
            selection: const CockpitCliOutputSelection(
              format: CockpitCliFormat.jsonl,
              view: CockpitCliOutputView.full,
            ),
          );

    runtime.jsonLine(const <String, Object?>{
      'type': 'event',
      'event': <String, Object?>{
        'sequence': 7,
        'kind': 'step.passed',
        'artifacts': <Object?>[
          <String, Object?>{'sha256': 'complete-digest'},
        ],
      },
    });

    expect(stdout.toString(), isNot(contains('complete-digest')));
  });

  test('suite report exposes complete offline bundle export', () {
    final runner = CockpitCommandRunner(
      runtime: CockpitCliRuntime(
        stdoutSink: StringBuffer(),
        stderrSink: StringBuffer(),
      ),
    );

    final suite = runner.commands['suite'];
    expect(suite, isNotNull);
    final report = suite!.subcommands['report'];
    expect(report, isNotNull);
    expect(report!.argParser.options, contains('run-id'));
    expect(report.argParser.options, contains('output-dir'));
  });

  group('CockpitCliOutputRenderer', () {
    test('renders default AI output as canonical LON', () {
      const renderer = CockpitCliOutputRenderer();

      final text = renderer.renderAi(
        command: 'daemon.status',
        data: const <String, Object?>{
          'running': true,
          'healthy': true,
          'auth': 'yolo',
          'unused': null,
        },
        view: CockpitCliOutputView.brief,
      );
      final value = lon.decode(text)! as Map<Object?, Object?>;

      expect(text, '{state:ready auth:yolo}');
      expect(value['state'], 'ready');
      expect(value['auth'], 'yolo');
      expect(value, isNot(contains('unused')));
      expect(lon.encode(value), text);
    });

    test('keeps root and workspace receipts focused', () {
      const renderer = CockpitCliOutputRenderer();
      final root = lon.decode(
        renderer.renderAi(
          command: 'root.add',
          data: const <String, Object?>{
            'rootId': 'r0000000001',
            'state': 'active',
            'canonicalPath': '/work',
            'filesystemIdentity': 'posix:hash',
            'registeredAt': '2026-08-11T00:00:00Z',
          },
          view: CockpitCliOutputView.brief,
        ),
      )!;
      final workspace = lon.decode(
        renderer.renderAi(
          command: 'workspace.register',
          data: const <String, Object?>{
            'workspaceId': 'w0000000001',
            'projectId': 'p0000000001',
            'rootId': 'r0000000001',
            'checkoutId': 'c0000000001',
            'state': 'active',
            'canonicalPath': '/work/app',
            'filesystemIdentity': 'posix:hash',
          },
          view: CockpitCliOutputView.brief,
        ),
      )!;

      expect(root, <Object?, Object?>{
        'root': 'r0000000001',
        'state': 'active',
        'path': '/work',
      });
      expect(workspace, <Object?, Object?>{
        'project': 'p0000000001',
        'workspace': 'w0000000001',
        'state': 'active',
        'path': '/work/app',
      });
    });

    test('flattens successful target task receipts', () {
      const renderer = CockpitCliOutputRenderer();
      final value = lon.decode(
        renderer.renderAi(
          command: 'target.register',
          data: const <String, Object?>{
            'operationId': 'o0000000001',
            'workspaceId': 'w0000000001',
            'kind': 'target.register',
            'lifecycle': 'completed',
            'outcome': 'succeeded',
            'idempotencyKey': 'register-1',
            'output': <String, Object?>{'targetId': 't0000000001'},
            'submittedAt': '2026-08-11T00:00:00Z',
          },
          view: CockpitCliOutputView.brief,
        ),
      )!;

      expect(value, <Object?, Object?>{
        'op': 'o0000000001',
        'target': 't0000000001',
      });
    });

    test('prioritizes failing report rows and reports omissions', () {
      const renderer = CockpitCliOutputRenderer(moreMaximumBytes: 2400);
      final cases = <Map<String, Object?>>[
        <String, Object?>{
          'entryId': 'failed-entry',
          'caseId': 'failed-case',
          'outcome': 'failed',
          'stability': 'stable',
          'targetId': 'android',
          'attempts': <Object?>[
            <String, Object?>{
              'attemptId': 'attempt-failed',
              'number': 1,
              'outcome': 'failed',
              'targetId': 'android',
              'failure': <String, Object?>{
                'code': 'assertionFailed',
                'message': 'Expected Save to be visible.',
              },
            },
          ],
        },
        for (var index = 0; index < 80; index += 1)
          <String, Object?>{
            'entryId': 'passed-entry-$index',
            'caseId': 'passed-case-$index',
            'outcome': 'passed',
            'stability': 'stable',
            'targetId': 'android',
            'attempts': <Object?>[
              <String, Object?>{
                'attemptId': 'attempt-passed-$index',
                'number': 1,
                'outcome': 'passed',
                'targetId': 'android',
              },
            ],
          },
      ];

      final text = renderer.renderAi(
        command: 'suite.report',
        data: <String, Object?>{
          'schemaVersion': 'cockpit.report/v2',
          'projectId': 'project',
          'workspaceId': 'workspace',
          'runId': 'run-1',
          'suiteId': 'regression',
          'lifecycle': 'completed',
          'outcome': 'failed',
          'stability': 'stable',
          'durationMs': 4200,
          'counts': const <String, Object?>{
            'total': 81,
            'passed': 80,
            'failed': 1,
          },
          'cases': cases,
        },
        view: CockpitCliOutputView.more,
      );

      final value = lon.decode(text)! as Map<Object?, Object?>;
      final renderedCases = value['cases']! as List<Object?>;

      expect(text.length, lessThanOrEqualTo(2400));
      expect(
        (renderedCases.first as Map<Object?, Object?>)['entry'],
        'failed-entry',
      );
      expect(value['more'], isA<int>());
      expect(lon.encode(value), text);
    });

    test('renders exact JSON at full view', () {
      const renderer = CockpitCliOutputRenderer();
      final data = <String, Object?>{
        'items': <Object?>[
          for (var index = 0; index < 100; index += 1)
            <String, Object?>{'id': 'item-$index', 'value': index},
        ],
      };

      final text = renderer.renderJson(
        command: 'artifact.list',
        data: data,
        view: CockpitCliOutputView.full,
      );
      final result = jsonDecode(text) as Map<String, Object?>;

      expect(result['items']! as List<Object?>, hasLength(100));
      expect(result, isNot(contains('_meta')));
    });

    test('projects analysis for both AI text and JSON view', () {
      const renderer = CockpitCliOutputRenderer();
      final operation = <String, Object?>{
        'operationId': 'operation-1',
        'kind': 'analyze.files',
        'lifecycle': 'completed',
        'outcome': 'failed',
        'workspaceId': 'workspace-1',
        'output': <String, Object?>{
          'workspaceRoot': '/private/workspace',
          'success': false,
          'clean': false,
          'summary': '1 error, 1 warning',
          'totalDiagnostics': 2,
          'severityCounts': <String, Object?>{'error': 1, 'warning': 1},
          'diagnostics': <Object?>[
            <String, Object?>{
              'severity': 'warning',
              'code': 'unused_local_variable',
              'message': 'Unused value.',
              'path': 'lib/a.dart',
              'line': 8,
              'column': 3,
              'documentationUrl': 'https://example.invalid/unused',
            },
            <String, Object?>{
              'severity': 'error',
              'code': 'undefined_identifier',
              'message': 'Undefined name.',
              'path': 'lib/b.dart',
              'line': 4,
              'column': 7,
            },
          ],
        },
      };

      final ai = renderer.renderAi(
        command: 'op.run',
        data: operation,
        view: CockpitCliOutputView.brief,
      );
      final aiValue = lon.decode(ai)! as Map<Object?, Object?>;
      final json =
          jsonDecode(
                renderer.renderJson(
                  command: 'op.run',
                  data: operation,
                  view: CockpitCliOutputView.brief,
                ),
              )
              as Map<String, Object?>;

      final aiOutput = aiValue['output']! as Map<Object?, Object?>;
      final aiDiagnostics = aiOutput['diag']! as List<Object?>;
      expect(
        (aiDiagnostics.first as Map<Object?, Object?>)['code'],
        'undefined_identifier',
      );
      expect(ai, isNot(contains('documentationUrl')));
      expect(ai, isNot(contains('/private/workspace')));
      final output = json['output']! as Map<String, Object?>;
      final diagnostics = output['diag']! as List<Object?>;
      expect((diagnostics.first as Map<String, Object?>)['severity'], 'error');
      expect(output, isNot(contains('workspaceRoot')));
    });

    test('preserves concise op session receipts', () {
      const renderer = CockpitCliOutputRenderer();
      final text = renderer.renderAi(
        command: 'op.run',
        data: const <String, Object?>{
          'operationId': 'operation-1',
          'kind': 'surface.inspect',
          'lifecycle': 'completed',
          'outcome': 'succeeded',
          'sessionHandle': '1',
          'idempotencyKey': 'cli-operation-1',
          'output': <String, Object?>{'success': true},
        },
        view: CockpitCliOutputView.brief,
      );
      final value = lon.decode(text)! as Map<Object?, Object?>;

      expect(value['session'], 1);
      expect(value, isNot(contains('idem')));
      expect(value, isNot(contains('lifecycle')));
      expect(value, isNot(contains('outcome')));
      expect(text, isNot(contains('success')));
    });

    test('system action output exposes a path without inline stdout', () {
      const renderer = CockpitCliOutputRenderer();
      const operation = <String, Object?>{
        'operationId': 'operation-system',
        'kind': 'system.action',
        'lifecycle': 'completed',
        'outcome': 'succeeded',
        'output': <String, Object?>{
          'action': 'readUiTree',
          'availability': 'available',
          'success': true,
          'path': '/tmp/ui-tree.txt',
          'stdout': '<hierarchy>must-not-render</hierarchy>',
          'recommendedNextStep': 'resolveNativeLocator',
        },
      };

      for (final view in <CockpitCliOutputView>[
        CockpitCliOutputView.brief,
        CockpitCliOutputView.more,
      ]) {
        final value =
            lon.decode(
                  renderer.renderAi(
                    command: 'op.run',
                    data: operation,
                    view: view,
                  ),
                )!
                as Map<Object?, Object?>;
        final output = value['output']! as Map<Object?, Object?>;
        expect(output['action'], 'readUiTree');
        expect(output['path'], '/tmp/ui-tree.txt');
        expect(output, isNot(contains('stdout')));
        expect(output, isNot(contains('success')));
        expect(output, isNot(contains('availability')));
      }
    });

    test('lease list output preserves bounded pagination metadata', () {
      const renderer = CockpitCliOutputRenderer();
      final text = renderer.renderAi(
        command: 'op.run',
        data: const <String, Object?>{
          'operationId': 'operation-leases',
          'kind': 'lease.list',
          'lifecycle': 'completed',
          'outcome': 'succeeded',
          'output': <String, Object?>{
            'items': <Object?>[
              <String, Object?>{
                'leaseId': 'lease-50',
                'resourceKind': 'device',
                'resourceId': 'android:emulator-5554',
                'state': 'active',
                'requestedAt': '2026-08-14T00:00:00.000Z',
              },
            ],
            'total': 3113,
            'next': 'lease-50',
          },
        },
        view: CockpitCliOutputView.brief,
      );
      final value = lon.decode(text)! as Map<Object?, Object?>;
      final output = value['output']! as Map<Object?, Object?>;

      expect(output['total'], 3113);
      expect(output['next'], 'lease-50');
      expect(output['counts'], <Object?, Object?>{'active': 1});
      expect(output['actionable'], 1);
    });

    test('renders one exact operation without truncation metadata', () {
      const renderer = CockpitCliOutputRenderer();
      final text = renderer.renderAi(
        command: 'op.list',
        data: const <Object?>[
          <String, Object?>{
            'kind': 'viewport.set',
            'title': 'viewport.set',
            'description': 'Cockpit viewport.set operation.',
            'scope': 'workspace',
            'mutationClass': 'mutating',
            'idempotency': 'required',
            'executionMode': 'synchronous',
            'defaultTimeoutMs': 120000,
            'maximumTimeoutMs': 600000,
            'requestSchemaRef': 'cockpit://operations/schema#viewport.set',
            'responseSchemaRef': 'cockpit://operations/schema#result',
            'safetyEffects': <Object?>[],
          },
        ],
        view: CockpitCliOutputView.brief,
      );
      final value = lon.decode(text)! as Map<Object?, Object?>;

      expect(value['kind'], 'viewport.set');
      expect(value['timeoutMs'], 120000);
      expect(value['maxTimeoutMs'], 600000);
      expect(value, isNot(contains('_meta')));
      expect(value, isNot(contains('title')));
      expect(value, isNot(contains('description')));
    });

    test('keeps latest Flutter logs and omits repeated operation identity', () {
      const renderer = CockpitCliOutputRenderer();
      final text = renderer.renderAi(
        command: 'op.run',
        data: <String, Object?>{
          'operationId': 'operation-logs',
          'workspaceId': 'workspace-1',
          'kind': 'logs.read',
          'lifecycle': 'completed',
          'outcome': 'succeeded',
          'output': <String, Object?>{
            'operationId': 'operation-logs',
            'workspaceId': 'workspace-1',
            'appId': 'app-1',
            'source': 'app_snapshot',
            'available': true,
            'lines': <Object?>[
              for (var index = 0; index < 20; index += 1) 'line-$index',
            ],
          },
        },
        view: CockpitCliOutputView.brief,
      );

      final value = lon.decode(text)! as Map<Object?, Object?>;
      final output = value['output']! as Map<Object?, Object?>;
      final lines = output['lines']! as List<Object?>;

      expect(RegExp('operation-logs').allMatches(text), hasLength(1));
      expect(lines, contains('line-19'));
      expect(lines, isNot(contains('line-0')));
      expect(value['more'], isA<int>());
    });

    test('emits LON without losing operation hierarchy', () {
      const renderer = CockpitCliOutputRenderer();
      final text = renderer.renderAi(
        command: 'op.run',
        data: const <String, Object?>{
          'operationId': 'op-1',
          'kind': 'command.run',
          'lifecycle': 'completed',
          'outcome': 'succeeded',
          'workspaceId': 'workspace-1',
          'output': <String, Object?>{
            'selectedPlane': 'flutterSemanticPlane',
            'recommendedNextStep': 'readPostActionState',
            'command': <String, Object?>{
              'commandId': 'tap-save',
              'commandType': 'tap',
              'success': true,
              'durationMs': 18,
              'locatorResolution': <String, Object?>{
                'matchedKind': 'text',
                'matchedValue': 'Save',
              },
            },
          },
        },
        view: CockpitCliOutputView.more,
      );

      final value = lon.decode(text)! as Map<Object?, Object?>;
      final output = value['output']! as Map<Object?, Object?>;
      final command = output['command']! as Map<Object?, Object?>;
      final locator = command['loc']! as Map<Object?, Object?>;

      expect(value['op'], 'op-1');
      expect(output['plane'], 'flutterSemanticPlane');
      expect(output['next'], 'readPostActionState');
      expect(command['id'], 'tap-save');
      expect(command['type'], 'tap');
      expect(command, isNot(contains('success')));
      expect(command['ms'], 18);
      expect(locator, <Object?, Object?>{'kind': 'text', 'value': 'Save'});
      expect(lon.encode(value), text);
    });

    test('renders errors as canonical LON', () {
      const renderer = CockpitCliOutputRenderer();

      final text = renderer.renderError(
        code: 'operationDenied',
        message: 'Authorization is required.',
        retryable: false,
        responsibleLayer: 'supervisor',
      );

      expect(
        text,
        '{error:{code:operationDenied message:"Authorization is required."}}',
      );
      expect(lon.decode(text), <Object?, Object?>{
        'error': <Object?, Object?>{
          'code': 'operationDenied',
          'message': 'Authorization is required.',
        },
      });

      final more =
          lon.decode(
                renderer.renderError(
                  code: 'operationDenied',
                  message: 'Authorization is required.',
                  retryable: true,
                  category: 'environment',
                  responsibleLayer: 'supervisor',
                  view: CockpitCliOutputView.more,
                ),
              )!
              as Map<Object?, Object?>;
      expect(more, <Object?, Object?>{
        'error': <Object?, Object?>{
          'code': 'operationDenied',
          'message': 'Authorization is required.',
          'retry': true,
          'category': 'environment',
          'layer': 'supervisor',
        },
      });
    });

    test('shortens public fields without rewriting live schema fields', () {
      const renderer = CockpitCliOutputRenderer();
      final text = renderer.renderJson(
        command: 'explain',
        data: const <String, Object?>{
          'inputContract': <String, Object?>{
            'schemaRef': 'cockpit://operations/schema#example',
            'schema': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'maximumTimeoutMs': <String, Object?>{'type': 'integer'},
              },
              'required': <String>['maximumTimeoutMs'],
            },
          },
          'recommendedCommand': 'cockpit dev status',
          'op': "cockpit op run app.status --input '{}'",
        },
        view: CockpitCliOutputView.full,
      );
      final value = jsonDecode(text) as Map<String, Object?>;
      final input = value['input']! as Map<String, Object?>;
      final schema = input['schema']! as Map<String, Object?>;
      final properties = schema['properties']! as Map<String, Object?>;

      expect(value['use'], 'cockpit dev status');
      expect(value['op'], "cockpit op run app.status --input '{}'");
      expect(input['ref'], 'cockpit://operations/schema#example');
      expect(properties, contains('maximumTimeoutMs'));
      expect(schema['required'], <Object?>['maximumTimeoutMs']);
    });

    test('uses one concise vocabulary across public output families', () {
      const renderer = CockpitCliOutputRenderer();
      final value =
          jsonDecode(
                renderer.renderJson(
                  command: 'contract.sample',
                  data: const <String, Object?>{
                    'operationId': 'o123',
                    'targetId': 't123',
                    'targetKind': 'flutterApp',
                    'appId': 'a123',
                    'sessionId': 's123',
                    'documentKind': 'suite',
                    'requestedPlane': 'native',
                    'actualPlane': 'flutter',
                    'logicalWidth': 800,
                    'logicalHeight': 600,
                    'diagnosticsTruncated': true,
                    'stderrPreview': 'failed',
                    'runtimeSteps': <Object?>['tap'],
                    'appReachable': true,
                    'remoteSessionReachable': false,
                    'failure': <String, Object?>{
                      'code': 'blocked',
                      'retryable': false,
                    },
                    'sha256': 'unused',
                    'sourceSha256': 'also-unused',
                    'screenshotDigest': 'still-unused',
                    'sizeBytes': 999,
                  },
                  view: CockpitCliOutputView.full,
                ),
              )
              as Map<String, Object?>;

      expect(value['op'], 'o123');
      expect(value['target'], 't123');
      expect(value['targetType'], 'flutterApp');
      expect(value['docType'], 'suite');
      expect(value['app'], 'a123');
      expect(value['runtime'], 's123');
      expect(value['wanted'], 'native');
      expect(value['plane'], 'flutter');
      expect(value['logicalW'], 800);
      expect(value['logicalH'], 600);
      expect(value['diagPartial'], isTrue);
      expect(value['stderr'], 'failed');
      expect(value['steps'], <Object?>['tap']);
      expect(value['appLive'], isTrue);
      expect(value['bridgeLive'], isFalse);
      expect(value['error'], containsPair('code', 'blocked'));
      expect(value, isNot(contains('sha256')));
      expect(value, isNot(contains('sourceSha256')));
      expect(value, isNot(contains('screenshotDigest')));
      expect(value, isNot(contains('bytes')));
    });

    test('explain brief output preserves input enum values', () {
      const renderer = CockpitCliOutputRenderer();
      final text = renderer.renderJson(
        command: 'explain',
        data: const <String, Object?>{
          'operation': <String, Object?>{
            'kind': 'command.run',
            'scope': 'workspace',
            'mutationClass': 'mutating',
            'idempotency': 'required',
            'executionMode': 'synchronous',
            'timeoutMs': 300000,
            'maximumTimeoutMs': 1800000,
          },
          'inputContract': <String, Object?>{
            'available': true,
            'schemaRef': 'cockpit://operations/schema#command.run',
            'precision': 'structural',
            'schema': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'sessionId': <String, Object?>{
                  'type': 'string',
                  'x-cockpit-injected-by': '--session',
                },
                'profile': <String, Object?>{
                  'type': 'string',
                  'enum': <String>[
                    'minimal',
                    'locate',
                    'tree',
                    'standard',
                    'inspect',
                    'evidence',
                  ],
                },
              },
              'required': <String>['sessionId'],
              'additionalProperties': false,
            },
          },
          'recommendedCommand': 'cockpit dev tap "Exact text"',
        },
        view: CockpitCliOutputView.brief,
      );
      final value = jsonDecode(text) as Map<String, Object?>;
      final input = value['input']! as Map<String, Object?>;
      final fields = input['fields']! as Map<String, Object?>;
      final profile = fields['profile']! as Map<String, Object?>;

      expect(
        profile['values'],
        'minimal|locate|tree|standard|inspect|evidence',
      );
      expect(value, isNot(contains('_meta')));
    });

    test('explain examples omit CLI-injected session identity', () {
      expect(
        cockpitOperationInputExample(const <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'sessionId': <String, Object?>{
              'type': 'string',
              'x-cockpit-injected-by': '--session',
            },
            'action': <String, Object?>{'type': 'string'},
          },
          'examples': <Object?>[
            <String, Object?>{
              'sessionId': 'session-example',
              'action': 'readUiTree',
            },
          ],
        }),
        <String, Object?>{'action': 'readUiTree'},
      );
    });
  });

  test('writer persists JSON and emits only its path receipt', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cockpit-cli-output-',
    );
    addTearDown(() async => directory.delete(recursive: true));
    final stdout = StringBuffer();
    final destination = File('${directory.path}/nested/result.json');
    final writer = CockpitCliOutputWriter(
      stdoutSink: stdout,
      workingDirectory: directory.path,
    );

    await writer.writeSuccess(
      command: 'run.get',
      data: const <String, Object?>{
        'runId': 'run-1',
        'lifecycle': 'completed',
        'outcome': 'passed',
      },
      selection: CockpitCliOutputSelection(
        format: CockpitCliFormat.json,
        view: CockpitCliOutputView.full,
        outputPath: destination.path,
      ),
    );

    final persisted =
        jsonDecode(await destination.readAsString()) as Map<String, Object?>;
    expect(persisted['run'], 'run-1');
    final receipt = jsonDecode(stdout.toString()) as Map<String, Object?>;
    expect(receipt, <String, Object?>{'path': destination.path});
  });

  test(
    'writer persists canonical LON and emits only its LON receipt',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'cockpit-cli-output-lon-',
      );
      addTearDown(() async => directory.delete(recursive: true));
      final stdout = StringBuffer();
      final destination = File('${directory.path}/result.lon');
      final writer = CockpitCliOutputWriter(
        stdoutSink: stdout,
        workingDirectory: directory.path,
      );

      await writer.writeSuccess(
        command: 'dev.status',
        data: const <String, Object?>{
          'ok': true,
          'session': '1',
          'state': 'ready',
        },
        selection: CockpitCliOutputSelection(
          view: CockpitCliOutputView.full,
          outputPath: destination.path,
        ),
      );

      final persisted = lon.decode(await destination.readAsString());
      expect(persisted, <Object?, Object?>{'session': 1, 'state': 'ready'});
      final receipt = lon.decode(stdout.toString())! as Map<Object?, Object?>;
      expect(receipt, <Object?, Object?>{'path': destination.path});
    },
  );

  test('writer persists YAML and emits only its path receipt', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cockpit-cli-output-yaml-',
    );
    addTearDown(() async => directory.delete(recursive: true));
    final stdout = StringBuffer();
    final destination = File('${directory.path}/result.yaml');
    final writer = CockpitCliOutputWriter(
      stdoutSink: stdout,
      workingDirectory: directory.path,
    );

    await writer.writeSuccess(
      command: 'dev.status',
      data: const <String, Object?>{'sessionHandle': '1', 'lifecycle': 'ready'},
      selection: CockpitCliOutputSelection(
        format: CockpitCliFormat.yaml,
        view: CockpitCliOutputView.full,
        outputPath: destination.path,
      ),
    );

    final persisted = loadYaml(await destination.readAsString()) as YamlMap;
    expect(persisted['session'], 1);
    final receipt = loadYaml(stdout.toString()) as YamlMap;
    expect(jsonDecode(jsonEncode(receipt)), <String, Object?>{
      'path': destination.path,
    });
  });

  test('path format prints a screenshot artifact without --output', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cockpit-cli-screenshot-path-',
    );
    addTearDown(() async => directory.delete(recursive: true));
    final screenshot = File('${directory.path}/current.png');
    await screenshot.writeAsBytes(const <int>[1, 2, 3]);
    final stdout = StringBuffer();
    final writer = CockpitCliOutputWriter(stdoutSink: stdout);

    await writer.writeSuccess(
      command: 'dev.screenshot',
      data: <String, Object?>{
        'evidence': <String, Object?>{
          'actual': <String, Object?>{'path': screenshot.path},
        },
      },
      selection: const CockpitCliOutputSelection(format: CockpitCliFormat.path),
    );

    expect(stdout.toString().trim(), await screenshot.resolveSymbolicLinks());
  });

  test('path format prints one network body artifact', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cockpit-cli-network-path-',
    );
    addTearDown(() async => directory.delete(recursive: true));
    final body = File('${directory.path}/response.json');
    await body.writeAsString('{}');
    final stdout = StringBuffer();
    final writer = CockpitCliOutputWriter(stdoutSink: stdout);

    await writer.writeSuccess(
      command: 'dev.network',
      data: <String, Object?>{
        'evidence': <String, Object?>{'response': body.path},
      },
      selection: const CockpitCliOutputSelection(format: CockpitCliFormat.path),
    );

    expect(stdout.toString().trim(), await body.resolveSymbolicLinks());
  });

  test('path format prints one materialized system action artifact', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cockpit-cli-system-action-path-',
    );
    addTearDown(() async => directory.delete(recursive: true));
    final tree = File('${directory.path}/ui-tree.txt');
    await tree.writeAsString('<hierarchy/>');
    final stdout = StringBuffer();
    final writer = CockpitCliOutputWriter(stdoutSink: stdout);

    await writer.writeSuccess(
      command: 'op.run',
      data: <String, Object?>{
        'kind': 'system.action',
        'output': <String, Object?>{'path': tree.path},
      },
      selection: const CockpitCliOutputSelection(format: CockpitCliFormat.path),
    );

    expect(stdout.toString().trim(), await tree.resolveSymbolicLinks());
  });

  test(
    'writer rejects inline artifact and file content before output',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'cockpit-cli-output-artifact-',
      );
      addTearDown(() async => directory.delete(recursive: true));
      final destination = File('${directory.path}/result.json');
      final writer = CockpitCliOutputWriter(
        stdoutSink: StringBuffer(),
        workingDirectory: directory.path,
      );

      await expectLater(
        writer.writeSuccess(
          command: 'dev.screenshot',
          data: const <String, Object?>{
            'artifactPayloads': <String, Object?>{
              'screenshot.png': 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB',
            },
          },
          selection: CockpitCliOutputSelection(
            format: CockpitCliFormat.json,
            outputPath: destination.path,
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(contains('forbidden'), isNot(contains('iVBOR'))),
          ),
        ),
      );
      expect(await destination.exists(), isFalse);
    },
  );

  test('writer keeps stdout silent for output files when requested', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cockpit-cli-output-silent-',
    );
    addTearDown(() async => directory.delete(recursive: true));
    final stdout = StringBuffer();
    final writer = CockpitCliOutputWriter(
      stdoutSink: stdout,
      workingDirectory: directory.path,
    );

    await writer.writeSuccess(
      command: 'run.get',
      data: const <String, Object?>{'runId': 'run-1'},
      selection: const CockpitCliOutputSelection(
        format: CockpitCliFormat.none,
        view: CockpitCliOutputView.full,
        outputPath: 'result.json',
      ),
    );

    expect(stdout.toString(), isEmpty);
    expect(await File('${directory.path}/result.json').exists(), isTrue);
  });
}
