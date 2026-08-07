import 'dart:async';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart'
    show CockpitRemoteSessionStatus;

import '../remote/cockpit_android_port_forwarder.dart';
import '../platform/ios/cockpit_ios_device_connection.dart';
import '../session/cockpit_apple_bundle_support.dart';
import '../session/cockpit_flutter_launch_configuration.dart';
import '../session/cockpit_platform_app_identity.dart';
import '../session/cockpit_remote_session_handle.dart';
import '../session/cockpit_remote_session_launcher.dart';
import '../session/cockpit_session_process_runner.dart';
import '../session/cockpit_session_path.dart';
import 'cockpit_flutter_run_machine_client.dart';

typedef CockpitDevelopmentMachineClientStarter =
    Future<CockpitFlutterRunMachineClient> Function({
      required String projectDir,
      required String target,
      required String deviceId,
      String? flavor,
      String? flutterExecutable,
      List<String> extraArgs,
      Map<String, String>? environment,
    });
typedef CockpitDevelopmentMachineClientStarted =
    FutureOr<void> Function(CockpitFlutterRunMachineClient machineClient);
typedef CockpitDevelopmentRecoveryProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      required Duration timeout,
    });
typedef CockpitIosDeviceConnectionResolver =
    Future<CockpitIosDeviceConnection?> Function(String deviceId);
typedef CockpitIosFallbackBundleIdResolver =
    Future<String> Function({required String appBundlePath});
typedef CockpitIosFallbackAppBundlePathResolver =
    Future<String> Function({required String projectDir, String? flavor});
typedef CockpitPlatformAppIdResolver =
    Future<String?> Function({
      required String projectDir,
      required String platform,
      String? flavor,
    });
typedef CockpitDevelopmentMachineDiagnosticLogger =
    FutureOr<void> Function(String message);

final class CockpitLaunchDevelopmentMachineSessionRequest {
  const CockpitLaunchDevelopmentMachineSessionRequest({
    required this.projectDir,
    required this.target,
    required this.platform,
    required this.deviceId,
    required this.sessionPort,
    required this.hostPort,
    required this.launchTimeout,
    required this.flutterVersion,
    this.flavor,
    this.flutterExecutable,
    this.launchId,
    this.launchConfiguration = CockpitFlutterLaunchConfiguration.empty,
  });

  final String projectDir;
  final String target;
  final String platform;
  final String deviceId;
  final int sessionPort;
  final int hostPort;
  final Duration launchTimeout;
  final String flutterVersion;
  final String? flavor;
  final String? flutterExecutable;
  final String? launchId;
  final CockpitFlutterLaunchConfiguration launchConfiguration;
}

final class CockpitLaunchDevelopmentMachineSessionResult {
  const CockpitLaunchDevelopmentMachineSessionResult({
    required this.machineClient,
    required this.remoteSessionHandle,
  });

  final CockpitFlutterRunMachineClient machineClient;
  final CockpitRemoteSessionHandle remoteSessionHandle;
}

final class CockpitDevelopmentSessionFallbackException implements Exception {
  const CockpitDevelopmentSessionFallbackException({
    required this.code,
    required this.message,
    this.remoteSessionHandle,
    this.remoteStatus,
  });

  final String code;
  final String message;
  final CockpitRemoteSessionHandle? remoteSessionHandle;
  final CockpitRemoteSessionStatus? remoteStatus;

  @override
  String toString() => 'CockpitDevelopmentSessionFallbackException: $message';
}

final class CockpitDevelopmentSessionMachineLauncher {
  CockpitDevelopmentSessionMachineLauncher({
    CockpitDevelopmentMachineClientStarter? machineClientStarter,
    CockpitDevelopmentRecoveryProcessRunner? recoveryProcessRunner,
    CockpitRemoteSessionStatusReader statusReader =
        cockpitReadRemoteSessionStatus,
    CockpitAndroidPortForwarder portForwarder =
        const CockpitAndroidPortForwarder(),
    CockpitIosDeviceConnectionResolver? iosDeviceConnectionResolver,
    CockpitIosFallbackBundleIdResolver iosFallbackBundleIdResolver =
        cockpitResolveIosBundleId,
    CockpitIosFallbackAppBundlePathResolver iosFallbackAppBundlePathResolver =
        _resolveIosPhysicalAppBundlePath,
    CockpitPlatformAppIdResolver platformAppIdResolver =
        cockpitResolvePlatformAppId,
    CockpitDevelopmentMachineDiagnosticLogger? diagnosticLogger,
    Future<void> Function(Duration duration)? delay,
    DateTime Function()? now,
  }) : _machineClientStarter =
           machineClientStarter ?? CockpitFlutterRunMachineClient.start,
       _recoveryProcessRunner = recoveryProcessRunner ?? _runRecoveryProcess,
       _statusReader = statusReader,
       _portForwarder = portForwarder,
       _iosDeviceConnectionResolver =
           iosDeviceConnectionResolver ??
           CockpitIosDeviceConnectionProbe().probe,
       _iosFallbackBundleIdResolver = iosFallbackBundleIdResolver,
       _iosFallbackAppBundlePathResolver = iosFallbackAppBundlePathResolver,
       _platformAppIdResolver = platformAppIdResolver,
       _diagnosticLogger = diagnosticLogger,
       _delay = delay ?? Future<void>.delayed,
       _now = now ?? DateTime.now;

  final CockpitDevelopmentMachineClientStarter _machineClientStarter;
  final CockpitDevelopmentRecoveryProcessRunner _recoveryProcessRunner;
  final CockpitRemoteSessionStatusReader _statusReader;
  final CockpitAndroidPortForwarder _portForwarder;
  final CockpitIosDeviceConnectionResolver _iosDeviceConnectionResolver;
  final CockpitIosFallbackBundleIdResolver _iosFallbackBundleIdResolver;
  final CockpitIosFallbackAppBundlePathResolver
  _iosFallbackAppBundlePathResolver;
  final CockpitPlatformAppIdResolver _platformAppIdResolver;
  final CockpitDevelopmentMachineDiagnosticLogger? _diagnosticLogger;
  final Future<void> Function(Duration duration) _delay;
  final DateTime Function() _now;

  Future<CockpitLaunchDevelopmentMachineSessionResult> launch(
    CockpitLaunchDevelopmentMachineSessionRequest request,
  ) {
    return launchWithLifecycle(request);
  }

  Future<CockpitLaunchDevelopmentMachineSessionResult> launchWithLifecycle(
    CockpitLaunchDevelopmentMachineSessionRequest request, {
    CockpitResolvedRemoteSessionEndpoint? endpoint,
    CockpitDevelopmentMachineClientStarted? onMachineClientStarted,
  }) async {
    final resolvedEndpoint =
        endpoint ?? await resolveRemoteSessionEndpoint(request);
    final deadline = _now().add(request.launchTimeout);
    var attemptedRecovery = false;

    while (true) {
      final machineClient = await startMachineClient(
        request,
        endpoint: resolvedEndpoint,
      );
      try {
        await onMachineClientStarted?.call(machineClient);
        final remoteSessionHandle = await waitForRemoteSession(
          request: request,
          machineClient: machineClient,
          endpoint: resolvedEndpoint,
          deadline: deadline,
        );

        return CockpitLaunchDevelopmentMachineSessionResult(
          machineClient: machineClient,
          remoteSessionHandle: remoteSessionHandle,
        );
      } on Object catch (error) {
        final recovery = attemptedRecovery
            ? null
            : _developmentRecovery(
                request: request,
                error: error,
                machineClient: machineClient,
              );
        if (recovery == null) {
          await machineClient.dispose();
          rethrow;
        }
        attemptedRecovery = true;
        await machineClient.dispose();
        if (recovery == _DevelopmentLaunchRecovery.clean) {
          await _runMacosDevelopmentClean(
            request,
            timeout: _capTimeout(
              _remaining(deadline),
              const Duration(minutes: 2),
            ),
          );
        } else {
          _remaining(deadline);
        }
      }
    }
  }

  Future<void> _runMacosDevelopmentClean(
    CockpitLaunchDevelopmentMachineSessionRequest request, {
    required Duration timeout,
  }) async {
    final flutterExecutable =
        request.flutterExecutable ?? cockpitFlutterExecutable();
    final result = await _recoveryProcessRunner(
      flutterExecutable,
      const <String>['clean'],
      workingDirectory: request.projectDir,
      timeout: timeout,
    );
    if (result.exitCode != 0) {
      throw StateError(
        '$flutterExecutable clean failed while recovering macOS Swift module '
        'cache: ${_processOutputText(result)}',
      );
    }
  }

  Future<CockpitFlutterRunMachineClient> startMachineClient(
    CockpitLaunchDevelopmentMachineSessionRequest request, {
    required CockpitResolvedRemoteSessionEndpoint endpoint,
  }) {
    return _machineClientStarter(
      projectDir: request.projectDir,
      target: request.target,
      deviceId: request.deviceId,
      flavor: request.flavor,
      flutterExecutable: request.flutterExecutable,
      extraArgs: _buildRemoteSessionExtraArgs(request, endpoint: endpoint),
      environment: request.launchConfiguration.processEnvironment,
    );
  }

  Future<CockpitRemoteSessionHandle> waitForRemoteSession({
    required CockpitLaunchDevelopmentMachineSessionRequest request,
    required CockpitFlutterRunMachineClient machineClient,
    required CockpitResolvedRemoteSessionEndpoint endpoint,
    DateTime? deadline,
  }) async {
    final hostPort = request.platform == 'android'
        ? await _portForwarder.ensureForwarded(
            deviceId: request.deviceId,
            preferredHostPort: request.hostPort,
            devicePort: request.sessionPort,
          )
        : request.hostPort;
    final publicHost = endpoint.publicHost;
    final baseUri = Uri(scheme: 'http', host: publicHost, port: hostPort);
    await _logDiagnostic(
      'remote_status_probe begin platform=${request.platform} '
      'base_url=$baseUri host_port=$hostPort device_port=${request.sessionPort}',
    );
    final effectiveDeadline = deadline ?? _now().add(request.launchTimeout);
    late final CockpitRemoteSessionStatus status;
    late final String appId;
    if (_isPhysicalIosDevice(request)) {
      status = await _waitForRemoteStatus(
        request: request,
        machineClient: machineClient,
        baseUri: baseUri,
        deadline: effectiveDeadline,
      );
      appId = await (() async {
        try {
          return await _waitForMachineAppId(
            request: request,
            machineClient: machineClient,
            deadline: effectiveDeadline,
          );
        } on CockpitDevelopmentSessionFallbackException catch (error) {
          final remoteSessionHandle =
              await _buildPhysicalIosFallbackRemoteSessionHandle(
                request: request,
                endpoint: endpoint,
                hostPort: hostPort,
                status: status,
              );
          throw CockpitDevelopmentSessionFallbackException(
            code: error.code,
            message: error.message,
            remoteSessionHandle: remoteSessionHandle,
            remoteStatus: status,
          );
        }
      })();
    } else {
      appId = await _waitForMachineAppId(
        request: request,
        machineClient: machineClient,
        deadline: effectiveDeadline,
      );
      status = await _waitForRemoteStatus(
        request: request,
        machineClient: machineClient,
        baseUri: baseUri,
        deadline: effectiveDeadline,
      );
    }
    final platformAppId = await _resolvePlatformAppId(
      request: request,
      status: status,
    );

    return CockpitRemoteSessionHandle.fromRemoteStatus(
      projectDir: request.projectDir,
      target: request.target,
      deviceId: request.deviceId,
      appId: appId,
      platformAppId: platformAppId,
      platformAppIdKnown: platformAppId != null,
      processId: status.processId,
      host: publicHost,
      hostPort: hostPort,
      devicePort: request.sessionPort,
      status: status,
      launchedAt: _now(),
    );
  }

  List<String> _buildRemoteSessionExtraArgs(
    CockpitLaunchDevelopmentMachineSessionRequest request, {
    required CockpitResolvedRemoteSessionEndpoint endpoint,
  }) {
    final disableIpv6UnsafeObservers =
        request.platform == 'ios' && endpoint.bindHost == '::';
    final internalArgs = cockpitBuildRemoteControlDartDefineArguments(
      host: endpoint.bindHost,
      port: request.sessionPort,
      flutterVersion: request.flutterVersion,
      launchId: request.launchId,
      disableHttpNetworkObserver: disableIpv6UnsafeObservers,
      disableRuntimeObserver: disableIpv6UnsafeObservers,
    );
    return cockpitBuildFlutterLaunchArguments(
      userConfiguration: request.launchConfiguration,
      internalArguments: <String>['--no-dds', ...internalArgs],
    );
  }

  Future<CockpitResolvedRemoteSessionEndpoint> resolveRemoteSessionEndpoint(
    CockpitLaunchDevelopmentMachineSessionRequest request,
  ) async {
    if (request.platform != 'ios') {
      return CockpitResolvedRemoteSessionEndpoint(
        bindHost: cockpitRemoteBindHostForPlatform(request.platform),
        publicHost: cockpitRemotePublicHostForPlatform(request.platform),
      );
    }

    if (cockpitLooksLikeIosSimulatorDeviceId(request.deviceId)) {
      return const CockpitResolvedRemoteSessionEndpoint(
        bindHost: '0.0.0.0',
        publicHost: '127.0.0.1',
      );
    }

    final connection = await _iosDeviceConnectionResolver(request.deviceId);
    if (connection != null && connection.hasReachableTunnel) {
      return CockpitResolvedRemoteSessionEndpoint(
        bindHost: '::',
        publicHost: connection.tunnelIpAddress!,
      );
    }

    throw StateError(
      'Unable to resolve a reachable iOS tunnel address for device '
      '${request.deviceId}. Ensure the device is unlocked, connected, and '
      'developer disk image services are available.',
    );
  }

  Future<String> _waitForMachineAppId({
    required CockpitLaunchDevelopmentMachineSessionRequest request,
    required CockpitFlutterRunMachineClient machineClient,
    required DateTime deadline,
  }) async {
    while (_now().isBefore(deadline)) {
      final currentAppId = machineClient.currentAppId;
      if (currentAppId != null && currentAppId.isNotEmpty) {
        return currentAppId;
      }
      final exitError = _machineExitError(
        request: request,
        machineClient: machineClient,
        remoteSessionReady: true,
      );
      if (exitError != null) {
        throw exitError;
      }
      await _delay(const Duration(milliseconds: 50));
    }
    if (_isPhysicalIosDevice(request)) {
      throw const CockpitDevelopmentSessionFallbackException(
        code: 'iosPhysicalRemoteSessionReadyButDevelopmentAttachFailed',
        message:
            'The iOS physical-device remote session became reachable, but '
            'flutter run --machine never reported app.start before timeout. '
            'Automation fallback is safe.',
      );
    }
    throw TimeoutException(
      'Flutter run machine session never reported an app.start appId.',
      deadline.difference(_now()),
    );
  }

  Future<CockpitRemoteSessionStatus> _waitForRemoteStatus({
    required CockpitLaunchDevelopmentMachineSessionRequest request,
    required CockpitFlutterRunMachineClient machineClient,
    required Uri baseUri,
    required DateTime deadline,
    Duration pollInterval = const Duration(milliseconds: 500),
  }) async {
    String? lastRejectedStatus;
    Object? lastProbeError;
    var probeAttempts = 0;
    while (true) {
      final remaining = deadline.difference(_now());
      if (remaining <= Duration.zero) {
        break;
      }
      probeAttempts += 1;
      try {
        final status = await _statusReader(baseUri).timeout(remaining);
        if (_remoteStatusMatchesRequest(request: request, status: status)) {
          await _logDiagnostic(
            'remote_status_probe ready base_url=$baseUri '
            'attempt=$probeAttempts platform=${status.platform} '
            'session_id=${status.sessionId}',
          );
          return status;
        }
        lastRejectedStatus =
            'platform=${status.platform}, expected=${request.platform}, '
            'sessionId=${status.sessionId}, '
            'expectedSessionId=${request.launchId ?? ''}';
        await _logDiagnostic(
          'remote_status_probe rejected base_url=$baseUri '
          'attempt=$probeAttempts ${_compactDiagnostic(lastRejectedStatus)}',
        );
      } on Object catch (error) {
        lastProbeError = error;
        if (_shouldLogRemoteProbeFailure(probeAttempts, error)) {
          await _logDiagnostic(
            'remote_status_probe failed base_url=$baseUri '
            'attempt=$probeAttempts error=${_compactDiagnostic(error)}'
            '${_machineDiagnosticsSuffix(machineClient)}',
          );
        }
        final exitError = _machineExitError(
          request: request,
          machineClient: machineClient,
          remoteSessionReady: false,
        );
        if (exitError != null && !_isPhysicalIosDevice(request)) {
          throw exitError;
        }
      }
      final exitError = _machineExitError(
        request: request,
        machineClient: machineClient,
        remoteSessionReady: false,
      );
      if (exitError != null && !_isPhysicalIosDevice(request)) {
        throw exitError;
      }
      final retryDelay = deadline.difference(_now());
      if (retryDelay <= Duration.zero) {
        break;
      }
      await _delay(retryDelay < pollInterval ? retryDelay : pollInterval);
    }
    final exitCode = machineClient.lastExitCode;
    final diagnostics = machineClient.recentDiagnosticSummary;
    await _logDiagnostic(
      'remote_status_probe timed_out base_url=$baseUri attempts=$probeAttempts'
      '${lastProbeError == null ? '' : ' last_error=${_compactDiagnostic(lastProbeError)}'}'
      '${lastRejectedStatus == null ? '' : ' last_rejected=${_compactDiagnostic(lastRejectedStatus)}'}'
      '${exitCode == null ? '' : ' machine_exit_code=$exitCode'}'
      '${diagnostics.isEmpty ? '' : ' diagnostics=${_compactDiagnostic(diagnostics)}'}',
    );
    final suffix = exitCode == null
        ? ''
        : diagnostics.isEmpty
        ? ' after flutter run --machine exited (exitCode=$exitCode)'
        : ' after flutter run --machine exited '
              '(exitCode=$exitCode): $diagnostics';
    throw TimeoutException(
      'Remote session did not become ready at $baseUri$suffix'
      '${lastRejectedStatus == null ? '' : ' (last rejected health: $lastRejectedStatus)'}.',
      deadline.difference(_now()),
    );
  }

  bool _shouldLogRemoteProbeFailure(int attempt, Object error) {
    if (attempt <= 3) {
      return true;
    }
    if (attempt % 20 == 0) {
      return true;
    }
    final message = '$error'.toLowerCase();
    return !message.contains('connection refused');
  }

  String _machineDiagnosticsSuffix(CockpitFlutterRunMachineClient client) {
    final diagnostics = client.recentDiagnosticSummary;
    if (diagnostics.isEmpty) {
      return '';
    }
    return ' diagnostics=${_compactDiagnostic(diagnostics)}';
  }

  String _compactDiagnostic(Object? value, {int maxLength = 600}) {
    final text = '$value'.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= maxLength) {
      return text;
    }
    return '${text.substring(0, maxLength)}...';
  }

  Future<void> _logDiagnostic(String message) async {
    final logger = _diagnosticLogger;
    if (logger == null) {
      return;
    }
    await logger(message);
  }

  bool _remoteStatusMatchesRequest({
    required CockpitLaunchDevelopmentMachineSessionRequest request,
    required CockpitRemoteSessionStatus status,
  }) {
    final expectedLaunchId = request.launchId?.trim();
    if (expectedLaunchId != null &&
        expectedLaunchId.isNotEmpty &&
        status.sessionId != expectedLaunchId) {
      return false;
    }
    return status.platform.trim().toLowerCase() ==
        request.platform.trim().toLowerCase();
  }

  Object? _machineExitError({
    required CockpitLaunchDevelopmentMachineSessionRequest request,
    required CockpitFlutterRunMachineClient machineClient,
    required bool remoteSessionReady,
  }) {
    final exitCode = machineClient.lastExitCode;
    if (exitCode == null) {
      return null;
    }
    final diagnostics = machineClient.recentDiagnosticSummary;
    final suffix = diagnostics.isEmpty ? '' : ': $diagnostics';
    if (remoteSessionReady && _isPhysicalIosDevice(request)) {
      return CockpitDevelopmentSessionFallbackException(
        code: 'iosPhysicalRemoteSessionReadyButDevelopmentAttachFailed',
        message:
            'The iOS physical-device remote session became reachable, but '
            'flutter run --machine exited before app.start '
            '(exitCode=$exitCode)$suffix. Automation fallback is safe.',
      );
    }
    return StateError(
      'Flutter run machine session exited before ${remoteSessionReady ? 'app.start' : 'the remote session became reachable'} '
      '(exitCode=$exitCode)$suffix',
    );
  }

  Future<CockpitRemoteSessionHandle>
  _buildPhysicalIosFallbackRemoteSessionHandle({
    required CockpitLaunchDevelopmentMachineSessionRequest request,
    required CockpitResolvedRemoteSessionEndpoint endpoint,
    required int hostPort,
    required CockpitRemoteSessionStatus status,
  }) async {
    final platformAppId = await _resolvePhysicalIosFallbackPlatformAppId(
      request: request,
    );
    final appId = platformAppId ?? status.sessionId;
    return CockpitRemoteSessionHandle.fromRemoteStatus(
      projectDir: request.projectDir,
      target: request.target,
      deviceId: request.deviceId,
      appId: appId,
      platformAppId: platformAppId,
      platformAppIdKnown: platformAppId != null,
      host: endpoint.publicHost,
      hostPort: hostPort,
      devicePort: request.sessionPort,
      status: status,
      launchedAt: _now(),
    );
  }

  Future<String?> _resolvePlatformAppId({
    required CockpitLaunchDevelopmentMachineSessionRequest request,
    required CockpitRemoteSessionStatus status,
  }) async {
    if (_isPhysicalIosDevice(request) &&
        status.platform.toLowerCase() == 'ios') {
      return _resolvePhysicalIosFallbackPlatformAppId(request: request);
    }
    try {
      return await _platformAppIdResolver(
        projectDir: request.projectDir,
        platform: request.platform,
        flavor: request.flavor,
      );
    } on Object {
      return null;
    }
  }

  Future<String?> _resolvePhysicalIosFallbackPlatformAppId({
    required CockpitLaunchDevelopmentMachineSessionRequest request,
  }) async {
    try {
      final appBundlePath = await _iosFallbackAppBundlePathResolver(
        projectDir: request.projectDir,
        flavor: request.flavor,
      );
      final bundleId = await _iosFallbackBundleIdResolver(
        appBundlePath: appBundlePath,
      );
      final normalized = bundleId.trim();
      return normalized.isEmpty ? null : normalized;
    } on Object {
      // Keep the ready remote session reusable even if bundle lookup fails.
      return null;
    }
  }

  bool _isPhysicalIosDevice(
    CockpitLaunchDevelopmentMachineSessionRequest request,
  ) {
    return request.platform == 'ios' &&
        !cockpitLooksLikeIosSimulatorDeviceId(request.deviceId);
  }

  _DevelopmentLaunchRecovery? _developmentRecovery({
    required CockpitLaunchDevelopmentMachineSessionRequest request,
    required Object error,
    required CockpitFlutterRunMachineClient machineClient,
  }) {
    final text = <String>[
      '$error',
      machineClient.recentDiagnosticSummary,
    ].where((value) => value.trim().isNotEmpty).join('\n');
    if (_isRecoverableResidentCompilerFailure(text)) {
      return _DevelopmentLaunchRecovery.retry;
    }
    if (request.platform == 'macos' &&
        _isRecoverableMacosSwiftModuleCacheFailure(text)) {
      return _DevelopmentLaunchRecovery.clean;
    }
    return null;
  }

  bool _isRecoverableResidentCompilerFailure(String output) {
    return output.contains(
          'A connection to the Resident Frontend Compiler could not be established',
        ) &&
        output.contains('A server is already running');
  }

  bool _isRecoverableMacosSwiftModuleCacheFailure(String output) {
    return output.contains('has been modified since the module file') ||
        output.contains('SwiftExplicitPrecompiledModules') ||
        output.contains('explicit-swift-module-map-file');
  }

  String _processOutputText(ProcessResult result) {
    final stderrText = '${result.stderr}'.trim();
    if (stderrText.isNotEmpty) {
      return stderrText;
    }
    return '${result.stdout}'.trim();
  }

  Duration _remaining(DateTime deadline) {
    final remaining = deadline.difference(_now());
    if (remaining <= Duration.zero) {
      throw TimeoutException(
        'Development session launch timed out before macOS cache recovery could start.',
      );
    }
    return remaining;
  }

  Duration _capTimeout(Duration value, Duration max) {
    return value < max ? value : max;
  }

  static Future<ProcessResult> _runRecoveryProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    required Duration timeout,
  }) {
    return cockpitRunProcessWithTimeout(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      timeout: timeout,
    );
  }
}

enum _DevelopmentLaunchRecovery { retry, clean }

final class CockpitResolvedRemoteSessionEndpoint {
  const CockpitResolvedRemoteSessionEndpoint({
    required this.bindHost,
    required this.publicHost,
  });

  final String bindHost;
  final String publicHost;
}

Future<String> _resolveIosPhysicalAppBundlePath({
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
