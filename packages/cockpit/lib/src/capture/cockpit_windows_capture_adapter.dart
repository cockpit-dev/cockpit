import 'dart:async';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../platform/windows/cockpit_windows_screen_capture.dart';
import '../platform/windows/cockpit_windows_window_target.dart';
import 'cockpit_host_capture_adapter.dart';

final class CockpitWindowsCaptureAdapter implements CockpitHostCaptureAdapter {
  CockpitWindowsCaptureAdapter({
    required String appId,
    int? processId,
    CockpitCaptureTempFileFactory tempFileFactory =
        cockpitCreateCaptureTempFile,
    CockpitWindowsWindowResolver windowResolver =
        cockpitResolveWindowsWindowTarget,
    CockpitWindowsScreenCaptureWriter screenCaptureWriter =
        cockpitWriteWindowsScreenCapture,
    Duration timeout = const Duration(seconds: 5),
    Duration activationSettleDelay = const Duration(milliseconds: 250),
  }) : _appId = appId,
       _processId = processId,
       _tempFileFactory = tempFileFactory,
       _windowResolver = windowResolver,
       _screenCaptureWriter = screenCaptureWriter,
       _timeout = timeout,
       _activationSettleDelay = activationSettleDelay;

  final String _appId;
  final int? _processId;
  final CockpitCaptureTempFileFactory _tempFileFactory;
  final CockpitWindowsWindowResolver _windowResolver;
  final CockpitWindowsScreenCaptureWriter _screenCaptureWriter;
  final Duration _timeout;
  final Duration _activationSettleDelay;

  @override
  Future<CockpitCommandExecution> capture(CockpitCommand command) async {
    final request = command.screenshotRequest;
    if (request == null) {
      return cockpitFailedCaptureExecution(
        command: command,
        durationMs: 0,
        message: 'Host screenshot capture requires a screenshot request.',
      );
    }

    final stopwatch = Stopwatch()..start();
    final commandTimeout = command.timeoutMs;
    final captureTimeout = commandTimeout == null || commandTimeout <= 0
        ? _timeout
        : Duration(milliseconds: commandTimeout);
    Duration remainingTimeout() {
      final remaining = captureTimeout - stopwatch.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('Windows host screenshot deadline expired.');
      }
      return remaining;
    }

    final artifact = cockpitCaptureArtifactForRequest(request);
    final outputFile = await _tempFileFactory(
      cockpitCaptureFileName(request.name),
    );
    outputFile.parent.createSync(recursive: true);
    if (outputFile.existsSync()) {
      outputFile.deleteSync();
    }

    try {
      final windowTarget = await _windowResolver(
        appId: _appId,
        processId: _processId,
        timeout: remainingTimeout(),
        activationSettleDelay: _activationSettleDelay,
      );
      await _screenCaptureWriter(
        target: windowTarget,
        outputFile: outputFile,
        timeout: remainingTimeout(),
      ).timeout(remainingTimeout());
      stopwatch.stop();
      return await cockpitValidateHostCaptureOutput(
        command: command,
        artifact: artifact,
        durationMs: stopwatch.elapsedMilliseconds,
        outputFile: outputFile,
        captureDescription: 'Windows host screenshot',
        details: <String, Object?>{
          'appId': _appId,
          'processId': windowTarget.processId,
        },
      );
    } on TimeoutException {
      stopwatch.stop();
      return cockpitFailedCaptureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        message: 'Windows host screenshot timed out.',
        details: <String, Object?>{'appId': _appId},
      );
    } on CockpitWindowsWindowException catch (error) {
      stopwatch.stop();
      return cockpitFailedCaptureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        message: 'Windows host screenshot failed.',
        details: <String, Object?>{
          'appId': _appId,
          'errorCode': error.code,
          'error': error.message,
        },
      );
    } on CockpitWindowsScreenCaptureException catch (error) {
      stopwatch.stop();
      return cockpitFailedCaptureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        message: 'Windows host screenshot failed.',
        details: <String, Object?>{
          'appId': _appId,
          'errorCode': error.code,
          'error': error.message,
        },
      );
    } on StateError catch (error) {
      stopwatch.stop();
      return cockpitFailedCaptureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        message: 'Windows host screenshot failed.',
        details: <String, Object?>{'appId': _appId, 'error': error.toString()},
      );
    } on Object catch (error) {
      stopwatch.stop();
      return cockpitFailedCaptureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        message: 'Windows host screenshot threw an unexpected error.',
        details: <String, Object?>{'appId': _appId, 'error': error.toString()},
      );
    }
  }
}
