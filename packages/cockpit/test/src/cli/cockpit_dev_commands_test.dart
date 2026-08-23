import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/cli/cockpit_cli_runtime.dart';
import 'package:cockpit/src/cli/cockpit_command_runner.dart';
import 'package:cockpit/src/cli/cockpit_update_service.dart';
import 'package:cockpit/src/application/cockpit_ui_locator_advisor.dart';
import 'package:cockpit/src/cli/commands/dev_interaction_commands.dart';
import 'package:cockpit/src/cli/commands/skill_command.dart';
import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_version.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('top-level version is instant and matches pubspec', () async {
    final stdout = StringBuffer();
    final runner = CockpitCommandRunner(
      runtime: CockpitCliRuntime(
        stdoutSink: stdout,
        stderrSink: StringBuffer(),
        clientProvider: () async =>
            throw StateError('--version must not connect to the Supervisor.'),
      ),
    );

    final exitCode = await runner.run(const <String>['--version']);
    final pubspec =
        loadYaml(_cockpitPubspecFile().readAsStringSync()) as YamlMap;

    expect(exitCode, cockpitSuccessExitCode);
    expect(stdout.toString(), 'cockpit $cockpitVersion\n');
    expect(pubspec['version'], cockpitVersion);
  });

  test('dev exposes the task-oriented Flutter command surface', () {
    final runner = CockpitCommandRunner(
      runtime: CockpitCliRuntime(
        stdoutSink: StringBuffer(),
        stderrSink: StringBuffer(),
      ),
    );

    final dev = runner.commands['dev'];
    expect(dev, isNotNull);
    expect(
      dev!.subcommands.keys,
      containsAll(<String>{
        'start',
        'use',
        'status',
        'inspect',
        'tree',
        'tap',
        'hold',
        'double',
        'inc',
        'dec',
        'type',
        'press',
        'back',
        'dismiss',
        'recover',
        'open',
        'scroll',
        'wait',
        'screenshot',
        'network',
        'viewport',
        'reload',
        'restart',
        'diagnose',
        'stop',
      }),
    );
    expect(dev.subcommands['tap']!.usage, contains('cockpit dev tap'));
    expect(
      dev.subcommands['tap']!.invocation,
      'cockpit dev tap SELECTOR [arguments]',
    );
    expect(
      dev.subcommands['start']!.invocation,
      'cockpit dev start [ENTRYPOINT] [arguments]',
    );
    expect(
      dev.subcommands['viewport']!.invocation,
      'cockpit dev viewport WIDTHxHEIGHT [arguments]',
    );
    expect(
      dev.subcommands['open']!.invocation,
      'cockpit dev open URI [arguments]',
    );
    expect(
      dev.subcommands['status']!.description,
      'Read the current Flutter development session state.',
    );
    expect(
      dev.subcommands['start']!.argParser.options.keys,
      contains('session'),
    );
    expect(
      dev.subcommands['tap']!.argParser.options.keys,
      isNot(
        containsAll(<String>[
          'id',
          'key',
          'type',
          'tip',
          'route',
          'path',
          'index',
          'within',
          'fuzzy',
          'contains',
        ]),
      ),
    );
    expect(
      dev.subcommands['wait']!.argParser.options['quiet']!.defaultsTo,
      '500ms',
    );
    expect(
      dev.subcommands['scroll']!.argParser.options.keys,
      containsAll(<String>['direction', 'align', 'offset', 'max-scrolls']),
    );
    expect(
      dev.subcommands['scroll']!.argParser.options['align']!.defaultsTo,
      'nearest',
    );
    expect(
      dev.subcommands['scroll']!.argParser.options['offset']!.defaultsTo,
      '0',
    );
    expect(
      dev.subcommands['wait']!.argParser.options['network']!.defaultsTo,
      false,
    );
    expect(
      dev.subcommands['wait']!.argParser.options['timeout']!.defaultsTo,
      '30s',
    );
    expect(
      dev.subcommands['open']!.argParser.options['timeout']!.defaultsTo,
      '1m',
    );
    expect(
      dev.subcommands['recover']!.argParser.options['dialog']!.defaultsTo,
      isNull,
    );
    expect(
      dev.subcommands['recover']!.argParser.options.keys,
      isNot(contains('decision')),
    );
    expect(
      dev.subcommands['recover']!.argParser.options['timeout']!.defaultsTo,
      '2m',
    );
    expect(
      dev.subcommands['screenshot']!.argParser.options.keys,
      containsAll(<String>{
        'save',
        'compare',
        'diff',
        'pixel-tolerance',
        'max-changed-pixels',
      }),
    );
    expect(
      dev.subcommands['network']!.argParser.options.keys,
      containsAll(<String>{
        'before',
        'limit',
        'failures',
        'method',
        'uri',
        'body',
        'raw',
      }),
    );
    expect(
      dev.subcommands['network']!.argParser.options['limit']!.defaultsTo,
      '12',
    );
  });

  test('session-bound next commands keep the exact handle', () {
    for (final path in const <String>[
      'lib/src/cli/cockpit_dev_runtime.dart',
      'lib/src/cli/cockpit_dev_screenshot.dart',
      'lib/src/cli/cockpit_dev_network.dart',
    ]) {
      final source = File(path).readAsStringSync();
      final nextCommands =
          RegExp(r"(?:next:|'next':)(?:(?!,\s*\n).)*", dotAll: true)
              .allMatches(source)
              .where((match) => match.group(0)!.contains('cockpit dev '));
      expect(nextCommands, isNotEmpty, reason: path);
      for (final match in nextCommands) {
        expect(match.group(0), contains('--session'), reason: path);
      }
    }
  });

  test('skill exposes one bounded AI installation prompt', () async {
    final stdout = StringBuffer();
    final runner = CockpitCommandRunner(
      runtime: CockpitCliRuntime(
        stdoutSink: stdout,
        stderrSink: StringBuffer(),
        clientProvider: () async =>
            throw StateError('skill must not connect to the Supervisor.'),
      ),
    );

    final exitCode = await runner.run(const <String>['skill']);

    expect(exitCode, cockpitSuccessExitCode);
    expect(runner.commands, contains('skill'));
    expect(stdout.toString(), '{prompt:"$cockpitSkillPrompt"}\n');
    expect(cockpitSkillPrompt, contains(cockpitSkillInstallUrl));
    expect(cockpitSkillPrompt, contains('curl -fsSL'));
    expect(cockpitSkillInstallUrl, contains('raw.githubusercontent.com'));
  });

  test(
    'update checks for a release and returns the executable next step',
    () async {
      final stdout = StringBuffer();
      final runner = CockpitCommandRunner(
        runtime: CockpitCliRuntime(
          stdoutSink: stdout,
          stderrSink: StringBuffer(),
        ),
        updateService: CockpitUpdateService(
          latestVersionLookup: (_) async => '99.0.0',
        ),
      );

      final exitCode = await runner.run(const <String>['update', '--check']);

      expect(exitCode, cockpitSuccessExitCode);
      expect(runner.commands['update']!.argParser.options, contains('check'));
      expect(
        stdout.toString(),
        '{version:$cockpitVersion latest:99.0.0 next:"cockpit update"}\n',
      );
    },
  );

  test('update exposes one bounded runtime upgrade command', () {
    final runner = CockpitCommandRunner(
      runtime: CockpitCliRuntime(
        stdoutSink: StringBuffer(),
        stderrSink: StringBuffer(),
      ),
    );
    final update = runner.commands['update'];

    expect(update, isNotNull);
    expect(update!.description, 'Update Cockpit and reconnect its Supervisor.');
    expect(update.argParser.options['timeout']!.defaultsTo, '10m');
    expect(update.argParser.options['format']!.defaultsTo, 'lon');
  });

  test('operation discovery accepts an exact development session', () {
    final runner = CockpitCommandRunner(
      runtime: CockpitCliRuntime(
        stdoutSink: StringBuffer(),
        stderrSink: StringBuffer(),
      ),
    );
    final list = runner.commands['op']!.subcommands['list']!;

    expect(
      list.argParser.parse(const <String>['-s', '9']).option('session'),
      '9',
    );
  });

  test('dev compiles a multi-condition selector into one exact locator', () {
    final runner = CockpitCommandRunner(
      runtime: CockpitCliRuntime(
        stdoutSink: StringBuffer(),
        stderrSink: StringBuffer(),
      ),
    );
    final tap = runner.commands['dev']!.subcommands['tap']!;
    final arguments = tap.argParser.parse(const <String>[
      'Confirm >> TextButton#save-button@save-key["Save"]'
          '[tip="Save changes"][route="/editor"]'
          '[path="/editor/dialog/textbutton"]:nth(2)',
    ]);

    final locator = cockpitReadDevLocator(
      arguments,
      selector: arguments.rest.single,
    );

    expect(
      locator,
      const CockpitLocator(
        cockpitId: 'save-button',
        key: 'save-key',
        text: 'Save',
        tooltip: 'Save changes',
        type: 'TextButton',
        route: '/editor',
        path: '/editor/dialog/textbutton',
        index: 1,
        ancestor: CockpitLocator(type: 'Confirm'),
      ),
    );
  });

  test('dev requires one target selector', () {
    final runner = CockpitCommandRunner(
      runtime: CockpitCliRuntime(
        stdoutSink: StringBuffer(),
        stderrSink: StringBuffer(),
      ),
    );
    final tap = runner.commands['dev']!.subcommands['tap']!;
    final arguments = tap.argParser.parse(const <String>[]);

    expect(
      () => cockpitReadDevLocator(arguments, selector: null),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Target is required.',
        ),
      ),
    );
  });

  test('dev rejects invalid task flags before resolving a session', () async {
    final stderr = StringBuffer();
    final runner = CockpitCommandRunner(
      runtime: CockpitCliRuntime(
        stdoutSink: StringBuffer(),
        stderrSink: stderr,
      ),
    );

    final exitCode = await runner.run(const <String>[
      'dev',
      'wait',
      '--quiet',
      '49ms',
      '--format',
      'json',
    ]);

    expect(exitCode, cockpitDataExitCode);
    final error = jsonDecode(stderr.toString()) as Map<String, Object?>;
    expect((error['error']! as Map<String, Object?>)['code'], 'invalidInput');
  });

  test('dev open rejects a relative URI before resolving a session', () async {
    final stderr = StringBuffer();
    final runner = CockpitCommandRunner(
      runtime: CockpitCliRuntime(
        stdoutSink: StringBuffer(),
        stderrSink: stderr,
      ),
    );

    final exitCode = await runner.run(const <String>[
      'dev',
      'open',
      '/tasks/42',
      '--format',
      'json',
    ]);

    expect(exitCode, cockpitDataExitCode);
    final error = jsonDecode(stderr.toString()) as Map<String, Object?>;
    expect((error['error']! as Map<String, Object?>)['code'], 'invalidInput');
    expect(stderr.toString(), contains('include a scheme'));
  });

  test('dev network rejects body retrieval without a request ID', () async {
    final stderr = StringBuffer();
    final runner = CockpitCommandRunner(
      runtime: CockpitCliRuntime(
        stdoutSink: StringBuffer(),
        stderrSink: stderr,
      ),
    );

    final exitCode = await runner.run(const <String>[
      'dev',
      'network',
      '--body',
      'response',
      '--format',
      'json',
    ]);

    expect(exitCode, cockpitDataExitCode);
    final error = jsonDecode(stderr.toString()) as Map<String, Object?>;
    expect((error['error']! as Map<String, Object?>)['code'], 'invalidInput');
    expect(stderr.toString(), contains('--body requires a request ID'));
  });

  test('session state errors remain actionable without a daemon', () async {
    final stderr = StringBuffer();
    final runner = CockpitCommandRunner(
      runtime: CockpitCliRuntime(
        sessionHandleStoreProvider: () async =>
            throw const CockpitStorageException(
              code: 'storageCorrupt',
              path: '/tmp/cli-sessions.json',
              diagnostic: 'Unsupported CLI session schemaVersion.',
            ),
        stdoutSink: StringBuffer(),
        stderrSink: stderr,
      ),
    );

    final exitCode = await runner.run(const <String>[
      'session',
      'list',
      '--format',
      'json',
    ]);

    expect(exitCode, cockpitNoInputExitCode);
    final error = jsonDecode(stderr.toString()) as Map<String, Object?>;
    expect((error['error']! as Map<String, Object?>)['code'], 'storageCorrupt');
    expect(
      stderr.toString(),
      contains('Unsupported CLI session schemaVersion'),
    );
    expect(stderr.toString(), isNot(contains('internalError')));
  });

  test(
    'dev locator search is UI-only and returns shortest stable locators',
    () {
      final result = cockpitBuildUiLocatorMatchesFromOutput(<String, Object?>{
        'snapshot': <String, Object?>{
          'visibleTargets': <Object?>[
            <String, Object?>{
              'registrationId': 'internal-tooltip',
              'text': 'Documents',
              'tooltip': 'Documents',
              'typeName': 'Tooltip',
              'routeName': '/',
              'supportedCommands': <Object?>['tap'],
              'ancestors': const <Object?>[],
            },
            <String, Object?>{
              'registrationId': 'internal-text',
              'text': 'Documents',
              'typeName': 'RichText',
              'routeName': '/',
              'supportedCommands': const <Object?>[],
              'ancestors': const <Object?>[],
            },
            <String, Object?>{
              'registrationId': 'internal-id',
              'cockpitId': 'documents.nav',
              'text': 'Open documents',
              'typeName': 'IconButton',
              'routeName': '/',
              'supportedCommands': <Object?>['tap'],
              'ancestors': const <Object?>[],
            },
          ],
          'network': <String, Object?>{
            'entries': <Object?>[
              <String, Object?>{
                'uri': '/documents',
                'sha256': 'must-not-escape',
                'responseBodyPreview': 'Documents secret body',
              },
            ],
          },
        },
      }, 'Documents');

      expect(result['count'], 3);
      final matches = (result['matches']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(matches[0]['sel'], 'Documents');
      expect(matches[0]['can'], 'tap');
      expect(matches[1]['sel'], 'RichText["Documents"]');
      expect(matches[2]['sel'], '#documents.nav');
      expect(matches[2]['label'], 'Open documents');
      final encoded = jsonEncode(result);
      expect(encoded, isNot(contains('network')));
      expect(encoded, isNot(contains('sha256')));
      expect(encoded, isNot(contains('registrationId')));
      expect(encoded, isNot(contains('internal-')));
      expect(encoded, isNot(contains('path')));
    },
  );

  test(
    'dev locator miss returns bounded mounted context from one snapshot',
    () {
      final result = cockpitBuildUiLocatorMatchesFromOutput(<String, Object?>{
        'snapshot': <String, Object?>{
          'route': '/upgrade',
          'visibleTargets': <Object?>[
            for (var index = 0; index < 6; index += 1)
              <String, Object?>{
                'registrationId': 'action-$index',
                'cockpitId': 'action-$index',
                'text': 'Action $index',
                'typeName': 'FilledButton',
                'routeName': '/upgrade',
                'supportedCommands': <Object?>['tap'],
                'ancestors': const <Object?>[],
              },
          ],
        },
      }, 'Missing target');

      expect(result['count'], 0);
      expect(result['matches'], isEmpty);
      expect(result['route'], '/upgrade');
      final mounted = (result['mounted']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(mounted, hasLength(4));
      expect(mounted, everyElement(containsPair('can', 'tap')));
      expect(jsonEncode(result), isNot(contains('registrationId')));
    },
  );

  test('dev locator hit omits mounted fallback context', () {
    final result = cockpitBuildUiLocatorMatchesFromOutput(<String, Object?>{
      'snapshot': <String, Object?>{
        'route': '/edit',
        'visibleTargets': <Object?>[
          <String, Object?>{
            'registrationId': 'save',
            'cockpitId': 'save',
            'text': 'Save',
            'typeName': 'FilledButton',
            'routeName': '/edit',
            'supportedCommands': <Object?>['tap'],
            'ancestors': const <Object?>[],
          },
        ],
      },
    }, 'Save');

    expect(result['count'], 1);
    expect(result, isNot(contains('route')));
    expect(result, isNot(contains('mounted')));
  });

  test('dev target index returns only compact actionable selectors', () {
    final result = cockpitBuildUiTargetIndexFromOutput(<String, Object?>{
      'snapshot': <String, Object?>{
        'route': '/edit',
        'visibleTargets': <Object?>[
          <String, Object?>{
            'registrationId': 'internal-save',
            'cockpitId': 'save',
            'text': 'Save',
            'typeName': 'FilledButton',
            'routeName': '/edit',
            'supportedCommands': <Object?>['tap'],
            'ancestors': const <Object?>[],
          },
          <String, Object?>{
            'registrationId': 'internal-title',
            'keyValue': 'title',
            'text': 'Title',
            'typeName': 'TextField',
            'routeName': '/edit',
            'supportedCommands': <Object?>['enterText', 'sendKeyEvent'],
            'ancestors': const <Object?>[],
          },
        ],
        'network': <String, Object?>{
          'entries': <Object?>[
            <String, Object?>{'sha256': 'must-not-escape'},
          ],
        },
      },
    });

    expect(result['route'], '/edit');
    expect(result['count'], 2);
    final targets = (result['targets']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(targets.map((target) => target['label']), <Object?>[
      'Save',
      'Title',
    ]);
    expect(targets.map((target) => target['can']), <Object?>['tap', 'type']);
    expect(
      targets.map((target) => target['sel']),
      everyElement(matches(RegExp(r'^:[a-z0-9]{6,}$'))),
    );
    final encoded = jsonEncode(result);
    expect(encoded, isNot(contains('registrationId')));
    expect(encoded, isNot(contains('sha256')));
    expect(encoded, isNot(contains('network')));
  });

  test('dev target index returns controls in visual order with state', () {
    Map<String, Object?> target({
      required String id,
      required String text,
      required double dy,
      List<Object?> commands = const <Object?>[],
      Map<String, Object?>? control,
      String type = 'FilledButton',
    }) => <String, Object?>{
      'registrationId': id,
      'cockpitId': id,
      'text': text,
      'typeName': type,
      'routeName': '/dashboard',
      'supportedCommands': commands,
      'control': ?control,
      'ancestors': const <Object?>[],
      'layout': <String, Object?>{
        'dx': 20,
        'dy': dy,
        'width': 120,
        'height': 40,
      },
    };

    final result = cockpitBuildUiTargetIndexFromOutput(<String, Object?>{
      'snapshot': <String, Object?>{
        'route': '/dashboard',
        'visibleTargets': <Object?>[
          target(
            id: 'sidebar',
            text: 'Sidebar',
            dy: 100,
            commands: <Object?>['tap'],
          ),
          target(
            id: 'refresh',
            text: 'Refresh',
            dy: 10,
            commands: <Object?>['tap'],
          ),
          target(
            id: 'submit',
            text: 'Submit',
            dy: 60,
            control: <String, Object?>{'enabled': false},
          ),
          target(id: 'heading', text: 'Overview', dy: 0, type: 'Text'),
          target(
            id: 'status-only',
            text: 'Ready',
            dy: 120,
            control: <String, Object?>{},
            type: 'Semantics',
          ),
          target(
            id: 'readout',
            text: '46',
            dy: 140,
            control: <String, Object?>{'readOnly': true, 'value': '46'},
            type: 'EditableText',
          ),
        ],
      },
    });

    expect(result['count'], 3);
    final targets = (result['targets']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(targets.map((target) => target['label']), <Object?>[
      'Refresh',
      'Submit',
      'Sidebar',
    ]);
    expect(targets.map((target) => target['can']), <Object?>[
      'tap',
      null,
      'tap',
    ]);
    expect(targets[1]['state'], 'disabled');
    expect(
      targets.map((target) => target['sel']),
      everyElement(matches(RegExp(r'^:[a-z0-9]{6,}$'))),
    );
  });

  test('dev target index includes a complete ordinary screen by default', () {
    final result = cockpitBuildUiTargetIndexFromOutput(<String, Object?>{
      'snapshot': <String, Object?>{
        'route': '/many',
        'visibleTargets': <Object?>[
          for (var index = 0; index < 40; index += 1)
            <String, Object?>{
              'registrationId': 'action-$index',
              'cockpitId': 'action-$index',
              'text': 'Action $index',
              'typeName': 'TextButton',
              'routeName': '/many',
              'supportedCommands': <Object?>['tap'],
              'ancestors': const <Object?>[],
              'layout': <String, Object?>{
                'dx': 20,
                'dy': index * 44,
                'width': 120,
                'height': 40,
              },
            },
        ],
      },
    });

    expect(result['count'], 40);
    expect(result['targets'], hasLength(40));
    expect(result, isNot(contains('more')));
  });

  test('dev target index ignores unrelated truncated diagnostic detail', () {
    final result = cockpitBuildUiTargetIndexFromOutput(<String, Object?>{
      'snapshot': <String, Object?>{
        'truncated': true,
        'summary': <String, Object?>{'visibleTargetCount': 1},
        'visibleTargets': <Object?>[
          <String, Object?>{
            'registrationId': 'save',
            'text': 'Save',
            'typeName': 'TextButton',
            'routeName': '/',
            'supportedCommands': <Object?>['tap'],
            'ancestors': const <Object?>[],
          },
        ],
      },
    });

    expect(result, isNot(contains('partial')));
  });

  test('dev target index ignores omitted passive targets', () {
    final result = cockpitBuildUiTargetIndexFromOutput(<String, Object?>{
      'snapshot': <String, Object?>{
        'summary': <String, Object?>{'visibleTargetCount': 200},
        'visibleTargets': <Object?>[
          <String, Object?>{
            'registrationId': 'refresh',
            'text': 'Refresh',
            'typeName': 'IconButton',
            'routeName': '/',
            'supportedCommands': <Object?>['tap'],
            'ancestors': const <Object?>[],
          },
          <String, Object?>{
            'registrationId': 'heading',
            'text': 'Overview',
            'typeName': 'Text',
            'routeName': '/',
            'supportedCommands': const <Object?>[],
            'ancestors': const <Object?>[],
          },
        ],
      },
    });

    expect(result['count'], 1);
    expect(result, isNot(contains('partial')));
  });

  test('dev target index exposes every direct task action', () {
    final result = cockpitBuildUiTargetIndexFromOutput(<String, Object?>{
      'snapshot': <String, Object?>{
        'visibleTargets': <Object?>[
          <String, Object?>{
            'registrationId': 'advanced-control',
            'text': 'Volume',
            'typeName': 'Slider',
            'routeName': '/',
            'supportedCommands': <Object?>[
              'tap',
              'longPress',
              'doubleTap',
              'increase',
              'decrease',
              'dismiss',
              'showOnScreen',
            ],
            'ancestors': const <Object?>[],
          },
        ],
      },
    });

    final target =
        (result['targets']! as List<Object?>).single as Map<String, Object?>;
    expect(target['can'], 'tap|hold|double|inc|dec|dismiss|scroll');
  });

  test('dev locator search can return a semantic ID selector', () {
    final result = cockpitBuildUiLocatorMatchesFromOutput(<String, Object?>{
      'snapshot': <String, Object?>{
        'visibleTargets': <Object?>[
          <String, Object?>{
            'registrationId': 'internal',
            'semanticId': 'checkout.submit',
            'typeName': 'GestureDetector',
            'routeName': '/checkout',
            'supportedCommands': <Object?>['tap', 'longPress'],
            'ancestors': const <Object?>[],
          },
        ],
      },
    }, 'checkout.submit');

    expect(result['matches'], <Object?>[
      <String, Object?>{'sel': '[sem="checkout.submit"]', 'can': 'tap|hold'},
    ]);
  });

  test('dev locator search marks a mounted clipped target as offscreen', () {
    final result = cockpitBuildUiLocatorMatchesFromOutput(<String, Object?>{
      'snapshot': <String, Object?>{
        'visibleTargets': <Object?>[
          <String, Object?>{
            'registrationId': 'open-command-lab',
            'keyValue': 'settings-open-command-lab',
            'text': 'Open command lab',
            'typeName': 'FilledButton',
            'routeName': '/settings',
            'visible': false,
            'supportedCommands': <Object?>['tap'],
            'ancestors': const <Object?>[],
          },
        ],
      },
    }, '@settings-open-command-lab');

    expect(result['matches'], <Object?>[
      <String, Object?>{
        'sel': '@settings-open-command-lab',
        'label': 'Open command lab',
        'can': 'tap',
        'state': 'offscreen',
      },
    ]);
  });

  test('dev locator search prefers native keys over copied identities', () {
    final result = cockpitBuildUiLocatorMatchesFromOutput(<String, Object?>{
      'snapshot': <String, Object?>{
        'summary': <String, Object?>{'visibleTargetCount': 1},
        'visibleTargets': <Object?>[
          <String, Object?>{
            'registrationId': 'native.editor.textfield.task-title.1',
            'cockpitId': 'task-title-field',
            'keyValue': 'task-title-field',
            'text': 'Task title',
            'typeName': 'TextField',
            'routeName': '/editor',
            'supportedCommands': <Object?>['tap', 'enterText'],
            'ancestors': <Object?>[],
          },
        ],
      },
    }, 'Task title');

    expect(result['matches'], <Object?>[
      <String, Object?>{
        'sel': '@task-title-field',
        'label': 'Task title',
        'can': 'tap|type',
      },
    ]);
  });

  test('dev inspect preserves a verified explicit selector', () {
    final result = cockpitBuildUiLocatorMatchesFromOutput(<String, Object?>{
      'snapshot': <String, Object?>{
        'summary': <String, Object?>{'visibleTargetCount': 3},
        'visibleTargets': <Object?>[
          <String, Object?>{
            'registrationId': 'native.editor.textfield.task-title.1',
            'keyValue': 'task-title-field',
            'text': 'Task title',
            'typeName': 'TextField',
            'routeName': '/editor',
            'supportedCommands': <Object?>['tap', 'enterText'],
            'ancestors': <Object?>[],
          },
          <String, Object?>{
            'registrationId': 'native.editor.textfield.task-body.1',
            'keyValue': 'task-body-field',
            'text': 'Task body',
            'typeName': 'TextField',
            'routeName': '/editor',
            'supportedCommands': <Object?>['tap', 'enterText'],
            'ancestors': <Object?>[],
          },
          <String, Object?>{
            'registrationId': 'native.settings.textfield.task-title.1',
            'keyValue': 'task-title-field',
            'text': 'Task title',
            'typeName': 'TextField',
            'routeName': '/settings',
            'supportedCommands': <Object?>['tap', 'enterText'],
            'ancestors': <Object?>[],
          },
        ],
      },
    }, 'TextField@task-title-field[route="/editor"]');

    expect(result['count'], 1);
    expect(result['matches'], <Object?>[
      <String, Object?>{
        'sel': 'TextField@task-title-field[route="/editor"]',
        'label': 'Task title',
        'can': 'tap|type',
      },
    ]);
  });

  test('dev locator search reports partial only when matches are omitted', () {
    Map<String, Object?> snapshot({
      required int count,
      bool truncated = false,
    }) => <String, Object?>{
      'snapshot': <String, Object?>{
        'truncated': truncated,
        'summary': <String, Object?>{'visibleTargetCount': count},
        'visibleTargets': <Object?>[
          <String, Object?>{
            'registrationId': 'save',
            'text': 'Save',
            'typeName': 'TextButton',
            'routeName': '/',
            'supportedCommands': <Object?>['tap'],
            'ancestors': <Object?>[],
          },
        ],
      },
    };

    final complete = cockpitBuildUiLocatorMatchesFromOutput(
      snapshot(count: 1, truncated: true),
      'Save',
    );
    final incomplete = cockpitBuildUiLocatorMatchesFromOutput(
      snapshot(count: 2),
      'Save',
    );

    expect(complete, isNot(contains('partial')));
    expect(incomplete['partial'], isTrue);
  });

  test('dev locator search uses ancestor and deterministic index last', () {
    Map<String, Object?> target(String registrationId, double dy) =>
        <String, Object?>{
          'registrationId': registrationId,
          'text': 'Continue',
          'typeName': 'TextButton',
          'routeName': '/',
          'supportedCommands': <Object?>['tap'],
          'ancestors': <Object?>[
            <String, Object?>{'typeName': 'Dialog'},
          ],
          'layout': <String, Object?>{
            'dx': 10,
            'dy': dy,
            'width': 100,
            'height': 40,
          },
        };

    final indexed = cockpitBuildUiLocatorMatchesFromOutput(<String, Object?>{
      'snapshot': <String, Object?>{
        'visibleTargets': <Object?>[target('second', 80), target('first', 20)],
      },
    }, 'Continue');
    final indexedSelectors = (indexed['matches']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .map((match) => match['sel']! as String)
        .toList();
    expect(
      indexedSelectors,
      containsAll(<String>['["Continue"]:nth(1)', '["Continue"]:nth(2)']),
    );

    final scoped = cockpitBuildUiLocatorMatchesFromOutput(<String, Object?>{
      'snapshot': <String, Object?>{
        'visibleTargets': <Object?>[
          target('dialog', 20),
          <String, Object?>{
            ...target('sidebar', 80),
            'ancestors': <Object?>[
              <String, Object?>{'typeName': 'Sidebar'},
            ],
          },
        ],
      },
    }, 'Continue');
    final scopedSelectors = (scoped['matches']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .map((match) => match['sel']! as String)
        .toList();
    expect(scopedSelectors, contains('Dialog >> Continue'));
    expect(scopedSelectors, contains('Sidebar >> Continue'));
  });

  test('dev locator search prefers a stable ancestor over a widget path', () {
    Map<String, Object?> target({
      required String registrationId,
      required String key,
      required String path,
      required String ancestorKey,
    }) => <String, Object?>{
      'registrationId': registrationId,
      'keyValue': key,
      'text': 'Open',
      'typeName': 'TextButton',
      'path': path,
      'routeName': '/tasks',
      'supportedCommands': <Object?>['tap'],
      'ancestors': <Object?>[
        <String, Object?>{
          'typeName': 'Card',
          'cockpitId': ancestorKey,
          'keyValue': ancestorKey,
          'routeName': '/tasks',
          'path': '/scaffold/listview/card',
        },
      ],
    };

    final result = cockpitBuildUiLocatorMatchesFromOutput(<String, Object?>{
      'snapshot': <String, Object?>{
        'visibleTargets': <Object?>[
          target(
            registrationId: 'first',
            key: 'open',
            path: '/scaffold/listview/card/textbutton',
            ancestorKey: 'task-a',
          ),
          target(
            registrationId: 'second',
            key: 'open',
            path: '/scaffold/listview/card/textbutton',
            ancestorKey: 'task-b',
          ),
        ],
      },
    }, 'Open');

    expect(result['matches'], <Object?>[
      <String, Object?>{
        'sel': '@task-a >> @open',
        'label': 'Open',
        'can': 'tap',
      },
      <String, Object?>{
        'sel': '@task-b >> @open',
        'label': 'Open',
        'can': 'tap',
      },
    ]);
  });

  test('dev locator search combines ancestor conditions before path', () {
    Map<String, Object?> target({
      required String registrationId,
      required String section,
      required String route,
      required String path,
    }) => <String, Object?>{
      'registrationId': registrationId,
      'text': 'Continue',
      'typeName': 'TextButton',
      'path': path,
      'routeName': route,
      'supportedCommands': <Object?>['tap'],
      'ancestors': <Object?>[
        <String, Object?>{
          'typeName': 'Card',
          'textPreview': section,
          'routeName': route,
          'path': '/scaffold/listview/card',
        },
      ],
    };

    final result = cockpitBuildUiLocatorMatchesFromOutput(<String, Object?>{
      'snapshot': <String, Object?>{
        'visibleTargets': <Object?>[
          target(
            registrationId: 'first',
            section: 'Billing',
            route: '/settings',
            path: '/scaffold/listview/card/textbutton',
          ),
          target(
            registrationId: 'second',
            section: 'Profile',
            route: '/settings',
            path: '/scaffold/listview/card/textbutton',
          ),
        ],
      },
    }, 'Continue');

    final selectors = (result['matches']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .map((match) => match['sel'])
        .toList(growable: false);
    expect(selectors, <Object?>[
      '["Billing"] >> Continue',
      '["Profile"] >> Continue',
    ]);
    expect(selectors, everyElement(isNot(contains('[path='))));
  });

  test('dev locator search uses exact text parts from composite controls', () {
    final result = cockpitBuildUiLocatorMatchesFromOutput(<String, Object?>{
      'snapshot': <String, Object?>{
        'visibleTargets': <Object?>[
          <String, Object?>{
            'registrationId': 'command-item',
            'text': '/inspect Inspect the current project',
            'textParts': <Object?>['/inspect', 'Inspect the current project'],
            'typeName': 'InkWell',
            'routeName': '/',
            'supportedCommands': <Object?>['tap'],
            'ancestors': const <Object?>[],
          },
        ],
      },
    }, '/inspect');

    expect(result['count'], 1);
    expect(result['matches'], <Object?>[
      <String, Object?>{'sel': '/inspect', 'can': 'tap'},
    ]);
  });

  test('dev target index omits aggregated descendant text labels', () {
    final result = cockpitBuildUiTargetIndexFromOutput(<String, Object?>{
      'snapshot': <String, Object?>{
        'route': '/inbox',
        'visibleTargets': <Object?>[
          <String, Object?>{
            'registrationId': 'task-row',
            'semanticId': 'Open task Selector proof',
            'text':
                'Complete task Selector proof Open task Selector proof '
                'MEDIUM Pending sync Selector proof Open for notes, due date, '
                'and next actions. Open',
            'textParts': <Object?>['MEDIUM', 'Pending sync'],
            'typeName': 'Wrap',
            'routeName': '/inbox',
            'supportedCommands': <Object?>['tap'],
            'ancestors': const <Object?>[],
          },
        ],
      },
    });

    final target =
        (result['targets']! as List<Object?>).single as Map<String, Object?>;
    expect(target['sel'], matches(RegExp(r'^:[a-z0-9]+$')));
    expect(target['label'], 'Open task Selector proof');
    expect(target['can'], 'tap');
    expect(jsonEncode(target), isNot(contains('Complete task')));
  });

  test('dev inspect collapses an identityless text duplicate in one row', () {
    Map<String, Object?> target({
      required String registrationId,
      required String type,
      required double dx,
      required double dy,
      required double width,
      required double height,
      String? semanticId,
    }) => <String, Object?>{
      'registrationId': registrationId,
      'semanticId': ?semanticId,
      'text':
          'Complete task Selector proof Open task Selector proof MEDIUM '
          'Pending sync Selector proof Open for notes, due date, and next '
          'actions. Open',
      'textParts': type == 'Text'
          ? <Object?>['Open']
          : <Object?>['MEDIUM', 'Pending sync'],
      'typeName': type,
      'routeName': '/inbox',
      'scrollablePath': '/list',
      'supportedCommands': <Object?>['tap', 'longPress'],
      'ancestors': const <Object?>[],
      'layout': <String, Object?>{
        'dx': dx,
        'dy': dy,
        'width': width,
        'height': height,
      },
    };

    final result = cockpitBuildUiLocatorMatchesFromOutput(<String, Object?>{
      'snapshot': <String, Object?>{
        'visibleTargets': <Object?>[
          target(
            registrationId: 'task-row',
            type: 'Wrap',
            semanticId: 'Open task Selector proof',
            dx: 93,
            dy: 822,
            width: 161,
            height: 28,
          ),
          target(
            registrationId: 'open-label',
            type: 'Text',
            dx: 368,
            dy: 827,
            width: 34,
            height: 16,
          ),
        ],
      },
    }, 'Selector proof');

    expect(result['count'], 1);
    expect(result['matches'], <Object?>[
      <String, Object?>{
        'sel': '[sem="Open task Selector proof"]',
        'can': 'tap|hold',
      },
    ]);
  });

  test('dev inspect folds a text proxy into a stable action superset', () {
    Map<String, Object?> target({
      required String registrationId,
      required String type,
      required double dx,
      required double dy,
      required double width,
      required double height,
      required List<Object?> commands,
      String? semanticId,
    }) => <String, Object?>{
      'registrationId': registrationId,
      'semanticId': ?semanticId,
      'text':
          'Complete task Android CLI verification '
          'Open task Android CLI verification MEDIUM Pending sync '
          'Android CLI verification Open',
      'textParts': <Object?>[
        'MEDIUM',
        'Pending sync',
        'Android CLI verification',
      ],
      'typeName': type,
      'routeName': '/inbox',
      'scrollablePath': '/inbox/listview',
      'supportedCommands': commands,
      'ancestors': const <Object?>[],
      'layout': <String, Object?>{
        'dx': dx,
        'dy': dy,
        'width': width,
        'height': height,
      },
    };

    final result = cockpitBuildUiLocatorMatchesFromOutput(<String, Object?>{
      'snapshot': <String, Object?>{
        'visibleTargets': <Object?>[
          target(
            registrationId: 'row',
            type: 'InkWell',
            semanticId: 'Open task Android CLI verification',
            dx: 93,
            dy: 672,
            width: 264,
            height: 134,
            commands: <Object?>['tap', 'longPress', 'doubleTap'],
          ),
          target(
            registrationId: 'label',
            type: 'Text',
            dx: 369,
            dy: 692,
            width: 34,
            height: 16,
            commands: <Object?>['tap', 'longPress'],
          ),
        ],
      },
    }, 'Open');

    expect(result['count'], 1);
    expect(result['matches'], <Object?>[
      <String, Object?>{
        'sel': '[sem="Open task Android CLI verification"]',
        'can': 'tap|hold|double',
      },
    ]);
  });

  test('dev locator advice preserves exact text case', () {
    Map<String, Object?> target(String registrationId, String text) =>
        <String, Object?>{
          'registrationId': registrationId,
          'text': text,
          'typeName': 'TextButton',
          'routeName': '/',
          'supportedCommands': <Object?>['tap'],
          'ancestors': const <Object?>[],
        };

    final result = cockpitBuildUiLocatorMatchesFromOutput(<String, Object?>{
      'snapshot': <String, Object?>{
        'visibleTargets': <Object?>[
          target('upper', 'Save'),
          target('lower', 'save'),
        ],
      },
    }, 'save');
    final selectors = (result['matches']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .map((match) => match['sel'])
        .toList(growable: false);

    expect(selectors, containsAll(<String>['Save', 'save']));
  });

  test('dev locator search does not recall every target from its route', () {
    final result = cockpitBuildUiLocatorMatchesFromOutput(<String, Object?>{
      'snapshot': <String, Object?>{
        'visibleTargets': <Object?>[
          <String, Object?>{
            'registrationId': 'inbox-title',
            'text': 'Inbox',
            'typeName': 'RichText',
            'routeName': '/inbox',
            'supportedCommands': const <Object?>[],
            'ancestors': const <Object?>[],
          },
          <String, Object?>{
            'registrationId': 'reset-button',
            'text': 'Reset',
            'typeName': 'TextButton',
            'routeName': '/inbox',
            'supportedCommands': <Object?>['tap'],
            'ancestors': const <Object?>[],
          },
        ],
      },
    }, 'Inbox');

    expect(result['count'], 1);
    expect(result['matches'], <Object?>[
      <String, Object?>{'sel': 'Inbox'},
    ]);
  });

  test('dev locator advice rejects index ordered by internal identity', () {
    Map<String, Object?> target(String registrationId) => <String, Object?>{
      'registrationId': registrationId,
      'text': 'Continue',
      'typeName': 'TextButton',
      'routeName': '/',
      'supportedCommands': <Object?>['tap'],
      'ancestors': const <Object?>[],
      'layout': const <String, Object?>{
        'dx': 10,
        'dy': 20,
        'width': 100,
        'height': 40,
      },
    };

    final result = cockpitBuildUiLocatorMatchesFromOutput(<String, Object?>{
      'snapshot': <String, Object?>{
        'visibleTargets': <Object?>[target('first'), target('second')],
      },
    }, 'Continue');
    final matches = (result['matches']! as List<Object?>)
        .cast<Map<String, Object?>>();

    expect(matches, everyElement(containsPair('ambiguous', true)));
    expect(
      matches.map((match) => match['sel']! as String),
      everyElement(isNot(contains(':nth('))),
    );
  });

  test(
    'dev locator advice uses path only after simpler signals stay equal',
    () {
      Map<String, Object?> target(String registrationId, String path) =>
          <String, Object?>{
            'registrationId': registrationId,
            'text': 'Continue',
            'typeName': 'TextButton',
            'path': path,
            'routeName': '/',
            'supportedCommands': <Object?>['tap'],
            'ancestors': const <Object?>[],
          };

      final result = cockpitBuildUiLocatorMatchesFromOutput(<String, Object?>{
        'snapshot': <String, Object?>{
          'visibleTargets': <Object?>[
            target('first', '/scaffold/sidebar/textbutton'),
            target('second', '/scaffold/dialog/textbutton'),
          ],
        },
      }, 'Continue');
      final selectors = (result['matches']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .map((match) => match['sel']! as String)
          .toList(growable: false);

      expect(
        selectors,
        containsAll(<String>[
          '["Continue"][path="/scaffold/sidebar/textbutton"]',
          '["Continue"][path="/scaffold/dialog/textbutton"]',
        ]),
      );
    },
  );
}

File _cockpitPubspecFile() {
  var directory = Directory.current.absolute;
  while (true) {
    for (final candidate in <File>[
      File(p.join(directory.path, 'pubspec.yaml')),
      File(p.join(directory.path, 'packages', 'cockpit', 'pubspec.yaml')),
    ]) {
      if (!candidate.existsSync()) continue;
      final pubspec = loadYaml(candidate.readAsStringSync());
      if (pubspec is YamlMap && pubspec['name'] == 'cockpit') return candidate;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Unable to locate packages/cockpit/pubspec.yaml.');
    }
    directory = parent;
  }
}
