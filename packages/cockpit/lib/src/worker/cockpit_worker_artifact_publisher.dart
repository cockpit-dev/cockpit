import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../artifacts/cockpit_test_attempt_bundle_writer.dart';
import '../foundation/cockpit_ids.dart';
import '../foundation/cockpit_locked_json_store.dart';
import '../foundation/cockpit_permissions.dart';
import 'cockpit_json_rpc_peer.dart';
import 'cockpit_worker_artifact_retainer.dart';
import 'cockpit_worker_protocol_result.dart';
import 'cockpit_worker_run_event_store.dart';
import 'cockpit_worker_value_reader.dart';

abstract interface class CockpitWorkerArtifactPublisher {
  Future<List<CockpitArtifactResource>> publishAttemptBundle({
    required String runId,
    required String caseId,
    required String attemptId,
    required String bundleRoot,
    required DateTime deadline,
    required CockpitRpcCancellation cancellation,
  });

  Future<List<CockpitArtifactResource>> publishSuiteReport({
    required CockpitTestSuiteReport report,
    required String reportRoot,
    required DateTime deadline,
    required CockpitRpcCancellation cancellation,
  });

  Future<void> resume();
}

final class CockpitDurableWorkerArtifactPublisher
    implements CockpitWorkerArtifactPublisher {
  CockpitDurableWorkerArtifactPublisher({
    required this.workspaceId,
    required String stateRoot,
    required CockpitJsonRpcPeer peer,
    required CockpitWorkerRunEventStore events,
    required CockpitWorkerArtifactRetainer artifactRetainer,
    required CockpitPermissionHardener permissionHardener,
    required CockpitDirectorySyncer directorySyncer,
    required CockpitWorkerEventRedactor redactor,
    CockpitTokenGenerator? tokenGenerator,
    DateTime Function()? utcNow,
    this.maximumArtifactsPerAttempt = 4096,
    this.maximumArtifactsPerRun = 100000,
    this.maximumRuns = 10000,
    this.maximumDepth = 64,
    this.maximumArtifactBytes = 16 * 1024 * 1024 * 1024,
    this.maximumAggregateBytes = 64 * 1024 * 1024 * 1024,
    this.recoveryTimeout = const Duration(seconds: 30),
  }) : stateRoot = p.normalize(stateRoot),
       _peer = peer,
       _events = events,
       _artifactRetainer = artifactRetainer,
       _permissionHardener = permissionHardener,
       _directorySyncer = directorySyncer,
       _redactor = redactor,
       _tokenGenerator = tokenGenerator ?? CockpitSecureTokenGenerator(),
       _utcNow = utcNow ?? (() => DateTime.now().toUtc()) {
    workerId(workspaceId, r'$.workspaceId');
    if (!p.isAbsolute(stateRoot) || p.normalize(stateRoot) != stateRoot) {
      throw const FormatException('Artifact publisher state root is invalid.');
    }
    if (maximumArtifactsPerAttempt < 1 ||
        maximumArtifactsPerAttempt > 100000 ||
        maximumArtifactsPerRun < 1 ||
        maximumArtifactsPerRun > 100000 ||
        maximumRuns < 1 ||
        maximumRuns > 100000 ||
        maximumDepth < 1 ||
        maximumDepth > 256 ||
        maximumArtifactBytes < 1 ||
        maximumAggregateBytes < maximumArtifactBytes ||
        recoveryTimeout < const Duration(seconds: 1) ||
        recoveryTimeout > const Duration(minutes: 5)) {
      throw ArgumentError('Artifact publication bounds are invalid.');
    }
  }

  final String workspaceId;
  final String stateRoot;
  final int maximumArtifactsPerAttempt;
  final int maximumArtifactsPerRun;
  final int maximumRuns;
  final int maximumDepth;
  final int maximumArtifactBytes;
  final int maximumAggregateBytes;
  final Duration recoveryTimeout;
  final CockpitJsonRpcPeer _peer;
  final CockpitWorkerRunEventStore _events;
  final CockpitWorkerArtifactRetainer _artifactRetainer;
  final CockpitPermissionHardener _permissionHardener;
  final CockpitDirectorySyncer _directorySyncer;
  final CockpitWorkerEventRedactor _redactor;
  final CockpitTokenGenerator _tokenGenerator;
  final DateTime Function() _utcNow;
  final Map<String, Future<void>> _runLocks = <String, Future<void>>{};
  var _rpcSequence = 0;

  @override
  Future<List<CockpitArtifactResource>> publishAttemptBundle({
    required String runId,
    required String caseId,
    required String attemptId,
    required String bundleRoot,
    required DateTime deadline,
    required CockpitRpcCancellation cancellation,
  }) async {
    workerId(runId, r'$.runId');
    workerId(caseId, r'$.caseId');
    workerId(attemptId, r'$.attemptId');
    return _locked(runId, () async {
      _checkOperation(deadline, cancellation);
      final runRoot = p.join(stateRoot, 'runs', runId);
      final plan = await _artifactRetainer.planCommittedBundle(
        ownerId: runId,
        sourcePath: bundleRoot,
      );
      final sourceBundleRoot = plan.sourcePath;
      final retainedBundleRoot = plan.retainedPath;
      _checkOperation(deadline, cancellation);
      await _validateBundleRoot(sourceBundleRoot, runRoot: runRoot);
      final manifest = await const CockpitTestAttemptBundleReader()
          .readAndVerify(path: sourceBundleRoot);
      final context = manifest.context;
      if (context.workspaceId != workspaceId ||
          context.runId != runId ||
          context.caseId != caseId ||
          context.attemptId != attemptId) {
        throw const FormatException('Attempt bundle ownership is invalid.');
      }
      if (manifest.artifacts.length + 1 > maximumArtifactsPerAttempt) {
        throw const FormatException(
          'Attempt artifact count bound was exceeded.',
        );
      }
      final catalog = await _catalog(runId).read();
      final existing = _decodeCatalog(
        catalog,
        expectedRunId: runId,
        maximumArtifacts: maximumArtifactsPerRun,
      );
      final existingByPath = <String, CockpitArtifactResource>{
        for (final resource in existing) resource.relativePath: resource,
      };
      final artifactIds = existing
          .map((resource) => resource.artifactId)
          .toSet();
      final prepared = <CockpitArtifactResource>[];
      final preparedPaths = <String>{};
      var aggregateBytes = 0;
      final declared =
          <
            ({
              String kind,
              String mediaType,
              String relativePath,
              String? stepExecutionId,
              DateTime createdAt,
            })
          >[
            (
              kind: 'attempt.manifest',
              mediaType: 'application/json',
              relativePath: 'manifest.json',
              stepExecutionId: null,
              createdAt: manifest.createdAt,
            ),
            for (final artifact in manifest.artifacts)
              (
                kind: _foundationArtifactKind(artifact.kind),
                mediaType: artifact.mediaType,
                relativePath: artifact.relativePath,
                stepExecutionId: artifact.stepExecutionId,
                createdAt: manifest.createdAt,
              ),
          ];
      for (final item in declared) {
        _checkOperation(deadline, cancellation);
        final relativeToBundle = _safeRelativePath(item.relativePath);
        final depth = p.posix.split(relativeToBundle).length;
        if (depth > maximumDepth) {
          throw const FormatException(
            'Attempt artifact depth bound was exceeded.',
          );
        }
        final sourceFilePath = p.normalize(
          p.join(sourceBundleRoot, relativeToBundle),
        );
        await _validateImmutableFile(
          sourceFilePath,
          bundleRoot: sourceBundleRoot,
        );
        final size = await File(sourceFilePath).length();
        if (size > maximumArtifactBytes) {
          throw const FormatException(
            'Attempt artifact byte bound was exceeded.',
          );
        }
        aggregateBytes += size;
        if (aggregateBytes > maximumAggregateBytes) {
          throw const FormatException(
            'Attempt artifact aggregate byte bound was exceeded.',
          );
        }
        final digest =
            (await sha256.bind(File(sourceFilePath).openRead()).first)
                .toString();
        _checkOperation(deadline, cancellation);
        final retainedFilePath = p.normalize(
          p.join(retainedBundleRoot, relativeToBundle),
        );
        final relativeToRun = p
            .relative(retainedFilePath, from: runRoot)
            .replaceAll('\\', '/');
        if (!preparedPaths.add(relativeToRun)) {
          throw const FormatException(
            'Attempt artifact path is declared more than once.',
          );
        }
        final existingResource = existingByPath[relativeToRun];
        final artifactId =
            existingResource?.artifactId ??
            'artifact_${_tokenGenerator.nextToken(byteLength: 24)}';
        if (existingResource == null && !artifactIds.add(artifactId)) {
          throw const FormatException(
            'Generated artifact id conflicts with the durable catalog.',
          );
        }
        final candidate = _redactedResource(
          CockpitArtifactResource(
            artifactId: artifactId,
            workspaceId: workspaceId,
            runId: runId,
            attemptId: attemptId,
            stepExecutionId: item.stepExecutionId,
            kind: item.kind,
            relativePath: relativeToRun,
            mediaType: item.mediaType,
            sizeBytes: size,
            sha256: digest,
            createdAt: item.createdAt.toUtc(),
            downloadUrl: '/api/v2/runs/$runId/artifacts/$artifactId',
          ),
        );
        if (existingResource != null &&
            !_sameArtifactResource(existingResource, candidate)) {
          throw const FormatException(
            'Attempt artifact conflicts with its durable catalog entry.',
          );
        }
        prepared.add(existingResource ?? candidate);
      }
      final resources = List<CockpitArtifactResource>.unmodifiable(prepared);
      final merged = <String, CockpitArtifactResource>{
        for (final resource in existing) resource.artifactId: resource,
        for (final resource in resources) resource.artifactId: resource,
      }.values.toList(growable: false);
      if (merged.length > maximumArtifactsPerRun) {
        throw const FormatException(
          'Worker artifact catalog bound was exceeded.',
        );
      }
      _checkOperation(deadline, cancellation);
      final retained = await _artifactRetainer.commitCommittedBundle(plan);
      if (!p.equals(retained.path, retainedBundleRoot)) {
        throw StateError('Committed bundle target differs from its plan.');
      }
      _checkOperation(deadline, cancellation);
      await _verifyRetainedBundle(
        runId,
        retained.path,
        resources,
        deadline: deadline,
      );
      await _catalog(runId).transact<void>((currentJson) {
        final current = _decodeCatalog(
          currentJson,
          expectedRunId: runId,
          maximumArtifacts: maximumArtifactsPerRun,
        );
        if (!_sameArtifactCatalog(current, existing)) {
          throw const FormatException(
            'Worker artifact catalog changed after publication preflight.',
          );
        }
        return CockpitLockedJsonUpdate.write(
          _encodeCatalog(runId, merged),
          null,
        );
      });
      for (final resource in resources) {
        if (!await _events.containsArtifact(runId, resource.artifactId)) {
          await _events.append(
            runId,
            CockpitWorkerEventDraft(
              kind: 'artifact.published',
              entityKind: CockpitRunEventEntityKind.artifact,
              caseId: caseId,
              attemptId: attemptId,
              stepExecutionId: resource.stepExecutionId,
              artifacts: <CockpitArtifactReference>[resource.reference],
            ),
            publishImmediately: false,
          );
        }
      }
      await _publish(
        projectId: context.projectId,
        runId: runId,
        caseId: context.caseId,
        resources: resources,
        deadline: deadline,
      );
      await _events.resume();
      return List<CockpitArtifactResource>.unmodifiable(resources);
    });
  }

  @override
  Future<List<CockpitArtifactResource>> publishSuiteReport({
    required CockpitTestSuiteReport report,
    required String reportRoot,
    required DateTime deadline,
    required CockpitRpcCancellation cancellation,
  }) async {
    final runId = report.runId;
    workerId(runId, r'$.runId');
    if (report.workspaceId != workspaceId) {
      throw const FormatException('Suite report crosses workspace authority.');
    }
    return _locked(runId, () async {
      _checkOperation(deadline, cancellation);
      final runRoot = p.join(stateRoot, 'runs', runId);
      final plan = await _artifactRetainer.planCommittedBundle(
        ownerId: runId,
        sourcePath: reportRoot,
      );
      final sourceReportRoot = plan.sourcePath;
      final retainedReportRoot = plan.retainedPath;
      await _validateBundleRoot(sourceReportRoot, runRoot: runRoot);
      final reportManifest = await _verifySourceReport(
        report,
        sourceReportRoot,
      );

      final catalog = await _catalog(runId).read();
      final existing = _decodeCatalog(
        catalog,
        expectedRunId: runId,
        maximumArtifacts: maximumArtifactsPerRun,
      );
      final existingByPath = <String, CockpitArtifactResource>{
        for (final resource in existing) resource.relativePath: resource,
      };
      final artifactIds = existing
          .map((resource) => resource.artifactId)
          .toSet();
      final resources = <CockpitArtifactResource>[];
      var aggregateBytes = 0;
      final declaredFiles = <({String path, String kind, String mediaType})>[
        (
          path: 'manifest.json',
          kind: 'report.manifest',
          mediaType: 'application/json',
        ),
        for (final file in reportManifest.files)
          (path: file.relativePath, kind: file.kind, mediaType: file.mediaType),
      ];
      if (declaredFiles.length > maximumArtifactsPerRun) {
        throw const FormatException(
          'Suite report artifact count bound was exceeded.',
        );
      }
      for (final declared in declaredFiles) {
        _checkOperation(deadline, cancellation);
        final relativePath = _safeRelativePath(declared.path);
        if (p.posix.split(relativePath).length > maximumDepth) {
          throw const FormatException(
            'Suite report artifact depth bound was exceeded.',
          );
        }
        final sourcePath = p.normalize(
          p.joinAll(<String>[sourceReportRoot, ...p.posix.split(relativePath)]),
        );
        await _validateImmutableFile(sourcePath, bundleRoot: sourceReportRoot);
        final size = await File(sourcePath).length();
        if (size > maximumArtifactBytes) {
          throw const FormatException('Suite report file is too large.');
        }
        aggregateBytes += size;
        if (aggregateBytes > maximumAggregateBytes) {
          throw const FormatException(
            'Suite report aggregate byte bound was exceeded.',
          );
        }
        final digest = (await sha256.bind(File(sourcePath).openRead()).first)
            .toString();
        final retainedPath = p.normalize(
          p.joinAll(<String>[
            retainedReportRoot,
            ...p.posix.split(relativePath),
          ]),
        );
        final relativeToRun = p
            .relative(retainedPath, from: runRoot)
            .replaceAll('\\', '/');
        final existingResource = existingByPath[relativeToRun];
        final artifactId =
            existingResource?.artifactId ??
            'artifact_${_tokenGenerator.nextToken(byteLength: 24)}';
        if (existingResource == null && !artifactIds.add(artifactId)) {
          throw const FormatException(
            'Generated report artifact id conflicts with the durable catalog.',
          );
        }
        final candidate = _redactedResource(
          CockpitArtifactResource(
            artifactId: artifactId,
            workspaceId: workspaceId,
            runId: runId,
            kind: declared.kind,
            relativePath: relativeToRun,
            mediaType: declared.mediaType,
            sizeBytes: size,
            sha256: digest,
            createdAt: report.finishedAt.toUtc(),
            downloadUrl: '/api/v2/runs/$runId/artifacts/$artifactId',
          ),
        );
        if (existingResource != null &&
            !_sameArtifactResource(existingResource, candidate)) {
          throw const FormatException(
            'Suite report artifact conflicts with its durable catalog entry.',
          );
        }
        resources.add(existingResource ?? candidate);
      }
      final merged = <String, CockpitArtifactResource>{
        for (final resource in existing) resource.artifactId: resource,
        for (final resource in resources) resource.artifactId: resource,
      }.values.toList(growable: false);
      if (merged.length > maximumArtifactsPerRun) {
        throw const FormatException(
          'Worker artifact catalog bound was exceeded.',
        );
      }
      _checkOperation(deadline, cancellation);
      final retained = await _artifactRetainer.commitCommittedBundle(plan);
      if (!p.equals(retained.path, retainedReportRoot)) {
        throw StateError('Committed report target differs from its plan.');
      }
      await _verifyRetainedReport(
        report,
        retained.path,
        resources,
        deadline: deadline,
      );
      await _catalog(runId).transact<void>((currentJson) {
        final current = _decodeCatalog(
          currentJson,
          expectedRunId: runId,
          maximumArtifacts: maximumArtifactsPerRun,
        );
        if (!_sameArtifactCatalog(current, existing)) {
          throw const FormatException(
            'Worker artifact catalog changed after report preflight.',
          );
        }
        return CockpitLockedJsonUpdate.write(
          _encodeCatalog(runId, merged),
          null,
        );
      });
      for (final resource in resources) {
        if (await _events.containsArtifact(runId, resource.artifactId)) {
          continue;
        }
        await _events.append(
          runId,
          CockpitWorkerEventDraft(
            kind: 'artifact.published',
            entityKind: CockpitRunEventEntityKind.artifact,
            artifacts: <CockpitArtifactReference>[resource.reference],
          ),
          publishImmediately: false,
        );
      }
      await _publish(
        projectId: report.projectId,
        runId: runId,
        caseId: null,
        resources: resources,
        deadline: deadline,
      );
      await _events.resume();
      return List<CockpitArtifactResource>.unmodifiable(resources);
    });
  }

  @override
  Future<void> resume() async {
    final runsRoot = Directory(p.join(stateRoot, 'runs'));
    if (!await runsRoot.exists()) return;
    final recoveryDeadline = _utcNow().add(recoveryTimeout);
    var runCount = 0;
    await for (final entity in runsRoot.list(followLinks: false)) {
      _checkRecoveryDeadline(recoveryDeadline);
      if (await FileSystemEntity.type(entity.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        throw FileSystemException(
          'Worker run root contains an invalid entry.',
          entity.path,
        );
      }
      runCount += 1;
      if (runCount > maximumRuns) {
        throw const FormatException(
          'Worker artifact recovery run bound was exceeded.',
        );
      }
      final runId = p.basename(entity.path);
      workerId(runId, r'$.runId');
      await _validateCanonicalDirectory(entity.path, authority: runsRoot.path);
      final path = p.join(entity.path, 'artifacts.json');
      final catalogType = await FileSystemEntity.type(path, followLinks: false);
      final List<CockpitArtifactResource> resources;
      if (catalogType == FileSystemEntityType.notFound) {
        resources = const <CockpitArtifactResource>[];
      } else {
        if (catalogType != FileSystemEntityType.file) {
          throw FileSystemException(
            'Worker artifact catalog is not a regular file.',
            path,
          );
        }
        await cockpitValidateCanonicalRegularFile(
          path,
          diagnostic: 'Worker artifact catalog is not canonical.',
        );
        resources = _decodeCatalog(
          await _catalog(runId).read(),
          expectedRunId: runId,
          maximumArtifacts: maximumArtifactsPerRun,
        );
      }
      await _recoverRetainedBundles(
        runId,
        resources,
        deadline: recoveryDeadline,
      );
      if (resources.isEmpty) continue;
      final contexts = await _ensureArtifactEvents(runId, resources);
      final resourcesByOwner =
          <
            ({String projectId, String? caseId}),
            List<CockpitArtifactResource>
          >{};
      for (final resource in resources) {
        final attemptId = resource.attemptId;
        final context = attemptId == null ? null : contexts[attemptId];
        final owner = context == null
            ? await _reportOwner(runId, resource)
            : (projectId: context.projectId, caseId: context.caseId);
        resourcesByOwner
            .putIfAbsent(owner, () => <CockpitArtifactResource>[])
            .add(resource);
      }
      for (final entry in resourcesByOwner.entries) {
        await _publish(
          projectId: entry.key.projectId,
          runId: runId,
          caseId: entry.key.caseId,
          resources: entry.value,
          deadline: _utcNow().add(const Duration(seconds: 10)),
        );
      }
    }
  }

  Future<void> _recoverRetainedBundles(
    String runId,
    List<CockpitArtifactResource> resources, {
    required DateTime deadline,
  }) async {
    final runRoot = p.join(stateRoot, 'runs', runId);
    final artifactRoot = p.join(runRoot, 'artifacts');
    final liveByRoot = <String, List<CockpitArtifactResource>>{};
    for (final resource in resources) {
      _checkRecoveryDeadline(deadline);
      final components = p.posix.split(resource.relativePath);
      if (components.length < 3 ||
          components.first != 'artifacts' ||
          !_validRetainedBundleName(components[1])) {
        throw const FormatException(
          'Worker artifact catalog path has no retained bundle authority.',
        );
      }
      final bundleRoot = p.join(artifactRoot, components[1]);
      final candidate = p.normalize(
        p.joinAll(<String>[runRoot, ...components]),
      );
      if (!p.isWithin(bundleRoot, candidate)) {
        throw const FormatException(
          'Worker artifact catalog path escapes its retained bundle.',
        );
      }
      liveByRoot
          .putIfAbsent(bundleRoot, () => <CockpitArtifactResource>[])
          .add(resource);
    }
    for (final entry in liveByRoot.entries) {
      final attemptOwned = entry.value
          .map((resource) => resource.attemptId != null)
          .toSet();
      if (attemptOwned.length != 1) {
        throw const FormatException(
          'Retained artifact bundle mixes ownership levels.',
        );
      }
      if (attemptOwned.single) {
        await _verifyRetainedBundle(
          runId,
          entry.key,
          entry.value,
          deadline: deadline,
        );
      } else {
        final report = await _readSuiteReport(entry.key);
        await _verifyRetainedReport(
          report,
          entry.key,
          entry.value,
          deadline: deadline,
        );
      }
    }

    final artifactType = await FileSystemEntity.type(
      artifactRoot,
      followLinks: false,
    );
    if (artifactType == FileSystemEntityType.notFound) {
      if (liveByRoot.isNotEmpty) {
        throw const FormatException(
          'Worker artifact catalog references a missing retained root.',
        );
      }
      return;
    }
    if (artifactType != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Worker retained artifact root is invalid.',
        artifactRoot,
      );
    }
    await _validateCanonicalDirectory(artifactRoot, authority: runRoot);
    final retainedRoots = <String>[];
    await for (final entity in Directory(
      artifactRoot,
    ).list(followLinks: false)) {
      _checkRecoveryDeadline(deadline);
      if (retainedRoots.length >= maximumArtifactsPerRun) {
        throw const FormatException(
          'Worker retained bundle count bound was exceeded.',
        );
      }
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type != FileSystemEntityType.directory ||
          !_validRetainedBundleName(p.basename(entity.path))) {
        throw FileSystemException(
          'Worker retained artifact root contains an unknown entity.',
          entity.path,
        );
      }
      await _validateRecoveryBundleShape(entity.path, deadline: deadline);
      retainedRoots.add(p.normalize(entity.path));
    }
    final orphans =
        retainedRoots
            .where((path) => !liveByRoot.containsKey(path))
            .toList(growable: false)
          ..sort();
    for (final orphan in orphans) {
      _checkRecoveryDeadline(deadline);
      await Directory(orphan).delete(recursive: true);
    }
    if (orphans.isNotEmpty) await _directorySyncer.sync(artifactRoot);
  }

  Future<void> _verifyRetainedBundle(
    String runId,
    String bundleRoot,
    List<CockpitArtifactResource> resources, {
    required DateTime deadline,
  }) async {
    await _validateRecoveryBundleShape(bundleRoot, deadline: deadline);
    final manifest = await const CockpitTestAttemptBundleReader().readAndVerify(
      path: bundleRoot,
    );
    if (manifest.context.workspaceId != workspaceId ||
        manifest.context.runId != runId) {
      throw const FormatException(
        'Persisted artifact manifest ownership is invalid.',
      );
    }
    final expectedPaths = <String>{
      'manifest.json',
      for (final artifact in manifest.artifacts)
        _safeRelativePath(artifact.relativePath),
    };
    final actualPaths = <String>{};
    for (final resource in resources) {
      _checkRecoveryDeadline(deadline);
      if (resource.workspaceId != workspaceId ||
          resource.runId != runId ||
          resource.attemptId != manifest.context.attemptId ||
          resource.downloadUrl !=
              '/api/v2/runs/$runId/artifacts/${resource.artifactId}') {
        throw const FormatException(
          'Persisted artifact resource ownership is invalid.',
        );
      }
      final filePath = p.normalize(
        p.joinAll(<String>[
          p.join(stateRoot, 'runs', runId),
          ...p.posix.split(resource.relativePath),
        ]),
      );
      await _validateImmutableFile(filePath, bundleRoot: bundleRoot);
      final relative = p
          .relative(filePath, from: bundleRoot)
          .replaceAll('\\', '/');
      if (!actualPaths.add(relative)) {
        throw const FormatException(
          'Persisted artifact bundle path is indexed more than once.',
        );
      }
      final size = await File(filePath).length();
      final digest = (await sha256.bind(File(filePath).openRead()).first)
          .toString();
      if (size != resource.sizeBytes || digest != resource.sha256) {
        throw const FormatException(
          'Persisted artifact resource byte integrity is invalid.',
        );
      }
      if (relative == 'manifest.json') {
        if (resource.kind != 'attempt.manifest' ||
            resource.mediaType != 'application/json' ||
            resource.stepExecutionId != null ||
            resource.createdAt != manifest.createdAt) {
          throw const FormatException(
            'Persisted artifact manifest metadata is invalid.',
          );
        }
        continue;
      }
      final declared = manifest.artifacts
          .where((artifact) => artifact.relativePath == relative)
          .firstOrNull;
      if (declared == null ||
          resource.kind != _foundationArtifactKind(declared.kind) ||
          resource.mediaType != declared.mediaType ||
          resource.stepExecutionId != declared.stepExecutionId ||
          resource.createdAt != manifest.createdAt ||
          resource.sizeBytes != declared.sizeBytes ||
          resource.sha256 != declared.sha256) {
        throw const FormatException(
          'Persisted artifact resource metadata is invalid.',
        );
      }
    }
    if (actualPaths.length != expectedPaths.length ||
        !actualPaths.containsAll(expectedPaths)) {
      throw const FormatException(
        'Persisted artifact catalog does not cover its immutable bundle.',
      );
    }
  }

  Future<CockpitTestReportBundleManifest> _verifySourceReport(
    CockpitTestSuiteReport expected,
    String reportRoot,
  ) async {
    final manifest = await _readReportManifest(reportRoot);
    if (manifest.runId != expected.runId) {
      throw const FormatException(
        'Suite report manifest ownership is invalid.',
      );
    }
    final declared = <String, CockpitTestReportBundleFile>{
      for (final file in manifest.files) file.relativePath: file,
    };
    final required = expected.reportPolicy.formats.map(_reportFileName).toSet();
    if (!declared.keys.toSet().containsAll(required)) {
      throw const FormatException(
        'Suite report files do not match the declared report policy.',
      );
    }
    var actualCount = 0;
    await for (final entity in Directory(
      reportRoot,
    ).list(recursive: true, followLinks: false)) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.directory) continue;
      if (type != FileSystemEntityType.file) {
        throw FileSystemException(
          'Suite report contains a non-file entry.',
          entity.path,
        );
      }
      final relative = p
          .relative(entity.path, from: reportRoot)
          .replaceAll('\\', '/');
      if (relative == 'manifest.json') continue;
      actualCount += 1;
      final file = declared[relative];
      if (file == null ||
          await File(entity.path).length() != file.sizeBytes ||
          (await sha256.bind(File(entity.path).openRead()).first).toString() !=
              file.sha256) {
        throw const FormatException(
          'Suite report manifest integrity verification failed.',
        );
      }
    }
    if (actualCount != declared.length) {
      throw const FormatException(
        'Suite report manifest does not cover every file.',
      );
    }
    final parsed = await _readSuiteReport(reportRoot);
    if (jsonEncode(parsed.toJson()) != jsonEncode(expected.toJson())) {
      throw const FormatException(
        'Canonical suite report does not match the executed report.',
      );
    }
    return manifest;
  }

  Future<void> _verifyRetainedReport(
    CockpitTestSuiteReport expected,
    String bundleRoot,
    List<CockpitArtifactResource> resources, {
    required DateTime deadline,
  }) async {
    await _validateRecoveryBundleShape(bundleRoot, deadline: deadline);
    final report = await _readSuiteReport(bundleRoot);
    if (jsonEncode(report.toJson()) != jsonEncode(expected.toJson()) ||
        report.workspaceId != workspaceId) {
      throw const FormatException(
        'Persisted suite report ownership or content is invalid.',
      );
    }
    final manifest = await _readReportManifest(bundleRoot);
    final declared = <String, CockpitTestReportBundleFile>{
      for (final file in manifest.files) file.relativePath: file,
    };
    final actualNames = <String>{};
    for (final resource in resources) {
      _checkRecoveryDeadline(deadline);
      if (resource.workspaceId != workspaceId ||
          resource.runId != report.runId ||
          resource.attemptId != null ||
          resource.stepExecutionId != null ||
          resource.downloadUrl !=
              '/api/v2/runs/${report.runId}/artifacts/${resource.artifactId}') {
        throw const FormatException(
          'Persisted report artifact ownership is invalid.',
        );
      }
      final filePath = p.normalize(
        p.joinAll(<String>[
          p.join(stateRoot, 'runs', report.runId),
          ...p.posix.split(resource.relativePath),
        ]),
      );
      await _validateImmutableFile(filePath, bundleRoot: bundleRoot);
      final name = p.relative(filePath, from: bundleRoot).replaceAll('\\', '/');
      final declaration = declared[name];
      final isManifest = name == 'manifest.json';
      if (!actualNames.add(name) ||
          !isManifest && declaration == null ||
          resource.kind !=
              (isManifest ? 'report.manifest' : declaration!.kind) ||
          resource.mediaType !=
              (isManifest ? 'application/json' : declaration!.mediaType) ||
          resource.createdAt != report.finishedAt.toUtc()) {
        throw const FormatException(
          'Persisted report artifact metadata is invalid.',
        );
      }
      final size = await File(filePath).length();
      final digest = (await sha256.bind(File(filePath).openRead()).first)
          .toString();
      if (resource.sizeBytes != size || resource.sha256 != digest) {
        throw const FormatException(
          'Persisted report artifact byte integrity is invalid.',
        );
      }
      if (!isManifest &&
          (declaration!.sizeBytes != size || declaration.sha256 != digest)) {
        throw const FormatException(
          'Persisted report manifest integrity is invalid.',
        );
      }
    }
    final expectedNames = <String>{'manifest.json', ...declared.keys};
    if (actualNames.length != expectedNames.length ||
        !actualNames.containsAll(expectedNames)) {
      throw const FormatException(
        'Persisted report artifact catalog is incomplete.',
      );
    }
  }

  Future<CockpitTestSuiteReport> _readSuiteReport(String reportRoot) async {
    final path = p.join(reportRoot, 'report.json');
    await _validateImmutableFile(path, bundleRoot: reportRoot);
    if (await File(path).length() > maximumArtifactBytes) {
      throw const FormatException('Canonical suite report is too large.');
    }
    return CockpitTestReportBundle.fromJson(
      jsonDecode(await File(path).readAsString()),
    ).report;
  }

  Future<CockpitTestReportBundleManifest> _readReportManifest(
    String reportRoot,
  ) async {
    final path = p.join(reportRoot, 'manifest.json');
    await _validateImmutableFile(path, bundleRoot: reportRoot);
    if (await File(path).length() > maximumArtifactBytes) {
      throw const FormatException('Report bundle manifest is too large.');
    }
    return CockpitTestReportBundleManifest.fromJson(
      jsonDecode(await File(path).readAsString()),
    );
  }

  Future<void> _validateRecoveryBundleShape(
    String bundleRoot, {
    required DateTime deadline,
  }) async {
    final artifactRoot = p.dirname(bundleRoot);
    await _validateCanonicalDirectory(bundleRoot, authority: artifactRoot);
    final maximumEntities = maximumArtifactsPerAttempt * maximumDepth + 1;
    var count = 0;
    await for (final entity in Directory(
      bundleRoot,
    ).list(recursive: true, followLinks: false)) {
      _checkRecoveryDeadline(deadline);
      count += 1;
      if (count > maximumEntities) {
        throw const FormatException(
          'Worker retained bundle entity bound was exceeded.',
        );
      }
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type != FileSystemEntityType.file &&
          type != FileSystemEntityType.directory) {
        throw FileSystemException(
          'Worker retained bundle contains an invalid entity.',
          entity.path,
        );
      }
      final relative = p.relative(entity.path, from: bundleRoot);
      if (p.split(relative).length > maximumDepth) {
        throw const FormatException(
          'Worker retained bundle depth bound was exceeded.',
        );
      }
      final canonical = p.normalize(
        type == FileSystemEntityType.directory
            ? await Directory(entity.path).resolveSymbolicLinks()
            : await File(entity.path).resolveSymbolicLinks(),
      );
      if (!p.equals(canonical, p.normalize(entity.path)) ||
          !p.isWithin(bundleRoot, canonical)) {
        throw FileSystemException(
          'Worker retained bundle entity escapes authority.',
          entity.path,
        );
      }
    }
  }

  Future<void> _publish({
    required String projectId,
    required String runId,
    required String? caseId,
    required List<CockpitArtifactResource> resources,
    required DateTime deadline,
  }) async {
    for (var offset = 0; offset < resources.length; offset += 256) {
      final end = (offset + 256).clamp(0, resources.length);
      final batch = resources.sublist(offset, end);
      final raw = await _peer.call(
        method: 'publishArtifactBatch',
        params: <String, Object?>{
          'protocolVersion': cockpitWorkerProtocolVersion,
          'workspaceId': workspaceId,
          'idempotencyKey': 'artifact-$runId-$offset-${++_rpcSequence}',
          'projectId': projectId,
          'runId': runId,
          'caseId': ?caseId,
          'artifacts': batch.map((artifact) => artifact.toJson()).toList(),
        },
        deadline: deadline,
      );
      final result = CockpitWorkerPublishArtifactBatchResult.fromJson(raw);
      final expected = batch.map((artifact) => artifact.artifactId).toSet();
      if (result.runId != runId ||
          result.artifactIds.length != expected.length ||
          !result.artifactIds.every(expected.contains)) {
        throw const FormatException(
          'Supervisor artifact acknowledgement is inconsistent.',
        );
      }
    }
  }

  Future<Map<String, CockpitTestRunContext>> _ensureArtifactEvents(
    String runId,
    List<CockpitArtifactResource> resources,
  ) async {
    if (resources.isEmpty) return const <String, CockpitTestRunContext>{};
    final manifests = resources
        .where((resource) => resource.kind == 'attempt.manifest')
        .toList(growable: false);
    final contextByAttempt = <String, CockpitTestRunContext>{};
    for (final resource in manifests) {
      final path = p.normalize(
        p.join(stateRoot, 'runs', runId, resource.relativePath),
      );
      final root = p.dirname(path);
      final manifest = await const CockpitTestAttemptBundleReader()
          .readAndVerify(path: root);
      if (manifest.context.workspaceId != workspaceId ||
          manifest.context.runId != runId ||
          manifest.context.attemptId != resource.attemptId) {
        throw const FormatException(
          'Persisted artifact manifest ownership is invalid.',
        );
      }
      contextByAttempt[manifest.context.attemptId] = manifest.context;
    }
    for (final resource in resources) {
      if (await _events.containsArtifact(runId, resource.artifactId)) continue;
      final attemptId = resource.attemptId;
      final context = attemptId == null ? null : contextByAttempt[attemptId];
      if (attemptId != null && context == null) {
        throw const FormatException(
          'Persisted artifact has no immutable attempt manifest.',
        );
      }
      await _events.append(
        runId,
        CockpitWorkerEventDraft(
          kind: 'artifact.published',
          entityKind: CockpitRunEventEntityKind.artifact,
          caseId: context?.caseId,
          attemptId: attemptId,
          stepExecutionId: resource.stepExecutionId,
          artifacts: <CockpitArtifactReference>[resource.reference],
        ),
        publishImmediately: false,
      );
    }
    return Map<String, CockpitTestRunContext>.unmodifiable(contextByAttempt);
  }

  Future<({String projectId, String? caseId})> _reportOwner(
    String runId,
    CockpitArtifactResource resource,
  ) async {
    if (resource.attemptId != null) {
      throw const FormatException(
        'Attempt artifact owner must come from its immutable manifest.',
      );
    }
    final components = p.posix.split(resource.relativePath);
    if (components.length < 3 ||
        components.first != 'artifacts' ||
        !_validRetainedBundleName(components[1])) {
      throw const FormatException(
        'Report artifact path has no retained bundle authority.',
      );
    }
    final report = await _readSuiteReport(
      p.join(stateRoot, 'runs', runId, 'artifacts', components[1]),
    );
    if (report.workspaceId != workspaceId || report.runId != runId) {
      throw const FormatException('Persisted suite report owner is invalid.');
    }
    return (projectId: report.projectId, caseId: null);
  }

  CockpitArtifactResource _redactedResource(CockpitArtifactResource resource) {
    final value = _redactor(resource.toJson());
    if (value is! Map<Object?, Object?>) {
      throw const FormatException(
        'Artifact redaction did not return metadata.',
      );
    }
    final safe = CockpitArtifactResource.fromJson(
      Map<String, Object?>.from(value),
    );
    if (safe.artifactId != resource.artifactId ||
        safe.workspaceId != resource.workspaceId ||
        safe.runId != resource.runId ||
        safe.attemptId != resource.attemptId ||
        safe.stepExecutionId != resource.stepExecutionId ||
        safe.relativePath != resource.relativePath ||
        safe.sizeBytes != resource.sizeBytes ||
        safe.sha256 != resource.sha256) {
      throw const FormatException(
        'Artifact redaction changed immutable ownership metadata.',
      );
    }
    return safe;
  }

  Future<void> _validateBundleRoot(
    String bundleRoot, {
    required String runRoot,
  }) async {
    final normalized = p.normalize(bundleRoot);
    if (!p.isAbsolute(bundleRoot) ||
        normalized != bundleRoot ||
        !p.isWithin(runRoot, normalized) ||
        await FileSystemEntity.type(normalized, followLinks: false) !=
            FileSystemEntityType.directory) {
      throw FileSystemException(
        'Attempt bundle escapes its immutable run authority.',
        bundleRoot,
      );
    }
    final canonical = p.normalize(
      await Directory(normalized).resolveSymbolicLinks(),
    );
    if (!p.equals(canonical, normalized) || !p.isWithin(runRoot, canonical)) {
      throw FileSystemException('Attempt bundle is not canonical.', bundleRoot);
    }
  }

  Future<void> _validateCanonicalDirectory(
    String path, {
    required String authority,
  }) async {
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw FileSystemException(
        'Worker artifact directory is unavailable.',
        path,
      );
    }
    final canonical = p.normalize(await Directory(path).resolveSymbolicLinks());
    if (!p.equals(canonical, p.normalize(path)) ||
        !p.isWithin(authority, canonical)) {
      throw FileSystemException(
        'Worker artifact directory escapes authority.',
        path,
      );
    }
  }

  Future<void> _validateImmutableFile(
    String filePath, {
    required String bundleRoot,
  }) async {
    if (!p.isWithin(bundleRoot, filePath) ||
        await FileSystemEntity.type(filePath, followLinks: false) !=
            FileSystemEntityType.file) {
      throw FileSystemException(
        'Attempt artifact is not a confined file.',
        filePath,
      );
    }
    final canonical = p.normalize(await File(filePath).resolveSymbolicLinks());
    if (!p.equals(canonical, filePath) || !p.isWithin(bundleRoot, canonical)) {
      throw FileSystemException('Attempt artifact is not canonical.', filePath);
    }
  }

  CockpitLockedJsonStore<Map<String, Object?>> _catalog(String runId) =>
      CockpitLockedJsonStore<Map<String, Object?>>(
        path: p.join(stateRoot, 'runs', runId, 'artifacts.json'),
        codec: const _ArtifactCatalogCodec(),
        createInitial: () =>
            _encodeCatalog(runId, const <CockpitArtifactResource>[]),
        permissionHardener: _permissionHardener,
        directorySyncer: _directorySyncer,
        maximumBytes: 64 * 1024 * 1024,
      );

  void _checkOperation(DateTime deadline, CockpitRpcCancellation cancellation) {
    cancellation.throwIfCancelled();
    if (!_utcNow().toUtc().isBefore(deadline.toUtc())) {
      throw TimeoutException('Artifact publication deadline expired.');
    }
  }

  void _checkRecoveryDeadline(DateTime deadline) {
    if (!_utcNow().toUtc().isBefore(deadline.toUtc())) {
      throw TimeoutException('Artifact recovery deadline expired.');
    }
  }

  Future<T> _locked<T>(String runId, Future<T> Function() operation) {
    final previous = _runLocks[runId] ?? Future<void>.value();
    final completer = Completer<T>();
    late final Future<void> current;
    current = previous
        .catchError((Object _) {})
        .then((_) => operation())
        .then(completer.complete, onError: completer.completeError)
        .whenComplete(() {
          if (identical(_runLocks[runId], current)) _runLocks.remove(runId);
        });
    _runLocks[runId] = current;
    return completer.future;
  }
}

final class _ArtifactCatalogCodec
    implements CockpitJsonCodec<Map<String, Object?>> {
  const _ArtifactCatalogCodec();

  @override
  Map<String, Object?> decode(Object? json) => workerObject(json, r'$');

  @override
  Object? encode(Map<String, Object?> value) => value;
}

Map<String, Object?> _encodeCatalog(
  String runId,
  Iterable<CockpitArtifactResource> artifacts,
) => <String, Object?>{
  'schemaVersion': 'cockpit.worker.artifacts/v1',
  'runId': runId,
  'artifacts': artifacts.map((artifact) => artifact.toJson()).toList(),
};

List<CockpitArtifactResource> _decodeCatalog(
  Map<String, Object?> value, {
  required String expectedRunId,
  required int maximumArtifacts,
}) {
  final json = workerObject(value, r'$');
  workerKeys(
    json,
    const <String>{'schemaVersion', 'runId', 'artifacts'},
    r'$',
    required: const <String>{'schemaVersion', 'runId', 'artifacts'},
  );
  if (json['schemaVersion'] != 'cockpit.worker.artifacts/v1' ||
      json['runId'] != expectedRunId) {
    throw const FormatException('Worker artifact catalog identity is invalid.');
  }
  final raw = workerList(
    json['artifacts'],
    r'$.artifacts',
    maximum: maximumArtifacts,
  );
  final ids = <String>{};
  final paths = <String>{};
  return <CockpitArtifactResource>[
    for (var index = 0; index < raw.length; index += 1)
      () {
        final resource = CockpitArtifactResource.fromJson(
          raw[index],
          path: '\$.artifacts[$index]',
        );
        if (resource.runId != expectedRunId ||
            !ids.add(resource.artifactId) ||
            !paths.add(resource.relativePath)) {
          throw const FormatException('Worker artifact catalog is corrupt.');
        }
        return resource;
      }(),
  ];
}

bool _sameArtifactResource(
  CockpitArtifactResource left,
  CockpitArtifactResource right,
) => jsonEncode(left.toJson()) == jsonEncode(right.toJson());

bool _sameArtifactCatalog(
  List<CockpitArtifactResource> left,
  List<CockpitArtifactResource> right,
) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (!_sameArtifactResource(left[index], right[index])) return false;
  }
  return true;
}

String _safeRelativePath(String value) {
  final normalized = p.posix.normalize(value.replaceAll('\\', '/'));
  if (normalized.isEmpty ||
      normalized == '.' ||
      p.posix.isAbsolute(normalized) ||
      normalized == '..' ||
      normalized.startsWith('../')) {
    throw const FormatException('Attempt artifact relative path is invalid.');
  }
  return normalized;
}

bool _validRetainedBundleName(String value) =>
    RegExp(r'^bundle_[A-Za-z0-9_-]{32}$').hasMatch(value);

String _foundationArtifactKind(String value) {
  final normalized = value
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), ' ')
      .trim()
      .split(RegExp(r' +'))
      .where((part) => part.isNotEmpty)
      .map(
        (part) => '${part.substring(0, 1).toUpperCase()}${part.substring(1)}',
      )
      .join();
  if (normalized.isEmpty) return 'attempt.artifact';
  final lowerCamel =
      '${normalized.substring(0, 1).toLowerCase()}${normalized.substring(1)}';
  return 'attempt.$lowerCamel';
}

String _reportFileName(CockpitTestReportFormat format) => switch (format) {
  CockpitTestReportFormat.json => 'report.json',
  CockpitTestReportFormat.junit => 'junit.xml',
  CockpitTestReportFormat.html => 'index.html',
  CockpitTestReportFormat.summary => 'summary.md',
};
