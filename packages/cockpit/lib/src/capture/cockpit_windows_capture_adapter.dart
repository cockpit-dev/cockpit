import 'dart:async';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../platform/windows/cockpit_windows_window_target.dart';
import '../platform/windows/cockpit_windows_powershell.dart';
import '../session/cockpit_session_process_runner.dart';
import 'cockpit_host_capture_adapter.dart';

final class CockpitWindowsCaptureAdapter implements CockpitHostCaptureAdapter {
  CockpitWindowsCaptureAdapter({
    required String appId,
    int? processId,
    String powershellExecutable = 'powershell',
    CockpitCaptureProcessRunner? processRunner,
    CockpitCaptureTempFileFactory tempFileFactory =
        cockpitCreateCaptureTempFile,
    CockpitWindowsWindowResolver windowResolver =
        cockpitResolveWindowsWindowTarget,
    Duration timeout = const Duration(seconds: 5),
    Duration activationSettleDelay = const Duration(milliseconds: 250),
  }) : _appId = appId,
       _processId = processId,
       _powershellExecutable = powershellExecutable,
       _processRunner = processRunner,
       _tempFileFactory = tempFileFactory,
       _windowResolver = windowResolver,
       _timeout = timeout,
       _activationSettleDelay = activationSettleDelay;

  final String _appId;
  final int? _processId;
  final String _powershellExecutable;
  final CockpitCaptureProcessRunner? _processRunner;
  final CockpitCaptureTempFileFactory _tempFileFactory;
  final CockpitWindowsWindowResolver _windowResolver;
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

    Future<ProcessResult> runProcess(
      String executable,
      List<String> arguments,
    ) => _runProcess(executable, arguments, timeout: remainingTimeout());

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
        powershellExecutable: _powershellExecutable,
        processRunner: runProcess,
        timeout: remainingTimeout(),
        activationSettleDelay: _activationSettleDelay,
      ).timeout(remainingTimeout());
      final result = await runProcess(
        _powershellExecutable,
        cockpitWindowsPowerShellCommand(
          _captureScript,
          arguments: <String>[
            outputFile.path,
            windowTarget.handle.toString(),
            windowTarget.left.toString(),
            windowTarget.top.toString(),
            windowTarget.width.toString(),
            windowTarget.height.toString(),
          ],
        ),
      );
      stopwatch.stop();

      if (result.exitCode != 0) {
        return cockpitFailedCaptureExecution(
          command: command,
          durationMs: stopwatch.elapsedMilliseconds,
          message: 'Windows host screenshot failed.',
          details: <String, Object?>{
            'appId': _appId,
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
        captureDescription: 'Windows host screenshot',
        details: <String, Object?>{'appId': _appId},
      );
    } on TimeoutException {
      stopwatch.stop();
      return cockpitFailedCaptureExecution(
        command: command,
        durationMs: stopwatch.elapsedMilliseconds,
        message: 'Windows host screenshot timed out.',
        details: <String, Object?>{'appId': _appId},
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

  static const String _captureScript = r'''
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System.Runtime.InteropServices;

public static class CockpitDpiInterop {
  [DllImport("user32.dll")]
  public static extern bool SetProcessDPIAware();

  [DllImport("user32.dll")]
  public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint flags);
}
"@
[void][CockpitDpiInterop]::SetProcessDPIAware()
$outputPath = $args[0]
$windowHandle = [IntPtr][long]$args[1]
$left = [int]$args[2]
$top = [int]$args[3]
$width = [int]$args[4]
$height = [int]$args[5]
$bitmap = New-Object System.Drawing.Bitmap $width, $height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$captured = $false
$deviceContext = $graphics.GetHdc()
try {
  $captured = [CockpitDpiInterop]::PrintWindow($windowHandle, $deviceContext, 2)
} finally {
  $graphics.ReleaseHdc($deviceContext)
}
if (-not $captured) {
  $graphics.CopyFromScreen(
    [System.Drawing.Point]::new($left, $top),
    [System.Drawing.Point]::Empty,
    [System.Drawing.Size]::new($width, $height)
  )
}
$bitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()
''';

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
