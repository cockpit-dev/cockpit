import 'dart:async';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../session/cockpit_session_process_runner.dart';
import 'cockpit_host_capture_adapter.dart';

final class CockpitSimctlCaptureAdapter implements CockpitHostCaptureAdapter {
  CockpitSimctlCaptureAdapter({
    required String deviceId,
    String executable = 'xcrun',
    CockpitCaptureProcessRunner? processRunner,
    CockpitCaptureTempFileFactory tempFileFactory =
        cockpitCreateCaptureTempFile,
    Duration timeout = const Duration(seconds: 5),
  }) : _deviceId = deviceId,
       _executable = executable,
       _processRunner = processRunner,
       _tempFileFactory = tempFileFactory,
       _timeout = timeout;

  final String _deviceId;
  final String _executable;
  final CockpitCaptureProcessRunner? _processRunner;
  final CockpitCaptureTempFileFactory _tempFileFactory;
  final Duration _timeout;

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
    final artifact = cockpitCaptureArtifactForRequest(request);
    final outputFile = await _tempFileFactory(
      cockpitCaptureFileName(request.name),
    );
    outputFile.parent.createSync(recursive: true);
    if (outputFile.existsSync()) {
      outputFile.deleteSync();
    }

    try {
      final result = await _runProcess(_executable, <String>[
        'simctl',
        'io',
        _deviceId,
        'screenshot',
        outputFile.path,
      ], timeout: captureTimeout);
      stopwatch.stop();

      if (result.exitCode != 0) {
        return cockpitFailedCaptureExecution(
          command: command,
          durationMs: stopwatch.elapsedMilliseconds,
          message: 'simctl screenshot failed.',
          details: <String, Object?>{
            'deviceId': _deviceId,
            'exitCode': result.exitCode,
            'stderr': '${result.stderr}'.trim(),
          },
        );
      }
      return cockpitValidateHostCaptureOutput(
        command: command,
        artifact: artifact,
        durationMs: stopwatch.elapsedMilliseconds,
        outputFile: outputFile,
        captureDescription: 'simctl screenshot',
        details: <String, Object?>{'deviceId': _deviceId},
      );
    } on TimeoutException {
      stopwatch.stop();
      return cockpitFailedCaptureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        message: 'simctl screenshot timed out.',
        details: <String, Object?>{'deviceId': _deviceId},
      );
    } on Object catch (error) {
      stopwatch.stop();
      return cockpitFailedCaptureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        message: 'simctl screenshot threw an unexpected error.',
        details: <String, Object?>{
          'deviceId': _deviceId,
          'error': error.toString(),
        },
      );
    }
  }

  Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  }) {
    final injected = _processRunner;
    if (injected != null) {
      return injected(executable, arguments).timeout(timeout);
    }
    return cockpitRunProcessWithTimeout(
      executable,
      arguments,
      timeout: timeout,
    );
  }
}
