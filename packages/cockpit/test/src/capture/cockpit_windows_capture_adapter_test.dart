import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/src/capture/cockpit_windows_capture_adapter.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'windows capture adapter runs powershell capture and writes a screenshot',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_windows_capture_adapter',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final invocations = <List<String>>[];
      final outputFile = File(p.join(tempDir.path, 'acceptance.png'));
      final adapter = CockpitWindowsCaptureAdapter(
        appId: 'cockpit_demo',
        processId: 4101,
        tempFileFactory: (_) async => outputFile,
        processRunner: (executable, arguments) async {
          expect(executable, 'powershell');
          invocations.add(List<String>.from(arguments));
          outputFile.writeAsBytesSync(_opaquePng);
          return ProcessResult(0, 0, '', '');
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
      expect(invocations.single[0], '-NoProfile');
      expect(invocations.single[1], '-NonInteractive');
      expect(invocations.single[2], '-EncodedCommand');
      final script = _decodeWindowsPowerShellEncodedCommand(
        invocations.single[3],
      );
      expect(script, isNot(contains('PrimaryScreen.Bounds')));
      expect(script, isNot(contains('PrintWindow')));
      expect(script, contains('CopyFromScreen'));
      expect(script, contains('GetWindowRect'));
      expect(script, contains(r'$outputPath = $args[0]'));
      expect(script, contains(r'$appId = $args[1]'));
      expect(script, contains("} '${outputFile.path.replaceAll("'", "''")}'"));
      expect(script, contains("'cockpit_demo' '4101' '250'"));
    },
  );

  test(
    'windows capture adapter times out stalled powershell capture',
    () async {
      final adapter = CockpitWindowsCaptureAdapter(
        appId: 'cockpit_demo',
        timeout: const Duration(milliseconds: 50),
        processRunner: (executable, arguments) {
          return Future<ProcessResult>.delayed(
            const Duration(milliseconds: 150),
            () => ProcessResult(0, 0, '', ''),
          );
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
    },
  );

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
      processRunner: (executable, arguments) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        outputFile.writeAsBytesSync(_opaquePng);
        return ProcessResult(0, 0, '', '');
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

  test('windows capture adapter reports capture process failure', () async {
    final adapter = CockpitWindowsCaptureAdapter(
      appId: 'cockpit_demo',
      processRunner: (executable, arguments) async =>
          ProcessResult(0, 1, '', 'No visible Windows window was found.'),
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
      execution.result.error?.details['stderr'],
      contains('No visible Windows window was found.'),
    );
  });
}

String _decodeWindowsPowerShellEncodedCommand(String encoded) {
  final bytes = base64.decode(encoded);
  return String.fromCharCodes(<int>[
    for (var index = 0; index < bytes.length; index += 2)
      bytes[index] | (bytes[index + 1] << 8),
  ]);
}

final List<int> _opaquePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVQI12O8rmb7n4GBgQEADj0CO1/m6EIAAAAASUVORK5CYII=',
);
