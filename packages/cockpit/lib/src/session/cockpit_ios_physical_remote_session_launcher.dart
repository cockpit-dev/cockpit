import 'dart:async';
import 'dart:io';

import '../platform/ios/cockpit_ios_device_connection.dart';
import '../remote/cockpit_ios_port_forwarder.dart';
import 'cockpit_apple_bundle_support.dart';
import 'cockpit_flutter_launch_configuration.dart';
import 'cockpit_remote_session_handle.dart';
import 'cockpit_remote_session_launch_options.dart';
import 'cockpit_remote_session_launcher.dart';
import 'cockpit_session_process_runner.dart';
import 'cockpit_session_path.dart';

typedef CockpitIosPhysicalProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
    });
typedef CockpitIosDeviceConnectionReader =
    Future<CockpitIosDeviceConnection?> Function(String deviceId);
typedef CockpitIosPhysicalBundleIdResolver =
    Future<String> Function({required String appBundlePath});
typedef CockpitIosPhysicalAppBundlePathResolver =
    Future<String> Function({required String projectDir, String? flavor});

final class CockpitIosPhysicalRemoteSessionLauncher
    implements CockpitRemoteSessionLauncher {
  CockpitIosPhysicalRemoteSessionLauncher({
    CockpitIosPhysicalProcessRunner? processRunner,
    CockpitIosDeviceConnectionReader deviceConnectionResolver =
        _defaultDeviceConnectionResolver,
    CockpitIosPortForwarder? portForwarder,
    CockpitIosPhysicalBundleIdResolver bundleIdResolver = _resolveBundleId,
    CockpitIosPhysicalAppBundlePathResolver appBundlePathResolver =
        _resolveAppBundlePath,
    CockpitRemoteSessionStatusReader statusReader =
        cockpitReadRemoteSessionStatus,
    CockpitFlutterVersionReader flutterVersionReader =
        cockpitReadActiveFlutterVersion,
    CockpitFlutterExecutableVersionReader? flutterVersionForExecutableReader,
    DateTime Function()? now,
  }) : _processRunner = processRunner ?? _runProcess,
       _useKillableProcessRunner = processRunner == null,
       _deviceConnectionResolver = deviceConnectionResolver,
       _portForwarder = portForwarder ?? CockpitIosPortForwarder(),
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

  final CockpitIosPhysicalProcessRunner _processRunner;
  final bool _useKillableProcessRunner;
  final CockpitIosDeviceConnectionReader _deviceConnectionResolver;
  final CockpitIosPortForwarder _portForwarder;
  final CockpitIosPhysicalBundleIdResolver _bundleIdResolver;
  final CockpitIosPhysicalAppBundlePathResolver _appBundlePathResolver;
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
        'CockpitIosPhysicalRemoteSessionLauncher only supports ios options.',
      );
    }
    if (cockpitLooksLikeIosSimulatorDeviceId(options.deviceId)) {
      throw StateError(
        'CockpitIosPhysicalRemoteSessionLauncher only supports physical iOS devices.',
      );
    }

    final deadline = _now().add(options.launchTimeout);
    final connection = await _deviceConnectionResolver(options.deviceId)
        .timeout(
          _remaining(deadline),
          onTimeout: () => throw TimeoutException(
            'Resolving the iOS device tunnel timed out.',
            _remaining(deadline),
          ),
        );
    if (connection == null || !connection.hasReachableTunnel) {
      throw StateError(
        'Unable to resolve a reachable iOS device tunnel for ${options.deviceId}.',
      );
    }

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
    await _runRequired(
      flutterExecutable,
      <String>[
        'run',
        '-d',
        options.deviceId,
        '--profile',
        '--no-resident',
        '--target',
        options.target,
        if (options.flavor case final flavor?
            when flavor.isNotEmpty) ...<String>['--flavor', flavor],
        ...cockpitBuildFlutterLaunchArguments(
          userConfiguration: options.launchConfiguration,
          internalArguments: cockpitBuildRemoteControlDartDefineArguments(
            host: '::',
            port: options.sessionPort,
            flutterVersion: flutterVersion,
            launchId: options.launchId,
            disableHttpNetworkObserver: true,
            disableRuntimeObserver: true,
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
            'Resolving the iOS device app bundle path timed out.',
            _remaining(deadline),
          ),
        );
    final bundleId = await _bundleIdResolver(appBundlePath: appBundlePath)
        .timeout(
          _remaining(deadline),
          onTimeout: () => throw TimeoutException(
            'Resolving the iOS device bundle identifier timed out.',
            _remaining(deadline),
          ),
        );
    final hostPort = connection.isWired
        ? await _portForwarder.ensureForwarded(
            deviceId: options.deviceId,
            preferredHostPort: options.sessionPort,
            devicePort: options.sessionPort,
            flutterExecutable: flutterExecutable,
          )
        : options.sessionPort;
    final baseUri = Uri(
      scheme: 'http',
      host: connection.isWired ? '127.0.0.1' : connection.tunnelIpAddress!,
      port: hostPort,
    );
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
        host: baseUri.host,
        hostPort: hostPort,
        devicePort: options.sessionPort,
        status: status,
        launchedAt: _now(),
      );
    } on Object {
      if (connection.isWired) {
        await _portForwarder.removeForwarded(
          deviceId: options.deviceId,
          hostPort: hostPort,
        );
      }
      rethrow;
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
        'iOS physical-device remote session launch timed out before the next stage could start.',
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
      pathContext.join(projectDir, 'build', 'ios', 'iphoneos'),
    );
    if (!buildDirectory.existsSync()) {
      throw StateError(
        'Unable to locate iOS device build output at ${buildDirectory.path}.',
      );
    }
    return cockpitSelectBestAppBundlePath(
      searchRoot: buildDirectory,
      flavor: flavor,
      pathContext: pathContext,
      platformLabel: 'iOS device',
    );
  }
}

Future<CockpitIosDeviceConnection?> _defaultDeviceConnectionResolver(
  String deviceId,
) {
  return CockpitIosDeviceConnectionProbe().probe(deviceId);
}
