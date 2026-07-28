import 'dart:async';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';

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
    Duration timeout = const Duration(seconds: 5),
    Duration activationSettleDelay = const Duration(milliseconds: 250),
  }) : _appId = appId,
       _processId = processId,
       _powershellExecutable = powershellExecutable,
       _processRunner = processRunner,
       _tempFileFactory = tempFileFactory,
       _timeout = timeout,
       _activationSettleDelay = activationSettleDelay;

  final String _appId;
  final int? _processId;
  final String _powershellExecutable;
  final CockpitCaptureProcessRunner? _processRunner;
  final CockpitCaptureTempFileFactory _tempFileFactory;
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
      final result = await _runProcess(
        _powershellExecutable,
        cockpitWindowsPowerShellCommand(
          _captureScript,
          arguments: <String>[
            outputFile.path,
            _appId,
            _processId?.toString() ?? '',
            _activationSettleDelay.inMilliseconds.toString(),
          ],
        ),
        timeout: remainingTimeout(),
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
Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class CockpitCaptureInterop {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
  }

  [DllImport("user32.dll")]
  public static extern bool SetProcessDPIAware();

  [DllImport("user32.dll")]
  [return: MarshalAs(UnmanagedType.Bool)]
  public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

  [DllImport("user32.dll")]
  [return: MarshalAs(UnmanagedType.Bool)]
  public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);

  [DllImport("user32.dll")]
  [return: MarshalAs(UnmanagedType.Bool)]
  public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@
[void][CockpitCaptureInterop]::SetProcessDPIAware()
$outputPath = $args[0]
$appId = $args[1]
$targetProcessIdArg = $args[2]
$settleMs = [int]$args[3]
if ([string]::IsNullOrWhiteSpace($targetProcessIdArg)) {
  $process = Get-Process -Name $appId -ErrorAction Stop |
    Where-Object {
      $_.MainWindowHandle -ne 0 -and
      -not [string]::IsNullOrWhiteSpace($_.MainWindowTitle)
    } |
    Sort-Object -Property Id -Descending |
    Select-Object -First 1
} else {
  $targetProcessId = [int]$targetProcessIdArg
  $process = Get-Process -Id $targetProcessId -ErrorAction Stop |
    Where-Object {
      $_.MainWindowHandle -ne 0 -and
      -not [string]::IsNullOrWhiteSpace($_.MainWindowTitle)
    } |
    Select-Object -First 1
}
if ($null -eq $process) {
  if ([string]::IsNullOrWhiteSpace($targetProcessIdArg)) {
    throw "No visible main window was found for process $appId."
  }
  throw "No visible main window was found for process id $targetProcessIdArg."
}
$windowHandle = [IntPtr]$process.MainWindowHandle
try {
  [Microsoft.VisualBasic.Interaction]::AppActivate($process.Id) | Out-Null
} catch {}
[void][CockpitCaptureInterop]::ShowWindowAsync($windowHandle, 9)
[void][CockpitCaptureInterop]::SetForegroundWindow($windowHandle)
if ($settleMs -gt 0) {
  Start-Sleep -Milliseconds $settleMs
}
$rect = New-Object CockpitCaptureInterop+RECT
if (-not [CockpitCaptureInterop]::GetWindowRect($windowHandle, [ref]$rect)) {
  throw "GetWindowRect failed for process $appId."
}
$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top
if ($width -le 0 -or $height -le 0) {
  throw "Resolved invalid bounds for process ${appId}: $($rect.Left),$($rect.Top),$width,$height"
}
$bitmap = New-Object System.Drawing.Bitmap $width, $height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
try {
  $graphics.CopyFromScreen(
    [System.Drawing.Point]::new($rect.Left, $rect.Top),
    [System.Drawing.Point]::Empty,
    [System.Drawing.Size]::new($width, $height)
  )
  $bitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
  $graphics.Dispose()
  $bitmap.Dispose()
}
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
