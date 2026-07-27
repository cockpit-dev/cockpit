import 'dart:async';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/src/session/cockpit_flutter_launch_configuration.dart';
import 'package:cockpit/src/session/cockpit_macos_remote_session_launcher.dart';
import 'package:cockpit/src/session/cockpit_remote_session_launch_options.dart';
import 'package:test/test.dart';

void main() {
  test(
    'macos remote session launcher builds, opens, and returns a handle',
    () async {
      final invocations = <String>[];
      Map<String, Object?>? startInvocation;
      final launcher = CockpitMacosRemoteSessionLauncher(
        flutterVersionReader: () async => '3.38.9',
        processRunner:
            (
              executable,
              arguments, {
              String? workingDirectory,
              Map<String, String>? environment,
            }) async {
              invocations.add('$executable ${arguments.join(' ')}');
              return ProcessResult(0, 0, '', '');
            },
        appBundlePathResolver:
            ({required String projectDir, String? flavor}) async =>
                '$projectDir/build/macos/Build/Products/Debug/cockpit_demo.app',
        bundleIdResolver: ({required String appBundlePath}) async =>
            'dev.cockpit.cockpitDemo',
        bundleExecutablePathResolver: ({required String appBundlePath}) async =>
            throw StateError('executable path should be resolved only for env'),
        appStarter:
            ({
              required String appBundlePath,
              required String? executablePath,
              required Map<String, String>? environment,
              required Duration timeout,
            }) async {
              startInvocation = <String, Object?>{
                'appBundlePath': appBundlePath,
                'executablePath': executablePath,
                'environment': environment,
              };
              return null;
            },
        statusReader: (baseUri) async => CockpitRemoteSessionStatus(
          sessionId: 'macos-bootstrap-session',
          platform: 'macos',
          transportType: 'remoteHttp',
          currentRouteName: '/home',
          capabilities: CockpitCapabilities(
            platform: 'macos',
            transportType: 'remoteHttp',
            supportsInAppControl: true,
            supportsFlutterViewCapture: true,
            supportsNativeScreenCapture: true,
            supportsHostAutomation: true,
            supportedCommands: <CockpitCommandType>[CockpitCommandType.tap],
            supportedLocatorStrategies: CockpitLocatorKind.values,
          ),
          recordingCapabilities: CockpitRecordingCapabilities(
            supportsNativeRecording: true,
            preferredAcceptanceRecordingKind: CockpitRecordingKind.nativeScreen,
          ),
          snapshot: CockpitSnapshot(routeName: '/home'),
        ),
      );

      final handle = await launcher.launch(
        const CockpitRemoteSessionLaunchOptions(
          projectDir: '/workspace/examples/cockpit_demo',
          target: 'cockpit/main.dart',
          platform: 'macos',
          deviceId: 'macos',
          sessionPort: 47331,
        ),
      );

      expect(handle.platform, 'macos');
      expect(handle.deviceId, 'macos');
      expect(handle.appId, 'dev.cockpit.cockpitDemo');
      expect(handle.baseUrl, 'http://127.0.0.1:47331');
      expect(
        invocations,
        contains(
          'flutter build macos --debug --target cockpit/main.dart --dart-define=FLUTTER_COCKPIT_REMOTE_ENABLED=true --dart-define=FLUTTER_COCKPIT_REMOTE_HOST=127.0.0.1 --dart-define=FLUTTER_COCKPIT_REMOTE_PORT=47331 --dart-define=FLUTTER_COCKPIT_FLUTTER_VERSION=3.38.9',
        ),
      );
      expect(
        invocations,
        contains(
          'osascript -e tell application id "dev.cockpit.cockpitDemo" to quit',
        ),
      );
      expect(startInvocation, <String, Object?>{
        'appBundlePath':
            '/workspace/examples/cockpit_demo/build/macos/Build/Products/Debug/cockpit_demo.app',
        'executablePath': null,
        'environment': null,
      });
    },
  );

  test(
    'macos launcher reads Flutter version from the configured executable',
    () async {
      final invocations = <String>[];
      final launcher = CockpitMacosRemoteSessionLauncher(
        flutterVersionReader: () async =>
            throw StateError('legacy version reader should not be used'),
        processRunner:
            (
              executable,
              arguments, {
              String? workingDirectory,
              Map<String, String>? environment,
            }) async {
              invocations.add('$executable ${arguments.join(' ')}');
              if (executable == '/opt/flutter/bin/flutter' &&
                  arguments.join(' ') == '--version --machine') {
                return ProcessResult(0, 0, '{"frameworkVersion":"3.32.0"}', '');
              }
              return ProcessResult(0, 0, '', '');
            },
        appBundlePathResolver:
            ({required String projectDir, String? flavor}) async =>
                '$projectDir/build/macos/Build/Products/Debug/cockpit_demo.app',
        bundleIdResolver: ({required String appBundlePath}) async =>
            'dev.cockpit.cockpitDemo',
        statusReader: (baseUri) async => CockpitRemoteSessionStatus(
          sessionId: 'macos-sdk-session',
          platform: 'macos',
          transportType: 'remoteHttp',
          currentRouteName: '/home',
          capabilities: CockpitCapabilities(
            platform: 'macos',
            transportType: 'remoteHttp',
            supportsInAppControl: true,
            supportsFlutterViewCapture: true,
            supportsNativeScreenCapture: true,
            supportsHostAutomation: true,
          ),
          recordingCapabilities: CockpitRecordingCapabilities(
            supportsNativeRecording: true,
          ),
          snapshot: CockpitSnapshot(routeName: '/home'),
        ),
      );

      await launcher.launch(
        const CockpitRemoteSessionLaunchOptions(
          projectDir: '/workspace/examples/cockpit_demo',
          target: 'cockpit/main.dart',
          platform: 'macos',
          deviceId: 'macos',
          sessionPort: 47331,
          flutterExecutable: '/opt/flutter/bin/flutter',
        ),
      );

      expect(
        invocations,
        contains('/opt/flutter/bin/flutter --version --machine'),
      );
      expect(
        invocations,
        contains(
          '/opt/flutter/bin/flutter build macos --debug --target cockpit/main.dart --dart-define=FLUTTER_COCKPIT_REMOTE_ENABLED=true --dart-define=FLUTTER_COCKPIT_REMOTE_HOST=127.0.0.1 --dart-define=FLUTTER_COCKPIT_REMOTE_PORT=47331 --dart-define=FLUTTER_COCKPIT_FLUTTER_VERSION=3.32.0',
        ),
      );
    },
  );

  test(
    'macos launcher cleans and retries once for stale Swift module cache failures',
    () async {
      final invocations = <String>[];
      var buildCount = 0;
      final launcher = CockpitMacosRemoteSessionLauncher(
        flutterVersionReader: () async => '3.44.0',
        processRunner:
            (
              executable,
              arguments, {
              String? workingDirectory,
              Map<String, String>? environment,
            }) async {
              invocations.add('$executable ${arguments.join(' ')}');
              if (arguments.length >= 2 &&
                  arguments[0] == 'build' &&
                  arguments[1] == 'macos') {
                buildCount += 1;
                if (buildCount == 1) {
                  return ProcessResult(
                    0,
                    1,
                    '',
                    "file 'FlutterPluginRegistrarMacOS.h' has been modified since the module file 'flutter_cockpit.pcm' was built",
                  );
                }
              }
              return ProcessResult(0, 0, '', '');
            },
        appBundlePathResolver:
            ({required String projectDir, String? flavor}) async =>
                '$projectDir/build/macos/Build/Products/Debug/cockpit_demo.app',
        bundleIdResolver: ({required String appBundlePath}) async =>
            'dev.cockpit.cockpitDemo',
        statusReader: (baseUri) async => CockpitRemoteSessionStatus(
          sessionId: 'macos-cache-retry-session',
          platform: 'macos',
          transportType: 'remoteHttp',
          currentRouteName: '/home',
          capabilities: CockpitCapabilities(
            platform: 'macos',
            transportType: 'remoteHttp',
            supportsInAppControl: true,
            supportsFlutterViewCapture: true,
            supportsNativeScreenCapture: true,
            supportsHostAutomation: true,
          ),
          recordingCapabilities: CockpitRecordingCapabilities(
            supportsNativeRecording: true,
          ),
          snapshot: CockpitSnapshot(routeName: '/home'),
        ),
      );

      await launcher.launch(
        const CockpitRemoteSessionLaunchOptions(
          projectDir: '/workspace/examples/cockpit_demo',
          target: 'cockpit/main.dart',
          platform: 'macos',
          deviceId: 'macos',
          sessionPort: 47331,
        ),
      );

      expect(buildCount, 2);
      expect(invocations, contains('flutter clean'));
      expect(invocations, contains('flutter pub get'));
    },
  );

  test('macos remote session launcher times out slow build stages', () async {
    final launcher = CockpitMacosRemoteSessionLauncher(
      flutterVersionReader: () async => '3.38.9',
      processRunner:
          (
            executable,
            arguments, {
            String? workingDirectory,
            Map<String, String>? environment,
          }) {
            return Future<ProcessResult>.delayed(
              const Duration(milliseconds: 150),
              () => ProcessResult(0, 0, '', ''),
            );
          },
      now: () => DateTime.utc(2026, 3, 24, 12),
    );

    expect(
      () => launcher.launch(
        const CockpitRemoteSessionLaunchOptions(
          projectDir: '/workspace/examples/cockpit_demo',
          target: 'cockpit/main.dart',
          platform: 'macos',
          deviceId: 'macos',
          sessionPort: 47331,
          launchTimeout: Duration(milliseconds: 50),
        ),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test(
    'macos remote session launcher prefers a flavor-matching app bundle',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_macos_remote_session_launcher_flavor',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final productsDirectory = Directory(
        '${tempDir.path}/build/macos/Build/Products/Debug',
      );
      await productsDirectory.create(recursive: true);
      final defaultBundle = Directory('${productsDirectory.path}/Orbit.app');
      final flavoredBundle = Directory(
        '${productsDirectory.path}/OrbitStaging.app',
      );
      await flavoredBundle.create(recursive: true);
      await Directory(
        '${flavoredBundle.path}/Contents',
      ).create(recursive: true);
      await File(
        '${flavoredBundle.path}/Contents/Info.plist',
      ).writeAsString('');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await defaultBundle.create(recursive: true);
      await Directory('${defaultBundle.path}/Contents').create(recursive: true);
      await File('${defaultBundle.path}/Contents/Info.plist').writeAsString('');

      String? resolvedBundlePath;
      final launcher = CockpitMacosRemoteSessionLauncher(
        flutterVersionReader: () async => '3.38.9',
        processRunner:
            (
              executable,
              arguments, {
              String? workingDirectory,
              Map<String, String>? environment,
            }) async {
              return ProcessResult(0, 0, '', '');
            },
        bundleIdResolver: ({required String appBundlePath}) async {
          resolvedBundlePath = appBundlePath;
          return 'dev.cockpit.orbitStaging';
        },
        statusReader: (baseUri) async => CockpitRemoteSessionStatus(
          sessionId: 'macos-staging-session',
          platform: 'macos',
          transportType: 'remoteHttp',
          currentRouteName: '/home',
          capabilities: CockpitCapabilities(
            platform: 'macos',
            transportType: 'remoteHttp',
            supportsInAppControl: true,
            supportsFlutterViewCapture: true,
            supportsNativeScreenCapture: true,
            supportsHostAutomation: true,
          ),
          recordingCapabilities: CockpitRecordingCapabilities(
            supportsNativeRecording: true,
          ),
          snapshot: CockpitSnapshot(routeName: '/home'),
        ),
      );

      await launcher.launch(
        CockpitRemoteSessionLaunchOptions(
          projectDir: tempDir.path,
          target: 'cockpit/main.dart',
          flavor: 'staging',
          platform: 'macos',
          deviceId: 'macos',
          sessionPort: 47331,
        ),
      );

      expect(resolvedBundlePath, flavoredBundle.path);
    },
  );

  test(
    'macos remote session launcher falls back to the newest app bundle',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_macos_remote_session_launcher_recency',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final productsDirectory = Directory(
        '${tempDir.path}/build/macos/Build/Products/Debug',
      );
      await productsDirectory.create(recursive: true);
      final staleBundle = Directory('${productsDirectory.path}/Orbit.app');
      final newestBundle = Directory(
        '${productsDirectory.path}/Cockpit Demo.app',
      );
      await staleBundle.create(recursive: true);
      await Directory('${staleBundle.path}/Contents').create(recursive: true);
      await File(
        '${staleBundle.path}/Contents/Info.plist',
      ).create(recursive: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await newestBundle.create(recursive: true);
      await Directory('${newestBundle.path}/Contents').create(recursive: true);
      await File(
        '${newestBundle.path}/Contents/Info.plist',
      ).create(recursive: true);

      String? resolvedBundlePath;
      final launcher = CockpitMacosRemoteSessionLauncher(
        flutterVersionReader: () async => '3.38.9',
        processRunner:
            (
              executable,
              arguments, {
              String? workingDirectory,
              Map<String, String>? environment,
            }) async {
              return ProcessResult(0, 0, '', '');
            },
        bundleIdResolver: ({required String appBundlePath}) async {
          resolvedBundlePath = appBundlePath;
          return 'dev.cockpit.cockpitDemo';
        },
        statusReader: (baseUri) async => CockpitRemoteSessionStatus(
          sessionId: 'macos-latest-session',
          platform: 'macos',
          transportType: 'remoteHttp',
          currentRouteName: '/home',
          capabilities: CockpitCapabilities(
            platform: 'macos',
            transportType: 'remoteHttp',
            supportsInAppControl: true,
            supportsFlutterViewCapture: true,
            supportsNativeScreenCapture: true,
            supportsHostAutomation: true,
          ),
          recordingCapabilities: CockpitRecordingCapabilities(
            supportsNativeRecording: true,
          ),
          snapshot: CockpitSnapshot(routeName: '/home'),
        ),
      );

      await launcher.launch(
        CockpitRemoteSessionLaunchOptions(
          projectDir: tempDir.path,
          target: 'cockpit/main.dart',
          platform: 'macos',
          deviceId: 'macos',
          sessionPort: 47331,
        ),
      );

      expect(resolvedBundlePath, newestBundle.path);
    },
  );

  test(
    'macos remote session launcher ignores nested helper app bundles',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_macos_remote_session_launcher_nested',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final productsDirectory = Directory(
        '${tempDir.path}/build/macos/Build/Products/Debug',
      );
      await productsDirectory.create(recursive: true);
      final topLevelBundle = Directory('${productsDirectory.path}/Orbit.app');
      await topLevelBundle.create(recursive: true);
      await Directory(
        '${topLevelBundle.path}/Contents',
      ).create(recursive: true);
      await File(
        '${topLevelBundle.path}/Contents/Info.plist',
      ).create(recursive: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final nestedHelperBundle = Directory(
        '${topLevelBundle.path}/Contents/Helpers/Orbit Helper.app',
      );
      await nestedHelperBundle.create(recursive: true);
      await Directory(
        '${nestedHelperBundle.path}/Contents',
      ).create(recursive: true);
      await File(
        '${nestedHelperBundle.path}/Contents/Info.plist',
      ).create(recursive: true);

      String? resolvedBundlePath;
      final launcher = CockpitMacosRemoteSessionLauncher(
        flutterVersionReader: () async => '3.38.9',
        processRunner:
            (
              executable,
              arguments, {
              String? workingDirectory,
              Map<String, String>? environment,
            }) async {
              return ProcessResult(0, 0, '', '');
            },
        bundleIdResolver: ({required String appBundlePath}) async {
          resolvedBundlePath = appBundlePath;
          return 'dev.cockpit.orbit';
        },
        statusReader: (baseUri) async => CockpitRemoteSessionStatus(
          sessionId: 'macos-nested-session',
          platform: 'macos',
          transportType: 'remoteHttp',
          currentRouteName: '/home',
          capabilities: CockpitCapabilities(
            platform: 'macos',
            transportType: 'remoteHttp',
            supportsInAppControl: true,
            supportsFlutterViewCapture: true,
            supportsNativeScreenCapture: true,
            supportsHostAutomation: true,
          ),
          recordingCapabilities: CockpitRecordingCapabilities(
            supportsNativeRecording: true,
          ),
          snapshot: CockpitSnapshot(routeName: '/home'),
        ),
      );

      await launcher.launch(
        CockpitRemoteSessionLaunchOptions(
          projectDir: tempDir.path,
          target: 'cockpit/main.dart',
          platform: 'macos',
          deviceId: 'macos',
          sessionPort: 47331,
        ),
      );

      expect(resolvedBundlePath, topLevelBundle.path);
    },
  );

  test(
    'macos launcher forwards user Flutter arguments and runtime environment',
    () async {
      final buildInvocations = <Map<String, Object?>>[];
      Map<String, Object?>? startInvocation;
      final launcher = CockpitMacosRemoteSessionLauncher(
        flutterVersionReader: () async => '3.38.9',
        processRunner:
            (
              executable,
              arguments, {
              String? workingDirectory,
              Map<String, String>? environment,
            }) async {
              buildInvocations.add(<String, Object?>{
                'executable': executable,
                'arguments': arguments,
                'environment': environment,
              });
              return ProcessResult(0, 0, '', '');
            },
        appBundlePathResolver:
            ({required String projectDir, String? flavor}) async =>
                '$projectDir/build/macos/Build/Products/Debug/cockpit_demo.app',
        bundleIdResolver: ({required String appBundlePath}) async =>
            'dev.cockpit.cockpitDemo',
        bundleExecutablePathResolver: ({required String appBundlePath}) async =>
            '$appBundlePath/Contents/MacOS/cockpit_demo',
        appStarter:
            ({
              required String appBundlePath,
              required String? executablePath,
              required Map<String, String>? environment,
              required Duration timeout,
            }) async {
              startInvocation = <String, Object?>{
                'appBundlePath': appBundlePath,
                'executablePath': executablePath,
                'environment': environment,
              };
              return 6101;
            },
        statusReader: (baseUri) async => CockpitRemoteSessionStatus(
          sessionId: 'macos-launch-config',
          platform: 'macos',
          transportType: 'remoteHttp',
          currentRouteName: '/home',
          capabilities: CockpitCapabilities(
            platform: 'macos',
            transportType: 'remoteHttp',
            supportsInAppControl: true,
            supportsFlutterViewCapture: true,
            supportsNativeScreenCapture: true,
            supportsHostAutomation: true,
          ),
          recordingCapabilities: CockpitRecordingCapabilities(
            supportsNativeRecording: true,
          ),
          snapshot: CockpitSnapshot(routeName: '/home'),
        ),
      );

      final handle = await launcher.launch(
        CockpitRemoteSessionLaunchOptions(
          projectDir: '/workspace/examples/cockpit_demo',
          target: 'cockpit/main.dart',
          platform: 'macos',
          deviceId: 'macos',
          sessionPort: 47331,
          launchConfiguration: CockpitFlutterLaunchConfiguration(
            dartDefines: const <String>['API_URL=https://example.test'],
            dartDefineFromFiles: const <String>['config/dev.json'],
            flutterArgs: const <String>['--track-widget-creation'],
            environment: const <String, String>{'API_TOKEN': 'secret'},
          ),
        ),
      );

      expect(
        buildInvocations.first['arguments'],
        containsAllInOrder(<String>[
          '--dart-define=API_URL=https://example.test',
          '--dart-define-from-file=config/dev.json',
          '--track-widget-creation',
          '--dart-define=FLUTTER_COCKPIT_REMOTE_ENABLED=true',
        ]),
      );
      expect(buildInvocations.first['environment'], <String, String>{
        'API_TOKEN': 'secret',
      });
      expect(startInvocation?['environment'], <String, String>{
        'API_TOKEN': 'secret',
      });
      expect(handle.processId, 6101);
    },
  );
}
