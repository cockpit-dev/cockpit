import 'dart:async';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../platform/macos/cockpit_macos_window_target.dart';
import '../session/cockpit_session_process_runner.dart';
import 'cockpit_host_capture_adapter.dart';

final class CockpitMacosCaptureAdapter implements CockpitHostCaptureAdapter {
  CockpitMacosCaptureAdapter({
    required String appId,
    String osascriptExecutable = 'osascript',
    String screencaptureExecutable = 'screencapture',
    CockpitCaptureProcessRunner? processRunner,
    CockpitCaptureTempFileFactory tempFileFactory =
        cockpitCreateCaptureTempFile,
    CockpitMacosWindowTargetResolver windowTargetResolver =
        cockpitResolveMacosWindowTarget,
    Duration timeout = const Duration(seconds: 5),
    Duration activationSettleDelay = const Duration(milliseconds: 250),
  }) : _appId = appId,
       _osascriptExecutable = osascriptExecutable,
       _screencaptureExecutable = screencaptureExecutable,
       _processRunner = processRunner,
       _tempFileFactory = tempFileFactory,
       _windowTargetResolver = windowTargetResolver,
       _timeout = timeout,
       _activationSettleDelay = activationSettleDelay;

  final String _appId;
  final String _osascriptExecutable;
  final String _screencaptureExecutable;
  final CockpitCaptureProcessRunner? _processRunner;
  final CockpitCaptureTempFileFactory _tempFileFactory;
  final CockpitMacosWindowTargetResolver _windowTargetResolver;
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
    final artifact = cockpitCaptureArtifactForRequest(request);
    final outputFile = await _tempFileFactory(
      cockpitCaptureFileName(request.name),
    );
    outputFile.parent.createSync(recursive: true);
    if (outputFile.existsSync()) {
      outputFile.deleteSync();
    }

    try {
      final windowTarget = await _windowTargetResolver(
        appId: _appId,
        osascriptExecutable: _osascriptExecutable,
        processRunner: _runProcess,
        timeout: _timeout,
        activationSettleDelay: _activationSettleDelay,
      );
      final windowId = windowTarget.windowId;
      final bounds =
          '${windowTarget.left},${windowTarget.top},${windowTarget.width},${windowTarget.height}';
      var strategy = windowId == null ? 'bounds' : 'window';
      var result = await _runProcess(_screencaptureExecutable, <String>[
        '-x',
        '-o',
        if (windowId != null) ...<String>['-l', '$windowId'] else ...<String>[
          '-R',
          bounds,
        ],
        outputFile.path,
      ]);
      ProcessResult? windowFailure;
      if (result.exitCode != 0 && windowId != null) {
        windowFailure = result;
        if (outputFile.existsSync()) outputFile.deleteSync();
        strategy = 'boundsFallback';
        result = await _runProcess(_screencaptureExecutable, <String>[
          '-x',
          '-o',
          '-R',
          bounds,
          outputFile.path,
        ]);
      }
      stopwatch.stop();

      if (result.exitCode != 0) {
        return cockpitFailedCaptureExecution(
          command: command,
          durationMs: stopwatch.elapsedMilliseconds,
          message: 'macOS screencapture failed.',
          details: <String, Object?>{
            'appId': _appId,
            'strategy': strategy,
            'exitCode': result.exitCode,
            'stderr': '${result.stderr}'.trim(),
            if (windowFailure != null)
              'windowAttempt': <String, Object?>{
                'windowId': windowId,
                'exitCode': windowFailure.exitCode,
                'stderr': '${windowFailure.stderr}'.trim(),
              },
          },
        );
      }
      return cockpitValidateHostCaptureOutput(
        command: command,
        artifact: artifact,
        durationMs: stopwatch.elapsedMilliseconds,
        outputFile: outputFile,
        captureDescription: 'macOS screencapture',
        details: <String, Object?>{
          'appId': _appId,
          'strategy': strategy,
          if (windowFailure != null) 'windowId': windowId,
        },
      );
    } on TimeoutException {
      stopwatch.stop();
      return cockpitFailedCaptureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        message: 'macOS screencapture timed out.',
        details: <String, Object?>{'appId': _appId},
      );
    } on StateError catch (error) {
      stopwatch.stop();
      return cockpitFailedCaptureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        message: 'macOS host screenshot failed.',
        details: <String, Object?>{'appId': _appId, 'error': error.toString()},
      );
    } on Object catch (error) {
      stopwatch.stop();
      return cockpitFailedCaptureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        message: 'macOS screencapture threw an unexpected error.',
        details: <String, Object?>{'appId': _appId, 'error': error.toString()},
      );
    }
  }

  Future<ProcessResult> _runProcess(String executable, List<String> arguments) {
    final injected = _processRunner;
    if (injected != null) {
      return injected(executable, arguments).timeout(_timeout);
    }
    return cockpitRunProcessWithTimeout(
      executable,
      arguments,
      timeout: _timeout,
    );
  }
}
