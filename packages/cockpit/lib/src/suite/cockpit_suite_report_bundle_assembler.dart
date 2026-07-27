import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

import '../artifacts/cockpit_test_attempt_bundle_writer.dart';

final class CockpitSuiteReportArtifactCopy {
  const CockpitSuiteReportArtifactCopy({
    required this.sourcePath,
    required this.artifact,
  });

  final String sourcePath;
  final CockpitTestReportArtifact artifact;
}

final class CockpitSuiteReportBundlePlan {
  CockpitSuiteReportBundlePlan({
    required this.bundle,
    required Iterable<CockpitSuiteReportArtifactCopy> artifactCopies,
    required Map<String, String> executionRoots,
  }) : artifactCopies = List<CockpitSuiteReportArtifactCopy>.unmodifiable(
         artifactCopies,
       ),
       executionRoots = Map<String, String>.unmodifiable(executionRoots);

  final CockpitTestReportBundle bundle;
  final List<CockpitSuiteReportArtifactCopy> artifactCopies;
  final Map<String, String> executionRoots;
}

final class CockpitSuiteReportBundleAssembler {
  const CockpitSuiteReportBundleAssembler({
    CockpitTestAttemptBundleReader reader =
        const CockpitTestAttemptBundleReader(),
  }) : _reader = reader;

  final CockpitTestAttemptBundleReader _reader;

  Future<CockpitSuiteReportBundlePlan> assemble({
    required CockpitTestSuiteReport report,
    required String sourceRunRoot,
    required Iterable<CockpitArtifactResource> artifactResources,
  }) async {
    _validateRoot(sourceRunRoot);
    final resources = artifactResources.toList(growable: false);
    final byAttempt = <String, List<CockpitArtifactResource>>{};
    for (final resource in resources) {
      if (resource.runId != report.runId ||
          resource.workspaceId != report.workspaceId) {
        throw const FormatException(
          'Report source artifact crosses suite authority.',
        );
      }
      final attemptId = resource.attemptId;
      if (attemptId != null) {
        byAttempt
            .putIfAbsent(attemptId, () => <CockpitArtifactResource>[])
            .add(resource);
      }
    }
    final links = _attemptLinks(report);
    final componentOrdinals = <String, int>{};
    var fixtureOrdinal = 0;
    final executions = <CockpitTestReportExecution>[];
    final copies = <CockpitSuiteReportArtifactCopy>[];
    final roots = <String, String>{};
    final attemptIds = byAttempt.keys.toList()..sort();
    for (final attemptId in attemptIds) {
      final attemptResources = byAttempt[attemptId]!;
      final manifestResource = attemptResources.singleWhere(
        (resource) => resource.kind == 'attempt.manifest',
      );
      final manifestPath = _sourcePath(
        sourceRunRoot,
        manifestResource.relativePath,
      );
      final manifest = await _reader.readAndVerify(
        path: p.dirname(manifestPath),
      );
      if (manifest.context.attemptId != attemptId) {
        throw const FormatException(
          'Published attempt manifest identity does not match its resource.',
        );
      }
      final link = _linkForAttempt(attemptId, links);
      late final CockpitTestReportExecutionRole role;
      late final String root;
      if (link != null && link.attemptId == attemptId) {
        role = CockpitTestReportExecutionRole.testCase;
        root = link.root;
      } else if (link != null) {
        role = CockpitTestReportExecutionRole.supporting;
        final next = (componentOrdinals[link.attemptId] ?? 0) + 1;
        componentOrdinals[link.attemptId] = next;
        root = p.posix.join(
          link.root,
          'components',
          '${_ordinal(next, 2)}-${_slug(manifest.context.caseId)}',
        );
      } else {
        role = CockpitTestReportExecutionRole.fixture;
        fixtureOrdinal += 1;
        root = p.posix.join(
          'run',
          'fixtures',
          '${_ordinal(fixtureOrdinal, 3)}-${_slug(manifest.context.caseId)}',
        );
      }
      roots[attemptId] = root;
      final built = _artifacts(
        manifest: manifest,
        resources: attemptResources,
        sourceRunRoot: sourceRunRoot,
        exportRoot: root,
      );
      copies.addAll(built.copies);
      executions.add(
        CockpitTestReportExecution(
          role: role,
          entryId: link?.entryId,
          attemptNumber: link?.number,
          result: _portableResult(manifest.result),
          artifacts: built.artifacts,
        ),
      );
    }
    executions.sort(_compareExecutions);
    return CockpitSuiteReportBundlePlan(
      bundle: CockpitTestReportBundle(
        generatedAt: report.finishedAt.toUtc(),
        report: report,
        executions: executions,
      ),
      artifactCopies: copies,
      executionRoots: roots,
    );
  }
}

typedef _AttemptLink = ({
  String attemptId,
  String entryId,
  int number,
  String root,
});

typedef _BuiltArtifacts = ({
  List<CockpitTestReportArtifact> artifacts,
  List<CockpitSuiteReportArtifactCopy> copies,
});

List<_AttemptLink> _attemptLinks(CockpitTestSuiteReport report) {
  final result = <_AttemptLink>[];
  for (var caseIndex = 0; caseIndex < report.cases.length; caseIndex += 1) {
    final testCase = report.cases[caseIndex];
    final caseRoot = p.posix.join(
      'cases',
      '${_ordinal(caseIndex + 1, 3)}-${_slug(testCase.entryId)}',
    );
    for (var index = 0; index < testCase.attempts.length; index += 1) {
      final attempt = testCase.attempts[index];
      result.add((
        attemptId: attempt.attemptId,
        entryId: testCase.entryId,
        number: attempt.number,
        root: p.posix.join(
          caseRoot,
          'attempts',
          '${_ordinal(index + 1, 2)}-${attempt.outcome.name}',
        ),
      ));
    }
  }
  result.sort(
    (left, right) => right.attemptId.length.compareTo(left.attemptId.length),
  );
  return result;
}

_AttemptLink? _linkForAttempt(String attemptId, List<_AttemptLink> links) {
  for (final link in links) {
    if (attemptId == link.attemptId ||
        attemptId.startsWith('${link.attemptId}_')) {
      return link;
    }
  }
  return null;
}

_BuiltArtifacts _artifacts({
  required CockpitTestAttemptBundleManifest manifest,
  required List<CockpitArtifactResource> resources,
  required String sourceRunRoot,
  required String exportRoot,
}) {
  final manifestResource = resources.singleWhere(
    (resource) => resource.kind == 'attempt.manifest',
  );
  final bundlePrefix = p.posix.dirname(manifestResource.relativePath);
  final resourcesByBundlePath = <String, CockpitArtifactResource>{};
  for (final resource in resources) {
    final relative = p.posix.relative(
      resource.relativePath,
      from: bundlePrefix,
    );
    if (relative == '.' || relative.startsWith('../')) {
      throw const FormatException(
        'Attempt resource escapes its immutable bundle.',
      );
    }
    resourcesByBundlePath[relative] = resource;
  }
  final artifacts = <CockpitTestReportArtifact>[];
  final copies = <CockpitSuiteReportArtifactCopy>[];
  final directoryCounts = <String, int>{};
  for (final entry in manifest.artifacts) {
    final resource = resourcesByBundlePath[entry.relativePath];
    if (resource == null ||
        resource.sha256 != entry.sha256 ||
        resource.sizeBytes != entry.sizeBytes) {
      throw FormatException(
        'Published resource is missing for evidence ${entry.artifactId}.',
      );
    }
    final directory = _evidenceDirectory(entry.kind, entry.mediaType);
    final ordinal = (directoryCounts[directory] ?? 0) + 1;
    directoryCounts[directory] = ordinal;
    final extension = _extension(entry.relativePath, entry.mediaType);
    final requestedName = p.posix.basenameWithoutExtension(entry.relativePath);
    final name = '${_ordinal(ordinal, 3)}-${_slug(requestedName)}$extension';
    final relativePath = p.posix.join(exportRoot, directory, name);
    final artifact = CockpitTestReportArtifact(
      evidenceId: entry.artifactId,
      resourceId: resource.artifactId,
      attemptId: manifest.context.attemptId,
      stepExecutionId: entry.stepExecutionId,
      kind: entry.kind,
      relativePath: relativePath,
      mediaType: entry.mediaType,
      sizeBytes: entry.sizeBytes,
      sha256: entry.sha256,
      createdAt: resource.createdAt.toUtc(),
    );
    artifacts.add(artifact);
    copies.add(
      CockpitSuiteReportArtifactCopy(
        sourcePath: _sourcePath(sourceRunRoot, resource.relativePath),
        artifact: artifact,
      ),
    );
  }
  return (
    artifacts: List<CockpitTestReportArtifact>.unmodifiable(artifacts),
    copies: List<CockpitSuiteReportArtifactCopy>.unmodifiable(copies),
  );
}

String _sourcePath(String sourceRunRoot, String relativePath) {
  final candidate = p.normalize(
    p.joinAll(<String>[sourceRunRoot, ...p.posix.split(relativePath)]),
  );
  if (!p.isWithin(sourceRunRoot, candidate)) {
    throw const FormatException('Report artifact source path escapes its run.');
  }
  return candidate;
}

CockpitTestAttemptResult _portableResult(CockpitTestAttemptResult source) =>
    CockpitTestAttemptResult(
      context: source.context,
      lifecycle: source.lifecycle,
      outcome: source.outcome,
      stability: source.stability,
      startedAt: source.startedAt,
      finishedAt: source.finishedAt,
      durationMs: source.durationMs,
      targetId: source.targetId,
      platform: source.platform,
      requestedPlane: source.requestedPlane,
      actualPlane: source.actualPlane,
      steps: source.steps,
      primaryError: source.primaryError,
      cleanupErrors: source.cleanupErrors,
    );

int _compareExecutions(
  CockpitTestReportExecution left,
  CockpitTestReportExecution right,
) {
  final role = left.role.index.compareTo(right.role.index);
  if (role != 0) return role;
  final entry = (left.entryId ?? '').compareTo(right.entryId ?? '');
  if (entry != 0) return entry;
  final number = (left.attemptNumber ?? 0).compareTo(right.attemptNumber ?? 0);
  if (number != 0) return number;
  return left.result.context.attemptId.compareTo(
    right.result.context.attemptId,
  );
}

String _evidenceDirectory(String kind, String mediaType) {
  final normalized = kind.toLowerCase();
  if (mediaType.startsWith('image/') || normalized.contains('screenshot')) {
    return 'screenshots';
  }
  if (mediaType.startsWith('video/') || normalized.contains('recording')) {
    return 'recordings';
  }
  if (normalized.contains('network') || normalized.contains('har')) {
    return 'network';
  }
  if (normalized.contains('log') ||
      mediaType == 'text/plain' ||
      mediaType == 'text/x-log') {
    return 'logs';
  }
  if (normalized.contains('snapshot')) return 'steps';
  return 'evidence';
}

String _extension(String relativePath, String mediaType) {
  final extension = p.posix.extension(relativePath).toLowerCase();
  if (extension.isNotEmpty && extension.length <= 12) return extension;
  return switch (mediaType) {
    'image/png' => '.png',
    'image/jpeg' => '.jpg',
    'image/webp' => '.webp',
    'video/mp4' => '.mp4',
    'application/json' => '.json',
    'text/plain' || 'text/x-log' => '.txt',
    _ => '.bin',
  };
}

String _slug(String value) {
  final normalized = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final safe = normalized.isEmpty ? 'item' : normalized;
  return safe.length <= 48
      ? safe
      : safe.substring(0, 48).replaceFirst(RegExp(r'-+$'), '');
}

String _ordinal(int value, int width) => value.toString().padLeft(width, '0');

void _validateRoot(String root) {
  if (!p.isAbsolute(root) || p.normalize(root) != root) {
    throw const FormatException(
      'Report source run root must be absolute and normalized.',
    );
  }
  final type = FileSystemEntity.typeSync(root, followLinks: false);
  if (type != FileSystemEntityType.directory) {
    throw FileSystemException('Report source run root is unavailable.', root);
  }
}
