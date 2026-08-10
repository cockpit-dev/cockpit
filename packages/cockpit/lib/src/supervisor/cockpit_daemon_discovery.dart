import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../foundation/cockpit_home.dart';
import '../foundation/cockpit_locked_json_store.dart';
import '../foundation/cockpit_permissions.dart';

const cockpitDaemonDiscoverySchema = 'cockpit.daemon/v3';

final class CockpitDaemonDiscovery {
  CockpitDaemonDiscovery({
    this.schemaVersion = cockpitDaemonDiscoverySchema,
    required this.instanceId,
    required this.processId,
    required this.processStartIdentity,
    required this.endpoint,
    required this.bearerToken,
    required this.apiMajor,
    required this.apiMinor,
    required this.engineVersion,
    required this.startedAt,
    this.authorizationMode = CockpitAuthorizationMode.restricted,
  }) {
    if (schemaVersion != cockpitDaemonDiscoverySchema ||
        !_identifier.hasMatch(instanceId) ||
        processId <= 1 ||
        processStartIdentity.trim().isEmpty ||
        processStartIdentity.length > 512 ||
        endpoint.scheme != 'http' ||
        endpoint.host != InternetAddress.loopbackIPv4.address ||
        endpoint.port < 1 ||
        endpoint.port > 65535 ||
        endpoint.path.isNotEmpty && endpoint.path != '/' ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        bearerToken.length < 32 ||
        bearerToken.length > 128 ||
        !_token.hasMatch(bearerToken) ||
        apiMajor < 0 ||
        apiMinor < 0 ||
        engineVersion.trim().isEmpty ||
        engineVersion.length > 128 ||
        !startedAt.isUtc) {
      throw const FormatException('Invalid Cockpit daemon discovery data.');
    }
  }

  final String schemaVersion;
  final String instanceId;
  final int processId;
  final String processStartIdentity;
  final Uri endpoint;
  final String bearerToken;
  final int apiMajor;
  final int apiMinor;
  final String engineVersion;
  final DateTime startedAt;
  final CockpitAuthorizationMode authorizationMode;

  bool identifiesSameInstance(CockpitDaemonDiscovery other) =>
      processId == other.processId &&
      processStartIdentity == other.processStartIdentity &&
      instanceId == other.instanceId;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'instanceId': instanceId,
    'processId': processId,
    'processStartIdentity': processStartIdentity,
    'endpoint': endpoint.toString(),
    'bearerToken': bearerToken,
    'apiVersion': <String, int>{'major': apiMajor, 'minor': apiMinor},
    'engineVersion': engineVersion,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'auth': authorizationMode.name,
  };

  factory CockpitDaemonDiscovery.fromJson(Object? value) {
    if (value is! Map<Object?, Object?> ||
        value.keys.any((key) => key is! String)) {
      throw const FormatException('Daemon discovery must be an object.');
    }
    final json = value.cast<String, Object?>();
    const fields = <String>{
      'schemaVersion',
      'instanceId',
      'processId',
      'processStartIdentity',
      'endpoint',
      'bearerToken',
      'apiVersion',
      'engineVersion',
      'startedAt',
      'auth',
    };
    if (json.keys.toSet().difference(fields).isNotEmpty ||
        fields.difference(json.keys.toSet()).isNotEmpty ||
        json['apiVersion'] is! Map<Object?, Object?>) {
      throw const FormatException('Daemon discovery fields are invalid.');
    }
    final api = (json['apiVersion']! as Map<Object?, Object?>);
    if (api.length != 2 ||
        api['major'] is! int ||
        api['minor'] is! int ||
        json['schemaVersion'] is! String ||
        json['instanceId'] is! String ||
        json['processId'] is! int ||
        json['processStartIdentity'] is! String ||
        json['endpoint'] is! String ||
        json['bearerToken'] is! String ||
        json['engineVersion'] is! String ||
        json['startedAt'] is! String) {
      throw const FormatException('Daemon discovery value types are invalid.');
    }
    final endpoint = Uri.tryParse(json['endpoint']! as String);
    final startedAt = DateTime.tryParse(json['startedAt']! as String);
    final authorizationMode = json['auth'] is String
        ? CockpitAuthorizationMode.values
              .where((value) => value.name == json['auth'])
              .firstOrNull
        : null;
    if (endpoint == null ||
        startedAt == null ||
        !startedAt.isUtc ||
        authorizationMode == null) {
      throw const FormatException('Daemon discovery values are invalid.');
    }
    return CockpitDaemonDiscovery(
      schemaVersion: json['schemaVersion']! as String,
      instanceId: json['instanceId']! as String,
      processId: json['processId']! as int,
      processStartIdentity: json['processStartIdentity']! as String,
      endpoint: endpoint,
      bearerToken: json['bearerToken']! as String,
      apiMajor: api['major']! as int,
      apiMinor: api['minor']! as int,
      engineVersion: json['engineVersion']! as String,
      startedAt: startedAt,
      authorizationMode: authorizationMode,
    );
  }

  static final RegExp _identifier = RegExp(r'^[A-Za-z][A-Za-z0-9._-]{0,127}$');
  static final RegExp _token = RegExp(r'^[A-Za-z0-9_-]+$');
}

final class CockpitDaemonDiscoveryStore {
  CockpitDaemonDiscoveryStore({
    required this.paths,
    required this.permissionHardener,
    required this.directorySyncer,
  }) : _atomicFile = CockpitAtomicJsonFile(
         permissionHardener: permissionHardener,
         directorySyncer: directorySyncer,
       );

  final CockpitHomePaths paths;
  final CockpitPermissionHardener permissionHardener;
  final CockpitDirectorySyncer directorySyncer;
  final CockpitAtomicJsonFile _atomicFile;

  Future<CockpitDaemonDiscovery?> read() async {
    final file = File(paths.daemonDiscovery);
    for (var attempt = 0; attempt < 2; attempt += 1) {
      try {
        return await _readExisting(file);
      } on FileSystemException {
        final currentType = await FileSystemEntity.type(
          file.path,
          followLinks: false,
        );
        if (currentType == FileSystemEntityType.notFound) return null;
        if (attempt != 0 || currentType != FileSystemEntityType.file) rethrow;
      }
    }
    throw StateError('Unreachable daemon discovery read state.');
  }

  Future<CockpitDaemonDiscovery?> _readExisting(File file) async {
    if (!await file.exists()) return null;
    await cockpitValidateCanonicalRegularFile(
      file.path,
      diagnostic: 'Daemon discovery is not a canonical regular file.',
    );
    final stat = await file.stat();
    if (stat.type == FileSystemEntityType.notFound) return null;
    if (!Platform.isWindows && stat.mode & 0x3f != 0) {
      throw const FormatException(
        'Daemon discovery permissions are not current-user only.',
      );
    }
    if (await file.length() > 64 * 1024) {
      throw const FormatException('Daemon discovery exceeds its size bound.');
    }
    return CockpitDaemonDiscovery.fromJson(
      jsonDecode(await file.readAsString()),
    );
  }

  Future<void> write(CockpitDaemonDiscovery discovery) => _atomicFile.write(
    paths.daemonDiscovery,
    discovery.toJson(),
    maximumBytes: 64 * 1024,
  );

  Future<void> deleteIfMatches(CockpitDaemonDiscovery discovery) async {
    final current = await read();
    if (current == null || !current.identifiesSameInstance(discovery)) {
      return;
    }
    final file = File(paths.daemonDiscovery);
    await file.delete();
    await directorySyncer.sync(file.parent.path);
  }
}

abstract interface class CockpitProcessIdentityProbe {
  Future<String?> readStartIdentity(int processId);
}

final class CockpitSystemProcessIdentityProbe
    implements CockpitProcessIdentityProbe {
  const CockpitSystemProcessIdentityProbe();

  @override
  Future<String?> readStartIdentity(int processId) async {
    if (processId <= 1) return null;
    final result = Platform.isWindows
        ? await Process.run(
            'powershell.exe',
            <String>[
              '-NoProfile',
              '-NonInteractive',
              '-Command',
              r'$p = Get-Process -Id ([int]$env:COCKPIT_PROCESS_ID) -ErrorAction SilentlyContinue; if ($p) { $p.StartTime.ToUniversalTime().ToFileTimeUtc() }',
            ],
            environment: <String, String>{'COCKPIT_PROCESS_ID': '$processId'},
          )
        : await Process.run(
            'ps',
            <String>['-o', 'lstart=', '-p', '$processId'],
            environment: const <String, String>{'LANG': 'C', 'LC_ALL': 'C'},
          );
    if (result.exitCode != 0) return null;
    final value = '${result.stdout}'.trim();
    return value.isEmpty || value.length > 512 ? null : value;
  }

  Future<String> current() async {
    final identity = await readStartIdentity(pid);
    if (identity == null) {
      throw StateError('Unable to determine daemon process start identity.');
    }
    return identity;
  }
}
