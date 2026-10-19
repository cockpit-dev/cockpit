import 'dart:convert';
import 'dart:io';

import 'package:cockpit/cockpit.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

/// Runs `cockpit_test` scenarios against a bridge-connected app over the
/// remote session protocol — the same Dart closures that run inside
/// `flutter_cockpit_test` integration tests, executed here against an
/// installed build (the release APK verification path documented in
/// `docs/cross-runner-programmatic-testing.md`).
///
/// The app must embed the Cockpit bridge, for example:
///
///   flutter build apk --release \
///     --dart-define=FLUTTER_COCKPIT_REMOTE_ENABLED=true \
///     --dart-define=FLUTTER_COCKPIT_REMOTE_AUTH_TOKEN="$COCKPIT_TOKEN"
///
/// For a device build, forward the bridge port first:
///
///   adb forward tcp:47331 tcp:47331
///
/// Then run:
///
///   dart run tool/programmatic_verify.dart \
///     --token "$COCKPIT_TOKEN" --expect-build-mode release
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('endpoint', defaultsTo: 'http://127.0.0.1:47331')
    ..addOption('token', defaultsTo: '')
    ..addOption(
      'expect-build-mode',
      help: 'Fail unless the connected app reports this build mode.',
    )
    ..addOption('locale', defaultsTo: 'en-US')
    ..addOption('output-root', defaultsTo: '.dart_tool/cockpit_programmatic')
    ..addOption(
      'project-dir',
      defaultsTo: _defaultProjectDirectory(),
      help: 'Project directory used as the tester workspace root.',
    )
    ..addFlag('help', abbr: 'h', negatable: false);
  late final ArgResults parsed;
  try {
    parsed = parser.parse(arguments);
    if (parsed.flag('help')) {
      stdout.writeln('Run cockpit_test scenarios over a remote app bridge.');
      stdout.writeln();
      stdout.writeln(parser.usage);
      return;
    }
  } on FormatException catch (error) {
    stderr.writeln('Invalid arguments: ${error.message}');
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }

  final endpoint = Uri.parse(parsed.option('endpoint')!);
  final token = parsed.option('token')!;
  final client = CockpitRemoteSessionClient(
    baseUri: endpoint,
    authToken: token,
  );

  final preflight = await _preflight(
    client,
    expectedBuildMode: parsed.option('expect-build-mode'),
  );
  if (preflight == null) {
    exitCode = 1;
    return;
  }

  final locale = CockpitLocaleProfile(parsed.option('locale')!);
  final suite = CockpitTestSuiteProgram(
    id: 'demo-release-programmatic',
    locales: <CockpitLocaleProfile>[locale],
    scenarios: <CockpitTestScenario>[
      _inboxLoads,
      _settingsRoundTrip,
      _taskEditorRoundTrip,
    ],
  );

  final result = await const CockpitProgrammaticTestRunner().runSuite(
    suite,
    createTester: (activeLocale) async => RemoteCockpitTester(
      client: client,
      workspaceRoot: parsed.option('project-dir')!,
      initialLocale: activeLocale,
    ),
  );

  final outputRoot = Directory(parsed.option('output-root')!);
  await outputRoot.create(recursive: true);
  final reportFile = File(p.join(outputRoot.path, 'programmatic-result.json'));
  await reportFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'endpoint': endpoint.toString(),
      'buildMode': preflight.buildMode,
      'suite': result.toJson(),
    }),
  );

  for (final attempt in result.attempts) {
    stderr.writeln(
      '${attempt.status.name.padRight(7)} '
      '${attempt.scenarioId} [${attempt.locale.toLanguageTag()}]'
      '${attempt.error == null ? '' : ' — ${attempt.error!.message}'}',
    );
  }
  stdout.writeln(
    'suite=${result.suiteId} passed=${result.passed} '
    'attempts=${result.attempts.length} report=${reportFile.path}',
  );
  exitCode = result.passed ? 0 : 1;
}

Future<CockpitRemoteSessionStatus?> _preflight(
  CockpitRemoteSessionClient client, {
  required String? expectedBuildMode,
}) async {
  final status = await client.readStatus();
  stderr.writeln(
    'connected session=${status.sessionId} '
    'platform=${status.platform} buildMode=${status.buildMode} '
    'route=${status.currentRouteName} '
    'inAppControl=${status.capabilities.supportsInAppControl}',
  );
  if (expectedBuildMode != null && status.buildMode != expectedBuildMode) {
    stderr.writeln(
      'The connected app reports buildMode=${status.buildMode}, '
      'expected $expectedBuildMode.',
    );
    return null;
  }
  if (!status.capabilities.supportsInAppControl) {
    stderr.writeln('The connected app does not advertise in-app control.');
    return null;
  }
  return status;
}

final CockpitTestScenario _inboxLoads = CockpitTestScenario(
  id: 'inbox-loads',
  body: (tester) async {
    await tester.waitForUi();
    final snapshot = await tester.collectSnapshot();
    cockpitExpectEquals(snapshot.routeName, '/inbox');
  },
);

final CockpitTestScenario _settingsRoundTrip = CockpitTestScenario(
  id: 'settings-round-trip',
  body: (tester) async {
    await tester.tap('#open-settings-action');
    await tester.waitForUi();
    var snapshot = await tester.collectSnapshot();
    cockpitExpectEquals(snapshot.routeName, '/settings');
    await tester.expectVisible('Tune the workspace.');
    await tester.execute(
      CockpitCommand(
        commandId: 'settings-back',
        commandType: CockpitCommandType.back,
      ),
    );
    await tester.waitForUi();
    snapshot = await tester.collectSnapshot();
    cockpitExpectEquals(snapshot.routeName, '/inbox');
  },
);

const _releaseTaskTitle = 'Cockpit release programmatic smoke';

final CockpitTestScenario _taskEditorRoundTrip = CockpitTestScenario(
  id: 'task-editor-round-trip',
  body: (tester) async {
    await tester.tap('New task');
    await tester.waitFor('#task-title-field');
    await tester.type(_releaseTaskTitle, into: '#task-title-field');
    await tester.tap('Save task');
    await tester.waitFor('#latest-task-open-action');
    await tester.expectVisible(_releaseTaskTitle);

    // Remove the row again so the suite stays idempotent on repeated runs.
    await tester.tap('#latest-task-open-action');
    await tester.waitForUi();
    var snapshot = await tester.collectSnapshot();
    cockpitExpectEquals(snapshot.routeName, '/detail');
    await tester.tap(const CockpitLocator(tooltip: 'Delete task'));
    await tester.waitForUi();
    snapshot = await tester.collectSnapshot();
    cockpitExpectEquals(snapshot.routeName, '/inbox');
    await tester.waitFor(_releaseTaskTitle, absent: true);
  },
);

String _defaultProjectDirectory() {
  final script = Platform.script;
  if (script.scheme == 'file') {
    return p.normalize(p.dirname(p.dirname(script.toFilePath())));
  }
  return p.normalize(Directory.current.absolute.path);
}
