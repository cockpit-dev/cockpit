import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cockpit_protocol/cockpit_protocol.dart';
import '../foundation/cockpit_home.dart';
import '../foundation/cockpit_locked_json_store.dart';
import '../foundation/cockpit_permissions.dart';
import 'cockpit_daemon_discovery.dart';
import 'cockpit_daemon_host.dart';

final class CockpitDaemonException implements Exception {
  const CockpitDaemonException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'CockpitDaemonException($code): $message';
}

final class CockpitDaemonStatus {
  const CockpitDaemonStatus({
    required this.running,
    required this.healthy,
    this.processId,
    this.endpoint,
    this.engineVersion,
    this.apiVersion,
    this.startedAt,
    this.authorizationMode,
    this.diagnostic,
  });

  final bool running;
  final bool healthy;
  final int? processId;
  final Uri? endpoint;
  final String? engineVersion;
  final CockpitApiVersion? apiVersion;
  final DateTime? startedAt;
  final CockpitAuthorizationMode? authorizationMode;
  final String? diagnostic;

  Map<String, Object?> toJson() => <String, Object?>{
    'running': running,
    'healthy': healthy,
    if (processId != null) 'processId': processId,
    if (endpoint != null) 'endpoint': endpoint.toString(),
    if (engineVersion != null) 'engineVersion': engineVersion,
    if (apiVersion != null) 'apiVersion': apiVersion!.toJson(),
    if (startedAt != null) 'startedAt': startedAt!.toUtc().toIso8601String(),
    if (authorizationMode != null) 'auth': authorizationMode!.name,
    if (diagnostic != null) 'diagnostic': diagnostic,
  };
}

final class CockpitDaemonLifecycleClient {
  CockpitDaemonLifecycleClient({
    required this.paths,
    required this.executable,
    required Iterable<String> daemonArguments,
    required Iterable<String> restartArguments,
    required this.permissionHardener,
    required this.directorySyncer,
    required this.requiredEngineVersion,
    this.requiredApiMajor = 2,
    this.startTimeout = const Duration(minutes: 2),
    this.launchFailure,
  }) : daemonArguments = List<String>.unmodifiable(daemonArguments),
       restartArguments = List<String>.unmodifiable(restartArguments);

  final CockpitHomePaths paths;
  final String executable;
  final List<String> daemonArguments;
  final List<String> restartArguments;
  final CockpitPermissionHardener permissionHardener;
  final CockpitDirectorySyncer directorySyncer;
  final String requiredEngineVersion;
  final int requiredApiMajor;
  final Duration startTimeout;
  final CockpitDaemonException? launchFailure;

  CockpitDaemonDiscoveryStore get _store => CockpitDaemonDiscoveryStore(
    paths: paths,
    permissionHardener: permissionHardener,
    directorySyncer: directorySyncer,
  );

  Future<CockpitDaemonDiscovery> ensure({Duration? timeout}) {
    final deadline = DateTime.now().toUtc().add(timeout ?? startTimeout);
    return _withLifecycleLock(deadline, () async {
      var launchAuthorizationMode = CockpitAuthorizationMode.restricted;
      final discovery = await _usableDiscovery(
        replaceIncompatibleEngine: true,
        onEngineReplacement: (mode) => launchAuthorizationMode = mode,
        deadline: deadline,
      );
      if (discovery != null) return discovery;
      return _startAndWait(
        launchAuthorizationMode,
        timeout: _remaining(deadline),
      );
    });
  }

  Future<CockpitDaemonDiscovery> start({
    CockpitAuthorizationMode? authorizationMode,
    Duration? timeout,
  }) {
    final deadline = DateTime.now().toUtc().add(timeout ?? startTimeout);
    return _withLifecycleLock(deadline, () async {
      var launchAuthorizationMode =
          authorizationMode ?? CockpitAuthorizationMode.restricted;
      final discovery = await _usableDiscovery(
        replaceIncompatibleEngine: true,
        onEngineReplacement: (mode) {
          if (authorizationMode == null) launchAuthorizationMode = mode;
        },
        deadline: deadline,
      );
      if (discovery != null) {
        if (authorizationMode == null ||
            discovery.authorizationMode == authorizationMode) {
          return discovery;
        }
        await _stopDiscovery(
          discovery,
          mode: CockpitDaemonShutdownMode.drain,
          timeout: _remaining(deadline),
        );
      }
      return _startAndWait(
        launchAuthorizationMode,
        timeout: _remaining(deadline),
      );
    });
  }

  Future<CockpitDaemonStatus> status() async {
    CockpitDaemonDiscovery? discovery;
    try {
      discovery = await _store.read();
    } on Object {
      return const CockpitDaemonStatus(
        running: false,
        healthy: false,
        diagnostic: 'discoveryInvalid',
      );
    }
    if (discovery == null) {
      return const CockpitDaemonStatus(running: false, healthy: false);
    }
    final identity = await const CockpitSystemProcessIdentityProbe()
        .readStartIdentity(discovery.processId);
    final running = identity == discovery.processStartIdentity;
    final server = running ? await _health(discovery) : null;
    return CockpitDaemonStatus(
      running: running,
      healthy: server != null,
      processId: running ? discovery.processId : null,
      endpoint: running ? discovery.endpoint : null,
      engineVersion: server?.engineVersion,
      apiVersion: server?.apiVersion,
      startedAt: server?.startedAt,
      authorizationMode: running ? discovery.authorizationMode : null,
      diagnostic: !running
          ? 'staleDiscovery'
          : server == null
          ? 'healthUnavailable'
          : server.apiVersion.major != requiredApiMajor
          ? 'upgradeRequired'
          : server.engineVersion != requiredEngineVersion
          ? 'upgradeRequired'
          : null,
    );
  }

  Future<void> stop({
    CockpitDaemonShutdownMode mode = CockpitDaemonShutdownMode.drain,
    Duration timeout = const Duration(seconds: 30),
  }) {
    final deadline = DateTime.now().toUtc().add(timeout);
    return _withLifecycleLock(deadline, () async {
      final discovery = await _store.read();
      if (discovery == null) return;
      await _stopDiscovery(
        discovery,
        mode: mode,
        timeout: _remaining(deadline),
      );
    });
  }

  Future<void> _stopDiscovery(
    CockpitDaemonDiscovery discovery, {
    required CockpitDaemonShutdownMode mode,
    required Duration timeout,
  }) async {
    final identity = await const CockpitSystemProcessIdentityProbe()
        .readStartIdentity(discovery.processId);
    if (identity != discovery.processStartIdentity) {
      if (await _health(discovery) != null) {
        throw const CockpitDaemonException(
          'discoveryIdentityMismatch',
          'A responsive endpoint does not match the recorded process identity.',
        );
      }
      await _store.deleteIfMatches(discovery);
      return;
    }
    final client = HttpClient();
    try {
      final request = await client.postUrl(
        discovery.endpoint.resolve('/_cockpit/lifecycle'),
      );
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${discovery.bearerToken}',
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(<String, String>{'mode': mode.name}));
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      await response.drain<void>();
      if (response.statusCode != HttpStatus.accepted) {
        throw CockpitDaemonException(
          'shutdownRejected',
          'Daemon rejected ${mode.name} shutdown.',
        );
      }
    } finally {
      client.close(force: true);
    }
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final current = await _store.read();
      if (current == null || !current.identifiesSameInstance(discovery)) {
        return;
      }
      final identity = await const CockpitSystemProcessIdentityProbe()
          .readStartIdentity(discovery.processId);
      if (identity != discovery.processStartIdentity) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw const CockpitDaemonException(
      'shutdownTimeout',
      'Daemon did not exit within the requested timeout.',
    );
  }

  Future<CockpitDaemonDiscovery> restart({
    CockpitAuthorizationMode? authorizationMode,
    Duration? timeout,
  }) {
    final deadline = DateTime.now().toUtc().add(timeout ?? startTimeout);
    return _withLifecycleLock(deadline, () async {
      final discovery = await _store.read();
      final launchAuthorizationMode =
          authorizationMode ??
          discovery?.authorizationMode ??
          CockpitAuthorizationMode.restricted;
      if (discovery != null) {
        await _stopDiscovery(
          discovery,
          mode: CockpitDaemonShutdownMode.drain,
          timeout: _remaining(deadline),
        );
      }
      return _startAndWait(
        launchAuthorizationMode,
        timeout: _remaining(deadline),
      );
    });
  }

  /// Schedules a restart in an independent CLI process.
  ///
  /// A Supervisor client can itself run inside a managed application session.
  /// A direct [restart] stops that session before its caller can launch the
  /// replacement daemon. This detached handoff survives the shutdown and uses
  /// the same Cockpit home and runtime configuration.
  Future<void> scheduleRestart({
    CockpitAuthorizationMode authorizationMode =
        CockpitAuthorizationMode.restricted,
  }) async {
    if (launchFailure case final failure?) throw failure;
    if (executable.isEmpty || daemonArguments.isEmpty) {
      throw const CockpitDaemonException(
        'daemonExecutableMissing',
        'Daemon executable paths are not configured.',
      );
    }
    await Process.start(
      executable,
      <String>[
        ...restartArguments,
        'daemon',
        'restart',
        if (authorizationMode == CockpitAuthorizationMode.yolo) '--yolo',
        '--format',
        'none',
      ],
      environment: <String, String>{
        ...Platform.environment,
        'COCKPIT_HOME': paths.home,
      },
      mode: ProcessStartMode.detached,
    );
  }

  Future<List<String>> logs({int maximumLines = 200}) async {
    if (maximumLines < 1 || maximumLines > 2000) {
      throw ArgumentError.value(maximumLines, 'maximumLines');
    }
    final file = File(paths.daemonLog);
    if (!await file.exists()) return const <String>[];
    return cockpitReadLogTail(file, maximumLines: maximumLines);
  }

  Future<Map<String, Object?>> doctor() async {
    final current = await status();
    final discovery = File(paths.daemonDiscovery);
    final lock = File(paths.daemonLock);
    return <String, Object?>{
      'status': current.toJson(),
      'home': paths.home,
      'discoveryExists': await discovery.exists(),
      'lockExists': await lock.exists(),
      'discoveryCanonical': !await discovery.exists()
          ? true
          : await _isCanonicalRegular(discovery.path),
      'tokenPermissionPolicy': permissionHardener.policy.name,
    };
  }

  Future<CockpitDaemonDiscovery?> _usableDiscovery({
    bool replaceIncompatibleEngine = false,
    void Function(CockpitAuthorizationMode mode)? onEngineReplacement,
    DateTime? deadline,
  }) async {
    CockpitDaemonDiscovery? discovery;
    try {
      discovery = await _store.read();
    } on Object catch (error) {
      throw CockpitDaemonException(
        'discoveryInvalid',
        'Daemon discovery is invalid and cannot be safely cleaned automatically: $error',
      );
    }
    if (discovery == null) return null;
    final identity = await const CockpitSystemProcessIdentityProbe()
        .readStartIdentity(discovery.processId);
    final server = identity == discovery.processStartIdentity
        ? await _healthUntilReady(
            discovery,
            timeout: deadline == null
                ? const Duration(seconds: 8)
                : _boundedRemaining(deadline, const Duration(seconds: 8)),
          )
        : await _health(
            discovery,
            timeout: deadline == null
                ? const Duration(seconds: 2)
                : _boundedRemaining(deadline, const Duration(seconds: 2)),
          );
    if (identity == discovery.processStartIdentity) {
      if (server == null) {
        throw const CockpitDaemonException(
          'activeDaemonUnhealthy',
          'The recorded daemon process is active but its endpoint is unhealthy.',
        );
      }
      if (server.apiVersion.major != requiredApiMajor) {
        throw const CockpitDaemonException(
          'upgradeRequired',
          'An active daemon uses an incompatible API major.',
        );
      }
      if (server.engineVersion != requiredEngineVersion) {
        if (!replaceIncompatibleEngine) return null;
        onEngineReplacement?.call(discovery.authorizationMode);
        await _stopDiscovery(
          discovery,
          mode: CockpitDaemonShutdownMode.drain,
          timeout: deadline == null
              ? const Duration(seconds: 30)
              : _remaining(deadline),
        );
        return null;
      }
      return discovery;
    }
    if (server != null) {
      throw const CockpitDaemonException(
        'discoveryIdentityMismatch',
        'A responsive endpoint does not match the recorded process identity.',
      );
    }
    await _store.deleteIfMatches(discovery);
    return null;
  }

  Future<CockpitServerInfo?> _health(
    CockpitDaemonDiscovery discovery, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .getUrl(discovery.endpoint.resolve('/_cockpit/health'))
          .timeout(timeout);
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${discovery.bearerToken}',
      );
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }
      final bytes = await response
          .fold<List<int>>(<int>[], (all, chunk) {
            if (all.length + chunk.length > 64 * 1024) {
              throw const FormatException('Health response is too large.');
            }
            return all..addAll(chunk);
          })
          .timeout(timeout);
      return CockpitServerInfo.fromJson(jsonDecode(utf8.decode(bytes)));
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<CockpitServerInfo?> _healthUntilReady(
    CockpitDaemonDiscovery discovery, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final deadline = DateTime.now().toUtc().add(timeout);
    while (true) {
      final remaining = deadline.difference(DateTime.now().toUtc());
      if (remaining <= Duration.zero) return null;
      final server = await _health(
        discovery,
        timeout: remaining < const Duration(seconds: 2)
            ? remaining
            : const Duration(seconds: 2),
      );
      if (server != null) return server;
      final delay = deadline.difference(DateTime.now().toUtc());
      if (delay <= Duration.zero) return null;
      await Future<void>.delayed(
        delay < const Duration(milliseconds: 200)
            ? delay
            : const Duration(milliseconds: 200),
      );
    }
  }

  Future<CockpitDaemonDiscovery> _startAndWait(
    CockpitAuthorizationMode authorizationMode, {
    required Duration timeout,
  }) async {
    final processId = await _startProcess(authorizationMode);
    return _waitUntilReady(startedProcessId: processId, timeout: timeout);
  }

  Future<T> _withLifecycleLock<T>(
    DateTime deadline,
    Future<T> Function() action,
  ) => _EnsureLocks.run(
    paths.daemonEnsureLock,
    deadline: deadline,
    action: () async {
      final lock = await File(
        paths.daemonEnsureLock,
      ).open(mode: FileMode.append);
      var acquired = false;
      try {
        await permissionHardener.hardenFile(File(paths.daemonEnsureLock));
        await _acquireLifecycleFileLock(lock, deadline);
        acquired = true;
        return await action();
      } finally {
        try {
          if (acquired) await lock.unlock();
        } finally {
          await lock.close();
        }
      }
    },
  );

  Future<void> _acquireLifecycleFileLock(
    RandomAccessFile lock,
    DateTime deadline,
  ) async {
    while (true) {
      try {
        await lock.lock(FileLock.exclusive);
        return;
      } on FileSystemException catch (error) {
        if (!_isLifecycleLockContention(error)) rethrow;
      }
      final remaining = _remaining(deadline);
      await Future<void>.delayed(
        remaining < const Duration(milliseconds: 50)
            ? remaining
            : const Duration(milliseconds: 50),
      );
    }
  }

  Future<int> _startProcess([
    CockpitAuthorizationMode authorizationMode =
        CockpitAuthorizationMode.restricted,
  ]) async {
    if (launchFailure case final failure?) throw failure;
    if (executable.isEmpty || daemonArguments.isEmpty) {
      throw const CockpitDaemonException(
        'daemonExecutableMissing',
        'Daemon executable paths are not configured.',
      );
    }
    final process = await Process.start(
      executable,
      <String>[
        ...daemonArguments,
        '--home=${paths.home}',
        '--auth=${authorizationMode.name}',
      ],
      environment: <String, String>{
        ...Platform.environment,
        'COCKPIT_HOME': paths.home,
      },
      mode: ProcessStartMode.detached,
    );
    return process.pid;
  }

  Future<CockpitDaemonDiscovery> _waitUntilReady({
    required int startedProcessId,
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    Object? lastError;
    while (DateTime.now().isBefore(deadline)) {
      try {
        final discovery = await _usableDiscovery(deadline: deadline);
        if (discovery != null) return discovery;
      } on Object catch (error) {
        lastError = error;
      }
      final processIdentity = await const CockpitSystemProcessIdentityProbe()
          .readStartIdentity(startedProcessId);
      if (processIdentity == null) {
        throw CockpitDaemonException(
          'daemonStartFailed',
          'Daemon process exited before becoming healthy. Inspect ${paths.daemonLog}.',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw CockpitDaemonException(
      'daemonStartTimeout',
      'Daemon did not publish a healthy discovery record${lastError == null ? '' : ': $lastError'}.',
    );
  }

  Duration _remaining(DateTime deadline) {
    final remaining = deadline.difference(DateTime.now().toUtc());
    if (remaining <= Duration.zero) {
      throw _daemonLifecycleTimeout();
    }
    return remaining;
  }

  Duration _boundedRemaining(DateTime deadline, Duration maximum) {
    final remaining = _remaining(deadline);
    return remaining < maximum ? remaining : maximum;
  }

  Future<bool> _isCanonicalRegular(String path) async {
    try {
      await cockpitValidateCanonicalRegularFile(
        path,
        diagnostic: 'not canonical',
      );
      return true;
    } on FileSystemException {
      return false;
    }
  }
}

const int _cockpitDaemonLogReadChunkBytes = 64 * 1024;
const int _cockpitDaemonLogReadLimitBytes = 2 * 1024 * 1024;
const int _cockpitDaemonLogLineLimitChars = 16 * 1024;

Future<List<String>> cockpitReadLogTail(
  File file, {
  required int maximumLines,
}) async {
  if (maximumLines < 1 || maximumLines > 2000) {
    throw ArgumentError.value(maximumLines, 'maximumLines');
  }
  final handle = await file.open();
  try {
    final length = await handle.length();
    if (length == 0) return const <String>[];
    final chunks = <List<int>>[];
    var offset = length;
    var bytesRead = 0;
    var newlineCount = 0;
    while (offset > 0 &&
        bytesRead < _cockpitDaemonLogReadLimitBytes &&
        newlineCount <= maximumLines) {
      final readSize = math.min(
        _cockpitDaemonLogReadChunkBytes,
        math.min(offset, _cockpitDaemonLogReadLimitBytes - bytesRead),
      );
      offset -= readSize;
      await handle.setPosition(offset);
      final chunk = await handle.read(readSize);
      chunks.add(chunk);
      bytesRead += chunk.length;
      newlineCount += chunk.where((byte) => byte == 0x0a).length;
      if (chunk.length < readSize) break;
    }

    final bytes = <int>[for (final chunk in chunks.reversed) ...chunk];
    var start = 0;
    if (offset > 0) {
      final firstNewline = bytes.indexOf(0x0a);
      start = firstNewline < 0 ? 0 : firstNewline + 1;
    }
    final text = utf8.decode(bytes.sublist(start), allowMalformed: true);
    final lines = const LineSplitter().convert(text);
    final first = math.max(0, lines.length - maximumLines);
    return lines.skip(first).map(_limitDaemonLogLine).toList(growable: false);
  } finally {
    await handle.close();
  }
}

String _limitDaemonLogLine(String line) {
  if (line.length <= _cockpitDaemonLogLineLimitChars) return line;
  return '…[truncated]${line.substring(line.length - _cockpitDaemonLogLineLimitChars)}';
}

abstract final class _EnsureLocks {
  static final Map<String, Future<void>> _tails = <String, Future<void>>{};

  static Future<T> run<T>(
    String path, {
    required DateTime deadline,
    required Future<T> Function() action,
  }) async {
    final previous = _tails[path] ?? Future<void>.value();
    final turn = Completer<void>();
    _tails[path] = turn.future;
    var entered = false;
    try {
      final remaining = deadline.difference(DateTime.now().toUtc());
      if (remaining <= Duration.zero) throw _daemonLifecycleTimeout();
      try {
        await previous.timeout(remaining);
      } on TimeoutException {
        throw _daemonLifecycleTimeout();
      }
      entered = true;
      return await action();
    } finally {
      if (entered) {
        _release(path, turn);
      } else {
        unawaited(previous.whenComplete(() => _release(path, turn)));
      }
    }
  }

  static void _release(String path, Completer<void> turn) {
    if (!turn.isCompleted) turn.complete();
    if (identical(_tails[path], turn.future)) _tails.remove(path);
  }
}

CockpitDaemonException _daemonLifecycleTimeout() =>
    const CockpitDaemonException(
      'daemonTimeout',
      'Daemon lifecycle command exceeded its timeout.',
    );

bool _isLifecycleLockContention(FileSystemException error) {
  final code = error.osError?.errorCode;
  if (code == 11 || code == 13 || code == 33 || code == 35) return true;
  final message = error.osError?.message.toLowerCase() ?? '';
  return message.contains('would block') ||
      message.contains('temporarily unavailable') ||
      message.contains('lock violation');
}
