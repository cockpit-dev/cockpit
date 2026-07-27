import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../infrastructure/cockpit_process_manager.dart';
import 'cockpit_host_recording_adapter.dart';

const Duration cockpitDefaultSimctlRecordingStartupTimeout = Duration(
  seconds: 15,
);
const Duration cockpitDefaultSimctlRecordingStopTimeout = Duration(seconds: 45);

bool cockpitHasActiveSimctlRecordingSession(String deviceId) {
  return _simctlSessionFile(deviceId).existsSync();
}

Future<bool> cockpitHasLiveSimctlRecordingSession(
  String deviceId, {
  CockpitPidLivenessChecker pidLivenessChecker =
      cockpitDefaultPidLivenessChecker,
}) async {
  final file = _simctlSessionFile(deviceId);
  if (!file.existsSync()) {
    return false;
  }
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<Object?, Object?>) {
      await _deleteSimctlSessionFile(file);
      return false;
    }
    final persisted = _PersistedSimctlRecordingSession.fromJson(
      Map<String, Object?>.from(decoded),
    );
    if (await pidLivenessChecker(persisted.pid)) {
      return true;
    }
    await _deleteSimctlSessionFile(file);
    return false;
  } on Object {
    await _deleteSimctlSessionFile(file);
    return false;
  }
}

final class CockpitSimctlRecordingAdapter
    implements CockpitHostRecordingAdapter {
  CockpitSimctlRecordingAdapter({
    required String deviceId,
    String executable = 'xcrun',
    CockpitRecordingProcessStarter processStarter =
        _startDetachedRecordingProcess,
    CockpitRecordingProcessRunner? processRunner,
    CockpitRecordingTempFileFactory tempFileFactory =
        cockpitCreateRecordingTempFile,
    String ffprobeExecutable = 'ffprobe',
    Duration startupTimeout = cockpitDefaultSimctlRecordingStartupTimeout,
    Duration stopTimeout = cockpitDefaultSimctlRecordingStopTimeout,
    Duration finalizationPollInterval = const Duration(milliseconds: 100),
    CockpitPidSignalSender pidSignalSender = Process.killPid,
    CockpitPidLivenessChecker pidLivenessChecker =
        cockpitDefaultPidLivenessChecker,
  }) : _deviceId = deviceId,
       _executable = executable,
       _processStarter = processStarter,
       _processRunner = processRunner,
       _tempFileFactory = tempFileFactory,
       _ffprobeExecutable = ffprobeExecutable,
       _startupTimeout = startupTimeout,
       _stopTimeout = stopTimeout,
       _finalizationPollInterval = finalizationPollInterval,
       _pidSignalSender = pidSignalSender,
       _pidLivenessChecker = pidLivenessChecker;

  final String _deviceId;
  final String _executable;
  final CockpitRecordingProcessStarter _processStarter;
  final CockpitRecordingProcessRunner? _processRunner;
  final CockpitRecordingTempFileFactory _tempFileFactory;
  final String _ffprobeExecutable;
  final Duration _startupTimeout;
  final Duration _stopTimeout;
  final Duration _finalizationPollInterval;
  final CockpitPidSignalSender _pidSignalSender;
  final CockpitPidLivenessChecker _pidLivenessChecker;

  @override
  Future<CockpitRecordingSession> startRecording(
    CockpitRecordingRequest request,
  ) async {
    if (await _restoreableSessionExists()) {
      throw StateError('A simctl recording is already active.');
    }

    final outputFile = await _tempFileFactory(
      cockpitRecordingFileName(request.name),
    );
    outputFile.parent.createSync(recursive: true);
    if (outputFile.existsSync()) {
      outputFile.deleteSync();
    }

    final process = await _processStarter(_executable, <String>[
      'simctl',
      'io',
      _deviceId,
      'recordVideo',
      '--codec=h264',
      '--force',
      outputFile.path,
    ]);

    final stdoutSubscription = process.stdout.listen((_) {});

    final startupCompleter = Completer<void>();
    final stderrBuffer = StringBuffer();
    final stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          stderrBuffer.writeln(line);
          if (!startupCompleter.isCompleted &&
              (line.contains('Recording started') ||
                  line.contains('Defaulting to display:'))) {
            startupCompleter.complete();
          }
        });

    try {
      await _waitForProcessStartup(
        process: process,
        startupCompleter: startupCompleter,
        stderrBuffer: stderrBuffer,
      );
    } on Object {
      await stdoutSubscription.cancel();
      await stderrSubscription.cancel();
      _pidSignalSender(process.pid, ProcessSignal.sigkill);
      await _waitForProcessExit(
        process.pid,
        timeout: _stopStageTimeout(const Duration(seconds: 2)),
      );
      rethrow;
    }

    final startedAt = DateTime.now();
    await _writePersistedSession(
      _PersistedSimctlRecordingSession(
        pid: process.pid,
        request: request,
        outputFilePath: outputFile.path,
        startedAt: startedAt,
      ),
    );
    await stdoutSubscription.cancel();
    await stderrSubscription.cancel();

    return CockpitRecordingSession(
      request: request,
      state: CockpitRecordingState.recording,
    );
  }

  @override
  Future<CockpitRecordingResult> stopRecording() async {
    final persistedSession = await _readPersistedSession();
    if (persistedSession == null) {
      throw StateError('No active simctl recording session exists.');
    }

    try {
      final durationMs = DateTime.now()
          .difference(persistedSession.startedAt)
          .inMilliseconds;
      final exited = await _requestGracefulStop(persistedSession);
      final result = await _finalizeStoppedRecordingWithRecovery(
        session: persistedSession,
        durationMs: durationMs,
      );
      if (!exited && result.state == CockpitRecordingState.failed) {
        return CockpitRecordingResult(
          state: CockpitRecordingState.failed,
          purpose: persistedSession.request.purpose,
          recordingKind: CockpitRecordingKind.nativeScreen,
          failureReason: _stopTimeoutFailureReason,
        );
      }
      return result;
    } on TimeoutException {
      _pidSignalSender(persistedSession.pid, ProcessSignal.sigkill);
      return CockpitRecordingResult(
        state: CockpitRecordingState.failed,
        purpose: persistedSession.request.purpose,
        recordingKind: CockpitRecordingKind.nativeScreen,
        failureReason: _stopTimeoutFailureReason,
      );
    } finally {
      await _clearActiveSession();
    }
  }

  Future<CockpitRecordingResult> _finalizeStoppedRecording({
    required CockpitRecordingRequest request,
    required File outputFile,
    required int durationMs,
  }) async {
    final hasOutput = await cockpitWaitForNonEmptyFile(
      outputFile,
      timeout: _stopTimeout,
      pollInterval: _finalizationPollInterval,
    );
    if (!hasOutput) {
      return CockpitRecordingResult(
        state: CockpitRecordingState.failed,
        purpose: request.purpose,
        recordingKind: CockpitRecordingKind.nativeScreen,
        failureReason: _missingOutputFailureReasonFor(outputFile),
      );
    }
    final finalized = await _waitForFinalizedOutput(outputFile);
    if (!finalized) {
      return CockpitRecordingResult(
        state: CockpitRecordingState.failed,
        purpose: request.purpose,
        recordingKind: CockpitRecordingKind.nativeScreen,
        failureReason:
            'simctl recording output did not finalize to a stable duration.',
      );
    }

    final timeline = await _probeRecordingTimeline(outputFile.path);
    return CockpitRecordingResult(
      state: CockpitRecordingState.completed,
      purpose: request.purpose,
      recordingKind: CockpitRecordingKind.nativeScreen,
      artifact: cockpitRecordingArtifactForName(request.name),
      durationMs: timeline?.durationMs ?? durationMs,
      sourceFilePath: outputFile.path,
    );
  }

  Future<void> _waitForProcessStartup({
    required Process process,
    required Completer<void> startupCompleter,
    required StringBuffer stderrBuffer,
  }) async {
    final deadline = DateTime.now().add(_startupTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (startupCompleter.isCompleted) {
        return;
      }

      final running = await _isProcessRunning(process.pid);
      if (!running) {
        final exitCode = await process.exitCode;
        throw StateError(
          'simctl recordVideo exited before startup (exitCode=$exitCode): ${stderrBuffer.toString().trim()}',
        );
      }

      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    if (startupCompleter.isCompleted) {
      return;
    }

    if (await _isProcessRunning(process.pid)) {
      throw TimeoutException(
        'simctl recordVideo did not confirm startup within '
        '${_formatDuration(_startupTimeout)}: '
        '${stderrBuffer.toString().trim()}',
      );
    }
    final exitCode = await process.exitCode;

    throw TimeoutException(
      'simctl recordVideo exited before confirming startup (exitCode=$exitCode).',
    );
  }

  Future<bool> _restoreableSessionExists() async {
    final persisted = await _readPersistedSession();
    if (persisted == null) {
      return false;
    }
    if (await _isProcessRunning(persisted.pid)) {
      return true;
    }
    await _clearPersistedSession();
    return false;
  }

  Future<void> _clearActiveSession() async {
    await _clearPersistedSession();
  }

  File get _sessionFile => _simctlSessionFile(_deviceId);

  Future<void> _writePersistedSession(
    _PersistedSimctlRecordingSession session,
  ) async {
    final file = _sessionFile;
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(session.toJson()));
  }

  Future<_PersistedSimctlRecordingSession?> _readPersistedSession() async {
    final file = _sessionFile;
    if (!file.existsSync()) {
      return null;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<Object?, Object?>) {
        await _clearPersistedSession();
        return null;
      }
      return _PersistedSimctlRecordingSession.fromJson(
        Map<String, Object?>.from(decoded),
      );
    } on FormatException {
      await _clearPersistedSession();
      return null;
    }
  }

  Future<void> _clearPersistedSession() async {
    await _deleteSimctlSessionFile(_sessionFile);
  }

  Future<bool> _waitForProcessExit(int pid, {Duration? timeout}) async {
    final effectiveTimeout = timeout ?? _stopTimeout;
    final deadline = DateTime.now().add(effectiveTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!await _isProcessRunning(pid)) {
        return true;
      }
      await Future<void>.delayed(_finalizationPollInterval);
    }
    return !await _isProcessRunning(pid);
  }

  Future<bool> _requestGracefulStop(
    _PersistedSimctlRecordingSession session,
  ) async {
    final pids = <int>{
      session.pid,
      ...await _discoverLiveRecordingPids(session.outputFilePath),
    };
    return _requestGracefulStopForPids(
      pids,
      outputFilePath: session.outputFilePath,
    );
  }

  Future<CockpitRecordingResult> _finalizeStoppedRecordingWithRecovery({
    required _PersistedSimctlRecordingSession session,
    required int durationMs,
  }) async {
    final outputFile = File(session.outputFilePath);
    var result = await _finalizeStoppedRecording(
      request: session.request,
      outputFile: outputFile,
      durationMs: durationMs,
    );
    if (result.state != CockpitRecordingState.failed ||
        !_isMissingOutputFailure(result.failureReason)) {
      return result;
    }

    final lateRecorderPids = await _discoverLiveRecordingPids(
      session.outputFilePath,
    );
    if (lateRecorderPids.isEmpty) {
      return result;
    }
    final stopped = await _requestGracefulStopForPids(
      lateRecorderPids,
      outputFilePath: session.outputFilePath,
    );
    if (!stopped) {
      return result;
    }
    result = await _finalizeStoppedRecording(
      request: session.request,
      outputFile: outputFile,
      durationMs: durationMs,
    );
    return result;
  }

  Future<bool> _requestGracefulStopForPids(
    Set<int> pids, {
    required String outputFilePath,
  }) async {
    var livePids = await _livePids(pids);
    if (livePids.isEmpty) {
      return true;
    }

    _sendSignalToPids(livePids, ProcessSignal.sigint);
    if (await _waitForPidsExit(
      livePids,
      timeout: _stopTimeout,
      finalizedOutputPath: outputFilePath,
    )) {
      return true;
    }

    final latePids = await _discoverLiveRecordingPids(outputFilePath);
    final unsignaledLatePids = latePids.difference(livePids);
    if (unsignaledLatePids.isNotEmpty) {
      _sendSignalToPids(unsignaledLatePids, ProcessSignal.sigint);
      livePids = <int>{...livePids, ...unsignaledLatePids};
      if (await _waitForPidsExit(
        livePids,
        timeout: _stopStageTimeout(const Duration(seconds: 3)),
        finalizedOutputPath: outputFilePath,
      )) {
        return true;
      }
    }

    livePids = await _livePids(<int>{...livePids, ...latePids});
    if (livePids.isEmpty) {
      return true;
    }
    _sendSignalToPids(livePids, ProcessSignal.sigkill);
    await _waitForPidsExit(
      livePids,
      timeout: _stopStageTimeout(const Duration(seconds: 2)),
    );
    return false;
  }

  void _sendSignalToPids(Set<int> pids, ProcessSignal signal) {
    for (final pid in pids) {
      try {
        _pidSignalSender(pid, signal);
      } on Object {
        // The process may already be gone; liveness polling is authoritative.
      }
    }
  }

  Future<bool> _waitForPidsExit(
    Set<int> pids, {
    required Duration timeout,
    String? finalizedOutputPath,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if ((await _livePids(pids)).isEmpty) {
        return true;
      }
      if (finalizedOutputPath != null &&
          await _hasFinalizedRecordingOutput(finalizedOutputPath)) {
        return true;
      }
      await Future<void>.delayed(_finalizationPollInterval);
    }
    return (await _livePids(pids)).isEmpty ||
        (finalizedOutputPath != null &&
            await _hasFinalizedRecordingOutput(finalizedOutputPath));
  }

  Future<bool> _hasFinalizedRecordingOutput(String outputFilePath) async {
    final outputFile = File(outputFilePath);
    if (!await outputFile.exists() || await outputFile.length() == 0) {
      return false;
    }
    return await _probeRecordingTimeline(outputFilePath) != null;
  }

  Future<Set<int>> _livePids(Iterable<int> pids) async {
    final result = <int>{};
    for (final pid in pids) {
      if (pid > 0 && await _isProcessRunning(pid)) {
        result.add(pid);
      }
    }
    return result;
  }

  Future<Set<int>> _discoverLiveRecordingPids(String outputFilePath) async {
    if (outputFilePath.isEmpty || Platform.isWindows) {
      return const <int>{};
    }
    try {
      final result = await _runProcess('/bin/ps', <String>[
        '-axo',
        'pid=,ppid=,command=',
        '-ww',
      ], timeout: _stopStageTimeout(const Duration(seconds: 3)));
      if (result.exitCode != 0) {
        return const <int>{};
      }
      final processes = _parseProcessList('${result.stdout}');
      final matchedPids = <int>{};
      for (final process in processes) {
        if (_isSimctlRecordingCommand(
          process.command,
          outputFilePath: outputFilePath,
        )) {
          matchedPids.add(process.pid);
        }
      }

      var changed = true;
      while (changed) {
        changed = false;
        for (final process in processes) {
          if (matchedPids.contains(process.ppid) &&
              _isSimctlRelatedCommand(process.command) &&
              matchedPids.add(process.pid)) {
            changed = true;
          }
        }
      }
      return await _livePids(matchedPids);
    } on TimeoutException {
      return const <int>{};
    } on ProcessException {
      return const <int>{};
    } on Object {
      return const <int>{};
    }
  }

  Future<bool> _isProcessRunning(int pid) async {
    return _pidLivenessChecker(pid);
  }

  Future<bool> _waitForFinalizedOutput(File outputFile) async {
    final stableFile = await cockpitWaitForStableFile(
      outputFile,
      timeout: _stopTimeout,
      pollInterval: _finalizationPollInterval,
    );
    if (!stableFile) {
      return false;
    }

    final deadline = DateTime.now().add(_stopTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final probe = await _probeRecordingTimeline(outputFile.path);
      if (probe == null) {
        return true;
      }
      if (_looksUsableForSimulatorAcceptance(probe)) {
        return true;
      }
      await Future<void>.delayed(_finalizationPollInterval);
    }

    final finalProbe = await _probeRecordingTimeline(outputFile.path);
    if (finalProbe == null) {
      return true;
    }
    return _looksUsableForSimulatorAcceptance(finalProbe);
  }

  bool _looksUsableForSimulatorAcceptance(
    _CockpitRecordingTimelineProbe probe,
  ) {
    return probe.durationMs > 0 &&
        (probe.frameCount == null || probe.frameCount! > 0);
  }

  Future<_CockpitRecordingTimelineProbe?> _probeRecordingTimeline(
    String path,
  ) async {
    try {
      final result = await _runProcess(_ffprobeExecutable, <String>[
        '-v',
        'error',
        '-print_format',
        'json',
        '-show_streams',
        '-show_format',
        path,
      ], timeout: _stopStageTimeout(const Duration(seconds: 3)));
      if (result.exitCode != 0) {
        return null;
      }
      final decoded = jsonDecode('${result.stdout}');
      if (decoded is! Map<Object?, Object?>) {
        return null;
      }
      final format = decoded['format'];
      if (format is! Map<Object?, Object?>) {
        return null;
      }
      final durationValue = format['duration'];
      if (durationValue is! String) {
        return null;
      }
      final durationSeconds = double.tryParse(durationValue);
      if (durationSeconds == null || durationSeconds <= 0) {
        return null;
      }
      int? frameCount;
      final streams = decoded['streams'];
      if (streams is List<Object?>) {
        for (final stream in streams) {
          if (stream is! Map<Object?, Object?>) {
            continue;
          }
          if (stream['codec_type'] != 'video') {
            continue;
          }
          final frameValue = stream['nb_frames'];
          if (frameValue is String) {
            frameCount = int.tryParse(frameValue);
          } else if (frameValue is int) {
            frameCount = frameValue;
          }
          break;
        }
      }
      return _CockpitRecordingTimelineProbe(
        durationMs: (durationSeconds * 1000).round(),
        frameCount: frameCount,
      );
    } on FormatException {
      return null;
    } on ProcessException {
      return null;
    }
  }

  Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  }) {
    final injected = _processRunner;
    if (injected != null) {
      return injected(executable, arguments).timeout(timeout);
    }
    return cockpitRunRecordingProcessWithTimeout(
      executable,
      arguments,
      timeout: timeout,
    );
  }

  Duration _stopStageTimeout(Duration maximum) {
    if (_stopTimeout <= Duration.zero) {
      return maximum;
    }
    return _stopTimeout < maximum ? _stopTimeout : maximum;
  }

  String get _stopTimeoutFailureReason {
    return 'simctl recording did not stop within '
        '${_formatDuration(_stopTimeout)} after SIGINT.';
  }
}

File _simctlSessionFile(String deviceId) {
  final sanitizedDeviceId = deviceId.replaceAll(
    RegExp(r'[^A-Za-z0-9._-]+'),
    '_',
  );
  return File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'flutter_cockpit_recording_sessions${Platform.pathSeparator}'
    'simctl_$sanitizedDeviceId.json',
  );
}

final class _PersistedSimctlRecordingSession {
  const _PersistedSimctlRecordingSession({
    required this.pid,
    required this.request,
    required this.outputFilePath,
    required this.startedAt,
  });

  final int pid;
  final CockpitRecordingRequest request;
  final String outputFilePath;
  final DateTime startedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'pid': pid,
    'request': request.toJson(),
    'outputFilePath': outputFilePath,
    'startedAt': startedAt.toUtc().toIso8601String(),
  };

  factory _PersistedSimctlRecordingSession.fromJson(Map<String, Object?> json) {
    return _PersistedSimctlRecordingSession(
      pid: json['pid']! as int,
      request: CockpitRecordingRequest.fromJson(
        Map<String, Object?>.from(json['request']! as Map<Object?, Object?>),
      ),
      outputFilePath: json['outputFilePath']! as String,
      startedAt: DateTime.parse(json['startedAt']! as String).toUtc(),
    );
  }
}

Future<Process> _startDetachedRecordingProcess(
  String executable,
  List<String> arguments,
) {
  return cockpitStartIsolatedProcess(
    executable,
    arguments,
    mode: ProcessStartMode.detachedWithStdio,
  );
}

Future<void> _deleteSimctlSessionFile(File file) async {
  if (!file.existsSync()) {
    return;
  }
  try {
    await file.delete();
  } on Object {
    // Best-effort stale session cleanup.
  }
}

final class _CockpitRecordingTimelineProbe {
  const _CockpitRecordingTimelineProbe({
    required this.durationMs,
    required this.frameCount,
  });

  final int durationMs;
  final int? frameCount;
}

final class _CockpitProcessListingEntry {
  const _CockpitProcessListingEntry({
    required this.pid,
    required this.ppid,
    required this.command,
  });

  final int pid;
  final int ppid;
  final String command;
}

List<_CockpitProcessListingEntry> _parseProcessList(String output) {
  final entries = <_CockpitProcessListingEntry>[];
  for (final rawLine in const LineSplitter().convert(output)) {
    final line = rawLine.trimLeft();
    if (line.isEmpty || line.startsWith('PID ')) {
      continue;
    }
    final match = RegExp(r'^(\d+)\s+(\d+)\s+(.+)$').firstMatch(line);
    if (match == null) {
      continue;
    }
    final pid = int.tryParse(match.group(1)!);
    final ppid = int.tryParse(match.group(2)!);
    final command = match.group(3)!.trim();
    if (pid == null || ppid == null || command.isEmpty) {
      continue;
    }
    entries.add(
      _CockpitProcessListingEntry(pid: pid, ppid: ppid, command: command),
    );
  }
  return entries;
}

bool _isSimctlRecordingCommand(
  String command, {
  required String outputFilePath,
}) {
  return _isSimctlRelatedCommand(command) &&
      command.contains('recordVideo') &&
      command.contains(outputFilePath);
}

bool _isSimctlRelatedCommand(String command) {
  return command.contains('simctl') || command.contains('xcrun');
}

String _formatDuration(Duration duration) {
  final milliseconds = duration.inMilliseconds;
  if (milliseconds < 1000 || milliseconds % 1000 != 0) {
    return '${milliseconds}ms';
  }
  return '${duration.inSeconds}s';
}

const String _missingOutputFailureReason =
    'simctl recording output file was missing or empty.';

String _missingOutputFailureReasonFor(File outputFile) {
  return '$_missingOutputFailureReason outputPath=${outputFile.path}';
}

bool _isMissingOutputFailure(String? failureReason) {
  return failureReason?.startsWith(_missingOutputFailureReason) ?? false;
}
