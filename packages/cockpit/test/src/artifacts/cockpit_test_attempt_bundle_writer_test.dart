import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/artifacts/cockpit_test_attempt_bundle_writer.dart';
import 'package:cockpit/src/artifacts/cockpit_test_attempt_recorder.dart';
import 'package:cockpit/src/worker/cockpit_worker_logger.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  const writer = CockpitTestAttemptBundleWriter();
  const reader = CockpitTestAttemptBundleReader();

  test('publishes and verifies an immutable identity-scoped bundle', () async {
    final root = await Directory.systemTemp.createTemp('cockpit-v2-bundle-');
    addTearDown(() => root.delete(recursive: true));
    final result = _result(evidence: const <String>['artifact000001']);
    final summary = await writer.write(
      rootPath: root.path,
      context: result.context,
      sourceSha256: _hash('a'),
      result: result,
      artifacts: <CockpitTestRecordedArtifact>[
        CockpitTestRecordedArtifact(
          artifactId: 'artifact000001',
          kind: 'screenshot',
          relativePath: 'screenshots/final.png',
          mediaType: 'image/png',
          stepExecutionId: 'main/verify',
          bytes: const <int>[1, 2, 3, 4],
        ),
      ],
      createdAt: DateTime.utc(2026, 7, 20, 1),
    );

    expect(p.normalize(summary.path), p.normalize(p.join(root.path, 'bundle')));
    final manifest = await reader.readAndVerify(
      path: summary.path,
      expectedManifestSha256: summary.manifestSha256,
    );
    expect(manifest.schemaVersion, 'cockpit.report/v2');
    expect(manifest.artifacts.single.sizeBytes, 4);
    expect(jsonEncode(manifest.toJson()), isNot(contains('taskId')));

    await expectLater(
      writer.write(
        rootPath: root.path,
        context: result.context,
        sourceSha256: _hash('a'),
        result: result,
        artifacts: const <CockpitTestRecordedArtifact>[],
        createdAt: DateTime.utc(2026, 7, 20, 1),
      ),
      throwsA(isA<CockpitTestBundlePublicationException>()),
    );
  });

  test('validates complete staging once before atomic publication', () async {
    final root = await Directory.systemTemp.createTemp(
      'cockpit-v2-commit-guard-',
    );
    addTearDown(() => root.delete(recursive: true));
    final result = _result(evidence: const <String>['artifact000001']);
    final expectedFinalPath = _bundlePath(root.path);
    var validationCount = 0;
    String? observedStagingPath;

    final summary = await writer.write(
      rootPath: root.path,
      context: result.context,
      sourceSha256: _hash('f'),
      result: result,
      artifacts: <CockpitTestRecordedArtifact>[
        CockpitTestRecordedArtifact(
          artifactId: 'artifact000001',
          kind: 'screenshot',
          relativePath: 'screenshots/final.png',
          mediaType: 'image/png',
          stepExecutionId: 'main/verify',
          bytes: const <int>[1, 2, 3, 4],
        ),
      ],
      createdAt: DateTime.utc(2026, 7, 20, 1),
      prePublicationValidator: (stagingPath) async {
        validationCount += 1;
        observedStagingPath = stagingPath;
        expect(await Directory(expectedFinalPath).exists(), isFalse);
        final manifest = await reader.readAndVerify(path: stagingPath);
        expect(manifest.artifacts.single.relativePath, 'screenshots/final.png');
        return null;
      },
    );

    expect(validationCount, 1);
    expect(summary.path, expectedFinalPath);
    expect(await Directory(expectedFinalPath).exists(), isTrue);
    expect(p.basename(observedStagingPath!), startsWith('.stage-'));
    expect(observedStagingPath, isNot(contains(result.context.attemptId)));
    expect(await Directory(observedStagingPath!).exists(), isFalse);
  });

  test('secret artifacts and manifests never reach the final path', () async {
    const secret = 'pre-publication-secret';
    for (final source in const <String>['artifact', 'manifest']) {
      final root = await Directory.systemTemp.createTemp(
        'cockpit-v2-secret-$source-',
      );
      addTearDown(() => root.delete(recursive: true));
      final result = _result(
        evidence: source == 'artifact'
            ? const <String>['artifact000001']
            : const <String>[],
        primaryError: source == 'manifest'
            ? CockpitTestError(
                code: CockpitTestErrorCode.driverFailed,
                message: 'Driver exposed $secret.',
              )
            : null,
      );
      final finalPath = _bundlePath(root.path);
      String? stagingPath;
      final validationError = CockpitTestError(
        code: CockpitTestErrorCode.bundlePublicationFailed,
        message: 'Bundle contains a plaintext secret.',
        details: const <String, Object?>{'reason': 'plaintextSecretRejected'},
      );

      await expectLater(
        writer.write(
          rootPath: root.path,
          context: result.context,
          sourceSha256: _hash('1'),
          result: result,
          artifacts: source == 'artifact'
              ? <CockpitTestRecordedArtifact>[
                  CockpitTestRecordedArtifact(
                    artifactId: 'artifact000001',
                    kind: 'binary',
                    relativePath: 'artifacts/payload.bin',
                    mediaType: 'application/octet-stream',
                    stepExecutionId: 'main/verify',
                    bytes: <int>[0xff, ...utf8.encode(secret), 0xfe],
                  ),
                ]
              : const <CockpitTestRecordedArtifact>[],
          createdAt: DateTime.utc(2026, 7, 20, 1),
          prePublicationValidator: (path) async {
            stagingPath = path;
            return await _treeContainsSensitiveBytes(path, secret)
                ? validationError
                : null;
          },
        ),
        throwsA(
          isA<CockpitTestBundlePublicationException>().having(
            (error) => error.error,
            'error',
            same(validationError),
          ),
        ),
        reason: source,
      );
      expect(await Directory(finalPath).exists(), isFalse, reason: source);
      expect(await Directory(stagingPath!).exists(), isFalse, reason: source);
    }
  });

  test('preserves typed validator throws and cleans staging', () async {
    final validationError = CockpitTestError(
      code: CockpitTestErrorCode.evidenceFailed,
      message: 'Commit guard rejected the bundle.',
    );
    final validators = <CockpitTestBundlePrePublicationValidator>[
      (_) async => throw validationError,
      (_) async => throw CockpitTestBundlePublicationException(validationError),
    ];
    for (var index = 0; index < validators.length; index += 1) {
      final root = await Directory.systemTemp.createTemp(
        'cockpit-v2-typed-validator-$index-',
      );
      addTearDown(() => root.delete(recursive: true));
      final result = _result(evidence: const <String>[]);
      String? stagingPath;

      await expectLater(
        writer.write(
          rootPath: root.path,
          context: result.context,
          sourceSha256: _hash('2'),
          result: result,
          artifacts: const <CockpitTestRecordedArtifact>[],
          createdAt: DateTime.utc(2026, 7, 20, 1),
          prePublicationValidator: (path) async {
            stagingPath = path;
            return validators[index](path);
          },
        ),
        throwsA(
          isA<CockpitTestBundlePublicationException>().having(
            (error) => error.error,
            'error',
            same(validationError),
          ),
        ),
      );
      expect(await Directory(_bundlePath(root.path)).exists(), isFalse);
      expect(await Directory(stagingPath!).exists(), isFalse);
    }
  });

  test('verification detects artifact tampering', () async {
    final root = await Directory.systemTemp.createTemp('cockpit-v2-tamper-');
    addTearDown(() => root.delete(recursive: true));
    final result = _result(evidence: const <String>['artifact000001']);
    final summary = await writer.write(
      rootPath: root.path,
      context: result.context,
      sourceSha256: _hash('b'),
      result: result,
      artifacts: <CockpitTestRecordedArtifact>[
        CockpitTestRecordedArtifact(
          artifactId: 'artifact000001',
          kind: 'snapshot',
          relativePath: 'snapshots/state.json',
          mediaType: 'application/json',
          stepExecutionId: 'main/verify',
          bytes: utf8.encode('{}'),
        ),
      ],
      createdAt: DateTime.utc(2026, 7, 20, 1),
    );
    await File(
      p.join(summary.path, 'snapshots', 'state.json'),
    ).writeAsString('{"tampered":true}', flush: true);

    await expectLater(
      reader.readAndVerify(path: summary.path),
      throwsA(
        isA<CockpitTestBundleIntegrityException>().having(
          (error) => error.error.code,
          'code',
          CockpitTestErrorCode.bundleIntegrityFailed,
        ),
      ),
    );
  });

  test('publication rejects evidence without a matching artifact', () async {
    final root = await Directory.systemTemp.createTemp('cockpit-v2-index-');
    addTearDown(() => root.delete(recursive: true));
    final result = _result(evidence: const <String>['artifact000001']);

    await expectLater(
      writer.write(
        rootPath: root.path,
        context: result.context,
        sourceSha256: _hash('c'),
        result: result,
        artifacts: const <CockpitTestRecordedArtifact>[],
        createdAt: DateTime.utc(2026, 7, 20, 1),
      ),
      throwsA(isA<CockpitTestBundlePublicationException>()),
    );
    expect(
      Directory(
        p.join(
          root.path,
          'projectOne',
          'workspaceOne',
          'runOne',
          'cases',
          'bundleCase',
          'attempts',
          'attemptOne',
        ),
      ).existsSync(),
      isFalse,
    );
  });

  test('indexes evidence for repeated execution occurrences', () async {
    final root = await Directory.systemTemp.createTemp(
      'cockpit-v2-occurrence-index-',
    );
    addTearDown(() => root.delete(recursive: true));
    final result = _resultWithRepeatedOccurrences();
    final summary = await writer.write(
      rootPath: root.path,
      context: result.context,
      sourceSha256: _hash('d'),
      result: result,
      artifacts: <CockpitTestRecordedArtifact>[
        CockpitTestRecordedArtifact(
          artifactId: 'artifact000001',
          kind: 'screenshot',
          relativePath: 'screenshots/attempt-1.png',
          mediaType: 'image/png',
          stepExecutionId: 'main/retry/retryBack',
          bytes: const <int>[1],
        ),
        CockpitTestRecordedArtifact(
          artifactId: 'artifact000002',
          kind: 'screenshot',
          relativePath: 'screenshots/attempt-2.png',
          mediaType: 'image/png',
          stepExecutionId: 'main/retry/retryBack',
          bytes: const <int>[2],
        ),
      ],
      createdAt: DateTime.utc(2026, 7, 20, 1),
    );

    final manifest = await reader.readAndVerify(path: summary.path);
    expect(manifest.evidenceIndex, hasLength(2));
    expect(manifest.evidenceIndex.map((entry) => entry.stepResultIndex), <int>[
      0,
      1,
    ]);
    expect(
      manifest.evidenceIndex.map((entry) => entry.artifactIds.single),
      <String>['artifact000001', 'artifact000002'],
    );
  });

  test('publication rejects Windows absolute artifact paths', () async {
    final root = await Directory.systemTemp.createTemp(
      'cockpit-v2-windows-path-',
    );
    addTearDown(() => root.delete(recursive: true));
    final result = _result(evidence: const <String>['artifact000001']);

    await expectLater(
      writer.write(
        rootPath: root.path,
        context: result.context,
        sourceSha256: _hash('e'),
        result: result,
        artifacts: <CockpitTestRecordedArtifact>[
          CockpitTestRecordedArtifact(
            artifactId: 'artifact000001',
            kind: 'snapshot',
            relativePath: 'C:/outside/attempt.json',
            mediaType: 'application/json',
            stepExecutionId: 'main/verify',
            bytes: const <int>[1],
          ),
        ],
        createdAt: DateTime.utc(2026, 7, 20, 1),
      ),
      throwsA(isA<CockpitTestBundlePublicationException>()),
    );
  });
}

CockpitTestAttemptResult _result({
  required List<String> evidence,
  CockpitTestError? primaryError,
}) {
  final context = CockpitTestRunContext(
    projectId: 'projectOne',
    workspaceId: 'workspaceOne',
    runId: 'runOne',
    caseId: 'bundleCase',
    attemptId: 'attemptOne',
    engineVersion: '2.0.0',
  );
  return CockpitTestAttemptResult(
    context: context,
    lifecycle: CockpitTestLifecycle.completed,
    outcome: primaryError == null
        ? CockpitTestOutcome.passed
        : CockpitTestOutcome.failed,
    stability: CockpitTestStability.stable,
    startedAt: DateTime.utc(2026, 7, 20),
    finishedAt: DateTime.utc(2026, 7, 20, 0, 0, 1),
    durationMs: 1000,
    targetId: 'deviceOne',
    platform: 'android',
    requestedPlane: CockpitTestPlane.semantic,
    actualPlane: CockpitTestPlane.semantic,
    primaryError: primaryError,
    steps: <CockpitTestStepResult>[
      CockpitTestStepResult(
        stepId: 'verify',
        executionId: 'main/verify',
        section: 'main',
        status: CockpitTestStepStatus.passed,
        startedAt: DateTime.utc(2026, 7, 20),
        durationMs: 10,
        evidence: evidence,
      ),
    ],
  );
}

String _bundlePath(String rootPath) => p.join(rootPath, 'bundle');

Future<bool> _treeContainsSensitiveBytes(String rootPath, String value) async {
  final scanner = CockpitSensitiveByteScanner(<String>[value]);
  await for (final entity in Directory(
    rootPath,
  ).list(recursive: true, followLinks: false)) {
    if (entity is File && await scanner.contains(entity.openRead())) {
      return true;
    }
  }
  return false;
}

String _hash(String character) => List<String>.filled(64, character).join();

CockpitTestAttemptResult _resultWithRepeatedOccurrences() {
  final context = CockpitTestRunContext(
    projectId: 'projectOne',
    workspaceId: 'workspaceOne',
    runId: 'runOne',
    caseId: 'bundleCase',
    attemptId: 'attemptOne',
    engineVersion: '2.0.0',
  );
  CockpitTestStepResult step(int attempt, String artifactId) =>
      CockpitTestStepResult(
        stepId: 'retryBack',
        executionId: 'main/retry/retryBack',
        section: 'main',
        status: CockpitTestStepStatus.passed,
        startedAt: DateTime.utc(2026, 7, 20),
        durationMs: 10,
        occurrence: CockpitTestStepOccurrence(retryAttempt: attempt),
        evidence: <String>[artifactId],
      );
  return CockpitTestAttemptResult(
    context: context,
    lifecycle: CockpitTestLifecycle.completed,
    outcome: CockpitTestOutcome.passed,
    stability: CockpitTestStability.flaky,
    startedAt: DateTime.utc(2026, 7, 20),
    finishedAt: DateTime.utc(2026, 7, 20, 0, 0, 1),
    durationMs: 1000,
    targetId: 'deviceOne',
    platform: 'android',
    requestedPlane: CockpitTestPlane.semantic,
    actualPlane: CockpitTestPlane.semantic,
    steps: <CockpitTestStepResult>[
      step(1, 'artifact000001'),
      step(2, 'artifact000002'),
    ],
  );
}
