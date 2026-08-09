import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/cli/cockpit_cli_runtime.dart';
import 'package:cockpit/src/cli/cockpit_command_runner.dart';
import 'package:cockpit/src/cli/cockpit_dev_locator_advisor.dart';
import 'package:cockpit/src/cli/commands/dev_interaction_commands.dart';
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
        'tap',
        'type',
        'press',
        'back',
        'dismiss',
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
      'cockpit dev tap [TARGET] [arguments]',
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
      dev.subcommands['status']!.description,
      'Read the current Flutter development session state.',
    );
    expect(
      dev.subcommands['start']!.argParser.options.keys,
      contains('session'),
    );
    expect(
      dev.subcommands['tap']!.argParser.options.keys,
      containsAll(<String>{
        'id',
        'key',
        'type',
        'tip',
        'route',
        'index',
        'within',
        'fuzzy',
        'contains',
      }),
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

  test('dev combines optional target conditions in one exact locator', () {
    final runner = CockpitCommandRunner(
      runtime: CockpitCliRuntime(
        stdoutSink: StringBuffer(),
        stderrSink: StringBuffer(),
      ),
    );
    final tap = runner.commands['dev']!.subcommands['tap']!;
    final arguments = tap.argParser.parse(const <String>[
      'Save',
      '--id',
      'save-button',
      '--key',
      'save-key',
      '--type',
      'TextButton',
      '--tip',
      'Save changes',
      '--route',
      '/editor',
      '--index',
      '1',
      '--within',
      'Confirm',
    ]);

    final locator = cockpitReadDevLocator(
      arguments,
      text: arguments.rest.single,
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
        index: 1,
        ancestor: CockpitLocator(type: 'Confirm'),
      ),
    );
  });

  test('dev target scope and index cannot replace a target condition', () {
    final runner = CockpitCommandRunner(
      runtime: CockpitCliRuntime(
        stdoutSink: StringBuffer(),
        stderrSink: StringBuffer(),
      ),
    );
    final tap = runner.commands['dev']!.subcommands['tap']!;
    final arguments = tap.argParser.parse(const <String>[
      '--within',
      'Dialog',
      '--index',
      '0',
    ]);

    expect(
      () => cockpitReadDevLocator(arguments, text: null),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('requires at least one target condition'),
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
      final result = cockpitBuildDevLocatorMatches(<String, Object?>{
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
      expect(matches[0]['loc'], <String, Object?>{'text': 'Documents'});
      expect(matches[0]['can'], <String>['tap']);
      expect(matches[1]['loc'], <String, Object?>{
        'text': 'Documents',
        'type': 'RichText',
      });
      expect(matches[2]['loc'], <String, Object?>{'id': 'documents.nav'});
      expect(matches[2]['label'], 'Open documents');
      final encoded = jsonEncode(result);
      expect(encoded, isNot(contains('network')));
      expect(encoded, isNot(contains('sha256')));
      expect(encoded, isNot(contains('registrationId')));
      expect(encoded, isNot(contains('internal-')));
      expect(encoded, isNot(contains('path')));
    },
  );

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

    final indexed = cockpitBuildDevLocatorMatches(<String, Object?>{
      'snapshot': <String, Object?>{
        'visibleTargets': <Object?>[target('second', 80), target('first', 20)],
      },
    }, 'Continue');
    final indexedLocators = (indexed['matches']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .map((match) => match['loc']! as Map<String, Object?>)
        .toList();
    expect(
      indexedLocators.map((loc) => loc['index']),
      containsAll(<int>[0, 1]),
    );

    final scoped = cockpitBuildDevLocatorMatches(<String, Object?>{
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
    final scopedLocators = (scoped['matches']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .map((match) => match['loc']! as Map<String, Object?>)
        .toList();
    expect(
      scopedLocators,
      anyElement(
        equals(<String, Object?>{'text': 'Continue', 'within': 'Dialog'}),
      ),
    );
    expect(
      scopedLocators,
      anyElement(
        equals(<String, Object?>{'text': 'Continue', 'within': 'Sidebar'}),
      ),
    );
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

    final result = cockpitBuildDevLocatorMatches(<String, Object?>{
      'snapshot': <String, Object?>{
        'visibleTargets': <Object?>[
          target('upper', 'Save'),
          target('lower', 'save'),
        ],
      },
    }, 'save');
    final locators = (result['matches']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .map((match) => match['loc'])
        .toList(growable: false);

    expect(
      locators,
      containsAll(<Map<String, Object?>>[
        <String, Object?>{'text': 'Save'},
        <String, Object?>{'text': 'save'},
      ]),
    );
  });

  test('dev locator search does not recall every target from its route', () {
    final result = cockpitBuildDevLocatorMatches(<String, Object?>{
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
      <String, Object?>{
        'loc': <String, Object?>{'text': 'Inbox'},
      },
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

    final result = cockpitBuildDevLocatorMatches(<String, Object?>{
      'snapshot': <String, Object?>{
        'visibleTargets': <Object?>[target('first'), target('second')],
      },
    }, 'Continue');
    final matches = (result['matches']! as List<Object?>)
        .cast<Map<String, Object?>>();

    expect(matches, everyElement(containsPair('ambiguous', true)));
    expect(
      matches.map((match) => match['loc']! as Map<String, Object?>),
      everyElement(isNot(contains('index'))),
    );
  });
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
