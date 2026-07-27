import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'cockpit_suite_report_bundle_assembler.dart';
import 'cockpit_suite_report_renderer.dart';

final class CockpitSuiteReportFiles {
  CockpitSuiteReportFiles(
    Map<CockpitTestReportFormat, String> paths, {
    required this.manifestPath,
  }) : paths = Map<CockpitTestReportFormat, String>.unmodifiable(paths);

  final Map<CockpitTestReportFormat, String> paths;
  final String manifestPath;
}

final class CockpitSuiteReportWriter {
  const CockpitSuiteReportWriter({
    CockpitSuiteReportRenderer renderer = const CockpitSuiteReportRenderer(),
    CockpitSuiteReportBundleAssembler assembler =
        const CockpitSuiteReportBundleAssembler(),
  }) : _renderer = renderer,
       _assembler = assembler;

  final CockpitSuiteReportRenderer _renderer;
  final CockpitSuiteReportBundleAssembler _assembler;

  Future<CockpitSuiteReportFiles> write({
    required CockpitTestSuiteReport report,
    required String runRoot,
    required String sourceRunRoot,
    required Iterable<CockpitArtifactResource> artifactResources,
  }) async {
    await _prepareRoot(runRoot);
    final plan = await _assembler.assemble(
      report: report,
      sourceRunRoot: sourceRunRoot,
      artifactResources: artifactResources,
    );
    for (final copy in plan.artifactCopies) {
      await _copyImmutable(
        copy.sourcePath,
        p.joinAll(<String>[
          runRoot,
          ...p.posix.split(copy.artifact.relativePath),
        ]),
        expectedSize: copy.artifact.sizeBytes,
        expectedSha256: copy.artifact.sha256,
      );
    }
    await _writeStructuredFiles(runRoot, plan);

    final outputs = <CockpitTestReportFormat, String>{};
    for (final format in report.reportPolicy.formats) {
      final name = _reportFileName(format);
      final target = p.join(runRoot, name);
      final content = switch (format) {
        CockpitTestReportFormat.json => _json(plan.bundle.toJson()),
        CockpitTestReportFormat.junit => _renderer.junit(report),
        CockpitTestReportFormat.html => _renderer.html(plan.bundle),
        CockpitTestReportFormat.summary => _renderer.summary(plan.bundle),
      };
      await _writeImmutable(target, content);
      outputs[format] = target;
    }
    final manifestPath = p.join(runRoot, 'manifest.json');
    final manifest = await _manifest(runRoot, plan);
    await _writeImmutable(manifestPath, _json(manifest.toJson()));
    await _verifyManifest(runRoot, manifest);
    return CockpitSuiteReportFiles(outputs, manifestPath: manifestPath);
  }

  Future<void> _writeStructuredFiles(
    String runRoot,
    CockpitSuiteReportBundlePlan plan,
  ) async {
    final report = plan.bundle.report;
    await _writeImmutable(
      p.join(runRoot, 'run', 'run.json'),
      _json(<String, Object?>{
        'schemaVersion': 'cockpit.report.run/v2',
        'projectId': report.projectId,
        'workspaceId': report.workspaceId,
        'runId': report.runId,
        'suiteId': report.suiteId,
        'sourceSha256': report.sourceSha256,
        'outcome': report.outcome.name,
        'stability': report.stability.name,
        'startedAt': report.startedAt.toUtc().toIso8601String(),
        'finishedAt': report.finishedAt.toUtc().toIso8601String(),
        'durationMs': report.durationMs,
        'counts': report.counts.toJson(),
        'environment': report.environment,
        'complete': report.complete,
      }),
    );
    await _writeImmutable(
      p.join(runRoot, 'run', 'events.jsonl'),
      _renderer.eventsJsonl(plan.bundle),
    );
    final executionByAttempt = <String, CockpitTestReportExecution>{
      for (final execution in plan.bundle.executions)
        execution.result.context.attemptId: execution,
    };
    for (var caseIndex = 0; caseIndex < report.cases.length; caseIndex += 1) {
      final testCase = report.cases[caseIndex];
      final caseRoot = p.join(
        runRoot,
        'cases',
        '${_ordinal(caseIndex + 1, 3)}-${_slug(testCase.entryId)}',
      );
      await _writeImmutable(
        p.join(caseRoot, 'case.json'),
        _json(testCase.toJson()),
      );
      for (var index = 0; index < testCase.attempts.length; index += 1) {
        final attempt = testCase.attempts[index];
        final attemptRoot = p.join(
          caseRoot,
          'attempts',
          '${_ordinal(index + 1, 2)}-${attempt.outcome.name}',
        );
        final execution = executionByAttempt[attempt.attemptId];
        await _writeImmutable(
          p.join(attemptRoot, 'manifest.json'),
          _json(
            execution?.toJson() ??
                <String, Object?>{
                  'role': CockpitTestReportExecutionRole.testCase.name,
                  'entryId': testCase.entryId,
                  'attemptNumber': attempt.number,
                  'summary': attempt.toJson(),
                },
          ),
        );
        if (execution != null) {
          await _writeImmutable(
            p.join(attemptRoot, 'steps', 'steps.json'),
            _json(<String, Object?>{
              'attemptId': attempt.attemptId,
              'steps': execution.result.steps
                  .map((step) => step.toJson())
                  .toList(),
            }),
          );
        }
      }
    }
    for (final execution in plan.bundle.executions) {
      if (execution.role == CockpitTestReportExecutionRole.testCase) continue;
      final root = plan.executionRoots[execution.result.context.attemptId]!;
      final absolute = p.joinAll(<String>[runRoot, ...p.posix.split(root)]);
      await _writeImmutable(
        p.join(absolute, 'manifest.json'),
        _json(execution.toJson()),
      );
      await _writeImmutable(
        p.join(absolute, 'steps', 'steps.json'),
        _json(<String, Object?>{
          'attemptId': execution.result.context.attemptId,
          'steps': execution.result.steps.map((step) => step.toJson()).toList(),
        }),
      );
    }
  }

  Future<CockpitTestReportBundleManifest> _manifest(
    String runRoot,
    CockpitSuiteReportBundlePlan plan,
  ) async {
    final evidenceByPath = <String, CockpitTestReportArtifact>{
      for (final copy in plan.artifactCopies)
        copy.artifact.relativePath: copy.artifact,
    };
    final caseIdsByDirectory = <String, String>{};
    for (
      var caseIndex = 0;
      caseIndex < plan.bundle.report.cases.length;
      caseIndex += 1
    ) {
      final testCase = plan.bundle.report.cases[caseIndex];
      caseIdsByDirectory['${_ordinal(caseIndex + 1, 3)}-${_slug(testCase.entryId)}'] =
          testCase.caseId;
    }
    final files = <CockpitTestReportBundleFile>[];
    await for (final entity in Directory(
      runRoot,
    ).list(recursive: true, followLinks: false)) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.directory) continue;
      if (type != FileSystemEntityType.file) {
        throw FileSystemException(
          'Offline report contains an unsupported file-system entity.',
          entity.path,
        );
      }
      final relativePath = p
          .relative(entity.path, from: runRoot)
          .replaceAll('\\', '/');
      if (relativePath == 'manifest.json') continue;
      final evidence = evidenceByPath[relativePath];
      final owner = _ownerFor(relativePath, plan, caseIdsByDirectory);
      final file = File(entity.path);
      files.add(
        CockpitTestReportBundleFile(
          relativePath: relativePath,
          kind: evidence == null
              ? _fileKind(relativePath)
              : _evidenceFileKind(evidence.kind),
          mediaType: evidence?.mediaType ?? _mediaType(relativePath),
          sizeBytes: await file.length(),
          sha256: (await sha256.bind(file.openRead()).first).toString(),
          runId: plan.bundle.report.runId,
          caseId: owner.caseId,
          attemptId: evidence?.attemptId ?? owner.attemptId,
          stepExecutionId: evidence?.stepExecutionId,
          resourceId: evidence?.resourceId,
          evidenceId: evidence?.evidenceId,
        ),
      );
    }
    files.sort(
      (left, right) => left.relativePath.compareTo(right.relativePath),
    );
    return CockpitTestReportBundleManifest(
      runId: plan.bundle.report.runId,
      createdAt: plan.bundle.report.finishedAt.toUtc(),
      files: files,
    );
  }

  Future<void> _verifyManifest(
    String runRoot,
    CockpitTestReportBundleManifest manifest,
  ) async {
    final declared = manifest.files.map((file) => file.relativePath).toSet();
    var actualCount = 0;
    await for (final entity in Directory(
      runRoot,
    ).list(recursive: true, followLinks: false)) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.directory) continue;
      if (type != FileSystemEntityType.file) {
        throw FileSystemException(
          'Offline report contains an unsupported file-system entity.',
          entity.path,
        );
      }
      final relative = p
          .relative(entity.path, from: runRoot)
          .replaceAll('\\', '/');
      if (relative == 'manifest.json') continue;
      actualCount += 1;
      if (!declared.contains(relative)) {
        throw const FormatException(
          'Offline report contains an undeclared file.',
        );
      }
    }
    if (actualCount != manifest.files.length) {
      throw const FormatException(
        'Offline report manifest does not cover every file.',
      );
    }
  }

  Future<void> _prepareRoot(String runRoot) async {
    final normalizedRoot = p.normalize(runRoot);
    if (!p.isAbsolute(runRoot) || normalizedRoot != runRoot) {
      throw const FormatException(
        'Suite report root must be absolute and normalized.',
      );
    }
    final type = await FileSystemEntity.type(runRoot, followLinks: false);
    if (type == FileSystemEntityType.link ||
        type != FileSystemEntityType.notFound &&
            type != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Suite report root is not a directory.',
        runRoot,
      );
    }
    await Directory(runRoot).create(recursive: true);
  }

  Future<void> _copyImmutable(
    String sourcePath,
    String targetPath, {
    required int expectedSize,
    required String expectedSha256,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists() ||
        await source.length() != expectedSize ||
        (await sha256.bind(source.openRead()).first).toString() !=
            expectedSha256) {
      throw const FormatException(
        'Offline report evidence source failed integrity verification.',
      );
    }
    final target = File(targetPath);
    await target.parent.create(recursive: true);
    if (await target.exists()) {
      if (await target.length() == expectedSize &&
          (await sha256.bind(target.openRead()).first).toString() ==
              expectedSha256) {
        return;
      }
      throw FileSystemException(
        'Finalized offline report evidence is immutable.',
        targetPath,
      );
    }
    final temporary = File(
      '$targetPath.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await source.copy(temporary.path);
    await temporary.rename(targetPath);
  }

  Future<void> _writeImmutable(String path, String content) async {
    final target = File(path);
    await target.parent.create(recursive: true);
    if (await target.exists()) {
      if (await target.readAsString() != content) {
        throw FileSystemException('Finalized suite report is immutable.', path);
      }
      return;
    }
    final temporary = File(
      '$path.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    final sink = temporary.openWrite(mode: FileMode.writeOnly);
    try {
      sink.write(content);
      await sink.flush();
      await sink.close();
      await temporary.rename(path);
    } on Object {
      await sink.close();
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }
}

({String? caseId, String? attemptId}) _ownerFor(
  String relativePath,
  CockpitSuiteReportBundlePlan plan,
  Map<String, String> caseIdsByDirectory,
) {
  for (final entry in plan.executionRoots.entries) {
    if (relativePath == entry.value ||
        relativePath.startsWith('${entry.value}/')) {
      final execution = plan.bundle.executions.singleWhere(
        (item) => item.result.context.attemptId == entry.key,
      );
      return (caseId: execution.result.context.caseId, attemptId: entry.key);
    }
  }
  final parts = p.posix.split(relativePath);
  if (parts.length > 1 && parts.first == 'cases') {
    return (caseId: caseIdsByDirectory[parts[1]], attemptId: null);
  }
  return (caseId: null, attemptId: null);
}

String _reportFileName(CockpitTestReportFormat format) => switch (format) {
  CockpitTestReportFormat.json => 'report.json',
  CockpitTestReportFormat.junit => 'junit.xml',
  CockpitTestReportFormat.html => 'index.html',
  CockpitTestReportFormat.summary => 'summary.md',
};

String _fileKind(String relativePath) {
  if (relativePath == 'report.json') return 'report.json';
  if (relativePath == 'index.html') return 'report.index';
  if (relativePath == 'junit.xml') return 'report.junit';
  if (relativePath == 'summary.md') return 'report.summary';
  if (relativePath == 'run/run.json') return 'report.run';
  if (relativePath == 'run/events.jsonl') return 'report.events';
  if (relativePath.endsWith('/case.json')) return 'report.case';
  if (relativePath.endsWith('/manifest.json')) return 'report.attempt';
  if (relativePath.endsWith('/steps.json')) return 'report.steps';
  return 'report.file';
}

String _evidenceFileKind(String value) {
  final normalized = value
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), ' ')
      .trim()
      .split(RegExp(r' +'))
      .where((part) => part.isNotEmpty)
      .map(
        (part) => '${part.substring(0, 1).toUpperCase()}${part.substring(1)}',
      )
      .join();
  if (normalized.isEmpty) return 'report.evidence';
  return 'report.evidence.'
      '${normalized.substring(0, 1).toLowerCase()}${normalized.substring(1)}';
}

String _mediaType(String relativePath) {
  final extension = p.posix.extension(relativePath).toLowerCase();
  return switch (extension) {
    '.json' => 'application/json',
    '.jsonl' => 'application/x-ndjson',
    '.xml' => 'application/xml',
    '.html' => 'text/html',
    '.md' => 'text/markdown',
    '.png' => 'image/png',
    '.jpg' || '.jpeg' => 'image/jpeg',
    '.webp' => 'image/webp',
    '.mp4' => 'video/mp4',
    '.txt' || '.log' => 'text/plain',
    _ => 'application/octet-stream',
  };
}

String _json(Object? value) =>
    '${const JsonEncoder.withIndent('  ').convert(value)}\n';

String _slug(String value) {
  final normalized = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final safe = normalized.isEmpty ? 'item' : normalized;
  if (safe.length <= 48) return safe;
  return safe.substring(0, 48).replaceFirst(RegExp(r'-+$'), '');
}

String _ordinal(int value, int width) => value.toString().padLeft(width, '0');
