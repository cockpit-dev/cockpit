import 'dart:io';

import 'package:args/args.dart';
import 'package:cockpit/src/cli/cockpit_dev_start.dart';
import 'package:cockpit/src/cli/cockpit_flutter_launch_configuration_cli.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('reads the complete structured Flutter launch configuration', () {
    final parser = ArgParser();
    cockpitAddFlutterLaunchConfigurationOptions(parser);

    final configuration = cockpitReadFlutterLaunchConfiguration(
      parser.parse(<String>[
        '--dart-define=API_URL=https://example.test',
        '--dart-define-from-file=config/staging.json',
        '--flutter-arg=--track-widget-creation',
        '--env=LOG_LEVEL=debug',
        '--env=EMPTY=',
      ]),
    );

    expect(configuration, <String, Object?>{
      'dartDefines': <String>['API_URL=https://example.test'],
      'dartDefineFromFiles': <String>['config/staging.json'],
      'flutterArgs': <String>['--track-widget-creation'],
      'environment': <String, String>{'LOG_LEVEL': 'debug', 'EMPTY': ''},
    });
  });

  test('omits an empty launch configuration', () {
    final parser = ArgParser();
    cockpitAddFlutterLaunchConfigurationOptions(parser);

    expect(cockpitReadFlutterLaunchConfiguration(parser.parse(const [])), null);
  });

  test('rebases dev define files from the invocation directory', () async {
    final root = await Directory.systemTemp.createTemp(
      'cockpit-dev-define-file-',
    );
    addTearDown(() => root.delete(recursive: true));
    final project = Directory(p.join(root.path, 'examples', 'demo'));
    final file = File(p.join(project.path, 'cockpit', 'e2e', 'launch.json'));
    await file.parent.create(recursive: true);
    await file.writeAsString('{}');

    final resolved = await cockpitResolveDevFlutterLaunchConfiguration(
      <String, Object?>{
        'dartDefineFromFiles': <String>[
          'examples/demo/cockpit/e2e/launch.json',
        ],
      },
      sourceDirectory: root.path,
      projectDirectory: project.path,
    );

    expect(resolved, <String, Object?>{
      'dartDefineFromFiles': <String>['cockpit/e2e/launch.json'],
    });
  });

  test('selects only the workspace owned by the Flutter project', () {
    final selected = cockpitSelectDevWorkspace(<CockpitWorkspaceResource>[
      _workspace('workspace-root', '/workspace'),
      _workspace('workspace-demo', '/workspace/examples/demo'),
    ], projectPath: '/workspace/examples/demo');

    expect(selected?.workspaceId, 'workspace-demo');
  });

  test('matches only development targets in safe local environments', () {
    bool matches(
      CockpitAutomationTargetMode mode,
      CockpitAutomationTargetEnvironment environment,
    ) => cockpitMatchesDevelopmentTarget(
      CockpitAutomationTargetResource(
        targetId: 'target-1',
        workspaceId: 'workspace-1',
        platform: 'android',
        deviceId: 'emulator-5554',
        targetKind: CockpitTargetKind.flutterApp,
        mode: mode,
        environment: environment,
        entrypoint: 'cockpit/main.dart',
      ),
      entrypoint: 'cockpit/main.dart',
      platform: 'android',
      deviceId: 'emulator-5554',
      flavor: null,
    );

    expect(
      matches(
        CockpitAutomationTargetMode.development,
        CockpitAutomationTargetEnvironment.development,
      ),
      isTrue,
    );
    expect(
      matches(
        CockpitAutomationTargetMode.development,
        CockpitAutomationTargetEnvironment.test,
      ),
      isTrue,
    );
    expect(
      matches(
        CockpitAutomationTargetMode.automation,
        CockpitAutomationTargetEnvironment.development,
      ),
      isFalse,
    );
    expect(
      matches(
        CockpitAutomationTargetMode.development,
        CockpitAutomationTargetEnvironment.production,
      ),
      isFalse,
    );
  });
}

CockpitWorkspaceResource _workspace(String id, String path) {
  final timestamp = DateTime.utc(2026, 8, 8);
  return CockpitWorkspaceResource(
    workspaceId: id,
    projectId: 'project-1',
    checkoutId: 'checkout-1',
    rootId: 'root-1',
    canonicalPath: path,
    filesystemIdentity: 'identity-$id',
    state: CockpitWorkspaceState.active,
    registeredAt: timestamp,
    updatedAt: timestamp,
  );
}
