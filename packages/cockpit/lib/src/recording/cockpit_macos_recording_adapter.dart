import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../platform/macos/cockpit_macos_window_target.dart';
import 'cockpit_host_recording_adapter.dart';

final class CockpitMacosRecordingAdapter
    implements CockpitHostRecordingAdapter {
  CockpitMacosRecordingAdapter({
    required String appId,
    String ffmpegExecutable = 'ffmpeg',
    String osascriptExecutable = 'osascript',
    CockpitRecordingProcessStarter processStarter =
        cockpitStartDetachedRecordingProcess,
    CockpitRecordingProcessRunner? processRunner,
    CockpitRecordingProcessRunner? ffprobeProcessRunner,
    CockpitRecordingTempFileFactory tempFileFactory =
        cockpitCreateRecordingTempFile,
    CockpitMacosWindowTargetResolver windowTargetResolver =
        cockpitResolveMacosWindowTarget,
    Duration startupTimeout = const Duration(seconds: 12),
    Duration commandTimeout = cockpitDefaultRecordingCommandTimeout,
    Duration startupEvidenceTimeout = const Duration(seconds: 2),
    Duration stopTimeout = const Duration(seconds: 10),
    Duration finalizationPollInterval = const Duration(milliseconds: 100),
    Duration activationSettleDelay = const Duration(milliseconds: 350),
    CockpitPidSignalSender pidSignalSender = Process.killPid,
    CockpitPidLivenessChecker pidLivenessChecker =
        cockpitDefaultPidLivenessChecker,
  }) : _appId = appId,
       _ffmpegExecutable = ffmpegExecutable,
       _osascriptExecutable = osascriptExecutable,
       _processStarter = processStarter,
       _processRunner = processRunner,
       _ffprobeProcessRunner = ffprobeProcessRunner ?? processRunner,
       _tempFileFactory = tempFileFactory,
       _windowTargetResolver = windowTargetResolver,
       _startupTimeout = startupTimeout,
       _commandTimeout = commandTimeout,
       _startupEvidenceTimeout = startupEvidenceTimeout,
       _stopTimeout = stopTimeout,
       _finalizationPollInterval = finalizationPollInterval,
       _activationSettleDelay = activationSettleDelay,
       _pidSignalSender = pidSignalSender,
       _pidLivenessChecker = pidLivenessChecker;

  final String _appId;
  final String _ffmpegExecutable;
  final String _osascriptExecutable;
  final CockpitRecordingProcessStarter _processStarter;
  final CockpitRecordingProcessRunner? _processRunner;
  final CockpitRecordingProcessRunner? _ffprobeProcessRunner;
  final CockpitRecordingTempFileFactory _tempFileFactory;
  final CockpitMacosWindowTargetResolver _windowTargetResolver;
  final Duration _startupTimeout;
  final Duration _commandTimeout;
  final Duration _startupEvidenceTimeout;
  final Duration _stopTimeout;
  final Duration _finalizationPollInterval;
  final Duration _activationSettleDelay;
  final CockpitPidSignalSender _pidSignalSender;
  final CockpitPidLivenessChecker _pidLivenessChecker;

  static const Set<String> _browserAppIds = <String>{
    'com.google.Chrome',
    'com.microsoft.edgemac',
    'org.mozilla.firefox',
  };

  Process? _process;
  CockpitRecordingRequest? _request;
  File? _outputFile;
  StreamSubscription<String>? _stderrSubscription;
  List<String>? _recentStderrLines;
  Stopwatch? _stopwatch;
  DateTime? _startedAt;

  String get _sessionCacheKey => 'macos:$_appId';

  bool get _usesBrowserHostCapture => _browserAppIds.contains(_appId);

  Duration get _effectiveStartupEvidenceTimeout {
    if (!_usesBrowserHostCapture) {
      return _startupEvidenceTimeout;
    }
    const browserMinimum = Duration(seconds: 6);
    return _startupEvidenceTimeout >= browserMinimum
        ? _startupEvidenceTimeout
        : browserMinimum;
  }

  Duration get _effectiveActivationSettleDelay {
    if (!_usesBrowserHostCapture) {
      return _activationSettleDelay;
    }
    const browserMinimum = Duration(seconds: 1);
    return _activationSettleDelay >= browserMinimum
        ? _activationSettleDelay
        : browserMinimum;
  }

  @override
  Future<CockpitRecordingSession> startRecording(
    CockpitRecordingRequest request,
  ) async {
    if (_process != null || await _restoreableSessionExists()) {
      throw StateError('A macOS recording is already active.');
    }

    await _activateApp();
    if (_effectiveActivationSettleDelay > Duration.zero) {
      await Future<void>.delayed(_effectiveActivationSettleDelay);
    }

    final inputSpecifier = await _resolveScreenInputSpecifier();
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
      'avfoundation',
      '-framerate',
      '30',
      '-capture_cursor',
      '1',
      '-i',
      inputSpecifier,
      '-vf',
      'scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p',
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
        cockpitClearActiveHostRecordingSession(_sessionCacheKey);
        throw StateError(_buildStartupFailureMessage(recentStderrLines));
      }
    } on Object {
      await stderrSubscription.cancel();
      await cockpitKillRecordingProcess(process);
      cockpitClearActiveHostRecordingSession(_sessionCacheKey);
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
        throw StateError('No active macOS recording session exists.');
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
            'macOS recording did not stop after SIGINT, SIGTERM, and SIGKILL.',
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
            'macOS recording output file was missing or empty. Ensure Screen Recording permission is granted to the terminal, Dart, ffmpeg, and the browser host app.',
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
            'macOS recording output did not finalize to a stable duration.',
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
          'macOS recording did not stop before timeout.',
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
            'macOS recording did not stop after SIGINT, SIGTERM, and SIGKILL.',
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
          'macOS recording did not stop before timeout.',
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
          'macOS recording output file was missing or empty. Ensure Screen Recording permission is granted to the terminal, Dart, ffmpeg, and the browser host app.',
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
          'macOS recording output did not finalize to a stable duration.',
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
      waitTimeout: _stopStageTimeout(const Duration(seconds: 4)),
      pollInterval: _finalizationPollInterval,
    )) {
      return true;
    }
    if (await cockpitSignalRecordingPid(
      pid,
      ProcessSignal.sigterm,
      signalSender: _pidSignalSender,
      livenessChecker: _pidLivenessChecker,
      waitTimeout: _stopStageTimeout(const Duration(seconds: 4)),
      pollInterval: _finalizationPollInterval,
    )) {
      return true;
    }
    return cockpitSignalRecordingPid(
      pid,
      ProcessSignal.sigkill,
      signalSender: _pidSignalSender,
      livenessChecker: _pidLivenessChecker,
      waitTimeout: _stopStageTimeout(const Duration(seconds: 2)),
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

  Future<void> _activateApp() async {
    final result = await _runProcess(_osascriptExecutable, <String>[
      '-l',
      'JavaScript',
      '-e',
      _activateAppScript,
      _appId,
    ], timeout: _commandTimeout);
    if (result.exitCode != 0) {
      throw StateError(
        'Unable to activate macOS app $_appId: ${result.stderr ?? result.stdout}',
      );
    }
  }

  static const String _activateAppScript = r'''
ObjC.import('AppKit')
ObjC.import('IOKit')
ObjC.bindFunction('IOPMAssertionDeclareUserActivity', ['int', ['id', 'uint32', 'uint32*']])

function run(argv) {
  const appId = argv[0]
  const assertionId = Ref()
  const wakeResult = $.IOPMAssertionDeclareUserActivity(
    $('Cockpit application recording'),
    0,
    assertionId,
  )
  if (Number(wakeResult) !== 0) {
    throw new Error(`Unable to wake the macOS display for ${appId}: ${wakeResult}`)
  }
  const apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier(appId)
  if (apps.count === 0) {
    throw new Error(`No running macOS application was found for ${appId}`)
  }
  if (!apps.objectAtIndex(0).activateWithOptions($.NSApplicationActivateIgnoringOtherApps)) {
    throw new Error(`Unable to activate macOS application ${appId}`)
  }
}
''';

  Future<String> _resolveScreenInputSpecifier() async {
    final result = await _runProcess(_ffmpegExecutable, <String>[
      '-f',
      'avfoundation',
      '-list_devices',
      'true',
      '-i',
      '',
    ], timeout: _commandTimeout);
    final output = <String>['${result.stdout}', '${result.stderr}'].join('\n');
    final screens = _parseCaptureScreens(output);
    if (screens.isEmpty) {
      throw StateError('Unable to resolve a macOS capture screen input.');
    }
    final selectedScreen = await _selectCaptureScreen(screens);
    return '${selectedScreen.index}:none';
  }

  Future<_CockpitMacosCaptureScreen> _selectCaptureScreen(
    List<_CockpitMacosCaptureScreen> screens,
  ) async {
    if (screens.length == 1) {
      return screens.first;
    }

    final screensWithBounds = screens
        .where((screen) => screen.hasBounds)
        .toList(growable: false);
    if (screensWithBounds.isEmpty) {
      return screens.first;
    }

    final windowTarget = await _tryResolveWindowTarget();
    if (windowTarget == null) {
      return screens.first;
    }

    _CockpitMacosCaptureScreen? bestScreen;
    var bestOverlap = 0;
    for (final screen in screensWithBounds) {
      final overlap = screen.overlapAreaWith(windowTarget);
      if (overlap > bestOverlap) {
        bestScreen = screen;
        bestOverlap = overlap;
      }
    }
    if (bestScreen != null && bestOverlap > 0) {
      return bestScreen;
    }

    final centerX = windowTarget.left + (windowTarget.width / 2.0);
    final centerY = windowTarget.top + (windowTarget.height / 2.0);
    for (final screen in screensWithBounds) {
      if (screen.containsPoint(centerX, centerY)) {
        return screen;
      }
    }

    var nearestScreen = screensWithBounds.first;
    var nearestDistance = nearestScreen.squaredDistanceToPoint(
      centerX,
      centerY,
    );
    for (final screen in screensWithBounds.skip(1)) {
      final distance = screen.squaredDistanceToPoint(centerX, centerY);
      if (distance < nearestDistance) {
        nearestScreen = screen;
        nearestDistance = distance;
      }
    }
    return nearestScreen;
  }

  Future<CockpitMacosWindowTarget?> _tryResolveWindowTarget() async {
    try {
      return await _windowTargetResolver(
        appId: _appId,
        osascriptExecutable: _osascriptExecutable,
        processRunner: (executable, arguments) =>
            _runProcess(executable, arguments, timeout: _commandTimeout),
        timeout: _commandTimeout,
        activationSettleDelay: Duration.zero,
      );
    } on Object {
      return null;
    }
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

  Duration _stopStageTimeout(Duration maximum) {
    if (_stopTimeout <= Duration.zero) {
      return maximum;
    }
    return _stopTimeout < maximum ? _stopTimeout : maximum;
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
        'ffmpeg never confirmed macOS screen capture startup or produced output. '
        'Ensure Screen Recording permission is granted to the terminal, Dart, and ffmpeg on this host.';
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
      timeout: _effectiveStartupEvidenceTimeout,
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
      timeout: _stopStageTimeout(const Duration(seconds: 2)),
      livenessChecker: _pidLivenessChecker,
      pollInterval: _finalizationPollInterval,
    );
  }

  String _withRecentStderr(String prefix, List<String> recentStderrLines) {
    if (recentStderrLines.isEmpty) {
      return prefix;
    }
    return '$prefix Recent ffmpeg output: ${recentStderrLines.join(' | ')}';
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

List<_CockpitMacosCaptureScreen> _parseCaptureScreens(String output) {
  return _captureScreenPattern
      .allMatches(output)
      .map((match) {
        return _CockpitMacosCaptureScreen(
          index: int.parse(match.group(1)!),
          width: int.tryParse(match.group(2) ?? ''),
          height: int.tryParse(match.group(3) ?? ''),
          left: int.tryParse(match.group(4) ?? ''),
          top: int.tryParse(match.group(5) ?? ''),
        );
      })
      .toList(growable: false);
}

final RegExp _captureScreenPattern = RegExp(
  r'\[([0-9]+)\]\s+Capture screen(?:\s+\d+)?(?:\s+(\d+)x(\d+)\s+@\s+(-?\d+),(-?\d+))?',
  multiLine: true,
);

final class _CockpitMacosCaptureScreen {
  const _CockpitMacosCaptureScreen({
    required this.index,
    this.width,
    this.height,
    this.left,
    this.top,
  });

  final int index;
  final int? width;
  final int? height;
  final int? left;
  final int? top;

  bool get hasBounds =>
      width != null &&
      height != null &&
      left != null &&
      top != null &&
      width! > 0 &&
      height! > 0;

  int get _right => left! + width!;
  int get _bottom => top! + height!;

  bool containsPoint(double x, double y) {
    if (!hasBounds) {
      return false;
    }
    return x >= left! && x < _right && y >= top! && y < _bottom;
  }

  int overlapAreaWith(CockpitMacosWindowTarget target) {
    if (!hasBounds) {
      return 0;
    }
    final overlapLeft = math.max(left!, target.left);
    final overlapTop = math.max(top!, target.top);
    final overlapRight = math.min(_right, target.left + target.width);
    final overlapBottom = math.min(_bottom, target.top + target.height);
    final overlapWidth = overlapRight - overlapLeft;
    final overlapHeight = overlapBottom - overlapTop;
    if (overlapWidth <= 0 || overlapHeight <= 0) {
      return 0;
    }
    return overlapWidth * overlapHeight;
  }

  double squaredDistanceToPoint(double x, double y) {
    if (!hasBounds) {
      return double.infinity;
    }
    final dx = x < left!
        ? left! - x
        : x > _right
        ? x - _right
        : 0.0;
    final dy = y < top!
        ? top! - y
        : y > _bottom
        ? y - _bottom
        : 0.0;
    return (dx * dx) + (dy * dy);
  }
}

final class _CockpitRecordingTimelineProbe {
  const _CockpitRecordingTimelineProbe({required this.durationMs});

  final int durationMs;
}
