import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('conjunctive locator round-trips every native relation', () {
    final locator = CockpitTestLocator.fromJson(<String, Object?>{
      'text': 'Save',
      'matchMode': 'contains',
      'role': 'button',
      'enabled': true,
      'ancestor': <String, Object?>{'label': 'Editor'},
      'descendant': <String, Object?>{'text': 'Shortcut'},
      'below': <String, Object?>{'testId': 'heading'},
      'fallbacks': <Object?>[
        <String, Object?>{'nativeId': 'save-button'},
      ],
    }, path: r'$.locator');

    expect(
      CockpitTestLocator.fromJson(locator.toJson(), path: r'$.locator'),
      locator,
    );
    expect(locator.signalMap, <String, String>{
      'text': 'Save',
      'role': 'button',
    });
    expect(locator.matchMode, CockpitTextMatchMode.contains);
  });

  test('fuzzy text matching tolerates typos but rejects short guesses', () {
    final locator = CockpitTestLocator.fromJson(<String, Object?>{
      'text': 'Svae task',
      'matchMode': 'fuzzy',
    }, path: r'$.locator');

    expect(locator.matchMode, CockpitTextMatchMode.fuzzy);
    expect(cockpitFuzzyTextMatches('Save task', locator.text!), isTrue);
    expect(
      cockpitFuzzyTextMatches('Open task Selector proof', 'Selctor proof'),
      isTrue,
    );
    expect(
      cockpitFuzzyTextMatches('Delete account', 'Create profile'),
      isFalse,
    );
    expect(cockpitFuzzyTextMatches('OK', 'KO'), isFalse);
  });

  test('public diagnostics, results, bundles, and imports round-trip', () {
    final location = CockpitTestSourceLocation(
      line: 3,
      column: 5,
      endLine: 3,
      endColumn: 18,
    );
    _expectRoundTrip(
      CockpitTestSourceMapEntry(path: r'$.steps[0]', location: location),
      CockpitTestSourceMapEntry.fromJson,
    );
    _expectRoundTrip(
      CockpitTestDiagnostic(
        code: 'invalidStep',
        message: 'The step is invalid.',
        path: r'$.steps[0]',
        location: location,
        details: <String, Object?>{'limit': 10},
      ),
      CockpitTestDiagnostic.fromJson,
    );

    final context = CockpitTestRunContext(
      projectId: 'projectA',
      workspaceId: 'workspaceA',
      runId: 'runA',
      caseId: 'caseA',
      attemptId: 'attemptA',
      engineVersion: '2.0.0',
    );
    final step = CockpitTestStepResult(
      stepId: 'tapContinue',
      executionId: 'main/tapContinue',
      section: 'main',
      status: CockpitTestStepStatus.passed,
      startedAt: DateTime.utc(2026, 7, 20, 1, 2, 3),
      durationMs: 42,
      occurrence: CockpitTestStepOccurrence(
        retryAttempt: 2,
        callPath: const <String>['loginCall'],
      ),
      sourceLocation: location,
      requestedPlane: CockpitTestPlane.semantic,
      actualPlane: CockpitTestPlane.semantic,
      driverId: 'flutterDriver',
      locatorResolution: const CockpitLocatorResolution(
        matchedKind: CockpitLocatorKind.cockpitId,
        matchedValue: 'continueButton',
        matchedSignals: <String, String>{'cockpitId': 'continueButton'},
      ),
      degradationReason: 'semanticTargetRecovered',
      evidence: const <String>['artifact000001'],
    );
    _expectRoundTrip(step, CockpitTestStepResult.fromJson);

    final result = CockpitTestAttemptResult(
      context: context,
      lifecycle: CockpitTestLifecycle.completed,
      outcome: CockpitTestOutcome.passed,
      stability: CockpitTestStability.stable,
      startedAt: DateTime.utc(2026, 7, 20, 1, 2, 3),
      finishedAt: DateTime.utc(2026, 7, 20, 1, 2, 4),
      durationMs: 1000,
      targetId: 'device-1',
      platform: 'android',
      requestedPlane: CockpitTestPlane.semantic,
      actualPlane: CockpitTestPlane.semantic,
      steps: <CockpitTestStepResult>[step],
      bundlePath: '/tmp/attemptA',
    );
    _expectRoundTrip(result, CockpitTestAttemptResult.fromJson);

    final artifact = CockpitTestArtifactEntry(
      artifactId: 'artifact000001',
      kind: 'screenshot',
      relativePath: 'artifacts/continue.png',
      mediaType: 'image/png',
      sizeBytes: 3,
      sha256: _hash('a'),
      stepExecutionId: 'main/tapContinue',
    );
    final manifest = CockpitTestAttemptBundleManifest(
      context: context,
      sourceSha256: _hash('b'),
      createdAt: DateTime.utc(2026, 7, 20, 1, 2, 4),
      result: result,
      artifacts: <CockpitTestArtifactEntry>[artifact],
      evidenceIndex: <CockpitTestEvidenceIndexEntry>[
        CockpitTestEvidenceIndexEntry(
          stepResultIndex: 0,
          stepExecutionId: 'main/tapContinue',
          artifactIds: const <String>['artifact000001'],
        ),
      ],
    );
    _expectRoundTrip(manifest, CockpitTestAttemptBundleManifest.fromJson);
    _expectRoundTrip(
      CockpitTestBundleSummary(
        path: '/tmp/attemptA',
        manifestSha256: _hash('c'),
        artifactCount: 1,
      ),
      CockpitTestBundleSummary.fromJson,
    );

    final testCase = CockpitTestCase(
      id: 'caseA',
      target: CockpitTestTargetRequirements(
        platform: 'android',
        targetKind: 'flutterApp',
        plane: CockpitTestPlane.semantic,
      ),
      steps: <CockpitTestStepTemplate>[
        CockpitTestStepTemplate(
          stepId: 'goBack',
          operation: CockpitTestActionOperationTemplate(
            CockpitTestActionTemplate(kind: CockpitTestActionKind.back),
          ),
        ),
      ],
    );
    final importManifest = CockpitTestImportManifest(
      sourceVersion: 1,
      sourceSha256: _hash('d'),
      projectId: 'projectA',
      workspaceId: 'workspaceA',
      caseId: 'caseA',
      engineVersion: '2.0.0',
      mappings: <CockpitTestImportMapping>[
        CockpitTestImportMapping(
          sourcePath: r'$.steps[0]',
          destinationPath: r'$.steps[0]',
        ),
      ],
      warnings: const <String>['Session identity was discarded.'],
    );
    _expectRoundTrip(importManifest, CockpitTestImportManifest.fromJson);
    _expectRoundTrip(
      CockpitTestImportResult(testCase: testCase, manifest: importManifest),
      CockpitTestImportResult.fromJson,
    );

    const sourceText = '  {"schemaVersion":1}\n';
    final request = CockpitTestImportRequest(
      sourceVersion: 1,
      sourceText: sourceText,
      projectId: 'projectA',
      workspaceId: 'workspaceA',
      caseId: 'caseA',
      engineVersion: '2.0.0',
    );
    final decodedRequest = CockpitTestImportRequest.fromJson(request.toJson());
    expect(decodedRequest.toJson(), request.toJson());
    expect(decodedRequest.sourceText, sourceText);

    final conditionError = CockpitTestError(
      code: CockpitTestErrorCode.conditionError,
      message: 'Condition failed to evaluate.',
    );
    _expectRoundTrip(
      CockpitTestConditionEvaluation.error(conditionError),
      CockpitTestConditionEvaluation.fromJson,
    );
    _expectRoundTrip(
      const CockpitTestConditionEvaluation.matched(),
      CockpitTestConditionEvaluation.fromJson,
    );
  });

  test('artifact entries reject Windows path forms', () {
    for (final relativePath in const <String>[
      'C:/outside.png',
      r'C:outside.png',
      r'\\server\share\outside.png',
    ]) {
      expect(
        () => CockpitTestArtifactEntry(
          artifactId: 'artifact000001',
          kind: 'screenshot',
          relativePath: relativePath,
          mediaType: 'image/png',
          sizeBytes: 1,
          sha256: _hash('a'),
        ),
        throwsFormatException,
        reason: relativePath,
      );
    }
  });

  test('public result and bundle invariants reject inconsistent input', () {
    expect(
      () => CockpitTestConditionEvaluation.fromJson(<String, Object?>{
        'state': 'matched',
        'error': <String, Object?>{
          'code': 'conditionError',
          'message': 'Unexpected error.',
        },
      }),
      throwsFormatException,
    );
    expect(
      () => CockpitTestStepResult.fromJson(<String, Object?>{
        'stepId': 'badStep',
        'executionId': 'main/badStep',
        'section': 'main',
        'status': 'failed',
        'startedAt': '2026-07-20T01:02:03.000Z',
        'durationMs': 1,
        'occurrence': <String, Object?>{},
      }),
      throwsFormatException,
    );
    expect(
      () => CockpitTestStepResult(
        stepId: 'badStep',
        executionId: 'main/badStep',
        section: 'main',
        status: CockpitTestStepStatus.passed,
        startedAt: DateTime.utc(2026, 7, 20),
        durationMs: 1,
        degradationReason: List<String>.filled(513, 'x').join(),
      ),
      throwsFormatException,
    );
  });
}

void _expectRoundTrip<T>(T value, T Function(Object?, {String path}) fromJson) {
  final json = (value as dynamic).toJson() as Map<String, Object?>;
  expect((fromJson(json) as dynamic).toJson(), json);
}

String _hash(String character) => List<String>.filled(64, character).join();
