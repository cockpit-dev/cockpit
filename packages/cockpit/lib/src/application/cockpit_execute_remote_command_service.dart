export 'cockpit_application_service_exception.dart';

import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

import '../control_core/cockpit_control_planner.dart';
import '../control_core/cockpit_execution_plan.dart';
import '../control_core/cockpit_intent.dart';
import '../control_core/cockpit_intent_action.dart';
import '../remote/cockpit_remote_command_timeout_budget.dart';
import '../remote/cockpit_remote_session_client.dart';
import '../session/cockpit_remote_session_handle.dart';
import 'cockpit_command_evidence_defaults.dart';
import 'cockpit_interactive_result_data.dart';
import 'cockpit_interactive_result_profile.dart';
import 'cockpit_interactive_session_lock.dart';
import 'cockpit_interactive_snapshot_store.dart';
import 'cockpit_read_remote_snapshot_service.dart';
import 'cockpit_session_reference_resolver.dart';

typedef CockpitRemoteCommandExecutor =
    Future<CockpitCommandExecution> Function(
      Uri baseUri,
      CockpitCommand command,
    );
typedef CockpitCommandArtifactTempFileFactory =
    Future<File> Function(String relativePath);

final class CockpitExecuteRemoteCommandRequest {
  const CockpitExecuteRemoteCommandRequest({
    required this.command,
    this.baseUri,
    this.sessionHandle,
    this.sessionHandlePath,
    this.androidDeviceId,
    this.iosDeviceId,
    this.resultProfile = const CockpitInteractiveResultProfile.standard(),
    this.snapshotOptions,
    this.compareAgainstSnapshotRef,
    this.defaultCommandTimeout = const Duration(seconds: 30),
    this.cancellation,
  });

  final CockpitCommand command;
  final Uri? baseUri;
  final CockpitRemoteSessionHandle? sessionHandle;
  final String? sessionHandlePath;
  final String? androidDeviceId;
  final String? iosDeviceId;
  final CockpitInteractiveResultProfile resultProfile;
  final CockpitSnapshotOptions? snapshotOptions;
  final String? compareAgainstSnapshotRef;
  final Duration defaultCommandTimeout;
  final Future<void>? cancellation;
}

final class CockpitExecuteRemoteCommandResult {
  const CockpitExecuteRemoteCommandResult({
    required this.command,
    required this.artifacts,
    this.selectedPlane = CockpitPlaneKind.flutterSemanticPlane,
    this.fallbackTrail = const <CockpitPlaneKind>[],
    this.recommendedNextStep = 'continue',
    this.changed,
    this.whatMatters,
    this.uiSummary,
    this.snapshot,
    this.diagnostics,
    this.runtimeSteps = const <Map<String, Object?>>[],
    this.delta,
    this.snapshotRef,
    this.artifactDownloads = const <CockpitRemoteArtifactDownload>[],
    this.sessionHandle,
    this.effectiveSnapshotOptions,
  });

  final CockpitInteractiveCommandCore command;
  final List<CockpitInteractiveArtifactDescriptor> artifacts;
  final CockpitPlaneKind selectedPlane;
  final List<CockpitPlaneKind> fallbackTrail;
  final String recommendedNextStep;
  final bool? changed;
  final String? whatMatters;
  final CockpitInteractiveSnapshotSummary? uiSummary;
  final CockpitSnapshot? snapshot;
  final Map<String, Object?>? diagnostics;
  final List<Map<String, Object?>> runtimeSteps;
  final CockpitInteractiveSnapshotDelta? delta;
  final String? snapshotRef;
  final List<CockpitRemoteArtifactDownload> artifactDownloads;
  final CockpitRemoteSessionHandle? sessionHandle;
  final CockpitSnapshotOptions? effectiveSnapshotOptions;

  Map<String, Object?> toJson() => <String, Object?>{
    'command': command.toJson(),
    'artifacts': artifacts.map((artifact) => artifact.toJson()).toList(),
    'selectedPlane': selectedPlane.name,
    'fallbackTrail': fallbackTrail.map((planeKind) => planeKind.name).toList(),
    'recommendedNextStep': recommendedNextStep,
    if (changed != null) 'changed': changed,
    if (whatMatters != null) 'whatMatters': whatMatters,
    if (uiSummary != null) 'uiSummary': uiSummary!.toJson(),
    if (snapshot != null) 'snapshot': snapshot!.toJson(),
    if (diagnostics != null) 'diagnostics': diagnostics,
    'runtimeSteps': runtimeSteps,
    if (delta != null) 'delta': delta!.toJson(),
    if (snapshotRef != null) 'snapshotRef': snapshotRef,
    if (artifactDownloads.isNotEmpty)
      'artifactDownloads': artifactDownloads
          .map((download) => download.toJson())
          .toList(growable: false),
    if (sessionHandle != null) 'sessionHandle': sessionHandle!.toJson(),
    if (effectiveSnapshotOptions != null)
      'effectiveSnapshotOptions': effectiveSnapshotOptions!.toJson(),
  };
}

final class CockpitExecuteRemoteCommandService {
  CockpitExecuteRemoteCommandService({
    CockpitRemoteCommandExecutor? executeCommand,
    CockpitRemoteSnapshotDetailedReader? readSnapshot,
    CockpitSessionReferenceResolver? sessionReferenceResolver,
    CockpitInteractiveSnapshotStore? snapshotStore,
    CockpitInteractiveSessionLock? sessionLock,
    CockpitCommandArtifactTempFileFactory? artifactTempFileFactory,
  }) : _executeCommand = executeCommand,
       _artifactTempFileFactory =
           artifactTempFileFactory ?? _defaultCommandArtifactTempFileFactory,
       _readSnapshot =
           readSnapshot ??
           ((baseUri, options) => CockpitRemoteSessionClient(
             baseUri: baseUri,
           ).readSnapshotDetailed(options: options)),
       _sessionReferenceResolver =
           sessionReferenceResolver ?? CockpitSessionReferenceResolver(),
       _snapshotStore = snapshotStore ?? CockpitInteractiveSnapshotStore(),
       _sessionLock = sessionLock ?? CockpitInteractiveSessionLock();

  final CockpitRemoteCommandExecutor? _executeCommand;
  final CockpitRemoteSnapshotDetailedReader _readSnapshot;
  final CockpitSessionReferenceResolver _sessionReferenceResolver;
  final CockpitInteractiveSnapshotStore _snapshotStore;
  final CockpitInteractiveSessionLock _sessionLock;
  final CockpitCommandArtifactTempFileFactory _artifactTempFileFactory;

  Future<CockpitExecuteRemoteCommandResult> execute(
    CockpitExecuteRemoteCommandRequest request,
  ) async {
    final resolved = await _sessionReferenceResolver.resolve(
      baseUri: request.baseUri,
      sessionHandle: request.sessionHandle,
      sessionHandlePath: request.sessionHandlePath,
      androidDeviceId: request.androidDeviceId,
      iosDeviceId: request.iosDeviceId,
    );
    final sessionKey = resolved.baseUri.toString();

    final execution = _sessionLock.run(sessionKey, () async {
      final effectiveCommand = _withDefaultTimeout(
        cockpitCommandWithAiEvidenceDefaults(request.command),
        defaultTimeout: request.defaultCommandTimeout,
      );
      final intent = CockpitIntent.fromCommand(effectiveCommand);
      final executionPlan = CockpitControlPlanner().plan(
        intent: intent,
        capabilityProfile: _legacyFlutterCapabilityProfile(intent),
      );
      final execution = await _executeCommandWithContext(
        resolved.baseUri,
        effectiveCommand,
        cancellation: request.cancellation,
      );
      final evidenceExecution = await _withPersistedMetadataArtifacts(
        execution,
        request.resultProfile.artifacts,
      );
      final effectiveSnapshotOptions =
          request.resultProfile.requiresPostActionSnapshotRead(
            compareAgainstSnapshot: request.compareAgainstSnapshotRef != null,
          )
          ? request.resultProfile.resolveSnapshotOptions(
              request.snapshotOptions ?? effectiveCommand.snapshotOptions,
            )
          : null;
      final snapshotResponse = effectiveSnapshotOptions == null
          ? null
          : await cockpitReadRemoteSnapshotConsistently(
              baseUri: resolved.baseUri,
              options: effectiveSnapshotOptions,
              readSnapshot: _readSnapshot,
            );
      final snapshot = snapshotResponse?.snapshot;
      final baseline = request.compareAgainstSnapshotRef == null
          ? null
          : _snapshotStore.read(
              request.compareAgainstSnapshotRef!,
              sessionKey: sessionKey,
            );
      final snapshotRef =
          snapshot == null || !request.resultProfile.emitsSnapshotRef
          ? null
          : _snapshotStore.put(sessionKey: sessionKey, snapshot: snapshot);

      return CockpitExecuteRemoteCommandResult(
        command: CockpitInteractiveCommandCore.fromResult(
          evidenceExecution.result,
        ),
        artifacts: cockpitInteractiveArtifactsFromExecution(
          evidenceExecution,
          request.resultProfile.artifacts,
        ),
        selectedPlane: executionPlan.selectedPlane,
        fallbackTrail: executionPlan.fallbackChain,
        recommendedNextStep: _recommendedNextStep(
          execution: execution,
          executionPlan: executionPlan,
        ),
        changed: evidenceExecution.result.changed,
        whatMatters: _whatMatters(evidenceExecution.result),
        uiSummary: snapshot == null || !request.resultProfile.emitsUiSummary
            ? null
            : cockpitInteractiveSummarizeSnapshot(snapshot),
        snapshot: request.resultProfile.emitsInlineSnapshot ? snapshot : null,
        diagnostics: snapshot == null
            ? null
            : cockpitInteractiveDiagnosticsFromSnapshot(
                snapshot,
                request.resultProfile.diagnostics,
              ),
        runtimeSteps: request.resultProfile.emitsRuntimeSteps
            ? evidenceExecution.runtimeSteps
                  .map((step) => (step.toJson()))
                  .toList(growable: false)
            : const <Map<String, Object?>>[],
        delta: snapshot == null || baseline == null
            ? null
            : cockpitInteractiveDiffSnapshots(baseline.snapshot, snapshot),
        snapshotRef: snapshotRef,
        artifactDownloads:
            snapshotResponse?.artifactDownloads ??
            const <CockpitRemoteArtifactDownload>[],
        sessionHandle: resolved.sessionHandle,
        effectiveSnapshotOptions: effectiveSnapshotOptions,
      );
    });
    final cancellation = request.cancellation;
    if (cancellation == null) return execution;
    return Future.any<CockpitExecuteRemoteCommandResult>(
      <Future<CockpitExecuteRemoteCommandResult>>[
        execution,
        cancellation.then<CockpitExecuteRemoteCommandResult>((_) {
          throw const CockpitRemoteCommandCancelledException();
        }),
      ],
    );
  }

  Future<CockpitCommandExecution> _executeCommandWithContext(
    Uri baseUri,
    CockpitCommand command, {
    Future<void>? cancellation,
  }) async {
    try {
      final executeCommand = _executeCommand;
      if (executeCommand != null) {
        final execution = executeCommand(baseUri, command);
        return cancellation == null
            ? await execution
            : await Future.any<CockpitCommandExecution>(
                <Future<CockpitCommandExecution>>[
                  execution,
                  cancellation.then<CockpitCommandExecution>((_) {
                    throw const CockpitRemoteCommandCancelledException();
                  }),
                ],
              );
      }
      return await CockpitRemoteSessionClient(
        baseUri: baseUri,
        requestTimeout: cockpitRemoteCommandTransportTimeoutForCommand(command),
        artifactTempFileFactory: _artifactTempFileFactory,
      ).executeDetailed(command, cancellation: cancellation);
    } on CockpitApplicationServiceException catch (error) {
      throw CockpitApplicationServiceException(
        code: error.code,
        message: error.message,
        details: <String, Object?>{
          ...error.details,
          'commandId': command.commandId,
          'commandType': command.commandType.name,
          if (command.timeoutMs != null) 'timeoutMs': command.timeoutMs,
        },
      );
    }
  }

  Future<CockpitCommandExecution> _withPersistedMetadataArtifacts(
    CockpitCommandExecution execution,
    CockpitInteractiveArtifactLevel artifactLevel,
  ) async {
    if (artifactLevel != CockpitInteractiveArtifactLevel.metadata) {
      return execution;
    }

    final artifactSourcePaths = <String, String>{
      ...execution.artifactSourcePaths,
    };
    for (final entry in execution.artifactPayloads.entries) {
      if (artifactSourcePaths.containsKey(entry.key)) {
        continue;
      }
      final bytes = entry.value;
      if (bytes.isEmpty) {
        continue;
      }
      final file = await _artifactTempFileFactory(entry.key);
      await file.parent.create(recursive: true);
      if (await file.exists()) {
        await file.delete();
      }
      await file.writeAsBytes(bytes, flush: true);
      artifactSourcePaths[entry.key] = file.path;
    }

    final persisted = CockpitCommandExecution(
      result: execution.result,
      artifactPayloads: execution.artifactPayloads,
      artifactSourcePaths: artifactSourcePaths,
      runtimeSteps: execution.runtimeSteps,
    );
    _requireMetadataArtifactEvidence(persisted);
    return persisted;
  }

  void _requireMetadataArtifactEvidence(CockpitCommandExecution execution) {
    for (final artifact in execution.result.artifacts) {
      if (!_isRequiredEvidenceArtifact(artifact)) {
        continue;
      }
      final payload = execution.artifactPayloads[artifact.relativePath];
      if (payload != null && payload.isNotEmpty) {
        continue;
      }
      final sourcePath = execution.artifactSourcePaths[artifact.relativePath];
      if (sourcePath != null && sourcePath.isNotEmpty) {
        try {
          final file = File(sourcePath);
          if (file.existsSync() && file.lengthSync() > 0) {
            continue;
          }
        } on Object {
          // Fall through to a structured failure below.
        }
      }

      throw CockpitApplicationServiceException(
        code: 'requiredArtifactEvidenceMissing',
        message:
            'Command result declared required screenshot evidence without non-empty bytes or a readable source file.',
        details: <String, Object?>{
          'commandId': execution.result.commandId,
          'commandType': execution.result.commandType.name,
          'artifactRole': artifact.role,
          'artifactPath': artifact.relativePath,
          if (sourcePath != null && sourcePath.isNotEmpty)
            'sourcePath': sourcePath,
        },
      );
    }
  }

  static CockpitCommand _withDefaultTimeout(
    CockpitCommand command, {
    required Duration defaultTimeout,
  }) {
    if (command.timeoutMs != null && command.timeoutMs! > 0) {
      return command;
    }
    final recommendedTimeout = _recommendedCommandTimeout(
      command,
      defaultTimeout: defaultTimeout,
    );
    return command.copyWith(timeoutMs: recommendedTimeout.inMilliseconds);
  }

  static Duration _recommendedCommandTimeout(
    CockpitCommand command, {
    required Duration defaultTimeout,
  }) {
    var recommended = defaultTimeout;
    final parameterTimeoutMs = _positiveInt(command.parameters['timeoutMs']);
    switch (command.commandType) {
      case CockpitCommandType.scrollUntilVisible:
        recommended = _maxDuration(
          recommended,
          _recommendedScrollUntilVisibleTimeout(command),
        );
      case CockpitCommandType.waitFor ||
          CockpitCommandType.waitForUiIdle ||
          CockpitCommandType.waitForNetworkIdle:
        if (parameterTimeoutMs != null) {
          recommended = _maxDuration(
            recommended,
            Duration(milliseconds: parameterTimeoutMs),
          );
        }
      default:
        if (parameterTimeoutMs != null) {
          recommended = _maxDuration(
            recommended,
            Duration(milliseconds: parameterTimeoutMs),
          );
        }
    }
    return recommended;
  }

  static Duration _recommendedScrollUntilVisibleTimeout(
    CockpitCommand command,
  ) {
    final maxScrolls = _positiveInt(command.parameters['maxScrolls']) ?? 12;
    final durationPerStepMs =
        _positiveInt(command.parameters['durationPerStepMs']) ?? 220;
    final probeSegments = _recommendedScrollProbeSegments(command);
    final revealRequested =
        command.parameters['revealAlignment'] != null ||
        (_positiveNum(command.parameters['revealPadding']) ?? 0) > 0 ||
        (_positiveNum(command.parameters['revealPaddingPx']) ?? 0) > 0;
    final continuous = command.parameters['continuous'] == true;
    final carriesEvidence = cockpitRemoteCommandCarriesEvidence(command);
    final explicitScrollable =
        command.parameters['scrollableKey'] != null ||
        command.parameters['scrollLocator'] != null ||
        command.parameters['scrollableLocator'] != null;
    final directionBudget = 2;
    final candidateBudget = explicitScrollable ? 1 : 2;

    final perProbeBudgetMs = durationPerStepMs + (revealRequested ? 420 : 320);
    final perStepBudgetMs =
        probeSegments * perProbeBudgetMs + (continuous ? 500 : 0);
    final searchBudget = maxScrolls * directionBudget * candidateBudget;
    final stepBudgetMs = searchBudget * perStepBudgetMs;
    final revealBudgetMs = revealRequested ? searchBudget * 350 : 0;
    final evidenceBudgetMs = carriesEvidence
        ? 4500 + (command.screenshotRequest?.includeSnapshot == true ? 1800 : 0)
        : 0;

    return Duration(
      milliseconds: stepBudgetMs + revealBudgetMs + evidenceBudgetMs + 1800,
    );
  }

  static int? _positiveInt(Object? value) {
    if (value is int && value > 0) {
      return value;
    }
    if (value is num) {
      final normalized = value.toInt();
      return normalized > 0 ? normalized : null;
    }
    return null;
  }

  static double? _positiveNum(Object? value) {
    if (value is num && value > 0) {
      return value.toDouble();
    }
    return null;
  }

  static int _recommendedScrollProbeSegments(CockpitCommand command) {
    if (command.locator == null) {
      return 1;
    }
    final viewportFraction =
        (_positiveNum(command.parameters['viewportFraction']) ?? 0.8)
            .clamp(0.1, 0.95)
            .toDouble();
    if (viewportFraction < 0.4) {
      return 1;
    }
    return (viewportFraction / 0.2).floor().clamp(1, 4);
  }

  static Duration _maxDuration(Duration left, Duration right) {
    return left >= right ? left : right;
  }

  static bool _isRequiredEvidenceArtifact(CockpitArtifactRef artifact) {
    return artifact.role == 'screenshot' || artifact.role == 'step_screenshot';
  }

  static CockpitCapabilityProfile _legacyFlutterCapabilityProfile(
    CockpitIntent intent,
  ) {
    return CockpitCapabilityProfile(
      targetKind: CockpitTargetKind.flutterApp,
      surfaceKinds: <CockpitSurfaceKind>{
        CockpitSurfaceKind.flutterSemantic,
        CockpitSurfaceKind.nativeUi,
      },
      actionCapabilities: <CockpitActionCapability>{
        CockpitActionCapability.tap,
        CockpitActionCapability.typeText,
        CockpitActionCapability.captureScreenshot,
        CockpitActionCapability.readLogs,
      },
      evidenceCapabilities: <CockpitEvidenceCapability>{
        CockpitEvidenceCapability.flutterScreenshot,
        if (intent.action == CockpitIntentAction.captureScreenshot)
          CockpitEvidenceCapability.nativeScreenshot,
      },
    );
  }

  static String _recommendedNextStep({
    required CockpitCommandExecution execution,
    required CockpitExecutionPlan executionPlan,
  }) {
    if (!execution.result.success) {
      return 'inspectFailureDiagnostics';
    }
    if (executionPlan.requiresObservation) {
      return 'readPostActionState';
    }
    if (executionPlan.requiresEvidence) {
      return 'reviewCapturedEvidence';
    }
    return 'continue';
  }

  static String? _whatMatters(CockpitCommandResult result) {
    if (result.error != null) {
      return result.error!.message;
    }
    if (result.degradationReason != null &&
        result.degradationReason!.isNotEmpty) {
      return result.degradationReason;
    }
    if (result.usedCaptureFallback) {
      return 'Capture completed with a fallback path.';
    }
    return null;
  }
}

Future<File> _defaultCommandArtifactTempFileFactory(String relativePath) async {
  final directory = await Directory.systemTemp.createTemp(
    'flutter_cockpit_command_artifacts_',
  );
  final basename = p.basename(relativePath);
  final safeBasename = basename
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return File(
    p.join(
      directory.path,
      safeBasename.isEmpty ? 'artifact.bin' : safeBasename,
    ),
  );
}
