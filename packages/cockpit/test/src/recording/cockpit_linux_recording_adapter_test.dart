import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/src/platform/linux/cockpit_linux_window_target.dart';
import 'package:cockpit/src/recording/cockpit_linux_recording_adapter.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'linux recording adapter starts and finalizes a host recording artifact',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_linux_recording_adapter',
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
output_path=""
for arg in "$@"; do
  output_path="$arg"
done
printf 'Output #0\n' >&2
printf "startup-evidence" > "$output_path"
while IFS= read -r line; do
  if [ "$line" = "q" ]; then
    printf "linux-video" > "$output_path"
    exit 0
  fi
done
''',
      );

      final adapter = CockpitLinuxRecordingAdapter(
        appId: 'cockpit_demo',
        ffmpegExecutable: ffmpegExecutable.path,
        windowActivatorExecutable: null,
        windowTargetResolver:
            ({
              required appId,
              required processId,
              required processRunner,
              required timeout,
            }) async {
              throw StateError('window resolution unavailable');
            },
        displayConfigResolver: () async => const CockpitLinuxDisplayConfig(
          display: ':99',
          captureSize: '1440x900',
        ),
        startupTimeout: const Duration(seconds: 2),
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
          name: 'host-linux-demo',
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
          relativePath: 'recordings/host-linux-demo.mp4',
        ),
      );
      expect(File(result.sourceFilePath!).readAsStringSync(), 'linux-video');
      final log = File(p.join(tempDir.path, 'ffmpeg.log')).readAsStringSync();
      expect(log, contains('-f x11grab'));
      expect(log, contains('-video_size 1440x900'));
      expect(log, contains('-i :99+0,0'));
    },
  );

  test(
    'linux recording adapter tolerates quiet startup when ffmpeg keeps running',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_linux_recording_adapter_quiet',
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
if printf '%s' "$*" | grep -q -- 'wmctrl'; then
  exit 0
fi
output_path=""
for arg in "$@"; do
  output_path="$arg"
done
sleep 0.1
printf "startup-evidence" > "$output_path"
while IFS= read -r line; do
  if [ "$line" = "q" ]; then
    printf "quiet-linux-video" > "$output_path"
    exit 0
  fi
done
''',
      );

      final adapter = CockpitLinuxRecordingAdapter(
        appId: 'cockpit_demo',
        ffmpegExecutable: ffmpegExecutable.path,
        windowActivatorExecutable: null,
        displayConfigResolver: () async => const CockpitLinuxDisplayConfig(
          display: ':99',
          captureSize: '1440x900',
        ),
        startupTimeout: const Duration(milliseconds: 500),
        startupEvidenceTimeout: const Duration(seconds: 2),
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
          name: 'quiet-linux-demo',
          attachToStep: true,
        ),
      );
      final result = await adapter.stopRecording();

      expect(session.state, CockpitRecordingState.recording);
      expect(result.state, CockpitRecordingState.completed);
      expect(
        File(result.sourceFilePath!).readAsStringSync(),
        'quiet-linux-video',
      );
    },
  );

  test(
    'linux recording adapter activates the resolved window for a specific process id',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_linux_recording_adapter_activation',
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
output_path=""
for arg in "$@"; do
  output_path="$arg"
done
printf 'Output #0\n' >&2
printf "startup-evidence" > "$output_path"
while IFS= read -r line; do
  if [ "$line" = "q" ]; then
    printf "linux-video" > "$output_path"
    exit 0
  fi
done
''',
      );
      final wmctrlExecutable = await _writeExecutable(
        directory: tempDir,
        name: 'wmctrl',
        body: r'''
#!/bin/sh
script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
printf '%s\n' "$*" > "$script_dir/wmctrl.log"
exit 0
''',
      );

      final adapter = CockpitLinuxRecordingAdapter(
        appId: 'cockpit_demo',
        processId: 5101,
        ffmpegExecutable: ffmpegExecutable.path,
        windowActivatorExecutable: wmctrlExecutable.path,
        windowTargetResolver:
            ({
              required appId,
              required processId,
              required processRunner,
              required timeout,
            }) async {
              expect(appId, 'cockpit_demo');
              expect(processId, 5101);
              return const CockpitLinuxWindowTarget(
                windowId: '0x02c00007',
                left: 120,
                top: 48,
                width: 900,
                height: 640,
              );
            },
        displayConfigResolver: () async => const CockpitLinuxDisplayConfig(
          display: ':99',
          captureSize: '1440x900',
        ),
        startupTimeout: const Duration(seconds: 2),
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
          name: 'host-linux-activation-demo',
          attachToStep: true,
        ),
      );
      final result = await adapter.stopRecording();

      expect(session.state, CockpitRecordingState.recording);
      expect(result.state, CockpitRecordingState.completed);
      expect(
        File(p.join(tempDir.path, 'wmctrl.log')).readAsStringSync().trim(),
        '-ia 0x02c00007',
      );
    },
  );

  test(
    'linux recording adapter records the resolved window instead of the full display when a target window is available',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_linux_recording_adapter_window_target',
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
output_path=""
for arg in "$@"; do
  output_path="$arg"
done
printf 'Output #0\n' >&2
printf "startup-evidence" > "$output_path"
while IFS= read -r line; do
  if [ "$line" = "q" ]; then
    printf "linux-window-video" > "$output_path"
    exit 0
  fi
done
''',
      );

      final adapter = CockpitLinuxRecordingAdapter(
        appId: 'cockpit_demo',
        processId: 5101,
        ffmpegExecutable: ffmpegExecutable.path,
        windowActivatorExecutable: null,
        windowTargetResolver:
            ({
              required appId,
              required processId,
              required processRunner,
              required timeout,
            }) async {
              return const CockpitLinuxWindowTarget(
                windowId: '0x02c00007',
                left: 120,
                top: 48,
                width: 900,
                height: 640,
              );
            },
        displayConfigResolver: () async => const CockpitLinuxDisplayConfig(
          display: ':99',
          captureSize: '1440x900',
        ),
        startupTimeout: const Duration(seconds: 2),
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
          name: 'host-linux-window-target-demo',
          attachToStep: true,
        ),
      );
      final result = await adapter.stopRecording();

      expect(session.state, CockpitRecordingState.recording);
      expect(result.state, CockpitRecordingState.completed);
      expect(
        File(result.sourceFilePath!).readAsStringSync(),
        'linux-window-video',
      );
      final log = File(p.join(tempDir.path, 'ffmpeg.log')).readAsStringSync();
      expect(log, contains('-window_id 0x02c00007'));
      expect(log, contains('-video_size 900x640'));
      expect(log, contains('-i :99'));
      expect(log, isNot(contains('-i :99+0,0')));
    },
  );

  test(
    'linux recording adapter fails fast without leaking a timed-out activation process',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_linux_recording_adapter_startup_failure',
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
if [ "$1" = "--activation-child" ]; then
  while true; do
    sleep 1
  done
fi
if [ "$1" = "-xa" ]; then
  printf '%s\n' "$$" > "$script_dir/activation.pid"
  "$0" --activation-child &
  printf '%s\n' "$!" > "$script_dir/activation-child.pid"
  wait
fi
while true; do
  sleep 1
done
''',
      );

      final adapter = CockpitLinuxRecordingAdapter(
        appId: 'cockpit_demo',
        ffmpegExecutable: ffmpegExecutable.path,
        windowActivatorExecutable: ffmpegExecutable.path,
        windowTargetResolver:
            ({
              required appId,
              required processId,
              required processRunner,
              required timeout,
            }) async {
              throw StateError('window resolution unavailable');
            },
        displayConfigResolver: () async => const CockpitLinuxDisplayConfig(
          display: ':99',
          captureSize: '1440x900',
        ),
        startupTimeout: const Duration(milliseconds: 500),
        commandTimeout: const Duration(milliseconds: 500),
        startupEvidenceTimeout: const Duration(milliseconds: 200),
        stopTimeout: const Duration(seconds: 2),
        finalizationPollInterval: const Duration(milliseconds: 10),
      );

      await expectLater(
        adapter.startRecording(
          const CockpitRecordingRequest(
            purpose: CockpitRecordingPurpose.acceptance,
            name: 'missing-linux-startup-evidence',
            attachToStep: true,
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Linux recording did not confirm startup'),
          ),
        ),
      );

      final activationPidFile = File(p.join(tempDir.path, 'activation.pid'));
      final activationChildPidFile = File(
        p.join(tempDir.path, 'activation-child.pid'),
      );
      final observedPids = <int>[
        if (activationPidFile.existsSync())
          int.parse(activationPidFile.readAsStringSync()),
        if (activationChildPidFile.existsSync())
          int.parse(activationChildPidFile.readAsStringSync()),
      ];
      addTearDown(() async {
        for (final pid in observedPids) {
          await _killProcessIfAlive(pid);
        }
      });
      expect(
        await _liveProcessIdsContaining(ffmpegExecutable.path),
        isEmpty,
        reason:
            'Timed-out activation and recording processes must not survive '
            'startRecording, even when the activation script has not yet '
            'written its PID under scheduler load.',
      );
    },
  );

  test(
    'linux recording adapter includes recent ffmpeg stderr when output is empty',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_linux_recording_adapter_empty_output_diagnostics',
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
printf 'Press [q] to stop\n' >&2
printf '[x11grab @ 0x123] Cannot open display :99\n' >&2
while IFS= read -r line; do
  if [ "$line" = "q" ]; then
    exit 0
  fi
done
''',
      );

      final adapter = CockpitLinuxRecordingAdapter(
        appId: 'cockpit_demo',
        ffmpegExecutable: ffmpegExecutable.path,
        windowActivatorExecutable: null,
        displayConfigResolver: () async => const CockpitLinuxDisplayConfig(
          display: ':99',
          captureSize: '1440x900',
        ),
        startupTimeout: const Duration(seconds: 2),
        stopTimeout: const Duration(seconds: 2),
        finalizationPollInterval: const Duration(milliseconds: 10),
      );

      final session = await adapter.startRecording(
        const CockpitRecordingRequest(
          purpose: CockpitRecordingPurpose.acceptance,
          name: 'empty-linux-output-diagnostics',
          attachToStep: true,
        ),
      );
      final result = await adapter.stopRecording();

      expect(session.state, CockpitRecordingState.recording);
      expect(result.state, CockpitRecordingState.failed);
      expect(result.failureReason, contains('Recent ffmpeg output'));
      expect(result.failureReason, contains('Cannot open display :99'));
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

Future<bool> _isProcessAlive(int pid) async {
  final result = await Process.run('/bin/kill', <String>['-0', '$pid']);
  return result.exitCode == 0;
}

Future<void> _killProcessIfAlive(int pid) async {
  if (!await _isProcessAlive(pid)) {
    return;
  }
  await Process.run('/bin/kill', <String>['-KILL', '$pid']);
}

Future<List<int>> _liveProcessIdsContaining(String commandFragment) async {
  final result = await Process.run('ps', const <String>[
    '-axo',
    'pid=,stat=,command=',
  ]);
  if (result.exitCode != 0) {
    throw StateError('Unable to inspect process state: ${result.stderr}');
  }
  final matches = <int>[];
  for (final line in '${result.stdout}'.split('\n')) {
    final match = RegExp(r'^\s*(\d+)\s+(\S+)\s+(.*)$').firstMatch(line);
    if (match == null || !match.group(3)!.contains(commandFragment)) {
      continue;
    }
    if (!match.group(2)!.startsWith('Z')) {
      matches.add(int.parse(match.group(1)!));
    }
  }
  return matches;
}
