import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/cli/cockpit_suite_report_exporter.dart';
import 'package:cockpit/src/supervisor/cockpit_supervisor_api_client.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('exports a complete report bundle with manifest paths', () async {
    final root = await Directory.systemTemp.createTemp(
      'cockpit-report-export-',
    );
    addTearDown(() => root.delete(recursive: true));
    const runId = 'run_export_1';
    final files = <String, List<int>>{
      'report.json': utf8.encode('{"complete":true}\n'),
      'index.html': utf8.encode('<!doctype html><title>Cockpit</title>\n'),
      'cases/001-login/evidence/success.png': <int>[1, 2, 3, 4],
    };
    final declarations = <CockpitTestReportBundleFile>[
      for (final entry in files.entries)
        CockpitTestReportBundleFile(
          relativePath: entry.key,
          kind: switch (p.posix.extension(entry.key)) {
            '.json' => 'report.json',
            '.html' => 'report.index',
            _ => 'report.evidence.screenshot',
          },
          mediaType: switch (p.posix.extension(entry.key)) {
            '.json' => 'application/json',
            '.html' => 'text/html',
            _ => 'image/png',
          },
          sizeBytes: entry.value.length,
          sha256: sha256.convert(entry.value).toString(),
          runId: runId,
        ),
    ];
    final manifestBytes = utf8.encode(
      '${jsonEncode(CockpitTestReportBundleManifest(runId: runId, createdAt: DateTime.utc(2026, 7, 29), files: declarations).toJson())}\n',
    );
    final bytesByPath = <String, List<int>>{
      'reports/final/manifest.json': manifestBytes,
      for (final entry in files.entries)
        'reports/final/${entry.key}': entry.value,
    };
    final artifacts = <CockpitArtifactResource>[
      _artifact(
        runId: runId,
        path: 'reports/final/manifest.json',
        kind: 'report.manifest',
        mediaType: 'application/json',
        bytes: manifestBytes,
        number: 0,
      ),
      for (var index = 0; index < declarations.length; index += 1)
        _artifact(
          runId: runId,
          path: 'reports/final/${declarations[index].relativePath}',
          kind: declarations[index].kind,
          mediaType: declarations[index].mediaType,
          bytes: files[declarations[index].relativePath]!,
          number: index + 1,
        ),
      _artifact(
        runId: runId,
        path: 'attempts/attempt_1/log.txt',
        kind: 'attempt.log',
        mediaType: 'text/plain',
        bytes: const <int>[9],
        number: 10,
        attemptId: 'attempt_1',
      ),
    ];
    final output = p.join(root.path, 'cockpit-report');

    final receipt = await const CockpitSuiteReportExporter().export(
      runId: runId,
      outputDirectory: output,
      artifacts: artifacts,
      download: ({required artifact, required destination}) async {
        final bytes = bytesByPath[artifact.relativePath]!;
        await destination.parent.create(recursive: true);
        await destination.writeAsBytes(bytes, flush: true);
        return CockpitArtifactDownloadReceipt(
          file: destination,
          mediaType: artifact.mediaType,
          sizeBytes: bytes.length,
          sha256: sha256.convert(bytes).toString(),
        );
      },
    );

    expect(receipt.path, output);
    expect(receipt.fileCount, files.length + 1);
    expect(receipt.manifestSha256, sha256.convert(manifestBytes).toString());
    expect(
      await File(p.join(output, 'index.html')).readAsString(),
      '<!doctype html><title>Cockpit</title>\n',
    );
    expect(
      await File(
        p.join(output, 'cases', '001-login', 'evidence', 'success.png'),
      ).readAsBytes(),
      <int>[1, 2, 3, 4],
    );
    expect(
      await FileSystemEntity.type(p.join(output, 'attempts')),
      FileSystemEntityType.notFound,
    );
  });

  test('removes staging output when catalog does not match manifest', () async {
    final root = await Directory.systemTemp.createTemp(
      'cockpit-report-export-invalid-',
    );
    addTearDown(() => root.delete(recursive: true));
    const runId = 'run_export_2';
    final reportBytes = utf8.encode('{}\n');
    final declaration = CockpitTestReportBundleFile(
      relativePath: 'report.json',
      kind: 'report.json',
      mediaType: 'application/json',
      sizeBytes: reportBytes.length,
      sha256: sha256.convert(reportBytes).toString(),
      runId: runId,
    );
    final manifestBytes = utf8.encode(
      jsonEncode(
        CockpitTestReportBundleManifest(
          runId: runId,
          createdAt: DateTime.utc(2026, 7, 29),
          files: <CockpitTestReportBundleFile>[declaration],
        ).toJson(),
      ),
    );
    final manifest = _artifact(
      runId: runId,
      path: 'reports/final/manifest.json',
      kind: 'report.manifest',
      mediaType: 'application/json',
      bytes: manifestBytes,
      number: 0,
    );
    final output = p.join(root.path, 'cockpit-report');

    await expectLater(
      const CockpitSuiteReportExporter().export(
        runId: runId,
        outputDirectory: output,
        artifacts: <CockpitArtifactResource>[manifest],
        download: ({required artifact, required destination}) async {
          await destination.writeAsBytes(manifestBytes);
          return CockpitArtifactDownloadReceipt(
            file: destination,
            mediaType: artifact.mediaType,
            sizeBytes: manifestBytes.length,
            sha256: sha256.convert(manifestBytes).toString(),
          );
        },
      ),
      throwsFormatException,
    );
    expect(await Directory(output).exists(), isFalse);
    expect(await root.list().toList(), isEmpty);
  });

  test('removes staged files when a report download fails', () async {
    final root = await Directory.systemTemp.createTemp(
      'cockpit-report-export-download-failure-',
    );
    addTearDown(() => root.delete(recursive: true));
    const runId = 'run_export_3';
    final reportBytes = utf8.encode('{}\n');
    final indexBytes = utf8.encode('<!doctype html>\n');
    final declarations = <CockpitTestReportBundleFile>[
      CockpitTestReportBundleFile(
        relativePath: 'report.json',
        kind: 'report.json',
        mediaType: 'application/json',
        sizeBytes: reportBytes.length,
        sha256: sha256.convert(reportBytes).toString(),
        runId: runId,
      ),
      CockpitTestReportBundleFile(
        relativePath: 'index.html',
        kind: 'report.index',
        mediaType: 'text/html',
        sizeBytes: indexBytes.length,
        sha256: sha256.convert(indexBytes).toString(),
        runId: runId,
      ),
    ];
    final manifestBytes = utf8.encode(
      jsonEncode(
        CockpitTestReportBundleManifest(
          runId: runId,
          createdAt: DateTime.utc(2026, 7, 29),
          files: declarations,
        ).toJson(),
      ),
    );
    final artifacts = <CockpitArtifactResource>[
      _artifact(
        runId: runId,
        path: 'reports/final/manifest.json',
        kind: 'report.manifest',
        mediaType: 'application/json',
        bytes: manifestBytes,
        number: 0,
      ),
      _artifact(
        runId: runId,
        path: 'reports/final/report.json',
        kind: 'report.json',
        mediaType: 'application/json',
        bytes: reportBytes,
        number: 1,
      ),
      _artifact(
        runId: runId,
        path: 'reports/final/index.html',
        kind: 'report.index',
        mediaType: 'text/html',
        bytes: indexBytes,
        number: 2,
      ),
    ];
    final output = p.join(root.path, 'cockpit-report');

    await expectLater(
      const CockpitSuiteReportExporter(maximumConcurrentDownloads: 1).export(
        runId: runId,
        outputDirectory: output,
        artifacts: artifacts,
        download: ({required artifact, required destination}) async {
          if (artifact.kind == 'report.index') {
            throw FileSystemException('download failed');
          }
          final bytes = artifact.kind == 'report.manifest'
              ? manifestBytes
              : reportBytes;
          await destination.parent.create(recursive: true);
          await destination.writeAsBytes(bytes);
          return CockpitArtifactDownloadReceipt(
            file: destination,
            mediaType: artifact.mediaType,
            sizeBytes: bytes.length,
            sha256: sha256.convert(bytes).toString(),
          );
        },
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await Directory(output).exists(), isFalse);
    expect(await root.list().toList(), isEmpty);
  });

  test('rejects an existing output directory before downloading', () async {
    final root = await Directory.systemTemp.createTemp(
      'cockpit-report-export-existing-',
    );
    addTearDown(() => root.delete(recursive: true));
    final output = await Directory(
      p.join(root.path, 'cockpit-report'),
    ).create();
    var downloaded = false;

    await expectLater(
      const CockpitSuiteReportExporter().export(
        runId: 'run_export_4',
        outputDirectory: output.path,
        artifacts: const <CockpitArtifactResource>[],
        download: ({required artifact, required destination}) async {
          downloaded = true;
          throw StateError('unreachable');
        },
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(downloaded, isFalse);
  });
}

CockpitArtifactResource _artifact({
  required String runId,
  required String path,
  required String kind,
  required String mediaType,
  required List<int> bytes,
  required int number,
  String? attemptId,
}) => CockpitArtifactResource(
  artifactId: 'artifact_export_$number',
  workspaceId: 'workspace_export',
  runId: runId,
  attemptId: attemptId,
  kind: kind,
  relativePath: path,
  mediaType: mediaType,
  sizeBytes: bytes.length,
  sha256: sha256.convert(bytes).toString(),
  createdAt: DateTime.utc(2026, 7, 29),
  downloadUrl: '/api/v2/runs/$runId/artifacts/artifact_export_$number',
);
