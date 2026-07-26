import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'cockpit_test_attempt_recorder.dart';

final class CockpitTestBundlePublicationException implements Exception {
  const CockpitTestBundlePublicationException(this.error);

  final CockpitTestError error;

  @override
  String toString() =>
      'CockpitTestBundlePublicationException: ${error.message}';
}

final class CockpitTestBundleIntegrityException implements Exception {
  const CockpitTestBundleIntegrityException(this.error);

  final CockpitTestError error;

  @override
  String toString() => 'CockpitTestBundleIntegrityException: ${error.message}';
}

typedef CockpitTestBundlePrePublicationValidator =
    Future<CockpitTestError?> Function(String stagingPath);

final class CockpitTestAttemptBundleReader {
  const CockpitTestAttemptBundleReader();

  Future<CockpitTestAttemptBundleManifest> readAndVerify({
    required String path,
    String? expectedManifestSha256,
  }) async {
    try {
      final directory = Directory(path);
      if (!await directory.exists()) {
        throw _integrityError('Attempt bundle does not exist.');
      }
      final manifestFile = File(p.join(path, 'manifest.json'));
      if (!await manifestFile.exists()) {
        throw _integrityError('Attempt bundle manifest is missing.');
      }
      final manifestBytes = await manifestFile.readAsBytes();
      final manifestHash = sha256.convert(manifestBytes).toString();
      if (expectedManifestSha256 != null &&
          manifestHash != expectedManifestSha256) {
        throw _integrityError('Attempt bundle manifest hash does not match.');
      }
      final decoded = jsonDecode(utf8.decode(manifestBytes));
      final manifest = CockpitTestAttemptBundleManifest.fromJson(decoded);
      final declaredPaths = <String>{'manifest.json'};
      for (final artifact in manifest.artifacts) {
        final relativePath = _safeRelativePath(artifact.relativePath);
        declaredPaths.add(relativePath);
        final file = File(_containedPath(path, relativePath));
        if (!await file.exists() ||
            await file.length() != artifact.sizeBytes ||
            (await sha256.bind(file.openRead()).first).toString() !=
                artifact.sha256) {
          throw _integrityError(
            'Artifact ${artifact.artifactId} failed integrity validation.',
          );
        }
      }
      final actualPaths = <String>{};
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        final type = await FileSystemEntity.type(
          entity.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.link) {
          throw _integrityError('Attempt bundle must not contain links.');
        }
        if (type == FileSystemEntityType.file) {
          actualPaths.add(
            p.relative(entity.path, from: path).replaceAll('\\', '/'),
          );
        }
      }
      if (actualPaths.length != declaredPaths.length ||
          !actualPaths.containsAll(declaredPaths)) {
        throw _integrityError(
          'Attempt bundle contains missing or undeclared files.',
        );
      }
      return manifest;
    } on CockpitTestBundleIntegrityException {
      rethrow;
    } catch (_) {
      throw _integrityError('Attempt bundle integrity validation failed.');
    }
  }
}

final class CockpitTestAttemptBundleWriter {
  const CockpitTestAttemptBundleWriter();

  Future<CockpitTestBundleSummary> write({
    required String rootPath,
    required CockpitTestRunContext context,
    required String sourceSha256,
    required CockpitTestAttemptResult result,
    required List<CockpitTestRecordedArtifact> artifacts,
    required DateTime createdAt,
    CockpitTestBundlePrePublicationValidator? prePublicationValidator,
  }) async {
    final finalPath = p.join(rootPath, 'bundle');
    final finalDirectory = Directory(finalPath);
    if (await finalDirectory.exists()) {
      throw _publicationError('Attempt bundle already exists.');
    }
    final parent = Directory(p.dirname(finalPath));
    await parent.create(recursive: true);
    final staging = await parent.createTemp('.stage-');
    try {
      final entries = <CockpitTestArtifactEntry>[];
      for (final artifact in artifacts) {
        final relativePath = _safeRelativePath(artifact.relativePath);
        final destination = File(_containedPath(staging.path, relativePath));
        await destination.parent.create(recursive: true);
        if (artifact.bytes != null) {
          await _writeAndFlush(destination, artifact.bytes!);
        } else {
          final source = File(artifact.sourcePath!);
          if (!await source.exists()) {
            throw _publicationError('An artifact source file is missing.');
          }
          await source.copy(destination.path);
          final handle = await destination.open(mode: FileMode.append);
          await handle.flush();
          await handle.close();
        }
        final size = await destination.length();
        final digest = await sha256.bind(destination.openRead()).first;
        entries.add(
          CockpitTestArtifactEntry(
            artifactId: artifact.artifactId,
            kind: artifact.kind,
            relativePath: relativePath,
            mediaType: artifact.mediaType,
            sizeBytes: size,
            sha256: digest.toString(),
            stepExecutionId: artifact.stepExecutionId,
          ),
        );
      }
      final artifactIds = entries.map((entry) => entry.artifactId).toSet();
      final evidenceIndex = <CockpitTestEvidenceIndexEntry>[];
      for (
        var stepResultIndex = 0;
        stepResultIndex < result.steps.length;
        stepResultIndex += 1
      ) {
        final step = result.steps[stepResultIndex];
        final ids = step.evidence.where(artifactIds.contains).toList();
        if (ids.isNotEmpty) {
          evidenceIndex.add(
            CockpitTestEvidenceIndexEntry(
              stepResultIndex: stepResultIndex,
              stepExecutionId: step.executionId,
              artifactIds: ids,
            ),
          );
        }
      }
      final manifest = CockpitTestAttemptBundleManifest(
        context: context,
        sourceSha256: sourceSha256,
        createdAt: createdAt,
        result: result,
        artifacts: entries,
        evidenceIndex: evidenceIndex,
      );
      final manifestBytes = utf8.encode(
        '${const JsonEncoder.withIndent('  ').convert(manifest.toJson())}\n',
      );
      final manifestFile = File(p.join(staging.path, 'manifest.json'));
      await _writeAndFlush(manifestFile, manifestBytes);
      final manifestHash = sha256.convert(manifestBytes).toString();
      final validationError = await prePublicationValidator?.call(staging.path);
      if (validationError != null) {
        throw CockpitTestBundlePublicationException(validationError);
      }
      await staging.rename(finalPath);
      return CockpitTestBundleSummary(
        path: finalPath,
        manifestSha256: manifestHash,
        artifactCount: entries.length,
      );
    } on CockpitTestBundlePublicationException {
      rethrow;
    } on CockpitTestError catch (error) {
      throw CockpitTestBundlePublicationException(error);
    } catch (_) {
      throw _publicationError('Attempt bundle publication failed.');
    } finally {
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }
}

String _safeRelativePath(String value) {
  final segments = value.split('/');
  if (value.isEmpty ||
      value.contains(r'\') ||
      RegExp(r'^[A-Za-z]:').hasMatch(value) ||
      p.posix.isAbsolute(value) ||
      value == 'manifest.json' ||
      segments.any(
        (segment) => segment.isEmpty || segment == '.' || segment == '..',
      )) {
    throw _publicationError('Artifact path is unsafe or reserved.');
  }
  return value;
}

String _containedPath(String rootPath, String relativePath) {
  final root = p.canonicalize(p.absolute(rootPath));
  final candidate = p.canonicalize(p.absolute(p.join(root, relativePath)));
  if (!p.isWithin(root, candidate)) {
    throw _publicationError('Artifact path escapes the attempt bundle.');
  }
  return candidate;
}

Future<void> _writeAndFlush(File file, List<int> bytes) async {
  final handle = await file.open(mode: FileMode.write);
  try {
    await handle.writeFrom(bytes);
    await handle.flush();
  } finally {
    await handle.close();
  }
}

CockpitTestBundlePublicationException _publicationError(String message) =>
    CockpitTestBundlePublicationException(
      CockpitTestError(
        code: CockpitTestErrorCode.bundlePublicationFailed,
        message: message,
      ),
    );

CockpitTestBundleIntegrityException _integrityError(String message) =>
    CockpitTestBundleIntegrityException(
      CockpitTestError(
        code: CockpitTestErrorCode.bundleIntegrityFailed,
        message: message,
      ),
    );
