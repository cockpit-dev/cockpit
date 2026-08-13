import 'dart:async';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../application/cockpit_app_handle.dart';
import '../application/cockpit_application_service_exception.dart';
import '../application/cockpit_stop_app_service.dart';
import '../adapters/cockpit_automation_adapter.dart';
import '../adapters/cockpit_capture_adapter.dart';
import '../adapters/cockpit_recording_adapter.dart';
import '../development/cockpit_development_probe.dart';
import '../development/cockpit_development_session_handle.dart';
import '../foundation/cockpit_ids.dart';
import '../remote/cockpit_remote_automation_adapter.dart';
import '../remote/cockpit_remote_capture_adapter.dart';
import '../remote/cockpit_remote_recording_adapter.dart';
import '../remote/cockpit_remote_session_client.dart';
import '../session/cockpit_remote_session_handle.dart';
import '../targets/cockpit_target_handle.dart';
import '../test/cockpit_test_action_lowerer.dart';
import '../test/cockpit_test_safety_policy.dart';
import '../system_control/cockpit_system_control_action_service.dart';
import '../system_control/cockpit_system_control_service.dart';
import '../system_control/cockpit_system_test_automation_adapter.dart';
import '../system_control/cockpit_system_test_evidence_adapters.dart';
import '../system_control/cockpit_system_test_target.dart';
import 'cockpit_case_run_adapter.dart';
import 'cockpit_worker_artifact_registry.dart';
import 'cockpit_worker_document_index.dart';
import 'cockpit_worker_resource_identity.dart';
import 'cockpit_worker_run_ownership_authority.dart';
import 'cockpit_worker_runtime_state_store.dart';
import 'cockpit_worker_value_reader.dart';
import 'cockpit_workspace_application_adapters.dart';

export 'cockpit_worker_runtime_state_store.dart'
    show
        CockpitFileWorkerRuntimeStateStore,
        CockpitInMemoryWorkerRuntimeStateStore,
        CockpitWorkerRuntimeStateStore;

abstract interface class CockpitWorkerTargetResolver {
  Future<CockpitWorkerTargetBinding> requireTarget({
    required String workspaceId,
    required String targetId,
  });
}

typedef CockpitWorkerDevelopmentSessionAborter =
    Future<void> Function(CockpitDevelopmentSessionHandle handle);
typedef CockpitWorkerDevelopmentSessionRestarter =
    Future<CockpitDevelopmentSessionHandle> Function(
      CockpitDevelopmentSessionHandle handle,
    );

abstract interface class CockpitWorkerTargetRegistrar {
  Future<String> registerTarget(CockpitWorkerTargetRegistration registration);
}

final class CockpitWorkerTargetRegistration {
  const CockpitWorkerTargetRegistration({
    required this.workspaceId,
    required this.platform,
    required this.deviceId,
    this.entrypoint,
    this.entrypointSha256,
    this.flavor,
    this.appId,
    this.wdaUrl,
    this.cdpUrl,
    this.targetKind = CockpitTargetKind.flutterApp,
    this.mode = CockpitAppMode.development,
    this.environment = CockpitTestTargetEnvironment.unknown,
  });

  final String workspaceId;
  final String platform;
  final String deviceId;
  final String? entrypoint;
  final String? entrypointSha256;
  final String? flavor;
  final String? appId;
  final String? wdaUrl;
  final String? cdpUrl;
  final CockpitTargetKind targetKind;
  final CockpitAppMode mode;
  final CockpitTestTargetEnvironment environment;

  bool get usesSystemControl =>
      targetKind != CockpitTargetKind.flutterApp ||
      (entrypoint == null && appId != null);
}

final class CockpitWorkerTargetBinding {
  const CockpitWorkerTargetBinding({
    required this.targetId,
    required this.deviceResourceId,
    required this.projectDir,
    required this.launchEntrypoint,
    required this.registration,
    this.handle,
  });

  final String targetId;
  final String deviceResourceId;
  final String projectDir;
  final String? launchEntrypoint;
  final CockpitWorkerTargetRegistration registration;
  final CockpitTargetHandle? handle;
}

final class CockpitWorkerAppBinding {
  const CockpitWorkerAppBinding({
    required this.appId,
    required this.targetId,
    required this.handle,
    required this.updatedAt,
  });

  final String appId;
  final String targetId;
  final CockpitAppHandle handle;
  final DateTime updatedAt;
}

final class CockpitWorkerSessionBinding {
  const CockpitWorkerSessionBinding({
    required this.sessionId,
    required this.appId,
    required this.targetId,
    required this.deviceResourceId,
    required this.resourceId,
    required this.remoteHandle,
    required this.environment,
    required this.updatedAt,
    this.developmentHandle,
  });

  final String sessionId;
  final String appId;
  final String targetId;
  final String deviceResourceId;
  final String resourceId;
  final CockpitRemoteSessionHandle remoteHandle;
  final CockpitDevelopmentSessionHandle? developmentHandle;
  final CockpitTestTargetEnvironment environment;
  final DateTime updatedAt;
}

final class CockpitWorkerRecordingBinding {
  const CockpitWorkerRecordingBinding({
    required this.recordingId,
    required this.sessionId,
    required this.appId,
    required this.resourceId,
    required this.createdAt,
  });

  final String recordingId;
  final String sessionId;
  final String appId;
  final String resourceId;
  final DateTime createdAt;
}

final class CockpitWorkerRuntimeRegistry
    implements
        CockpitWorkerTargetResolver,
        CockpitWorkerTargetRegistrar,
        CockpitWorkerSessionProvider,
        CockpitWorkerApplicationResourceResolver,
        CockpitWorkerArtifactRegistry {
  static const int maximumTargets = 10000;
  static const int maximumApps = 10000;
  static const int maximumSessions = 10000;
  static const int maximumRecordings = 10000;
  static const int maximumArtifacts = 100000;
  static const int maximumRetainedProbes = 10000;
  static const int maximumTransientSnapshots = 10000;

  CockpitWorkerRuntimeRegistry({
    required this.workspaceId,
    required this.workspaceRoot,
    required this.stateRoot,
    required CockpitWorkerRuntimeStateStore stateStore,
    CockpitStopAppService? stopAppService,
    CockpitWorkerDevelopmentSessionAborter? developmentSessionAborter,
    CockpitWorkerDevelopmentSessionRestarter? developmentSessionRestarter,
    CockpitWorkerRunOwnershipAuthority? runOwnershipAuthority,
    CockpitSystemControlService? systemControlService,
    CockpitSystemControlActionService? systemActionService,
    CockpitTokenGenerator? tokenGenerator,
    DateTime Function()? utcNow,
  }) : _stateStore = stateStore,
       _stopAppService = stopAppService ?? CockpitStopAppService(),
       _developmentSessionAborter = developmentSessionAborter,
       _developmentSessionRestarter = developmentSessionRestarter,
       _runOwnershipAuthority =
           runOwnershipAuthority ??
           const CockpitDenyAllWorkerRunOwnershipAuthority(),
       _tokenGenerator = tokenGenerator ?? CockpitSecureTokenGenerator(),
       _utcNow = utcNow ?? (() => DateTime.now().toUtc()) {
    _systemControlService =
        systemControlService ?? CockpitSystemControlService();
    _systemActionService =
        systemActionService ??
        CockpitSystemControlActionService(
          systemControlService: _systemControlService,
        );
    workerId(workspaceId, r'$.workspaceId');
    workerString(workspaceRoot, r'$.workspaceRoot', maximum: 32768);
    workerString(stateRoot, r'$.stateRoot', maximum: 32768);
    if (!p.isAbsolute(stateRoot) || p.normalize(stateRoot) != stateRoot) {
      throw const FormatException(
        'Worker runtime state root must be absolute and normalized.',
      );
    }
  }

  final String workspaceId;
  final String workspaceRoot;
  final String stateRoot;
  final CockpitWorkerRuntimeStateStore _stateStore;
  final CockpitStopAppService _stopAppService;
  final CockpitWorkerDevelopmentSessionAborter? _developmentSessionAborter;
  final CockpitWorkerDevelopmentSessionRestarter? _developmentSessionRestarter;
  final CockpitWorkerRunOwnershipAuthority _runOwnershipAuthority;
  final CockpitTokenGenerator _tokenGenerator;
  final DateTime Function() _utcNow;
  late final CockpitSystemControlService _systemControlService;
  late final CockpitSystemControlActionService _systemActionService;

  final Map<String, CockpitWorkerTargetBinding> _targets =
      <String, CockpitWorkerTargetBinding>{};
  final Map<String, CockpitWorkerAppBinding> _apps =
      <String, CockpitWorkerAppBinding>{};
  final Map<String, CockpitWorkerSessionBinding> _sessions =
      <String, CockpitWorkerSessionBinding>{};
  final Map<String, CockpitWorkerRecordingBinding> _recordings =
      <String, CockpitWorkerRecordingBinding>{};
  final Map<String, CockpitWorkerArtifactBinding> _artifacts =
      <String, CockpitWorkerArtifactBinding>{};
  final Map<String, _ProbeBinding> _probes = <String, _ProbeBinding>{};
  final Set<String> _authorizedRunIds = <String>{};
  // Snapshot refs are process-lifetime capabilities, cleared on owner teardown
  // or worker restart and intentionally excluded from persisted state.
  final Map<String, _SnapshotBinding> _snapshots = <String, _SnapshotBinding>{};
  final Map<(String, String), String> _snapshotRefsByIdentity =
      <(String, String), String>{};
  Future<void> _tail = Future<void>.value();
  var _loaded = false;

  @override
  Future<String> registerTarget(CockpitWorkerTargetRegistration registration) =>
      _locked(() async {
        await _ensureLoaded();
        _validateRegistration(registration);
        await _validateTargetEntrypointCurrent(registration);
        final project = _resolveTargetProject(
          registration,
          requireProject: true,
        );
        final targetId = _newId('tg');
        _targets[targetId] = CockpitWorkerTargetBinding(
          targetId: targetId,
          deviceResourceId: cockpitCanonicalDeviceResourceId(
            platform: registration.platform,
            deviceId: registration.deviceId,
          ),
          projectDir: project.projectDir,
          launchEntrypoint: project.launchEntrypoint,
          registration: registration,
        );
        await _persist();
        return targetId;
      });

  @override
  Future<CockpitWorkerTargetBinding> requireTarget({
    required String workspaceId,
    required String targetId,
  }) => _locked(() async {
    await _ensureLoaded();
    _requireWorkspace(workspaceId);
    workerId(targetId, r'$.targetId');
    final target =
        _targets[targetId] ?? (throw _unknownReference('target', targetId));
    await _validateTargetEntrypointCurrent(target.registration);
    return target;
  });

  Future<List<CockpitWorkerTargetBinding>> listTargets() => _locked(() async {
    await _ensureLoaded();
    final result = _targets.values.toList(growable: false)
      ..sort((left, right) => left.targetId.compareTo(right.targetId));
    return List<CockpitWorkerTargetBinding>.unmodifiable(result);
  });

  Future<CockpitWorkerTargetBinding> readTarget(String targetId) =>
      _locked(() async {
        await _ensureLoaded();
        workerId(targetId, r'$.targetId');
        return _targets[targetId] ??
            (throw _unknownReference('target', targetId));
      });

  Future<Map<String, String>> latestSessionIdsByTarget() => _locked(() async {
    await _ensureLoaded();
    final latest = <String, CockpitWorkerSessionBinding>{};
    for (final session in _sessions.values) {
      final current = latest[session.targetId];
      if (current == null || session.updatedAt.isAfter(current.updatedAt)) {
        latest[session.targetId] = session;
      }
    }
    return Map<String, String>.unmodifiable(<String, String>{
      for (final entry in latest.entries) entry.key: entry.value.sessionId,
    });
  });

  @override
  Future<CockpitWorkerApplicationResourcePlan> resolveApplicationResourcePlan({
    required String kind,
    required Map<String, Object?> input,
  }) => _locked(() async {
    await _ensureLoaded();
    if (kind == 'system.action') {
      final targetId = _systemActionTargetId(input);
      final target =
          _targets[targetId] ?? (throw _unknownReference('target', targetId));
      await _validateTargetEntrypointCurrent(target.registration);
      return CockpitWorkerApplicationResourcePlan(
        primaryResourceId: target.deviceResourceId,
        requiresPort: false,
      );
    }
    if (_targetResourceKinds.contains(kind)) {
      final targetId = workerId(input['targetId'], r'$.input.targetId');
      final target =
          _targets[targetId] ?? (throw _unknownReference('target', targetId));
      await _validateTargetEntrypointCurrent(target.registration);
      return CockpitWorkerApplicationResourcePlan(
        primaryResourceId: target.deviceResourceId,
        requiresPort:
            kind != 'target.launch' || !target.registration.usesSystemControl,
      );
    }
    if (kind == 'app.stop' || kind == 'app.get') {
      final appId = workerId(input['appId'], r'$.input.appId');
      final sessions = _sessions.values
          .where((binding) => binding.appId == appId)
          .toList(growable: false);
      if (sessions.length != 1) throw _unknownReference('app session', appId);
      return _sessionResourcePlan(sessions.single);
    }
    if (_sessionResourceKinds.contains(kind)) {
      final sessionId = workerId(input['sessionId'], r'$.input.sessionId');
      return _sessionResourcePlan(
        _sessions[sessionId] ?? (throw _unknownReference('session', sessionId)),
      );
    }
    if (kind == 'recording.stop') {
      final recordingId = workerId(
        input['recordingId'],
        r'$.input.recordingId',
      );
      final recording =
          _recordings[recordingId] ??
          (throw _unknownReference('recording', recordingId));
      return _sessionResourcePlan(
        _sessions[recording.sessionId] ??
            (throw _unknownReference('recording session', recordingId)),
      );
    }
    if (kind == 'shell.run') {
      return CockpitWorkerApplicationResourcePlan(
        primaryResourceId: cockpitCanonicalWorkspaceResourceId(workspaceId),
      );
    }
    throw FormatException('No canonical resource identity for $kind.');
  });

  String _systemActionTargetId(Map<String, Object?> input) {
    final targetValue = input['targetId'];
    final sessionValue = input['sessionId'];
    if ((targetValue == null) == (sessionValue == null)) {
      throw const FormatException(
        'system.action requires exactly one of targetId or sessionId.',
      );
    }
    if (sessionValue != null) {
      final sessionId = workerId(sessionValue, r'$.input.sessionId');
      return (_sessions[sessionId] ??
              (throw _unknownReference('session', sessionId)))
          .targetId;
    }
    return workerId(targetValue, r'$.input.targetId');
  }

  CockpitWorkerApplicationResourcePlan _sessionResourcePlan(
    CockpitWorkerSessionBinding session,
  ) => CockpitWorkerApplicationResourcePlan(
    primaryResourceId: session.resourceId,
    deviceResourceId: session.deviceResourceId,
  );

  Future<CockpitWorkerTargetBinding> recordTargetHandle({
    required String targetId,
    required CockpitTargetHandle handle,
  }) => _locked(() async {
    await _ensureLoaded();
    final current =
        _targets[targetId] ?? (throw _unknownReference('target', targetId));
    await _handlePersistence.validateTarget(handle);
    final updated = CockpitWorkerTargetBinding(
      targetId: targetId,
      deviceResourceId: current.deviceResourceId,
      projectDir: current.projectDir,
      launchEntrypoint: current.launchEntrypoint,
      registration: current.registration,
      handle: handle,
    );
    _targets[targetId] = updated;
    await _persist();
    return updated;
  });

  Future<CockpitWorkerAppBinding> recordApp({
    required String targetId,
    required CockpitAppHandle handle,
  }) => _locked(() async {
    await _ensureLoaded();
    final target =
        _targets[targetId] ?? (throw _unknownReference('target', targetId));
    await _handlePersistence.validateApp(handle);
    final binding = _recordAppInMemory(target: target, handle: handle);
    await _persist();
    return binding;
  });

  Future<CockpitWorkerAppBinding> recordLaunchedApp({
    required String targetId,
    required CockpitTargetHandle targetHandle,
    required CockpitAppHandle appHandle,
  }) => _locked(() async {
    await _ensureLoaded();
    final target =
        _targets[targetId] ?? (throw _unknownReference('target', targetId));
    await _handlePersistence.validateTarget(targetHandle);
    await _handlePersistence.validateApp(appHandle);
    final updatedTarget = CockpitWorkerTargetBinding(
      targetId: target.targetId,
      deviceResourceId: target.deviceResourceId,
      projectDir: target.projectDir,
      launchEntrypoint: target.launchEntrypoint,
      registration: target.registration,
      handle: targetHandle,
    );
    _targets[targetId] = updatedTarget;
    final binding = _recordAppInMemory(
      target: updatedTarget,
      handle: appHandle,
    );
    await _persist();
    return binding;
  });

  Future<CockpitWorkerAppBinding> recordSystemTargetLaunch({
    required String targetId,
    required DateTime launchedAt,
    int? processId,
  }) => _locked(() async {
    await _ensureLoaded();
    final target =
        _targets[targetId] ?? (throw _unknownReference('target', targetId));
    if (!target.registration.usesSystemControl) {
      throw const FormatException(
        'Remote targets must be recorded from their launched app handle.',
      );
    }
    final runtimeTarget =
        target.registration.entrypoint ??
        target.registration.appId ??
        target.registration.targetKind.name;
    final baseUrl = Uri(
      scheme: 'cockpit-system',
      path: '/$targetId',
    ).toString();
    final remote = CockpitRemoteSessionHandle(
      platform: target.registration.platform,
      deviceId: target.registration.deviceId,
      projectDir: target.projectDir,
      target: runtimeTarget,
      appId: targetId,
      platformAppId: target.registration.appId,
      processId: processId,
      host: 'system',
      hostPort: 0,
      devicePort: 0,
      baseUrl: baseUrl,
      launchedAt: launchedAt.toUtc(),
    );
    final app = CockpitAppHandle(
      appId: targetId,
      mode: CockpitAppMode.automation,
      platform: target.registration.platform,
      deviceId: target.registration.deviceId,
      projectDir: target.projectDir,
      target: runtimeTarget,
      baseUrl: baseUrl,
      launchedAt: launchedAt.toUtc(),
      platformAppId: target.registration.appId,
      processId: processId,
      remoteSession: remote,
    );
    final targetHandle = CockpitTargetHandle(
      targetId: targetId,
      targetKind: target.registration.targetKind,
      platform: target.registration.platform,
      deviceId: target.registration.deviceId,
      projectDir: target.projectDir,
      target: runtimeTarget,
      connection: CockpitTargetConnection(baseUrl: baseUrl),
      launchedAt: launchedAt.toUtc(),
      metadata: <String, Object?>{
        'appId': targetId,
        'appMode': CockpitAppMode.automation.jsonValue,
        if (target.registration.appId != null)
          'platformAppId': target.registration.appId,
        'processId': ?processId,
        'remoteSession': remote.toJson(),
      },
    );
    await _handlePersistence.validateTarget(targetHandle);
    await _handlePersistence.validateApp(app);
    final updatedTarget = CockpitWorkerTargetBinding(
      targetId: target.targetId,
      deviceResourceId: target.deviceResourceId,
      projectDir: target.projectDir,
      launchEntrypoint: target.launchEntrypoint,
      registration: target.registration,
      handle: targetHandle,
    );
    _targets[targetId] = updatedTarget;
    final binding = _recordAppInMemory(target: updatedTarget, handle: app);
    await _persist();
    return binding;
  });

  CockpitWorkerAppBinding _recordAppInMemory({
    required CockpitWorkerTargetBinding target,
    required CockpitAppHandle handle,
  }) {
    final existing = _apps.values
        .where((binding) => binding.handle.appId == handle.appId)
        .firstOrNull;
    final appId = existing?.appId ?? _newId('ap');
    if (existing != null &&
        !_sameOptionalRemoteHandle(
          existing.handle.remoteSession,
          handle.remoteSession,
        )) {
      _removeAppSessionsInMemory(appId);
    }
    final binding = CockpitWorkerAppBinding(
      appId: appId,
      targetId: target.targetId,
      handle: handle,
      updatedAt: _utcNow(),
    );
    _apps[appId] = binding;
    final remoteHandle = handle.remoteSession;
    if (remoteHandle != null) {
      _recordSessionInMemory(
        appId: appId,
        targetId: target.targetId,
        remoteHandle: remoteHandle,
        developmentHandle: handle.developmentSession,
        environment: target.registration.environment,
      );
    }
    return binding;
  }

  void _removeAppSessionsInMemory(String appId) {
    final sessionIds = <String>{
      for (final session in _sessions.values)
        if (session.appId == appId) session.sessionId,
    };
    if (sessionIds.isEmpty) {
      return;
    }
    final recordingIds = <String>{
      for (final recording in _recordings.values)
        if (recording.appId == appId ||
            sessionIds.contains(recording.sessionId))
          recording.recordingId,
    };
    _sessions.removeWhere(
      (_, session) => sessionIds.contains(session.sessionId),
    );
    _recordings.removeWhere(
      (_, recording) => recordingIds.contains(recording.recordingId),
    );
    _probes.removeWhere((_, probe) => sessionIds.contains(probe.sessionId));
    _removeSnapshotsForSessions(sessionIds);
    _removeOwnedArtifacts(sessionIds: sessionIds, recordingIds: recordingIds);
  }

  Future<CockpitWorkerAppBinding> requireApp(String appId) => _locked(() async {
    await _ensureLoaded();
    workerId(appId, r'$.appId');
    return _apps[appId] ?? (throw _unknownReference('app', appId));
  });

  Future<List<CockpitWorkerAppBinding>> listApps() => _locked(() async {
    await _ensureLoaded();
    final result = _apps.values.toList(growable: false)
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return List<CockpitWorkerAppBinding>.unmodifiable(result);
  });

  Future<CockpitWorkerAppBinding?> latestAppForTarget(String targetId) =>
      _locked(() async {
        await _ensureLoaded();
        final matches =
            _apps.values
                .where((binding) => binding.targetId == targetId)
                .toList(growable: false)
              ..sort(
                (left, right) => right.updatedAt.compareTo(left.updatedAt),
              );
        return matches.firstOrNull;
      });

  Future<CockpitWorkerSessionBinding> requireSession(String sessionId) =>
      _locked(() async {
        await _ensureLoaded();
        workerId(sessionId, r'$.sessionId');
        return _sessions[sessionId] ??
            (throw _unknownReference('session', sessionId));
      });

  Future<String> sessionIdForApp(String appId) => _locked(() async {
    await _ensureLoaded();
    final matches =
        _sessions.values
            .where((binding) => binding.appId == appId)
            .toList(growable: false)
          ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    if (matches.isEmpty) throw _unknownReference('app session', appId);
    return matches.first.sessionId;
  });

  Future<CockpitWorkerSessionBinding> updateDevelopmentSession(
    String sessionId,
    CockpitDevelopmentSessionHandle handle,
  ) => _locked(() async {
    await _ensureLoaded();
    final current =
        _sessions[sessionId] ?? (throw _unknownReference('session', sessionId));
    final remote = handle.remoteSessionHandle;
    if (remote == null) {
      throw const CockpitApplicationServiceException(
        code: 'workerSessionInvalid',
        message: 'Development session has no remote automation handle.',
      );
    }
    final currentHandle = current.developmentHandle;
    if (currentHandle != null &&
        currentHandle.developmentSessionId == handle.developmentSessionId &&
        handle.reloadGeneration < currentHandle.reloadGeneration) {
      final app = _apps[current.appId];
      if (app != null &&
          _syncTargetHandleFromApp(current.targetId, app.handle)) {
        await _persist();
      }
      return current;
    }
    if (_sameOptionalDevelopmentHandle(current.developmentHandle, handle)) {
      final app = _apps[current.appId];
      if (app != null &&
          _syncTargetHandleFromApp(current.targetId, app.handle)) {
        await _persist();
      }
      return current;
    }
    await _handlePersistence.validateDevelopment(handle);
    final updated = CockpitWorkerSessionBinding(
      sessionId: current.sessionId,
      appId: current.appId,
      targetId: current.targetId,
      deviceResourceId: current.deviceResourceId,
      resourceId: current.resourceId,
      remoteHandle: remote,
      developmentHandle: handle,
      environment: current.environment,
      updatedAt: _utcNow(),
    );
    _sessions[sessionId] = updated;
    final app = _apps[current.appId];
    if (app != null) {
      final refreshedApp = CockpitAppHandle.fromDevelopmentSession(
        handle,
        supervisorLogPath: app.handle.supervisorLogPath,
      );
      _apps[current.appId] = CockpitWorkerAppBinding(
        appId: app.appId,
        targetId: app.targetId,
        handle: refreshedApp,
        updatedAt: updated.updatedAt,
      );
      _syncTargetHandleFromApp(current.targetId, refreshedApp);
    }
    await _persist();
    return updated;
  });

  Future<void> removeApp(String appId) => _locked(() async {
    await _ensureLoaded();
    final app = _apps.remove(appId);
    if (app == null) throw _unknownReference('app', appId);
    _clearTargetHandleForApp(app);
    final sessionIds = <String>{
      for (final binding in _sessions.values)
        if (binding.appId == appId) binding.sessionId,
    };
    final recordingIds = <String>{
      for (final binding in _recordings.values)
        if (binding.appId == appId || sessionIds.contains(binding.sessionId))
          binding.recordingId,
    };
    _sessions.removeWhere((_, binding) => binding.appId == appId);
    _recordings.removeWhere(
      (_, binding) =>
          binding.appId == appId || sessionIds.contains(binding.sessionId),
    );
    _probes.removeWhere((_, binding) => sessionIds.contains(binding.sessionId));
    _removeSnapshotsForSessions(sessionIds);
    _removeOwnedArtifacts(sessionIds: sessionIds, recordingIds: recordingIds);
    await _persist();
  });

  Future<void> removeSession(String sessionId) => _locked(() async {
    await _ensureLoaded();
    if (_sessions.remove(sessionId) == null) {
      throw _unknownReference('session', sessionId);
    }
    final recordingIds = <String>{
      for (final binding in _recordings.values)
        if (binding.sessionId == sessionId) binding.recordingId,
    };
    _recordings.removeWhere((_, binding) => binding.sessionId == sessionId);
    _probes.removeWhere((_, binding) => binding.sessionId == sessionId);
    _removeSnapshotsForSessions(<String>{sessionId});
    _removeOwnedArtifacts(
      sessionIds: <String>{sessionId},
      recordingIds: recordingIds,
    );
    await _persist();
  });

  Future<void> invalidateDevelopmentSessions() => _locked(() async {
    await _ensureLoaded();
    final appIds = <String>{
      for (final binding in _sessions.values)
        if (binding.developmentHandle != null) binding.appId,
    };
    final sessionIds = <String>{
      for (final binding in _sessions.values)
        if (binding.developmentHandle != null) binding.sessionId,
    };
    final recordingIds = <String>{
      for (final binding in _recordings.values)
        if (sessionIds.contains(binding.sessionId)) binding.recordingId,
    };
    for (final app in _apps.values) {
      if (appIds.contains(app.appId)) _clearTargetHandleForApp(app);
    }
    _apps.removeWhere((id, _) => appIds.contains(id));
    _sessions.removeWhere((id, _) => sessionIds.contains(id));
    _recordings.removeWhere(
      (_, binding) => sessionIds.contains(binding.sessionId),
    );
    _probes.removeWhere((_, binding) => sessionIds.contains(binding.sessionId));
    _removeSnapshotsForSessions(sessionIds);
    _removeOwnedArtifacts(sessionIds: sessionIds, recordingIds: recordingIds);
    await _persist();
  });

  Future<CockpitWorkerRecordingBinding> recordRecording({
    required String sessionId,
  }) => _locked(() async {
    await _ensureLoaded();
    final session =
        _sessions[sessionId] ?? (throw _unknownReference('session', sessionId));
    final binding = CockpitWorkerRecordingBinding(
      recordingId: _newId('rc'),
      sessionId: sessionId,
      appId: session.appId,
      resourceId: session.resourceId,
      createdAt: _utcNow(),
    );
    _recordings[binding.recordingId] = binding;
    await _persist();
    return binding;
  });

  Future<CockpitWorkerRecordingBinding> requireRecording(String recordingId) =>
      _locked(() async {
        await _ensureLoaded();
        workerId(recordingId, r'$.recordingId');
        return _recordings[recordingId] ??
            (throw _unknownReference('recording', recordingId));
      });

  Future<void> flush() => _locked(() async {
    await _ensureLoaded();
    await _persist();
  });

  Future<void> removeRecording(String recordingId) => _locked(() async {
    await _ensureLoaded();
    if (_recordings.remove(recordingId) == null) {
      throw _unknownReference('recording', recordingId);
    }
    _removeOwnedArtifacts(recordingIds: <String>{recordingId});
    await _persist();
  });

  @override
  Future<CockpitWorkerArtifactBinding> registerArtifact({
    required String ownerKind,
    required String ownerId,
    required String kind,
    required String name,
    required String mediaType,
    required String retainedPath,
  }) => _locked(() async {
    await _ensureLoaded();
    if (!const <String>{'run', 'session', 'recording'}.contains(ownerKind)) {
      throw const FormatException('Artifact owner kind is invalid.');
    }
    workerId(ownerId, r'$.ownerId');
    workerId(kind, r'$.kind');
    workerString(name, r'$.name', maximum: 512);
    workerString(mediaType, r'$.mediaType', maximum: 128);
    workerString(retainedPath, r'$.retainedPath', maximum: 32768);
    if (ownerKind == 'run') {
      await _requireOwnedRunIds(<String>{ownerId});
    }
    final normalizedPath = p.normalize(p.absolute(retainedPath));
    if (!p.isAbsolute(retainedPath) ||
        name.contains('/') ||
        name.contains(r'\')) {
      throw const FormatException('Artifact path metadata is invalid.');
    }
    await _validateRetainedArtifactPath(
      normalizedPath,
      allowDirectory: kind == 'caseAttemptBundle',
      ownerKind: ownerKind,
      ownerId: ownerId,
    );
    final existing = _artifacts.values
        .where(
          (binding) =>
              binding.ownerKind == ownerKind &&
              binding.ownerId == ownerId &&
              binding.kind == kind &&
              binding.retainedPath == normalizedPath,
        )
        .firstOrNull;
    if (existing != null) return existing;
    final binding = CockpitWorkerArtifactBinding(
      artifactId: _newId('ar'),
      ownerKind: ownerKind,
      ownerId: ownerId,
      kind: kind,
      name: name,
      mediaType: mediaType,
      retainedPath: normalizedPath,
      createdAt: _utcNow(),
    );
    _artifacts[binding.artifactId] = binding;
    await _persist();
    return binding;
  });

  @override
  Future<CockpitWorkerArtifactBinding> requireArtifact(String artifactId) =>
      _locked(() async {
        await _ensureLoaded();
        workerId(artifactId, r'$.artifactId');
        final binding =
            _artifacts[artifactId] ??
            (throw _unknownReference('artifact', artifactId));
        if (binding.ownerKind == 'run') {
          await _requireOwnedRunIds(<String>{binding.ownerId});
        }
        await _validateRetainedArtifactPath(
          binding.retainedPath,
          allowDirectory: binding.kind == 'caseAttemptBundle',
          ownerKind: binding.ownerKind,
          ownerId: binding.ownerId,
        );
        return binding;
      });

  Future<void> _requireOwnedRunIds(Set<String> runIds) async {
    if (runIds.isEmpty) return;
    final candidates = Set<String>.unmodifiable(runIds);
    final owned = await _runOwnershipAuthority.findOwnedRunIds(
      workspaceId: workspaceId,
      candidateRunIds: candidates,
    );
    if (owned.length != candidates.length || !owned.containsAll(candidates)) {
      throw const FormatException(
        'Run-owned artifact references an unknown case run.',
      );
    }
  }

  Future<void> _validateRetainedArtifactPath(
    String retainedPath, {
    required bool allowDirectory,
    required String ownerKind,
    required String ownerId,
  }) async {
    if (!_isLexicallyConfinedArtifactPath(retainedPath)) {
      throw const FormatException(
        'Retained artifact path escapes the worker state root.',
      );
    }
    final type = await FileSystemEntity.type(retainedPath, followLinks: false);
    final allowed =
        type == FileSystemEntityType.file ||
        allowDirectory && type == FileSystemEntityType.directory;
    if (!allowed) {
      throw FileSystemException(
        'Retained artifact has an invalid type.',
        retainedPath,
      );
    }
    final canonical = p.normalize(
      type == FileSystemEntityType.directory
          ? await Directory(retainedPath).resolveSymbolicLinks()
          : await File(retainedPath).resolveSymbolicLinks(),
    );
    if (!p.equals(canonical, retainedPath) ||
        !_isLexicallyConfinedArtifactPath(canonical)) {
      throw FileSystemException(
        'Retained artifact resolves outside the worker state root.',
        retainedPath,
      );
    }
    final retainedOwnerRoot = _artifactOwnerRoot(ownerKind, ownerId);
    if (!p.isWithin(retainedOwnerRoot, canonical)) {
      throw FileSystemException(
        'Retained artifact escapes its owner authority.',
        retainedPath,
      );
    }
    if (type == FileSystemEntityType.directory) {
      if (ownerKind != 'run' || !p.isWithin(retainedOwnerRoot, canonical)) {
        throw FileSystemException(
          'Retained bundle escapes its run owner authority.',
          retainedPath,
        );
      }
      await for (final entity in Directory(
        retainedPath,
      ).list(recursive: true, followLinks: false)) {
        final nestedType = await FileSystemEntity.type(
          entity.path,
          followLinks: false,
        );
        if (nestedType != FileSystemEntityType.file &&
            nestedType != FileSystemEntityType.directory) {
          throw FileSystemException(
            'Retained bundle contains an invalid entry.',
            entity.path,
          );
        }
        final nestedCanonical = p.normalize(
          nestedType == FileSystemEntityType.directory
              ? await Directory(entity.path).resolveSymbolicLinks()
              : await File(entity.path).resolveSymbolicLinks(),
        );
        if (!p.equals(nestedCanonical, entity.path) ||
            !p.isWithin(canonical, nestedCanonical)) {
          throw FileSystemException(
            'Retained bundle entry escapes its committed root.',
            entity.path,
          );
        }
      }
    }
    if (type == FileSystemEntityType.file) {
      RandomAccessFile? handle;
      try {
        handle = await File(retainedPath).open(mode: FileMode.read);
        await handle.read(1);
      } finally {
        await handle?.close();
      }
    }
  }

  bool _isLexicallyConfinedArtifactPath(String retainedPath) =>
      p.isAbsolute(retainedPath) &&
      p.normalize(retainedPath) == retainedPath &&
      p.isWithin(stateRoot, retainedPath);

  Future<String> recordProbe({
    required String sessionId,
    required CockpitDevelopmentProbe probe,
  }) => _locked(() async {
    await _ensureLoaded();
    final session = _sessions[sessionId];
    if (session == null) {
      throw _unknownReference('session', sessionId);
    }
    final developmentSessionId =
        session.developmentHandle?.developmentSessionId;
    if (developmentSessionId == null ||
        probe.sessionId != developmentSessionId) {
      throw const FormatException('Probe session ownership is invalid.');
    }
    if (_probes.length >= maximumRetainedProbes) {
      throw const CockpitApplicationServiceException(
        code: 'workerProbeCapacityExceeded',
        message: 'Worker probe retention capacity is exhausted.',
      );
    }
    final probeId = _newId('pb');
    _probes[probeId] = _ProbeBinding(
      probeId: probeId,
      sessionId: sessionId,
      probe: probe,
    );
    await _persist();
    return probeId;
  });

  Future<CockpitDevelopmentProbe> requireProbe({
    required String sessionId,
    required String probeId,
  }) => _locked(() async {
    await _ensureLoaded();
    workerId(probeId, r'$.probeId');
    final binding = _probes[probeId];
    if (binding == null || binding.sessionId != sessionId) {
      throw _unknownReference('probe', probeId);
    }
    return binding.probe;
  });

  Future<String> recordSnapshotRef({
    required String sessionId,
    required String retainedRef,
  }) => _serialized(() async {
    await _ensureLoaded();
    if (!_sessions.containsKey(sessionId)) {
      throw _unknownReference('session', sessionId);
    }
    workerString(retainedRef, r'$.snapshotRef', maximum: 512);
    final identity = (sessionId, retainedRef);
    final existing = _snapshotRefsByIdentity[identity];
    if (existing != null) return existing;
    if (_snapshots.length >= maximumTransientSnapshots) {
      throw const CockpitApplicationServiceException(
        code: 'workerSnapshotCapacityExceeded',
        message: 'Worker snapshot reference capacity is exhausted.',
      );
    }
    final snapshotRef = _newId('sn');
    _snapshots[snapshotRef] = _SnapshotBinding(
      snapshotRef: snapshotRef,
      sessionId: sessionId,
      retainedRef: retainedRef,
    );
    _snapshotRefsByIdentity[identity] = snapshotRef;
    return snapshotRef;
  });

  void _removeSnapshotsForSessions(Set<String> sessionIds) {
    if (sessionIds.isEmpty) return;
    _snapshots.removeWhere(
      (_, binding) => sessionIds.contains(binding.sessionId),
    );
    _snapshotRefsByIdentity.removeWhere(
      (identity, _) => sessionIds.contains(identity.$1),
    );
  }

  Future<String?> resolveSnapshotRef({
    required String sessionId,
    required Object? snapshotRef,
  }) => _serialized(() async {
    await _ensureLoaded();
    if (snapshotRef == null) return null;
    final opaque = workerId(snapshotRef, r'$.snapshotRef');
    final binding = _snapshots[opaque];
    if (binding == null || binding.sessionId != sessionId) {
      throw _unknownReference('snapshot', opaque);
    }
    return binding.retainedRef;
  });

  String? publicAppIdForInternal(String internalAppId) => _apps.values
      .where((binding) => binding.handle.appId == internalAppId)
      .firstOrNull
      ?.appId;

  String? publicSessionIdForInternal(String internalSessionId) => _sessions
      .values
      .where(
        (binding) =>
            binding.remoteHandle.appId == internalSessionId ||
            binding.developmentHandle?.developmentSessionId ==
                internalSessionId,
      )
      .firstOrNull
      ?.sessionId;

  @override
  Future<CockpitWorkerHealthySession> selectHealthySession({
    required String? targetId,
    required CockpitTestTargetRequirements requirements,
    String? preferredResourceId,
  }) => _locked(() async {
    await _ensureLoaded();
    if (requirements.targetKind != CockpitTargetKind.flutterApp.name) {
      return _selectHealthySystemSession(
        targetId: targetId,
        requirements: requirements,
        preferredResourceId: preferredResourceId,
      );
    }
    final candidates =
        _sessions.values
            .where((binding) {
              if (targetId != null && binding.targetId != targetId) {
                return false;
              }
              if (preferredResourceId != null &&
                  binding.resourceId != preferredResourceId) {
                return false;
              }
              if (requirements.appId != null &&
                  binding.appId != requirements.appId) {
                return false;
              }
              return requirements.platform == 'flutter' ||
                  binding.remoteHandle.platform == requirements.platform;
            })
            .toList(growable: false)
          ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    for (final candidate in candidates) {
      final client = CockpitRemoteSessionClient(
        baseUri: candidate.remoteHandle.baseUri,
      );
      try {
        if (!await client.ping() || !await client.ready()) continue;
        final status = await client.readStatus();
        final systemDriver = await _secondarySystemDriver(candidate);
        final available = <String>{
          ...status.capabilities.supportedCommands.map(
            (command) => command.name,
          ),
          ...?systemDriver?.capabilities.supportedCommands.map(
            (command) => command.name,
          ),
        };
        if (!available.containsAll(requirements.requiredCapabilities)) {
          continue;
        }
        return CockpitWorkerHealthySession(
          sessionId: candidate.sessionId,
          targetId: candidate.targetId,
          deviceResourceId: candidate.deviceResourceId,
          resourceId: candidate.resourceId,
          environment: candidate.environment,
          automationAdapter: CockpitRemoteAutomationAdapter(
            client: client,
            workspaceRoot: workspaceRoot,
          ),
          captureAdapter: CockpitRemoteCaptureAdapter(client: client),
          recordingAdapter: CockpitRemoteRecordingAdapter(client: client),
          systemAutomationAdapter: systemDriver?.automation,
          systemCaptureAdapter: systemDriver?.capture,
          systemRecordingAdapter: systemDriver?.recording,
          healthCheck: () async => await client.ping() && await client.ready(),
          prepare: systemDriver?.prepare,
          isolate: (isolation, deadline) =>
              _isolateFlutterSession(candidate.sessionId, isolation, deadline),
          forceAbort: () => forceAbortSession(candidate.sessionId),
        );
      } on Object {
        continue;
      }
    }
    if (requirements.plane != CockpitTestPlane.semantic) {
      return _selectHealthySystemSession(
        targetId: targetId,
        requirements: requirements,
        preferredResourceId: preferredResourceId,
      );
    }
    throw const CockpitApplicationServiceException(
      code: 'healthySessionNotFound',
      message: 'No compatible healthy session is owned by this workspace.',
    );
  });

  Future<
    ({
      CockpitAutomationAdapter automation,
      CockpitCaptureAdapter? capture,
      CockpitRecordingAdapter? recording,
      CockpitCapabilities capabilities,
      Future<void> Function(DateTime deadline)? prepare,
    })?
  >
  _secondarySystemDriver(CockpitWorkerSessionBinding session) async {
    final binding = _targets[session.targetId];
    final app = _apps[session.appId];
    final appId = app?.handle.platformAppId ?? binding?.registration.appId;
    if (binding == null || appId == null || appId.trim().isEmpty) return null;
    final target = CockpitSystemTestTarget(
      platform: binding.registration.platform,
      deviceId: binding.registration.deviceId,
      appId: appId,
      targetKind: binding.registration.targetKind,
      processId: app?.handle.processId,
      metadata: <String, Object?>{
        if (binding.registration.wdaUrl != null)
          'wdaUrl': binding.registration.wdaUrl,
        if (binding.registration.cdpUrl != null)
          'cdpUrl': binding.registration.cdpUrl,
      },
    );
    final automation = CockpitSystemTestAutomationAdapter(
      target: target,
      controlService: _systemControlService,
      actionService: _systemActionService,
      workspaceRoot: workspaceRoot,
    );
    try {
      final capabilities = await automation.describeCapabilities();
      final profile = (await _systemControlService.describe(
        CockpitSystemControlDescribeRequest(
          platform: target.platform,
          deviceId: target.deviceId,
          appId: target.appId,
          processId: target.processId,
          metadata: target.metadata,
        ),
      )).profile;
      final actions = profile.availableActions.toSet();
      return (
        automation: automation,
        capabilities: capabilities,
        capture: actions.contains(CockpitSystemControlAction.captureScreenshot)
            ? CockpitSystemTestCaptureAdapter(
                target: target,
                actionService: _systemActionService,
              )
            : null,
        recording:
            actions.contains(CockpitSystemControlAction.startRecording) &&
                actions.contains(CockpitSystemControlAction.stopRecording)
            ? CockpitSystemTestRecordingAdapter(
                target: target,
                actionService: _systemActionService,
              )
            : null,
        prepare:
            actions.contains(CockpitSystemControlAction.activateWindow) &&
                _canPrepareInAppTarget(target)
            ? (deadline) => _activateTarget(target, deadline)
            : null,
      );
    } on Object {
      return null;
    }
  }

  Future<CockpitWorkerHealthySession> _selectHealthySystemSession({
    required String? targetId,
    required CockpitTestTargetRequirements requirements,
    required String? preferredResourceId,
  }) async {
    final candidates =
        _targets.values
            .where((candidate) {
              if (targetId != null && candidate.targetId != targetId) {
                return false;
              }
              final registration = candidate.registration;
              return registration.targetKind.name == requirements.targetKind &&
                  registration.platform.trim().toLowerCase() ==
                      requirements.platform.trim().toLowerCase();
            })
            .toList(growable: false)
          ..sort((left, right) => left.targetId.compareTo(right.targetId));
    for (final candidate in candidates) {
      final appMatches =
          _apps.values
              .where((binding) => binding.targetId == candidate.targetId)
              .toList(growable: false)
            ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      final app = appMatches.firstOrNull;
      final platformAppId =
          requirements.appId ??
          candidate.registration.appId ??
          app?.handle.platformAppId;
      if (_targetKindRequiresAppId(candidate.registration.targetKind) &&
          (platformAppId == null || platformAppId.trim().isEmpty)) {
        continue;
      }
      final target = CockpitSystemTestTarget(
        platform: candidate.registration.platform,
        deviceId: candidate.registration.deviceId,
        appId: platformAppId,
        targetKind: candidate.registration.targetKind,
        processId: app?.handle.processId,
        metadata: <String, Object?>{
          if (candidate.registration.wdaUrl != null)
            'wdaUrl': candidate.registration.wdaUrl,
          if (candidate.registration.cdpUrl != null)
            'cdpUrl': candidate.registration.cdpUrl,
        },
      );
      final automation = CockpitSystemTestAutomationAdapter(
        target: target,
        controlService: _systemControlService,
        actionService: _systemActionService,
        workspaceRoot: workspaceRoot,
      );
      try {
        final capabilities = await automation.describeCapabilities();
        final available = capabilities.supportedCommands
            .map((command) => command.name)
            .toSet();
        if (!available.containsAll(requirements.requiredCapabilities)) continue;
        final profile = (await _systemControlService.describe(
          CockpitSystemControlDescribeRequest(
            platform: target.platform,
            deviceId: target.deviceId,
            appId: target.appId,
            processId: target.processId,
            metadata: target.metadata,
          ),
        )).profile;
        final actions = profile.availableActions.toSet();
        final resourceId = cockpitCanonicalSystemSessionResourceId(
          deviceResourceId: candidate.deviceResourceId,
          targetId: candidate.targetId,
          targetKind: requirements.targetKind,
          appId: platformAppId,
        );
        if (preferredResourceId != null && resourceId != preferredResourceId) {
          continue;
        }
        return CockpitWorkerHealthySession(
          sessionId: 'system_${resourceId.substring('session_'.length)}',
          targetId: candidate.targetId,
          deviceResourceId: candidate.deviceResourceId,
          resourceId: resourceId,
          environment: candidate.registration.environment,
          automationAdapter: automation,
          captureAdapter:
              actions.contains(CockpitSystemControlAction.captureScreenshot)
              ? CockpitSystemTestCaptureAdapter(
                  target: target,
                  actionService: _systemActionService,
                )
              : null,
          recordingAdapter:
              actions.contains(CockpitSystemControlAction.startRecording) &&
                  actions.contains(CockpitSystemControlAction.stopRecording)
              ? CockpitSystemTestRecordingAdapter(
                  target: target,
                  actionService: _systemActionService,
                )
              : null,
          lowerer: const CockpitTestActionLowerer.system(),
          prepare: actions.contains(CockpitSystemControlAction.activateWindow)
              ? (deadline) => _activateTarget(target, deadline)
              : null,
          isolate: (isolation, deadline) =>
              _isolateSystemTarget(target, isolation, deadline),
          healthCheck: () async {
            final current = await automation.describeCapabilities();
            return current.supportedCommands
                .map((command) => command.name)
                .toSet()
                .containsAll(requirements.requiredCapabilities);
          },
        );
      } on Object {
        continue;
      }
    }
    throw const CockpitApplicationServiceException(
      code: 'healthySystemSessionNotFound',
      message: 'No compatible system automation target is available.',
    );
  }

  Future<void> _activateTarget(
    CockpitSystemTestTarget target,
    DateTime deadline,
  ) async {
    final remaining = deadline.difference(_utcNow());
    if (remaining <= Duration.zero) {
      throw TimeoutException('Session preparation deadline expired.');
    }
    const maximumTimeout = Duration(seconds: 30);
    final result = await _systemActionService.run(
      CockpitSystemControlActionRequest(
        platform: target.platform,
        deviceId: target.deviceId,
        appId: target.appId,
        processId: target.processId,
        metadata: target.metadata,
        action: CockpitSystemControlAction.activateWindow,
        timeout: remaining < maximumTimeout ? remaining : maximumTimeout,
      ),
    );
    if (result.success) return;
    throw CockpitApplicationServiceException(
      code: result.errorCode ?? 'sessionPreparationFailed',
      message:
          result.errorMessage ??
          'The selected application could not be brought to the foreground.',
      details: <String, Object?>{
        'action': CockpitSystemControlAction.activateWindow.name,
        'availability': result.availability.name,
        'recommendedNextStep': result.recommendedNextStep,
      },
    );
  }

  bool _canPrepareInAppTarget(CockpitSystemTestTarget target) {
    return switch (target.platform.trim().toLowerCase()) {
      'macos' || 'windows' || 'linux' => target.processId != null,
      'android' || 'ios' => target.appId?.trim().isNotEmpty ?? false,
      _ => false,
    };
  }

  Future<void> _isolateFlutterSession(
    String sessionId,
    CockpitTestSuiteIsolation isolation,
    DateTime deadline,
  ) async {
    if (isolation == CockpitTestSuiteIsolation.sharedSession) return;
    if (isolation == CockpitTestSuiteIsolation.resetAppData) {
      throw const CockpitApplicationServiceException(
        code: 'suiteIsolationUnsupported',
        message:
            'resetAppData is unavailable for an in-app Flutter session. Register the installed application as a nativeApp target.',
      );
    }
    final state = await _locked(() async {
      await _ensureLoaded();
      final session = _sessions[sessionId];
      if (session == null) throw _unknownReference('session', sessionId);
      final app = _apps[session.appId];
      if (app == null) throw _unknownReference('app', session.appId);
      return (session: session, app: app);
    });
    final developmentHandle = state.session.developmentHandle;
    final restarter = _developmentSessionRestarter;
    if (developmentHandle == null || restarter == null) {
      throw const CockpitApplicationServiceException(
        code: 'suiteIsolationUnsupported',
        message:
            'restartApp requires a live Flutter development session with hot-restart support.',
      );
    }
    final remaining = deadline.difference(_utcNow());
    if (remaining <= Duration.zero) {
      throw TimeoutException('Suite isolation deadline expired.');
    }
    final restarted = await restarter(developmentHandle).timeout(remaining);
    final remoteHandle = restarted.remoteSessionHandle;
    if (remoteHandle == null) {
      throw const CockpitApplicationServiceException(
        code: 'suiteIsolationFailed',
        message: 'Flutter hot restart did not retain a remote session handle.',
      );
    }
    await _locked(() async {
      await _ensureLoaded();
      final currentSession = _sessions[sessionId];
      final currentApp = _apps[state.app.appId];
      if (currentSession == null || currentApp == null) {
        throw _unknownReference('session', sessionId);
      }
      _sessions[sessionId] = CockpitWorkerSessionBinding(
        sessionId: currentSession.sessionId,
        appId: currentSession.appId,
        targetId: currentSession.targetId,
        deviceResourceId: currentSession.deviceResourceId,
        resourceId: currentSession.resourceId,
        remoteHandle: remoteHandle,
        developmentHandle: restarted,
        environment: currentSession.environment,
        updatedAt: _utcNow(),
      );
      final refreshedApp = CockpitAppHandle.fromDevelopmentSession(
        restarted,
        supervisorLogPath: currentApp.handle.supervisorLogPath,
      );
      _apps[currentApp.appId] = CockpitWorkerAppBinding(
        appId: currentApp.appId,
        targetId: currentApp.targetId,
        handle: refreshedApp,
        updatedAt: _utcNow(),
      );
      _syncTargetHandleFromApp(currentSession.targetId, refreshedApp);
      await _persist();
    });
  }

  bool _syncTargetHandleFromApp(String targetId, CockpitAppHandle app) {
    final target = _targets[targetId];
    final handle = target?.handle;
    if (target == null || handle == null) return false;
    final refreshedHandle = handle.withAppHandle(app);
    if (refreshedHandle == handle) return false;
    _targets[targetId] = CockpitWorkerTargetBinding(
      targetId: target.targetId,
      deviceResourceId: target.deviceResourceId,
      projectDir: target.projectDir,
      launchEntrypoint: target.launchEntrypoint,
      registration: target.registration,
      handle: refreshedHandle,
    );
    return true;
  }

  Future<void> _isolateSystemTarget(
    CockpitSystemTestTarget target,
    CockpitTestSuiteIsolation isolation,
    DateTime deadline,
  ) async {
    if (isolation == CockpitTestSuiteIsolation.sharedSession) return;
    final actions = isolation == CockpitTestSuiteIsolation.resetAppData
        ? const <CockpitSystemControlAction>[
            CockpitSystemControlAction.clearAppData,
            CockpitSystemControlAction.activateWindow,
          ]
        : const <CockpitSystemControlAction>[
            CockpitSystemControlAction.terminateApp,
            CockpitSystemControlAction.activateWindow,
          ];
    for (final action in actions) {
      final remaining = deadline.difference(_utcNow());
      if (remaining <= Duration.zero) {
        throw TimeoutException('Suite isolation deadline expired.');
      }
      final result = await _systemActionService.run(
        CockpitSystemControlActionRequest(
          platform: target.platform,
          deviceId: target.deviceId,
          appId: target.appId,
          processId: target.processId,
          metadata: target.metadata,
          action: action,
          timeout: remaining,
        ),
      );
      if (!result.success) {
        throw CockpitApplicationServiceException(
          code: result.errorCode ?? 'suiteIsolationFailed',
          message:
              result.errorMessage ??
              '${action.name} failed while preparing suite isolation.',
          details: <String, Object?>{
            'action': action.name,
            'availability': result.availability.name,
            'recommendedNextStep': result.recommendedNextStep,
          },
        );
      }
    }
  }

  Future<void> forceAbortSession(String sessionId) async {
    final app = await _locked(() async {
      await _ensureLoaded();
      final session = _sessions[sessionId];
      if (session == null) return null;
      return _apps[session.appId];
    });
    if (app == null) return;
    try {
      final developmentHandle = app.handle.developmentSession;
      if (developmentHandle != null && _developmentSessionAborter != null) {
        await _developmentSessionAborter(developmentHandle);
      } else {
        await _stopAppService.stop(CockpitStopAppRequest(app: app.handle));
      }
    } finally {
      await _locked(() async {
        _sessions.remove(sessionId);
        final recordingIds = <String>{
          for (final binding in _recordings.values)
            if (binding.sessionId == sessionId) binding.recordingId,
        };
        _recordings.removeWhere((_, binding) => binding.sessionId == sessionId);
        _probes.removeWhere((_, binding) => binding.sessionId == sessionId);
        _removeSnapshotsForSessions(<String>{sessionId});
        _removeOwnedArtifacts(
          sessionIds: <String>{sessionId},
          recordingIds: recordingIds,
        );
        await _persist();
      });
    }
  }

  void _recordSessionInMemory({
    required String appId,
    required String targetId,
    required CockpitRemoteSessionHandle remoteHandle,
    required CockpitDevelopmentSessionHandle? developmentHandle,
    required CockpitTestTargetEnvironment environment,
  }) {
    final existing = _sessions.values
        .where(
          (binding) =>
              binding.remoteHandle.baseUrl == remoteHandle.baseUrl &&
              binding.remoteHandle.appId == remoteHandle.appId,
        )
        .firstOrNull;
    final sessionId = existing?.sessionId ?? _newId('ss');
    _sessions[sessionId] = CockpitWorkerSessionBinding(
      sessionId: sessionId,
      appId: appId,
      targetId: targetId,
      deviceResourceId: _targets[targetId]!.deviceResourceId,
      resourceId: cockpitCanonicalSessionResourceId(
        deviceResourceId: _targets[targetId]!.deviceResourceId,
        handle: remoteHandle,
      ),
      remoteHandle: remoteHandle,
      developmentHandle: developmentHandle,
      environment: environment,
      updatedAt: _utcNow(),
    );
  }

  void _removeOwnedArtifacts({
    Set<String> sessionIds = const <String>{},
    Set<String> recordingIds = const <String>{},
  }) {
    _artifacts.removeWhere(
      (_, binding) =>
          binding.ownerKind == 'session' &&
              sessionIds.contains(binding.ownerId) ||
          binding.ownerKind == 'recording' &&
              recordingIds.contains(binding.ownerId),
    );
  }

  void _clearTargetHandleForApp(CockpitWorkerAppBinding app) {
    final target = _targets[app.targetId];
    final handle = target?.handle;
    if (target == null ||
        handle == null ||
        handle.metadata['appId'] != app.handle.appId) {
      return;
    }
    _targets[target.targetId] = CockpitWorkerTargetBinding(
      targetId: target.targetId,
      deviceResourceId: target.deviceResourceId,
      projectDir: target.projectDir,
      launchEntrypoint: target.launchEntrypoint,
      registration: target.registration,
    );
  }

  void _validateRegistration(CockpitWorkerTargetRegistration registration) {
    _requireWorkspace(registration.workspaceId);
    workerString(registration.platform, r'$.platform', maximum: 32);
    workerString(registration.deviceId, r'$.deviceId', maximum: 512);
    if (registration.flavor != null) {
      workerString(registration.flavor, r'$.flavor', maximum: 256);
    }
    final appId = registration.appId;
    if (appId != null) {
      workerString(appId, r'$.appId', maximum: 512);
      if (appId.trim().isEmpty) {
        throw const CockpitApplicationServiceException(
          code: 'targetAppIdInvalid',
          message: 'Target appId must not be blank.',
        );
      }
    } else if (_targetKindRequiresAppId(registration.targetKind)) {
      throw const CockpitApplicationServiceException(
        code: 'targetAppIdRequired',
        message: 'Target kind requires an appId.',
      );
    }
    if (registration.wdaUrl case final wdaUrl?) {
      workerString(wdaUrl, r'$.wdaUrl', maximum: 2048);
      final uri = Uri.tryParse(wdaUrl);
      if (uri == null ||
          !const <String>{'http', 'https'}.contains(uri.scheme) ||
          uri.host.isEmpty) {
        throw const CockpitApplicationServiceException(
          code: 'targetWdaUrlInvalid',
          message: 'Target wdaUrl must be an absolute HTTP(S) URL.',
        );
      }
    }
    if (registration.cdpUrl case final cdpUrl?) {
      workerString(cdpUrl, r'$.cdpUrl', maximum: 2048);
      final uri = Uri.tryParse(cdpUrl);
      if (uri == null ||
          !const <String>{'http', 'https', 'ws', 'wss'}.contains(uri.scheme) ||
          uri.host.isEmpty) {
        throw const CockpitApplicationServiceException(
          code: 'targetCdpUrlInvalid',
          message: 'Target cdpUrl must be an absolute HTTP(S) or WS(S) URL.',
        );
      }
    }
    final entrypoint = registration.entrypoint;
    final entrypointSha256 = registration.entrypointSha256;
    if ((entrypoint == null) != (entrypointSha256 == null)) {
      throw const CockpitApplicationServiceException(
        code: 'targetEntrypointIdentityInvalid',
        message: 'Target entrypoint path and digest must be bound together.',
      );
    }
    if (entrypoint != null && entrypointSha256 != null) {
      workerString(entrypoint, r'$.entrypoint', maximum: 4096);
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(entrypointSha256)) {
        throw const CockpitApplicationServiceException(
          code: 'targetEntrypointIdentityInvalid',
          message: 'Target entrypoint digest is invalid.',
        );
      }
      final normalized = p.normalize(entrypoint);
      if (p.isAbsolute(entrypoint) ||
          normalized == '..' ||
          normalized.startsWith('../') ||
          normalized.startsWith('..${p.separator}')) {
        throw const CockpitApplicationServiceException(
          code: 'targetOutsideWorkspace',
          message: 'Target entrypoint must be workspace-relative and confined.',
        );
      }
    }
  }

  Future<void> _validateTargetEntrypointCurrent(
    CockpitWorkerTargetRegistration registration,
  ) async {
    if (registration.targetKind != CockpitTargetKind.flutterApp) return;
    final relative = registration.entrypoint;
    final expectedSha256 = registration.entrypointSha256;
    if (relative == null || expectedSha256 == null) return;
    final root = p.normalize(
      await Directory(workspaceRoot).resolveSymbolicLinks(),
    );
    final candidate = p.normalize(p.join(root, relative));
    if (!p.equals(root, p.normalize(workspaceRoot)) ||
        !p.isWithin(root, candidate) ||
        await FileSystemEntity.type(candidate, followLinks: false) !=
            FileSystemEntityType.file) {
      throw const CockpitApplicationServiceException(
        code: 'targetEntrypointStale',
        message: 'Target entrypoint is no longer a confined regular file.',
      );
    }
    final canonical = p.normalize(await File(candidate).resolveSymbolicLinks());
    if (!p.equals(canonical, candidate) || !p.isWithin(root, canonical)) {
      throw const CockpitApplicationServiceException(
        code: 'targetEntrypointStale',
        message: 'Target entrypoint resolves outside the workspace.',
      );
    }
    RandomAccessFile? handle;
    try {
      handle = await File(canonical).open(mode: FileMode.read);
      final length = await handle.length();
      if (length > CockpitWorkerDocumentIndex.maximumIndexedFileBytes) {
        throw const CockpitApplicationServiceException(
          code: 'targetEntrypointStale',
          message: 'Target entrypoint exceeds the indexed size bound.',
        );
      }
      final bytes = await handle.read(length);
      final afterType = await FileSystemEntity.type(
        candidate,
        followLinks: false,
      );
      final afterCanonical = afterType == FileSystemEntityType.file
          ? p.normalize(await File(candidate).resolveSymbolicLinks())
          : null;
      if (bytes.length != length ||
          afterCanonical == null ||
          !p.equals(afterCanonical, canonical) ||
          sha256.convert(bytes).toString() != expectedSha256) {
        throw const CockpitApplicationServiceException(
          code: 'targetEntrypointStale',
          message: 'Target entrypoint changed after registration.',
        );
      }
    } finally {
      await handle?.close();
    }
  }

  ({String projectDir, String? launchEntrypoint}) _resolveTargetProject(
    CockpitWorkerTargetRegistration registration, {
    required bool requireProject,
  }) {
    final entrypoint = registration.entrypoint;
    if (registration.targetKind != CockpitTargetKind.flutterApp ||
        entrypoint == null) {
      return (projectDir: workspaceRoot, launchEntrypoint: entrypoint);
    }
    final absoluteEntrypoint = p.normalize(p.join(workspaceRoot, entrypoint));
    var directory = p.dirname(absoluteEntrypoint);
    while (p.equals(directory, workspaceRoot) ||
        p.isWithin(workspaceRoot, directory)) {
      final manifest = p.join(directory, 'pubspec.yaml');
      if (FileSystemEntity.typeSync(manifest, followLinks: false) ==
          FileSystemEntityType.file) {
        final canonicalManifest = p.normalize(
          File(manifest).resolveSymbolicLinksSync(),
        );
        if (p.equals(canonicalManifest, manifest)) {
          return (
            projectDir: directory,
            launchEntrypoint: p.relative(absoluteEntrypoint, from: directory),
          );
        }
      }
      if (p.equals(directory, workspaceRoot)) break;
      directory = p.dirname(directory);
    }
    if (!requireProject) {
      return (projectDir: workspaceRoot, launchEntrypoint: entrypoint);
    }
    throw CockpitApplicationServiceException(
      code: 'flutterProjectNotFound',
      message: 'No Flutter pubspec.yaml contains the selected entrypoint.',
      details: <String, Object?>{'entrypoint': entrypoint},
    );
  }

  void _requireWorkspace(String candidate) {
    if (candidate != workspaceId) {
      throw const CockpitApplicationServiceException(
        code: 'workspaceMismatch',
        message: 'Opaque reference belongs to another workspace.',
      );
    }
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final json = await _stateStore.read();
    if (json.isNotEmpty) {
      try {
        _replacePersistentState(json);
        await _validateLoadedHandleAuthorities();
        await _refreshRunArtifactAuthorities();
        _validatePersistentState();
      } catch (_) {
        _clearPersistentState();
        rethrow;
      }
    }
    _loaded = true;
  }

  Future<void> _validateLoadedHandleAuthorities() async {
    final handles = _handlePersistence;
    for (final target in _targets.values) {
      if (target.handle case final handle?) {
        await handles.validateTarget(handle);
      }
    }
    for (final app in _apps.values) {
      await handles.validateApp(app.handle);
    }
    for (final session in _sessions.values) {
      await handles.validateRemote(session.remoteHandle);
      if (session.developmentHandle case final development?) {
        await handles.validateDevelopment(development);
      }
    }
  }

  void _validatePersistentState({bool requireRunAuthority = true}) {
    _validateCollectionLimit('targets', _targets.length, maximumTargets);
    _validateCollectionLimit('apps', _apps.length, maximumApps);
    _validateCollectionLimit('sessions', _sessions.length, maximumSessions);
    _validateCollectionLimit(
      'recordings',
      _recordings.length,
      maximumRecordings,
    );
    _validateCollectionLimit('artifacts', _artifacts.length, maximumArtifacts);
    _validateCollectionLimit('probes', _probes.length, maximumRetainedProbes);
    _validateCollectionLimit(
      'transient snapshots',
      _snapshots.length,
      maximumTransientSnapshots,
    );
    if (_snapshotRefsByIdentity.length != _snapshots.length ||
        _snapshots.values.any(
          (binding) =>
              _snapshotRefsByIdentity[(
                binding.sessionId,
                binding.retainedRef,
              )] !=
              binding.snapshotRef,
        )) {
      throw const FormatException(
        'Worker transient snapshot identity is inconsistent.',
      );
    }

    for (final entry in _targets.entries) {
      final target = entry.value;
      if (entry.key != target.targetId ||
          !(p.equals(target.projectDir, workspaceRoot) ||
              p.isWithin(workspaceRoot, target.projectDir)) ||
          target.registration.workspaceId != workspaceId ||
          target.deviceResourceId !=
              cockpitCanonicalDeviceResourceId(
                platform: target.registration.platform,
                deviceId: target.registration.deviceId,
              )) {
        throw FormatException(
          'Target ownership is invalid for ${target.targetId}.',
        );
      }
      _validateRegistration(target.registration);
      final handle = target.handle;
      if (handle != null &&
          (!_targetHandleKindMatchesRegistration(
                registration: target.registration.targetKind,
                launched: handle.targetKind,
              ) ||
              handle.platform != target.registration.platform ||
              handle.deviceId != target.registration.deviceId ||
              !_projectOwnedByTarget(target, handle.projectDir))) {
        throw FormatException(
          'Target handle ownership is invalid for ${target.targetId}.',
        );
      }
      if (handle != null) {
        _validateTargetHandleOwnership(handle);
      }
    }

    for (final entry in _apps.entries) {
      final app = entry.value;
      final target = _targets[app.targetId];
      if (entry.key != app.appId ||
          target == null ||
          app.handle.platform != target.registration.platform ||
          app.handle.deviceId != target.registration.deviceId ||
          (target.handle == null
              ? !_projectOwnedByTarget(target, app.handle.projectDir)
              : app.handle.projectDir != target.handle!.projectDir) ||
          target.handle != null && app.handle.target != target.handle!.target) {
        throw FormatException('App ownership is invalid for ${app.appId}.');
      }
      _validateAppHandleOwnership(app.handle);
    }

    for (final entry in _sessions.entries) {
      final session = entry.value;
      final app = _apps[session.appId];
      final target = _targets[session.targetId];
      final appRemote = app?.handle.remoteSession;
      final appDevelopment = app?.handle.developmentSession;
      final canonicalDeviceResourceId = target?.deviceResourceId;
      if (entry.key != session.sessionId ||
          app == null ||
          target == null ||
          app.targetId != session.targetId ||
          session.environment != target.registration.environment ||
          session.deviceResourceId != canonicalDeviceResourceId ||
          appRemote == null ||
          !_sameRemoteHandle(session.remoteHandle, appRemote) ||
          !_sameOptionalDevelopmentHandle(
            session.developmentHandle,
            appDevelopment,
          ) ||
          session.resourceId !=
              cockpitCanonicalSessionResourceId(
                deviceResourceId: canonicalDeviceResourceId!,
                handle: session.remoteHandle,
              )) {
        throw FormatException(
          'Session ownership is invalid for ${session.sessionId}.',
        );
      }
    }

    for (final entry in _recordings.entries) {
      final recording = entry.value;
      final session = _sessions[recording.sessionId];
      if (entry.key != recording.recordingId ||
          session == null ||
          recording.appId != session.appId ||
          recording.resourceId != session.resourceId) {
        throw FormatException(
          'Recording ownership is invalid for ${recording.recordingId}.',
        );
      }
    }

    for (final entry in _artifacts.entries) {
      final artifact = entry.value;
      final ownerExists = switch (artifact.ownerKind) {
        'run' =>
          !requireRunAuthority || _authorizedRunIds.contains(artifact.ownerId),
        'session' => _sessions.containsKey(artifact.ownerId),
        'recording' => _recordings.containsKey(artifact.ownerId),
        _ => false,
      };
      final ownerRoot = _artifactOwnerRoot(
        artifact.ownerKind,
        artifact.ownerId,
      );
      if (entry.key != artifact.artifactId ||
          !ownerExists ||
          !p.isWithin(ownerRoot, artifact.retainedPath) ||
          artifact.kind == 'caseAttemptBundle' && artifact.ownerKind != 'run') {
        throw FormatException(
          'Artifact ownership is invalid for ${artifact.artifactId}.',
        );
      }
    }

    for (final entry in _probes.entries) {
      final probe = entry.value;
      final session = _sessions[probe.sessionId];
      if (entry.key != probe.probeId ||
          session == null ||
          session.developmentHandle == null ||
          probe.probe.sessionId !=
              session.developmentHandle!.developmentSessionId) {
        throw FormatException(
          'Probe ownership is invalid for ${probe.probeId}.',
        );
      }
    }
  }

  String _artifactOwnerRoot(String ownerKind, String ownerId) =>
      ownerKind == 'run'
      ? p.join(stateRoot, 'runs', ownerId, 'artifacts')
      : p.join(stateRoot, 'retained_artifacts', ownerKind, ownerId);

  void _validateTargetHandleOwnership(CockpitTargetHandle handle) {
    final remoteJson = handle.metadata['remoteSession'];
    if (remoteJson == null) return;
    if (remoteJson is! Map<Object?, Object?>) {
      throw const FormatException('Target remote handle ownership is invalid.');
    }
    final remote = CockpitRemoteSessionHandle.fromJson(
      Map<String, Object?>.from(remoteJson),
    );
    final metadataAppId = handle.metadata['appId'];
    if (metadataAppId is! String ||
        remote.appId != metadataAppId ||
        remote.platform != handle.platform ||
        remote.deviceId != handle.deviceId ||
        remote.projectDir != handle.projectDir ||
        remote.target != handle.target ||
        remote.baseUrl != handle.connection.baseUrl) {
      throw const FormatException('Target remote handle ownership is invalid.');
    }
  }

  void _validateAppHandleOwnership(CockpitAppHandle handle) {
    final remote = handle.remoteSession;
    if (remote != null &&
        (remote.appId != handle.appId ||
            remote.platform != handle.platform ||
            remote.deviceId != handle.deviceId ||
            remote.projectDir != handle.projectDir ||
            remote.target != handle.target ||
            remote.baseUrl != handle.baseUrl)) {
      throw FormatException('App remote handle ownership is invalid.');
    }
    final development = handle.developmentSession;
    if (development != null &&
        (development.appId != handle.appId ||
            development.platform != handle.platform ||
            development.deviceId != handle.deviceId ||
            development.projectDir != handle.projectDir ||
            development.target != handle.target ||
            development.appBaseUrl != handle.baseUrl ||
            !_sameOptionalRemoteHandle(
              development.remoteSessionHandle,
              remote,
            ))) {
      throw FormatException('App development handle ownership is invalid.');
    }
  }

  bool _projectOwnedByTarget(
    CockpitWorkerTargetBinding target,
    String projectDir,
  ) =>
      p.equals(projectDir, target.projectDir) ||
      p.isWithin(target.projectDir, projectDir);

  bool _targetHandleKindMatchesRegistration({
    required CockpitTargetKind registration,
    required CockpitTargetKind launched,
  }) =>
      registration == launched ||
      registration == CockpitTargetKind.flutterApp &&
          (launched == CockpitTargetKind.desktopApp ||
              launched == CockpitTargetKind.browserPage);

  void _validateCollectionLimit(String name, int length, int maximum) {
    if (length > maximum) {
      throw FormatException('Worker runtime $name capacity is exceeded.');
    }
  }

  Future<void> _persist() async {
    await _refreshRunArtifactAuthorities();
    _validatePersistentState();
    await _stateStore.write(_encode());
  }

  Future<void> _refreshRunArtifactAuthorities() async {
    final runIds = <String>{
      for (final artifact in _artifacts.values)
        if (artifact.ownerKind == 'run') artifact.ownerId,
    };
    await _requireOwnedRunIds(runIds);
    _authorizedRunIds
      ..clear()
      ..addAll(runIds);
  }

  _CockpitWorkerHandlePersistenceCodec get _handlePersistence =>
      _CockpitWorkerHandlePersistenceCodec(
        workspaceRoot: workspaceRoot,
        stateRoot: stateRoot,
      );

  void _replacePersistentState(Map<String, Object?> json) {
    _clearPersistentState();
    try {
      _decode(_deepCopy(json));
    } catch (_) {
      _clearPersistentState();
      rethrow;
    }
  }

  void _clearPersistentState() {
    _targets.clear();
    _apps.clear();
    _sessions.clear();
    _recordings.clear();
    _artifacts.clear();
    _probes.clear();
    _authorizedRunIds.clear();
    _snapshots.clear();
    _snapshotRefsByIdentity.clear();
  }

  Future<T> _locked<T>(Future<T> Function() action) => _serialized(() async {
    await _ensureLoaded();
    final before = _captureMemory();
    try {
      return await action();
    } catch (_) {
      _restoreMemory(before);
      rethrow;
    }
  });

  Future<T> _serialized<T>(Future<T> Function() action) {
    final previous = _tail;
    final turn = Completer<void>();
    _tail = turn.future;
    return (() async {
      await previous;
      try {
        return await action();
      } finally {
        turn.complete();
      }
    })();
  }

  _RegistryMemorySnapshot _captureMemory() => _RegistryMemorySnapshot(
    targets: Map<String, CockpitWorkerTargetBinding>.from(_targets),
    apps: Map<String, CockpitWorkerAppBinding>.from(_apps),
    sessions: Map<String, CockpitWorkerSessionBinding>.from(_sessions),
    recordings: Map<String, CockpitWorkerRecordingBinding>.from(_recordings),
    artifacts: Map<String, CockpitWorkerArtifactBinding>.from(_artifacts),
    probes: Map<String, _ProbeBinding>.from(_probes),
    authorizedRunIds: Set<String>.from(_authorizedRunIds),
    snapshots: Map<String, _SnapshotBinding>.from(_snapshots),
  );

  void _restoreMemory(_RegistryMemorySnapshot snapshot) {
    _targets
      ..clear()
      ..addAll(snapshot.targets);
    _apps
      ..clear()
      ..addAll(snapshot.apps);
    _sessions
      ..clear()
      ..addAll(snapshot.sessions);
    _recordings
      ..clear()
      ..addAll(snapshot.recordings);
    _artifacts
      ..clear()
      ..addAll(snapshot.artifacts);
    _probes
      ..clear()
      ..addAll(snapshot.probes);
    _authorizedRunIds
      ..clear()
      ..addAll(snapshot.authorizedRunIds);
    _snapshots
      ..clear()
      ..addAll(snapshot.snapshots);
    _snapshotRefsByIdentity
      ..clear()
      ..addEntries(
        _snapshots.values.map(
          (binding) => MapEntry((
            binding.sessionId,
            binding.retainedRef,
          ), binding.snapshotRef),
        ),
      );
  }

  String _newId(String prefix) =>
      _tokenGenerator.nextResourceId(prefix.substring(0, 1));

  CockpitApplicationServiceException _unknownReference(
    String kind,
    String id,
  ) => CockpitApplicationServiceException(
    code: 'opaqueReferenceNotFound',
    message: 'Worker-owned $kind reference was not found in this workspace.',
    details: <String, Object?>{'referenceId': id},
  );

  Map<String, Object?> _encode() => <String, Object?>{
    'schemaVersion': 'cockpit.worker.runtime/v4',
    'workspaceId': workspaceId,
    'targets': _targets.values
        .map((binding) => _encodeTarget(binding, _handlePersistence))
        .toList(growable: false),
    'apps': _apps.values
        .map((binding) => _encodeApp(binding, _handlePersistence))
        .toList(growable: false),
    'sessions': _sessions.values
        .map((binding) => _encodeSession(binding, _handlePersistence))
        .toList(growable: false),
    'recordings': _recordings.values
        .map(_encodeRecording)
        .toList(growable: false),
    'artifacts': _artifacts.values.map(_encodeArtifact).toList(growable: false),
    'probes': _probes.values.map(_encodeProbe).toList(growable: false),
  };

  void _decode(Map<String, Object?> json) {
    workerKeys(
      json,
      const <String>{
        'schemaVersion',
        'workspaceId',
        'targets',
        'apps',
        'sessions',
        'recordings',
        'artifacts',
        'probes',
      },
      r'$',
      required: const <String>{
        'schemaVersion',
        'workspaceId',
        'targets',
        'apps',
        'sessions',
        'recordings',
        'artifacts',
        'probes',
      },
    );
    if (json['schemaVersion'] != 'cockpit.worker.runtime/v4' ||
        json['workspaceId'] != workspaceId) {
      throw const FormatException('Worker runtime state identity is invalid.');
    }
    _decodeTargets(json['targets']);
    _decodeApps(json['apps']);
    _decodeSessions(json['sessions']);
    _decodeRecordings(json['recordings']);
    _decodeArtifacts(json['artifacts']);
    _decodeProbes(json['probes']);
    _validatePersistentState(requireRunAuthority: false);
  }

  // Decoding and encoding helpers are kept below the registry API so the
  // operation-facing ownership rules remain easy to audit.
  void _decodeTargets(Object? value) {
    final values = workerList(value, r'$.targets', maximum: maximumTargets);
    for (var index = 0; index < values.length; index += 1) {
      final path = '\$.targets[$index]';
      final json = workerObject(values[index], path);
      workerKeys(
        json,
        const <String>{
          'targetId',
          'deviceResourceId',
          'projectIdentity',
          'registration',
          'handle',
        },
        path,
        required: const <String>{
          'targetId',
          'deviceResourceId',
          'registration',
        },
      );
      final targetId = workerId(json['targetId'], '$path.targetId');
      final registrationJson = workerObject(
        json['registration'],
        '$path.registration',
      );
      workerKeys(
        registrationJson,
        const <String>{
          'workspaceId',
          'platform',
          'deviceId',
          'entrypoint',
          'entrypointSha256',
          'flavor',
          'appId',
          'wdaUrl',
          'cdpUrl',
          'targetKind',
          'mode',
          'environment',
        },
        '$path.registration',
        required: const <String>{
          'workspaceId',
          'platform',
          'deviceId',
          'targetKind',
          'mode',
          'environment',
        },
      );
      final registration = CockpitWorkerTargetRegistration(
        workspaceId: workerId(
          registrationJson['workspaceId'],
          '$path.registration.workspaceId',
        ),
        platform: workerString(
          registrationJson['platform'],
          '$path.registration.platform',
          maximum: 32,
        ),
        deviceId: workerString(
          registrationJson['deviceId'],
          '$path.registration.deviceId',
          maximum: 512,
        ),
        entrypoint: _optionalString(
          registrationJson['entrypoint'],
          '$path.registration.entrypoint',
          maximum: 4096,
        ),
        entrypointSha256: _optionalString(
          registrationJson['entrypointSha256'],
          '$path.registration.entrypointSha256',
          maximum: 64,
        ),
        flavor: _optionalString(
          registrationJson['flavor'],
          '$path.registration.flavor',
          maximum: 256,
        ),
        appId: _optionalString(
          registrationJson['appId'],
          '$path.registration.appId',
          maximum: 512,
        ),
        wdaUrl: _optionalString(
          registrationJson['wdaUrl'],
          '$path.registration.wdaUrl',
          maximum: 2048,
        ),
        cdpUrl: _optionalString(
          registrationJson['cdpUrl'],
          '$path.registration.cdpUrl',
          maximum: 2048,
        ),
        targetKind: CockpitTargetKind.fromJson(
          workerString(
            registrationJson['targetKind'],
            '$path.registration.targetKind',
            maximum: 64,
          ),
        ),
        mode: CockpitAppMode.fromJson(
          workerString(
            registrationJson['mode'],
            '$path.registration.mode',
            maximum: 32,
          ),
        ),
        environment: _targetEnvironment(
          registrationJson['environment'],
          '$path.registration.environment',
        ),
      );
      _validateRegistration(registration);
      final canonicalDeviceResourceId = cockpitCanonicalDeviceResourceId(
        platform: registration.platform,
        deviceId: registration.deviceId,
      );
      final persistedDeviceResourceId = workerId(
        json['deviceResourceId'],
        '$path.deviceResourceId',
      );
      if (persistedDeviceResourceId != canonicalDeviceResourceId) {
        throw FormatException(
          'Target physical resource identity is invalid at $path.',
        );
      }
      final project = json['projectIdentity'] == null
          ? _resolveTargetProject(registration, requireProject: false)
          : (
              projectDir: _handlePersistence._decodeWorkspaceProject(
                workerString(
                  json['projectIdentity'],
                  '$path.projectIdentity',
                  maximum: 4096,
                ),
                '$path.projectIdentity',
              ),
              launchEntrypoint: null,
            );
      final launchEntrypoint = registration.entrypoint == null
          ? null
          : p.relative(
              p.join(workspaceRoot, registration.entrypoint),
              from: project.projectDir,
            );
      if (launchEntrypoint != null &&
          (launchEntrypoint == '..' ||
              launchEntrypoint.startsWith('../') ||
              launchEntrypoint.startsWith('..${p.separator}'))) {
        throw FormatException(
          'Target entrypoint escapes its project at $path.',
        );
      }
      final handleJson = json['handle'];
      _putUnique(
        _targets,
        targetId,
        CockpitWorkerTargetBinding(
          targetId: targetId,
          deviceResourceId: canonicalDeviceResourceId,
          projectDir: project.projectDir,
          launchEntrypoint: launchEntrypoint,
          registration: registration,
          handle: handleJson == null
              ? null
              : _handlePersistence.decodeTarget(
                  workerObject(handleJson, '$path.handle'),
                  '$path.handle',
                ),
        ),
        path,
      );
    }
  }

  void _decodeApps(Object? value) {
    final values = workerList(value, r'$.apps', maximum: maximumApps);
    for (var index = 0; index < values.length; index += 1) {
      final path = '\$.apps[$index]';
      final json = workerObject(values[index], path);
      workerKeys(
        json,
        const <String>{'appId', 'targetId', 'handle', 'updatedAt'},
        path,
        required: const <String>{'appId', 'targetId', 'handle', 'updatedAt'},
      );
      final appId = workerId(json['appId'], '$path.appId');
      final targetId = workerId(json['targetId'], '$path.targetId');
      _putUnique(
        _apps,
        appId,
        CockpitWorkerAppBinding(
          appId: appId,
          targetId: targetId,
          handle: _handlePersistence.decodeApp(
            workerObject(json['handle'], '$path.handle'),
            '$path.handle',
          ),
          updatedAt: workerUtcDateTime(json['updatedAt'], '$path.updatedAt'),
        ),
        path,
      );
    }
  }

  void _decodeSessions(Object? value) {
    final values = workerList(value, r'$.sessions', maximum: maximumSessions);
    for (var index = 0; index < values.length; index += 1) {
      final path = '\$.sessions[$index]';
      final json = workerObject(values[index], path);
      workerKeys(
        json,
        const <String>{
          'sessionId',
          'appId',
          'targetId',
          'deviceResourceId',
          'resourceId',
          'remoteHandle',
          'developmentHandle',
          'environment',
          'updatedAt',
        },
        path,
        required: const <String>{
          'sessionId',
          'appId',
          'targetId',
          'deviceResourceId',
          'resourceId',
          'remoteHandle',
          'environment',
          'updatedAt',
        },
      );
      final sessionId = workerId(json['sessionId'], '$path.sessionId');
      final appId = workerId(json['appId'], '$path.appId');
      final targetId = workerId(json['targetId'], '$path.targetId');
      final remoteHandle = _handlePersistence.decodeRemote(
        workerObject(json['remoteHandle'], '$path.remoteHandle'),
        '$path.remoteHandle',
      );
      final persistedDeviceResourceId = workerId(
        json['deviceResourceId'],
        '$path.deviceResourceId',
      );
      final persistedResourceId = workerId(
        json['resourceId'],
        '$path.resourceId',
      );
      _putUnique(
        _sessions,
        sessionId,
        CockpitWorkerSessionBinding(
          sessionId: sessionId,
          appId: appId,
          targetId: targetId,
          deviceResourceId: persistedDeviceResourceId,
          resourceId: persistedResourceId,
          remoteHandle: remoteHandle,
          developmentHandle: json['developmentHandle'] == null
              ? null
              : _handlePersistence.decodeDevelopment(
                  workerObject(
                    json['developmentHandle'],
                    '$path.developmentHandle',
                  ),
                  '$path.developmentHandle',
                ),
          environment: _targetEnvironment(
            json['environment'],
            '$path.environment',
          ),
          updatedAt: workerUtcDateTime(json['updatedAt'], '$path.updatedAt'),
        ),
        path,
      );
    }
  }

  void _decodeRecordings(Object? value) {
    final values = workerList(
      value,
      r'$.recordings',
      maximum: maximumRecordings,
    );
    for (var index = 0; index < values.length; index += 1) {
      final path = '\$.recordings[$index]';
      final json = workerObject(values[index], path);
      workerKeys(
        json,
        const <String>{
          'recordingId',
          'sessionId',
          'appId',
          'resourceId',
          'createdAt',
        },
        path,
        required: const <String>{
          'recordingId',
          'sessionId',
          'appId',
          'resourceId',
          'createdAt',
        },
      );
      final recordingId = workerId(json['recordingId'], '$path.recordingId');
      final sessionId = workerId(json['sessionId'], '$path.sessionId');
      final appId = workerId(json['appId'], '$path.appId');
      final persistedResourceId = workerId(
        json['resourceId'],
        '$path.resourceId',
      );
      _putUnique(
        _recordings,
        recordingId,
        CockpitWorkerRecordingBinding(
          recordingId: recordingId,
          sessionId: sessionId,
          appId: appId,
          resourceId: persistedResourceId,
          createdAt: workerUtcDateTime(json['createdAt'], '$path.createdAt'),
        ),
        path,
      );
    }
  }

  void _decodeArtifacts(Object? value) {
    final values = workerList(value, r'$.artifacts', maximum: maximumArtifacts);
    for (var index = 0; index < values.length; index += 1) {
      final path = '\$.artifacts[$index]';
      final json = workerObject(values[index], path);
      workerKeys(
        json,
        const <String>{
          'artifactId',
          'ownerKind',
          'ownerId',
          'kind',
          'name',
          'mediaType',
          'retainedPath',
          'createdAt',
        },
        path,
        required: const <String>{
          'artifactId',
          'ownerKind',
          'ownerId',
          'kind',
          'name',
          'mediaType',
          'retainedPath',
          'createdAt',
        },
      );
      final ownerKind = workerString(
        json['ownerKind'],
        '$path.ownerKind',
        maximum: 32,
      );
      if (!const <String>{'run', 'session', 'recording'}.contains(ownerKind)) {
        throw FormatException('Invalid artifact owner at $path.ownerKind.');
      }
      final retainedPath = workerString(
        json['retainedPath'],
        '$path.retainedPath',
        maximum: 32768,
      );
      if (!_isLexicallyConfinedArtifactPath(retainedPath)) {
        throw FormatException('Invalid retained artifact path at $path.');
      }
      final name = workerString(json['name'], '$path.name', maximum: 512);
      if (name.contains('/') || name.contains(r'\')) {
        throw FormatException('Invalid artifact name at $path.name.');
      }
      final artifactId = workerId(json['artifactId'], '$path.artifactId');
      _putUnique(
        _artifacts,
        artifactId,
        CockpitWorkerArtifactBinding(
          artifactId: artifactId,
          ownerKind: ownerKind,
          ownerId: workerId(json['ownerId'], '$path.ownerId'),
          kind: workerId(json['kind'], '$path.kind'),
          name: name,
          mediaType: workerString(
            json['mediaType'],
            '$path.mediaType',
            maximum: 128,
          ),
          retainedPath: retainedPath,
          createdAt: workerUtcDateTime(json['createdAt'], '$path.createdAt'),
        ),
        path,
      );
    }
  }

  void _decodeProbes(Object? value) {
    final values = workerList(
      value,
      r'$.probes',
      maximum: maximumRetainedProbes,
    );
    for (var index = 0; index < values.length; index += 1) {
      final path = '\$.probes[$index]';
      final json = workerObject(values[index], path);
      workerKeys(
        json,
        const <String>{'probeId', 'sessionId', 'probe'},
        path,
        required: const <String>{'probeId', 'sessionId', 'probe'},
      );
      final probeId = workerId(json['probeId'], '$path.probeId');
      final sessionId = workerId(json['sessionId'], '$path.sessionId');
      _putUnique(
        _probes,
        probeId,
        _ProbeBinding(
          probeId: probeId,
          sessionId: sessionId,
          probe: CockpitDevelopmentProbe.fromJson(
            workerObject(json['probe'], '$path.probe'),
          ),
        ),
        path,
      );
    }
  }
}

bool _sameOptionalRemoteHandle(
  CockpitRemoteSessionHandle? left,
  CockpitRemoteSessionHandle? right,
) => left == null
    ? right == null
    : right != null && _sameRemoteHandle(left, right);

bool _sameRemoteHandle(
  CockpitRemoteSessionHandle left,
  CockpitRemoteSessionHandle right,
) =>
    left.platform == right.platform &&
    left.deviceId == right.deviceId &&
    left.projectDir == right.projectDir &&
    left.target == right.target &&
    left.appId == right.appId &&
    left.platformAppId == right.platformAppId &&
    left.platformAppIdKnown == right.platformAppIdKnown &&
    left.processId == right.processId &&
    left.host == right.host &&
    left.hostPort == right.hostPort &&
    left.devicePort == right.devicePort &&
    left.baseUrl == right.baseUrl &&
    left.launchedAt == right.launchedAt;

bool _sameOptionalDevelopmentHandle(
  CockpitDevelopmentSessionHandle? left,
  CockpitDevelopmentSessionHandle? right,
) => left == null
    ? right == null
    : right != null &&
          left.developmentSessionId == right.developmentSessionId &&
          left.platform == right.platform &&
          left.deviceId == right.deviceId &&
          left.projectDir == right.projectDir &&
          left.target == right.target &&
          left.appId == right.appId &&
          left.appBaseUrl == right.appBaseUrl &&
          left.supervisorBaseUrl == right.supervisorBaseUrl &&
          left.launchMode == right.launchMode &&
          _sameOptionalRemoteHandle(
            left.remoteSessionHandle,
            right.remoteSessionHandle,
          ) &&
          left.vmServiceUri == right.vmServiceUri &&
          left.launchedAt == right.launchedAt &&
          left.lastReloadAt == right.lastReloadAt &&
          left.reloadGeneration == right.reloadGeneration;

final class _RegistryMemorySnapshot {
  const _RegistryMemorySnapshot({
    required this.targets,
    required this.apps,
    required this.sessions,
    required this.recordings,
    required this.artifacts,
    required this.probes,
    required this.authorizedRunIds,
    required this.snapshots,
  });

  final Map<String, CockpitWorkerTargetBinding> targets;
  final Map<String, CockpitWorkerAppBinding> apps;
  final Map<String, CockpitWorkerSessionBinding> sessions;
  final Map<String, CockpitWorkerRecordingBinding> recordings;
  final Map<String, CockpitWorkerArtifactBinding> artifacts;
  final Map<String, _ProbeBinding> probes;
  final Set<String> authorizedRunIds;
  final Map<String, _SnapshotBinding> snapshots;
}

final class _ProbeBinding {
  const _ProbeBinding({
    required this.probeId,
    required this.sessionId,
    required this.probe,
  });

  final String probeId;
  final String sessionId;
  final CockpitDevelopmentProbe probe;
}

final class _SnapshotBinding {
  const _SnapshotBinding({
    required this.snapshotRef,
    required this.sessionId,
    required this.retainedRef,
  });

  final String snapshotRef;
  final String sessionId;
  final String retainedRef;
}

Map<String, Object?> _deepCopy(Map<String, Object?> value) =>
    workerObject(_copyJsonValue(value), r'$');

Object? _copyJsonValue(Object? value) => switch (value) {
  Map<Object?, Object?>() => <String, Object?>{
    for (final entry in value.entries)
      entry.key! as String: _copyJsonValue(entry.value),
  },
  List<Object?>() => value.map(_copyJsonValue).toList(growable: false),
  _ => value,
};

String? _optionalString(Object? value, String path, {required int maximum}) =>
    value == null ? null : workerString(value, path, maximum: maximum);

CockpitTestTargetEnvironment _targetEnvironment(Object? value, String path) {
  final name = workerString(value, path, maximum: 32);
  final matches = CockpitTestTargetEnvironment.values
      .where((candidate) => candidate.name == name)
      .toList(growable: false);
  if (matches.length != 1) {
    throw FormatException('Invalid target environment at $path.');
  }
  return matches.single;
}

void _putUnique<T>(
  Map<String, T> destination,
  String id,
  T value,
  String path,
) {
  if (destination.containsKey(id)) {
    throw FormatException('Duplicate opaque reference at $path.');
  }
  destination[id] = value;
}

final class _CockpitWorkerHandlePersistenceCodec {
  _CockpitWorkerHandlePersistenceCodec({
    required String workspaceRoot,
    required String stateRoot,
  }) : _workspaceRoot = _authorityRoot(workspaceRoot, 'workspaceRoot'),
       _stateRoot = _authorityRoot(stateRoot, 'stateRoot');

  final String _workspaceRoot;
  final String _stateRoot;

  Future<void> validateTarget(CockpitTargetHandle handle) async {
    await _validateWorkspaceProject(handle.projectDir);
    final remote = handle.metadata['remoteSession'];
    if (remote != null) {
      if (remote is! Map<Object?, Object?>) {
        throw const FormatException(
          'Target remote session metadata is invalid.',
        );
      }
      await validateRemote(
        CockpitRemoteSessionHandle.fromJson(Map<String, Object?>.from(remote)),
      );
    }
    final supervisorLogPath = handle.metadata['supervisorLogPath'];
    if (supervisorLogPath != null) {
      await _validateStateLogPath(
        workerString(
          supervisorLogPath,
          r'$.handle.metadata.supervisorLogPath',
          maximum: 32768,
        ),
      );
    }
  }

  Future<void> validateApp(CockpitAppHandle handle) async {
    await _validateWorkspaceProject(handle.projectDir);
    if (handle.supervisorLogPath case final path?) {
      await _validateStateLogPath(path);
    }
    if (handle.developmentSession case final development?) {
      await validateDevelopment(development);
    }
    if (handle.remoteSession case final remote?) {
      await validateRemote(remote);
    }
  }

  Future<void> validateDevelopment(
    CockpitDevelopmentSessionHandle handle,
  ) async {
    await _validateWorkspaceProject(handle.projectDir);
    if (handle.remoteSessionHandle case final remote?) {
      await validateRemote(remote);
    }
  }

  Future<void> validateRemote(CockpitRemoteSessionHandle handle) =>
      _validateWorkspaceProject(handle.projectDir);

  Map<String, Object?> encodeTarget(CockpitTargetHandle handle) {
    final json = Map<String, Object?>.from(handle.toJson());
    json['projectIdentity'] = _encodeWorkspaceProject(handle.projectDir);
    json.remove('projectDir');
    final metadata = Map<String, Object?>.from(handle.metadata);
    final remote = metadata['remoteSession'];
    if (remote != null) {
      if (remote is! Map<Object?, Object?>) {
        throw const FormatException(
          'Target remote session metadata is invalid.',
        );
      }
      metadata['remoteSession'] = encodeRemote(
        CockpitRemoteSessionHandle.fromJson(Map<String, Object?>.from(remote)),
      );
    }
    final supervisorLogPath = metadata.remove('supervisorLogPath');
    if (supervisorLogPath != null) {
      metadata['supervisorLogIdentity'] = _encodeStatePath(
        workerString(
          supervisorLogPath,
          r'$.handle.metadata.supervisorLogPath',
          maximum: 32768,
        ),
      );
    }
    json['metadata'] = metadata;
    return json;
  }

  CockpitTargetHandle decodeTarget(
    Map<String, Object?> persisted,
    String path,
  ) {
    final json = Map<String, Object?>.from(persisted);
    json['projectDir'] = _decodeWorkspaceProject(
      _takeIdentity(json, 'projectIdentity', 'projectDir', path),
      '$path.projectIdentity',
    );
    final metadata = workerObject(json['metadata'], '$path.metadata');
    final remote = metadata['remoteSession'];
    if (remote != null) {
      metadata['remoteSession'] = decodeRemote(
        workerObject(remote, '$path.metadata.remoteSession'),
        '$path.metadata.remoteSession',
      ).toJson();
    }
    if (metadata.containsKey('supervisorLogPath')) {
      throw FormatException(
        'Absolute supervisor log path is forbidden at $path.metadata.',
      );
    }
    final logIdentity = metadata.remove('supervisorLogIdentity');
    if (logIdentity != null) {
      metadata['supervisorLogPath'] = _decodeStatePath(
        workerString(
          logIdentity,
          '$path.metadata.supervisorLogIdentity',
          maximum: 32768,
        ),
        '$path.metadata.supervisorLogIdentity',
      );
    }
    json['metadata'] = metadata;
    return CockpitTargetHandle.fromJson(json);
  }

  Map<String, Object?> encodeApp(CockpitAppHandle handle) {
    final json = Map<String, Object?>.from(handle.toJson());
    json['projectIdentity'] = _encodeWorkspaceProject(handle.projectDir);
    json.remove('projectDir');
    json.remove('supervisorLogPath');
    if (handle.supervisorLogPath case final path?) {
      json['supervisorLogIdentity'] = _encodeStatePath(path);
    }
    if (handle.developmentSession case final development?) {
      json['developmentSession'] = encodeDevelopment(development);
    }
    if (handle.remoteSession case final remote?) {
      json['remoteSession'] = encodeRemote(remote);
    }
    return json;
  }

  CockpitAppHandle decodeApp(Map<String, Object?> persisted, String path) {
    final json = Map<String, Object?>.from(persisted);
    json['projectDir'] = _decodeWorkspaceProject(
      _takeIdentity(json, 'projectIdentity', 'projectDir', path),
      '$path.projectIdentity',
    );
    _decodeSupervisorLog(json, path);
    final development = json['developmentSession'];
    if (development != null) {
      json['developmentSession'] = decodeDevelopment(
        workerObject(development, '$path.developmentSession'),
        '$path.developmentSession',
      ).toJson();
    }
    final remote = json['remoteSession'];
    if (remote != null) {
      json['remoteSession'] = decodeRemote(
        workerObject(remote, '$path.remoteSession'),
        '$path.remoteSession',
      ).toJson();
    }
    return CockpitAppHandle.fromJson(json);
  }

  Map<String, Object?> encodeDevelopment(
    CockpitDevelopmentSessionHandle handle,
  ) {
    final json = Map<String, Object?>.from(handle.toJson());
    json['projectIdentity'] = _encodeWorkspaceProject(handle.projectDir);
    json.remove('projectDir');
    if (handle.remoteSessionHandle case final remote?) {
      json['remoteSessionHandle'] = encodeRemote(remote);
    }
    return json;
  }

  CockpitDevelopmentSessionHandle decodeDevelopment(
    Map<String, Object?> persisted,
    String path,
  ) {
    final json = Map<String, Object?>.from(persisted);
    json['projectDir'] = _decodeWorkspaceProject(
      _takeIdentity(json, 'projectIdentity', 'projectDir', path),
      '$path.projectIdentity',
    );
    final remote = json['remoteSessionHandle'];
    if (remote != null) {
      json['remoteSessionHandle'] = decodeRemote(
        workerObject(remote, '$path.remoteSessionHandle'),
        '$path.remoteSessionHandle',
      ).toJson();
    }
    return CockpitDevelopmentSessionHandle.fromJson(json);
  }

  Map<String, Object?> encodeRemote(CockpitRemoteSessionHandle handle) {
    final json = Map<String, Object?>.from(handle.toJson());
    json['projectIdentity'] = _encodeWorkspaceProject(handle.projectDir);
    json.remove('projectDir');
    return json;
  }

  CockpitRemoteSessionHandle decodeRemote(
    Map<String, Object?> persisted,
    String path,
  ) {
    final json = Map<String, Object?>.from(persisted);
    json['projectDir'] = _decodeWorkspaceProject(
      _takeIdentity(json, 'projectIdentity', 'projectDir', path),
      '$path.projectIdentity',
    );
    return CockpitRemoteSessionHandle.fromJson(json);
  }

  String _encodeWorkspaceProject(String value) =>
      _encodeIdentity(value, _workspaceRoot, allowRoot: true);

  String _encodeStatePath(String value) =>
      _encodeIdentity(value, _stateRoot, allowRoot: false);

  String _decodeWorkspaceProject(String value, String path) =>
      _decodeIdentity(value, _workspaceRoot, path, allowRoot: true);

  String _decodeStatePath(String value, String path) =>
      _decodeIdentity(value, _stateRoot, path, allowRoot: false);

  Future<void> _validateWorkspaceProject(String value) async {
    await _validateCanonicalEntity(
      value,
      root: _workspaceRoot,
      requiredType: FileSystemEntityType.directory,
      allowRoot: true,
    );
  }

  Future<void> _validateStateLogPath(String value) async {
    _encodeStatePath(value);
    final type = await FileSystemEntity.type(value, followLinks: false);
    if (type == FileSystemEntityType.file) {
      await _validateCanonicalEntity(
        value,
        root: _stateRoot,
        requiredType: FileSystemEntityType.file,
        allowRoot: false,
      );
      return;
    }
    if (type != FileSystemEntityType.notFound) {
      throw FileSystemException(
        'Persisted supervisor log has an invalid type.',
        value,
      );
    }

    var ancestor = p.dirname(value);
    while (true) {
      final ancestorType = await FileSystemEntity.type(
        ancestor,
        followLinks: false,
      );
      if (ancestorType != FileSystemEntityType.notFound) {
        if (ancestorType != FileSystemEntityType.directory) {
          throw FileSystemException(
            'Persisted supervisor log parent has an invalid type.',
            ancestor,
          );
        }
        await _validateCanonicalEntity(
          ancestor,
          root: _stateRoot,
          requiredType: FileSystemEntityType.directory,
          allowRoot: true,
        );
        return;
      }
      if (p.equals(ancestor, _stateRoot)) {
        throw FileSystemException(
          'Worker state root is unavailable.',
          _stateRoot,
        );
      }
      ancestor = p.dirname(ancestor);
    }
  }

  Future<void> _validateCanonicalEntity(
    String value, {
    required String root,
    required FileSystemEntityType requiredType,
    required bool allowRoot,
  }) async {
    final normalized = p.normalize(value);
    final confined =
        allowRoot && p.equals(normalized, root) || p.isWithin(root, normalized);
    final type = await FileSystemEntity.type(normalized, followLinks: false);
    if (!p.isAbsolute(value) ||
        normalized != value ||
        !confined ||
        type != requiredType) {
      throw FileSystemException(
        'Persisted handle entity has an invalid authority or type.',
        value,
      );
    }
    final canonical = p.normalize(
      requiredType == FileSystemEntityType.directory
          ? await Directory(normalized).resolveSymbolicLinks()
          : await File(normalized).resolveSymbolicLinks(),
    );
    if (!p.equals(canonical, normalized) ||
        !(allowRoot && p.equals(canonical, root) ||
            p.isWithin(root, canonical))) {
      throw FileSystemException(
        'Persisted handle entity escapes its worker authority.',
        value,
      );
    }
  }

  void _decodeSupervisorLog(Map<String, Object?> json, String path) {
    if (json.containsKey('supervisorLogPath')) {
      throw FormatException(
        'Absolute supervisor log path is forbidden at $path.',
      );
    }
    final identity = json.remove('supervisorLogIdentity');
    if (identity != null) {
      json['supervisorLogPath'] = _decodeStatePath(
        workerString(identity, '$path.supervisorLogIdentity', maximum: 32768),
        '$path.supervisorLogIdentity',
      );
    }
  }

  String _takeIdentity(
    Map<String, Object?> json,
    String identityKey,
    String forbiddenKey,
    String path,
  ) {
    if (json.containsKey(forbiddenKey)) {
      throw FormatException('Absolute $forbiddenKey is forbidden at $path.');
    }
    return workerString(
      json.remove(identityKey),
      '$path.$identityKey',
      minimum: 1,
      maximum: 32768,
    );
  }

  String _encodeIdentity(String value, String root, {required bool allowRoot}) {
    final normalized = p.normalize(value);
    if (!p.isAbsolute(value) || normalized != value) {
      throw const FormatException(
        'Persisted handle path must be absolute and normalized in memory.',
      );
    }
    if (p.equals(normalized, root)) {
      if (allowRoot) return '.';
      throw const FormatException(
        'Persisted handle path cannot name its root.',
      );
    }
    if (!p.isWithin(root, normalized)) {
      throw const FormatException(
        'Persisted handle path escapes its worker authority.',
      );
    }
    return p.relative(normalized, from: root);
  }

  String _decodeIdentity(
    String value,
    String root,
    String path, {
    required bool allowRoot,
  }) {
    final normalized = p.normalize(value);
    if (p.isAbsolute(value) || normalized != value) {
      throw FormatException('Handle identity is invalid at $path.');
    }
    final candidate = p.normalize(p.join(root, normalized));
    if (p.equals(candidate, root)) {
      if (allowRoot && normalized == '.') return root;
      throw FormatException('Handle identity names its authority at $path.');
    }
    if (!p.isWithin(root, candidate)) {
      throw FormatException('Handle identity escapes its authority at $path.');
    }
    return candidate;
  }

  static String _authorityRoot(String value, String name) {
    final normalized = p.normalize(value);
    if (!p.isAbsolute(value) || normalized != value) {
      throw FormatException('$name must be absolute and normalized.');
    }
    return normalized;
  }
}

Map<String, Object?> _encodeTarget(
  CockpitWorkerTargetBinding binding,
  _CockpitWorkerHandlePersistenceCodec handles,
) => <String, Object?>{
  'targetId': binding.targetId,
  'deviceResourceId': binding.deviceResourceId,
  'projectIdentity': handles._encodeWorkspaceProject(binding.projectDir),
  'registration': <String, Object?>{
    'workspaceId': binding.registration.workspaceId,
    'platform': binding.registration.platform,
    'deviceId': binding.registration.deviceId,
    if (binding.registration.entrypoint != null)
      'entrypoint': binding.registration.entrypoint,
    if (binding.registration.entrypointSha256 != null)
      'entrypointSha256': binding.registration.entrypointSha256,
    if (binding.registration.flavor != null)
      'flavor': binding.registration.flavor,
    if (binding.registration.appId != null) 'appId': binding.registration.appId,
    if (binding.registration.wdaUrl != null)
      'wdaUrl': binding.registration.wdaUrl,
    if (binding.registration.cdpUrl != null)
      'cdpUrl': binding.registration.cdpUrl,
    'targetKind': binding.registration.targetKind.name,
    'mode': binding.registration.mode.jsonValue,
    'environment': binding.registration.environment.name,
  },
  if (binding.handle != null) 'handle': handles.encodeTarget(binding.handle!),
};

Map<String, Object?> _encodeApp(
  CockpitWorkerAppBinding binding,
  _CockpitWorkerHandlePersistenceCodec handles,
) => <String, Object?>{
  'appId': binding.appId,
  'targetId': binding.targetId,
  'handle': handles.encodeApp(binding.handle),
  'updatedAt': binding.updatedAt.toUtc().toIso8601String(),
};

Map<String, Object?> _encodeSession(
  CockpitWorkerSessionBinding binding,
  _CockpitWorkerHandlePersistenceCodec handles,
) => <String, Object?>{
  'sessionId': binding.sessionId,
  'appId': binding.appId,
  'resourceId': binding.resourceId,
  'targetId': binding.targetId,
  'deviceResourceId': binding.deviceResourceId,
  'remoteHandle': handles.encodeRemote(binding.remoteHandle),
  if (binding.developmentHandle != null)
    'developmentHandle': handles.encodeDevelopment(binding.developmentHandle!),
  'environment': binding.environment.name,
  'updatedAt': binding.updatedAt.toUtc().toIso8601String(),
};

Map<String, Object?> _encodeRecording(CockpitWorkerRecordingBinding binding) =>
    <String, Object?>{
      'recordingId': binding.recordingId,
      'sessionId': binding.sessionId,
      'appId': binding.appId,
      'resourceId': binding.resourceId,
      'createdAt': binding.createdAt.toUtc().toIso8601String(),
    };

Map<String, Object?> _encodeArtifact(CockpitWorkerArtifactBinding binding) =>
    <String, Object?>{
      'artifactId': binding.artifactId,
      'ownerKind': binding.ownerKind,
      'ownerId': binding.ownerId,
      'kind': binding.kind,
      'name': binding.name,
      'mediaType': binding.mediaType,
      'retainedPath': binding.retainedPath,
      'createdAt': binding.createdAt.toUtc().toIso8601String(),
    };

const Set<String> _targetResourceKinds = <String>{
  'target.inspect',
  'app.launch',
  'target.launch',
  'session.remote.launch',
  'session.development.launch',
};

bool _targetKindRequiresAppId(CockpitTargetKind kind) => switch (kind) {
  CockpitTargetKind.nativeApp || CockpitTargetKind.desktopApp => true,
  CockpitTargetKind.browserPage ||
  CockpitTargetKind.systemSurface ||
  CockpitTargetKind.device ||
  CockpitTargetKind.hostWorkspace ||
  CockpitTargetKind.flutterApp => false,
};

const Set<String> _sessionResourceKinds = <String>{
  'session.remote.get',
  'session.remote.status',
  'snapshot.remote.read',
  'snapshot.remote.collect',
  'command.remote.execute',
  'command.remote.batch',
  'ui.remote.waitIdle',
  'session.development.get',
  'session.development.reload',
  'session.development.stop',
  'development.probe.collect',
  'ui.inspect',
  'surface.inspect',
  'logs.read',
  'network.read',
  'network.body',
  'errors.read',
  'session.logs.read',
  'evidence.screenshot.capture',
  'command.run',
  'command.batch',
  'app.reload',
  'app.restart',
  'ui.waitIdle',
  'viewport.set',
  'recording.start',
};

Map<String, Object?> _encodeProbe(_ProbeBinding binding) => <String, Object?>{
  'probeId': binding.probeId,
  'sessionId': binding.sessionId,
  'probe': binding.probe.toJson(),
};
