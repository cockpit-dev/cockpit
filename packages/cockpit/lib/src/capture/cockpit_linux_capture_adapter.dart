import 'dart:async';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../platform/linux/cockpit_linux_window_target.dart';
import '../recording/cockpit_linux_recording_adapter.dart';
import '../session/cockpit_session_process_runner.dart';
import 'cockpit_host_capture_adapter.dart';

final class CockpitLinuxCaptureAdapter implements CockpitHostCaptureAdapter {
  CockpitLinuxCaptureAdapter({
    required String appId,
    int? processId,
    List<String> captureExecutables = const <String>[
      'gnome-screenshot',
      'grim',
      'scrot',
      'xwd-ffmpeg',
      'ffmpeg-x11grab',
      'import',
    ],
    String? windowActivatorExecutable = 'wmctrl',
    CockpitCaptureProcessRunner? processRunner,
    CockpitCaptureTempFileFactory tempFileFactory =
        cockpitCreateCaptureTempFile,
    CockpitLinuxDisplayConfigResolver? displayConfigResolver,
    CockpitLinuxWindowTargetResolver windowTargetResolver =
        cockpitResolveLinuxWindowTarget,
    Duration timeout = const Duration(seconds: 5),
    Duration activationSettleDelay = const Duration(milliseconds: 250),
  }) : _appId = appId,
       _processId = processId,
       _captureExecutables = List<String>.unmodifiable(captureExecutables),
       _windowActivatorExecutable = windowActivatorExecutable,
       _processRunner = processRunner,
       _tempFileFactory = tempFileFactory,
       _displayConfigResolver =
           displayConfigResolver ??
           (() => CockpitLinuxRecordingAdapter.resolveDisplayConfig(
             processRunner,
           )),
       _windowTargetResolver = windowTargetResolver,
       _timeout = timeout,
       _activationSettleDelay = activationSettleDelay;

  final String _appId;
  final int? _processId;
  final List<String> _captureExecutables;
  final String? _windowActivatorExecutable;
  final CockpitCaptureProcessRunner? _processRunner;
  final CockpitCaptureTempFileFactory _tempFileFactory;
  final CockpitLinuxDisplayConfigResolver _displayConfigResolver;
  final CockpitLinuxWindowTargetResolver _windowTargetResolver;
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
      final windowTarget = await _tryResolveWindowTarget();
      await _bestEffortActivate(windowTarget);
      final result = await _capture(outputFile.path, windowTarget);
      stopwatch.stop();

      if (result.processResult.exitCode != 0) {
        return cockpitFailedCaptureExecution(
          command: command,
          durationMs: stopwatch.elapsedMilliseconds,
          message: 'Linux host screenshot failed.',
          details: <String, Object?>{
            'appId': _appId,
            'exitCode': result.processResult.exitCode,
            'stderr': '${result.processResult.stderr}'.trim(),
            'attempts': result.attempts,
          },
        );
      }
      return await cockpitValidateHostCaptureOutput(
        command: command,
        artifact: artifact,
        durationMs: stopwatch.elapsedMilliseconds,
        outputFile: outputFile,
        captureDescription: 'Linux host screenshot',
        details: <String, Object?>{'appId': _appId},
      );
    } on TimeoutException {
      stopwatch.stop();
      return cockpitFailedCaptureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        message: 'Linux host screenshot timed out.',
        details: <String, Object?>{'appId': _appId},
      );
    } on _CockpitLinuxCaptureFailure catch (error) {
      stopwatch.stop();
      return cockpitFailedCaptureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        message: 'Linux host screenshot failed.',
        details: <String, Object?>{
          'appId': _appId,
          'error': error.message,
          'attempts': error.attempts,
        },
      );
    } on StateError catch (error) {
      stopwatch.stop();
      return cockpitFailedCaptureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        message: 'Linux host screenshot failed.',
        details: <String, Object?>{'appId': _appId, 'error': error.toString()},
      );
    } on Object catch (error) {
      stopwatch.stop();
      return cockpitFailedCaptureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        message: 'Linux host screenshot threw an unexpected error.',
        details: <String, Object?>{'appId': _appId, 'error': error.toString()},
      );
    }
  }

  Future<CockpitLinuxWindowTarget?> _tryResolveWindowTarget() async {
    try {
      return await _windowTargetResolver(
        appId: _appId,
        processId: _processId,
        processRunner: _runProcess,
        timeout: _timeout,
      );
    } on Object {
      return null;
    }
  }

  Future<void> _bestEffortActivate(
    CockpitLinuxWindowTarget? windowTarget,
  ) async {
    final executable = _windowActivatorExecutable;
    if (executable == null || executable.isEmpty) {
      return;
    }
    try {
      final arguments = windowTarget == null
          ? <String>['-xa', _appId]
          : <String>['-ia', windowTarget.windowId];
      final result = await _runProcess(executable, arguments);
      if (result.exitCode == 0 && _activationSettleDelay > Duration.zero) {
        await Future<void>.delayed(_activationSettleDelay);
      }
    } on Object {
      // Activation is best-effort only.
    }
  }

  Future<_CockpitLinuxCaptureAttemptResult> _capture(
    String outputPath,
    CockpitLinuxWindowTarget? windowTarget,
  ) async {
    Object? lastFailure;
    final attempts = <Map<String, Object?>>[];
    for (final executable in _captureExecutables) {
      try {
        final result = switch (executable) {
          'xwd-ffmpeg' => await _captureWithXwdAndFfmpeg(
            outputPath,
            windowTarget,
            attempts,
          ),
          'ffmpeg-x11grab' => await _captureWithFfmpegX11Grab(
            outputPath,
            windowTarget,
            attempts,
          ),
          _ => await _captureWithExecutable(
            executable,
            outputPath,
            windowTarget,
            attempts,
          ),
        };
        if (result.exitCode == 0) {
          return _CockpitLinuxCaptureAttemptResult(
            processResult: result,
            attempts: attempts,
          );
        }
        lastFailure = StateError(
          '$executable exited with ${result.exitCode}: ${result.stderr ?? result.stdout}',
        );
      } on ProcessException catch (error) {
        lastFailure = error;
      } on StateError catch (error) {
        lastFailure = error;
      }
    }
    throw _CockpitLinuxCaptureFailure(
      message:
          lastFailure?.toString() ??
          'No Linux screenshot executable succeeded for $_appId.',
      attempts: attempts,
    );
  }

  Future<ProcessResult> _captureWithExecutable(
    String executable,
    String outputPath,
    CockpitLinuxWindowTarget? windowTarget,
    List<Map<String, Object?>> attempts,
  ) async {
    final arguments = _captureArgumentsFor(
      executable,
      outputPath,
      windowTarget,
    );
    final attempt = _startAttempt(executable, arguments);
    attempts.add(attempt);
    if (arguments == null) {
      attempt['status'] = 'skipped';
      attempt['error'] =
          '$executable requires a resolved Linux window target for $_appId.';
      throw StateError(
        '$executable requires a resolved Linux window target for $_appId.',
      );
    }
    return _runAttempt(executable, arguments, attempt);
  }

  Future<ProcessResult> _captureWithXwdAndFfmpeg(
    String outputPath,
    CockpitLinuxWindowTarget? windowTarget,
    List<Map<String, Object?>> attempts,
  ) async {
    final rawFile = File('$outputPath.xwd');
    if (rawFile.existsSync()) {
      rawFile.deleteSync();
    }
    try {
      final xwdArguments = <String>[
        if (windowTarget == null) ...<String>['-root'] else ...<String>[
          '-id',
          windowTarget.windowId,
        ],
        '-silent',
        '-out',
        rawFile.path,
      ];
      final xwdAttempt = _startAttempt('xwd', xwdArguments);
      attempts.add(xwdAttempt);
      final xwdResult = await _runAttempt('xwd', xwdArguments, xwdAttempt);
      if (xwdResult.exitCode != 0) {
        return xwdResult;
      }
      if (!rawFile.existsSync() || rawFile.lengthSync() == 0) {
        return ProcessResult(
          0,
          1,
          xwdResult.stdout,
          'xwd produced an empty XWD artifact.',
        );
      }
      final ffmpegArguments = <String>[
        '-y',
        '-loglevel',
        'error',
        '-i',
        rawFile.path,
        outputPath,
      ];
      final ffmpegAttempt = _startAttempt('xwd-ffmpeg', ffmpegArguments);
      attempts.add(ffmpegAttempt);
      return await _runAttempt('ffmpeg', ffmpegArguments, ffmpegAttempt);
    } finally {
      if (rawFile.existsSync()) {
        rawFile.deleteSync();
      }
    }
  }

  Future<ProcessResult> _captureWithFfmpegX11Grab(
    String outputPath,
    CockpitLinuxWindowTarget? windowTarget,
    List<Map<String, Object?>> attempts,
  ) async {
    final displayConfig = await _displayConfigResolver();
    final arguments = <String>[
      '-y',
      '-loglevel',
      'error',
      '-f',
      'x11grab',
      if (windowTarget != null) ...<String>[
        '-window_id',
        windowTarget.windowId,
      ],
      '-video_size',
      windowTarget == null
          ? displayConfig.captureSize
          : '${windowTarget.width}x${windowTarget.height}',
      '-i',
      windowTarget == null
          ? '${displayConfig.display}+0,0'
          : displayConfig.display,
      '-frames:v',
      '1',
      outputPath,
    ];
    final attempt = _startAttempt('ffmpeg-x11grab', arguments);
    attempts.add(attempt);
    return _runAttempt('ffmpeg', arguments, attempt);
  }

  List<String>? _captureArgumentsFor(
    String executable,
    String outputPath,
    CockpitLinuxWindowTarget? windowTarget,
  ) {
    return switch (executable) {
      'gnome-screenshot' => <String>['-w', '-f', outputPath],
      'grim' =>
        windowTarget == null
            ? null
            : <String>[
                '-g',
                '${windowTarget.left},${windowTarget.top} ${windowTarget.width}x${windowTarget.height}',
                outputPath,
              ],
      'scrot' => <String>['-u', outputPath],
      'import' => <String>[
        '-window',
        windowTarget?.windowId ?? 'root',
        outputPath,
      ],
      _ => <String>[outputPath],
    };
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

  Future<ProcessResult> _runAttempt(
    String executable,
    List<String> arguments,
    Map<String, Object?> attempt,
  ) async {
    try {
      final result = await _runProcess(executable, arguments);
      attempt['exitCode'] = result.exitCode;
      if ('${result.stderr}'.trim().isNotEmpty) {
        attempt['stderr'] = '${result.stderr}'.trim();
      }
      attempt['status'] = result.exitCode == 0 ? 'succeeded' : 'failed';
      return result;
    } on ProcessException catch (error) {
      attempt['status'] = 'failed';
      attempt['error'] = error.toString();
      rethrow;
    }
  }

  Map<String, Object?> _startAttempt(
    String executable,
    List<String>? arguments,
  ) {
    final attempt = <String, Object?>{'executable': executable};
    if (arguments != null) {
      attempt['arguments'] = arguments;
    }
    return attempt;
  }
}

final class _CockpitLinuxCaptureAttemptResult {
  const _CockpitLinuxCaptureAttemptResult({
    required this.processResult,
    required this.attempts,
  });

  final ProcessResult processResult;
  final List<Map<String, Object?>> attempts;
}

final class _CockpitLinuxCaptureFailure implements Exception {
  const _CockpitLinuxCaptureFailure({
    required this.message,
    required this.attempts,
  });

  final String message;
  final List<Map<String, Object?>> attempts;

  @override
  String toString() => message;
}
