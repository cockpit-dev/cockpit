import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/cockpit.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'adb adapter starts, pulls, and cleans up a host recording artifact',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_adb_recording_adapter',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final executable = await _writeExecutable(
        directory: tempDir,
        name: 'adb',
        body: r'''
#!/bin/sh
script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
log_file="$script_dir/adb.log"
storage_dir="$script_dir/device-storage"
mkdir -p "$storage_dir"
printf '%s\n' "$*" >> "$log_file"

command="$3"
subcommand="$4"
for last_arg in "$@"; do remote_path="$last_arg"; done
mapped_remote_path="$storage_dir$(printf '%s' "$remote_path" | sed 's#/#_#g')"
stop_signal_file="$storage_dir/stop-screenrecord.signal"
running_signal_file="$storage_dir/screenrecord-running.signal"

if [ "$command" = "shell" ] && [ "$subcommand" = "screenrecord" ]; then
  rm -f "$stop_signal_file"
  touch "$running_signal_file"
  while true; do
    if [ -f "$stop_signal_file" ]; then
      printf "adb-video" > "$mapped_remote_path"
      rm -f "$stop_signal_file"
      rm -f "$running_signal_file"
      exit 0
    fi
    sleep 1
  done
fi

if [ "$command" = "shell" ] && [ "$subcommand" = "pidof" ]; then
  if [ -f "$running_signal_file" ]; then
    printf '12345\n'
    exit 0
  fi
  exit 1
fi

if [ "$command" = "shell" ] && [ "$subcommand" = "killall" ]; then
  touch "$stop_signal_file"
  exit 0
fi

if [ "$command" = "pull" ]; then
  remote_path="$4"
  mapped_remote_path="$storage_dir$(printf '%s' "$remote_path" | sed 's#/#_#g')"
  cp "$mapped_remote_path" "$5"
  exit 0
fi

if [ "$command" = "shell" ] && [ "$subcommand" = "rm" ]; then
  rm -f "$mapped_remote_path"
  exit 0
fi

exit 1
''',
      );

      final adapter = CockpitAdbRecordingAdapter(
        deviceId: 'emulator-5554',
        executable: executable.path,
      );

      final session = await adapter.startRecording(
        const CockpitRecordingRequest(
          purpose: CockpitRecordingPurpose.acceptance,
          name: 'host-adb-demo',
          attachToStep: true,
        ),
      );
      final result = await adapter.stopRecording();
      final log = File(p.join(tempDir.path, 'adb.log')).readAsStringSync();

      expect(session.state, CockpitRecordingState.recording);
      expect(
        result.state,
        CockpitRecordingState.completed,
        reason: '${result.failureReason}\n$log',
      );
      expect(
        result.artifact,
        const CockpitArtifactRef(
          role: 'recording',
          relativePath: 'recordings/host-adb-demo.mp4',
        ),
      );
      expect(result.sourceFilePath, isNotNull);
      expect(File(result.sourceFilePath!).readAsStringSync(), 'adb-video');

      expect(log, contains('-s emulator-5554 shell screenrecord'));
      expect(log, contains('-s emulator-5554 shell pidof screenrecord'));
      expect(
        log,
        contains('-s emulator-5554 shell killall -s INT screenrecord'),
      );
      expect(log, contains('-s emulator-5554 pull'));
      expect(log, contains('-s emulator-5554 shell rm'));
    },
  );

  test(
    'adb adapter treats a live screenrecord process as started when pid probes are unavailable',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_adb_recording_adapter_no_pidof',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final executable = await _writeExecutable(
        directory: tempDir,
        name: 'adb',
        body: r'''
#!/bin/sh
script_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
log_file="$script_dir/adb.log"
storage_dir="$script_dir/device-storage"
mkdir -p "$storage_dir"
printf '%s\n' "$*" >> "$log_file"

command="$3"
subcommand="$4"
for last_arg in "$@"; do remote_path="$last_arg"; done
mapped_remote_path="$storage_dir$(printf '%s' "$remote_path" | sed 's#/#_#g')"
stop_signal_file="$storage_dir/stop-screenrecord.signal"

if [ "$command" = "shell" ] && [ "$subcommand" = "screenrecord" ]; then
  rm -f "$stop_signal_file"
  while true; do
    if [ -f "$stop_signal_file" ]; then
      printf "adb-video" > "$mapped_remote_path"
      rm -f "$stop_signal_file"
      exit 0
    fi
    sleep 1
  done
fi

if [ "$command" = "shell" ] && [ "$subcommand" = "pidof" ]; then
  exit 1
fi

if [ "$command" = "shell" ] && [ "$subcommand" = "ps" ]; then
  exit 1
fi

if [ "$command" = "shell" ] && [ "$subcommand" = "killall" ]; then
  touch "$stop_signal_file"
  exit 0
fi

if [ "$command" = "pull" ]; then
  remote_path="$4"
  mapped_remote_path="$storage_dir$(printf '%s' "$remote_path" | sed 's#/#_#g')"
  cp "$mapped_remote_path" "$5"
  exit 0
fi

if [ "$command" = "shell" ] && [ "$subcommand" = "rm" ]; then
  rm -f "$mapped_remote_path"
  exit 0
fi

exit 1
''',
      );

      final adapter = CockpitAdbRecordingAdapter(
        deviceId: 'emulator-5554',
        executable: executable.path,
      );

      final session = await adapter.startRecording(
        const CockpitRecordingRequest(
          purpose: CockpitRecordingPurpose.acceptance,
          name: 'host-adb-no-pidof',
          attachToStep: true,
        ),
      );
      final result = await adapter.stopRecording();
      final log = File(p.join(tempDir.path, 'adb.log')).readAsStringSync();

      expect(session.state, CockpitRecordingState.recording);
      expect(
        result.state,
        CockpitRecordingState.completed,
        reason: result.failureReason,
      );
      expect(File(result.sourceFilePath!).readAsStringSync(), 'adb-video');
      expect(log, contains('-s emulator-5554 shell pidof screenrecord'));
      expect(log, contains('-s emulator-5554 shell ps -A'));
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
