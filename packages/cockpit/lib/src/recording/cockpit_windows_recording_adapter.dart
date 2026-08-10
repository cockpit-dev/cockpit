import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../platform/windows/cockpit_windows_window_target.dart';
import 'cockpit_host_recording_adapter.dart';

final class CockpitWindowsRecordingAdapter
    implements CockpitHostRecordingAdapter {
  CockpitWindowsRecordingAdapter({
    required String appId,
    int? processId,
    String ffmpegExecutable = 'ffmpeg',
    CockpitRecordingProcessStarter processStarter =
        cockpitStartDetachedRecordingProcess,
    CockpitRecordingProcessRunner? processRunner,
    CockpitRecordingProcessRunner? ffprobeProcessRunner,
    CockpitRecordingTempFileFactory tempFileFactory =
        cockpitCreateRecordingTempFile,
    CockpitWindowsWindowResolver windowResolver =
        cockpitResolveWindowsWindowTarget,
    Duration startupTimeout = const Duration(seconds: 12),
    Duration commandTimeout = cockpitDefaultRecordingCommandTimeout,
    Duration startupEvidenceTimeout = const Duration(seconds: 2),
    Duration stopTimeout = const Duration(seconds: 10),
    Duration finalizationPollInterval = const Duration(milliseconds: 100),
    Duration activationSettleDelay = const Duration(milliseconds: 250),
    CockpitPidSignalSender pidSignalSender = Process.killPid,
    CockpitPidLivenessChecker pidLivenessChecker =
        cockpitDefaultPidLivenessChecker,
  }) : _appId = appId,
       _processId = processId,
       _ffmpegExecutable = ffmpegExecutable,
       _processStarter = processStarter,
       _ffprobeProcessRunner = ffprobeProcessRunner ?? processRunner,
       _tempFileFactory = tempFileFactory,
       _windowResolver = windowResolver,
       _startupTimeout = startupTimeout,
       _commandTimeout = commandTimeout,
       _startupEvidenceTimeout = startupEvidenceTimeout,
       _stopTimeout = stopTimeout,
       _finalizationPollInterval = finalizationPollInterval,
       _activationSettleDelay = activationSettleDelay,
       _pidSignalSender = pidSignalSender,
       _pidLivenessChecker = pidLivenessChecker;

  final String _appId;
  final int? _processId;
  final String _ffmpegExecutable;
  final CockpitRecordingProcessStarter _processStarter;
  final CockpitRecordingProcessRunner? _ffprobeProcessRunner;
  final CockpitRecordingTempFileFactory _tempFileFactory;
  final CockpitWindowsWindowResolver _windowResolver;
  final Duration _startupTimeout;
  final Duration _commandTimeout;
  final Duration _startupEvidenceTimeout;
  final Duration _stopTimeout;
  final Duration _finalizationPollInterval;
  final Duration _activationSettleDelay;
  final CockpitPidSignalSender _pidSignalSender;
  final CockpitPidLivenessChecker _pidLivenessChecker;

  Process? _process;
  CockpitRecordingRequest? _request;
  File? _outputFile;
  StreamSubscription<String>? _stderrSubscription;
  List<String>? _recentStderrLines;
  Stopwatch? _stopwatch;
  DateTime? _startedAt;

  String get _sessionCacheKey => 'windows:${_processId ?? _appId}';

  @override
  Future<CockpitRecordingSession> startRecording(
    CockpitRecordingRequest request,
  ) async {
    if (_process != null || await _restoreableSessionExists()) {
      throw StateError('A Windows recording is already active.');
    }

    final windowTarget = await _windowResolver(
      appId: _appId,
      processId: _processId,
      timeout: _commandTimeout,
      activationSettleDelay: _activationSettleDelay,
    );

    final outputFile = await _tempFileFactory(
      cockpitRecordingFileName(request.name),
    );
    outputFile.parent.createSync(recursive: true);
    if (outputFile.existsSync()) {
      outputFile.deleteSync();
    }

    final process = await _processStarter(_ffmpegExecutable, <String>[
      '-y',
      '-f',
      'gdigrab',
      '-framerate',
      '30',
      '-draw_mouse',
      '1',
      '-i',
      'hwnd=${windowTarget.handle}',
      '-vf',
      'format=yuv420p',
      '-c:v',
      'libx264',
      '-movflags',
      '+faststart',
      outputFile.path,
    ]);

    final stdoutSubscription = process.stdout.listen((_) {});

    final recentStderrLines = <String>[];
    final stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          _appendRecentStderrLine(recentStderrLines, line);
        });

    try {
      final started = await _waitForDetachedStartup(
        pid: process.pid,
        outputFile: outputFile,
        recentStderrLines: recentStderrLines,
      );
      if (!started) {
        await stderrSubscription.cancel();
        await cockpitKillRecordingProcess(process);
        throw StateError(_buildStartupFailureMessage(recentStderrLines));
      }
    } on Object {
      await stderrSubscription.cancel();
      await cockpitKillRecordingProcess(process);
      rethrow;
    }

    final startedAt = DateTime.now().toUtc();
    final stderrLogFile = cockpitHostRecordingSessionPaths(
      _sessionCacheKey,
    ).stderrLogFile;
    await stderrLogFile.parent.create(recursive: true);
    await stderrLogFile.writeAsString(
      recentStderrLines.isEmpty ? '' : '${recentStderrLines.join('\n')}\n',
      flush: true,
    );
    await cockpitPersistHostRecordingSession(
      _sessionCacheKey,
      CockpitHostRecordingPersistedSession(
        pid: process.pid,
        request: request,
        outputFilePath: outputFile.path,
        startedAt: startedAt,
        stderrLogPath: stderrLogFile.path,
      ),
    );
    await cockpitCancelRecordingSubscription(stdoutSubscription);
    await cockpitCancelRecordingSubscription(stderrSubscription);

    _process = process;
    _request = request;
    _outputFile = outputFile;
    _stderrSubscription = null;
    _recentStderrLines = recentStderrLines;
    _stopwatch = Stopwatch()..start();
    _startedAt = startedAt;
    cockpitStoreActiveHostRecordingSession(
      _sessionCacheKey,
      CockpitHostRecordingRuntimeSession(
        process: process,
        request: request,
        outputFile: outputFile,
        stderrSubscription: null,
        stopwatch: _stopwatch,
        startedAt: startedAt,
        recentStderrLines: recentStderrLines,
      ),
    );

    return CockpitRecordingSession(
      request: request,
      state: CockpitRecordingState.recording,
    );
  }

  @override
  Future<CockpitRecordingResult> stopRecording() async {
    final session = _currentSessionState;
    if (session == null) {
      final persistedSession = cockpitReadPersistedHostRecordingSession(
        _sessionCacheKey,
      );
      if (persistedSession == null) {
        throw StateError('No active Windows recording session exists.');
      }
      return _stopPersistedRecording(persistedSession);
    }
    final process = session.process;
    final request = session.request;
    final outputFile = session.outputFile;
    final stopwatch = session.stopwatch;

    try {
      final didStopGracefully = await _requestGracefulStop(process);
      final didStopAfterSignal =
          didStopGracefully || await _requestPidSignalStop(process.pid);
      if (!didStopAfterSignal) {
        return CockpitRecordingResult(
          state: CockpitRecordingState.failed,
          purpose: request.purpose,
          recordingKind: CockpitRecordingKind.nativeScreen,
          failureReason: _withRecentStderr(
            'Windows recording did not stop after SIGINT, SIGTERM, and SIGKILL.',
            session.recentStderrLines,
          ),
        );
      }

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
          failureReason: _withRecentStderr(
            'Windows recording output file was missing or empty.',
            session.recentStderrLines,
          ),
        );
      }
      final finalized = await _waitForFinalizedOutput(outputFile);
      if (!finalized) {
        return CockpitRecordingResult(
          state: CockpitRecordingState.failed,
          purpose: request.purpose,
          recordingKind: CockpitRecordingKind.nativeScreen,
          failureReason: _withRecentStderr(
            'Windows recording output did not finalize to a stable duration.',
            session.recentStderrLines,
          ),
        );
      }

      stopwatch?.stop();
      cockpitClearPersistedHostRecordingSession(_sessionCacheKey);
      return CockpitRecordingResult(
        state: CockpitRecordingState.completed,
        purpose: request.purpose,
        recordingKind: CockpitRecordingKind.nativeScreen,
        artifact: cockpitRecordingArtifactForName(request.name),
        durationMs: stopwatch?.elapsedMilliseconds ?? _durationMs(session),
        sourceFilePath: outputFile.path,
      );
    } on TimeoutException {
      await cockpitKillRecordingProcess(process, waitTimeout: _stopTimeout);
      return CockpitRecordingResult(
        state: CockpitRecordingState.failed,
        purpose: request.purpose,
        recordingKind: CockpitRecordingKind.nativeScreen,
        failureReason: _withRecentStderr(
          'Windows recording did not stop before timeout.',
          session.recentStderrLines,
        ),
      );
    } finally {
      await session.stderrSubscription?.cancel();
      cockpitClearActiveHostRecordingSession(_sessionCacheKey);
      cockpitClearPersistedHostRecordingSession(_sessionCacheKey);
      _process = null;
      _request = null;
      _outputFile = null;
      _stderrSubscription = null;
      _recentStderrLines = null;
      _stopwatch = null;
      _startedAt = null;
    }
  }

  CockpitHostRecordingRuntimeSession? get _currentSessionState {
    final process = _process;
    final request = _request;
    final outputFile = _outputFile;
    if (process != null && request != null && outputFile != null) {
      return CockpitHostRecordingRuntimeSession(
        process: process,
        request: request,
        outputFile: outputFile,
        stderrSubscription: _stderrSubscription,
        stopwatch: _stopwatch,
        startedAt: _startedAt,
        recentStderrLines: _recentStderrLines ?? const <String>[],
      );
    }
    return cockpitReadActiveHostRecordingSession(_sessionCacheKey);
  }

  Future<CockpitRecordingResult> _stopPersistedRecording(
    CockpitHostRecordingPersistedSession session,
  ) async {
    final outputFile = File(session.outputFilePath);
    final recentStderrLines = cockpitRecentHostRecordingStderrLines(session);
    try {
      final didStopAfterSignal = await _requestPidSignalStop(session.pid);
      if (!didStopAfterSignal) {
        return CockpitRecordingResult(
          state: CockpitRecordingState.failed,
          purpose: session.request.purpose,
          recordingKind: CockpitRecordingKind.nativeScreen,
          failureReason: _withRecentStderr(
            'Windows recording did not stop after SIGINT, SIGTERM, and SIGKILL.',
            recentStderrLines,
          ),
        );
      }
      return await _finalizeStoppedRecording(
        request: session.request,
        outputFile: outputFile,
        durationMs: DateTime.now()
            .toUtc()
            .difference(session.startedAt)
            .inMilliseconds,
        recentStderrLines: recentStderrLines,
      );
    } on TimeoutException {
      await cockpitSignalRecordingPid(
        session.pid,
        ProcessSignal.sigkill,
        signalSender: _pidSignalSender,
        livenessChecker: _pidLivenessChecker,
        waitTimeout: _stopTimeout,
        pollInterval: _finalizationPollInterval,
      );
      return CockpitRecordingResult(
        state: CockpitRecordingState.failed,
        purpose: session.request.purpose,
        recordingKind: CockpitRecordingKind.nativeScreen,
        failureReason: _withRecentStderr(
          'Windows recording did not stop before timeout.',
          recentStderrLines,
        ),
      );
    } finally {
      cockpitClearActiveHostRecordingSession(_sessionCacheKey);
    }
  }

  Future<CockpitRecordingResult> _finalizeStoppedRecording({
    required CockpitRecordingRequest request,
    required File outputFile,
    required int durationMs,
    required List<String> recentStderrLines,
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
        failureReason: _withRecentStderr(
          'Windows recording output file was missing or empty.',
          recentStderrLines,
        ),
      );
    }
    final finalized = await _waitForFinalizedOutput(outputFile);
    if (!finalized) {
      return CockpitRecordingResult(
        state: CockpitRecordingState.failed,
        purpose: request.purpose,
        recordingKind: CockpitRecordingKind.nativeScreen,
        failureReason: _withRecentStderr(
          'Windows recording output did not finalize to a stable duration.',
          recentStderrLines,
        ),
      );
    }
    return CockpitRecordingResult(
      state: CockpitRecordingState.completed,
      purpose: request.purpose,
      recordingKind: CockpitRecordingKind.nativeScreen,
      artifact: cockpitRecordingArtifactForName(request.name),
      durationMs: durationMs,
      sourceFilePath: outputFile.path,
    );
  }

  Future<bool> _requestPidSignalStop(int pid) async {
    if (!await _pidLivenessChecker(pid)) {
      return true;
    }
    if (await cockpitSignalRecordingPid(
      pid,
      ProcessSignal.sigint,
      signalSender: _pidSignalSender,
      livenessChecker: _pidLivenessChecker,
      waitTimeout: _stopTimeout,
      pollInterval: _finalizationPollInterval,
    )) {
      return true;
    }
    if (await cockpitSignalRecordingPid(
      pid,
      ProcessSignal.sigterm,
      signalSender: _pidSignalSender,
      livenessChecker: _pidLivenessChecker,
      waitTimeout: _stopTimeout,
      pollInterval: _finalizationPollInterval,
    )) {
      return true;
    }
    return cockpitSignalRecordingPid(
      pid,
      ProcessSignal.sigkill,
      signalSender: _pidSignalSender,
      livenessChecker: _pidLivenessChecker,
      waitTimeout: _stopTimeout,
      pollInterval: _finalizationPollInterval,
    );
  }

  Future<bool> _restoreableSessionExists() async {
    final runtime = cockpitReadActiveHostRecordingSession(_sessionCacheKey);
    if (runtime != null) {
      return true;
    }
    final persisted = cockpitReadPersistedHostRecordingSession(
      _sessionCacheKey,
    );
    if (persisted == null) {
      return false;
    }
    if (await _pidLivenessChecker(persisted.pid)) {
      return true;
    }
    cockpitClearPersistedHostRecordingSession(_sessionCacheKey);
    return false;
  }

  int? _durationMs(CockpitHostRecordingRuntimeSession session) {
    final startedAt = session.startedAt;
    if (startedAt == null) {
      return null;
    }
    return DateTime.now().toUtc().difference(startedAt).inMilliseconds;
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
      if (probe != null && probe.durationMs > 0) {
        return true;
      }
      await Future<void>.delayed(_finalizationPollInterval);
    }

    final finalProbe = await _probeRecordingTimeline(outputFile.path);
    return finalProbe != null && finalProbe.durationMs > 0;
  }

  Future<_CockpitRecordingTimelineProbe?> _probeRecordingTimeline(
    String path,
  ) async {
    try {
      final result = await _runFfprobeProcess('ffprobe', <String>[
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
      return _CockpitRecordingTimelineProbe(
        durationMs: (durationSeconds * 1000).round(),
      );
    } on Object {
      return null;
    }
  }

  void _appendRecentStderrLine(List<String> buffer, String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return;
    }
    buffer.add(trimmed);
    if (buffer.length > 8) {
      buffer.removeAt(0);
    }
  }

  String _buildStartupFailureMessage(List<String> recentStderrLines) {
    const prefix =
        'Windows recording did not confirm startup or produce output. '
        'Ensure the desktop session is active and ffmpeg gdigrab can capture the screen on this host.';
    if (recentStderrLines.isEmpty) {
      return prefix;
    }
    return '$prefix Recent ffmpeg output: ${recentStderrLines.join(' | ')}';
  }

  String _withRecentStderr(String prefix, List<String> recentStderrLines) {
    if (recentStderrLines.isEmpty) {
      return prefix;
    }
    return '$prefix Recent ffmpeg output: ${recentStderrLines.join(' | ')}';
  }

  Future<bool> _waitForDetachedStartup({
    required int pid,
    required File outputFile,
    required List<String> recentStderrLines,
  }) async {
    final deadline = DateTime.now().add(_startupTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_hasStartupConfirmation(recentStderrLines)) {
        return true;
      }
      if (outputFile.existsSync() && outputFile.lengthSync() > 0) {
        return true;
      }
      await Future<void>.delayed(_finalizationPollInterval);
    }
    if (_hasStartupConfirmation(recentStderrLines)) {
      return true;
    }
    if (outputFile.existsSync() && outputFile.lengthSync() > 0) {
      return true;
    }
    if (!await _pidLivenessChecker(pid)) {
      return false;
    }
    return cockpitWaitForNonEmptyFile(
      outputFile,
      timeout: _startupEvidenceTimeout,
      pollInterval: _finalizationPollInterval,
    );
  }

  bool _hasStartupConfirmation(List<String> recentStderrLines) {
    return recentStderrLines.any(
      (line) =>
          line.contains('Press [q] to stop') || line.contains('Output #0'),
    );
  }

  Future<bool> _requestGracefulStop(Process process) async {
    try {
      process.stdin.writeln('q');
      await process.stdin.flush();
    } on Object {
      return false;
    }
    return cockpitWaitForRecordingProcessOrPidExit(
      process,
      timeout: _stopTimeout,
      livenessChecker: _pidLivenessChecker,
      pollInterval: _finalizationPollInterval,
    );
  }

  Duration _stopStageTimeout(Duration maximum) {
    if (_stopTimeout <= Duration.zero) {
      return maximum;
    }
    return _stopTimeout < maximum ? _stopTimeout : maximum;
  }

  Future<ProcessResult> _runFfprobeProcess(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  }) {
    final injected = _ffprobeProcessRunner;
    if (injected != null) {
      return injected(executable, arguments).timeout(timeout);
    }
    return cockpitRunRecordingProcessWithTimeout(
      executable,
      arguments,
      timeout: timeout,
    );
  }
}

final class _CockpitRecordingTimelineProbe {
  const _CockpitRecordingTimelineProbe({required this.durationMs});

  final int durationMs;
}
