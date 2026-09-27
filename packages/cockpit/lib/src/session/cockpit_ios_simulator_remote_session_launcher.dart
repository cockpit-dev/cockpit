import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'cockpit_apple_bundle_support.dart';
import 'cockpit_android_remote_session_launcher.dart';
import 'cockpit_flutter_launch_configuration.dart';
import 'cockpit_remote_session_handle.dart';
import 'cockpit_remote_session_launch_options.dart';
import 'cockpit_remote_session_launcher.dart';
import 'cockpit_session_process_runner.dart';
import 'cockpit_session_path.dart';

typedef CockpitIosBundleIdResolver =
    Future<String> Function({required String appBundlePath});
typedef CockpitIosSimulatorAppBundlePathResolver =
    Future<String> Function({required String projectDir, String? flavor});

final class CockpitIosSimulatorRemoteSessionLauncher
    implements CockpitRemoteSessionLauncher {
  CockpitIosSimulatorRemoteSessionLauncher({
    CockpitWorkingDirectoryProcessRunner? processRunner,
    CockpitIosBundleIdResolver bundleIdResolver = _resolveBundleId,
    CockpitIosSimulatorAppBundlePathResolver appBundlePathResolver =
        _resolveAppBundlePath,
    CockpitRemoteSessionStatusReader statusReader =
        cockpitReadRemoteSessionStatus,
    CockpitFlutterVersionReader flutterVersionReader =
        cockpitReadActiveFlutterVersion,
    CockpitFlutterExecutableVersionReader? flutterVersionForExecutableReader,
    DateTime Function()? now,
  }) : _processRunner = processRunner ?? _runProcess,
       _useKillableProcessRunner = processRunner == null,
       _bundleIdResolver = bundleIdResolver,
       _appBundlePathResolver = appBundlePathResolver,
       _statusReader = statusReader,
       _flutterVersionReader = flutterVersionReader,
       _flutterVersionForExecutableReader =
           flutterVersionForExecutableReader ??
           ((flutterExecutable) => cockpitReadFlutterVersion(
             flutterExecutable,
             processRunner: (executable, arguments) =>
                 (processRunner ?? _runProcess)(executable, arguments),
           )),
       _now = now ?? DateTime.now;

  final CockpitWorkingDirectoryProcessRunner _processRunner;
  final bool _useKillableProcessRunner;
  final CockpitIosBundleIdResolver _bundleIdResolver;
  final CockpitIosSimulatorAppBundlePathResolver _appBundlePathResolver;
  final CockpitRemoteSessionStatusReader _statusReader;
  final CockpitFlutterVersionReader _flutterVersionReader;
  final CockpitFlutterExecutableVersionReader
  _flutterVersionForExecutableReader;
  final DateTime Function() _now;

  @override
  Future<CockpitRemoteSessionHandle> launch(
    CockpitRemoteSessionLaunchOptions options,
  ) async {
    if (options.platform != 'ios') {
      throw StateError(
        'CockpitIosSimulatorRemoteSessionLauncher only supports ios options.',
      );
    }

    final deadline = _now().add(options.launchTimeout);
    final flutterExecutable =
        options.flutterExecutable ?? cockpitFlutterExecutable();
    final flutterVersion = await cockpitResolveFlutterVersionForLaunch(
      flutterExecutable: flutterExecutable,
      explicitFlutterVersion: options.flutterVersion,
      legacyFlutterVersionReader: options.flutterExecutable == null
          ? _flutterVersionReader
          : null,
      flutterVersionForExecutableReader: _flutterVersionForExecutableReader,
    );
    final bindHost = cockpitRemoteBindHostForPlatform(options.platform);
    await _runRequired(
      flutterExecutable,
      <String>[
        'build',
        'ios',
        '--simulator',
        '--debug',
        '--no-codesign',
        '--target',
        options.target,
        if (options.flavor case final flavor?
            when flavor.isNotEmpty) ...<String>['--flavor', flavor],
        ...cockpitBuildFlutterLaunchArguments(
          userConfiguration: options.launchConfiguration,
          internalArguments: cockpitBuildRemoteControlDartDefineArguments(
            host: bindHost,
            port: options.sessionPort,
            flutterVersion: flutterVersion,
            launchId: options.launchId,
            passwordDartDefineFile: options.passwordDartDefineFile,
          ),
        ),
      ],
      workingDirectory: options.projectDir,
      environment: options.launchConfiguration.processEnvironment,
      timeout: _remaining(deadline),
    );

    final appBundlePath =
        await _appBundlePathResolver(
          projectDir: options.projectDir,
          flavor: options.flavor,
        ).timeout(
          _remaining(deadline),
          onTimeout: () => throw TimeoutException(
            'Resolving iOS simulator app bundle path timed out.',
            _remaining(deadline),
          ),
        );
    final bundleId = await _bundleIdResolver(appBundlePath: appBundlePath)
        .timeout(
          _remaining(deadline),
          onTimeout: () => throw TimeoutException(
            'Resolving iOS simulator bundle identifier timed out.',
            _remaining(deadline),
          ),
        );

    await _runRequired('xcrun', <String>[
      'simctl',
      'install',
      options.deviceId,
      appBundlePath,
    ], timeout: _remaining(deadline));
    await _runRequired('xcrun', <String>[
      'simctl',
      'launch',
      options.deviceId,
      bundleId,
    ], timeout: _remaining(deadline));

    final baseUri = Uri.parse('http://127.0.0.1:${options.sessionPort}');
    try {
      final status = await cockpitWaitForRemoteSessionReady(
        baseUri: baseUri,
        timeout: _remaining(deadline),
        statusReader: _statusReader,
        expectedSessionId: options.launchId,
        expectedPlatform: options.platform,
        password: options.password,
      );
      return CockpitRemoteSessionHandle.fromRemoteStatus(
        projectDir: options.projectDir,
        target: options.target,
        deviceId: options.deviceId,
        appId: bundleId,
        host: '127.0.0.1',
        hostPort: options.sessionPort,
        devicePort: options.sessionPort,
        status: status,
        launchedAt: _now(),
        password: options.password,
      );
    } on Object {
      await _bestEffortTerminateLaunchedApp(
        deviceId: options.deviceId,
        bundleId: bundleId,
      );
      rethrow;
    }
  }

  Future<void> _bestEffortTerminateLaunchedApp({
    required String deviceId,
    required String bundleId,
  }) async {
    try {
      await _runRequired('xcrun', <String>[
        'simctl',
        'terminate',
        deviceId,
        bundleId,
      ], timeout: const Duration(seconds: 5));
    } on Object {
      // Launch failure reporting takes priority over cleanup failures.
    }
  }

  Future<void> _runRequired(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    required Duration timeout,
  }) async {
    final result = _useKillableProcessRunner
        ? await cockpitRunProcessWithTimeout(
            executable,
            arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            timeout: timeout,
          )
        : await _processRunner(
            executable,
            arguments,
            workingDirectory: workingDirectory,
            environment: environment,
          ).timeout(
            timeout,
            onTimeout: () => throw TimeoutException(
              '$executable ${arguments.join(' ')} timed out.',
              timeout,
            ),
          );
    if (result.exitCode != 0) {
      throw StateError(
        '$executable ${arguments.join(' ')} failed: ${result.stderr ?? result.stdout}',
      );
    }
  }

  Duration _remaining(DateTime deadline) {
    final remaining = deadline.difference(_now());
    if (remaining <= Duration.zero) {
      throw TimeoutException(
        'iOS simulator remote session launch timed out before the next stage could start.',
      );
    }
    return remaining;
  }

  static Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    return cockpitRunShortProcess(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  }

  static Future<String> _resolveBundleId({required String appBundlePath}) =>
      cockpitResolveIosBundleId(appBundlePath: appBundlePath);

  static Future<String> _resolveAppBundlePath({
    required String projectDir,
    String? flavor,
  }) async {
    final pathContext = cockpitSessionPathContext(projectDir);
    final buildDirectory = Directory(
      pathContext.join(projectDir, 'build', 'ios', 'iphonesimulator'),
    );
    if (!buildDirectory.existsSync()) {
      throw StateError(
        'Unable to locate iOS simulator build output at ${buildDirectory.path}.',
      );
    }
    return _selectBestAppBundlePath(
      buildDirectory: buildDirectory,
      flavor: flavor,
      pathContext: pathContext,
      platformLabel: 'iOS simulator',
    );
  }
}

String _selectBestAppBundlePath({
  required Directory buildDirectory,
  required String? flavor,
  required p.Context pathContext,
  required String platformLabel,
}) {
  return cockpitSelectBestAppBundlePath(
    searchRoot: buildDirectory,
    flavor: flavor,
    pathContext: pathContext,
    platformLabel: platformLabel,
  );
}
