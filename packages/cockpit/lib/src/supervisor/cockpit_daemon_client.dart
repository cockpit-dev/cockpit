import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
    this.diagnostic,
  });

  final bool running;
  final bool healthy;
  final int? processId;
  final Uri? endpoint;
  final String? engineVersion;
  final CockpitApiVersion? apiVersion;
  final DateTime? startedAt;
  final String? diagnostic;

  Map<String, Object?> toJson() => <String, Object?>{
    'running': running,
    'healthy': healthy,
    if (processId != null) 'processId': processId,
    if (endpoint != null) 'endpoint': endpoint.toString(),
    if (engineVersion != null) 'engineVersion': engineVersion,
    if (apiVersion != null) 'apiVersion': apiVersion!.toJson(),
    if (startedAt != null) 'startedAt': startedAt!.toUtc().toIso8601String(),
    if (diagnostic != null) 'diagnostic': diagnostic,
  };
}

final class CockpitDaemonLifecycleClient {
  CockpitDaemonLifecycleClient({
    required this.paths,
    required this.dartExecutable,
    required this.daemonEntrypoint,
    required this.permissionHardener,
    required this.directorySyncer,
    this.requiredApiMajor = 2,
    this.startTimeout = const Duration(minutes: 2),
  });

  final CockpitHomePaths paths;
  final String dartExecutable;
  final String daemonEntrypoint;
  final CockpitPermissionHardener permissionHardener;
  final CockpitDirectorySyncer directorySyncer;
  final int requiredApiMajor;
  final Duration startTimeout;

  CockpitDaemonDiscoveryStore get _store => CockpitDaemonDiscoveryStore(
    paths: paths,
    permissionHardener: permissionHardener,
    directorySyncer: directorySyncer,
  );

  Future<CockpitDaemonDiscovery> ensure() =>
      _EnsureLocks.run(paths.daemonEnsureLock, () async {
        final first = await _usableDiscovery();
        if (first != null) return first;
        final lock = await File(
          paths.daemonEnsureLock,
        ).open(mode: FileMode.append);
        try {
          await permissionHardener.hardenFile(File(paths.daemonEnsureLock));
          await lock.lock(FileLock.blockingExclusive);
          final rechecked = await _usableDiscovery();
          if (rechecked != null) return rechecked;
          await _startProcess();
          return _waitUntilReady();
        } finally {
          try {
            await lock.unlock();
          } finally {
            await lock.close();
          }
        }
      });

  Future<CockpitDaemonDiscovery> start() => ensure();

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
      diagnostic: !running
          ? 'staleDiscovery'
          : server == null
          ? 'healthUnavailable'
          : server.apiVersion.major != requiredApiMajor
          ? 'upgradeRequired'
          : null,
    );
  }

  Future<void> stop({
    CockpitDaemonShutdownMode mode = CockpitDaemonShutdownMode.drain,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final discovery = await _store.read();
    if (discovery == null) return;
    final request = await HttpClient().postUrl(
      discovery.endpoint.resolve('/_cockpit/lifecycle'),
    );
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer ${discovery.bearerToken}',
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(<String, String>{'mode': mode.name}));
    final response = await request.close().timeout(const Duration(seconds: 5));
    await response.drain<void>();
    if (response.statusCode != HttpStatus.accepted) {
      throw CockpitDaemonException(
        'shutdownRejected',
        'Daemon rejected ${mode.name} shutdown.',
      );
    }
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
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

  Future<CockpitDaemonDiscovery> restart() async {
    await stop();
    return ensure();
  }

  Future<List<String>> logs({int maximumLines = 200}) async {
    if (maximumLines < 1 || maximumLines > 2000) {
      throw ArgumentError.value(maximumLines, 'maximumLines');
    }
    final file = File(paths.daemonLog);
    if (!await file.exists()) return const <String>[];
    if (await file.length() > 8 * 1024 * 1024) {
      throw const CockpitDaemonException(
        'logTooLarge',
        'Daemon log exceeds its read bound.',
      );
    }
    final lines = const LineSplitter().convert(await file.readAsString());
    return lines
        .skip(lines.length > maximumLines ? lines.length - maximumLines : 0)
        .toList();
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

  Future<CockpitDaemonDiscovery?> _usableDiscovery() async {
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
    final server = await _health(discovery);
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

  Future<CockpitServerInfo?> _health(CockpitDaemonDiscovery discovery) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    try {
      final request = await client
          .getUrl(discovery.endpoint.resolve('/_cockpit/health'))
          .timeout(const Duration(seconds: 1));
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${discovery.bearerToken}',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 1),
      );
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }
      final bytes = await response.fold<List<int>>(<int>[], (all, chunk) {
        if (all.length + chunk.length > 64 * 1024) {
          throw const FormatException('Health response is too large.');
        }
        return all..addAll(chunk);
      });
      return CockpitServerInfo.fromJson(jsonDecode(utf8.decode(bytes)));
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _startProcess() async {
    if (dartExecutable.isEmpty || daemonEntrypoint.isEmpty) {
      throw const CockpitDaemonException(
        'daemonExecutableMissing',
        'Daemon executable paths are not configured.',
      );
    }
    await Process.start(
      dartExecutable,
      <String>[daemonEntrypoint, '--home=${paths.home}'],
      environment: <String, String>{
        ...Platform.environment,
        'COCKPIT_HOME': paths.home,
      },
      mode: ProcessStartMode.detached,
    );
  }

  Future<CockpitDaemonDiscovery> _waitUntilReady() async {
    final deadline = DateTime.now().add(startTimeout);
    Object? lastError;
    while (DateTime.now().isBefore(deadline)) {
      try {
        final discovery = await _usableDiscovery();
        if (discovery != null) return discovery;
      } on Object catch (error) {
        lastError = error;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw CockpitDaemonException(
      'daemonStartTimeout',
      'Daemon did not publish a healthy discovery record${lastError == null ? '' : ': $lastError'}.',
    );
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

abstract final class _EnsureLocks {
  static final Map<String, Future<void>> _tails = <String, Future<void>>{};

  static Future<T> run<T>(String path, Future<T> Function() action) async {
    final previous = _tails[path] ?? Future<void>.value();
    final turn = Completer<void>();
    _tails[path] = turn.future;
    await previous;
    try {
      return await action();
    } finally {
      turn.complete();
      if (identical(_tails[path], turn.future)) _tails.remove(path);
    }
  }
}
