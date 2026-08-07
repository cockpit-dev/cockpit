import 'package:collection/collection.dart';

import '../context/cockpit_context_bundle.dart';
import '../capture/cockpit_capture_kind.dart';
import '../model/cockpit_environment.dart';
import '../model/cockpit_observation.dart';
import '../model/cockpit_run_manifest.dart';
import '../model/cockpit_step_record.dart';
import '../model/cockpit_task_status.dart';
import '../network/cockpit_network_entry.dart';
import '../runtime/cockpit_plane_kind.dart';
import '../runtime/cockpit_runtime_event.dart';
import '../runtime/cockpit_surface_kind.dart';
import '../runtime/cockpit_target_kind.dart';
import 'cockpit_evidence_index.dart';
import 'cockpit_session.dart';
import 'cockpit_timestamp_provider.dart';

final class CockpitBundleSummaryAssembler {
  /// Creates a CockpitBundleSummaryAssembler.
  CockpitBundleSummaryAssembler({CockpitTimestampProvider? now})
    : _now = now ?? _systemNow;

  final CockpitTimestampProvider _now;

  CockpitContextBundle assemble({
    required CockpitSession session,
    required CockpitEnvironment environment,
    required List<CockpitStepRecord> steps,
    required CockpitTaskStatus status,
    required List<String> capabilitiesUsed,
    String? failureSummary,
  }) {
    final evidenceIndex = CockpitEvidenceIndex.fromSteps(steps);
    final executionSummary = _summarizeExecutionContext(steps);
    final recordingFailureReason = _lastRecordingFailureReason(steps);
    final networkSummary = _summarizeNetworkActivity(steps);
    final deliveryArtifactFailureCodes = _deliveryArtifactFailureCodes(
      evidenceIndex,
    );
    final recordingEvidenceRequired = _recordingEvidenceRequired(
      evidenceIndex: evidenceIndex,
      steps: steps,
      recordingFailureReason: recordingFailureReason,
    );
    final deliveryVideoFailureCodes = _deliveryVideoFailureCodes(
      evidenceIndex: evidenceIndex,
      recordingFailureReason: recordingFailureReason,
      recordingEvidenceRequired: recordingEvidenceRequired,
    );
    final deliveryValidationFailureCodes = _combinedFailureCodes(
      deliveryArtifactFailureCodes,
      deliveryVideoFailureCodes,
    );
    final screenshotReady = evidenceIndex.deliveryArtifactsReady;
    final recordingReadyOrExplained =
        !recordingEvidenceRequired || evidenceIndex.deliveryVideoReady;
    final deliveryValidated = screenshotReady && recordingReadyOrExplained;
    final commandCount = steps.where((step) => step.commandType != null).length;
    final runtimeSummary = _summarizeRuntimeActivity(steps);
    final runtimeEventCount = runtimeSummary?.totalEntryCount ?? 0;
    final runtimeErrorCount = runtimeSummary?.errorCount ?? 0;
    final runtimeWarningCount = runtimeSummary?.warningCount ?? 0;
    final effectiveStatus =
        status == CockpitTaskStatus.completed && runtimeErrorCount > 0
        ? CockpitTaskStatus.failed
        : status;
    final effectiveFailureSummary =
        effectiveStatus == CockpitTaskStatus.failed &&
            failureSummary == null &&
            runtimeErrorCount > 0
        ? 'Runtime errors were captured during the task.'
        : failureSummary;
    final targetReachable = session.sessionId.isNotEmpty;
    final intendedPlaneWorked = executionSummary.fallbackCount == 0;
    final postconditionsSatisfied =
        effectiveStatus != CockpitTaskStatus.failed && runtimeErrorCount == 0;
    final artifactsReady = deliveryValidated;
    final logsCollected =
        networkSummary != null ||
        runtimeSummary != null ||
        steps.any(_hasDiagnosticsEvidence);
    final deliveryReadable =
        steps.isNotEmpty ||
        evidenceIndex.artifactRefs.isNotEmpty ||
        runtimeSummary != null ||
        networkSummary != null;
    final fallbackAcceptable =
        intendedPlaneWorked || (postconditionsSatisfied && deliveryReadable);
    final manifest = CockpitRunManifest(
      sessionId: session.sessionId,
      taskId: session.taskId,
      platform: session.platform,
      status: effectiveStatus,
      startedAt: session.startedAt,
      finishedAt: _now().toUtc(),
      artifactRefs: evidenceIndex.artifactRefs,
      failureSummary: effectiveFailureSummary,
      targetKind: executionSummary.targetKind,
      primaryExecutionPlane: executionSummary.primaryExecutionPlane,
      planesUsed: executionSummary.planesUsed,
      surfaceKindsUsed: executionSummary.surfaceKindsUsed,
      fallbackCount: executionSummary.fallbackCount,
      capabilitiesUsed: capabilitiesUsed,
      commandCount: commandCount,
      screenshotCount: evidenceIndex.screenshotCount,
      failureCount: evidenceIndex.failureCount,
      nativeScreenshotCount: evidenceIndex.nativeScreenshotCount,
      flutterScreenshotCount: evidenceIndex.flutterScreenshotCount,
      deliveryArtifactsReady: evidenceIndex.deliveryArtifactsReady,
      deliveryArtifactFailureCodes: deliveryArtifactFailureCodes,
      recordingCount: evidenceIndex.recordingCount,
      nativeRecordingCount: evidenceIndex.nativeRecordingCount,
      deliveryVideoReady: evidenceIndex.deliveryVideoReady,
      deliveryVideoFailureCodes: deliveryVideoFailureCodes,
      runtimeEventCount: runtimeEventCount,
      runtimeErrorCount: runtimeErrorCount,
      runtimeWarningCount: runtimeWarningCount,
    );
    final observations = steps
        .map((step) => step.observation)
        .whereType<CockpitObservation>()
        .toList(growable: false);
    final handoff = <String, Object?>{
      'sessionId': session.sessionId,
      'taskId': session.taskId,
      'platform': session.platform,
      'status': effectiveStatus.name,
      if (executionSummary.targetKind != null)
        'targetKind': executionSummary.targetKind!.name,
      if (executionSummary.primaryExecutionPlane != null)
        'primaryExecutionPlane': executionSummary.primaryExecutionPlane!.name,
      if (executionSummary.planesUsed.isNotEmpty)
        'planesUsed': executionSummary.planesUsed
            .map((plane) => plane.name)
            .toList(),
      if (executionSummary.surfaceKindsUsed.isNotEmpty)
        'surfaceKindsUsed': executionSummary.surfaceKindsUsed
            .map((surface) => surface.name)
            .toList(),
      'fallbackCount': executionSummary.fallbackCount,
      'stepCount': steps.length,
      'capabilitiesUsed': capabilitiesUsed,
      'commandCount': commandCount,
      'screenshotCount': evidenceIndex.screenshotCount,
      'failureCount': evidenceIndex.failureCount,
      'nativeScreenshotCount': evidenceIndex.nativeScreenshotCount,
      'flutterScreenshotCount': evidenceIndex.flutterScreenshotCount,
      'deliveryArtifactsReady': evidenceIndex.deliveryArtifactsReady,
      'deliveryArtifactFailureCodes': deliveryArtifactFailureCodes,
      'recordingCount': evidenceIndex.recordingCount,
      'nativeRecordingCount': evidenceIndex.nativeRecordingCount,
      'deliveryVideoReady': evidenceIndex.deliveryVideoReady,
      'deliveryVideoFailureCodes': deliveryVideoFailureCodes,
      'screenshotReady': screenshotReady,
      'recordingReadyOrExplained': recordingReadyOrExplained,
      'deliveryValidated': deliveryValidated,
      'gates': <String, Object?>{
        'targetReachable': targetReachable,
        'intendedPlaneWorked': intendedPlaneWorked,
        'fallbackAcceptable': fallbackAcceptable,
        'postconditionsSatisfied': postconditionsSatisfied,
        'artifactsReady': artifactsReady,
        'logsCollected': logsCollected,
        'deliveryReadable': deliveryReadable,
        'screenshotReady': screenshotReady,
        'recordingReadyOrExplained': recordingReadyOrExplained,
        'deliveryValidated': deliveryValidated,
      },
      'gateFailureCodes': <String, Object?>{
        'targetReachable': targetReachable
            ? const <String>[]
            : const <String>['targetUnreachable'],
        'intendedPlaneWorked': intendedPlaneWorked
            ? const <String>[]
            : const <String>['fallbackRequired'],
        'fallbackAcceptable': fallbackAcceptable
            ? const <String>[]
            : _combinedFailureCodes(
                intendedPlaneWorked
                    ? const <String>[]
                    : const <String>['fallbackRequired'],
                _combinedFailureCodes(
                  postconditionsSatisfied
                      ? const <String>[]
                      : const <String>['postconditionsNotSatisfied'],
                  artifactsReady
                      ? const <String>[]
                      : deliveryValidationFailureCodes,
                ),
              ),
        'postconditionsSatisfied': postconditionsSatisfied
            ? const <String>[]
            : <String>[
                if (runtimeErrorCount > 0)
                  'runtimeErrorsDetected'
                else
                  'taskFailed',
              ],
        'artifactsReady': artifactsReady
            ? const <String>[]
            : deliveryValidationFailureCodes,
        'logsCollected': logsCollected
            ? const <String>[]
            : const <String>['logsNotCollected'],
        'deliveryReadable': deliveryReadable
            ? const <String>[]
            : const <String>['deliveryUnreadable'],
        'screenshotReady': deliveryArtifactFailureCodes,
        'recordingReadyOrExplained': deliveryVideoFailureCodes,
        'deliveryValidated': deliveryValidationFailureCodes,
      },
      'runtimeEventCount': runtimeEventCount,
      'runtimeErrorCount': runtimeErrorCount,
      'runtimeWarningCount': runtimeWarningCount,
      'recordingFailureReason': ?recordingFailureReason,
      'failureSummary': ?effectiveFailureSummary,
    };

    return CockpitContextBundle(
      manifest: manifest,
      environment: environment,
      steps: steps,
      observations: observations,
      acceptanceMarkdown: _buildAcceptanceMarkdown(
        session: session,
        steps: steps,
        executionSummary: executionSummary,
        evidenceIndex: evidenceIndex,
        status: effectiveStatus,
        failureSummary: effectiveFailureSummary,
        networkSummary: networkSummary,
        runtimeSummary: runtimeSummary,
      ),
      handoff: handoff,
      delivery: <String, Object?>{
        'summary': effectiveStatus == CockpitTaskStatus.completed
            ? 'Ready for user delivery'
            : 'Delivery blocked by task failure',
        'primaryScreenshotRef': evidenceIndex.primaryScreenshotRef.isEmpty
            ? null
            : evidenceIndex.primaryScreenshotRef,
        'attachmentRefs': evidenceIndex.screenshotRefs,
        'deliveryArtifactsReady': evidenceIndex.deliveryArtifactsReady,
        'primaryRecordingRef': evidenceIndex.primaryRecordingRef.isEmpty
            ? null
            : evidenceIndex.primaryRecordingRef,
        'videoAttachmentRefs': evidenceIndex.recordingRefs,
        'deliveryVideoReady': evidenceIndex.deliveryVideoReady,
        'artifactFailureCodes': deliveryArtifactFailureCodes,
        'videoFailureCodes': deliveryVideoFailureCodes,
        'readiness': <String, Object?>{
          'artifacts': <String, Object?>{
            'ready': evidenceIndex.deliveryArtifactsReady,
            'failureCodes': deliveryArtifactFailureCodes,
          },
          'video': <String, Object?>{
            'ready': evidenceIndex.deliveryVideoReady,
            'failureCodes': deliveryVideoFailureCodes,
            'failureReason': ?recordingFailureReason,
          },
        },
      },
    );
  }

  String _buildAcceptanceMarkdown({
    required CockpitSession session,
    required List<CockpitStepRecord> steps,
    required _CockpitExecutionSummary executionSummary,
    required CockpitEvidenceIndex evidenceIndex,
    required CockpitTaskStatus status,
    String? failureSummary,
    _CockpitAcceptanceNetworkSummary? networkSummary,
    _CockpitAcceptanceRuntimeSummary? runtimeSummary,
  }) {
    final lastRecordingFailure = steps
        .where((step) => step.actionType == 'recording_failed')
        .map((step) => step.actionArgs['failureReason'] as String?)
        .whereType<String>()
        .lastOrNull;
    final buffer = StringBuffer()
      ..writeln('# Acceptance')
      ..writeln()
      ..writeln('- Session: ${session.sessionId}')
      ..writeln('- Task: ${session.taskId}')
      ..writeln('- Platform: ${session.platform}')
      ..writeln(
        '- Target kind: ${executionSummary.targetKind?.name ?? 'unknown'}',
      )
      ..writeln(
        '- Primary plane: ${executionSummary.primaryExecutionPlane?.name ?? 'unknown'}',
      )
      ..writeln('- Fallback count: ${executionSummary.fallbackCount}')
      ..writeln('- Status: ${status.name}')
      ..writeln('- Steps: ${steps.length}');

    if (failureSummary != null) {
      buffer.writeln('- Failure: $failureSummary');
    }

    buffer.writeln();
    buffer.writeln('## Recording');
    if (evidenceIndex.recordingRefs.isNotEmpty) {
      buffer.writeln();
      buffer.writeln(
        '- Acceptance video: ${evidenceIndex.recordingRefs.first}',
      );
      buffer.writeln(
        '- Recording count: ${evidenceIndex.recordingRefs.length}',
      );
    } else {
      buffer.writeln();
      buffer.writeln('- Recording unavailable');
      if (lastRecordingFailure != null) {
        buffer.writeln('- Recording failure: $lastRecordingFailure');
      }
    }

    if (networkSummary != null) {
      buffer.writeln();
      buffer.writeln('## Network');
      buffer.writeln();
      buffer.writeln('- Requests captured: ${networkSummary.totalEntryCount}');
      buffer.writeln('- Failures: ${networkSummary.failureCount}');
      if (networkSummary.recentEntries.isNotEmpty) {
        final latest = networkSummary.recentEntries.first;
        buffer.writeln(
          '- Latest request: ${latest.method} ${latest.uri} · ${latest.statusCode ?? 'pending'}',
        );
      }
      if (networkSummary.failingEntries.isNotEmpty) {
        final latestFailure = networkSummary.failingEntries.first;
        buffer.writeln(
          '- Latest failure: ${latestFailure.method} ${latestFailure.uri} · ${latestFailure.statusCode ?? latestFailure.error ?? 'failed'}',
        );
      }
    }

    if (runtimeSummary != null) {
      buffer.writeln();
      buffer.writeln('## Runtime');
      buffer.writeln();
      buffer.writeln('- Events captured: ${runtimeSummary.totalEntryCount}');
      buffer.writeln('- Errors: ${runtimeSummary.errorCount}');
      buffer.writeln('- Warnings: ${runtimeSummary.warningCount}');
      if (runtimeSummary.recentEntries.isNotEmpty) {
        final latest = runtimeSummary.recentEntries.first;
        buffer.writeln(
          '- Latest event: ${latest.kind.jsonValue} ${latest.message}',
        );
      }
      if (runtimeSummary.errorEntries.isNotEmpty) {
        final latestError = runtimeSummary.errorEntries.first;
        buffer.writeln(
          '- Latest error: ${latestError.kind.jsonValue} ${latestError.message}',
        );
      }
    }

    return buffer.toString().trimRight();
  }

  String? _lastRecordingFailureReason(List<CockpitStepRecord> steps) {
    return steps
        .where((step) => step.actionType == 'recording_failed')
        .map((step) => step.actionArgs['failureReason'] as String?)
        .whereType<String>()
        .lastOrNull;
  }

  List<String> _deliveryArtifactFailureCodes(
    CockpitEvidenceIndex evidenceIndex,
  ) {
    if (evidenceIndex.deliveryArtifactsReady) {
      return const <String>[];
    }
    if (evidenceIndex.screenshotCount == 0 ||
        evidenceIndex.primaryScreenshotRef.isEmpty) {
      return const <String>['primaryScreenshotMissing'];
    }
    return const <String>['acceptanceScreenshotMissing'];
  }

  List<String> _deliveryVideoFailureCodes({
    required CockpitEvidenceIndex evidenceIndex,
    required String? recordingFailureReason,
    required bool recordingEvidenceRequired,
  }) {
    if (!recordingEvidenceRequired) {
      return const <String>[];
    }
    if (evidenceIndex.deliveryVideoReady) {
      return const <String>[];
    }
    if (recordingFailureReason != null && recordingFailureReason.isNotEmpty) {
      return const <String>['recordingFailed'];
    }
    if (evidenceIndex.recordingCount == 0 ||
        evidenceIndex.primaryRecordingRef.isEmpty) {
      return const <String>['primaryRecordingMissing'];
    }
    return const <String>['acceptanceRecordingMissing'];
  }

  bool _recordingEvidenceRequired({
    required CockpitEvidenceIndex evidenceIndex,
    required List<CockpitStepRecord> steps,
    required String? recordingFailureReason,
  }) {
    return evidenceIndex.deliveryVideoReady ||
        evidenceIndex.recordingCount > 0 ||
        evidenceIndex.primaryRecordingRef.isNotEmpty ||
        (recordingFailureReason != null && recordingFailureReason.isNotEmpty) ||
        steps.any((step) => step.actionType.startsWith('recording_'));
  }

  List<String> _combinedFailureCodes(List<String> left, List<String> right) {
    return List<String>.unmodifiable(<String>{...left, ...right});
  }

  bool _hasDiagnosticsEvidence(CockpitStepRecord step) {
    if (step.snapshot?.diagnosticsArtifactRef != null ||
        step.observation?.diagnosticsArtifactRef != null) {
      return true;
    }
    return step.artifactRefs.any((artifact) => artifact.role == 'diagnostics');
  }

  _CockpitExecutionSummary _summarizeExecutionContext(
    List<CockpitStepRecord> steps,
  ) {
    CockpitTargetKind? targetKind;
    final planesUsed = <CockpitPlaneKind>[];
    final surfaceKindsUsed = <CockpitSurfaceKind>[];
    var fallbackCount = 0;

    void addPlane(CockpitPlaneKind? plane) {
      if (plane != null && !planesUsed.contains(plane)) {
        planesUsed.add(plane);
      }
    }

    void addSurface(CockpitSurfaceKind? surface) {
      if (surface != null && !surfaceKindsUsed.contains(surface)) {
        surfaceKindsUsed.add(surface);
      }
    }

    for (final step in steps) {
      targetKind ??= step.targetKind ?? step.observation?.targetKind;
      final executionPlane =
          step.executionPlane ??
          step.observation?.executionPlane ??
          _inferExecutionPlane(step);
      final surfaceKind =
          step.surfaceKind ??
          step.observation?.surfaceKind ??
          _inferSurfaceKind(step);
      addPlane(executionPlane);
      addSurface(surfaceKind);
      for (final fallbackPlane in step.fallbackTrail) {
        addPlane(fallbackPlane);
      }
      if (step.usedPlaneFallback ||
          step.fallbackTrail.isNotEmpty ||
          step.observation?.fallbackUsed == true) {
        fallbackCount += 1;
      }
    }

    return _CockpitExecutionSummary(
      targetKind: targetKind,
      primaryExecutionPlane: planesUsed.firstOrNull,
      planesUsed: planesUsed,
      surfaceKindsUsed: surfaceKindsUsed,
      fallbackCount: fallbackCount,
    );
  }

  CockpitPlaneKind? _inferExecutionPlane(CockpitStepRecord step) {
    if (step.executionPlane case final executionPlane?) {
      return executionPlane;
    }
    return switch (_inferSurfaceKind(step)) {
      CockpitSurfaceKind.nativeUi => CockpitPlaneKind.nativeUiPlane,
      CockpitSurfaceKind.systemUi ||
      CockpitSurfaceKind.deviceShell => CockpitPlaneKind.deviceSystemPlane,
      CockpitSurfaceKind.hostShell => CockpitPlaneKind.hostPlane,
      CockpitSurfaceKind.flutterSemantic ||
      CockpitSurfaceKind.desktopWindow ||
      CockpitSurfaceKind.browserDom => CockpitPlaneKind.flutterSemanticPlane,
      null => null,
    };
  }

  CockpitSurfaceKind? _inferSurfaceKind(CockpitStepRecord step) {
    if (step.surfaceKind case final surfaceKind?) {
      return surfaceKind;
    }
    if (step.resolvedCaptureKind case final captureKind?) {
      return switch (captureKind) {
        CockpitCaptureKind.hostSystem => CockpitSurfaceKind.systemUi,
        CockpitCaptureKind.appNative ||
        CockpitCaptureKind.nativeAcceptance => CockpitSurfaceKind.nativeUi,
        CockpitCaptureKind.flutterView => CockpitSurfaceKind.flutterSemantic,
      };
    }
    if (step.snapshot != null || step.observation != null) {
      return CockpitSurfaceKind.flutterSemantic;
    }
    return switch (step.targetKind ?? step.observation?.targetKind) {
      CockpitTargetKind.nativeApp => CockpitSurfaceKind.nativeUi,
      CockpitTargetKind.desktopApp => CockpitSurfaceKind.desktopWindow,
      CockpitTargetKind.browserPage => CockpitSurfaceKind.browserDom,
      CockpitTargetKind.systemSurface => CockpitSurfaceKind.systemUi,
      CockpitTargetKind.device => CockpitSurfaceKind.deviceShell,
      CockpitTargetKind.hostWorkspace => CockpitSurfaceKind.hostShell,
      CockpitTargetKind.flutterApp => CockpitSurfaceKind.flutterSemantic,
      null => null,
    };
  }

  _CockpitAcceptanceNetworkSummary? _summarizeNetworkActivity(
    List<CockpitStepRecord> steps,
  ) {
    final dedupedEntries = <String, CockpitNetworkEntry>{};
    var totalEntryCount = 0;
    var failureCount = 0;
    for (final step in steps) {
      final network = step.snapshot?.network;
      if (network == null) {
        continue;
      }
      final capturedCount = network.capturedEntryCount > 0
          ? network.capturedEntryCount
          : network.totalEntryCount;
      if (capturedCount > totalEntryCount) {
        totalEntryCount = capturedCount;
      }
      if (network.failureCount > failureCount) {
        failureCount = network.failureCount;
      }
      for (final entry in network.entries) {
        dedupedEntries[entry.requestId] = entry;
      }
    }

    if (dedupedEntries.isEmpty && totalEntryCount == 0 && failureCount == 0) {
      return null;
    }

    final orderedEntries = dedupedEntries.values.toList(growable: true)
      ..sort((left, right) => right.startedAt.compareTo(left.startedAt));
    final failingEntries = orderedEntries
        .where((entry) => entry.isFailure)
        .take(3)
        .toList(growable: false);

    return _CockpitAcceptanceNetworkSummary(
      totalEntryCount: totalEntryCount == 0
          ? orderedEntries.length
          : totalEntryCount,
      failureCount: failureCount == 0
          ? orderedEntries.where((entry) => entry.isFailure).length
          : failureCount,
      recentEntries: orderedEntries.take(3).toList(growable: false),
      failingEntries: failingEntries,
    );
  }

  _CockpitAcceptanceRuntimeSummary? _summarizeRuntimeActivity(
    List<CockpitStepRecord> steps,
  ) {
    final dedupedEvents = <String, CockpitRuntimeEvent>{};
    var totalEntryCount = 0;
    var errorCount = 0;
    var warningCount = 0;
    for (final step in steps) {
      final runtime = step.snapshot?.runtime;
      if (runtime != null) {
        final capturedCount = runtime.capturedEntryCount > 0
            ? runtime.capturedEntryCount
            : runtime.totalEntryCount;
        if (capturedCount > totalEntryCount) {
          totalEntryCount = capturedCount;
        }
        if (runtime.errorCount > errorCount) {
          errorCount = runtime.errorCount;
        }
        if (runtime.warningCount > warningCount) {
          warningCount = runtime.warningCount;
        }
        for (final entry in runtime.entries) {
          dedupedEvents[entry.eventId] = entry;
        }
      }

      if (step.actionType != 'runtime_event') {
        continue;
      }
      final event = _runtimeEventFromStep(step);
      if (event == null) {
        continue;
      }
      dedupedEvents[event.eventId] = event;
    }

    if (dedupedEvents.isEmpty &&
        totalEntryCount == 0 &&
        errorCount == 0 &&
        warningCount == 0) {
      return null;
    }

    final orderedEntries = dedupedEvents.values.toList(growable: true)
      ..sort((left, right) => right.recordedAt.compareTo(left.recordedAt));
    final derivedErrorCount = orderedEntries
        .where((entry) => entry.isError)
        .length;
    final derivedWarningCount = orderedEntries
        .where((entry) => entry.isWarning)
        .length;
    return _CockpitAcceptanceRuntimeSummary(
      totalEntryCount: totalEntryCount == 0
          ? orderedEntries.length
          : totalEntryCount,
      errorCount: errorCount == 0 ? derivedErrorCount : errorCount,
      warningCount: warningCount == 0 ? derivedWarningCount : warningCount,
      recentEntries: orderedEntries.take(3).toList(growable: false),
      errorEntries: orderedEntries
          .where((entry) => entry.isError)
          .take(3)
          .toList(growable: false),
    );
  }

  CockpitRuntimeEvent? _runtimeEventFromStep(CockpitStepRecord step) {
    final eventId = step.actionArgs['eventId'] as String?;
    final kind = step.actionArgs['kind'];
    final severity = step.actionArgs['severity'];
    final message = step.actionArgs['message'] as String?;
    if (eventId == null ||
        message == null ||
        kind == null ||
        severity == null) {
      return null;
    }
    final details = step.actionArgs['details'];
    return CockpitRuntimeEvent(
      eventId: eventId,
      kind: CockpitRuntimeEventKind.fromJson(kind),
      severity: CockpitRuntimeEventSeverity.fromJson(severity),
      message: message,
      recordedAt: step.actionArgs['recordedAt'] == null
          ? step.observedAt
          : DateTime.parse(step.actionArgs['recordedAt']! as String).toUtc(),
      routeName: step.actionArgs['routeName'] as String?,
      source: step.actionArgs['source'] as String?,
      details: Map<String, String>.from(
        (details as Map<Object?, Object?>?) ?? const <Object?, Object?>{},
      ),
      stackTracePreview: step.actionArgs['stackTracePreview'] as String?,
      stackTraceTruncated:
          step.actionArgs['stackTraceTruncated'] as bool? ?? false,
    );
  }

  static DateTime _systemNow() => DateTime.now().toUtc();
}

final class _CockpitExecutionSummary {
  const _CockpitExecutionSummary({
    required this.targetKind,
    required this.primaryExecutionPlane,
    required this.planesUsed,
    required this.surfaceKindsUsed,
    required this.fallbackCount,
  });

  final CockpitTargetKind? targetKind;
  final CockpitPlaneKind? primaryExecutionPlane;
  final List<CockpitPlaneKind> planesUsed;
  final List<CockpitSurfaceKind> surfaceKindsUsed;
  final int fallbackCount;
}

final class _CockpitAcceptanceNetworkSummary {
  const _CockpitAcceptanceNetworkSummary({
    required this.totalEntryCount,
    required this.failureCount,
    required this.recentEntries,
    required this.failingEntries,
  });

  final int totalEntryCount;
  final int failureCount;
  final List<CockpitNetworkEntry> recentEntries;
  final List<CockpitNetworkEntry> failingEntries;
}

final class _CockpitAcceptanceRuntimeSummary {
  const _CockpitAcceptanceRuntimeSummary({
    required this.totalEntryCount,
    required this.errorCount,
    required this.warningCount,
    required this.recentEntries,
    required this.errorEntries,
  });

  final int totalEntryCount;
  final int errorCount;
  final int warningCount;
  final List<CockpitRuntimeEvent> recentEntries;
  final List<CockpitRuntimeEvent> errorEntries;
}
