import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

import '../supervisor/cockpit_supervisor_api_client.dart';

typedef CockpitReportArtifactDownloader =
    Future<CockpitArtifactDownloadReceipt> Function({
      required CockpitArtifactResource artifact,
      required File destination,
    });

final class CockpitSuiteReportExportReceipt {
  const CockpitSuiteReportExportReceipt({
    required this.path,
    required this.fileCount,
    required this.sizeBytes,
    required this.manifestSha256,
  });

  final String path;
  final int fileCount;
  final int sizeBytes;
  final String manifestSha256;
}

final class CockpitSuiteReportExporter {
  const CockpitSuiteReportExporter({this.maximumConcurrentDownloads = 8});

  final int maximumConcurrentDownloads;

  Future<CockpitSuiteReportExportReceipt> export({
    required String runId,
    required String outputDirectory,
    required Iterable<CockpitArtifactResource> artifacts,
    required CockpitReportArtifactDownloader download,
  }) async {
    final destination = p.normalize(outputDirectory);
    if (!p.isAbsolute(destination) || destination != outputDirectory) {
      throw const FormatException(
        'Suite report output directory must be absolute and normalized.',
      );
    }
    if (maximumConcurrentDownloads < 1) {
      throw const FormatException(
        'Suite report download concurrency must be positive.',
      );
    }
    if (await FileSystemEntity.type(destination, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw FileSystemException(
        'Suite report output directory already exists.',
        destination,
      );
    }

    final catalog = artifacts
        .where((artifact) => artifact.runId == runId)
        .toList(growable: false);
    final manifests = catalog
        .where(
          (artifact) =>
              artifact.kind == 'report.manifest' &&
              artifact.attemptId == null &&
              artifact.stepExecutionId == null,
        )
        .toList(growable: false);
    if (manifests.length != 1) {
      throw const FormatException(
        'Suite report requires exactly one root manifest artifact.',
      );
    }
    final manifestArtifact = manifests.single;
    if (p.posix.basename(manifestArtifact.relativePath) != 'manifest.json') {
      throw const FormatException(
        'Suite report manifest artifact path is invalid.',
      );
    }

    await Directory(p.dirname(destination)).create(recursive: true);
    final staging = await Directory(
      p.dirname(destination),
    ).createTemp('.${p.basename(destination)}.part-');
    try {
      final manifestReceipt = await download(
        artifact: manifestArtifact,
        destination: File(p.join(staging.path, 'manifest.json')),
      );
      final manifest = CockpitTestReportBundleManifest.fromJson(
        jsonDecode(await manifestReceipt.file.readAsString()),
      );
      if (manifest.runId != runId) {
        throw const FormatException(
          'Suite report manifest does not belong to the requested run.',
        );
      }

      final manifestDirectory = p.posix.dirname(manifestArtifact.relativePath);
      final prefix = manifestDirectory == '.' ? '' : '$manifestDirectory/';
      final byPath = <String, CockpitArtifactResource>{};
      for (final artifact in catalog) {
        if (byPath.containsKey(artifact.relativePath)) {
          throw const FormatException(
            'Suite report artifact path is indexed more than once.',
          );
        }
        byPath[artifact.relativePath] = artifact;
      }

      final downloads =
          <
            ({
              CockpitArtifactResource artifact,
              CockpitTestReportBundleFile declaration,
            })
          >[];
      for (final declaration in manifest.files) {
        final artifact = byPath['$prefix${declaration.relativePath}'];
        if (artifact == null ||
            artifact.attemptId != null ||
            artifact.stepExecutionId != null ||
            artifact.kind != declaration.kind ||
            artifact.mediaType != declaration.mediaType ||
            artifact.sizeBytes != declaration.sizeBytes ||
            artifact.sha256 != declaration.sha256) {
          throw FormatException(
            'Suite report artifact does not match manifest: '
            '${declaration.relativePath}.',
          );
        }
        downloads.add((artifact: artifact, declaration: declaration));
      }

      var next = 0;
      Future<void> worker() async {
        while (next < downloads.length) {
          final item = downloads[next];
          next += 1;
          await download(
            artifact: item.artifact,
            destination: File(
              p.joinAll(<String>[
                staging.path,
                ...p.posix.split(item.declaration.relativePath),
              ]),
            ),
          );
        }
      }

      final workerCount = maximumConcurrentDownloads < downloads.length
          ? maximumConcurrentDownloads
          : downloads.length;
      await Future.wait(<Future<void>>[
        for (var index = 0; index < workerCount; index += 1) worker(),
      ]);
      await staging.rename(destination);
      return CockpitSuiteReportExportReceipt(
        path: destination,
        fileCount: manifest.files.length + 1,
        sizeBytes:
            manifestArtifact.sizeBytes +
            manifest.files.fold<int>(
              0,
              (total, file) => total + file.sizeBytes,
            ),
        manifestSha256: manifestArtifact.sha256,
      );
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }
}
