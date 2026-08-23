import 'dart:io';

import 'package:path/path.dart' as p;

import '../foundation/cockpit_home.dart';
import '../foundation/cockpit_ids.dart';
import 'cockpit_cli_runtime.dart';
import 'cockpit_cli_session_handles.dart';
import 'cockpit_dev_runtime.dart';

final class CockpitDevNetworkService {
  CockpitDevNetworkService(this.runtime, this.dev);

  final CockpitCliRuntime runtime;
  final CockpitDevRuntime dev;

  Future<int> read({
    required String? sessionReference,
    required String? requestId,
    required String? before,
    required int limit,
    required bool failuresOnly,
    required String? method,
    required String? uriContains,
    required String? body,
    required bool raw,
  }) async {
    var session = await runtime.resolveDevelopmentSession(sessionReference);
    final read = await dev
        .invokeRead(session, 'network.read', <String, Object?>{
          'includeEntries': true,
          'maxEntries': requestId == null ? limit : 1,
          'maxEndpointSummaries': limit.clamp(1, 12),
          'id': ?requestId,
          'before': ?before,
          'method': ?method,
          'uriContains': ?uriContains,
          if (failuresOnly) 'onlyFailures': true,
        }, accepts: dev.diagnosticReadSucceeded);
    final unavailable = read.unavailable;
    if (unavailable != null) {
      return dev.writeUnavailable(action: 'network', resolution: unavailable);
    }
    session = read.session;
    final network = read.result!;
    if (!dev.diagnosticReadSucceeded(network)) {
      return dev.writeOperation(
        action: 'network',
        session: session,
        result: network,
        state: network.output,
        changed: 'none',
      );
    }
    final networkState = Map<String, Object?>.from(
      network.output ?? const <String, Object?>{},
    );
    if (requestId != null && !_hasOneEntry(networkState, requestId)) {
      return dev.writeEnvelope(
        action: 'network',
        session: session,
        ok: false,
        state: networkState,
        changed: 'none',
        errors: <Object?>[
          <String, Object?>{
            'code': 'networkRequestNotFound',
            'message': 'Network request $requestId is not retained.',
          },
        ],
        next:
            'cockpit dev network --before $requestId --session ${session.handleId}',
        failureExitCode: cockpitDataExitCode,
      );
    }
    if (body == null) {
      if (!dev.operationSucceeded(network)) {
        return dev.writeOperation(
          action: 'network',
          session: session,
          result: network,
          state: networkState,
          changed: 'none',
        );
      }
      return dev.writeEnvelope(
        action: 'network',
        session: session,
        ok: true,
        state: networkState,
        changed: read.changed,
      );
    }

    final captured = await dev
        .invoke(session, 'network.body', <String, Object?>{
          'sessionId': session.sessionId,
          'requestId': requestId,
          'body': body,
          if (raw) 'raw': true,
        });
    if (!dev.operationSucceeded(captured)) {
      return dev.writeOperation(
        action: 'network',
        session: session,
        result: captured,
        state: networkState,
        changed: 'none',
      );
    }
    final bodyOutput = captured.output ?? const <String, Object?>{};
    final references = <String, _DevelopmentArtifact>{
      for (final part in _parts(body)) part: ?_artifact(bodyOutput, part),
    };
    final absent = _absentParts(bodyOutput);
    final paths = await _download(
      session: session,
      requestId: requestId!,
      artifacts: references,
    );
    final continuing = bodyOutput['continuing'] == true;
    final state = <String, Object?>{
      ...networkState,
      'body': paths,
      if (absent.isNotEmpty) 'absent': absent,
      if (continuing) 'continuing': true,
    };
    if (paths.isEmpty) {
      return dev.writeEnvelope(
        action: 'network',
        session: session,
        ok: false,
        state: state,
        changed: 'none',
        errors: <Object?>[
          <String, Object?>{
            'code': 'networkBodyAbsent',
            'message':
                'Network request $requestId has no ${absent.join(' or ')} body.',
          },
        ],
        failureExitCode: cockpitDataExitCode,
      );
    }
    return dev.writeEnvelope(
      action: 'network',
      session: session,
      ok: true,
      state: state,
      changed: 'captured',
      evidence: paths,
      next: continuing
          ? 'cockpit dev network $requestId --body $body'
                '${raw ? ' --raw' : ''} --session ${session.handleId}'
          : null,
    );
  }

  Future<Map<String, String>> _download({
    required CockpitCliSessionHandle session,
    required String requestId,
    required Map<String, _DevelopmentArtifact> artifacts,
  }) async {
    final home = CockpitHome.system();
    final homePaths = await home.initialize();
    final checkoutIdentity = session.checkoutIdentity!;
    final safeId = requestId.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    final directory = Directory(
      p.join(
        homePaths.artifactsDirectory,
        'development',
        checkoutIdentity.substring(0, 16),
        session.handleId,
        'network',
        safeId,
        CockpitSecureTokenGenerator().nextResourceIdToken(),
      ),
    );
    await directory.create(recursive: true);
    await home.permissionHardener.hardenDirectory(directory);
    final resolvedDirectory = p.normalize(
      await directory.resolveSymbolicLinks(),
    );
    final client = await runtime.client();
    final downloaded = await Future.wait(
      artifacts.entries.map((entry) async {
        final artifact = entry.value;
        final destination = File(
          p.join(resolvedDirectory, p.basename(artifact.name)),
        );
        final receipt = await client.downloadDevelopmentArtifactToFile(
          workspaceId: session.workspaceId,
          sessionId: session.sessionId,
          artifactId: artifact.id,
          mediaType: artifact.mediaType,
          destination: destination,
        );
        return MapEntry(
          entry.key,
          p.normalize(await receipt.file.resolveSymbolicLinks()),
        );
      }),
    );
    return Map<String, String>.unmodifiable(Map.fromEntries(downloaded));
  }
}

bool _hasOneEntry(Map<String, Object?> state, String requestId) {
  final entries = state['entries'];
  if (entries is! List<Object?> || entries.length != 1) return false;
  final entry = entries.single;
  return entry is Map<Object?, Object?> && entry['requestId'] == requestId;
}

Iterable<String> _parts(String body) =>
    body == 'both' ? const <String>['request', 'response'] : <String>[body];

_DevelopmentArtifact? _artifact(Map<String, Object?> output, String part) {
  final partValue = output[part];
  final partMap = partValue is Map<Object?, Object?> ? partValue : null;
  final artifactValue = partMap?['artifact'];
  final artifactMap = artifactValue is Map<Object?, Object?>
      ? artifactValue
      : null;
  final referenceValue = artifactMap?['artifactRef'];
  final reference = referenceValue is Map<Object?, Object?>
      ? referenceValue
      : null;
  final id = reference?['artifactId'];
  final name = reference?['name'];
  final mediaType = reference?['mediaType'];
  if (id is! String || name is! String || mediaType is! String) {
    return null;
  }
  return _DevelopmentArtifact(id: id, name: name, mediaType: mediaType);
}

List<String> _absentParts(Map<String, Object?> output) {
  final value = output['absent'];
  if (value is! List<Object?>) return const <String>[];
  return value.whereType<String>().toList(growable: false);
}

final class _DevelopmentArtifact {
  const _DevelopmentArtifact({
    required this.id,
    required this.name,
    required this.mediaType,
  });

  final String id;
  final String name;
  final String mediaType;
}
