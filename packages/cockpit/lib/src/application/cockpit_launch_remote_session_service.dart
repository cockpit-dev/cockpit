import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

import '../foundation/cockpit_ids.dart';
import '../foundation/cockpit_permissions.dart';
import '../infrastructure/cockpit_sdk_environment.dart';
import '../platform/android/cockpit_android_device_readiness.dart';
import '../remote/cockpit_android_port_forwarder.dart';
import '../remote/cockpit_local_session_port_resolver.dart';
import '../session/cockpit_flutter_launch_configuration.dart';
import '../session/cockpit_remote_password_dart_define_file.dart';
import '../session/cockpit_remote_session_handle.dart';
import '../session/cockpit_remote_session_launch_options.dart';
import '../session/cockpit_remote_session_launcher.dart';
import 'cockpit_app_temp_store.dart';
import 'cockpit_application_service_exception.dart';
import 'cockpit_entrypoint_resolver.dart';
import 'cockpit_compact_json.dart';

final class CockpitLaunchRemoteSessionRequest {
  const CockpitLaunchRemoteSessionRequest({
    required this.projectDir,
    required this.platform,
    required this.deviceId,
    required this.sessionPort,
    this.target,
    this.flavor,
    this.launchTimeout = const Duration(seconds: 120),
    this.allowSessionPortFallback = true,
    this.authPassword = '',
    this.persistHandlePath,
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

  /// Operator-chosen password for the session's remote boundary. Empty means
  /// the boundary accepts unauthenticated requests.
  final String authPassword;
  final String? persistHandlePath;
  final CockpitFlutterLaunchConfiguration launchConfiguration;
}

final class CockpitLaunchRemoteSessionResult {
  const CockpitLaunchRemoteSessionResult({
    required this.sessionHandle,
    required this.health,
    this.persistedHandlePath,
  });

  final CockpitRemoteSessionHandle sessionHandle;
  final CockpitRemoteSessionStatus health;
  final String? persistedHandlePath;
}

final class CockpitLaunchRemoteSessionService {
  CockpitLaunchRemoteSessionService({
    CockpitRemoteSessionLauncher? launcher,
    CockpitRemoteSessionStatusReader? statusReader,
    CockpitSdkEnvironment? sdkEnvironment,
    CockpitFlutterExecutableVersionReader? flutterVersionForExecutableReader,
    CockpitEntrypointResolver? entrypointResolver,
    CockpitHostPortAllocator sessionPortAllocator = cockpitAllocateHostPort,
    CockpitHostPortAvailabilityChecker sessionPortAvailabilityChecker =
        cockpitIsHostPortAvailable,
    CockpitAppTempStore? appTempStore,
    CockpitTokenGenerator? tokenGenerator,
    CockpitPermissionHardener? authFilePermissionHardener,
    void Function(String value)? sensitiveValueRegistrar,
    void Function(String message)? diagnosticLogger,
  }) : _launcher = launcher ?? CockpitPlatformRemoteSessionLauncher(),
       _statusReader = statusReader ?? cockpitReadRemoteSessionStatus,
       _sdkEnvironment = sdkEnvironment ?? CockpitSdkEnvironment.current(),
       _flutterVersionForExecutableReader = flutterVersionForExecutableReader,
       _entrypointResolver = entrypointResolver ?? CockpitEntrypointResolver(),
       _sessionPortAllocator = sessionPortAllocator,
       _sessionPortAvailabilityChecker = sessionPortAvailabilityChecker,
       _appTempStore = appTempStore,
       _tokenGenerator = tokenGenerator ?? CockpitSecureTokenGenerator(),
       _authFilePermissionHardener = authFilePermissionHardener,
       _sensitiveValueRegistrar = sensitiveValueRegistrar,
       _diagnosticLogger = diagnosticLogger;

  final CockpitRemoteSessionLauncher _launcher;
  final CockpitRemoteSessionStatusReader _statusReader;
  final CockpitSdkEnvironment _sdkEnvironment;
  final CockpitFlutterExecutableVersionReader?
  _flutterVersionForExecutableReader;
  final CockpitEntrypointResolver _entrypointResolver;
  final CockpitHostPortAllocator _sessionPortAllocator;
  final CockpitHostPortAvailabilityChecker _sessionPortAvailabilityChecker;
  final CockpitAppTempStore? _appTempStore;
  final CockpitTokenGenerator _tokenGenerator;
  final CockpitPermissionHardener? _authFilePermissionHardener;
  final void Function(String value)? _sensitiveValueRegistrar;
  final void Function(String message)? _diagnosticLogger;

  Future<CockpitLaunchRemoteSessionResult> launch(
    CockpitLaunchRemoteSessionRequest request,
  ) async {
    final normalizedProjectDir = cockpitNormalizeProjectDir(request.projectDir);
    await request.launchConfiguration.validateProjectFiles(
      normalizedProjectDir,
    );
    final resolvedTarget = _entrypointResolver.resolve(
      projectDir: normalizedProjectDir,
      target: request.target,
    );
    final resolvedSessionPort = await cockpitResolveLocalSessionPort(
      platform: request.platform,
      deviceId: request.deviceId,
      preferredPort: request.sessionPort,
      allowFallbackAllocation: request.allowSessionPortFallback,
      portAllocator: _sessionPortAllocator,
      portAvailabilityChecker: _sessionPortAvailabilityChecker,
    );
    final flutterExecutable = _sdkEnvironment.flutterExecutable;
    final flutterVersion = await (_flutterVersionForExecutableReader == null
        ? cockpitReadFlutterVersion(
            flutterExecutable,
            workingDirectory: normalizedProjectDir,
          )
        : _flutterVersionForExecutableReader(flutterExecutable));
    final launchId = _tokenGenerator.nextResourceId('r');
    final password = request.authPassword;
    if (password.isNotEmpty) {
      _sensitiveValueRegistrar?.call(password);
    }
    final prepared = await _prepareAppEnvironment(
      platform: request.platform,
      hostPort: resolvedSessionPort,
      configuration: request.launchConfiguration,
    );
    CockpitRemotePasswordDartDefineFile? authFile;
    late final CockpitRemoteSessionHandle sessionHandle;
    try {
      if (password.isNotEmpty) {
        authFile = await CockpitRemotePasswordDartDefineFile.create(
          password,
          permissionHardener: _authFilePermissionHardener,
        );
      }
      sessionHandle = await _launcher.launch(
        CockpitRemoteSessionLaunchOptions(
          projectDir: normalizedProjectDir,
          target: resolvedTarget,
          platform: request.platform,
          deviceId: request.deviceId,
          sessionPort: resolvedSessionPort,
          flavor: request.flavor,
          launchTimeout: request.launchTimeout,
          flutterExecutable: flutterExecutable,
          flutterVersion: flutterVersion,
          launchId: launchId,
          password: password,
          passwordDartDefineFile: authFile?.path,
          launchConfiguration: request.launchConfiguration,
          appEnvironment: prepared.environment,
        ),
      );
    } on Object catch (error, stackTrace) {
      await _releaseAfterFailedLaunch(prepared.key);
      if (error is CockpitAndroidDeviceReadinessException) {
        Error.throwWithStackTrace(
          CockpitApplicationServiceException(
            code: error.code,
            message: error.message,
          ),
          stackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      await _deleteAuthFile(authFile);
    }
    final health = await _statusReader(
      sessionHandle.baseUri,
      password: sessionHandle.password,
    );
    final persistedHandlePath = await _persistHandleIfRequested(
      path: request.persistHandlePath,
      handle: sessionHandle,
    );

    return CockpitLaunchRemoteSessionResult(
      sessionHandle: sessionHandle,
      health: health,
      persistedHandlePath: persistedHandlePath,
    );
  }

  Future<_PreparedAppEnvironment> _prepareAppEnvironment({
    required String platform,
    required int hostPort,
    required CockpitFlutterLaunchConfiguration configuration,
  }) async {
    final environment = configuration.processEnvironment;
    final store = _appTempStore;
    if (store == null ||
        !_needsManagedRemoteAppTemp(
          platform: platform,
          hasUserEnvironment: environment != null,
        )) {
      return _PreparedAppEnvironment(environment: environment);
    }
    final key = cockpitRemoteAppTempKey(platform: platform, hostPort: hostPort);
    try {
      final path = await store.prepare(key);
      return _PreparedAppEnvironment(
        key: key,
        environment: configuration
            .withManagedEnvironment(cockpitAppTempEnvironment(path))
            .processEnvironment,
      );
    } on Object catch (error, stackTrace) {
      await _releaseAfterFailedLaunch(key);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _releaseAfterFailedLaunch(String? key) async {
    final store = _appTempStore;
    if (store == null || key == null) return;
    try {
      await store.release(key);
    } on Object catch (error) {
      _reportCleanupFailure(
        'Remote application temporary directory cleanup failed: $error',
      );
    }
  }

  Future<void> _deleteAuthFile(
    CockpitRemotePasswordDartDefineFile? file,
  ) async {
    if (file == null) return;
    try {
      await file.delete();
    } on Object catch (error) {
      _reportCleanupFailure(
        'Remote authentication define file cleanup failed: $error',
      );
    }
  }

  void _reportCleanupFailure(String message) {
    try {
      _diagnosticLogger?.call(message);
    } on Object {
      // Cleanup diagnostics must never replace the authoritative launch result.
    }
  }

  Future<String?> _persistHandleIfRequested({
    required String? path,
    required CockpitRemoteSessionHandle handle,
  }) async {
    if (path == null || path.isEmpty) {
      return null;
    }

    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(cockpitPrettyJsonText(handle.toJson()));
    return p.normalize(file.path);
  }
}

final class _PreparedAppEnvironment {
  const _PreparedAppEnvironment({this.key, this.environment});

  final String? key;
  final Map<String, String>? environment;
}

bool _needsManagedRemoteAppTemp({
  required String platform,
  required bool hasUserEnvironment,
}) => switch (platform.trim().toLowerCase()) {
  'linux' || 'windows' => true,
  // Environment-free macOS launches use LaunchServices and do not inherit
  // the worker process temporary directory. Custom environments launch the
  // bundle executable directly and therefore need stable app temp state.
  'macos' => hasUserEnvironment,
  _ => false,
};
