import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../infrastructure/cockpit_process_manager.dart';
import 'cockpit_android_remote_session_launcher.dart';
import 'cockpit_apple_bundle_support.dart';
import 'cockpit_flutter_launch_configuration.dart';
import 'cockpit_remote_session_handle.dart';
import 'cockpit_remote_session_launch_options.dart';
import 'cockpit_remote_session_launcher.dart';
import 'cockpit_session_process_runner.dart';
import 'cockpit_session_path.dart';

typedef CockpitMacosBundleIdResolver =
    Future<String> Function({required String appBundlePath});

typedef CockpitMacosAppBundlePathResolver =
    Future<String> Function({required String projectDir, String? flavor});
typedef CockpitMacosBundleExecutablePathResolver =
    Future<String> Function({required String appBundlePath});
typedef CockpitMacosAppStarter =
    Future<int?> Function({
      required String appBundlePath,
      required String? executablePath,
      required Map<String, String>? environment,
      required Duration timeout,
    });

final class CockpitMacosRemoteSessionLauncher
    implements CockpitRemoteSessionLauncher {
  CockpitMacosRemoteSessionLauncher({
    CockpitWorkingDirectoryProcessRunner? processRunner,
    CockpitMacosBundleIdResolver bundleIdResolver = _resolveBundleId,
    CockpitMacosAppBundlePathResolver appBundlePathResolver =
        _resolveAppBundlePath,
    CockpitMacosBundleExecutablePathResolver bundleExecutablePathResolver =
        cockpitResolveMacosBundleExecutablePath,
    CockpitMacosAppStarter appStarter = _startMacosApp,
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
       _bundleExecutablePathResolver = bundleExecutablePathResolver,
       _appStarter = appStarter,
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
  final CockpitMacosBundleIdResolver _bundleIdResolver;
  final CockpitMacosAppBundlePathResolver _appBundlePathResolver;
  final CockpitMacosBundleExecutablePathResolver _bundleExecutablePathResolver;
  final CockpitMacosAppStarter _appStarter;
  final CockpitRemoteSessionStatusReader _statusReader;
  final CockpitFlutterVersionReader _flutterVersionReader;
  final CockpitFlutterExecutableVersionReader
  _flutterVersionForExecutableReader;
  final DateTime Function() _now;

  @override
  Future<CockpitRemoteSessionHandle> launch(
    CockpitRemoteSessionLaunchOptions options,
  ) async {
    if (options.platform != 'macos') {
      throw StateError(
        'CockpitMacosRemoteSessionLauncher only supports macos options.',
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
    await _runMacosBuildWithCacheRecovery(
      flutterExecutable,
      <String>[
        'build',
        'macos',
        '--debug',
        '--target',
        options.target,
        if (options.flavor case final flavor?
            when flavor.isNotEmpty) ...<String>['--flavor', flavor],
        ...cockpitBuildFlutterLaunchArguments(
          userConfiguration: options.launchConfiguration,
          internalArguments: cockpitBuildRemoteControlDartDefineArguments(
            host: '127.0.0.1',
            port: options.sessionPort,
            flutterVersion: flutterVersion,
            launchId: options.launchId,
          ),
        ),
      ],
      workingDirectory: options.projectDir,
      environment: options.launchConfiguration.processEnvironment,
      deadline: deadline,
    );

    final appBundlePath = await _appBundlePathResolver(
      projectDir: options.projectDir,
      flavor: options.flavor,
    );
    final bundleId = await _bundleIdResolver(appBundlePath: appBundlePath);
    final processEnvironment =
        options.appEnvironment ??
        options.launchConfiguration.processEnvironment;
    final executablePath =
        processEnvironment == null || processEnvironment.isEmpty
        ? null
        : await _bundleExecutablePathResolver(appBundlePath: appBundlePath);
    await _bestEffortStopRunningApp(
      bundleId,
      timeout: _capTimeout(_remaining(deadline), const Duration(seconds: 5)),
    );

    final processId = await _appStarter(
      appBundlePath: appBundlePath,
      executablePath: executablePath,
      environment: processEnvironment,
      timeout: _remaining(deadline),
    );

    final baseUri = Uri.parse('http://127.0.0.1:${options.sessionPort}');
    try {
      final status = await cockpitWaitForRemoteSessionReady(
        baseUri: baseUri,
        timeout: _remaining(deadline),
        statusReader: _statusReader,
        expectedSessionId: options.launchId,
        expectedPlatform: options.platform,
      );
      return CockpitRemoteSessionHandle.fromRemoteStatus(
        projectDir: options.projectDir,
        target: options.target,
        deviceId: options.deviceId,
        appId: bundleId,
        processId: processId,
        host: '127.0.0.1',
        hostPort: options.sessionPort,
        devicePort: options.sessionPort,
        status: status,
        launchedAt: _now(),
      );
    } on Object {
      await _bestEffortStopRunningApp(
        bundleId,
        timeout: const Duration(seconds: 5),
      );
      rethrow;
    }
  }

  Future<void> _bestEffortStopRunningApp(
    String bundleId, {
    required Duration timeout,
  }) async {
    try {
      await _runRequired('osascript', <String>[
        '-e',
        'tell application id "$bundleId" to quit',
      ], timeout: timeout);
      await Future<void>.delayed(const Duration(milliseconds: 400));
    } on Object {
      // The app may not be running yet; launch should still continue.
    }
  }

  Future<void> _runRequired(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    required Duration timeout,
  }) async {
    final result = await _runProcessResult(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      timeout: timeout,
    );
    if (result.exitCode != 0) {
      throw _failedProcessStateError(executable, arguments, result);
    }
  }

  Future<void> _runMacosBuildWithCacheRecovery(
    String flutterExecutable,
    List<String> buildArguments, {
    required String workingDirectory,
    Map<String, String>? environment,
    required DateTime deadline,
  }) async {
    final firstResult = await _runProcessResult(
      flutterExecutable,
      buildArguments,
      workingDirectory: workingDirectory,
      environment: environment,
      timeout: _remaining(deadline),
    );
    if (firstResult.exitCode == 0) {
      return;
    }
    final firstOutput = _processOutputText(firstResult);
    if (!_isRecoverableMacosBuildCacheFailure(firstOutput)) {
      throw _failedProcessStateError(
        flutterExecutable,
        buildArguments,
        firstResult,
      );
    }

    await _runRequired(
      flutterExecutable,
      const <String>['clean'],
      workingDirectory: workingDirectory,
      timeout: _capTimeout(_remaining(deadline), const Duration(minutes: 2)),
    );
    await _runRequired(
      flutterExecutable,
      const <String>['pub', 'get'],
      workingDirectory: workingDirectory,
      environment: environment,
      timeout: _capTimeout(_remaining(deadline), const Duration(minutes: 2)),
    );
    final retryResult = await _runProcessResult(
      flutterExecutable,
      buildArguments,
      workingDirectory: workingDirectory,
      environment: environment,
      timeout: _remaining(deadline),
    );
    if (retryResult.exitCode != 0) {
      throw _failedProcessStateError(
        flutterExecutable,
        buildArguments,
        retryResult,
      );
    }
  }

  Future<ProcessResult> _runProcessResult(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    required Duration timeout,
  }) {
    if (_useKillableProcessRunner) {
      return cockpitRunProcessWithTimeout(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        timeout: timeout,
      );
    }
    return _processRunner(
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
  }

  StateError _failedProcessStateError(
    String executable,
    List<String> arguments,
    ProcessResult result,
  ) {
    return StateError(
      '$executable ${arguments.join(' ')} failed: ${_processOutputText(result)}',
    );
  }

  String _processOutputText(ProcessResult result) {
    final stderrText = '${result.stderr}'.trim();
    if (stderrText.isNotEmpty) {
      return stderrText;
    }
    return '${result.stdout}'.trim();
  }

  bool _isRecoverableMacosBuildCacheFailure(String output) {
    return output.contains('has been modified since the module file') ||
        output.contains('SwiftExplicitPrecompiledModules') ||
        output.contains('explicit-swift-module-map-file') ||
        output.contains('FlutterGeneratedPluginSwiftPackage') &&
            output.contains("doesn't exist in file system");
  }

  Duration _remaining(DateTime deadline) {
    final remaining = deadline.difference(_now());
    if (remaining <= Duration.zero) {
      throw TimeoutException(
        'macOS remote session launch timed out before the next stage could start.',
      );
    }
    return remaining;
  }

  Duration _capTimeout(Duration value, Duration max) {
    return value < max ? value : max;
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

  static Future<int?> _startMacosApp({
    required String appBundlePath,
    required String? executablePath,
    required Map<String, String>? environment,
    required Duration timeout,
  }) async {
    if (environment == null || environment.isEmpty) {
      await cockpitRunProcessWithTimeout('open', <String>[
        '-n',
        appBundlePath,
      ], timeout: timeout);
      return null;
    }
    if (executablePath == null || executablePath.isEmpty) {
      throw StateError(
        'macOS runtime environment requires a bundle executable path.',
      );
    }
    final pathContext = cockpitSessionPathContext(executablePath);
    final process =
        await cockpitStartIsolatedProcess(
          executablePath,
          const <String>[],
          workingDirectory: pathContext.dirname(executablePath),
          environment: environment,
          mode: ProcessStartMode.detached,
        ).timeout(
          timeout,
          onTimeout: () => throw TimeoutException(
            'Launching $executablePath timed out.',
            timeout,
          ),
        );
    return process.pid == 0 ? null : process.pid;
  }

  static Future<String> _resolveBundleId({required String appBundlePath}) =>
      cockpitResolveMacosBundleId(appBundlePath: appBundlePath);

  static Future<String> _resolveAppBundlePath({
    required String projectDir,
    String? flavor,
  }) async {
    final pathContext = cockpitSessionPathContext(projectDir);
    final productsDirectory = Directory(
      pathContext.join(
        projectDir,
        'build',
        'macos',
        'Build',
        'Products',
        'Debug',
      ),
    );
    if (!productsDirectory.existsSync()) {
      throw StateError(
        'Unable to locate macOS build products at ${productsDirectory.path}.',
      );
    }
    return _selectBestMacosAppBundlePath(
      productsDirectory: productsDirectory,
      flavor: flavor,
      pathContext: pathContext,
    );
  }
}

String _selectBestMacosAppBundlePath({
  required Directory productsDirectory,
  required String? flavor,
  required p.Context pathContext,
}) {
  return cockpitSelectBestAppBundlePath(
    searchRoot: productsDirectory,
    flavor: flavor,
    pathContext: pathContext,
    platformLabel: 'macOS',
  );
}
