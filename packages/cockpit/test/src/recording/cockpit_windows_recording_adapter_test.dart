import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/src/platform/windows/cockpit_windows_window_target.dart';
import 'package:cockpit/src/recording/cockpit_windows_recording_adapter.dart';
import 'package:test/test.dart';

void main() {
  test(
    'windows recording adapter starts and finalizes a host recording artifact',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_windows_recording_adapter',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final ffmpegInvocations = <List<String>>[];

      final adapter = CockpitWindowsRecordingAdapter(
        appId: 'cockpit_demo',
        processId: 4101,
        windowResolver:
            ({
              required appId,
              required processId,
              required timeout,
              required activationSettleDelay,
            }) async {
              expect(appId, 'cockpit_demo');
              expect(processId, 4101);
              return const CockpitWindowsWindowTarget(
                processId: 4101,
                title: 'Cockpit Demo',
                handle: 4242,
                left: 120,
                top: 48,
                width: 900,
                height: 640,
              );
            },
        ffmpegExecutable: 'ffmpeg',
        processStarter: (executable, arguments) async {
          expect(executable, 'ffmpeg');
          ffmpegInvocations.add(List<String>.from(arguments));
          final outputPath = arguments.last;
          return _FakeRecordingProcess(
            startupLine: 'Press [q] to stop',
            onStopRequested: () async {
              File(outputPath).writeAsStringSync('windows-video');
            },
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
          name: 'host-windows-demo',
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
          relativePath: 'recordings/host-windows-demo.mp4',
        ),
      );
      expect(File(result.sourceFilePath!).readAsStringSync(), 'windows-video');
      expect(ffmpegInvocations.single.join(' '), contains('-f gdigrab'));
      expect(ffmpegInvocations.single.join(' '), contains('-i hwnd=4242'));
      expect(ffmpegInvocations.single.join(' '), isNot(contains('title=')));
      expect(ffmpegInvocations.single.join(' '), isNot(contains('-i desktop')));
    },
  );

  test(
    'windows recording adapter tolerates quiet startup when ffmpeg keeps running',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_windows_recording_adapter_quiet',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final adapter = CockpitWindowsRecordingAdapter(
        appId: 'cockpit_demo',
        windowResolver:
            ({
              required appId,
              required processId,
              required timeout,
              required activationSettleDelay,
            }) async => const CockpitWindowsWindowTarget(
              processId: 4101,
              title: 'Cockpit Demo',
              handle: 4242,
              left: 20,
              top: 12,
              width: 300,
              height: 240,
            ),
        ffmpegExecutable: 'ffmpeg',
        processStarter: (executable, arguments) async {
          final outputPath = arguments.last;
          return _FakeRecordingProcess(
            onStarted: () async {
              await Future<void>.delayed(const Duration(milliseconds: 100));
              File(outputPath).writeAsStringSync('startup-evidence');
            },
            onStopRequested: () async {
              File(outputPath).writeAsStringSync('quiet-windows-video');
            },
          );
        },
        startupTimeout: const Duration(milliseconds: 500),
        startupEvidenceTimeout: const Duration(seconds: 2),
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
          name: 'quiet-windows-demo',
          attachToStep: true,
        ),
      );
      final result = await adapter.stopRecording();

      expect(session.state, CockpitRecordingState.recording);
      expect(result.state, CockpitRecordingState.completed);
      expect(
        File(result.sourceFilePath!).readAsStringSync(),
        'quiet-windows-video',
      );
    },
  );

  test(
    'windows recording adapter fails fast when ffmpeg never confirms startup or produces output',
    () async {
      final adapter = CockpitWindowsRecordingAdapter(
        appId: 'cockpit_demo',
        windowResolver:
            ({
              required appId,
              required processId,
              required timeout,
              required activationSettleDelay,
            }) async => const CockpitWindowsWindowTarget(
              processId: 4101,
              title: 'Cockpit Demo',
              handle: 4242,
              left: 20,
              top: 12,
              width: 300,
              height: 240,
            ),
        ffmpegExecutable: 'ffmpeg',
        processStarter: (_, _) async =>
            _FakeRecordingProcess(onStopRequested: () async {}),
        startupTimeout: const Duration(milliseconds: 500),
        startupEvidenceTimeout: const Duration(milliseconds: 200),
        stopTimeout: const Duration(seconds: 2),
        finalizationPollInterval: const Duration(milliseconds: 10),
      );

      await expectLater(
        adapter.startRecording(
          const CockpitRecordingRequest(
            purpose: CockpitRecordingPurpose.acceptance,
            name: 'missing-windows-startup-evidence',
            attachToStep: true,
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Windows recording did not confirm startup'),
          ),
        ),
      );
    },
  );

  test(
    'windows recording adapter includes recent ffmpeg stderr when output is empty',
    () async {
      final adapter = CockpitWindowsRecordingAdapter(
        appId: 'cockpit_demo',
        windowResolver:
            ({
              required appId,
              required processId,
              required timeout,
              required activationSettleDelay,
            }) async => const CockpitWindowsWindowTarget(
              processId: 4101,
              title: 'Cockpit Demo',
              handle: 4242,
              left: 20,
              top: 12,
              width: 300,
              height: 240,
            ),
        ffmpegExecutable: 'ffmpeg',
        processStarter: (_, _) async => _FakeRecordingProcess(
          startupLine:
              'Press [q] to stop\n[gdigrab @ 0x123] Capturing window failed',
          onStopRequested: () async {},
        ),
        startupTimeout: const Duration(seconds: 2),
        stopTimeout: const Duration(seconds: 2),
        finalizationPollInterval: const Duration(milliseconds: 10),
      );

      final session = await adapter.startRecording(
        const CockpitRecordingRequest(
          purpose: CockpitRecordingPurpose.acceptance,
          name: 'empty-windows-output-diagnostics',
          attachToStep: true,
        ),
      );
      final result = await adapter.stopRecording();

      expect(session.state, CockpitRecordingState.recording);
      expect(result.state, CockpitRecordingState.failed);
      expect(result.failureReason, contains('Recent ffmpeg output'));
      expect(result.failureReason, contains('Capturing window failed'));
    },
  );
}

final class _FakeRecordingProcess implements Process {
  _FakeRecordingProcess({
    this.startupLine,
    this.onStarted,
    required Future<void> Function() onStopRequested,
  }) : _onStopRequested = onStopRequested {
    scheduleMicrotask(() {
      if (startupLine != null && !_stderrController.isClosed) {
        _stderrController.add(utf8.encode('$startupLine\n'));
      }
    });
    if (onStarted != null) {
      scheduleMicrotask(() async {
        await onStarted!.call();
      });
    }
    _stdinController.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) async {
          if (line == 'q' && !_exitCodeCompleter.isCompleted) {
            await _onStopRequested();
            await _closeWithExitCode(0);
          }
        });
  }

  final String? startupLine;
  final Future<void> Function()? onStarted;
  final Future<void> Function() _onStopRequested;
  final StreamController<List<int>> _stdoutController =
      StreamController<List<int>>();
  final StreamController<List<int>> _stderrController =
      StreamController<List<int>>();
  final StreamController<List<int>> _stdinController =
      StreamController<List<int>>();
  final Completer<int> _exitCodeCompleter = Completer<int>();

  late final IOSink _stdin = IOSink(_stdinController.sink);

  @override
  int get pid => 4242;

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  @override
  Future<int> get exitCode => _exitCodeCompleter.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_exitCodeCompleter.isCompleted) {
      unawaited(_closeWithExitCode(0));
    }
    return true;
  }

  Future<void> _closeWithExitCode(int code) async {
    if (!_exitCodeCompleter.isCompleted) {
      _exitCodeCompleter.complete(code);
    }
    await _stdoutController.close();
    await _stderrController.close();
  }
}
