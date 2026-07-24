import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

import '../application/cockpit_compact_json.dart';
import '../foundation/cockpit_home.dart';
import '../foundation/cockpit_locked_json_store.dart';
import '../supervisor/cockpit_supervisor_authorization.dart';
import '../supervisor/cockpit_supervisor_api_client.dart';

const int cockpitSuccessExitCode = 0;
const int cockpitUsageExitCode = 64;
const int cockpitDataExitCode = 65;
const int cockpitNoInputExitCode = 66;
const int cockpitUnavailableExitCode = 69;
const int cockpitPermissionExitCode = 77;
const int cockpitTemporaryExitCode = 75;

typedef CockpitSupervisorClientProvider =
    Future<CockpitSupervisorApiClient> Function();
typedef CockpitAuthorizationPolicyStoreProvider =
    Future<CockpitSupervisorAuthorizationPolicyStore> Function();

typedef CockpitCliAction = Future<int> Function(ArgResults arguments);

final class CockpitLeafCommand extends Command<int> {
  CockpitLeafCommand({
    required this.name,
    required this.description,
    required CockpitCliAction action,
    void Function(ArgParser parser)? configure,
  }) : _action = action {
    configure?.call(argParser);
  }

  @override
  final String name;

  @override
  final String description;

  final CockpitCliAction _action;

  @override
  Future<int> run() => _action(argResults!);
}

final class CockpitCliRuntime {
  CockpitCliRuntime({
    CockpitSupervisorClientProvider? clientProvider,
    CockpitAuthorizationPolicyStoreProvider? authorizationPolicyStoreProvider,
    StringSink? stdoutSink,
    StringSink? stderrSink,
    String? workingDirectory,
  }) : _clientProvider =
           clientProvider ?? (() => createCockpitSupervisorApiClient()),
       _authorizationPolicyStoreProvider =
           authorizationPolicyStoreProvider ?? _systemAuthorizationPolicyStore,
       stdoutSink = stdoutSink ?? stdout,
       stderrSink = stderrSink ?? stderr,
       workingDirectory = workingDirectory ?? Directory.current.path;

  final CockpitSupervisorClientProvider _clientProvider;
  final CockpitAuthorizationPolicyStoreProvider
  _authorizationPolicyStoreProvider;
  final StringSink stdoutSink;
  final StringSink stderrSink;
  final String workingDirectory;
  Future<CockpitSupervisorApiClient>? _client;
  Future<CockpitSupervisorAuthorizationPolicyStore>? _authorizationPolicyStore;

  Future<CockpitSupervisorApiClient> client() => _client ??= _clientProvider();

  Future<CockpitSupervisorAuthorizationPolicyStore>
  authorizationPolicyStore() =>
      _authorizationPolicyStore ??= _authorizationPolicyStoreProvider();

  CockpitSupervisorAuthorizationPolicy authorizationPolicyFile(String path) {
    final resolved = p.normalize(
      p.isAbsolute(path) ? path : p.join(workingDirectory, path),
    );
    final file = File(resolved);
    if (!file.existsSync()) {
      throw FileSystemException(
        'Authorization policy file was not found.',
        resolved,
      );
    }
    if (file.lengthSync() > 1024 * 1024) {
      throw const FormatException('Authorization policy exceeds 1 MiB.');
    }
    return CockpitSupervisorAuthorizationPolicy.fromJson(
      jsonDecode(file.readAsStringSync()),
    );
  }

  void success(Object? data) {
    final value = <String, Object?>{'ok': true, 'data': data};
    final text = cockpitCompactJsonText(value);
    if (utf8.encode(text).length > cockpitSupervisorMaximumResponseBytes) {
      throw const CockpitSupervisorClientException(
        code: 'outputTooLarge',
        message: 'CLI output exceeds 1 MiB.',
      );
    }
    stdoutSink.writeln(text);
  }

  void error({
    required String code,
    required String message,
    bool retryable = false,
    String? category,
    String? responsibleLayer,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    stderrSink.writeln(
      cockpitCompactJsonText(<String, Object?>{
        'ok': false,
        'error': <String, Object?>{
          'code': code,
          'message': message.length <= 4096
              ? message
              : '${message.substring(0, 4093)}...',
          'retryable': retryable,
          'category': ?category,
          'responsibleLayer': ?responsibleLayer,
          if (details.isNotEmpty) 'details': details,
        },
      }),
    );
  }

  Future<String> workspaceId(String? explicit) async {
    final workspaces = await (await client()).workspaces();
    if (explicit != null) {
      final matches = workspaces.where(
        (workspace) => workspace.workspaceId == explicit,
      );
      if (matches.length != 1 ||
          matches.single.state != CockpitWorkspaceState.active) {
        throw CockpitSupervisorClientException(
          code: 'workspaceNotFound',
          message: 'Active workspace $explicit was not found.',
        );
      }
      return explicit;
    }
    final canonicalCwd = p.normalize(
      await Directory(workingDirectory).resolveSymbolicLinks(),
    );
    final matches = workspaces.where((workspace) {
      if (workspace.state != CockpitWorkspaceState.active) return false;
      final relative = p.relative(canonicalCwd, from: workspace.canonicalPath);
      return relative == '.' ||
          relative != '..' &&
              !relative.startsWith('../') &&
              p.isRelative(relative);
    }).toList();
    if (matches.length != 1) {
      throw CockpitSupervisorClientException(
        code: matches.isEmpty ? 'workspaceNotFound' : 'workspaceAmbiguous',
        message: matches.isEmpty
            ? 'Current directory is not inside a registered workspace.'
            : 'Current directory matches multiple workspaces; pass --workspace-id.',
      );
    }
    return matches.single.workspaceId;
  }

  Map<String, Object?> jsonObject(String? inline, String? file) {
    if (inline != null && file != null) {
      throw const FormatException(
        'Use only one of --input-json and --input-file.',
      );
    }
    final source =
        inline ?? (file == null ? '{}' : File(file).readAsStringSync());
    if (utf8.encode(source).length > cockpitSupervisorMaximumResponseBytes) {
      throw const FormatException('JSON input exceeds 1 MiB.');
    }
    final value = jsonDecode(source);
    if (value is! Map<Object?, Object?> ||
        value.keys.any((key) => key is! String)) {
      throw const FormatException('JSON input must be an object.');
    }
    return Map<String, Object?>.from(value);
  }
}

Future<CockpitSupervisorAuthorizationPolicyStore>
_systemAuthorizationPolicyStore() async {
  final resolver = CockpitHomeResolver.system();
  final home = CockpitHome.system();
  final paths = await home.initialize();
  return CockpitSupervisorAuthorizationPolicyStore(
    path: paths.authorizationPolicy,
    permissionHardener: home.permissionHardener,
    directorySyncer: CockpitSystemDirectorySyncer(resolver.platform),
  );
}

int cockpitExitCodeFor(CockpitApiError error) => switch (error.code) {
  CockpitErrorCode.authenticationRequired ||
  CockpitErrorCode.authorizationDenied => cockpitPermissionExitCode,
  CockpitErrorCode.notFound => cockpitNoInputExitCode,
  _ when error.retryable => cockpitTemporaryExitCode,
  _ => cockpitDataExitCode,
};
