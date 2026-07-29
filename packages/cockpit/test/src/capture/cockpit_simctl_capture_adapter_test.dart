import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/src/capture/cockpit_simctl_capture_adapter.dart';
import 'package:test/test.dart';

void main() {
  CockpitCommand captureCommand({
    CockpitScreenshotReason reason = CockpitScreenshotReason.acceptance,
    int? timeoutMs,
  }) {
    return CockpitCommand(
      commandId: 'simctl-capture',
      commandType: CockpitCommandType.captureScreenshot,
      timeoutMs: timeoutMs,
      screenshotRequest: CockpitScreenshotRequest(
        reason: reason,
        name: 'simctl-home',
      ),
    );
  }

  test('simctl capture writes the screenshot artifact', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'cockpit_simctl_capture_test',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });
    final commands = <List<String>>[];

    final adapter = CockpitSimctlCaptureAdapter(
      deviceId: 'SIM-UDID',
      processRunner: (executable, arguments) async {
        commands.add(<String>[executable, ...arguments]);
        final outputPath = arguments.last;
        File(outputPath).writeAsBytesSync(_opaqueBlackPng);
        return ProcessResult(0, 0, '', '');
      },
      tempFileFactory: (fileName) async => File('${tempDir.path}/$fileName'),
    );

    final execution = await adapter.capture(captureCommand());

    expect(execution.result.success, isTrue);
    expect(commands.single.take(4), <String>[
      'xcrun',
      'simctl',
      'io',
      'SIM-UDID',
    ]);
    expect(commands.single[4], 'screenshot');
    final artifact = execution.result.artifacts.single;
    final sourcePath = execution.artifactSourcePaths[artifact.relativePath];
    expect(sourcePath, isNotNull);
    expect(File(sourcePath!).existsSync(), isTrue);
  });

  test('simctl diagnostic capture accepts a transparent PNG', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'cockpit_simctl_transparent_diagnostic_test',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });
    final outputFile = File('${tempDir.path}/diagnostic.png');
    final adapter = CockpitSimctlCaptureAdapter(
      deviceId: 'SIM-UDID',
      processRunner: (executable, arguments) async {
        outputFile.writeAsBytesSync(_transparentPng);
        return ProcessResult(0, 0, '', '');
      },
      tempFileFactory: (_) async => outputFile,
    );

    final execution = await adapter.capture(
      captureCommand(reason: CockpitScreenshotReason.baseline),
    );

    expect(execution.result.success, isTrue);
    expect(outputFile.existsSync(), isTrue);
  });

  test('simctl acceptance capture rejects a transparent PNG', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'cockpit_simctl_transparent_acceptance_test',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });
    final outputFile = File('${tempDir.path}/acceptance.png');
    final adapter = CockpitSimctlCaptureAdapter(
      deviceId: 'SIM-UDID',
      processRunner: (executable, arguments) async {
        outputFile.writeAsBytesSync(_transparentPng);
        return ProcessResult(0, 0, '', '');
      },
      tempFileFactory: (_) async => outputFile,
    );

    final execution = await adapter.capture(captureCommand());

    expect(execution.result.success, isFalse);
    expect(
      execution.result.error?.details['validationCode'],
      'screenshotFullyTransparent',
    );
    expect(outputFile.existsSync(), isFalse);
  });

  for (final reason in <CockpitScreenshotReason>[
    CockpitScreenshotReason.baseline,
    CockpitScreenshotReason.acceptance,
  ]) {
    test('simctl ${reason.name} capture rejects a truncated PNG', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_simctl_truncated_${reason.name}_test',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });
      final outputFile = File('${tempDir.path}/${reason.name}.png');
      final adapter = CockpitSimctlCaptureAdapter(
        deviceId: 'SIM-UDID',
        processRunner: (executable, arguments) async {
          outputFile.writeAsBytesSync(_truncatedPng);
          return ProcessResult(0, 0, '', '');
        },
        tempFileFactory: (_) async => outputFile,
      );

      final execution = await adapter.capture(captureCommand(reason: reason));

      expect(execution.result.success, isFalse);
      expect(
        execution.result.error?.details['validationCode'],
        'screenshotDecodeFailed',
      );
      expect(outputFile.existsSync(), isFalse);
    });
  }

  test('simctl capture surfaces failures with stderr details', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'cockpit_simctl_capture_fail_test',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    final adapter = CockpitSimctlCaptureAdapter(
      deviceId: 'SIM-UDID',
      processRunner: (executable, arguments) async {
        return ProcessResult(0, 1, '', 'Invalid device: SIM-UDID');
      },
      tempFileFactory: (fileName) async => File('${tempDir.path}/$fileName'),
    );

    final execution = await adapter.capture(captureCommand());

    expect(execution.result.success, isFalse);
    expect(
      execution.result.error?.details['stderr'],
      contains('Invalid device'),
    );
  });

  test('simctl capture honors the command timeout budget', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'cockpit_simctl_command_timeout_test',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    final adapter = CockpitSimctlCaptureAdapter(
      deviceId: 'SIM-UDID',
      timeout: const Duration(milliseconds: 1),
      processRunner: (executable, arguments) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        File(arguments.last).writeAsBytesSync(_opaqueBlackPng);
        return ProcessResult(0, 0, '', '');
      },
      tempFileFactory: (fileName) async => File('${tempDir.path}/$fileName'),
    );

    final execution = await adapter.capture(captureCommand(timeoutMs: 250));

    expect(execution.result.success, isTrue);
  });
}

final Uint8List _opaqueBlackPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQI12NgYGD4DwABBAEApOCsMQAAAABJRU5ErkJggg==',
);
final Uint8List _transparentPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVQI12NgAAIAAAUAAeImBZsAAAAASUVORK5CYII=',
);
final Uint8List _truncatedPng = Uint8List.sublistView(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVQI12O8rmb7n4GBgQEADj0CO1/m6EIAAAAASUVORK5CYII=',
  ),
  0,
  50,
);
