import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../foundation/cockpit_home.dart';
import '../foundation/cockpit_ids.dart';
import '../foundation/cockpit_locked_json_store.dart';
import '../foundation/cockpit_permissions.dart';
import 'cockpit_daemon_discovery.dart';

enum CockpitDaemonShutdownMode { drain, cancel, emergency }

typedef CockpitDaemonRequestHandler =
    Future<void> Function(HttpRequest request);
typedef CockpitDaemonShutdownHandler =
    Future<void> Function(CockpitDaemonShutdownMode mode);

final class CockpitDaemonAlreadyRunningException implements Exception {
  const CockpitDaemonAlreadyRunningException();

  @override
  String toString() => 'CockpitDaemonAlreadyRunningException';
}

final class CockpitDaemonHost {
  CockpitDaemonHost({
    required this.paths,
    required this.serverInfo,
    required this.requestHandler,
    required this.shutdownHandler,
    required this.permissionHardener,
    required this.directorySyncer,
    CockpitTokenGenerator? tokenGenerator,
  }) : _tokenGenerator = tokenGenerator ?? CockpitSecureTokenGenerator();

  final CockpitHomePaths paths;
  final CockpitServerInfo serverInfo;
  final CockpitDaemonRequestHandler requestHandler;
  final CockpitDaemonShutdownHandler shutdownHandler;
  final CockpitPermissionHardener permissionHardener;
  final CockpitDirectorySyncer directorySyncer;
  final CockpitTokenGenerator _tokenGenerator;
  final Completer<void> _closed = Completer<void>();
  HttpServer? _server;
  RandomAccessFile? _daemonLock;
  CockpitDaemonDiscovery? _discovery;
  bool _stopping = false;
  Future<void>? _stopOperation;

  CockpitDaemonDiscovery get discovery =>
      _discovery ?? (throw StateError('Daemon host has not started.'));
  Future<void> get closed => _closed.future;

  Future<CockpitDaemonDiscovery> start() async {
    if (_server != null) throw StateError('Daemon host is already started.');
    final lockFile = File(paths.daemonLock);
    final daemonLock = await lockFile.open(mode: FileMode.append);
    try {
      await permissionHardener.hardenFile(lockFile);
    } on Object {
      await daemonLock.close();
      rethrow;
    }
    try {
      await daemonLock.lock(FileLock.exclusive);
    } on FileSystemException {
      await daemonLock.close();
      throw const CockpitDaemonAlreadyRunningException();
    }
    _daemonLock = daemonLock;
    late final String identity;
    HttpServer? server;
    try {
      identity = await const CockpitSystemProcessIdentityProbe().current();
      server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
        shared: false,
      );
    } on Object {
      await _releaseDaemonLock();
      rethrow;
    }
    final discovery = CockpitDaemonDiscovery(
      instanceId: serverInfo.instanceId,
      processId: pid,
      processStartIdentity: identity,
      endpoint: Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
      ),
      bearerToken: _tokenGenerator.nextToken(),
      apiMajor: serverInfo.apiVersion.major,
      apiMinor: serverInfo.apiVersion.minor,
      engineVersion: serverInfo.engineVersion,
      startedAt: serverInfo.startedAt,
    );
    _server = server;
    _discovery = discovery;
    try {
      await CockpitDaemonDiscoveryStore(
        paths: paths,
        permissionHardener: permissionHardener,
        directorySyncer: directorySyncer,
      ).write(discovery);
    } on Object {
      await server.close(force: true);
      _server = null;
      _discovery = null;
      await _releaseDaemonLock();
      rethrow;
    }
    server.listen(
      _handle,
      onError: (_) {},
      onDone: () {
        if (!_stopping) {
          unawaited(stop(CockpitDaemonShutdownMode.drain));
        }
      },
      cancelOnError: false,
    );
    return discovery;
  }

  Future<void> stop(CockpitDaemonShutdownMode mode) {
    final existing = _stopOperation;
    if (existing != null) return existing;
    final operation = _stop(mode);
    _stopOperation = operation;
    return operation;
  }

  Future<void> _stop(CockpitDaemonShutdownMode mode) async {
    _stopping = true;
    try {
      await shutdownHandler(mode);
    } finally {
      try {
        await _server?.close(
          force: mode == CockpitDaemonShutdownMode.emergency,
        );
        final discovery = _discovery;
        if (discovery != null) {
          await CockpitDaemonDiscoveryStore(
            paths: paths,
            permissionHardener: permissionHardener,
            directorySyncer: directorySyncer,
          ).deleteIfMatches(discovery);
        }
      } finally {
        await _releaseDaemonLock();
        if (!_closed.isCompleted) _closed.complete();
      }
    }
  }

  Future<void> _releaseDaemonLock() async {
    final lock = _daemonLock;
    _daemonLock = null;
    if (lock == null) return;
    try {
      await lock.unlock();
    } finally {
      await lock.close();
    }
  }

  Future<void> _handle(HttpRequest request) async {
    request.response.headers.set('Cache-Control', 'no-store');
    request.response.headers.set('X-Content-Type-Options', 'nosniff');
    try {
      if (!request.connectionInfo!.remoteAddress.isLoopback) {
        return _error(request, HttpStatus.forbidden, 'loopbackRequired');
      }
      if (request.headers.value('origin') != null ||
          request.method == 'OPTIONS') {
        return _error(request, HttpStatus.forbidden, 'corsDenied');
      }
      final authorization = request.headers.value(
        HttpHeaders.authorizationHeader,
      );
      if (authorization != 'Bearer ${discovery.bearerToken}') {
        request.response.headers.set(
          HttpHeaders.wwwAuthenticateHeader,
          'Bearer',
        );
        return _error(request, HttpStatus.unauthorized, 'unauthorized');
      }
      if (request.uri.path == '/_cockpit/health') {
        if (request.method != 'GET') {
          return _error(
            request,
            HttpStatus.methodNotAllowed,
            'methodNotAllowed',
          );
        }
        return _json(request, HttpStatus.ok, serverInfo.toJson());
      }
      if (request.uri.path == '/_cockpit/lifecycle') {
        if (request.method != 'POST') {
          return _error(
            request,
            HttpStatus.methodNotAllowed,
            'methodNotAllowed',
          );
        }
        final value = await _readLifecycleBody(request);
        final mode = switch (value) {
          'drain' => CockpitDaemonShutdownMode.drain,
          'cancel' => CockpitDaemonShutdownMode.cancel,
          'emergency' => CockpitDaemonShutdownMode.emergency,
          _ => throw const FormatException('Invalid shutdown mode.'),
        };
        await _json(request, HttpStatus.accepted, <String, Object?>{
          'accepted': true,
          'mode': mode.name,
        });
        unawaited(stop(mode));
        return;
      }
      if (_stopping) {
        return _error(request, HttpStatus.serviceUnavailable, 'daemonDraining');
      }
      await requestHandler(request);
    } on FormatException catch (error) {
      await _error(
        request,
        HttpStatus.badRequest,
        'invalidRequest',
        message: error.message,
      );
    } on Object {
      await _error(request, HttpStatus.internalServerError, 'internalError');
    }
  }

  Future<String> _readLifecycleBody(HttpRequest request) async {
    if (request.headers.contentType?.mimeType != ContentType.json.mimeType) {
      throw const FormatException('Content-Type must be application/json.');
    }
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
      if (bytes.length > 4096) {
        throw const FormatException('Lifecycle body is too large.');
      }
    }
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<Object?, Object?> ||
        value.length != 1 ||
        value['mode'] is! String) {
      throw const FormatException('Invalid lifecycle request.');
    }
    return value['mode']! as String;
  }

  Future<void> _json(HttpRequest request, int status, Object? body) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  Future<void> _error(
    HttpRequest request,
    int status,
    String code, {
    String? message,
  }) => _json(request, status, <String, Object?>{
    'error': <String, Object?>{
      'code': code,
      'category': status >= 500 ? 'internal' : 'invalidInput',
      'message': message ?? code,
      'retryable': status >= 500,
      'responsibleLayer': 'supervisor',
      'redactedDetails': <String, Object?>{},
    },
  });
}
