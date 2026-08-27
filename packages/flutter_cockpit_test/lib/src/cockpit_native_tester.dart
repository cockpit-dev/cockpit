import 'dart:async';

import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';

import 'cockpit_test_options.dart';

/// Native evidence and viewport controls available to a Cockpit integration
/// test.
final class CockpitNativeTester {
  CockpitNativeTester(
    this._root, {
    Duration defaultTimeout = cockpitIntegrationTestNativeTimeout,
  }) : _defaultTimeout = _validateTimeout(defaultTimeout, 'defaultTimeout');

  final FlutterCockpitRootState _root;
  final Duration _defaultTimeout;
  CockpitRecordingSession? _activeRecording;

  Future<bool> queryCaptureAvailability({Duration? timeout}) {
    return _run(
      FlutterCockpit.binding.queryNativeCaptureAvailability(),
      timeout: timeout,
      operation: 'query native capture availability',
    );
  }

  Future<CockpitCaptureResult> captureScreenshot({
    required String name,
    CockpitScreenshotReason reason = CockpitScreenshotReason.acceptance,
    bool includeSnapshot = true,
    bool allowFallback = false,
    Duration? timeout,
  }) {
    return _run(
      _root.captureScreenshot(
        CockpitScreenshotRequest(
          reason: reason,
          name: name,
          includeSnapshot: includeSnapshot,
          attachToStep: true,
          profile: CockpitCaptureProfile.nativePreferred,
          allowFallback: allowFallback,
        ),
        profile: CockpitCaptureProfile.nativePreferred,
        allowFallback: allowFallback,
      ),
      timeout: timeout,
      operation: 'native screenshot',
    );
  }

  Future<CockpitRecordingCapabilities> queryRecordingCapabilities({
    Duration? timeout,
  }) {
    return _run(
      _root.queryRecordingCapabilities(),
      timeout: timeout,
      operation: 'query recording capabilities',
    );
  }

  Future<CockpitRecordingSession> startRecording({
    required String name,
    CockpitRecordingPurpose purpose = CockpitRecordingPurpose.acceptance,
    CockpitRecordingMode mode = CockpitRecordingMode.native,
    CockpitRecordingLayer? layer,
    bool allowFallback = false,
    Duration? timeout,
  }) async {
    final session = await _run(
      _root.startRecording(
        CockpitRecordingRequest(
          purpose: purpose,
          name: name,
          mode: mode,
          layer: layer,
          allowFallback: allowFallback,
          attachToStep: true,
        ),
      ),
      timeout: timeout,
      operation: 'start native recording',
      onTimeout: _cancelPendingRecordingStart,
    );
    _activeRecording = session.state == CockpitRecordingState.recording
        ? session
        : null;
    return session;
  }

  Future<CockpitRecordingResult> stopRecording({Duration? timeout}) async {
    final result = await _run(
      _root.stopRecording(),
      timeout: timeout,
      operation: 'stop native recording',
    );
    _activeRecording = null;
    return result;
  }

  /// Finalizes an accidentally active recording during test teardown.
  Future<void> close({Duration? timeout}) async {
    if (_activeRecording == null) return;
    try {
      await stopRecording(timeout: timeout);
    } on Object {
      // The test result already owns the primary failure; teardown is best
      // effort and must not hide it with a secondary native error.
      _activeRecording = null;
    }
  }

  Future<CockpitViewportResizeResult> resizeViewport({
    required int width,
    required int height,
    Duration? timeout,
  }) {
    return _run(
      _root.resizeViewport(
        CockpitViewportResizeRequest(width: width, height: height),
      ),
      timeout: timeout,
      operation: 'resize native viewport',
    );
  }

  Future<T> _run<T>(
    Future<T> future, {
    required Duration? timeout,
    required String operation,
    Future<void> Function()? onTimeout,
  }) async {
    final effective = _validateTimeout(timeout ?? _defaultTimeout, 'timeout');
    return await future.timeout(
      effective,
      onTimeout: () async {
        await onTimeout?.call();
        throw TimeoutException(
          'Cockpit $operation exceeded its '
          '${effective.inMilliseconds}ms timeout.',
          effective,
        );
      },
    );
  }

  Future<void> _cancelPendingRecordingStart() async {
    try {
      await FlutterCockpit.binding.cancelRecordingStart().timeout(
        const Duration(seconds: 2),
      );
    } on Object {
      // A platform without a cancellable pending request is already bounded
      // by the facade timeout; do not replace the primary timeout error.
    }
  }

  static Duration _validateTimeout(Duration value, String name) {
    if (value <= Duration.zero ||
        value > cockpitIntegrationTestMaximumTimeout) {
      throw ArgumentError.value(
        value,
        name,
        'Timeout must be between 1ms and '
        '${cockpitIntegrationTestMaximumTimeout.inMilliseconds}ms.',
      );
    }
    return value;
  }
}
