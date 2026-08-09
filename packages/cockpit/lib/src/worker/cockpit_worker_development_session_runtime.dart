import 'dart:async';
import 'dart:io';

import '../application/cockpit_app_handle.dart';
import '../application/cockpit_application_service_exception.dart';
import '../application/cockpit_entrypoint_resolver.dart';
import '../application/cockpit_launch_development_session_service.dart';
import '../application/cockpit_platform_app_stopper.dart';
import '../development/cockpit_development_session_handle.dart';
import '../development/cockpit_development_session_machine_launcher.dart';
import '../development/cockpit_development_session_status.dart';
import '../development/cockpit_development_session_supervisor.dart';
import '../development/cockpit_flutter_run_machine_client.dart';
import '../development/cockpit_vm_network_profiler.dart';
import '../foundation/cockpit_ids.dart';
import '../infrastructure/cockpit_sdk_environment.dart';
import '../remote/cockpit_android_port_forwarder.dart';
import '../remote/cockpit_remote_session_client.dart';
import '../session/cockpit_remote_session_launcher.dart';
import '../session/cockpit_flutter_launch_configuration.dart';

final class CockpitWorkerDevelopmentSessionSnapshot {
  const CockpitWorkerDevelopmentSessionSnapshot({
    required this.handle,
    required this.status,
  });

  final CockpitDevelopmentSessionHandle handle;
  final CockpitDevelopmentSessionStatus status;
}

final class CockpitWorkerDevelopmentSessionRuntime {
  CockpitWorkerDevelopmentSessionRuntime({
    CockpitDevelopmentSessionMachineLauncher? machineLauncher,
    CockpitAndroidPortForwarder portForwarder =
        const CockpitAndroidPortForwarder(),
    CockpitEntrypointResolver? entrypointResolver,
    CockpitSdkEnvironment? sdkEnvironment,
    CockpitFlutterExecutableVersionReader? flutterVersionReader,
    CockpitTokenGenerator? tokenGenerator,
    CockpitDevelopmentMachineDiagnosticLogger? logger,
    CockpitVmNetworkProfiler? networkProfiler,
    CockpitPlatformAppStopper? platformAppStopper,
    Future<CockpitFlutterRunMachineClient> Function(
      CockpitDevelopmentSessionHandle handle,
    )?
    machineClientAttacher,
    DateTime Function()? utcNow,
  }) : _portForwarder = portForwarder,
       _machineLauncher =
           machineLauncher ??
           CockpitDevelopmentSessionMachineLauncher(
             portForwarder: portForwarder,
             diagnosticLogger: logger,
           ),
       _entrypointResolver = entrypointResolver ?? CockpitEntrypointResolver(),
       _sdkEnvironment = sdkEnvironment ?? CockpitSdkEnvironment.current(),
       _flutterVersionReader = flutterVersionReader,
       _tokenGenerator = tokenGenerator ?? CockpitSecureTokenGenerator(),
       _logger = logger,
       _networkProfiler = networkProfiler,
       _platformAppStopper = platformAppStopper ?? CockpitPlatformAppStopper(),
       _machineClientAttacher = machineClientAttacher,
       _utcNow = utcNow ?? (() => DateTime.now().toUtc());

  final CockpitDevelopmentSessionMachineLauncher _machineLauncher;
  final CockpitAndroidPortForwarder _portForwarder;
  final CockpitEntrypointResolver _entrypointResolver;
  final CockpitSdkEnvironment _sdkEnvironment;
  final CockpitFlutterExecutableVersionReader? _flutterVersionReader;
  final CockpitTokenGenerator _tokenGenerator;
  final CockpitDevelopmentMachineDiagnosticLogger? _logger;
  final CockpitVmNetworkProfiler? _networkProfiler;
  final CockpitPlatformAppStopper _platformAppStopper;
  final Future<CockpitFlutterRunMachineClient> Function(
    CockpitDevelopmentSessionHandle handle,
  )?
  _machineClientAttacher;
  final DateTime Function() _utcNow;
  final Map<String, CockpitDevelopmentSessionSupervisor> _sessions =
      <String, CockpitDevelopmentSessionSupervisor>{};
  final Map<String, Future<CockpitDevelopmentSessionSupervisor>> _recoveries =
      <String, Future<CockpitDevelopmentSessionSupervisor>>{};
  final Set<String> _reloadsNeedingRelaunch = <String>{};

  Future<CockpitLaunchDevelopmentSessionResult> launch(
    CockpitLaunchDevelopmentSessionRequest request,
  ) async {
    final projectDir = cockpitNormalizeProjectDir(request.projectDir);
    final target = _entrypointResolver.resolve(
      projectDir: projectDir,
      target: request.target,
    );
    final developmentSessionId = 'ds-${_tokenGenerator.nextResourceIdToken()}';
    final flutterExecutable = _sdkEnvironment.flutterExecutable;
    final flutterVersion = await (_flutterVersionReader == null
        ? cockpitReadFlutterVersion(
            flutterExecutable,
            workingDirectory: projectDir,
          )
        : _flutterVersionReader(flutterExecutable));
    final hostPort = request.platform == 'android'
        ? await _portForwarder.ensureForwarded(
            deviceId: request.deviceId,
            preferredHostPort: request.sessionPort,
            devicePort: request.sessionPort,
          )
        : request.sessionPort;
    final machineRequest = CockpitLaunchDevelopmentMachineSessionRequest(
      projectDir: projectDir,
      target: target,
      flavor: request.flavor,
      platform: request.platform,
      deviceId: request.deviceId,
      sessionPort: request.sessionPort,
      hostPort: hostPort,
      launchTimeout: request.launchTimeout,
      flutterExecutable: flutterExecutable,
      flutterVersion: flutterVersion,
      launchId: developmentSessionId,
      launchConfiguration: request.launchConfiguration,
    );
    final endpoint = await _machineLauncher.resolveRemoteSessionEndpoint(
      machineRequest,
    );
    final supervisor = CockpitDevelopmentSessionSupervisor(
      initialHandle: CockpitDevelopmentSessionHandle(
        developmentSessionId: developmentSessionId,
        platform: request.platform,
        deviceId: request.deviceId,
        projectDir: projectDir,
        target: target,
        appId: '',
        appBaseUrl: Uri(
          scheme: 'http',
          host: endpoint.publicHost,
          port: hostPort,
        ).toString(),
        supervisorBaseUrl: 'cockpit-worker://development/$developmentSessionId',
        flavor: request.flavor,
        flutterVersion: flutterVersion,
        bindHost: endpoint.bindHost,
        reloadRecoverable: request.launchConfiguration.isEmpty,
        launchedAt: _utcNow(),
        reloadGeneration: 0,
      ),
      machineClient: null,
      remoteReachabilityProbe: (baseUri) => _probe(
        platform: request.platform,
        deviceId: request.deviceId,
        hostPort: hostPort,
        devicePort: request.sessionPort,
        baseUri: baseUri,
        readiness: false,
      ),
      remoteControlReadinessProbe: (baseUri) => _probe(
        platform: request.platform,
        deviceId: request.deviceId,
        hostPort: hostPort,
        devicePort: request.sessionPort,
        baseUri: baseUri,
        readiness: true,
      ),
      logger: _logger == null
          ? null
          : (message) async {
              await _logger(message);
            },
      vmServiceObserver: (uri) {
        final profiler = _networkProfiler;
        if (profiler == null) return;
        unawaited(
          profiler
              .enable(sessionId: developmentSessionId, vmServiceUri: uri)
              .catchError((Object error) async {
                await _logger?.call('VM network profiling unavailable: $error');
              }),
        );
      },
      bindControlPlane: false,
      settleTimeout: request.launchTimeout,
    );
    final deadline = _utcNow().add(request.launchTimeout);
    await supervisor.start();
    try {
      final launched = await _machineLauncher.launchWithLifecycle(
        machineRequest,
        endpoint: endpoint,
        onMachineClientStarted: supervisor.bindMachineClient,
      );
      await supervisor.bindRemoteSession(launched.remoteSessionHandle);
      await supervisor.waitForState(
        CockpitDevelopmentSessionState.ready,
        timeout: _remaining(deadline),
      );
      final snapshot = await _snapshot(supervisor);
      _sessions[developmentSessionId] = supervisor;
      _reloadsNeedingRelaunch.remove(developmentSessionId);
      return CockpitLaunchDevelopmentSessionResult(
        sessionHandle: snapshot.handle,
        status: snapshot.status,
        app: CockpitAppHandle.fromDevelopmentSession(snapshot.handle),
      );
    } on Object catch (error, stackTrace) {
      supervisor.reportStartupFailure(error);
      await supervisor.dispose();
      final mapped = _developmentLaunchFailure(error);
      if (identical(mapped, error)) rethrow;
      Error.throwWithStackTrace(mapped, stackTrace);
    }
  }

  Future<CockpitWorkerDevelopmentSessionSnapshot> query(
    CockpitDevelopmentSessionHandle handle,
  ) async => _snapshot(await _require(handle));

  Future<CockpitWorkerDevelopmentSessionSnapshot> reload(
    CockpitDevelopmentSessionHandle handle,
    CockpitDevelopmentReloadMode mode,
  ) async {
    final supervisor = await _require(handle);
    if (_reloadsNeedingRelaunch.contains(handle.developmentSessionId)) {
      throw CockpitApplicationServiceException(
        code: 'reloadNeedsRelaunch',
        message:
            'Cockpit reattached to this app after its worker restarted, but '
            'the original custom launch values were intentionally not '
            'persisted. Relaunch with `cockpit dev start` and the original '
            'launch options before reloading or restarting.',
        details: <String, Object?>{'mode': mode.jsonValue},
      );
    }
    try {
      await supervisor.reload(mode);
    } on CockpitApplicationServiceException {
      rethrow;
    } on Object catch (error) {
      final status = await supervisor.currentStatus();
      final restart = mode == CockpitDevelopmentReloadMode.hotRestart;
      throw CockpitApplicationServiceException(
        code: restart ? 'hotRestartFailed' : 'hotReloadFailed',
        message:
            status.lastError ??
            (restart ? 'Hot restart failed.' : 'Hot reload failed.'),
        details: <String, Object?>{
          'state': status.state.jsonValue,
          'cause': error.runtimeType.toString(),
        },
      );
    }
    return _snapshot(supervisor);
  }

  Future<CockpitWorkerDevelopmentSessionSnapshot> stop(
    CockpitDevelopmentSessionHandle handle,
  ) async {
    final supervisor = await _require(handle);
    await supervisor.stop();
    await _stopPlatformApp(await supervisor.currentHandle());
    _sessions.remove(handle.developmentSessionId);
    _reloadsNeedingRelaunch.remove(handle.developmentSessionId);
    return _snapshot(supervisor);
  }

  Future<void> forceStop(CockpitDevelopmentSessionHandle handle) async {
    final supervisor = await _require(handle);
    _sessions.remove(handle.developmentSessionId);
    _reloadsNeedingRelaunch.remove(handle.developmentSessionId);
    await supervisor.stop();
    await _stopPlatformApp(await supervisor.currentHandle());
  }

  Future<void> _stopPlatformApp(CockpitDevelopmentSessionHandle handle) async {
    if (handle.platform == 'web') {
      return;
    }
    try {
      await _platformAppStopper
          .stop(CockpitAppHandle.fromDevelopmentSession(handle))
          .timeout(const Duration(seconds: 10));
    } on Object catch (error) {
      await _logger?.call('Development platform stop failed: $error');
    }
  }

  Future<void> dispose() async {
    final supervisors = _sessions.values.toList(growable: false);
    _sessions.clear();
    _recoveries.clear();
    _reloadsNeedingRelaunch.clear();
    await Future.wait<void>(
      supervisors.map((supervisor) async {
        try {
          await supervisor.detach();
        } on Object catch (error) {
          await _logger?.call('Development session detach failed: $error');
        }
      }),
    );
  }

  Future<CockpitDevelopmentSessionSupervisor> _require(
    CockpitDevelopmentSessionHandle handle,
  ) async {
    final existing = _sessions[handle.developmentSessionId];
    if (existing != null) {
      return existing;
    }
    final pending = _recoveries[handle.developmentSessionId];
    if (pending != null) {
      return pending;
    }
    final recovery = _recover(handle);
    _recoveries[handle.developmentSessionId] = recovery;
    try {
      return await recovery;
    } finally {
      _recoveries.remove(handle.developmentSessionId);
    }
  }

  Future<CockpitDevelopmentSessionSupervisor> _recover(
    CockpitDevelopmentSessionHandle handle,
  ) async {
    if (handle.remoteSessionHandle == null) {
      throw const CockpitApplicationServiceException(
        code: 'developmentSessionRecoveryUnavailable',
        message: 'Development session has no remote runtime identity.',
      );
    }
    final supervisor = CockpitDevelopmentSessionSupervisor(
      initialHandle: handle,
      machineClient: null,
      machineClientConnector: () => _attachMachineClient(handle),
      remoteReachabilityProbe: (baseUri) =>
          _probeHandle(handle, baseUri: baseUri, readiness: false),
      remoteControlReadinessProbe: (baseUri) =>
          _probeHandle(handle, baseUri: baseUri, readiness: true),
      logger: _logger == null
          ? null
          : (message) async {
              await _logger(message);
            },
      vmServiceObserver: (uri) {
        final profiler = _networkProfiler;
        if (profiler == null) return;
        unawaited(
          profiler
              .enable(sessionId: handle.developmentSessionId, vmServiceUri: uri)
              .catchError((Object error) async {
                await _logger?.call('VM network profiling unavailable: $error');
              }),
        );
      },
      bindControlPlane: false,
      startupSettleTimeout: const Duration(seconds: 5),
    );
    _sessions[handle.developmentSessionId] = supervisor;
    if (handle.reloadRecoverable) {
      _reloadsNeedingRelaunch.remove(handle.developmentSessionId);
    } else {
      _reloadsNeedingRelaunch.add(handle.developmentSessionId);
    }
    try {
      await supervisor.start();
      await supervisor.waitForStartupRecovery();
      return supervisor;
    } on Object {
      _sessions.remove(handle.developmentSessionId);
      _reloadsNeedingRelaunch.remove(handle.developmentSessionId);
      await supervisor.dispose();
      rethrow;
    }
  }

  Future<CockpitFlutterRunMachineClient> _attachMachineClient(
    CockpitDevelopmentSessionHandle handle,
  ) async {
    final injected = _machineClientAttacher;
    late final CockpitFlutterRunMachineClient client;
    if (injected != null) {
      client = await injected(handle);
    } else {
      final remote = handle.remoteSessionHandle!;
      final platform = handle.platform.trim().toLowerCase();
      final usePlatformAppId = platform == 'android' || platform == 'ios';
      final debugUrl = usePlatformAppId || handle.vmServiceUri == null
          ? null
          : cockpitFlutterAttachDebugUri(handle.vmServiceUri!);
      final platformAppId = usePlatformAppId
          ? remote.effectivePlatformAppId
          : null;
      if (debugUrl == null && platformAppId == null) {
        throw const CockpitApplicationServiceException(
          code: 'developmentSessionRecoveryUnavailable',
          message: 'Development session has no safe Flutter attach identity.',
        );
      }
      final extraArgs = await _recoveryFlutterArguments(handle);
      client = await CockpitFlutterRunMachineClient.attach(
        projectDir: handle.projectDir,
        target: handle.target,
        deviceId: handle.deviceId,
        platformAppId: platformAppId,
        debugUrl: debugUrl,
        flavor: handle.flavor,
        flutterExecutable: _sdkEnvironment.flutterExecutable,
        extraArgs: extraArgs,
      );
    }
    try {
      await client.waitForAppId();
      await client.waitForAppStarted();
      return client;
    } on Object {
      await client.dispose();
      rethrow;
    }
  }

  Future<List<String>> _recoveryFlutterArguments(
    CockpitDevelopmentSessionHandle handle,
  ) async {
    if (!handle.reloadRecoverable) {
      return const <String>[];
    }
    final remote = handle.remoteSessionHandle!;
    final flutterVersion =
        handle.flutterVersion ??
        await (_flutterVersionReader == null
            ? cockpitReadFlutterVersion(
                _sdkEnvironment.flutterExecutable,
                workingDirectory: handle.projectDir,
              )
            : _flutterVersionReader(_sdkEnvironment.flutterExecutable));
    final bindHost =
        handle.bindHost ?? cockpitRemoteBindHostForPlatform(handle.platform);
    final disableIpv6UnsafeObservers =
        handle.platform == 'ios' && bindHost == '::';
    return <String>[
      ...cockpitBuildRemoteControlDartDefineArguments(
        host: bindHost,
        port: remote.devicePort,
        flutterVersion: flutterVersion,
        launchId: handle.developmentSessionId,
        disableHttpNetworkObserver: disableIpv6UnsafeObservers,
        disableRuntimeObserver: disableIpv6UnsafeObservers,
      ),
    ];
  }

  Future<bool> _probeHandle(
    CockpitDevelopmentSessionHandle handle, {
    required Uri baseUri,
    required bool readiness,
  }) {
    final remote = handle.remoteSessionHandle!;
    return _probe(
      platform: handle.platform,
      deviceId: handle.deviceId,
      hostPort: remote.hostPort,
      devicePort: remote.devicePort,
      baseUri: baseUri,
      readiness: readiness,
    );
  }

  Future<CockpitWorkerDevelopmentSessionSnapshot> _snapshot(
    CockpitDevelopmentSessionSupervisor supervisor,
  ) async {
    for (var attempt = 0; attempt < 3; attempt += 1) {
      final handle = await supervisor.currentHandle();
      final status = await supervisor.currentStatus();
      if (handle.reloadGeneration == status.reloadGeneration) {
        return CockpitWorkerDevelopmentSessionSnapshot(
          handle: handle,
          status: status,
        );
      }
    }
    throw StateError('Development session snapshot did not stabilize.');
  }

  Future<bool> _probe({
    required String platform,
    required String deviceId,
    required int hostPort,
    required int devicePort,
    required Uri baseUri,
    required bool readiness,
  }) async {
    if (platform == 'android') {
      await _portForwarder.ensureForwarded(
        deviceId: deviceId,
        preferredHostPort: hostPort,
        devicePort: devicePort,
      );
    }
    try {
      final client = CockpitRemoteSessionClient(baseUri: baseUri);
      return readiness ? await client.ready() : await client.ping();
    } on Object {
      return false;
    }
  }

  Duration _remaining(DateTime deadline) {
    final remaining = deadline.difference(_utcNow());
    if (remaining <= Duration.zero) {
      throw TimeoutException('Development session launch timed out.');
    }
    return remaining;
  }

  Object _developmentLaunchFailure(Object error) {
    if (error is CockpitApplicationServiceException ||
        error is CockpitDevelopmentSessionFallbackException ||
        error is TimeoutException) {
      return error;
    }
    if (error is StateError ||
        error is ProcessException ||
        error is FileSystemException ||
        error is CockpitFlutterRunMachineRequestException) {
      return CockpitApplicationServiceException(
        code: 'flutterLaunchFailed',
        message: _developmentLaunchFailureMessage(error),
        details: <String, Object?>{'cause': error.runtimeType.toString()},
      );
    }
    return error;
  }

  String _developmentLaunchFailureMessage(Object error) {
    if (error is StateError) return error.message.toString();
    if (error is CockpitFlutterRunMachineRequestException) {
      return error.message;
    }
    if (error is FileSystemException) {
      final path = error.path;
      return path == null ? error.message : '${error.message}: $path';
    }
    return '$error';
  }
}
