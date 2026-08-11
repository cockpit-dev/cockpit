import 'dart:async';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

import '../application/cockpit_application_service_exception.dart';
import '../application/cockpit_interactive_result_profile.dart';
import '../remote/cockpit_remote_session_client.dart';
import 'cockpit_worker_forwarded_port_handoff.dart';
import 'cockpit_worker_resource_grant.dart';
import 'cockpit_worker_artifact_retainer.dart';
import 'cockpit_worker_runtime_registry.dart';
import 'cockpit_worker_value_reader.dart';
import 'cockpit_workspace_operation_registry.dart';

final class CockpitWorkerApplicationInput {
  CockpitWorkerApplicationInput(
    this._value, {
    required Set<String> allowed,
    Set<String> required = const <String>{},
  }) {
    workerKeys(_value, allowed, r'$.input', required: required);
  }

  final Map<String, Object?> _value;

  String id(String key) => workerId(_value[key], '\$.input.$key');

  String? optionalId(String key) =>
      _value[key] == null ? null : workerId(_value[key], '\$.input.$key');

  String string(String key, {int maximum = 4096}) =>
      workerString(_value[key], '\$.input.$key', maximum: maximum);

  String? optionalString(String key, {int maximum = 4096}) =>
      _value[key] == null
      ? null
      : workerString(_value[key], '\$.input.$key', maximum: maximum);

  int integer(String key, {int minimum = 0, int maximum = 2147483647}) =>
      workerInteger(
        _value[key],
        '\$.input.$key',
        minimum: minimum,
        maximum: maximum,
      );

  int? optionalInteger(
    String key, {
    int minimum = 0,
    int maximum = 2147483647,
  }) => _value[key] == null
      ? null
      : workerInteger(
          _value[key],
          '\$.input.$key',
          minimum: minimum,
          maximum: maximum,
        );

  bool boolean(String key, {bool defaultValue = false}) => _value[key] == null
      ? defaultValue
      : workerBoolean(_value[key], '\$.input.$key');

  Map<String, Object?> object(String key) =>
      workerObject(_value[key], '\$.input.$key');

  Map<String, Object?>? optionalObject(String key) =>
      _value[key] == null ? null : workerObject(_value[key], '\$.input.$key');

  List<Object?> list(String key, {int maximum = 1000}) =>
      workerList(_value[key], '\$.input.$key', maximum: maximum);

  CockpitInteractiveResultProfile profile({
    CockpitInteractiveResultProfileName defaultName =
        CockpitInteractiveResultProfileName.standard,
  }) {
    final value = _value['profile'];
    return CockpitInteractiveResultProfile.preset(
      value == null
          ? defaultName
          : CockpitInteractiveResultProfileName.fromJson(value),
    );
  }

  CockpitSnapshotOptions? optionalSnapshotOptions() {
    final value = optionalObject('snapshotOptions');
    return value == null ? null : CockpitSnapshotOptions.fromJson(value);
  }
}

Future<T> runWorkerApplicationOperation<T>({
  required CockpitWorkspaceOperationContext context,
  required Future<T> Function() operation,
}) async {
  context.cancellation.throwIfCancelled();
  final remaining = context.deadline.difference(DateTime.now().toUtc());
  if (remaining <= Duration.zero) {
    throw TimeoutException('Workspace operation deadline expired.');
  }
  final result = await operation();
  context.cancellation.throwIfCancelled();
  return result;
}

Future<R> runWorkerTransactionalLaunch<T, R>({
  required Future<T> Function() launch,
  required Future<R> Function(T launched) commit,
  required Future<void> Function(T launched) rollback,
}) async {
  final launched = await launch();
  try {
    return await commit(launched);
  } on Object catch (primary, primaryStackTrace) {
    try {
      await rollback(launched);
    } on Object catch (cleanupError) {
      throw CockpitWorkerOperationRollbackException(
        primary: primary,
        cleanupError: cleanupError,
        warningCode: 'launchRollbackFailed',
        warningMessage: 'Failed to stop an application after launch failed.',
      );
    }
    Error.throwWithStackTrace(primary, primaryStackTrace);
  }
}

Future<R> runWorkerTransactionalApplicationLaunch<T, R>({
  required CockpitWorkspaceOperationContext context,
  required Future<T> Function() launch,
  required Future<R> Function(T launched) commit,
  required Future<void> Function(T launched) rollback,
}) => runWorkerTransactionalLaunch<T, R>(
  launch: () async {
    context.cancellation.throwIfCancelled();
    if (!DateTime.now().toUtc().isBefore(context.deadline)) {
      throw TimeoutException('Workspace operation deadline expired.');
    }
    return launch();
  },
  commit: (launched) {
    context.cancellation.throwIfCancelled();
    if (!DateTime.now().toUtc().isBefore(context.deadline)) {
      throw TimeoutException('Workspace operation deadline expired.');
    }
    return commit(launched);
  },
  rollback: rollback,
);

Future<R> runWorkerTransactionalPortLaunch<T, R>({
  required CockpitWorkerForwardedPortHandoff handoff,
  required CockpitWorkerResourceGrant grant,
  required DateTime deadline,
  required Future<T> Function(int port) launch,
  required Future<R> Function(T launched) commit,
  required Future<void> Function(T launched) rollback,
}) async {
  T? launched;
  var launchCompleted = false;
  try {
    final result = await handoff.launchWithGrant(
      grant: grant,
      deadline: deadline,
      launch: (port) async {
        final value = await launch(port);
        launched = value;
        launchCompleted = true;
        return value;
      },
    );
    return await commit(result);
  } on Object catch (primary, primaryStackTrace) {
    if (!launchCompleted) {
      Error.throwWithStackTrace(primary, primaryStackTrace);
    }
    try {
      await rollback(launched as T);
    } on Object catch (cleanupError) {
      throw CockpitWorkerOperationRollbackException(
        primary: primary,
        cleanupError: cleanupError,
        warningCode: 'launchRollbackFailed',
        warningMessage: 'Failed to stop an application after launch failed.',
      );
    }
    Error.throwWithStackTrace(primary, primaryStackTrace);
  }
}

Duration boundedWorkerDuration({
  required CockpitWorkspaceOperationContext context,
  required int? requestedMilliseconds,
  required Duration defaultValue,
  required Duration maximum,
}) {
  var value = requestedMilliseconds == null
      ? defaultValue
      : Duration(milliseconds: requestedMilliseconds);
  if (value > maximum) value = maximum;
  final remaining = context.deadline.difference(DateTime.now().toUtc());
  if (remaining <= Duration.zero) {
    throw TimeoutException('Workspace operation deadline expired.');
  }
  return value < remaining ? value : remaining;
}

CockpitWorkerResourceGrant requireWorkerResourceGrant({
  required CockpitWorkspaceOperationContext context,
  required List<CockpitWorkerResourceGrant> grants,
  required CockpitLeaseResourceKind kind,
  required String resourceId,
}) {
  final matches = grants
      .where(
        (grant) =>
            grant.workspaceId == context.workspaceId &&
            grant.resourceKind == kind &&
            grant.resourceId == resourceId &&
            grant.expiresAt.isAfter(DateTime.now().toUtc()),
      )
      .toList(growable: false);
  if (matches.length != 1) {
    throw const CockpitApplicationServiceException(
      code: 'workerResourceGrantInvalid',
      message: 'Supervisor grant does not authorize this workspace mutation.',
    );
  }
  return matches.single;
}

CockpitRemoteArtifactTempFileFactory cockpitWorkerArtifactTempFileFactory(
  String producerRoot,
) {
  final normalizedProducerRoot = p.normalize(producerRoot);
  if (!p.isAbsolute(normalizedProducerRoot)) {
    throw const FormatException(
      'Worker artifact producer root must be absolute.',
    );
  }
  final temporaryRoot = p.normalize(p.join(normalizedProducerRoot, 'tmp'));
  if (!p.isWithin(normalizedProducerRoot, temporaryRoot)) {
    throw const FormatException(
      'Worker artifact temporary root escapes producer ownership.',
    );
  }
  return (relativePath) async {
    final temporaryDirectory = Directory(temporaryRoot);
    final canonicalTemporaryRoot = p.normalize(
      await temporaryDirectory.resolveSymbolicLinks(),
    );
    if (!p.equals(canonicalTemporaryRoot, temporaryRoot) ||
        !p.isWithin(normalizedProducerRoot, canonicalTemporaryRoot)) {
      throw const FileSystemException(
        'Worker artifact temporary root is not producer-confined.',
      );
    }
    final artifactDirectory = await temporaryDirectory.createTemp(
      'interactive_artifact_',
    );
    final rawBasename = p.basename(relativePath.replaceAll('\\', '/'));
    final basename = rawBasename
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'^\.+$'), '');
    return File(
      p.join(
        artifactDirectory.path,
        basename.isEmpty ? 'artifact.bin' : basename,
      ),
    );
  };
}

final class CockpitWorkerResultSanitizer {
  const CockpitWorkerResultSanitizer({
    required this.workspaceRoot,
    required this.registry,
    required this.artifactRetainer,
  });

  final String workspaceRoot;
  final CockpitWorkerRuntimeRegistry registry;
  final CockpitWorkerArtifactRetainer artifactRetainer;
  static const Set<String> _logicalPathKeys = <String>{
    'loc',
    'route',
    'routeName',
  };

  Future<Map<String, Object?>> sanitize(
    Map<String, Object?> value, {
    String? appId,
    String? sessionId,
    String? targetId,
    String? recordingId,
    String? runId,
    String? committedBundleRoot,
    Map<String, String> probeIds = const <String, String>{},
  }) async => Map<String, Object?>.from(
    await _sanitizeValue(
          value,
          appId: appId,
          sessionId: sessionId,
          targetId: targetId,
          recordingId: recordingId,
          runId: runId,
          committedBundleRoot: committedBundleRoot,
          probeIds: probeIds,
          artifactPaths: const <String, String>{},
          artifactContext: false,
        )
        as Map<String, Object?>,
  );

  Future<Object?> _sanitizeValue(
    Object? value, {
    required String? appId,
    required String? sessionId,
    required String? targetId,
    required String? recordingId,
    required String? runId,
    required String? committedBundleRoot,
    required Map<String, String> probeIds,
    required Map<String, String> artifactPaths,
    required bool artifactContext,
    String? artifactRoot,
    String? key,
  }) async {
    if (key == 'appId' && appId != null) return appId;
    if (key == 'sessionId' && sessionId != null) return sessionId;
    if (key == 'developmentSessionId' && sessionId != null) return sessionId;
    if (key == 'targetId' && targetId != null) return targetId;
    if (key == 'recordingId' && recordingId != null) return recordingId;
    if (key == 'probeId' && value is String && probeIds[value] != null) {
      return probeIds[value];
    }
    if (key == 'snapshotRef' && value is String && sessionId != null) {
      return await registry.recordSnapshotRef(
        sessionId: sessionId,
        retainedRef: value,
      );
    }
    return switch (value) {
      Map<Object?, Object?>() => _sanitizeMap(
        value,
        appId: appId,
        sessionId: sessionId,
        targetId: targetId,
        recordingId: recordingId,
        runId: runId,
        committedBundleRoot: committedBundleRoot,
        probeIds: probeIds,
        artifactPaths: artifactPaths,
        artifactContext: artifactContext,
        artifactRoot: artifactRoot,
      ),
      List<Object?>() => Future.wait<Object?>(
        value.map(
          (item) => _sanitizeValue(
            item,
            appId: appId,
            sessionId: sessionId,
            targetId: targetId,
            recordingId: recordingId,
            runId: runId,
            committedBundleRoot: committedBundleRoot,
            probeIds: probeIds,
            artifactPaths: artifactPaths,
            artifactContext: artifactContext,
            artifactRoot: artifactRoot,
          ),
        ),
      ),
      String() => _sanitizeString(value, key: key),
      _ => value,
    };
  }

  Future<Map<String, Object?>> _sanitizeMap(
    Map<Object?, Object?> value, {
    required String? appId,
    required String? sessionId,
    required String? targetId,
    required String? recordingId,
    required String? runId,
    required String? committedBundleRoot,
    required Map<String, String> probeIds,
    required Map<String, String> artifactPaths,
    required bool artifactContext,
    required String? artifactRoot,
  }) async {
    final json = <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key! as String: entry.value,
    };
    final localArtifactPaths = <String, String>{...artifactPaths};
    for (final sourceMapKey in _artifactSourceMapKeys) {
      if (json[sourceMapKey] case final Map<Object?, Object?> sourceMap) {
        for (final entry in sourceMap.entries) {
          if (entry.key is String && entry.value is String) {
            localArtifactPaths[entry.key! as String] = entry.value! as String;
          }
        }
      }
    }
    final directPath = _directArtifactPath(json);
    final isBundleRoot = directPath?.$1 == 'bundlePath';
    var localArtifactRoot = artifactRoot;
    if (isBundleRoot) {
      localArtifactRoot = _normalizedArtifactPath(directPath!.$2);
    }
    if (directPath != null && !isBundleRoot) {
      for (final nestedKey in _nestedArtifactKeys) {
        if (json[nestedKey] case final Map<Object?, Object?> artifact) {
          if (artifact['relativePath'] case final String relativePath) {
            localArtifactPaths[relativePath] = directPath.$2;
          }
        }
      }
    }
    final relativePath = json['relativePath'] is String
        ? json['relativePath']! as String
        : null;
    final retainedPath =
        directPath?.$2 ??
        (relativePath == null ? null : localArtifactPaths[relativePath]) ??
        (artifactContext && relativePath != null && localArtifactRoot != null
            ? _resolveBundleArtifactPath(localArtifactRoot, relativePath)
            : null);
    final owner = _artifactOwner(
      runId: runId,
      recordingId: recordingId,
      sessionId: sessionId,
    );
    final isNestedArtifactContainer = _nestedArtifactKeys.any(
      (candidate) => json[candidate] is Map<Object?, Object?>,
    );
    Map<String, Object?>? artifactReference;
    if (owner != null &&
        retainedPath != null &&
        (isBundleRoot || !isNestedArtifactContainer || relativePath != null)) {
      final normalizedPath = p.isAbsolute(retainedPath)
          ? p.normalize(retainedPath)
          : p.normalize(p.join(workspaceRoot, retainedPath));
      final name = p.basename(relativePath ?? normalizedPath);
      final kind = isBundleRoot
          ? 'caseAttemptBundle'
          : _artifactKind(json['role'], name);
      final confinedPath = await artifactRetainer.retain(
        ownerKind: owner.$1,
        ownerId: owner.$2,
        sourcePath: normalizedPath,
        allowDirectory: isBundleRoot,
        committedRoot: isBundleRoot ? committedBundleRoot : localArtifactRoot,
      );
      artifactReference = (await registry.registerArtifact(
        ownerKind: owner.$1,
        ownerId: owner.$2,
        kind: kind,
        name: name,
        mediaType: isBundleRoot
            ? 'application/vnd.cockpit.attempt-bundle'
            : _artifactMediaType(name),
        retainedPath: confinedPath,
      )).toReferenceJson();
    }
    final result = <String, Object?>{};
    for (final entry in json.entries) {
      if (_privateResultKeys.hasMatch(entry.key) ||
          _artifactSourceMapKeys.contains(entry.key)) {
        continue;
      }
      result[entry.key] = await _sanitizeValue(
        entry.value,
        key: entry.key,
        appId: appId,
        sessionId: sessionId,
        targetId: targetId,
        recordingId: recordingId,
        runId: runId,
        committedBundleRoot: committedBundleRoot,
        probeIds: probeIds,
        artifactPaths: localArtifactPaths,
        artifactContext:
            artifactContext || _artifactContainerKeys.contains(entry.key),
        artifactRoot: localArtifactRoot,
      );
    }
    if (artifactReference != null) result['artifactRef'] = artifactReference;
    return result;
  }

  String _sanitizeString(String value, {required String? key}) {
    final normalizedRoot = p.normalize(p.absolute(workspaceRoot));
    final redacted = value.replaceAll(normalizedRoot, '<workspace-path>');
    if (redacted != value) {
      return redacted;
    }
    if (_logicalPathKeys.contains(key)) return value;
    if (p.isAbsolute(value)) return '<redacted-path>';
    return value;
  }
}

(String, String)? _artifactOwner({
  required String? runId,
  required String? recordingId,
  required String? sessionId,
}) {
  if (runId != null) return ('run', runId);
  if (recordingId != null) return ('recording', recordingId);
  if (sessionId != null) return ('session', sessionId);
  return null;
}

String? _resolveBundleArtifactPath(String root, String relativePath) {
  if (relativePath.isEmpty || p.isAbsolute(relativePath)) return null;
  final normalizedRoot = _normalizedArtifactPath(root);
  final candidate = p.normalize(
    p.absolute(p.join(normalizedRoot, relativePath)),
  );
  if (!p.isWithin(normalizedRoot, candidate)) return null;
  return candidate;
}

String _normalizedArtifactPath(String value) =>
    p.isAbsolute(value) ? p.normalize(value) : p.normalize(p.absolute(value));

(String, String)? _directArtifactPath(Map<String, Object?> value) {
  for (final key in _directArtifactPathKeys) {
    final candidate = value[key];
    if (candidate is String && candidate.isNotEmpty) return (key, candidate);
  }
  return null;
}

String _artifactKind(Object? role, String name) {
  if (role is String) {
    final normalized = role
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._:-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (normalized.isNotEmpty && RegExp(r'^[a-z0-9]').hasMatch(normalized)) {
      return normalized;
    }
  }
  final extension = p.extension(name).toLowerCase();
  return switch (extension) {
    '.png' || '.jpg' || '.jpeg' || '.webp' => 'screenshot',
    '.mp4' || '.mov' || '.webm' => 'recording',
    '.json' || '.jsonl' || '.log' || '.txt' => 'diagnostic',
    _ => 'artifact',
  };
}

String _artifactMediaType(String name) =>
    switch (p.extension(name).toLowerCase()) {
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.webp' => 'image/webp',
      '.mp4' => 'video/mp4',
      '.mov' => 'video/quicktime',
      '.webm' => 'video/webm',
      '.json' || '.jsonl' => 'application/json',
      '.log' || '.txt' || '.md' => 'text/plain',
      '.zip' => 'application/zip',
      _ => 'application/octet-stream',
    };

const Set<String> _directArtifactPathKeys = <String>{
  'sourcePath',
  'sourceFilePath',
  'outputFilePath',
  'bundlePath',
};

const Set<String> _artifactSourceMapKeys = <String>{
  'artifactSourcePaths',
  'artifactPaths',
};

const Set<String> _nestedArtifactKeys = <String>{
  'artifact',
  'diagnosticsArtifactRef',
};

const Set<String> _artifactContainerKeys = <String>{
  ..._nestedArtifactKeys,
  'artifacts',
  'artifactRefs',
  'captureRefs',
};

final RegExp _privateResultKeys = RegExp(
  r'(?:^|_)(?:projectDir|target|host|hostPort|devicePort|deviceId|platformAppId|processId|baseUrl|appBaseUrl|supervisorBaseUrl|vmServiceUri|sessionHandle|remoteSession|remoteSessionHandle|developmentSession|developmentHandle|appJsonPath|targetJsonPath|persistedHandlePath|sessionHandlePath|supervisorLogPath|sourcePath|sourceFilePath|downloadPath|relativePath|path|root|directory|handleFile|bundlePath|bundleDir)$',
  caseSensitive: false,
);
