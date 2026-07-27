import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

import '../application/cockpit_app_handle.dart';
import '../application/cockpit_application_service_exception.dart';
import '../application/cockpit_collect_development_probe_service.dart';
import '../application/cockpit_compare_development_probe_service.dart';
import '../application/cockpit_launch_app_service.dart';
import '../application/cockpit_launch_development_session_service.dart';
import '../application/cockpit_launch_target_service.dart';
import '../application/cockpit_interactive_result_profile.dart';
import '../application/cockpit_read_app_service.dart';
import '../application/cockpit_read_target_service.dart';
import '../application/cockpit_stop_app_service.dart';
import '../development/cockpit_development_probe.dart';
import '../development/cockpit_development_session_handle.dart';
import '../development/cockpit_development_session_status.dart';
import '../session/cockpit_flutter_launch_configuration.dart';
import '../system_control/cockpit_system_control_action_service.dart';
import '../system_control/cockpit_system_control_service.dart';
import '../targets/cockpit_target_handle.dart';
import 'cockpit_worker_application_support.dart';
import 'cockpit_worker_development_session_runtime.dart';
import 'cockpit_worker_forwarded_port_handoff.dart';
import 'cockpit_worker_resource_grant.dart';
import 'cockpit_worker_runtime_registry.dart';
import 'cockpit_workspace_operation_registry.dart';

final class CockpitWorkerLifecycleOperations {
  CockpitWorkerLifecycleOperations({
    required this.workspaceId,
    required CockpitWorkerRuntimeRegistry registry,
    required CockpitWorkerTargetResolver targets,
    required CockpitWorkerForwardedPortHandoff portHandoff,
    required CockpitWorkerDevelopmentSessionRuntime developmentRuntime,
    CockpitLaunchAppService? launchAppService,
    CockpitLaunchTargetService? launchTargetService,
    CockpitStopAppService? stopAppService,
    CockpitReadAppService? readAppService,
    CockpitReadTargetService? readTargetService,
    CockpitCollectDevelopmentProbeService? collectProbeService,
    CockpitCompareDevelopmentProbeService? compareProbeService,
    CockpitSystemControlService? systemControlService,
    CockpitSystemControlActionService? systemActionService,
  }) : _registry = registry,
       _targets = targets,
       _portHandoff = portHandoff,
       _developmentRuntime = developmentRuntime,
       _launchApp = launchAppService ?? CockpitLaunchAppService(),
       _launchTarget =
           launchTargetService ??
           CockpitLaunchTargetService(launchAppService: launchAppService),
       _stopApp = stopAppService ?? CockpitStopAppService(),
       _readApp = readAppService ?? CockpitReadAppService(),
       _readTarget = readTargetService ?? CockpitReadTargetService(),
       _collectProbe =
           collectProbeService ?? CockpitCollectDevelopmentProbeService(),
       _compareProbe =
           compareProbeService ??
           const CockpitCompareDevelopmentProbeService() {
    _systemControl = systemControlService ?? CockpitSystemControlService();
    _systemAction =
        systemActionService ??
        CockpitSystemControlActionService(systemControlService: _systemControl);
  }

  static const Set<String> kinds = <String>{
    'app.list',
    'app.get',
    'target.list',
    'target.get',
    'target.inspect',
    'app.launch',
    'target.launch',
    'app.stop',
    'session.development.launch',
    'session.development.get',
    'session.development.reload',
    'session.development.stop',
    'development.probe.collect',
    'development.probe.compare',
  };

  final String workspaceId;
  final CockpitWorkerRuntimeRegistry _registry;
  final CockpitWorkerTargetResolver _targets;
  final CockpitWorkerForwardedPortHandoff _portHandoff;
  final CockpitWorkerDevelopmentSessionRuntime _developmentRuntime;
  final CockpitLaunchAppService _launchApp;
  final CockpitLaunchTargetService _launchTarget;
  final CockpitStopAppService _stopApp;
  final CockpitReadAppService _readApp;
  final CockpitReadTargetService _readTarget;
  final CockpitCollectDevelopmentProbeService _collectProbe;
  final CockpitCompareDevelopmentProbeService _compareProbe;
  late final CockpitSystemControlService _systemControl;
  late final CockpitSystemControlActionService _systemAction;

  Future<Map<String, Object?>> execute({
    required String kind,
    required Map<String, Object?> input,
    required CockpitWorkspaceOperationContext context,
    required List<CockpitWorkerResourceGrant> grants,
    required CockpitWorkerResultSanitizer sanitizer,
  }) => switch (kind) {
    'app.list' => _listApps(input),
    'app.get' => _getApp(input, context, grants, sanitizer),
    'target.list' => _listTargets(input),
    'target.get' => _getTargetResource(input),
    'target.inspect' => _inspectTarget(input, context, grants, sanitizer),
    'app.launch' => _launchApplication(input, context, grants, sanitizer),
    'target.launch' => _launchTargetOperation(
      input,
      context,
      grants,
      sanitizer,
    ),
    'app.stop' => _stopApplication(input, context, grants, sanitizer),
    'session.development.launch' => _launchDevelopmentSession(
      input,
      context,
      grants,
      sanitizer,
    ),
    'session.development.get' => _getDevelopmentSession(
      input,
      context,
      grants,
      sanitizer,
    ),
    'session.development.reload' => _reloadDevelopmentSession(
      input,
      context,
      grants,
      sanitizer,
    ),
    'session.development.stop' => _stopDevelopmentSession(
      input,
      context,
      grants,
      sanitizer,
    ),
    'development.probe.collect' => _collectDevelopmentProbe(
      input,
      context,
      grants,
      sanitizer,
    ),
    'development.probe.compare' => _compareDevelopmentProbes(
      input,
      context,
      sanitizer,
    ),
    _ => throw StateError('Lifecycle operation routing is inconsistent.'),
  };

  Future<Map<String, Object?>> _listApps(Map<String, Object?> input) async {
    CockpitWorkerApplicationInput(input, allowed: const <String>{});
    final apps = await _registry.listApps();
    return <String, Object?>{
      'apps': <Map<String, Object?>>[
        for (final app in apps)
          <String, Object?>{
            'appId': app.appId,
            'targetId': app.targetId,
            'mode': app.handle.mode.jsonValue,
            'platform': app.handle.platform,
            'supportsHotReload': app.handle.supportsHotReload,
            'updatedAt': app.updatedAt.toUtc().toIso8601String(),
          },
      ],
    };
  }

  Future<Map<String, Object?>> _listTargets(Map<String, Object?> input) async {
    CockpitWorkerApplicationInput(input, allowed: const <String>{});
    final targets = await _registry.listTargets();
    final sessionIds = await _registry.latestSessionIdsByTarget();
    return <String, Object?>{
      'targets': <Map<String, Object?>>[
        for (final target in targets)
          _targetResource(target, sessionIds[target.targetId]).toJson(),
      ],
    };
  }

  Future<Map<String, Object?>> _getTargetResource(
    Map<String, Object?> input,
  ) async {
    final values = CockpitWorkerApplicationInput(
      input,
      allowed: const <String>{'targetId'},
      required: const <String>{'targetId'},
    );
    final target = await _registry.readTarget(values.id('targetId'));
    final sessionId = (await _registry
        .latestSessionIdsByTarget())[target.targetId];
    return <String, Object?>{
      'target': _targetResource(target, sessionId).toJson(),
    };
  }

  Future<Map<String, Object?>> _getApp(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) async {
    final values = CockpitWorkerApplicationInput(
      input,
      allowed: const <String>{'appId', 'profile', 'snapshotOptions'},
      required: const <String>{'appId'},
    );
    final app = await _registry.requireApp(values.id('appId'));
    final sessionId = await _registry.sessionIdForApp(app.appId);
    final session = await _registry.requireSession(sessionId);
    requireWorkerResourceGrant(
      context: context,
      grants: grants,
      kind: CockpitLeaseResourceKind.session,
      resourceId: session.resourceId,
    );
    final result = await runWorkerApplicationOperation(
      context: context,
      operation: () => _readApp.read(
        CockpitReadAppRequest(
          app: app.handle,
          resultProfile: values.profile(
            defaultName: CockpitInteractiveResultProfileName.minimal,
          ),
          snapshotOptions: values.optionalSnapshotOptions(),
        ),
      ),
    );
    return sanitizer.sanitize(
      result.toJson(),
      appId: app.appId,
      sessionId: sessionId,
      targetId: app.targetId,
    );
  }

  Future<Map<String, Object?>> _inspectTarget(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) async {
    final values = CockpitWorkerApplicationInput(
      input,
      allowed: const <String>{'targetId', 'profile', 'snapshotOptions'},
      required: const <String>{'targetId'},
    );
    final binding = await _targets.requireTarget(
      workspaceId: workspaceId,
      targetId: values.id('targetId'),
    );
    requireWorkerResourceGrant(
      context: context,
      grants: grants,
      kind: CockpitLeaseResourceKind.device,
      resourceId: binding.deviceResourceId,
    );
    final handle = binding.handle;
    if (handle == null && binding.registration.usesSystemControl) {
      final result = await runWorkerApplicationOperation(
        context: context,
        operation: () => _systemControl.describe(
          CockpitSystemControlDescribeRequest(
            platform: binding.registration.platform,
            deviceId: binding.registration.deviceId,
            appId: binding.registration.appId,
            metadata: <String, Object?>{
              if (binding.registration.wdaUrl != null)
                'wdaUrl': binding.registration.wdaUrl,
            },
          ),
        ),
      );
      return <String, Object?>{
        'targetId': binding.targetId,
        'targetKind': binding.registration.targetKind.name,
        ...result.profile.toJson(),
        'recommendedNextStep': result.recommendedNextStep,
      };
    }
    if (handle == null) {
      throw const CockpitApplicationServiceException(
        code: 'targetNotLaunched',
        message: 'Worker target has not been launched.',
      );
    }
    final result = await runWorkerApplicationOperation(
      context: context,
      operation: () => _readTarget.read(
        CockpitReadTargetRequest(
          target: handle,
          resultProfile: values.profile(
            defaultName: CockpitInteractiveResultProfileName.minimal,
          ),
          snapshotOptions: values.optionalSnapshotOptions(),
        ),
      ),
    );
    final latestApp = await _registry.latestAppForTarget(binding.targetId);
    final sessionId = latestApp == null
        ? null
        : await _registry.sessionIdForApp(latestApp.appId);
    Map<String, Object?>? systemControl;
    if (latestApp != null) {
      final described = await runWorkerApplicationOperation(
        context: context,
        operation: () => _systemControl.describe(
          CockpitSystemControlDescribeRequest(
            platform: binding.registration.platform,
            deviceId: binding.registration.deviceId,
            appId: latestApp.handle.platformAppId ?? binding.registration.appId,
            processId: latestApp.handle.processId,
            metadata: <String, Object?>{
              if (binding.registration.wdaUrl != null)
                'wdaUrl': binding.registration.wdaUrl,
            },
          ),
        ),
      );
      systemControl = await sanitizer.sanitize(
        described.profile.toJson(),
        sessionId: sessionId,
        targetId: binding.targetId,
      );
    }
    return <String, Object?>{
      'targetId': binding.targetId,
      'platform': binding.registration.platform,
      'targetKind': result.target.targetKind.name,
      'capabilityProfile': result.capabilityProfile.toJson(),
      'foregroundSurface': result.foregroundSurface.name,
      'selectedPlane': result.selectedPlane.name,
      'fallbackTrail': result.fallbackTrail
          .map((plane) => plane.name)
          .toList(growable: false),
      'recommendedNextStep': result.recommendedNextStep,
      'systemControl': ?systemControl,
      if (result.whatMatters != null) 'whatMatters': result.whatMatters,
      if (result.currentRouteName != null)
        'currentRouteName': result.currentRouteName,
      if (result.uiSummary != null) 'uiSummary': result.uiSummary!.toJson(),
      if (result.snapshot != null) 'snapshot': result.snapshot!.toJson(),
      if (result.snapshotRef != null)
        'snapshotRef': (await sanitizer.sanitize(
          <String, Object?>{'snapshotRef': result.snapshotRef},
          sessionId: sessionId,
          targetId: binding.targetId,
        ))['snapshotRef'],
    };
  }

  Future<Map<String, Object?>> _launchApplication(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) async {
    final values = _launchInput(input);
    final target = await _launchTargetBinding(values, context, grants);
    final mode = _appMode(values.optionalString('mode', maximum: 32), target);
    final timeout = _launchTimeout(
      values,
      context,
      const Duration(minutes: 10),
    );
    final launchConfiguration = _launchConfiguration(values);
    final portGrant = requireForwardedPortGrant(
      workspaceId: workspaceId,
      grants: grants,
      deadline: context.deadline,
    );
    if (mode == CockpitAppMode.development) {
      return _launchWorkerDevelopmentSession(
        target: target,
        context: context,
        portGrant: portGrant,
        timeout: timeout,
        sanitizer: sanitizer,
        launchConfiguration: launchConfiguration,
      );
    }
    return runWorkerTransactionalPortLaunch<
      CockpitLaunchAppResult,
      Map<String, Object?>
    >(
      handoff: _portHandoff,
      grant: portGrant,
      deadline: context.deadline,
      launch: (port) => runWorkerApplicationOperation(
        context: context,
        operation: () => _launchApp.launch(
          CockpitLaunchAppRequest(
            projectDir: target.projectDir,
            target: target.registration.entrypoint,
            flavor: target.registration.flavor,
            platform: target.registration.platform,
            deviceId: target.registration.deviceId,
            sessionPort: port,
            mode: mode,
            launchTimeout: timeout,
            allowSessionPortFallback: false,
            launchConfiguration: launchConfiguration,
          ),
        ),
      ),
      commit: (result) => _recordLaunchedApp(
        result.app,
        target.targetId,
        result.toJson(),
        sanitizer,
      ),
      rollback: (result) => _rollbackLaunchedApp(result.app),
    );
  }

  Future<Map<String, Object?>> _launchTargetOperation(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) async {
    final values = _launchInput(input);
    final target = await _launchTargetBinding(values, context, grants);
    final launchConfiguration = _launchConfiguration(values);
    if (target.registration.usesSystemControl) {
      if (values.optionalString('mode', maximum: 32) != null) {
        throw const FormatException(
          'mode applies only to entrypoint-backed Flutter target launches.',
        );
      }
      if (!launchConfiguration.isEmpty) {
        throw const FormatException(
          'launchConfiguration applies only to entrypoint-backed Flutter '
          'target launches.',
        );
      }
      return runWorkerTransactionalApplicationLaunch<
        CockpitSystemControlActionResult,
        Map<String, Object?>
      >(
        context: context,
        launch: () async {
          final result = await _systemAction.run(
            CockpitSystemControlActionRequest(
              platform: target.registration.platform,
              deviceId: target.registration.deviceId,
              appId: target.registration.appId,
              metadata: <String, Object?>{
                if (target.registration.wdaUrl != null)
                  'wdaUrl': target.registration.wdaUrl,
              },
              action: CockpitSystemControlAction.activateWindow,
              timeout: _launchTimeout(
                values,
                context,
                const Duration(seconds: 30),
              ),
            ),
          );
          if (!result.success) {
            throw CockpitApplicationServiceException(
              code: result.errorCode ?? 'targetLaunchFailed',
              message:
                  result.errorMessage ?? 'System target activation failed.',
              details: <String, Object?>{
                'availability': result.availability.name,
                'recommendedNextStep': result.recommendedNextStep,
              },
            );
          }
          return result;
        },
        commit: (result) => _recordLaunchedSystemTarget(
          target: target,
          activation: result,
          sanitizer: sanitizer,
        ),
        rollback: (result) => _rollbackLaunchedSystemTarget(target, result),
      );
    }
    final mode = _appMode(values.optionalString('mode', maximum: 32), target);
    final timeout = _launchTimeout(values, context, const Duration(minutes: 2));
    final portGrant = requireForwardedPortGrant(
      workspaceId: workspaceId,
      grants: grants,
      deadline: context.deadline,
    );
    if (mode == CockpitAppMode.development &&
        target.registration.targetKind == CockpitTargetKind.flutterApp) {
      return _launchWorkerDevelopmentSession(
        target: target,
        context: context,
        portGrant: portGrant,
        timeout: timeout,
        sanitizer: sanitizer,
        includeTarget: true,
        launchConfiguration: launchConfiguration,
      );
    }
    return runWorkerTransactionalPortLaunch<
      CockpitLaunchTargetResult,
      Map<String, Object?>
    >(
      handoff: _portHandoff,
      grant: portGrant,
      deadline: context.deadline,
      launch: (port) => runWorkerApplicationOperation(
        context: context,
        operation: () => _launchTarget.launch(
          CockpitLaunchTargetRequest(
            projectDir: target.projectDir,
            target: target.registration.entrypoint,
            flavor: target.registration.flavor,
            platform: target.registration.platform,
            deviceId: target.registration.deviceId,
            sessionPort: port,
            targetKind: target.registration.targetKind,
            mode: mode,
            launchTimeout: timeout,
            allowSessionPortFallback: false,
            launchConfiguration: launchConfiguration,
          ),
        ),
      ),
      commit: (result) async {
        final app = result.app;
        if (app == null) {
          await _registry.recordTargetHandle(
            targetId: target.targetId,
            handle: result.target,
          );
          return <String, Object?>{
            'targetId': target.targetId,
            'targetKind': result.target.targetKind.name,
            'platform': result.target.platform,
            if (result.recommendedNextStep != null)
              'recommendedNextStep': result.recommendedNextStep,
            if (result.whatMatters != null) 'whatMatters': result.whatMatters,
          };
        }
        return _recordLaunchedApp(
          app,
          target.targetId,
          result.toJson(),
          sanitizer,
          targetHandle: result.target,
        );
      },
      rollback: (result) async {
        if (result.app case final app?) await _rollbackLaunchedApp(app);
      },
    );
  }

  Future<Map<String, Object?>> _stopApplication(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) async {
    final values = CockpitWorkerApplicationInput(
      input,
      allowed: const <String>{'appId'},
      required: const <String>{'appId'},
    );
    final app = await _registry.requireApp(values.id('appId'));
    final sessionId = await _registry.sessionIdForApp(app.appId);
    final session = await _registry.requireSession(sessionId);
    requireWorkerResourceGrant(
      context: context,
      grants: grants,
      kind: CockpitLeaseResourceKind.session,
      resourceId: session.resourceId,
    );
    late final Map<String, Object?> result;
    if (session.developmentHandle case final developmentHandle?) {
      final stopped = await runWorkerApplicationOperation(
        context: context,
        operation: () => _developmentRuntime.stop(developmentHandle),
      );
      result = <String, Object?>{
        'app': app.handle.toJson(),
        'status': stopped.status.toJson(),
      };
    } else {
      final stopped = await runWorkerApplicationOperation(
        context: context,
        operation: () => _stopApp.stop(CockpitStopAppRequest(app: app.handle)),
      );
      result = stopped.toJson();
    }
    await _registry.removeApp(app.appId);
    return sanitizer.sanitize(
      result,
      appId: app.appId,
      sessionId: sessionId,
      targetId: app.targetId,
    );
  }

  Future<Map<String, Object?>> _launchDevelopmentSession(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) async {
    final values = _launchInput(input, allowMode: false);
    final target = await _launchTargetBinding(values, context, grants);
    final timeout = _launchTimeout(values, context, const Duration(minutes: 2));
    final launchConfiguration = _launchConfiguration(values);
    final portGrant = requireForwardedPortGrant(
      workspaceId: workspaceId,
      grants: grants,
      deadline: context.deadline,
    );
    return _launchWorkerDevelopmentSession(
      target: target,
      context: context,
      portGrant: portGrant,
      timeout: timeout,
      sanitizer: sanitizer,
      launchConfiguration: launchConfiguration,
    );
  }

  Future<Map<String, Object?>> _getDevelopmentSession(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) async {
    final values = _sessionInput(input);
    final session = await _registry.requireSession(values.id('sessionId'));
    requireWorkerResourceGrant(
      context: context,
      grants: grants,
      kind: CockpitLeaseResourceKind.session,
      resourceId: session.resourceId,
    );
    final handle = _developmentHandle(session);
    final result = await runWorkerApplicationOperation(
      context: context,
      operation: () => _developmentRuntime.query(handle),
    );
    return sanitizer.sanitize(
      <String, Object?>{
        'sessionId': session.sessionId,
        'appId': session.appId,
        'targetId': session.targetId,
        'status': result.status.toJson(),
        'recommendedNextStep': _recommendedDevelopmentNextStep(result.status),
      },
      sessionId: session.sessionId,
      appId: session.appId,
      targetId: session.targetId,
    );
  }

  Future<Map<String, Object?>> _reloadDevelopmentSession(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) async {
    final values = CockpitWorkerApplicationInput(
      input,
      allowed: const <String>{'sessionId', 'mode'},
      required: const <String>{'sessionId'},
    );
    final session = await _registry.requireSession(values.id('sessionId'));
    requireWorkerResourceGrant(
      context: context,
      grants: grants,
      kind: CockpitLeaseResourceKind.session,
      resourceId: session.resourceId,
    );
    final result = await runWorkerApplicationOperation(
      context: context,
      operation: () => _developmentRuntime.reload(
        _developmentHandle(session),
        _reloadMode(values.optionalString('mode', maximum: 32)),
      ),
    );
    await _registry.updateDevelopmentSession(session.sessionId, result.handle);
    return sanitizer.sanitize(
      <String, Object?>{
        'sessionId': session.sessionId,
        'appId': session.appId,
        'targetId': session.targetId,
        'status': result.status.toJson(),
      },
      sessionId: session.sessionId,
      appId: session.appId,
      targetId: session.targetId,
    );
  }

  Future<Map<String, Object?>> _stopDevelopmentSession(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) async {
    final values = _sessionInput(input);
    final session = await _registry.requireSession(values.id('sessionId'));
    requireWorkerResourceGrant(
      context: context,
      grants: grants,
      kind: CockpitLeaseResourceKind.session,
      resourceId: session.resourceId,
    );
    final result = await runWorkerApplicationOperation(
      context: context,
      operation: () => _developmentRuntime.stop(_developmentHandle(session)),
    );
    await _registry.removeApp(session.appId);
    return sanitizer.sanitize(
      <String, Object?>{
        'sessionId': session.sessionId,
        'appId': session.appId,
        'targetId': session.targetId,
        'status': result.status.toJson(),
      },
      sessionId: session.sessionId,
      appId: session.appId,
      targetId: session.targetId,
    );
  }

  Future<Map<String, Object?>> _collectDevelopmentProbe(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
    CockpitWorkerResultSanitizer sanitizer,
  ) async {
    final values = CockpitWorkerApplicationInput(
      input,
      allowed: const <String>{'sessionId', 'profile', 'reason', 'checkpoint'},
      required: const <String>{'sessionId'},
    );
    final session = await _registry.requireSession(values.id('sessionId'));
    requireWorkerResourceGrant(
      context: context,
      grants: grants,
      kind: CockpitLeaseResourceKind.session,
      resourceId: session.resourceId,
    );
    final result = await runWorkerApplicationOperation(
      context: context,
      operation: () => _collectProbe.collect(
        CockpitCollectDevelopmentProbeRequest(
          sessionHandle: _developmentHandle(session),
          profile: CockpitDevelopmentProbeProfile.fromJson(
            values.optionalString('profile', maximum: 32) ?? 'quick',
          ),
          reason: CockpitDevelopmentProbeReason.fromJson(
            values.optionalString('reason', maximum: 32) ?? 'manual',
          ),
          checkpoint: values.optionalString('checkpoint', maximum: 256),
        ),
      ),
    );
    final probeId = await _registry.recordProbe(
      sessionId: session.sessionId,
      probe: result.probe,
    );
    return sanitizer.sanitize(
      result.toJson(),
      sessionId: session.sessionId,
      appId: session.appId,
      targetId: session.targetId,
      probeIds: <String, String>{result.probe.probeId: probeId},
    );
  }

  Future<Map<String, Object?>> _compareDevelopmentProbes(
    Map<String, Object?> input,
    CockpitWorkspaceOperationContext context,
    CockpitWorkerResultSanitizer sanitizer,
  ) async {
    final values = CockpitWorkerApplicationInput(
      input,
      allowed: const <String>{'sessionId', 'fromProbeId', 'toProbeId'},
      required: const <String>{'sessionId', 'fromProbeId', 'toProbeId'},
    );
    final sessionId = values.id('sessionId');
    final session = await _registry.requireSession(sessionId);
    final fromId = values.id('fromProbeId');
    final toId = values.id('toProbeId');
    final from = await _registry.requireProbe(
      sessionId: sessionId,
      probeId: fromId,
    );
    final to = await _registry.requireProbe(
      sessionId: sessionId,
      probeId: toId,
    );
    final result = await runWorkerApplicationOperation(
      context: context,
      operation: () => _compareProbe.compare(
        CockpitCompareDevelopmentProbeRequest(fromProbe: from, toProbe: to),
      ),
    );
    return sanitizer.sanitize(
      result.toJson(),
      sessionId: sessionId,
      appId: session.appId,
      targetId: session.targetId,
      probeIds: <String, String>{from.probeId: fromId, to.probeId: toId},
    );
  }

  CockpitWorkerApplicationInput _launchInput(
    Map<String, Object?> input, {
    bool allowMode = true,
  }) => CockpitWorkerApplicationInput(
    input,
    allowed: <String>{
      'targetId',
      'launchTimeoutMs',
      'launchConfiguration',
      if (allowMode) 'mode',
    },
    required: const <String>{'targetId'},
  );

  CockpitFlutterLaunchConfiguration _launchConfiguration(
    CockpitWorkerApplicationInput input,
  ) {
    final value = input.optionalObject('launchConfiguration');
    return value == null
        ? CockpitFlutterLaunchConfiguration.empty
        : CockpitFlutterLaunchConfiguration.fromJson(value);
  }

  CockpitWorkerApplicationInput _sessionInput(Map<String, Object?> input) =>
      CockpitWorkerApplicationInput(
        input,
        allowed: const <String>{'sessionId'},
        required: const <String>{'sessionId'},
      );

  Future<CockpitWorkerTargetBinding> _launchTargetBinding(
    CockpitWorkerApplicationInput input,
    CockpitWorkspaceOperationContext context,
    List<CockpitWorkerResourceGrant> grants,
  ) async {
    final targetId = input.id('targetId');
    final target = await _targets.requireTarget(
      workspaceId: workspaceId,
      targetId: targetId,
    );
    requireWorkerResourceGrant(
      context: context,
      grants: grants,
      kind: CockpitLeaseResourceKind.device,
      resourceId: target.deviceResourceId,
    );
    return target;
  }

  CockpitAppMode _appMode(
    String? requested,
    CockpitWorkerTargetBinding target,
  ) => requested == null
      ? target.registration.mode
      : CockpitAppMode.fromJson(requested);

  Duration _launchTimeout(
    CockpitWorkerApplicationInput input,
    CockpitWorkspaceOperationContext context,
    Duration defaultValue,
  ) => boundedWorkerDuration(
    context: context,
    requestedMilliseconds: input.optionalInteger(
      'launchTimeoutMs',
      minimum: 1,
      maximum: 1800000,
    ),
    defaultValue: defaultValue,
    maximum: const Duration(minutes: 30),
  );

  CockpitDevelopmentReloadMode _reloadMode(String? value) => switch (value) {
    null || 'hot_reload' => CockpitDevelopmentReloadMode.hotReload,
    'hot_restart' => CockpitDevelopmentReloadMode.hotRestart,
    _ => throw const FormatException('Invalid development reload mode.'),
  };

  CockpitAutomationTargetResource _targetResource(
    CockpitWorkerTargetBinding target,
    String? sessionId,
  ) => CockpitAutomationTargetResource(
    targetId: target.targetId,
    workspaceId: workspaceId,
    platform: target.registration.platform,
    deviceId: target.registration.deviceId,
    targetKind: target.registration.targetKind,
    mode: CockpitAutomationTargetMode.values.byName(
      target.registration.mode.jsonValue,
    ),
    environment: CockpitAutomationTargetEnvironment.values.byName(
      target.registration.environment.name,
    ),
    entrypoint: target.registration.entrypoint == null
        ? null
        : p.posix.joinAll(p.split(target.registration.entrypoint!)),
    entrypointSha256: target.registration.entrypointSha256,
    flavor: target.registration.flavor,
    appId: target.registration.appId,
    sessionId: sessionId,
  );

  Future<Map<String, Object?>> _launchWorkerDevelopmentSession({
    required CockpitWorkerTargetBinding target,
    required CockpitWorkspaceOperationContext context,
    required CockpitWorkerResourceGrant portGrant,
    required Duration timeout,
    required CockpitWorkerResultSanitizer sanitizer,
    required CockpitFlutterLaunchConfiguration launchConfiguration,
    bool includeTarget = false,
  }) =>
      runWorkerTransactionalPortLaunch<
        CockpitLaunchDevelopmentSessionResult,
        Map<String, Object?>
      >(
        handoff: _portHandoff,
        grant: portGrant,
        deadline: context.deadline,
        launch: (port) => runWorkerApplicationOperation(
          context: context,
          operation: () => _developmentRuntime.launch(
            CockpitLaunchDevelopmentSessionRequest(
              projectDir: target.projectDir,
              target: target.registration.entrypoint,
              flavor: target.registration.flavor,
              platform: target.registration.platform,
              deviceId: target.registration.deviceId,
              sessionPort: port,
              launchTimeout: timeout,
              allowSessionPortFallback: false,
              launchConfiguration: launchConfiguration,
            ),
          ),
        ),
        commit: (result) =>
            _recordLaunchedApp(result.app, target.targetId, <String, Object?>{
              if (includeTarget)
                'target': CockpitTargetHandle.fromAppHandle(
                  result.app,
                ).toJson(),
              'app': result.app.toJson(),
              'status': result.status.toJson(),
            }, sanitizer),
        rollback: (result) => _rollbackLaunchedApp(result.app),
      );

  String _recommendedDevelopmentNextStep(
    CockpitDevelopmentSessionStatus status,
  ) => switch (status.state) {
    CockpitDevelopmentSessionState.ready => 'ready_for_incremental_probe',
    CockpitDevelopmentSessionState.starting ||
    CockpitDevelopmentSessionState.reloading ||
    CockpitDevelopmentSessionState.restarting => 'wait_for_ready',
    CockpitDevelopmentSessionState.stopped => 'launch_development_session',
    CockpitDevelopmentSessionState.failed => 'relaunch_development_session',
  };

  CockpitDevelopmentSessionHandle _developmentHandle(
    CockpitWorkerSessionBinding session,
  ) =>
      session.developmentHandle ??
      (throw const CockpitApplicationServiceException(
        code: 'developmentSessionRequired',
        message: 'Operation requires a worker-owned development session.',
      ));

  Future<Map<String, Object?>> _recordLaunchedApp(
    CockpitAppHandle app,
    String targetId,
    Map<String, Object?> result,
    CockpitWorkerResultSanitizer sanitizer, {
    CockpitTargetHandle? targetHandle,
  }) async {
    final binding = await _registry.recordLaunchedApp(
      targetId: targetId,
      targetHandle: targetHandle ?? CockpitTargetHandle.fromAppHandle(app),
      appHandle: app,
    );
    try {
      final sessionId = await _registry.sessionIdForApp(binding.appId);
      final sanitized = await sanitizer.sanitize(
        result,
        appId: binding.appId,
        sessionId: sessionId,
        targetId: targetId,
      );
      return sanitized
        ..['appId'] = binding.appId
        ..['sessionId'] = sessionId
        ..['targetId'] = targetId;
    } on Object catch (primary, primaryStackTrace) {
      try {
        await _registry.removeApp(binding.appId);
      } on Object catch (cleanupError) {
        throw CockpitWorkerOperationRollbackException(
          primary: primary,
          cleanupError: cleanupError,
          warningCode: 'runtimeRegistrationRollbackFailed',
          warningMessage:
              'Failed to remove a partially registered application.',
        );
      }
      Error.throwWithStackTrace(primary, primaryStackTrace);
    }
  }

  Future<Map<String, Object?>> _recordLaunchedSystemTarget({
    required CockpitWorkerTargetBinding target,
    required CockpitSystemControlActionResult activation,
    required CockpitWorkerResultSanitizer sanitizer,
  }) async {
    final binding = await _registry.recordSystemTargetLaunch(
      targetId: target.targetId,
      launchedAt: DateTime.now().toUtc(),
      processId: activation.processId,
    );
    try {
      final sessionId = await _registry.sessionIdForApp(binding.appId);
      final sanitized = await sanitizer.sanitize(
        <String, Object?>{
          'targetId': target.targetId,
          'targetKind': target.registration.targetKind.name,
          'platform': target.registration.platform,
          'activation': activation.toJson(),
        },
        appId: binding.appId,
        sessionId: sessionId,
        targetId: target.targetId,
      );
      return sanitized
        ..['appId'] = binding.appId
        ..['sessionId'] = sessionId
        ..['targetId'] = target.targetId;
    } on Object catch (primary, primaryStackTrace) {
      try {
        await _registry.removeApp(binding.appId);
      } on Object catch (cleanupError) {
        throw CockpitWorkerOperationRollbackException(
          primary: primary,
          cleanupError: cleanupError,
          warningCode: 'runtimeRegistrationRollbackFailed',
          warningMessage:
              'Failed to remove a partially registered system application.',
        );
      }
      Error.throwWithStackTrace(primary, primaryStackTrace);
    }
  }

  Future<void> _rollbackLaunchedApp(CockpitAppHandle app) async {
    if (app.developmentSession case final development?) {
      try {
        await _developmentRuntime.stop(development);
        return;
      } on Object {
        await _stopApp.stop(CockpitStopAppRequest(app: app));
        return;
      }
    }
    await _stopApp.stop(CockpitStopAppRequest(app: app));
  }

  Future<void> _rollbackLaunchedSystemTarget(
    CockpitWorkerTargetBinding target,
    CockpitSystemControlActionResult activation,
  ) async {
    final result = await _systemAction.run(
      CockpitSystemControlActionRequest(
        platform: target.registration.platform,
        deviceId: target.registration.deviceId,
        appId: target.registration.appId,
        processId: activation.processId,
        metadata: <String, Object?>{
          if (target.registration.wdaUrl != null)
            'wdaUrl': target.registration.wdaUrl,
        },
        action: CockpitSystemControlAction.terminateApp,
      ),
    );
    if (!result.success) {
      throw CockpitApplicationServiceException(
        code: result.errorCode ?? 'targetLaunchRollbackFailed',
        message:
            result.errorMessage ??
            'System target termination failed during launch rollback.',
        details: <String, Object?>{
          'availability': result.availability.name,
          'recommendedNextStep': result.recommendedNextStep,
        },
      );
    }
  }
}
