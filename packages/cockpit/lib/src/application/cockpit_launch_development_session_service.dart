import 'dart:io';

import 'package:path/path.dart' as p;

import '../development/cockpit_development_session_handle.dart';
import '../development/cockpit_development_session_status.dart';
import '../remote/cockpit_android_port_forwarder.dart';
import '../remote/cockpit_local_session_port_resolver.dart';
import '../session/cockpit_flutter_launch_configuration.dart';
import 'cockpit_app_handle.dart';
import 'cockpit_compact_json.dart';
import 'cockpit_entrypoint_resolver.dart';

typedef CockpitDevelopmentSessionLauncher =
    Future<CockpitDevelopmentSessionBootstrap> Function(
      CockpitLaunchDevelopmentSessionRequest request,
    );

final class CockpitLaunchDevelopmentSessionRequest {
  const CockpitLaunchDevelopmentSessionRequest({
    required this.projectDir,
    required this.platform,
    required this.deviceId,
    required this.sessionPort,
    this.target,
    this.flavor,
    this.launchTimeout = const Duration(seconds: 120),
    this.allowSessionPortFallback = true,
    this.persistHandlePath,
    this.persistAppHandlePath,
    this.launchConfiguration = CockpitFlutterLaunchConfiguration.empty,
  });

  final String projectDir;
  final String? target;
  final String? flavor;
  final String platform;
  final String deviceId;
  final int sessionPort;
  final Duration launchTimeout;
  final bool allowSessionPortFallback;
  final String? persistHandlePath;
  final String? persistAppHandlePath;
  final CockpitFlutterLaunchConfiguration launchConfiguration;
}

final class CockpitDevelopmentSessionBootstrap {
  const CockpitDevelopmentSessionBootstrap({
    required this.sessionHandle,
    required this.status,
    this.supervisorLogPath,
  });

  final CockpitDevelopmentSessionHandle sessionHandle;
  final CockpitDevelopmentSessionStatus status;
  final String? supervisorLogPath;
}

final class CockpitLaunchDevelopmentSessionResult {
  CockpitLaunchDevelopmentSessionResult({
    required this.sessionHandle,
    required this.status,
    CockpitAppHandle? app,
    this.persistedHandlePath,
    this.appJsonPath,
    this.supervisorLogPath,
  }) : app =
           app ??
           CockpitAppHandle.fromDevelopmentSession(
             sessionHandle,
             supervisorLogPath: supervisorLogPath,
           );

  final CockpitDevelopmentSessionHandle sessionHandle;
  final CockpitDevelopmentSessionStatus status;
  final CockpitAppHandle app;
  final String? persistedHandlePath;
  final String? appJsonPath;
  final String? supervisorLogPath;
}

final class CockpitLaunchDevelopmentSessionService {
  CockpitLaunchDevelopmentSessionService({
    CockpitDevelopmentSessionLauncher? launcher,
    CockpitEntrypointResolver? entrypointResolver,
    CockpitHostPortAllocator sessionPortAllocator = cockpitAllocateHostPort,
    CockpitHostPortAvailabilityChecker sessionPortAvailabilityChecker =
        cockpitIsHostPortAvailable,
  }) : _launcher = launcher ?? _workerRoutingRequired,
       _entrypointResolver = entrypointResolver ?? CockpitEntrypointResolver(),
       _sessionPortAllocator = sessionPortAllocator,
       _sessionPortAvailabilityChecker = sessionPortAvailabilityChecker;

  final CockpitDevelopmentSessionLauncher _launcher;
  final CockpitEntrypointResolver _entrypointResolver;
  final CockpitHostPortAllocator _sessionPortAllocator;
  final CockpitHostPortAvailabilityChecker _sessionPortAvailabilityChecker;

  Future<CockpitLaunchDevelopmentSessionResult> launch(
    CockpitLaunchDevelopmentSessionRequest request,
  ) async {
    final normalizedProjectDir = cockpitNormalizeProjectDir(request.projectDir);
    await request.launchConfiguration.validateProjectFiles(
      normalizedProjectDir,
    );
    final resolvedSessionPort = await cockpitResolveLocalSessionPort(
      platform: request.platform,
      deviceId: request.deviceId,
      preferredPort: request.sessionPort,
      allowFallbackAllocation: request.allowSessionPortFallback,
      portAllocator: _sessionPortAllocator,
      portAvailabilityChecker: _sessionPortAvailabilityChecker,
    );
    final resolvedRequest = CockpitLaunchDevelopmentSessionRequest(
      projectDir: normalizedProjectDir,
      target: _entrypointResolver.resolve(
        projectDir: normalizedProjectDir,
        target: request.target,
      ),
      flavor: request.flavor,
      platform: request.platform,
      deviceId: request.deviceId,
      sessionPort: resolvedSessionPort,
      launchTimeout: request.launchTimeout,
      allowSessionPortFallback: request.allowSessionPortFallback,
      persistHandlePath: request.persistHandlePath,
      persistAppHandlePath: request.persistAppHandlePath,
      launchConfiguration: request.launchConfiguration,
    );
    final bootstrap = await _launcher(resolvedRequest);
    final persistedHandlePath = await _persistHandleIfRequested(
      path: resolvedRequest.persistHandlePath,
      handle: bootstrap.sessionHandle,
    );
    final app = CockpitAppHandle.fromDevelopmentSession(
      bootstrap.sessionHandle,
      supervisorLogPath: bootstrap.supervisorLogPath,
    );
    final appJsonPath = await _persistAppIfRequested(
      path: resolvedRequest.persistAppHandlePath,
      app: app,
    );

    return CockpitLaunchDevelopmentSessionResult(
      sessionHandle: bootstrap.sessionHandle,
      status: bootstrap.status,
      app: app,
      persistedHandlePath: persistedHandlePath,
      appJsonPath: appJsonPath,
      supervisorLogPath: bootstrap.supervisorLogPath,
    );
  }

  Future<String?> _persistHandleIfRequested({
    required String? path,
    required CockpitDevelopmentSessionHandle handle,
  }) async {
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(cockpitPrettyJsonText(handle.toJson()));
    return p.normalize(file.path);
  }

  Future<String?> _persistAppIfRequested({
    required String? path,
    required CockpitAppHandle app,
  }) async {
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(cockpitPrettyJsonText(app.toJson()));
    return p.normalize(file.path);
  }
}

Future<CockpitDevelopmentSessionBootstrap> _workerRoutingRequired(
  CockpitLaunchDevelopmentSessionRequest _,
) => throw UnsupportedError(
  'Development sessions must be launched through the workspace worker.',
);
