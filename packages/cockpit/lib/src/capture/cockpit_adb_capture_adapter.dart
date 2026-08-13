import 'dart:async';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../infrastructure/cockpit_process_output_collector.dart';
import '../infrastructure/cockpit_process_manager.dart';
import 'cockpit_host_capture_adapter.dart';

final class CockpitAdbCaptureAdapter implements CockpitHostCaptureAdapter {
  CockpitAdbCaptureAdapter({
    required String deviceId,
    String? platformAppId,
    String executable = 'adb',
    CockpitCaptureProcessStarter processStarter = cockpitStartIsolatedProcess,
    CockpitCaptureTempFileFactory tempFileFactory =
        cockpitCreateCaptureTempFile,
    Duration timeout = const Duration(seconds: 5),
  }) : _deviceId = deviceId,
       _platformAppId = platformAppId?.trim(),
       _executable = executable,
       _processStarter = processStarter,
       _tempFileFactory = tempFileFactory,
       _timeout = timeout;

  final String _deviceId;
  final String? _platformAppId;
  final String _executable;
  final CockpitCaptureProcessStarter _processStarter;
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
    final artifact = cockpitCaptureArtifactForRequest(request);
    final outputFile = await _tempFileFactory(
      cockpitCaptureFileName(request.name),
    );
    outputFile.parent.createSync(recursive: true);
    if (outputFile.existsSync()) {
      outputFile.deleteSync();
    }

    final process = await _processStarter(_executable, <String>[
      '-s',
      _deviceId,
      'exec-out',
      'screencap',
      '-p',
    ]);
    final sink = outputFile.openWrite();
    final stdoutDone = Completer<void>();
    var lastStdoutDataAt = DateTime.now();
    final stdoutSubscription = process.stdout.listen(
      (chunk) {
        lastStdoutDataAt = DateTime.now();
        sink.add(chunk);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!stdoutDone.isCompleted) {
          stdoutDone.completeError(error, stackTrace);
        }
      },
      onDone: () {
        if (!stdoutDone.isCompleted) {
          stdoutDone.complete();
        }
      },
      cancelOnError: true,
    );
    final stderrCollector = CockpitProcessOutputCollector(process.stderr);

    try {
      final exitCode = await process.exitCode.timeout(_timeout);
      await _waitForCaptureStream(stdoutDone.future, () => lastStdoutDataAt);
      await _cancelCaptureSubscription(stdoutSubscription);
      final stderr = await stderrCollector.collectText();
      await _closeCaptureSink(sink);
      stopwatch.stop();

      if (exitCode != 0) {
        return cockpitFailedCaptureExecution(
          command: command,
          durationMs: stopwatch.elapsedMilliseconds,
          message: 'adb screencap failed.',
          details: <String, Object?>{
            'deviceId': _deviceId,
            'exitCode': exitCode,
            'stderr': stderr.trim(),
          },
        );
      }
      final execution = await cockpitValidateHostCaptureOutput(
        command: command,
        artifact: artifact,
        durationMs: stopwatch.elapsedMilliseconds,
        outputFile: outputFile,
        captureDescription: 'adb screencap',
        details: <String, Object?>{'deviceId': _deviceId},
      );
      if (!execution.result.success) return execution;
      final surface = await _readSurfaceRelation();
      if (surface == null) return execution;
      final result = execution.result;
      return CockpitCommandExecution(
        result: CockpitCommandResult(
          success: result.success,
          commandId: result.commandId,
          commandType: result.commandType,
          locatorResolution: result.locatorResolution,
          durationMs: result.durationMs,
          artifacts: result.artifacts,
          requestedCaptureProfile: result.requestedCaptureProfile,
          resolvedCaptureKind: result.resolvedCaptureKind,
          usedCaptureFallback: result.usedCaptureFallback,
          degradationReason: surface['relation'] == 'differentApp'
              ? 'systemSurfaceMismatch'
              : result.degradationReason,
          surface: surface,
          changed: result.changed,
          error: result.error,
        ),
        artifactPayloads: execution.artifactPayloads,
        artifactSourcePaths: execution.artifactSourcePaths,
        runtimeSteps: execution.runtimeSteps,
      );
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await _cancelCaptureSubscription(stdoutSubscription);
      await stderrCollector.cancel();
      await _closeCaptureSink(sink);
      stopwatch.stop();
      return cockpitFailedCaptureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        message: 'adb screencap timed out.',
        details: <String, Object?>{'deviceId': _deviceId},
      );
    } on Object catch (error) {
      process.kill(ProcessSignal.sigkill);
      await _cancelCaptureSubscription(stdoutSubscription);
      await stderrCollector.cancel();
      await _closeCaptureSink(sink);
      stopwatch.stop();
      return cockpitFailedCaptureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        message: 'adb screencap threw an unexpected error.',
        details: <String, Object?>{
          'deviceId': _deviceId,
          'error': error.toString(),
        },
      );
    }
  }

  Future<Map<String, Object?>?> _readSurfaceRelation() async {
    final expectedPackage = _platformAppId;
    if (expectedPackage == null || expectedPackage.isEmpty) return null;
    try {
      final process = await _processStarter(_executable, <String>[
        '-s',
        _deviceId,
        'shell',
        'dumpsys',
        'window',
      ]);
      final stdoutCollector = CockpitProcessOutputCollector(process.stdout);
      final stderrCollector = CockpitProcessOutputCollector(process.stderr);
      final exitCode = await process.exitCode.timeout(
        const Duration(milliseconds: 750),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      final output = await Future.wait(<Future<String>>[
        stdoutCollector.collectText(),
        stderrCollector.collectText(),
      ]);
      if (exitCode != 0) {
        return <String, Object?>{'relation': 'unknown', 'app': expectedPackage};
      }
      final focusLine = output.first
          .split('\n')
          .map((line) => line.trim())
          .firstWhere(
            (line) =>
                line.contains('mCurrentFocus=') ||
                line.contains('mFocusedWindow='),
            orElse: () => '',
          );
      final focusedSurface = _focusedSurface(focusLine);
      final focusedPackage = focusedSurface.packageId;
      final relation = focusedSurface.systemOverlay
          ? 'systemOverlay'
          : focusedPackage == null
          ? 'unknown'
          : focusedPackage == expectedPackage
          ? 'app'
          : _isAndroidSystemPackage(focusedPackage)
          ? 'systemOverlay'
          : 'differentApp';
      return <String, Object?>{
        'relation': relation,
        if (relation != 'app') 'app': expectedPackage,
        if (focusedPackage != null && relation != 'app')
          'front': focusedPackage,
      };
    } on Object {
      return <String, Object?>{'relation': 'unknown', 'app': expectedPackage};
    }
  }
}

({String? packageId, bool systemOverlay}) _focusedSurface(String line) {
  if (line.isEmpty) return (packageId: null, systemOverlay: false);
  final systemError = RegExp(
    r'(?:Application Not Responding|Application Error):\s*'
    r'([A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+)',
  ).firstMatch(line);
  if (systemError != null) {
    return (packageId: systemError.group(1), systemOverlay: true);
  }
  final component = RegExp(
    r'([A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+)/[A-Za-z0-9_.$]+',
  ).firstMatch(line);
  return (packageId: component?.group(1), systemOverlay: false);
}

bool _isAndroidSystemPackage(String packageId) {
  return const <String>{
    'android',
    'com.android.systemui',
    'com.android.permissioncontroller',
    'com.google.android.permissioncontroller',
    'com.android.packageinstaller',
    'com.google.android.packageinstaller',
  }.contains(packageId);
}

// Drain pending stdout after process exit: keep reading while data is still
// arriving (slow pipe must not truncate the PNG) but return quickly once the
// pipe goes quiet, because an inherited stdout handle never closes.
Future<void> _waitForCaptureStream(
  Future<void> done,
  DateTime Function() lastDataAt,
) async {
  const maxDrain = Duration(seconds: 2);
  const quietWindow = Duration(milliseconds: 150);
  final deadline = DateTime.now().add(maxDrain);
  var isDone = false;
  Object? streamError;
  StackTrace? streamStackTrace;
  unawaited(
    done.then(
      (_) => isDone = true,
      onError: (Object error, StackTrace stackTrace) {
        streamError = error;
        streamStackTrace = stackTrace;
        isDone = true;
      },
    ),
  );
  while (!isDone && DateTime.now().isBefore(deadline)) {
    if (DateTime.now().difference(lastDataAt()) >= quietWindow) {
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  // A mid-stream read error means the PNG may be truncated; surface it so the
  // capture reports failure instead of shipping a corrupt artifact as success.
  if (streamError != null) {
    Error.throwWithStackTrace(
      streamError!,
      streamStackTrace ?? StackTrace.current,
    );
  }
}

Future<void> _cancelCaptureSubscription(
  StreamSubscription<List<int>> subscription,
) async {
  try {
    await subscription.cancel().timeout(const Duration(milliseconds: 200));
  } on Object {
    // Best-effort process stream cleanup only.
  }
}

Future<void> _closeCaptureSink(IOSink sink) async {
  try {
    await sink.flush().timeout(const Duration(milliseconds: 200));
  } on Object {
    // The failure result below is more useful than a sink cleanup error.
  }
  try {
    await sink.close().timeout(const Duration(milliseconds: 200));
  } on Object {
    // The temp file may already be closed after a stream error.
  }
}
