import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/src/capture/cockpit_windows_capture_adapter.dart';
import 'package:cockpit/src/platform/windows/cockpit_windows_screen_capture.dart';
import 'package:cockpit/src/platform/windows/cockpit_windows_window_target.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('windows capture adapter writes an in-process screen capture', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'cockpit_windows_capture_adapter',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    late CockpitWindowsWindowTarget capturedTarget;
    late File capturedOutputFile;
    late Duration capturedTimeout;
    final outputFile = File(p.join(tempDir.path, 'acceptance.png'));
    final adapter = CockpitWindowsCaptureAdapter(
      appId: 'cockpit_demo',
      processId: 4101,
      tempFileFactory: (_) async => outputFile,
      windowResolver: _windowResolver,
      screenCaptureWriter:
          ({required target, required outputFile, required timeout}) async {
            capturedTarget = target;
            capturedOutputFile = outputFile;
            capturedTimeout = timeout;
            outputFile.writeAsBytesSync(_opaquePng);
          },
    );

    final execution = await adapter.capture(
      CockpitCommand(
        commandId: 'capture-1',
        commandType: CockpitCommandType.captureScreenshot,
        screenshotRequest: const CockpitScreenshotRequest(
          reason: CockpitScreenshotReason.acceptance,
          name: 'windows-acceptance',
          attachToStep: true,
        ),
      ),
    );

    expect(execution.result.success, isTrue);
    expect(
      execution.result.artifacts.single.relativePath,
      matches(
        RegExp(
          r'^screenshots/\d{8}T\d{12}Z_windows_acceptance_acceptance\.png$',
        ),
      ),
    );
    expect(execution.artifactSourcePaths, isNotEmpty);
    expect(outputFile.readAsBytesSync(), _opaquePng);
    expect(capturedTarget.processId, 4101);
    expect(capturedTarget.left, 120);
    expect(capturedTarget.top, 48);
    expect(capturedTarget.width, 900);
    expect(capturedTarget.height, 640);
    expect(capturedOutputFile.path, outputFile.path);
    expect(capturedTimeout, greaterThan(Duration.zero));
  });

  test('windows capture adapter times out stalled native capture', () async {
    final adapter = CockpitWindowsCaptureAdapter(
      appId: 'cockpit_demo',
      timeout: const Duration(milliseconds: 50),
      windowResolver: _windowResolver,
      screenCaptureWriter:
          ({required target, required outputFile, required timeout}) {
            return Future<void>.delayed(const Duration(milliseconds: 150));
          },
    );

    final execution = await adapter.capture(
      CockpitCommand(
        commandId: 'capture-2',
        commandType: CockpitCommandType.captureScreenshot,
        screenshotRequest: const CockpitScreenshotRequest(
          reason: CockpitScreenshotReason.acceptance,
          name: 'windows-timeout',
        ),
      ),
    );

    expect(execution.result.success, isFalse);
    expect(
      execution.result.error?.message,
      'Windows host screenshot timed out.',
    );
  });

  test('windows capture adapter honors the command timeout budget', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'cockpit_windows_capture_command_timeout',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    final outputFile = File(p.join(tempDir.path, 'command-budget.png'));
    final adapter = CockpitWindowsCaptureAdapter(
      appId: 'cockpit_demo',
      timeout: const Duration(milliseconds: 50),
      tempFileFactory: (_) async => outputFile,
      windowResolver: _windowResolver,
      screenCaptureWriter:
          ({required target, required outputFile, required timeout}) async {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            outputFile.writeAsBytesSync(_opaquePng);
          },
    );

    final execution = await adapter.capture(
      CockpitCommand(
        commandId: 'capture-command-budget',
        commandType: CockpitCommandType.captureScreenshot,
        timeoutMs: 500,
        screenshotRequest: const CockpitScreenshotRequest(
          reason: CockpitScreenshotReason.acceptance,
          name: 'windows-command-budget',
        ),
      ),
    );

    expect(execution.result.success, isTrue);
    expect(outputFile.readAsBytesSync(), _opaquePng);
  });

  test('windows capture adapter reports native capture failure', () async {
    final adapter = CockpitWindowsCaptureAdapter(
      appId: 'cockpit_demo',
      windowResolver: _windowResolver,
      screenCaptureWriter:
          ({required target, required outputFile, required timeout}) async {
            throw const CockpitWindowsScreenCaptureException(
              'windowsScreenCopyFailed',
              'Windows could not copy the requested screen bounds.',
            );
          },
    );

    final execution = await adapter.capture(
      CockpitCommand(
        commandId: 'capture-3',
        commandType: CockpitCommandType.captureScreenshot,
        screenshotRequest: const CockpitScreenshotRequest(
          reason: CockpitScreenshotReason.acceptance,
          name: 'windows-window-missing',
        ),
      ),
    );

    expect(execution.result.success, isFalse);
    expect(execution.result.error?.message, 'Windows host screenshot failed.');
    expect(
      execution.result.error?.details,
      containsPair('appId', 'cockpit_demo'),
    );
    expect(
      execution.result.error?.details,
      containsPair('errorCode', 'windowsScreenCopyFailed'),
    );
  });

  test('windows capture adapter preserves window resolution failure', () async {
    final adapter = CockpitWindowsCaptureAdapter(
      appId: 'cockpit_demo',
      windowResolver:
          ({
            required appId,
            required processId,
            required timeout,
            required activationSettleDelay,
          }) async {
            throw const CockpitWindowsWindowException(
              'windowsWindowAmbiguous',
              'Multiple windows match cockpit_demo.',
            );
          },
    );

    final execution = await adapter.capture(
      CockpitCommand(
        commandId: 'capture-window-ambiguous',
        commandType: CockpitCommandType.captureScreenshot,
        screenshotRequest: const CockpitScreenshotRequest(
          reason: CockpitScreenshotReason.acceptance,
          name: 'windows-window-ambiguous',
        ),
      ),
    );

    expect(execution.result.success, isFalse);
    expect(execution.result.error?.message, 'Windows host screenshot failed.');
    expect(
      execution.result.error?.details,
      containsPair('errorCode', 'windowsWindowAmbiguous'),
    );
  });

  test('windows BGRA capture encoding produces an opaque PNG', () {
    final png = cockpitEncodeWindowsBgraPng(
      width: 2,
      height: 1,
      bytes: Uint8List.fromList(<int>[0, 0, 255, 0, 0, 255, 0, 0]),
    );

    final image = img.decodePng(png);
    expect(image, isNotNull);
    final red = image!.getPixel(0, 0);
    final green = image.getPixel(1, 0);
    expect((red.r, red.g, red.b, red.a), (255, 0, 0, 255));
    expect((green.r, green.g, green.b, green.a), (0, 255, 0, 255));
  });
}

Future<CockpitWindowsWindowTarget> _windowResolver({
  required String appId,
  required int? processId,
  required Duration timeout,
  required Duration activationSettleDelay,
}) async => CockpitWindowsWindowTarget(
  processId: processId ?? 4101,
  title: 'Cockpit Demo',
  handle: 4242,
  left: 120,
  top: 48,
  width: 900,
  height: 640,
);

final List<int> _opaquePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVQI12O8rmb7n4GBgQEADj0CO1/m6EIAAAAASUVORK5CYII=',
);
