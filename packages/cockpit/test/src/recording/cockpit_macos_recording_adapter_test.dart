import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/src/platform/macos/cockpit_macos_window_target.dart';
import 'package:cockpit/src/recording/cockpit_host_recording_adapter.dart';
import 'package:cockpit/src/recording/cockpit_macos_recording_adapter.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  setUp(() {
    cockpitClearActiveHostRecordingSession('macos:com.google.Chrome');
  });

  tearDown(() {
    cockpitClearActiveHostRecordingSession('macos:com.google.Chrome');
  });

  test(
    'macos recording adapter starts and finalizes a host recording artifact',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_macos_recording_adapter',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final ffmpegExecutable = await _writeExecutable(
        directory: tempDir,
        name: 'ffmpeg',
        body: r'''
#!/bin/sh
script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
log_file="$script_dir/ffmpeg.log"
printf '%s\n' "$*" >> "$log_file"
if printf '%s' "$*" | grep -q -- '-list_devices true'; then
  printf '[1] Capture screen 0\n' >&2
  exit 0
fi
output_path=""
for arg in "$@"; do
  output_path="$arg"
done
printf 'Press [q] to stop\n' >&2
trap 'printf "macos-video" > "$output_path"; exit 0' INT
while true; do
  sleep 1
done
''',
      );

      final osascriptExecutable = await _writeExecutable(
        directory: tempDir,
        name: 'osascript',
        body: r'''
#!/bin/sh
exit 0
''',
      );

      final adapter = CockpitMacosRecordingAdapter(
        appId: 'dev.cockpit.cockpitDemo',
        ffmpegExecutable: ffmpegExecutable.path,
        osascriptExecutable: osascriptExecutable.path,
        startupTimeout: const Duration(seconds: 2),
        stopTimeout: const Duration(seconds: 2),
        finalizationPollInterval: const Duration(milliseconds: 10),
        ffprobeProcessRunner: (executable, arguments) async => ProcessResult(
          0,
          0,
          '{"format":{"duration":"2.000"},"streams":[{"codec_type":"video","nb_frames":"40"}]}',
          '',
        ),
      );

      final session = await adapter.startRecording(
        const CockpitRecordingRequest(
          purpose: CockpitRecordingPurpose.acceptance,
          name: 'host-macos-demo',
          attachToStep: true,
        ),
      );
      final result = await adapter.stopRecording();

      expect(session.state, CockpitRecordingState.recording);
      expect(result.state, CockpitRecordingState.completed);
      expect(
        result.artifact,
        const CockpitArtifactRef(
          role: 'recording',
          relativePath: 'recordings/host-macos-demo.mp4',
        ),
      );
      expect(File(result.sourceFilePath!).readAsStringSync(), 'macos-video');
      expect(
        File(p.join(tempDir.path, 'ffmpeg.log')).readAsStringSync(),
        contains('-f avfoundation'),
      );
    },
  );

  test(
    'macos recording adapter tolerates quiet startup when ffmpeg keeps running',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_macos_recording_adapter_quiet',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final ffmpegExecutable = await _writeExecutable(
        directory: tempDir,
        name: 'ffmpeg',
        body: r'''
#!/bin/sh
script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
log_file="$script_dir/ffmpeg.log"
printf '%s\n' "$*" >> "$log_file"
if printf '%s' "$*" | grep -q -- '-list_devices true'; then
  printf '[1] Capture screen 0\n' >&2
  exit 0
fi
output_path=""
for arg in "$@"; do
  output_path="$arg"
done
trap 'printf "quiet-macos-video" > "$output_path"; exit 0' INT
sleep 0.1
printf "startup-evidence" > "$output_path"
while true; do
  sleep 1
done
''',
      );

      final osascriptExecutable = await _writeExecutable(
        directory: tempDir,
        name: 'osascript',
        body: r'''
#!/bin/sh
exit 0
''',
      );

      final adapter = CockpitMacosRecordingAdapter(
        appId: 'dev.cockpit.cockpitDemo',
        ffmpegExecutable: ffmpegExecutable.path,
        osascriptExecutable: osascriptExecutable.path,
        startupTimeout: const Duration(milliseconds: 200),
        startupEvidenceTimeout: const Duration(seconds: 1),
        stopTimeout: const Duration(seconds: 2),
        finalizationPollInterval: const Duration(milliseconds: 10),
        ffprobeProcessRunner: (executable, arguments) async => ProcessResult(
          0,
          0,
          '{"format":{"duration":"1.500"},"streams":[{"codec_type":"video","nb_frames":"30"}]}',
          '',
        ),
      );

      final session = await adapter.startRecording(
        const CockpitRecordingRequest(
          purpose: CockpitRecordingPurpose.acceptance,
          name: 'quiet-startup-demo',
          attachToStep: true,
        ),
      );
      final result = await adapter.stopRecording();

      expect(session.state, CockpitRecordingState.recording);
      expect(result.state, CockpitRecordingState.completed);
      expect(
        File(result.sourceFilePath!).readAsStringSync(),
        'quiet-macos-video',
      );
    },
  );

  test(
    'macos recording adapter fails fast when ffmpeg never confirms startup or produces output',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_macos_recording_adapter_startup_failure',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final ffmpegExecutable = await _writeExecutable(
        directory: tempDir,
        name: 'ffmpeg',
        body: r'''
#!/bin/sh
if printf '%s' "$*" | grep -q -- '-list_devices true'; then
  printf '[1] Capture screen 0\n' >&2
  exit 0
fi
while true; do
  sleep 1
done
''',
      );

      final osascriptExecutable = await _writeExecutable(
        directory: tempDir,
        name: 'osascript',
        body: r'''
#!/bin/sh
exit 0
''',
      );

      final adapter = CockpitMacosRecordingAdapter(
        appId: 'dev.cockpit.cockpitDemo',
        ffmpegExecutable: ffmpegExecutable.path,
        osascriptExecutable: osascriptExecutable.path,
        startupTimeout: const Duration(milliseconds: 200),
        startupEvidenceTimeout: const Duration(milliseconds: 100),
        stopTimeout: const Duration(seconds: 2),
        finalizationPollInterval: const Duration(milliseconds: 10),
      );

      await expectLater(
        adapter.startRecording(
          const CockpitRecordingRequest(
            purpose: CockpitRecordingPurpose.acceptance,
            name: 'missing-startup-evidence',
            attachToStep: true,
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Ensure Screen Recording permission is granted'),
          ),
        ),
      );
    },
  );

  test(
    'macos recording adapter can stop an active session after the adapter instance is recreated',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_macos_recording_adapter_recreated',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final ffmpegExecutable = await _writeExecutable(
        directory: tempDir,
        name: 'ffmpeg',
        body: r'''
#!/bin/sh
script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
log_file="$script_dir/ffmpeg.log"
printf '%s\n' "$*" >> "$log_file"
if printf '%s' "$*" | grep -q -- '-list_devices true'; then
  printf '[1] Capture screen 0\n' >&2
  exit 0
fi
output_path=""
for arg in "$@"; do
  output_path="$arg"
done
printf 'Press [q] to stop\n' >&2
trap 'printf "recreated-macos-video" > "$output_path"; exit 0' INT
while true; do
  sleep 1
done
''',
      );

      final osascriptExecutable = await _writeExecutable(
        directory: tempDir,
        name: 'osascript',
        body: r'''
#!/bin/sh
exit 0
''',
      );

      CockpitMacosRecordingAdapter buildAdapter() {
        return CockpitMacosRecordingAdapter(
          appId: 'com.google.Chrome',
          ffmpegExecutable: ffmpegExecutable.path,
          osascriptExecutable: osascriptExecutable.path,
          startupTimeout: const Duration(seconds: 2),
          stopTimeout: const Duration(seconds: 2),
          finalizationPollInterval: const Duration(milliseconds: 10),
          ffprobeProcessRunner: (executable, arguments) async => ProcessResult(
            0,
            0,
            '{"format":{"duration":"2.000"},"streams":[{"codec_type":"video","nb_frames":"40"}]}',
            '',
          ),
        );
      }

      final startedAdapter = buildAdapter();
      await startedAdapter.startRecording(
        const CockpitRecordingRequest(
          purpose: CockpitRecordingPurpose.acceptance,
          name: 'host-macos-recreated',
          attachToStep: true,
        ),
      );

      final stoppedAdapter = buildAdapter();
      final result = await stoppedAdapter.stopRecording();

      expect(result.state, CockpitRecordingState.completed);
      expect(
        File(result.sourceFilePath!).readAsStringSync(),
        'recreated-macos-video',
      );
    },
  );

  test(
    'macos recording adapter gives browser-host capture more quiet startup time',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_macos_browser_recording_adapter',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final ffmpegExecutable = await _writeExecutable(
        directory: tempDir,
        name: 'ffmpeg',
        body: r'''
#!/bin/sh
script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
log_file="$script_dir/ffmpeg.log"
printf '%s\n' "$*" >> "$log_file"
if printf '%s' "$*" | grep -q -- '-list_devices true'; then
  printf '[1] Capture screen 0\n' >&2
  exit 0
fi
output_path=""
for arg in "$@"; do
  output_path="$arg"
done
printf '[avfoundation @ 0xc78808000] Overriding selected pixel format to use uyvy422 instead.\n' >&2
trap 'printf "browser-macos-video" > "$output_path"; exit 0' INT
sleep 3
printf "browser-startup-evidence" > "$output_path"
while true; do
  sleep 1
done
''',
      );

      final osascriptExecutable = await _writeExecutable(
        directory: tempDir,
        name: 'osascript',
        body: r'''
#!/bin/sh
exit 0
''',
      );

      final adapter = CockpitMacosRecordingAdapter(
        appId: 'com.google.Chrome',
        ffmpegExecutable: ffmpegExecutable.path,
        osascriptExecutable: osascriptExecutable.path,
        startupTimeout: const Duration(milliseconds: 200),
        startupEvidenceTimeout: const Duration(milliseconds: 100),
        stopTimeout: const Duration(seconds: 2),
        finalizationPollInterval: const Duration(milliseconds: 10),
        ffprobeProcessRunner: (executable, arguments) async => ProcessResult(
          0,
          0,
          '{"format":{"duration":"2.000"},"streams":[{"codec_type":"video","nb_frames":"40"}]}',
          '',
        ),
      );

      final session = await adapter.startRecording(
        const CockpitRecordingRequest(
          purpose: CockpitRecordingPurpose.acceptance,
          name: 'browser-host-demo',
          attachToStep: true,
        ),
      );
      final result = await adapter.stopRecording();

      expect(session.state, CockpitRecordingState.recording);
      expect(result.state, CockpitRecordingState.completed);
      expect(
        File(result.sourceFilePath!).readAsStringSync(),
        'browser-macos-video',
      );
    },
  );

  test(
    'macos recording adapter rejects pixel-format negotiation without recorded frames',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_macos_browser_pixel_format_recording_adapter',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final ffmpegExecutable = await _writeExecutable(
        directory: tempDir,
        name: 'ffmpeg',
        body: r'''
#!/bin/sh
script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
if printf '%s' "$*" | grep -q -- '-list_devices true'; then
  printf '[1] Capture screen 0\n' >&2
  exit 0
fi
output_path=""
for arg in "$@"; do
  output_path="$arg"
done
printf '[avfoundation @ 0xc78808000] Overriding selected pixel format to use uyvy422 instead.\n' >&2
trap 'printf "browser-pixel-format-video" > "$output_path"; exit 0' INT
while true; do
  sleep 1
done
''',
      );

      final osascriptExecutable = await _writeExecutable(
        directory: tempDir,
        name: 'osascript',
        body: r'''
#!/bin/sh
exit 0
''',
      );

      final adapter = CockpitMacosRecordingAdapter(
        appId: 'com.google.Chrome',
        ffmpegExecutable: ffmpegExecutable.path,
        osascriptExecutable: osascriptExecutable.path,
        startupTimeout: const Duration(milliseconds: 200),
        startupEvidenceTimeout: const Duration(milliseconds: 100),
        stopTimeout: const Duration(seconds: 2),
        finalizationPollInterval: const Duration(milliseconds: 10),
        ffprobeProcessRunner: (executable, arguments) async => ProcessResult(
          0,
          0,
          '{"format":{"duration":"2.000"},"streams":[{"codec_type":"video","nb_frames":"40"}]}',
          '',
        ),
      );

      await expectLater(
        adapter.startRecording(
          const CockpitRecordingRequest(
            purpose: CockpitRecordingPurpose.acceptance,
            name: 'browser-host-pixel-format-demo',
            attachToStep: true,
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('ffmpeg never confirmed macOS screen capture startup'),
              contains('Overriding selected pixel format'),
            ),
          ),
        ),
      );
    },
  );

  test(
    'macos recording adapter clears the active session after a failed stop so a new recording can start',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_macos_recording_adapter_retry_after_failed_stop',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final ffmpegExecutable = await _writeExecutable(
        directory: tempDir,
        name: 'ffmpeg',
        body: r'''
#!/bin/sh
script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
state_file="$script_dir/run-count"
if printf '%s' "$*" | grep -q -- '-list_devices true'; then
  printf '[1] Capture screen 0\n' >&2
  exit 0
fi
count=0
if [ -f "$state_file" ]; then
  count="$(cat "$state_file")"
fi
count=$((count + 1))
printf '%s' "$count" > "$state_file"
output_path=""
for arg in "$@"; do
  output_path="$arg"
done
printf 'Press [q] to stop\n' >&2
if [ "$count" -eq 1 ]; then
  trap 'exit 0' INT
else
  trap 'printf "retry-macos-video" > "$output_path"; exit 0' INT
fi
while true; do
  sleep 1
done
''',
      );

      final osascriptExecutable = await _writeExecutable(
        directory: tempDir,
        name: 'osascript',
        body: r'''
#!/bin/sh
exit 0
''',
      );

      CockpitMacosRecordingAdapter buildAdapter() {
        return CockpitMacosRecordingAdapter(
          appId: 'dev.cockpit.cockpitDemo',
          ffmpegExecutable: ffmpegExecutable.path,
          osascriptExecutable: osascriptExecutable.path,
          startupTimeout: const Duration(seconds: 2),
          stopTimeout: const Duration(seconds: 2),
          finalizationPollInterval: const Duration(milliseconds: 10),
          ffprobeProcessRunner: (executable, arguments) async {
            final countFile = File(p.join(tempDir.path, 'run-count'));
            final count = int.parse(countFile.readAsStringSync());
            if (count == 1) {
              return ProcessResult(
                0,
                0,
                '{"format":{"duration":"0.000"},"streams":[{"codec_type":"video","nb_frames":"0"}]}',
                '',
              );
            }
            return ProcessResult(
              0,
              0,
              '{"format":{"duration":"2.000"},"streams":[{"codec_type":"video","nb_frames":"40"}]}',
              '',
            );
          },
        );
      }

      final firstAdapter = buildAdapter();
      await firstAdapter.startRecording(
        const CockpitRecordingRequest(
          purpose: CockpitRecordingPurpose.acceptance,
          name: 'failed-stop-demo',
        ),
      );
      final firstResult = await firstAdapter.stopRecording();

      expect(firstResult.state, CockpitRecordingState.failed);

      final secondAdapter = buildAdapter();
      final secondSession = await secondAdapter.startRecording(
        const CockpitRecordingRequest(
          purpose: CockpitRecordingPurpose.acceptance,
          name: 'retry-stop-demo',
        ),
      );
      final secondResult = await secondAdapter.stopRecording();

      expect(secondSession.state, CockpitRecordingState.recording);
      expect(secondResult.state, CockpitRecordingState.completed);
      expect(
        File(secondResult.sourceFilePath!).readAsStringSync(),
        'retry-macos-video',
      );
    },
  );

  test(
    'macos recording adapter includes recent ffmpeg stderr when output is empty',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_macos_recording_adapter_empty_output_diagnostics',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final ffmpegExecutable = await _writeExecutable(
        directory: tempDir,
        name: 'ffmpeg',
        body: r'''
#!/bin/sh
if printf '%s' "$*" | grep -q -- '-list_devices true'; then
  printf '[1] Capture screen 0\n' >&2
  exit 0
fi
printf '[avfoundation @ 0x123] Input/output error while opening screen capture\n' >&2
printf 'Press [q] to stop\n' >&2
trap 'exit 0' INT
while true; do
  sleep 1
done
''',
      );

      final osascriptExecutable = await _writeExecutable(
        directory: tempDir,
        name: 'osascript',
        body: r'''
#!/bin/sh
exit 0
''',
      );

      final adapter = CockpitMacosRecordingAdapter(
        appId: 'com.google.Chrome',
        ffmpegExecutable: ffmpegExecutable.path,
        osascriptExecutable: osascriptExecutable.path,
        startupTimeout: const Duration(seconds: 2),
        stopTimeout: const Duration(seconds: 2),
        finalizationPollInterval: const Duration(milliseconds: 10),
      );

      final session = await adapter.startRecording(
        const CockpitRecordingRequest(
          purpose: CockpitRecordingPurpose.acceptance,
          name: 'empty-output-diagnostics',
        ),
      );
      final result = await adapter.stopRecording();

      expect(session.state, CockpitRecordingState.recording);
      expect(result.state, CockpitRecordingState.failed);
      expect(result.failureReason, contains('Recent ffmpeg output'));
      expect(
        result.failureReason,
        contains('Input/output error while opening screen capture'),
      );
    },
  );

  test(
    'macos recording adapter selects the capture screen that matches the target window coordinates',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_macos_recording_adapter_display_selection',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final ffmpegExecutable = await _writeExecutable(
        directory: tempDir,
        name: 'ffmpeg',
        body: r'''
#!/bin/sh
script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
log_file="$script_dir/ffmpeg.log"
printf '%s\n' "$*" >> "$log_file"
if printf '%s' "$*" | grep -q -- '-list_devices true'; then
  cat <<'EOF' >&2
[AVFoundation indev @ 0x111] AVFoundation video devices:
[AVFoundation indev @ 0x111] [0] Capture screen 0 1440x900 @ 0,0
[AVFoundation indev @ 0x111] [1] Capture screen 1 2560x1440 @ 1440,0
EOF
  exit 0
fi
output_path=""
for arg in "$@"; do
  output_path="$arg"
done
printf 'Press [q] to stop\n' >&2
trap 'printf "display-selected-video" > "$output_path"; exit 0' INT
while true; do
  sleep 1
done
''',
      );

      final osascriptExecutable = await _writeExecutable(
        directory: tempDir,
        name: 'osascript',
        body: r'''
#!/bin/sh
exit 0
''',
      );

      final adapter = CockpitMacosRecordingAdapter(
        appId: 'dev.cockpit.cockpitDemo',
        processId: 89688,
        ffmpegExecutable: ffmpegExecutable.path,
        osascriptExecutable: osascriptExecutable.path,
        windowTargetResolver:
            ({
              required appId,
              required processId,
              required osascriptExecutable,
              required processRunner,
              required timeout,
              required activationSettleDelay,
            }) async {
              expect(processId, 89688);
              return const CockpitMacosWindowTarget(
                left: 1680,
                top: 120,
                width: 1280,
                height: 720,
              );
            },
        startupTimeout: const Duration(seconds: 2),
        stopTimeout: const Duration(seconds: 2),
        finalizationPollInterval: const Duration(milliseconds: 10),
        ffprobeProcessRunner: (executable, arguments) async => ProcessResult(
          0,
          0,
          '{"format":{"duration":"2.000"},"streams":[{"codec_type":"video","nb_frames":"40"}]}',
          '',
        ),
      );

      final session = await adapter.startRecording(
        const CockpitRecordingRequest(
          purpose: CockpitRecordingPurpose.acceptance,
          name: 'host-macos-display-selection',
          attachToStep: true,
        ),
      );
      final result = await adapter.stopRecording();

      expect(session.state, CockpitRecordingState.recording);
      expect(result.state, CockpitRecordingState.completed);
      expect(
        File(result.sourceFilePath!).readAsStringSync(),
        'display-selected-video',
      );
      expect(
        File(p.join(tempDir.path, 'ffmpeg.log')).readAsStringSync(),
        contains('-i 1:none'),
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
