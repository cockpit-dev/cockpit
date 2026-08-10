import 'package:cockpit/src/application/cockpit_application_service_exception.dart';
import 'package:cockpit/src/session/cockpit_flutter_launch_configuration.dart';
import 'package:test/test.dart';

void main() {
  test('launch configuration renders Flutter arguments in stable order', () {
    final configuration = CockpitFlutterLaunchConfiguration(
      dartDefines: const <String>['API_URL=https://example.test', 'EMPTY='],
      dartDefineFromFiles: const <String>['config/dev.json'],
      flutterArgs: const <String>[
        '--web-renderer=canvaskit',
        '--enable-experiment',
        'records',
        '--build-name',
        'AI Build',
      ],
      environment: const <String, String>{
        'API_TOKEN': 'secret',
        'EMPTY_ENV': '',
      },
    );

    expect(configuration.toFlutterArguments(), <String>[
      '--dart-define=API_URL=https://example.test',
      '--dart-define=EMPTY=',
      '--dart-define-from-file=config/dev.json',
      '--web-renderer=canvaskit',
      '--enable-experiment',
      'records',
      '--build-name',
      'AI Build',
    ]);
    expect(configuration.processEnvironment, <String, String>{
      'API_TOKEN': 'secret',
      'EMPTY_ENV': '',
    });
  });

  test('launch configuration rejects malformed or reserved values', () {
    expect(
      () => CockpitFlutterLaunchConfiguration.fromJson(const <String, Object?>{
        'unknown': true,
      }),
      throwsA(isA<CockpitApplicationServiceException>()),
    );
    expect(
      () => CockpitFlutterLaunchConfiguration.fromJson(<String, Object?>{
        'flutterArgs': List<String>.filled(1025, '--verbose'),
      }),
      throwsA(isA<CockpitApplicationServiceException>()),
    );
    expect(
      () => CockpitFlutterLaunchConfiguration(
        dartDefines: const <String>['FLUTTER_COCKPIT_CUSTOM=1'],
      ),
      throwsArgumentError,
    );
    expect(
      () => CockpitFlutterLaunchConfiguration(
        environment: const <String, String>{'BAD=KEY': 'value'},
      ),
      throwsArgumentError,
    );
    expect(
      () => CockpitFlutterLaunchConfiguration(
        flutterArgs: const <String>[
          '--dart-define=FLUTTER_COCKPIT_REMOTE_ENABLED=false',
        ],
      ),
      throwsArgumentError,
    );
    for (final reservedArg in <String>[
      '--target',
      '--target=cockpit/main.dart',
      '--target cockpit/main.dart',
      '-t',
      '-d',
      '-d emulator-5554',
      '--device-id',
      '--device-id=emulator-5554',
      '--device-id emulator-5554',
      '--flavor',
      '--flavor=staging',
      '--flavor staging',
      '--machine',
      '--no-resident',
      '--debug',
      '--profile',
      '--release',
      '--simulator',
      '--no-codesign',
      '--dds',
      '--no-dds',
      '--disable-dds',
      '--no-disable-dds',
    ]) {
      expect(
        () => CockpitFlutterLaunchConfiguration(
          flutterArgs: <String>[reservedArg],
        ),
        throwsArgumentError,
        reason: reservedArg,
      );
    }
  });

  test('managed development environment rejects conflicting user temp', () {
    final configuration = CockpitFlutterLaunchConfiguration(
      environment: const <String, String>{'temp': '/tmp/custom'},
    );

    expect(
      () => configuration.withManagedEnvironment(const <String, String>{
        'TMPDIR': '/tmp/cockpit',
      }),
      throwsA(
        isA<CockpitApplicationServiceException>().having(
          (error) => error.code,
          'code',
          'invalidLaunchConfiguration',
        ),
      ),
    );
  });

  test('remote control dart defines are rendered by one shared builder', () {
    expect(
      cockpitBuildRemoteControlDartDefineArguments(
        host: '::',
        port: 47331,
        flutterVersion: '3.32.0',
        launchId: 'launch-1',
        disableHttpNetworkObserver: true,
        disableRuntimeObserver: true,
      ),
      <String>[
        '--dart-define=FLUTTER_COCKPIT_REMOTE_ENABLED=true',
        '--dart-define=FLUTTER_COCKPIT_REMOTE_HOST=::',
        '--dart-define=FLUTTER_COCKPIT_REMOTE_PORT=47331',
        '--dart-define=FLUTTER_COCKPIT_REMOTE_LAUNCH_ID=launch-1',
        '--dart-define=FLUTTER_COCKPIT_ENABLE_HTTP_NETWORK_OBSERVER=false',
        '--dart-define=FLUTTER_COCKPIT_ENABLE_RUNTIME_OBSERVER=false',
        '--dart-define=FLUTTER_COCKPIT_FLUTTER_VERSION=3.32.0',
      ],
    );
  });
}
