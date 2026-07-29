import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/src/capture/cockpit_macos_capture_adapter.dart';
import 'package:cockpit/src/platform/macos/cockpit_macos_window_target.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'macos capture adapter activates the app and writes a screenshot',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_macos_capture_adapter',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final executable = await _writeExecutable(
        directory: tempDir,
        name: 'macos-capture-tool',
        body: r'''
#!/bin/sh
script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
log_file="$script_dir/macos-capture.log"
printf '%s\n' "$*" >> "$log_file"
if [ "$1" = "-e" ]; then
  exit 0
fi
last_arg=""
for arg in "$@"; do
  last_arg="$arg"
done
cp "$script_dir/opaque.png" "$last_arg"
''',
      );
      await File(p.join(tempDir.path, 'opaque.png')).writeAsBytes(_opaquePng);

      final adapter = CockpitMacosCaptureAdapter(
        appId: 'dev.cockpit.cockpitDemo',
        osascriptExecutable: executable.path,
        screencaptureExecutable: executable.path,
        windowTargetResolver:
            ({
              required appId,
              required osascriptExecutable,
              required processRunner,
              required timeout,
              required activationSettleDelay,
            }) async {
              expect(appId, 'dev.cockpit.cockpitDemo');
              expect(osascriptExecutable, executable.path);
              return const CockpitMacosWindowTarget(
                windowId: 1234,
                left: 48,
                top: 64,
                width: 960,
                height: 720,
              );
            },
        activationSettleDelay: Duration.zero,
      );

      final execution = await adapter.capture(
        CockpitCommand(
          commandId: 'capture-1',
          commandType: CockpitCommandType.captureScreenshot,
          screenshotRequest: const CockpitScreenshotRequest(
            reason: CockpitScreenshotReason.acceptance,
            name: 'macos-acceptance',
            attachToStep: true,
          ),
        ),
      );

      expect(execution.result.success, isTrue);
      expect(
        execution.result.artifacts.single.relativePath,
        matches(
          RegExp(
            r'^screenshots/\d{8}T\d{12}Z_macos_acceptance_acceptance\.png$',
          ),
        ),
      );
      expect(execution.artifactSourcePaths, isNotEmpty);
      final sourcePath = execution.artifactSourcePaths.values.single;
      expect(File(sourcePath).readAsBytesSync(), _opaquePng);
      final log = File(
        p.join(tempDir.path, 'macos-capture.log'),
      ).readAsStringSync();
      expect(log, contains('-x'));
      expect(log, contains('-l'));
      expect(log, contains('1234'));
    },
  );

  test('macos capture adapter reports window resolution failure', () async {
    final adapter = CockpitMacosCaptureAdapter(
      appId: 'dev.cockpit.cockpitDemo',
      windowTargetResolver:
          ({
            required appId,
            required osascriptExecutable,
            required processRunner,
            required timeout,
            required activationSettleDelay,
          }) async {
            throw StateError('No visible macOS window was found.');
          },
      activationSettleDelay: Duration.zero,
    );

    final execution = await adapter.capture(
      CockpitCommand(
        commandId: 'capture-2',
        commandType: CockpitCommandType.captureScreenshot,
        screenshotRequest: const CockpitScreenshotRequest(
          reason: CockpitScreenshotReason.acceptance,
          name: 'macos-window-missing',
        ),
      ),
    );

    expect(execution.result.success, isFalse);
    expect(execution.result.error?.message, 'macOS host screenshot failed.');
    expect(
      execution.result.error?.details,
      containsPair('appId', 'dev.cockpit.cockpitDemo'),
    );
    expect(
      execution.result.error?.details['error'],
      contains('No visible macOS window was found.'),
    );
  });

  test(
    'macos capture adapter retries failed window capture by bounds',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_macos_capture_bounds_fallback',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) await tempDir.delete(recursive: true);
      });
      final output = File(p.join(tempDir.path, 'capture.png'));
      final invocations = <List<String>>[];
      final adapter = CockpitMacosCaptureAdapter(
        appId: 'dev.cockpit.cockpitDemo',
        tempFileFactory: (_) async => output,
        processRunner: (_, arguments) async {
          invocations.add(List<String>.from(arguments));
          if (arguments.contains('-l')) {
            return ProcessResult(
              0,
              1,
              '',
              'could not create image from window',
            );
          }
          await output.writeAsBytes(_opaquePng);
          return ProcessResult(0, 0, '', '');
        },
        windowTargetResolver:
            ({
              required appId,
              required osascriptExecutable,
              required processRunner,
              required timeout,
              required activationSettleDelay,
            }) async => const CockpitMacosWindowTarget(
              windowId: 1234,
              left: 48,
              top: 64,
              width: 960,
              height: 720,
            ),
        activationSettleDelay: Duration.zero,
      );

      final execution = await adapter.capture(
        CockpitCommand(
          commandId: 'capture-fallback',
          commandType: CockpitCommandType.captureScreenshot,
          screenshotRequest: const CockpitScreenshotRequest(
            reason: CockpitScreenshotReason.acceptance,
            name: 'macos-bounds-fallback',
          ),
        ),
      );

      expect(execution.result.success, isTrue);
      expect(invocations, hasLength(2));
      expect(invocations.first, containsAllInOrder(<String>['-l', '1234']));
      expect(
        invocations.last,
        containsAllInOrder(<String>['-R', '48,64,960,720']),
      );
    },
  );
}

Future<File> _writeExecutable({
  required Directory directory,
  required String name,
  required String body,
}) async {
  final file = File(p.join(directory.path, name));
  await file.writeAsString(body);
  await Process.run('chmod', <String>['+x', file.path]);
  return file;
}

final List<int> _opaquePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVQI12O8rmb7n4GBgQEADj0CO1/m6EIAAAAASUVORK5CYII=',
);
