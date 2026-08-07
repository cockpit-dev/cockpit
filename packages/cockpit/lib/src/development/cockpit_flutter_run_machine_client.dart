import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../session/cockpit_remote_session_launcher.dart';
import '../session/cockpit_session_process_runner.dart';
import '../infrastructure/cockpit_process_manager.dart';
import 'cockpit_flutter_run_machine_event.dart';

final class CockpitFlutterRunMachineRequestException implements Exception {
  const CockpitFlutterRunMachineRequestException(this.message);

  final String message;

  @override
  String toString() => 'CockpitFlutterRunMachineRequestException: $message';
}

final class CockpitFlutterRunMachineClient {
  CockpitFlutterRunMachineClient({
    required Stream<String> stdoutLines,
    required Stream<String> stderrLines,
    required Future<int> exitCode,
    required Future<void> Function(String payload) requestWriter,
    Future<void> Function()? closeProcess,
  }) : _requestWriter = requestWriter,
       _closeProcess = closeProcess {
    _stdoutSubscription = stdoutLines.listen(_handleStdoutLine);
    _stderrSubscription = stderrLines.listen(_handleStderrLine);
    _exitCodeSubscription = exitCode.asStream().listen(_handleExitCode);
  }

  final Future<void> Function(String payload) _requestWriter;
  final Future<void> Function()? _closeProcess;
  final StreamController<CockpitFlutterRunMachineEvent> _eventsController =
      StreamController<CockpitFlutterRunMachineEvent>.broadcast();
  final Map<int, Completer<Object?>> _requestCompleters =
      <int, Completer<Object?>>{};
  final List<String> _recentDiagnosticLines = <String>[];
  late final StreamSubscription<String> _stdoutSubscription;
  late final StreamSubscription<String> _stderrSubscription;
  late final StreamSubscription<int> _exitCodeSubscription;
  final Completer<Uri> _vmServiceUriCompleter = Completer<Uri>();
  final Completer<String> _appIdCompleter = Completer<String>();
  final Completer<void> _closedCompleter = Completer<void>();
  int _nextRequestId = 0;
  String? _currentAppId;
  Uri? _currentVmServiceUri;
  int? _lastExitCode;
  String? _lastStderrLine;

  Stream<CockpitFlutterRunMachineEvent> get events => _eventsController.stream;

  String? get currentAppId => _currentAppId;
  Uri? get currentVmServiceUri => _currentVmServiceUri;
  int? get lastExitCode => _lastExitCode;
  String? get lastStderrLine => _lastStderrLine;
  String get recentDiagnosticSummary =>
      _recentDiagnosticLines.join('\n').trim();

  Future<Uri> get vmServiceUri => _vmServiceUriCompleter.future;

  static Future<CockpitFlutterRunMachineClient> start({
    required String projectDir,
    required String target,
    required String deviceId,
    String? flavor,
    String? flutterExecutable,
    List<String> extraArgs = const <String>[],
    Map<String, String>? environment,
  }) async {
    final resolvedFlutterExecutable =
        flutterExecutable ?? cockpitFlutterExecutable();
    final process = await cockpitStartIsolatedProcess(
      resolvedFlutterExecutable,
      <String>[
        'run',
        '--machine',
        '--target',
        target,
        '-d',
        deviceId,
        if (flavor != null && flavor.isNotEmpty) ...<String>[
          '--flavor',
          flavor,
        ],
        ...extraArgs,
      ],
      workingDirectory: projectDir,
      environment: environment,
      runInShell: cockpitShouldRunExecutableInShell(resolvedFlutterExecutable),
    );

    return CockpitFlutterRunMachineClient(
      stdoutLines: process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter()),
      stderrLines: process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter()),
      exitCode: process.exitCode,
      requestWriter: (payload) async {
        process.stdin.write(payload);
        await process.stdin.flush();
      },
      closeProcess: () => _terminateProcess(process),
    );
  }

  static Future<CockpitFlutterRunMachineClient> attach({
    required String projectDir,
    required String target,
    required String deviceId,
    String? platformAppId,
    Uri? debugUrl,
    String? flavor,
    String? flutterExecutable,
    List<String> extraArgs = const <String>[],
    Map<String, String>? environment,
  }) async {
    final resolvedFlutterExecutable =
        flutterExecutable ?? cockpitFlutterExecutable();
    final process = await cockpitStartIsolatedProcess(
      resolvedFlutterExecutable,
      <String>[
        'attach',
        '--machine',
        '--target',
        target,
        '-d',
        deviceId,
        if (debugUrl != null) '--debug-url=$debugUrl',
        if (debugUrl == null && platformAppId != null)
          '--app-id=$platformAppId',
        '--no-dds',
        if (flavor != null && flavor.isNotEmpty) ...<String>[
          '--flavor',
          flavor,
        ],
        ...extraArgs,
      ],
      workingDirectory: projectDir,
      environment: environment,
      runInShell: cockpitShouldRunExecutableInShell(resolvedFlutterExecutable),
    );

    return CockpitFlutterRunMachineClient(
      stdoutLines: process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter()),
      stderrLines: process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter()),
      exitCode: process.exitCode,
      requestWriter: (payload) async {
        process.stdin.write(payload);
        await process.stdin.flush();
      },
      closeProcess: () => _terminateProcess(process),
    );
  }

  Future<Object?> sendRequest(
    String method, {
    Map<String, Object?>? params,
  }) async {
    final exitCode = _lastExitCode;
    if (exitCode != null) {
      throw CockpitFlutterRunMachineRequestException(
        _requestFailureMessage(exitCode),
      );
    }
    final id = _nextRequestId++;
    final completer = Completer<Object?>();
    _requestCompleters[id] = completer;
    final payload =
        '[${jsonEncode(<String, Object?>{'id': id, 'method': method, 'params': params})}]\n';
    try {
      await _requestWriter(payload);
    } on Object {
      _requestCompleters.remove(id);
      rethrow;
    }
    return completer.future;
  }

  Future<Object?> hotReload({
    required String appId,
    bool pause = false,
    String? reason,
  }) {
    return sendRequest(
      'app.restart',
      params: <String, Object?>{
        'appId': appId,
        'fullRestart': false,
        'pause': pause,
        'reason': reason,
        'debounce': true,
      },
    );
  }

  Future<Object?> hotRestart({
    required String appId,
    bool pause = false,
    String? reason,
  }) {
    return sendRequest(
      'app.restart',
      params: <String, Object?>{
        'appId': appId,
        'fullRestart': true,
        'pause': pause,
        'reason': reason,
        'debounce': true,
      },
    );
  }

  Future<Object?> stop({required String appId}) {
    return sendRequest('app.stop', params: <String, Object?>{'appId': appId});
  }

  Future<Object?> detach({required String appId}) {
    return sendRequest('app.detach', params: <String, Object?>{'appId': appId});
  }

  Future<String> waitForAppId({
    Duration timeout = const Duration(seconds: 30),
  }) {
    final current = _currentAppId;
    if (current != null && current.isNotEmpty) {
      return Future<String>.value(current);
    }
    return Future.any<String>(<Future<String>>[
      _appIdCompleter.future,
      _closedCompleter.future.then<String>((_) {
        throw CockpitFlutterRunMachineRequestException(
          _lastExitCode == null
              ? 'Flutter machine client closed before app.start.'
              : _requestFailureMessage(_lastExitCode!),
        );
      }),
    ]).timeout(
      timeout,
      onTimeout: () => throw TimeoutException(
        'Flutter machine attach did not report app.start.',
        timeout,
      ),
    );
  }

  Future<void> dispose({bool terminateProcess = true}) async {
    if (terminateProcess) {
      await _closeWithinTimeout(_closeProcess?.call());
    }
    await _closeWithinTimeout(_stdoutSubscription.cancel());
    await _closeWithinTimeout(_stderrSubscription.cancel());
    await _closeWithinTimeout(_exitCodeSubscription.cancel());
    for (final completer in _requestCompleters.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          const CockpitFlutterRunMachineRequestException(
            'Machine client disposed before response was received.',
          ),
        );
      }
    }
    _requestCompleters.clear();
    if (!_closedCompleter.isCompleted) {
      _closedCompleter.complete();
    }
    await _eventsController.close();
  }

  Future<void> _closeWithinTimeout(Future<void>? operation) async {
    if (operation == null) {
      return;
    }
    try {
      await operation.timeout(const Duration(seconds: 1));
    } on TimeoutException {
      // Best-effort shutdown must not hang the supervisor.
    }
  }

  static Future<void> _terminateProcess(Process process) async {
    try {
      process.stdin.close();
    } on Object {
      // Ignore shutdown races.
    }
    if (process.kill(ProcessSignal.sigterm)) {
      await Future.any(<Future<Object?>>[
        process.exitCode,
        Future<Object?>.delayed(const Duration(milliseconds: 400)),
      ]);
    }
    if (!process.kill(ProcessSignal.sigkill)) {
      return;
    }
    await Future.any(<Future<Object?>>[
      process.exitCode,
      Future<Object?>.delayed(const Duration(milliseconds: 200)),
    ]);
  }

  void _handleStdoutLine(String line) {
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      _appendRecentDiagnostic(line);
      _eventsController.add(
        CockpitFlutterRunMachineEvent(
          kind: CockpitFlutterRunMachineEventKind.stdout,
          message: line,
        ),
      );
      return;
    }

    final payload =
        decoded is List && decoded.length == 1 && decoded.first is Map
        ? Map<String, Object?>.from(decoded.first as Map<Object?, Object?>)
        : null;
    if (payload == null) {
      _appendRecentDiagnostic(line);
      _eventsController.add(
        CockpitFlutterRunMachineEvent(
          kind: CockpitFlutterRunMachineEventKind.stdout,
          message: line,
        ),
      );
      return;
    }

    final event = payload['event'];
    final method = payload['method'];
    final id = payload['id'];
    final params = payload['params'] as Map<Object?, Object?>?;
    if (event is String) {
      _handleEvent(
        event,
        params == null ? null : Map<String, Object?>.from(params),
      );
      return;
    }

    if (method is String) {
      _eventsController.add(
        CockpitFlutterRunMachineEvent(
          kind: CockpitFlutterRunMachineEventKind.request,
          method: method,
          id: id as int?,
          params: params == null ? null : Map<String, Object?>.from(params),
        ),
      );
      return;
    }

    if (id is int) {
      final completer = _requestCompleters.remove(id);
      final error = payload['error'];
      if (error != null) {
        completer?.completeError(
          CockpitFlutterRunMachineRequestException('$error'),
        );
      } else {
        completer?.complete(payload['result']);
      }
      _eventsController.add(
        CockpitFlutterRunMachineEvent(
          kind: CockpitFlutterRunMachineEventKind.response,
          id: id,
          result: payload['result'],
          error: error,
        ),
      );
      return;
    }

    _eventsController.add(
      CockpitFlutterRunMachineEvent(
        kind: CockpitFlutterRunMachineEventKind.unknown,
        message: line,
      ),
    );
  }

  void _handleEvent(String eventName, Map<String, Object?>? params) {
    switch (eventName) {
      case 'app.start':
        _currentAppId = params?['appId'] as String?;
        if (_currentAppId case final appId?
            when appId.isNotEmpty && !_appIdCompleter.isCompleted) {
          _appIdCompleter.complete(appId);
        }
      case 'app.debugPort':
        final wsUri = params?['wsUri'] as String?;
        if (wsUri != null) {
          _currentVmServiceUri = Uri.parse(wsUri);
        }
        if (_currentVmServiceUri != null &&
            !_vmServiceUriCompleter.isCompleted) {
          _vmServiceUriCompleter.complete(_currentVmServiceUri!);
        }
    }

    _eventsController.add(
      CockpitFlutterRunMachineEvent(
        kind: _kindForEventName(eventName),
        eventName: eventName,
        params: params,
        message: _messageForEvent(eventName, params),
      ),
    );
  }

  String? _messageForEvent(String eventName, Map<String, Object?>? params) {
    if (params == null) {
      return null;
    }
    return switch (eventName) {
      'app.progress' || 'daemon.logMessage' => params['message'] as String?,
      'app.stop' => params['error'] as String?,
      _ => null,
    };
  }

  void _handleStderrLine(String line) {
    _lastStderrLine = line;
    _appendRecentDiagnostic(line);
    _eventsController.add(
      CockpitFlutterRunMachineEvent(
        kind: CockpitFlutterRunMachineEventKind.stderr,
        message: line,
      ),
    );
  }

  void _handleExitCode(int code) {
    _lastExitCode = code;
    for (final completer in _requestCompleters.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          CockpitFlutterRunMachineRequestException(
            _requestFailureMessage(code),
          ),
        );
      }
    }
    _requestCompleters.clear();
    if (!_closedCompleter.isCompleted) {
      _closedCompleter.complete();
    }
    _eventsController.add(
      CockpitFlutterRunMachineEvent(
        kind: CockpitFlutterRunMachineEventKind.processExit,
        exitCode: code,
      ),
    );
  }

  String _requestFailureMessage(int code) {
    return 'Flutter run machine exited before the request completed '
        '(exitCode=$code)'
        '${recentDiagnosticSummary.isEmpty ? '' : ': $recentDiagnosticSummary'}';
  }

  void _appendRecentDiagnostic(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _recentDiagnosticLines.add(trimmed);
    if (_recentDiagnosticLines.length > 20) {
      _recentDiagnosticLines.removeAt(0);
    }
  }

  static CockpitFlutterRunMachineEventKind _kindForEventName(String eventName) {
    return switch (eventName) {
      'daemon.connected' => CockpitFlutterRunMachineEventKind.daemonConnected,
      'app.start' => CockpitFlutterRunMachineEventKind.appStart,
      'app.started' => CockpitFlutterRunMachineEventKind.appStarted,
      'app.stop' => CockpitFlutterRunMachineEventKind.appStop,
      'app.debugPort' => CockpitFlutterRunMachineEventKind.appDebugPort,
      'app.progress' => CockpitFlutterRunMachineEventKind.appProgress,
      'daemon.logMessage' => CockpitFlutterRunMachineEventKind.daemonLogMessage,
      _ => CockpitFlutterRunMachineEventKind.unknown,
    };
  }
}
