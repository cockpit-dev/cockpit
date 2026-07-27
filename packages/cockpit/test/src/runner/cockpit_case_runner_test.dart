import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/cockpit.dart';
import 'package:cockpit/src/artifacts/cockpit_test_attempt_recorder.dart';
import 'package:cockpit/src/runner/cockpit_case_driver_delegate.dart';
import 'package:cockpit/src/runner/cockpit_case_operation_lease.dart';
import 'package:cockpit/src/test/cockpit_test_action_lowerer.dart';
import 'package:cockpit/src/test/cockpit_test_execution_plan.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

import '../support/cockpit_case_runner_test_support.dart';
import '../support/cockpit_case_runtime_test_support.dart';

void main() {
  const compiler = CockpitTestDocumentCompiler();

  test(
    'runner resolves secrets only at dispatch and publishes redacted bundle',
    () async {
      final root = await Directory.systemTemp.createTemp('cockpit-v2-runner-');
      addTearDown(() => root.delete(recursive: true));
      final adapter = RecordingAutomationAdapter();
      final resolver = RecordingSecretResolver('plain-secret-value');
      final safety = RecordingSafetyPolicy();
      final compiled = compiler.compile(_secretCase()).requireCase();
      final result = await _runner(adapter, resolver, safety).run(
        compiled: compiled,
        context: _context('secretCase'),
        targetId: 'emulatorOne',
        targetEnvironment: CockpitTestTargetEnvironment.test,
        reportRoot: root.path,
      );

      expect(result.outcome, CockpitTestOutcome.passed);
      expect(result.stability, CockpitTestStability.stable);
      expect(adapter.commands, hasLength(1));
      expect(adapter.commands.single.parameters['text'], 'plain-secret-value');
      expect(resolver.references, <String>['env:PASSWORD']);
      expect(
        safety.requests.map((request) => request.phase),
        <CockpitTestSafetyPhase>[
          CockpitTestSafetyPhase.preflight,
          CockpitTestSafetyPhase.dispatch,
        ],
      );
      for (final request in safety.requests) {
        final encoded = jsonEncode(request.action.toJson());
        expect(encoded, isNot(contains('plain-secret-value')));
        expect(encoded, isNot(contains('env:PASSWORD')));
      }
      final manifest = await const CockpitTestAttemptBundleReader()
          .readAndVerify(path: result.bundlePath!);
      final encodedManifest = jsonEncode(manifest.toJson());
      expect(encodedManifest, isNot(contains('plain-secret-value')));
      expect(encodedManifest, isNot(contains('env:PASSWORD')));
      expect(encodedManifest, isNot(contains('taskId')));
      expect(manifest.artifacts, isEmpty);
    },
  );

  test(
    'dispatch safety denial blocks before secret resolution and driver call',
    () async {
      final root = await Directory.systemTemp.createTemp('cockpit-v2-safety-');
      addTearDown(() => root.delete(recursive: true));
      final adapter = RecordingAutomationAdapter();
      final resolver = RecordingSecretResolver('plain-secret-value');
      final safety = RecordingSafetyPolicy(denyDispatch: true);
      final result = await _runner(adapter, resolver, safety).run(
        compiled: compiler.compile(_secretCase()).requireCase(),
        context: _context('secretCase'),
        targetId: 'emulatorOne',
        targetEnvironment: CockpitTestTargetEnvironment.test,
        reportRoot: root.path,
      );

      expect(result.outcome, CockpitTestOutcome.blocked);
      expect(result.primaryError?.code, CockpitTestErrorCode.safetyDenied);
      expect(adapter.commands, isEmpty);
      expect(resolver.references, isEmpty);
      expect(result.bundlePath, isNotNull);
    },
  );

  test('runner rejects non-V2 target kind without dispatch', () async {
    final root = await Directory.systemTemp.createTemp('cockpit-v2-target-');
    addTearDown(() => root.delete(recursive: true));
    final adapter = RecordingAutomationAdapter();
    final result =
        await _runner(
          adapter,
          RecordingSecretResolver('unused'),
          RecordingSafetyPolicy(),
        ).run(
          compiled: compiler
              .compile(_simpleCase(targetKind: 'app'))
              .requireCase(),
          context: _context('simpleCase'),
          targetId: 'emulatorOne',
          targetEnvironment: CockpitTestTargetEnvironment.test,
          reportRoot: root.path,
        );

    expect(result.outcome, CockpitTestOutcome.blocked);
    expect(result.primaryError?.code, CockpitTestErrorCode.targetMismatch);
    expect(adapter.commands, isEmpty);
  });

  test('system runner accepts a Flutter app on the native plane', () async {
    final root = await Directory.systemTemp.createTemp(
      'cockpit-v2-flutter-native-',
    );
    addTearDown(() => root.delete(recursive: true));
    final adapter = RecordingAutomationAdapter();
    final result =
        await _runner(
          adapter,
          RecordingSecretResolver('unused'),
          RecordingSafetyPolicy(),
          lowerer: const CockpitTestActionLowerer.system(),
        ).run(
          compiled: compiler
              .compile(_simpleCase(targetKind: 'flutterApp', plane: 'native'))
              .requireCase(),
          context: _context('simpleCase'),
          targetId: 'emulatorOne',
          targetEnvironment: CockpitTestTargetEnvironment.test,
          reportRoot: root.path,
        );

    expect(result.outcome, CockpitTestOutcome.passed);
    expect(adapter.commands, hasLength(1));
  });

  test('preparation failure publication preserves validator error', () async {
    final root = await Directory.systemTemp.createTemp(
      'cockpit-v2-preparation-guard-',
    );
    addTearDown(() => root.delete(recursive: true));
    final validationError = CockpitTestError(
      code: CockpitTestErrorCode.bundlePublicationFailed,
      message: 'Preparation bundle failed commit validation.',
      details: const <String, Object?>{'reason': 'commitGuardRejected'},
    );
    var validationCount = 0;
    final result =
        await _runner(
          RecordingAutomationAdapter(),
          RecordingSecretResolver('unused'),
          RecordingSafetyPolicy(),
          bundlePrePublicationValidator: (_) async {
            validationCount += 1;
            return validationError;
          },
        ).run(
          compiled: compiler
              .compile(_simpleCase(targetKind: 'app'))
              .requireCase(),
          context: _context('simpleCase'),
          targetId: 'emulatorOne',
          targetEnvironment: CockpitTestTargetEnvironment.test,
          reportRoot: root.path,
        );

    expect(validationCount, 1);
    expect(result.primaryError?.code, CockpitTestErrorCode.targetMismatch);
    expect(result.cleanupErrors, hasLength(1));
    expect(result.cleanupErrors.single, same(validationError));
    expect(result.bundlePath, isNull);
  });

  test('successful retry marks the attempt flaky', () async {
    final root = await Directory.systemTemp.createTemp('cockpit-v2-retry-');
    addTearDown(() => root.delete(recursive: true));
    final adapter = RecordingAutomationAdapter(outcomes: <bool>[false, true]);
    final result =
        await _runner(
          adapter,
          RecordingSecretResolver('unused'),
          RecordingSafetyPolicy(),
        ).run(
          compiled: compiler.compile(_retryCase()).requireCase(),
          context: _context('retryCase'),
          targetId: 'emulatorOne',
          targetEnvironment: CockpitTestTargetEnvironment.test,
          reportRoot: root.path,
        );

    expect(result.outcome, CockpitTestOutcome.passed);
    expect(result.stability, CockpitTestStability.flaky);
    expect(adapter.commands, hasLength(2));
    expect(
      result.steps
          .where((step) => step.stepId == 'retryBack')
          .map((step) => step.occurrence.retryAttempt),
      <int?>[1, 2],
    );
  });

  test('revoked driver operation aborts and rejects late artifacts', () async {
    final clock = ManualCockpitClock();
    final adapter = _HangingAbortableAutomationAdapter();
    final recorder = CockpitTestAttemptRecorder(clock: clock);
    final node = actionNode('lateAction', 'main');
    final plan = testExecutionPlan(steps: <CockpitTestExecutionNode>[node]);
    final delegate = CockpitCaseDriverDelegate(
      automationAdapter: adapter,
      secretResolver: RecordingSecretResolver('unused'),
      safetyPolicy: RecordingSafetyPolicy(),
      lowerer: const CockpitTestActionLowerer(),
      recorder: recorder,
      runContext: _context('runtimeCase'),
      plan: plan,
      capabilities: await adapter.describeCapabilities(),
      targetEnvironment: CockpitTestTargetEnvironment.test,
    );
    final lease = CockpitCaseOperationLease();
    final operation = delegate.executeAction(
      node: node,
      action: (node.operation as CockpitTestActionPlanOperation).action,
      timeout: const Duration(milliseconds: 50),
      cleanup: false,
      lease: lease,
    );
    await _pump();

    lease.revoke(requestAbort: true);
    adapter.completeWithArtifact();
    await operation;
    await _pump();

    expect(adapter.abortCount, 1);
    expect(recorder.artifacts, isEmpty);
  });

  test('runner deadline revokes the active driver operation', () async {
    final root = await Directory.systemTemp.createTemp('cockpit-v2-timeout-');
    addTearDown(() => root.delete(recursive: true));
    final clock = ManualCockpitClock();
    final adapter = _HangingAbortableAutomationAdapter();
    final future =
        CockpitCaseRunner(
          automationAdapter: adapter,
          secretResolver: RecordingSecretResolver('unused'),
          safetyPolicy: RecordingSafetyPolicy(),
          clock: clock,
        ).run(
          compiled: compiler.compile(_timedCase()).requireCase(),
          context: _context('timedCase'),
          targetId: 'emulatorOne',
          targetEnvironment: CockpitTestTargetEnvironment.test,
          reportRoot: root.path,
        );
    for (var index = 0; index < 20 && adapter.command == null; index += 1) {
      await _pump();
    }
    expect(adapter.command, isNotNull);

    clock.elapse(const Duration(milliseconds: 50));
    final result = await future;
    adapter.completeWithArtifact();
    await _pump();

    expect(result.primaryError?.code, CockpitTestErrorCode.timeout);
    expect(adapter.abortCount, 1);
  });

  test('revoked screenshot evidence does not start snapshot work', () async {
    final clock = ManualCockpitClock();
    final automation = RecordingAutomationAdapter();
    final capture = _HangingCaptureAdapter();
    final recorder = CockpitTestAttemptRecorder(clock: clock);
    final node = CockpitTestExecutionNode(
      stepId: 'collectEvidence',
      executionId: 'main/collectEvidence',
      section: 'main',
      timeoutMs: 1000,
      evidence: const CockpitTestEvidencePolicy(
        screenshot: CockpitTestEvidenceMode.always,
        snapshot: CockpitTestEvidenceMode.always,
      ),
      safety: CockpitTestSafetyDeclaration(),
      sourcePath: r'$.steps[0]',
      operation: CockpitTestActionPlanOperation(
        CockpitTestAction(kind: CockpitTestActionKind.back),
      ),
    );
    final plan = testExecutionPlan(steps: <CockpitTestExecutionNode>[node]);
    final delegate = CockpitCaseDriverDelegate(
      automationAdapter: automation,
      captureAdapter: capture,
      secretResolver: RecordingSecretResolver('unused'),
      safetyPolicy: RecordingSafetyPolicy(),
      lowerer: const CockpitTestActionLowerer(),
      recorder: recorder,
      runContext: _context('runtimeCase'),
      plan: plan,
      capabilities: await automation.describeCapabilities(),
      targetEnvironment: CockpitTestTargetEnvironment.test,
    );
    final lease = CockpitCaseOperationLease();
    final operation = delegate.executeAction(
      node: node,
      action: (node.operation as CockpitTestActionPlanOperation).action,
      timeout: const Duration(seconds: 1),
      cleanup: false,
      lease: lease,
    );
    for (var index = 0; index < 20 && capture.command == null; index += 1) {
      await _pump();
    }
    expect(capture.command, isNotNull);

    lease.revoke(requestAbort: true);
    capture.fail();
    await operation;

    expect(capture.abortCount, 1);
    expect(automation.commands, hasLength(1));
  });

  test('failed recording stop remains eligible for residual cleanup', () async {
    final clock = ManualCockpitClock();
    final automation = RecordingAutomationAdapter();
    final recording = _FailOnceRecordingAdapter();
    final recorder = CockpitTestAttemptRecorder(clock: clock);
    final plan = testExecutionPlan(
      steps: <CockpitTestExecutionNode>[actionNode('unused', 'main')],
    );
    final delegate = CockpitCaseDriverDelegate(
      automationAdapter: automation,
      recordingAdapter: recording,
      secretResolver: RecordingSecretResolver('unused'),
      safetyPolicy: RecordingSafetyPolicy(),
      lowerer: const CockpitTestActionLowerer(),
      recorder: recorder,
      runContext: _context('runtimeCase'),
      plan: plan,
      capabilities: await automation.describeCapabilities(),
      targetEnvironment: CockpitTestTargetEnvironment.test,
    );
    final startNode = CockpitTestExecutionNode(
      stepId: 'startRecording',
      executionId: 'setup/startRecording',
      section: 'setup',
      timeoutMs: 1000,
      evidence: const CockpitTestEvidencePolicy(),
      safety: CockpitTestSafetyDeclaration(),
      sourcePath: r'$.setup[0]',
      operation: const CockpitTestStartRecordingPlanOperation(
        name: 'acceptance',
        purpose: 'acceptance',
        mode: 'auto',
        allowFallback: false,
        attachToStep: true,
      ),
    );
    final stopNode = CockpitTestExecutionNode(
      stepId: 'stopRecording',
      executionId: 'main/stopRecording',
      section: 'main',
      timeoutMs: 1000,
      evidence: const CockpitTestEvidencePolicy(),
      safety: CockpitTestSafetyDeclaration(),
      sourcePath: r'$.steps[0]',
      operation: const CockpitTestStopRecordingPlanOperation(settleMs: 0),
    );
    final started = await delegate.startRecording(
      node: startNode,
      operation: startNode.operation as CockpitTestStartRecordingPlanOperation,
      timeout: const Duration(seconds: 1),
      cleanup: false,
      lease: CockpitCaseOperationLease(),
    );
    expect(started.isSuccess, isTrue);

    final stopped = await delegate.stopRecording(
      node: stopNode,
      operation: stopNode.operation as CockpitTestStopRecordingPlanOperation,
      timeout: const Duration(seconds: 1),
      cleanup: false,
      lease: CockpitCaseOperationLease(),
    );
    expect(stopped.error?.code, CockpitTestErrorCode.recordingFailed);
    expect(delegate.residualCleanupNode, isNotNull);

    final cleanup = await delegate.cleanupResidual(
      timeout: const Duration(seconds: 1),
      lease: CockpitCaseOperationLease(),
    );
    expect(cleanup.isSuccess, isTrue);
    expect(recording.stopCount, 2);
    expect(delegate.residualCleanupNode, isNull);
  });
}

CockpitCaseRunner _runner(
  RecordingAutomationAdapter adapter,
  RecordingSecretResolver resolver,
  RecordingSafetyPolicy safety, {
  CockpitTestBundlePrePublicationValidator? bundlePrePublicationValidator,
  CockpitTestActionLowerer lowerer = const CockpitTestActionLowerer(),
}) => CockpitCaseRunner(
  automationAdapter: adapter,
  secretResolver: resolver,
  safetyPolicy: safety,
  lowerer: lowerer,
  bundlePrePublicationValidator: bundlePrePublicationValidator,
  clock: ManualCockpitClock(),
);

CockpitTestRunContext _context(String caseId) => CockpitTestRunContext(
  projectId: 'projectOne',
  workspaceId: 'workspaceOne',
  runId: 'runOne',
  caseId: caseId,
  attemptId: 'attemptOne',
  engineVersion: '2.0.0',
);

String _secretCase() => '''
schemaVersion: cockpit.test/v2
kind: case
id: secretCase
target: {platform: android, targetKind: flutterApp, plane: semantic}
defaults:
  evidence: {screenshot: none, snapshot: none, failurePolicy: failStep}
variables:
  password: {source: secret, type: string, reference: env:PASSWORD}
steps:
  - stepId: enterPassword
    safety: {effects: [credentialSensitive], reason: Test authentication}
    action: {type: enterText, text: {\$var: password}}
''';

String _simpleCase({required String targetKind, String plane = 'semantic'}) =>
    '''
schemaVersion: cockpit.test/v2
kind: case
id: simpleCase
target: {platform: android, targetKind: $targetKind, plane: $plane}
steps:
  - {stepId: goBack, action: {type: back}}
''';

String _retryCase() => '''
schemaVersion: cockpit.test/v2
kind: case
id: retryCase
target: {platform: android, targetKind: flutterApp, plane: semantic}
defaults:
  evidence: {screenshot: none, snapshot: none, failurePolicy: failStep}
steps:
  - stepId: retryControl
    retry:
      maxAttempts: 2
      steps:
        - {stepId: retryBack, action: {type: back}}
''';

String _timedCase() => '''
schemaVersion: cockpit.test/v2
kind: case
id: timedCase
target: {platform: android, targetKind: flutterApp, plane: semantic}
defaults:
  commandTimeoutMs: 50
  evidence: {screenshot: none, snapshot: none, failurePolicy: failStep}
steps:
  - {stepId: lateAction, action: {type: back}}
''';

Future<void> _pump() async {
  await Future<void>.value();
  await Future<void>.value();
}

final class _HangingAbortableAutomationAdapter
    implements CockpitAutomationAdapter, CockpitActiveOperationAborter {
  final Completer<CockpitCommandExecution> _execution =
      Completer<CockpitCommandExecution>();
  CockpitCommand? command;
  int abortCount = 0;

  @override
  Future<void> abortActiveOperation() async {
    abortCount += 1;
  }

  @override
  Future<CockpitCapabilities> describeCapabilities() async =>
      CockpitCapabilities(
        platform: 'android',
        transportType: 'inApp',
        supportsInAppControl: true,
        supportsFlutterViewCapture: true,
        supportsNativeScreenCapture: false,
        supportsHostAutomation: false,
        supportedCommands: CockpitCommandType.values,
        supportedLocatorStrategies: CockpitLocatorKind.values,
      );

  @override
  Future<CockpitCommandExecution> execute(CockpitCommand command) {
    this.command = command;
    return _execution.future;
  }

  void completeWithArtifact() {
    final activeCommand = command!;
    const path = 'late/action.json';
    _execution.complete(
      CockpitCommandExecution(
        result: CockpitCommandResult(
          success: true,
          commandId: activeCommand.commandId,
          commandType: activeCommand.commandType,
          durationMs: 100,
          artifacts: const <CockpitArtifactRef>[
            CockpitArtifactRef(role: 'late', relativePath: path),
          ],
        ),
        artifactPayloads: const <String, List<int>>{
          path: <int>[1, 2, 3],
        },
      ),
    );
  }
}

final class _HangingCaptureAdapter
    implements CockpitCaptureAdapter, CockpitActiveOperationAborter {
  final Completer<CockpitCommandExecution> _capture =
      Completer<CockpitCommandExecution>();
  CockpitCommand? command;
  int abortCount = 0;

  @override
  Future<void> abortActiveOperation() async {
    abortCount += 1;
  }

  @override
  Future<CockpitCommandExecution> capture(CockpitCommand command) {
    this.command = command;
    return _capture.future;
  }

  void fail() {
    _capture.completeError(StateError('Capture was aborted.'));
  }
}

final class _FailOnceRecordingAdapter implements CockpitRecordingAdapter {
  int stopCount = 0;

  @override
  Future<CockpitRecordingSession> startRecording(
    CockpitRecordingRequest request,
  ) async => CockpitRecordingSession(
    request: request,
    state: CockpitRecordingState.recording,
  );

  @override
  Future<CockpitRecordingResult> stopRecording() async {
    stopCount += 1;
    if (stopCount == 1) {
      throw StateError('First stop attempt failed.');
    }
    return CockpitRecordingResult(state: CockpitRecordingState.completed);
  }
}
