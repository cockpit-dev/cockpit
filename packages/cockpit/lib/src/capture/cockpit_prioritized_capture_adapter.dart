import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../adapters/cockpit_capture_adapter.dart';
import '../remote/cockpit_remote_session_client.dart';
import 'cockpit_host_capture_adapter.dart';

final class CockpitPrioritizedCaptureAdapter implements CockpitCaptureAdapter {
  CockpitPrioritizedCaptureAdapter({
    required CockpitCaptureAdapter remoteAdapter,
    required CockpitCaptureAdapter hostAcceptanceAdapter,
    required CockpitRemoteSessionClient client,
    bool preferHostForAcceptance = true,
    Duration preCaptureIdleTimeout = const Duration(milliseconds: 600),
  }) : _remoteAdapter = remoteAdapter,
       _hostAcceptanceAdapter = hostAcceptanceAdapter,
       _client = client,
       _preferHostForAcceptance = preferHostForAcceptance,
       _preCaptureIdleTimeout = preCaptureIdleTimeout;

  final CockpitCaptureAdapter _remoteAdapter;
  final CockpitCaptureAdapter _hostAcceptanceAdapter;
  final CockpitRemoteSessionClient _client;
  final bool _preferHostForAcceptance;
  final Duration _preCaptureIdleTimeout;

  @override
  Future<CockpitCommandExecution> capture(CockpitCommand command) async {
    final request = command.screenshotRequest;
    if (request == null) {
      return _remoteAdapter.capture(command);
    }

    await _bestEffortWaitForUiIdle();
    final hostFirst = _prefersHost(request);
    final primary = await _attempt(
      command,
      adapter: hostFirst ? _hostAcceptanceAdapter : _remoteAdapter,
      label: hostFirst ? 'host' : 'app',
    );
    if (primary.execution.result.success) {
      return _attachSnapshotIfNeeded(
        primary.execution,
        request: request,
        capturedByHost: hostFirst,
      );
    }
    if (!request.allowsFallback) {
      return primary.execution;
    }

    final fallback = await _attempt(
      command,
      adapter: hostFirst ? _remoteAdapter : _hostAcceptanceAdapter,
      label: hostFirst ? 'app' : 'host',
    );
    if (!fallback.execution.result.success) {
      return _withFallbackMetadata(
        primary.execution,
        degradationReason:
            '${primary.failureReason}; ${fallback.fallbackFailureSummary}',
        fallbackAttempt: fallback,
      );
    }
    final fallbackExecution = await _attachSnapshotIfNeeded(
      fallback.execution,
      request: request,
      capturedByHost: !hostFirst,
    );
    return _withFallbackMetadata(
      fallbackExecution,
      degradationReason: primary.failureReason,
    );
  }

  bool _prefersHost(CockpitScreenshotRequest request) {
    final profile =
        request.profile ??
        (request.reason == CockpitScreenshotReason.acceptance
            ? CockpitCaptureProfile.acceptance
            : CockpitCaptureProfile.diagnostic);
    return switch (profile) {
      CockpitCaptureProfile.nativePreferred => true,
      CockpitCaptureProfile.acceptance => _preferHostForAcceptance,
      CockpitCaptureProfile.diagnostic ||
      CockpitCaptureProfile.flutterPreferred => false,
    };
  }

  Future<_CaptureAttempt> _attempt(
    CockpitCommand command, {
    required CockpitCaptureAdapter adapter,
    required String label,
  }) async {
    try {
      final execution = await adapter.capture(command);
      return _CaptureAttempt(execution: execution, label: label, threw: false);
    } on Object catch (error, stackTrace) {
      return _CaptureAttempt(
        execution: cockpitFailedCaptureExecution(
          command: command,
          durationMs: 0,
          message: '${_capitalize(label)} screenshot capture threw.',
          details: <String, Object?>{
            'error': error.toString(),
            'stackTrace': stackTrace.toString(),
          },
        ),
        label: label,
        threw: true,
      );
    }
  }

  Future<void> _bestEffortWaitForUiIdle() async {
    try {
      await _client.waitForUiIdle(timeout: _preCaptureIdleTimeout);
    } on Object {
      // Capture remains useful when the app status/idle endpoint is degraded.
    }
  }

  Future<CockpitCommandExecution> _attachSnapshotIfNeeded(
    CockpitCommandExecution execution, {
    required CockpitScreenshotRequest request,
    required bool capturedByHost,
  }) async {
    if (!capturedByHost || !request.includeSnapshot) {
      return execution;
    }

    try {
      final snapshot = await _client.readSnapshot(
        options:
            request.snapshotOptions ??
            _defaultSnapshotOptionsForReason(request.reason),
      );
      return CockpitCommandExecution(
        result: CockpitCommandResult(
          success: execution.result.success,
          commandId: execution.result.commandId,
          commandType: execution.result.commandType,
          locatorResolution: execution.result.locatorResolution,
          durationMs: execution.result.durationMs,
          artifacts: execution.result.artifacts,
          snapshot: snapshot.toJson(),
          requestedCaptureProfile: execution.result.requestedCaptureProfile,
          resolvedCaptureKind: execution.result.resolvedCaptureKind,
          usedCaptureFallback: execution.result.usedCaptureFallback,
          degradationReason: execution.result.degradationReason,
          surface: execution.result.surface,
          changed: execution.result.changed,
          error: execution.result.error,
        ),
        artifactPayloads: execution.artifactPayloads,
        artifactSourcePaths: execution.artifactSourcePaths,
        runtimeSteps: execution.runtimeSteps,
      );
    } on Object {
      return execution;
    }
  }

  String _capitalize(String value) =>
      '${value.substring(0, 1).toUpperCase()}${value.substring(1)}';

  CockpitCommandExecution _withFallbackMetadata(
    CockpitCommandExecution execution, {
    required String degradationReason,
    _CaptureAttempt? fallbackAttempt,
  }) {
    final result = execution.result;
    final originalError = result.error;
    final error = originalError == null
        ? null
        : CockpitCommandError(
            code: originalError.code,
            message: originalError.message,
            details: <String, Object?>{
              ...originalError.details,
              if (fallbackAttempt != null)
                'fallbackFailure': fallbackAttempt.failureDetails,
            },
          );
    final nestedReason = result.degradationReason;
    final combinedReason = nestedReason == null || nestedReason.isEmpty
        ? degradationReason
        : '$degradationReason; $nestedReason';
    return CockpitCommandExecution(
      result: CockpitCommandResult(
        success: result.success,
        commandId: result.commandId,
        commandType: result.commandType,
        locatorResolution: result.locatorResolution,
        durationMs: result.durationMs,
        artifacts: result.artifacts,
        snapshot: result.snapshot,
        requestedCaptureProfile: result.requestedCaptureProfile,
        resolvedCaptureKind: result.resolvedCaptureKind,
        usedCaptureFallback: true,
        degradationReason: combinedReason,
        surface: result.surface,
        changed: result.changed,
        error: error,
      ),
      artifactPayloads: execution.artifactPayloads,
      artifactSourcePaths: execution.artifactSourcePaths,
      runtimeSteps: execution.runtimeSteps,
    );
  }

  CockpitSnapshotOptions _defaultSnapshotOptionsForReason(
    CockpitScreenshotReason reason,
  ) {
    return switch (reason) {
      CockpitScreenshotReason.assertionFailure =>
        const CockpitSnapshotOptions.investigate(),
      CockpitScreenshotReason.baseline =>
        const CockpitSnapshotOptions.baseline(),
      CockpitScreenshotReason.acceptance =>
        const CockpitSnapshotOptions.investigate(),
      CockpitScreenshotReason.beforeAction ||
      CockpitScreenshotReason.afterAction =>
        const CockpitSnapshotOptions.live(),
    };
  }
}

final class _CaptureAttempt {
  const _CaptureAttempt({
    required this.execution,
    required this.label,
    required this.threw,
  });

  final CockpitCommandExecution execution;
  final String label;
  final bool threw;

  String get failureReason => '${label}Capture${threw ? 'Threw' : 'Failed'}';

  String get fallbackFailureSummary {
    final error = execution.result.error;
    final thrownDetail = error?.details['error'];
    final detail = threw && thrownDetail is String
        ? thrownDetail
        : error?.message ??
              execution.result.degradationReason ??
              'capture returned success=false';
    return '${label}Fallback${threw ? 'Threw' : 'Failed'}: $detail';
  }

  Map<String, Object?> get failureDetails {
    final error = execution.result.error;
    final thrownError = error?.details['error'];
    final stackTrace = error?.details['stackTrace'];
    return <String, Object?>{
      'source': label,
      'threw': threw,
      'error':
          thrownError ??
          error?.message ??
          execution.result.degradationReason ??
          'capture returned success=false',
      if (stackTrace is String && stackTrace.isNotEmpty)
        'stackTrace': stackTrace,
    };
  }
}
