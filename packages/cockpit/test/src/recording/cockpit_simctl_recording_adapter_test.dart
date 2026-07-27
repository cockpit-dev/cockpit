import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/cockpit.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('simctl default startup timeout allows first-frame evidence', () {
    expect(
      cockpitDefaultSimctlRecordingStartupTimeout,
      greaterThanOrEqualTo(const Duration(seconds: 10)),
    );
  });

  test('simctl default stop timeout covers slow CI finalization windows', () {
    expect(
      cockpitDefaultSimctlRecordingStopTimeout,
      greaterThanOrEqualTo(const Duration(seconds: 30)),
    );
  });

  test('simctl adapter requires startup evidence before recording', () async {
    const deviceId = 'simulator-no-banner';
    await _deletePersistedSession(deviceId);
    addTearDown(() => _deletePersistedSession(deviceId));

    final tempDir = await Directory.systemTemp.createTemp(
      'cockpit_simctl_recording_no_banner',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    final runtime = _FakeSimctlRuntime(pid: 4101);

    final adapter = CockpitSimctlRecordingAdapter(
      deviceId: deviceId,
      processStarter: runtime.start,
      pidSignalSender: runtime.sendSignal,
      pidLivenessChecker: runtime.isRunning,
      tempFileFactory: (basename) async => File(p.join(tempDir.path, basename)),
      processRunner: _ffprobeUnavailable,
      startupTimeout: const Duration(milliseconds: 80),
      stopTimeout: const Duration(milliseconds: 80),
      finalizationPollInterval: const Duration(milliseconds: 10),
    );

    await expectLater(
      adapter.startRecording(
        const CockpitRecordingRequest(
          purpose: CockpitRecordingPurpose.acceptance,
          name: 'host-simctl-no-banner',
          attachToStep: true,
        ),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(runtime.receivedSignals, contains(ProcessSignal.sigkill));
    expect(cockpitHasActiveSimctlRecordingSession(deviceId), isFalse);
  });

  test(
    'simctl adapter fails when the recording output file is missing',
    () async {
      const deviceId = 'simulator-456';
      await _deletePersistedSession(deviceId);
      addTearDown(() => _deletePersistedSession(deviceId));

      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_simctl_recording_missing_output',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final runtime = _FakeSimctlRuntime(
        pid: 4201,
        startupLine:
            'Note: No display specified. Defaulting to display: screen-1',
      );

      final adapter = CockpitSimctlRecordingAdapter(
        deviceId: deviceId,
        processStarter: runtime.start,
        pidSignalSender: runtime.sendSignal,
        pidLivenessChecker: runtime.isRunning,
        tempFileFactory: (basename) async =>
            File(p.join(tempDir.path, basename)),
        processRunner: _ffprobeUnavailable,
        stopTimeout: const Duration(milliseconds: 200),
        finalizationPollInterval: const Duration(milliseconds: 10),
      );

      await adapter.startRecording(
        const CockpitRecordingRequest(
          purpose: CockpitRecordingPurpose.acceptance,
          name: 'host-simctl-missing',
          attachToStep: true,
        ),
      );
      final result = await adapter.stopRecording();

      expect(result.state, CockpitRecordingState.failed);
      expect(result.failureReason, contains('output'));
      expect(runtime.lastArguments, contains('--codec=h264'));
    },
  );

  test(
    'simctl adapter stops the live recorder when xcrun exits before simctl',
    () async {
      const deviceId = 'simulator-orphan-child';
      await _deletePersistedSession(deviceId);
      addTearDown(() => _deletePersistedSession(deviceId));

      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_simctl_recording_orphan_child',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final runtime = _FakeSimctlRuntime(
        pid: 4211,
        startupLine: 'Recording started',
        childPid: 4212,
        parentStopsBeforeChild: true,
        onChildStop: (outputPath) async {
          File(outputPath).writeAsStringSync('simctl-child-video');
        },
      );

      final adapter = CockpitSimctlRecordingAdapter(
        deviceId: deviceId,
        processStarter: runtime.start,
        pidSignalSender: runtime.sendSignal,
        pidLivenessChecker: runtime.isRunning,
        tempFileFactory: (basename) async =>
            File(p.join(tempDir.path, basename)),
        processRunner: runtime.runProcess,
        stopTimeout: const Duration(milliseconds: 300),
        finalizationPollInterval: const Duration(milliseconds: 10),
      );

      await adapter.startRecording(
        const CockpitRecordingRequest(
          purpose: CockpitRecordingPurpose.acceptance,
          name: 'host-simctl-orphan-child',
          attachToStep: true,
        ),
      );
      final result = await adapter.stopRecording();

      expect(
        result.state,
        CockpitRecordingState.completed,
        reason: result.failureReason,
      );
      expect(
        runtime.receivedSignalsByPid[4211],
        contains(ProcessSignal.sigint),
      );
      expect(
        runtime.receivedSignalsByPid[4212],
        contains(ProcessSignal.sigint),
      );
      expect(
        File(result.sourceFilePath!).readAsStringSync(),
        'simctl-child-video',
      );
    },
  );

  test('simctl adapter accepts a single finalized simulator frame', () async {
    const deviceId = 'simulator-321';
    await _deletePersistedSession(deviceId);
    addTearDown(() => _deletePersistedSession(deviceId));

    final tempDir = await Directory.systemTemp.createTemp(
      'cockpit_simctl_recording_sparse_timeline',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    final runtime = _FakeSimctlRuntime(
      pid: 4301,
      startupLine: 'Recording started',
      onStop: (outputPath) async {
        File(outputPath).writeAsStringSync('simctl-video');
      },
    );

    final adapter = CockpitSimctlRecordingAdapter(
      deviceId: deviceId,
      processStarter: runtime.start,
      pidSignalSender: runtime.sendSignal,
      pidLivenessChecker: runtime.isRunning,
      tempFileFactory: (basename) async => File(p.join(tempDir.path, basename)),
      processRunner: (executable, arguments) async {
        if (executable == 'ffprobe') {
          return ProcessResult(0, 0, '''
{"format":{"duration":"0.067"},"streams":[{"codec_type":"video","nb_frames":"1"}]}
''', '');
        }
        throw ProcessException(executable, arguments, 'unexpected command');
      },
      finalizationPollInterval: const Duration(milliseconds: 10),
    );

    await adapter.startRecording(
      const CockpitRecordingRequest(
        purpose: CockpitRecordingPurpose.acceptance,
        name: 'host-simctl-sparse',
        attachToStep: true,
      ),
    );
    final result = await adapter.stopRecording();

    expect(
      result.state,
      CockpitRecordingState.completed,
      reason: result.failureReason,
    );
  });

  test(
    'simctl adapter accepts finalized video when process liveness lags',
    () async {
      const deviceId = 'simulator-lingering-wrapper';
      await _deletePersistedSession(deviceId);
      addTearDown(() => _deletePersistedSession(deviceId));

      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_simctl_recording_lingering_wrapper',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final runtime = _FakeSimctlRuntime(
        pid: 4351,
        startupLine: 'Recording started',
        lingerAfterOutput: true,
        onStop: (outputPath) async {
          File(outputPath).writeAsStringSync('simctl-finalized-video');
        },
      );
      final adapter = CockpitSimctlRecordingAdapter(
        deviceId: deviceId,
        processStarter: runtime.start,
        pidSignalSender: runtime.sendSignal,
        pidLivenessChecker: runtime.isRunning,
        tempFileFactory: (basename) async =>
            File(p.join(tempDir.path, basename)),
        processRunner: (executable, arguments) async {
          if (executable == 'ffprobe') {
            return ProcessResult(0, 0, '''
{"format":{"duration":"1.500"},"streams":[{"codec_type":"video","nb_frames":"30"}]}
''', '');
          }
          throw ProcessException(executable, arguments, 'unexpected command');
        },
        stopTimeout: const Duration(milliseconds: 300),
        finalizationPollInterval: const Duration(milliseconds: 10),
      );

      await adapter.startRecording(
        const CockpitRecordingRequest(
          purpose: CockpitRecordingPurpose.acceptance,
          name: 'host-simctl-lingering-wrapper',
          attachToStep: true,
        ),
      );
      final result = await adapter.stopRecording();

      expect(
        result.state,
        CockpitRecordingState.completed,
        reason: result.failureReason,
      );
    },
  );

  test('simctl adapter waits for configured graceful stop', () async {
    const deviceId = 'simulator-slow-stop';
    await _deletePersistedSession(deviceId);
    addTearDown(() => _deletePersistedSession(deviceId));

    final tempDir = await Directory.systemTemp.createTemp(
      'cockpit_simctl_recording_slow_stop',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    final runtime = _FakeSimctlRuntime(
      pid: 4451,
      startupLine: 'Recording started',
      onStop: (outputPath) async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        File(outputPath).writeAsStringSync('simctl-slow-stop-video');
      },
    );

    final adapter = CockpitSimctlRecordingAdapter(
      deviceId: deviceId,
      processStarter: runtime.start,
      pidSignalSender: runtime.sendSignal,
      pidLivenessChecker: runtime.isRunning,
      tempFileFactory: (basename) async => File(p.join(tempDir.path, basename)),
      processRunner: _ffprobeUnavailable,
      stopTimeout: const Duration(milliseconds: 300),
      finalizationPollInterval: const Duration(milliseconds: 10),
    );

    await adapter.startRecording(
      const CockpitRecordingRequest(
        purpose: CockpitRecordingPurpose.acceptance,
        name: 'host-simctl-slow-stop',
        attachToStep: true,
      ),
    );
    final result = await adapter.stopRecording();

    expect(
      result.state,
      CockpitRecordingState.completed,
      reason: result.failureReason,
    );
    expect(
      File(result.sourceFilePath!).readAsStringSync(),
      'simctl-slow-stop-video',
    );
  });

  test('simctl adapter reports the configured stop timeout', () async {
    const deviceId = 'simulator-stop-timeout';
    await _deletePersistedSession(deviceId);
    addTearDown(() => _deletePersistedSession(deviceId));

    final tempDir = await Directory.systemTemp.createTemp(
      'cockpit_simctl_recording_stop_timeout',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    final runtime = _FakeSimctlRuntime(
      pid: 4461,
      startupLine: 'Recording started',
      ignoreSigint: true,
    );

    final adapter = CockpitSimctlRecordingAdapter(
      deviceId: deviceId,
      processStarter: runtime.start,
      pidSignalSender: runtime.sendSignal,
      pidLivenessChecker: runtime.isRunning,
      tempFileFactory: (basename) async => File(p.join(tempDir.path, basename)),
      processRunner: _ffprobeUnavailable,
      stopTimeout: const Duration(milliseconds: 60),
      finalizationPollInterval: const Duration(milliseconds: 10),
    );

    await adapter.startRecording(
      const CockpitRecordingRequest(
        purpose: CockpitRecordingPurpose.acceptance,
        name: 'host-simctl-timeout',
        attachToStep: true,
      ),
    );
    final result = await adapter.stopRecording();

    expect(result.state, CockpitRecordingState.failed);
    expect(result.failureReason, contains('60ms'));
    expect(runtime.receivedSignals, contains(ProcessSignal.sigkill));
  });

  test(
    'simctl adapter can stop an active recording after the adapter instance is recreated',
    () async {
      const deviceId = 'simulator-recreated';
      await _deletePersistedSession(deviceId);
      addTearDown(() => _deletePersistedSession(deviceId));

      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_simctl_recording_recreated',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final runtime = _FakeSimctlRuntime(
        pid: 4401,
        startupLine: 'Recording started',
        onStop: (outputPath) async {
          File(outputPath).writeAsStringSync('simctl-recreated-video');
        },
      );

      CockpitSimctlRecordingAdapter buildAdapter() {
        return CockpitSimctlRecordingAdapter(
          deviceId: deviceId,
          processStarter: runtime.start,
          pidSignalSender: runtime.sendSignal,
          pidLivenessChecker: runtime.isRunning,
          tempFileFactory: (basename) async =>
              File(p.join(tempDir.path, basename)),
          processRunner: _ffprobeUnavailable,
          startupTimeout: const Duration(seconds: 1),
          stopTimeout: const Duration(seconds: 2),
          finalizationPollInterval: const Duration(milliseconds: 10),
        );
      }

      final startedAdapter = buildAdapter();
      await startedAdapter.startRecording(
        const CockpitRecordingRequest(
          purpose: CockpitRecordingPurpose.acceptance,
          name: 'host-simctl-recreated',
          attachToStep: true,
        ),
      );

      final stoppedAdapter = buildAdapter();
      final result = await stoppedAdapter.stopRecording();

      expect(
        result.state,
        CockpitRecordingState.completed,
        reason: result.failureReason,
      );
      expect(
        File(result.sourceFilePath!).readAsStringSync(),
        'simctl-recreated-video',
      );
    },
  );
}

Future<ProcessResult> _ffprobeUnavailable(
  String executable,
  List<String> arguments,
) async {
  if (executable == 'ffprobe') {
    return ProcessResult(0, 1, '', 'ffprobe unavailable');
  }
  throw ProcessException(executable, arguments, 'unexpected command');
}

Future<void> _deletePersistedSession(String deviceId) async {
  final sanitizedDeviceId = deviceId.replaceAll(
    RegExp(r'[^A-Za-z0-9._-]+'),
    '_',
  );
  final file = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'flutter_cockpit_recording_sessions${Platform.pathSeparator}'
    'simctl_$sanitizedDeviceId.json',
  );
  if (file.existsSync()) {
    await file.delete();
  }
}

final class _FakeSimctlRuntime {
  _FakeSimctlRuntime({
    required this.pid,
    this.childPid,
    this.startupLine,
    this.onStop,
    this.onChildStop,
    this.ignoreSigint = false,
    this.parentStopsBeforeChild = false,
    this.lingerAfterOutput = false,
  }) : _process = _FakeSimctlProcess(pid: pid, startupLine: startupLine);

  final int pid;
  final int? childPid;
  final String? startupLine;
  final Future<void> Function(String outputPath)? onStop;
  final Future<void> Function(String outputPath)? onChildStop;
  final bool ignoreSigint;
  final bool parentStopsBeforeChild;
  final bool lingerAfterOutput;
  final _FakeSimctlProcess _process;
  final List<ProcessSignal> receivedSignals = <ProcessSignal>[];
  final Map<int, List<ProcessSignal>> receivedSignalsByPid =
      <int, List<ProcessSignal>>{};
  bool _running = true;
  bool _childRunning = true;
  List<String> lastArguments = const <String>[];
  String? _outputPath;

  Future<Process> start(String executable, List<String> arguments) async {
    lastArguments = List<String>.of(arguments);
    _outputPath = arguments.last;
    return _process;
  }

  bool sendSignal(int targetPid, ProcessSignal signal) {
    receivedSignalsByPid
        .putIfAbsent(targetPid, () => <ProcessSignal>[])
        .add(signal);
    if (targetPid == childPid) {
      if (!_childRunning) {
        return false;
      }
      if (signal == ProcessSignal.sigint &&
          _outputPath != null &&
          onChildStop != null) {
        unawaited(onChildStop!(_outputPath!).then((_) => _stopChild()));
        return true;
      }
      unawaited(_stopChild());
      return true;
    }
    if (targetPid != pid || !_running) {
      return false;
    }
    receivedSignals.add(signal);
    if (signal == ProcessSignal.sigint && ignoreSigint) {
      return true;
    }
    if (signal == ProcessSignal.sigint && parentStopsBeforeChild) {
      unawaited(_stop());
      return true;
    }
    if (signal == ProcessSignal.sigint &&
        _outputPath != null &&
        onStop != null) {
      unawaited(
        onStop!(_outputPath!).then((_) async {
          if (!lingerAfterOutput) {
            await _stop();
          }
        }),
      );
      return true;
    }
    unawaited(_stop());
    return true;
  }

  Future<bool> isRunning(int targetPid) async {
    if (targetPid == childPid) {
      return _childRunning;
    }
    return targetPid == pid && _running;
  }

  Future<ProcessResult> runProcess(
    String executable,
    List<String> arguments,
  ) async {
    if (executable == 'ffprobe') {
      return _ffprobeUnavailable(executable, arguments);
    }
    if (executable == '/bin/ps' &&
        arguments.length == 3 &&
        arguments[0] == '-axo') {
      return ProcessResult(0, 0, _processListOutput(), '');
    }
    throw ProcessException(executable, arguments, 'unexpected command');
  }

  String _processListOutput() {
    final outputPath = _outputPath;
    final buffer = StringBuffer()..writeln('  PID  PPID COMMAND');
    if (_running) {
      buffer.writeln(
        '$pid     1 xcrun simctl io simulator-wrapper recordVideo --force ${outputPath ?? ''}',
      );
    }
    final childPid = this.childPid;
    if (childPid != null && _childRunning) {
      buffer.writeln(
        '$childPid $pid /Applications/Xcode.app/Contents/Developer/usr/bin/simctl io simulator-orphan-child recordVideo --codec=h264 --force ${outputPath ?? ''}',
      );
    }
    return buffer.toString();
  }

  Future<void> _stop() async {
    _running = false;
    await _process.closeWithExitCode(0);
  }

  Future<void> _stopChild() async {
    _childRunning = false;
  }
}

final class _FakeSimctlProcess implements Process {
  _FakeSimctlProcess({required this.pid, this.startupLine}) {
    if (startupLine != null) {
      scheduleMicrotask(() {
        if (!_stderrController.isClosed) {
          _stderrController.add(utf8.encode('$startupLine\n'));
        }
      });
    }
  }

  @override
  final int pid;

  final String? startupLine;
  final StreamController<List<int>> _stdoutController =
      StreamController<List<int>>();
  final StreamController<List<int>> _stderrController =
      StreamController<List<int>>();
  final StreamController<List<int>> _stdinController =
      StreamController<List<int>>();
  final Completer<int> _exitCodeCompleter = Completer<int>();

  late final IOSink _stdin = IOSink(_stdinController.sink);

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
    unawaited(closeWithExitCode(0));
    return true;
  }

  Future<void> closeWithExitCode(int code) async {
    if (!_exitCodeCompleter.isCompleted) {
      _exitCodeCompleter.complete(code);
    }
    await _stdoutController.close();
    await _stderrController.close();
    await _stdinController.close();
  }
}
