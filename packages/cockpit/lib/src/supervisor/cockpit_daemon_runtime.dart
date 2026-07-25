import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../foundation/cockpit_home.dart';
import '../foundation/cockpit_ids.dart';
import '../foundation/cockpit_locked_json_store.dart';
import '../foundation/cockpit_permissions.dart';
import '../worker/cockpit_worker_logger.dart';
import 'cockpit_daemon_host.dart';
import 'cockpit_daemon_discovery.dart';
import 'cockpit_supervisor_http_api.dart';
import 'cockpit_supervisor_authorization.dart';
import 'cockpit_supervisor_runtime.dart';

Future<int> runCockpitDaemon(List<String> arguments) async {
  final configuration = _DaemonConfiguration.parse(arguments);
  final platform = Platform.isWindows
      ? CockpitHostPlatform.windows
      : Platform.isMacOS
      ? CockpitHostPlatform.macos
      : CockpitHostPlatform.linux;
  final resolver = CockpitHomeResolver(
    platform: platform,
    environment: <String, String>{
      ...Platform.environment,
      'COCKPIT_HOME': configuration.home,
    },
    userHome:
        Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'] ?? '',
  );
  final hardener = platform == CockpitHostPlatform.windows
      ? const CockpitWindowsAclPermissionHardener()
      : const CockpitPosixPermissionHardener();
  final syncer = CockpitSystemDirectorySyncer(platform);
  final paths = await CockpitHome(
    paths: CockpitHomePaths(configuration.home),
    permissionHardener: hardener,
  ).initialize();
  final logFile = File(paths.daemonLog);
  await logFile.writeAsString('', mode: FileMode.append, flush: true);
  await hardener.hardenFile(logFile);
  final logSink = logFile.openWrite(mode: FileMode.append);
  final logger = CockpitWorkerLogger(stderrSink: logSink);
  final workerEntrypoint = await _workerEntrypoint();
  final authorization = await CockpitSupervisorAuthorizationPolicyStore(
    path: paths.authorizationPolicy,
    permissionHardener: hardener,
    directorySyncer: syncer,
  ).read();
  final runtime = await CockpitSupervisorRuntime.initialize(
    homeResolver: resolver,
    dartExecutable: Platform.resolvedExecutable,
    workerEntrypoint: workerEntrypoint,
    authorization: authorization,
    logger: logger,
  );
  final startedAt = DateTime.now().toUtc();
  final serverInfo = runtime.serverInfo(
    instanceId:
        'instance_${CockpitSecureTokenGenerator().nextToken(byteLength: 16)}',
    startedAt: startedAt,
  );
  final api = CockpitSupervisorHttpApi(
    runtime: runtime,
    serverInfo: serverInfo,
  );
  late final CockpitDaemonHost host;
  host = CockpitDaemonHost(
    paths: paths,
    serverInfo: serverInfo,
    requestHandler: (request) async {
      try {
        await api.handle(request);
      } on Object catch (error, stackTrace) {
        logger.log(
          'error',
          'Supervisor request failed.',
          fields: <String, Object?>{
            'method': request.method,
            'path': request.uri.path,
            'error': '$error',
            'stackTrace': '$stackTrace',
          },
        );
        rethrow;
      }
    },
    shutdownHandler: (mode) => runtime.shutdown(
      cancel: mode != CockpitDaemonShutdownMode.drain,
      emergency: mode == CockpitDaemonShutdownMode.emergency,
    ),
    permissionHardener: hardener,
    directorySyncer: syncer,
  );
  final signals = <StreamSubscription<ProcessSignal>>[];
  try {
    await host.start();
    logger.log(
      'info',
      'Daemon started.',
      fields: <String, Object?>{'pid': pid},
    );
    await logSink.flush();
    if (!Platform.isWindows) {
      for (final signal in <ProcessSignal>[
        ProcessSignal.sigterm,
        ProcessSignal.sigint,
      ]) {
        signals.add(
          signal.watch().listen(
            (_) => unawaited(host.stop(CockpitDaemonShutdownMode.drain)),
          ),
        );
      }
    }
    final foreground = configuration.foregroundWorkspace;
    if (foreground == null) {
      await host.closed;
      return 0;
    }
    return await _runForeground(configuration, host.discovery);
  } finally {
    for (final signal in signals) {
      await signal.cancel();
    }
    await host.stop(CockpitDaemonShutdownMode.drain);
    logger.log(
      'info',
      'Daemon stopped.',
      fields: <String, Object?>{'pid': pid},
    );
    await logSink.flush();
    await logSink.close();
    await hardener.hardenFile(logFile);
  }
}

Future<int> _runForeground(
  _DaemonConfiguration configuration,
  CockpitDaemonDiscovery discovery,
) async {
  final workspacePath = p.normalize(
    await Directory(configuration.foregroundWorkspace!).resolveSymbolicLinks(),
  );
  final rootPath = p.dirname(workspacePath);
  final client = HttpClient();
  try {
    final root = await _request(
      client,
      discovery,
      'POST',
      '/api/v2/roots',
      <String, Object?>{'path': rootPath},
      expected: HttpStatus.created,
    );
    final workspace = await _request(
      client,
      discovery,
      'POST',
      '/api/v2/workspaces/register',
      <String, Object?>{'rootId': root['rootId'], 'path': workspacePath},
      expected: HttpStatus.created,
    );
    final submissionPath = configuration.foregroundSubmission;
    if (submissionPath == null) {
      throw const FormatException(
        'Foreground mode requires --foreground-submission.',
      );
    }
    final raw = jsonDecode(await File(submissionPath).readAsString());
    if (raw is! Map<Object?, Object?> ||
        raw.keys.any((key) => key is! String)) {
      throw const FormatException(
        'Foreground submission must be a JSON object.',
      );
    }
    final submission = Map<String, Object?>.from(raw)
      ..['workspaceId'] = workspace['workspaceId'];
    final accepted = await _request(
      client,
      discovery,
      'POST',
      '/api/v2/workspaces/${workspace['workspaceId']}/runs',
      submission,
      expected: HttpStatus.accepted,
    );
    while (true) {
      final run = await _request(
        client,
        discovery,
        'GET',
        '/api/v2/runs/${accepted['runId']}',
        null,
        expected: HttpStatus.ok,
      );
      if (run['lifecycle'] == 'completed') {
        return switch (run['outcome']) {
          'passed' => 0,
          'cancelled' || 'interrupted' => 2,
          _ => 1,
        };
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, Object?>> _request(
  HttpClient client,
  CockpitDaemonDiscovery discovery,
  String method,
  String path,
  Map<String, Object?>? body, {
  required int expected,
}) async {
  final request = await client.openUrl(
    method,
    discovery.endpoint.resolve(path),
  );
  request.headers
    ..set(HttpHeaders.authorizationHeader, 'Bearer ${discovery.bearerToken}')
    ..set('Cockpit-API-Version', '2.0');
  if (body != null) {
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
  }
  final response = await request.close();
  final bytes = await response.fold<List<int>>(
    <int>[],
    (all, chunk) => all..addAll(chunk),
  );
  final value = jsonDecode(utf8.decode(bytes));
  if (response.statusCode != expected || value is! Map<Object?, Object?>) {
    throw StateError(
      'Foreground API request failed with ${response.statusCode}.',
    );
  }
  return Map<String, Object?>.from(value);
}

Future<String> _workerEntrypoint() async {
  final library = await Isolate.resolvePackageUri(
    Uri.parse('package:cockpit/cockpit.dart'),
  );
  if (library == null) throw StateError('Unable to resolve cockpit package.');
  return p.join(
    p.dirname(p.dirname(library.toFilePath())),
    'bin',
    'cockpit_worker.dart',
  );
}

final class _DaemonConfiguration {
  const _DaemonConfiguration({
    required this.home,
    this.foregroundWorkspace,
    this.foregroundSubmission,
  });

  final String home;
  final String? foregroundWorkspace;
  final String? foregroundSubmission;

  static _DaemonConfiguration parse(List<String> arguments) {
    final values = <String, String>{};
    for (final argument in arguments) {
      final separator = argument.indexOf('=');
      if (!argument.startsWith('--') || separator < 3) {
        throw FormatException('Invalid cockpitd argument $argument.');
      }
      final name = argument.substring(2, separator);
      final value = argument.substring(separator + 1);
      if (!const {
            'home',
            'foreground-workspace',
            'foreground-submission',
          }.contains(name) ||
          value.isEmpty ||
          values.containsKey(name)) {
        throw FormatException('Invalid cockpitd option $name.');
      }
      values[name] = value;
    }
    final home = values['home'];
    if (home == null || !p.isAbsolute(home)) {
      throw const FormatException('--home must be an absolute path.');
    }
    final workspace = values['foreground-workspace'];
    final submission = values['foreground-submission'];
    if ((workspace == null) != (submission == null) ||
        workspace != null &&
            (!p.isAbsolute(workspace) || !p.isAbsolute(submission!))) {
      throw const FormatException(
        'Foreground paths must be paired and absolute.',
      );
    }
    return _DaemonConfiguration(
      home: p.normalize(home),
      foregroundWorkspace: workspace == null ? null : p.normalize(workspace),
      foregroundSubmission: submission == null ? null : p.normalize(submission),
    );
  }
}
