import 'dart:async';

import 'package:cockpit/cockpit.dart';
import 'package:cockpit/src/artifacts/cockpit_test_attempt_recorder.dart';
import 'package:cockpit/src/runner/cockpit_case_execution_kernel.dart';
import 'package:cockpit/src/test/cockpit_test_execution_plan.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

import '../support/cockpit_case_runtime_test_support.dart';

void main() {
  test(
    'failFast false preserves setup failure and still runs main/finally',
    () async {
      final clock = ManualCockpitClock();
      final delegate = DeterministicCaseDelegate()
        ..actionResults['setupFailure'] = <CockpitTestKernelOperationResult>[
          CockpitTestKernelOperationResult.failure(
            testDriverError('setupFailure'),
          ),
        ]
        ..actionResults['cleanupFailure'] = <CockpitTestKernelOperationResult>[
          CockpitTestKernelOperationResult.failure(
            testDriverError('cleanupFailure'),
          ),
        ];
      final recorder = CockpitTestAttemptRecorder(clock: clock);
      final result = await _kernel(clock, delegate, recorder).run(
        plan: testExecutionPlan(
          setup: <CockpitTestExecutionNode>[
            actionNode('setupFailure', 'setup'),
          ],
          steps: <CockpitTestExecutionNode>[actionNode('mainAction', 'main')],
          finallySteps: <CockpitTestExecutionNode>[
            actionNode('cleanupFailure', 'finally'),
          ],
          failFast: false,
        ),
        control: CockpitCaseExecutionControl(),
      );

      expect(result.primaryError?.stepId, 'setupFailure');
      expect(result.cleanupErrors.map((error) => error.stepId), <String?>[
        'cleanupFailure',
      ]);
      expect(delegate.events, <String>[
        'action:setupFailure:primary',
        'action:mainAction:primary',
        'action:cleanupFailure:cleanup',
        'cleanup:residual',
      ]);
    },
  );

  test('conditions distinguish matched, notMatched, and error', () async {
    final clock = ManualCockpitClock();
    final delegate = DeterministicCaseDelegate()
      ..conditionResults.addAll(<CockpitTestKernelConditionResult>[
        const CockpitTestKernelConditionResult(
          evaluation: CockpitTestConditionEvaluation.matched(),
        ),
        const CockpitTestKernelConditionResult(
          evaluation: CockpitTestConditionEvaluation.notMatched(),
        ),
        CockpitTestKernelConditionResult(
          evaluation: CockpitTestConditionEvaluation.error(
            CockpitTestError(
              code: CockpitTestErrorCode.conditionError,
              message: 'Condition transport failed.',
              stepId: 'errorIf',
            ),
          ),
        ),
      ]);
    final recorder = CockpitTestAttemptRecorder(clock: clock);
    final result = await _kernel(clock, delegate, recorder).run(
      plan: testExecutionPlan(
        failFast: false,
        steps: <CockpitTestExecutionNode>[
          _ifNode('matchedIf', 'matchedThen', 'matchedElse'),
          _ifNode('notMatchedIf', 'notMatchedThen', 'notMatchedElse'),
          _ifNode('errorIf', 'errorThen', 'errorElse'),
        ],
      ),
      control: CockpitCaseExecutionControl(),
    );

    expect(result.primaryError?.code, CockpitTestErrorCode.conditionError);
    expect(delegate.events, contains('action:matchedThen:primary'));
    expect(delegate.events, contains('action:notMatchedElse:primary'));
    expect(delegate.events, isNot(contains('action:errorThen:primary')));
    expect(delegate.events, isNot(contains('action:errorElse:primary')));
  });

  test('failed steps record the effective requested plane', () async {
    final clock = ManualCockpitClock();
    final delegate = DeterministicCaseDelegate()
      ..actionResults['nativeFailure'] = <CockpitTestKernelOperationResult>[
        CockpitTestKernelOperationResult.failure(
          testDriverError('nativeFailure'),
        ),
      ];
    final recorder = CockpitTestAttemptRecorder(clock: clock);

    final result = await _kernel(clock, delegate, recorder).run(
      plan: testExecutionPlan(
        steps: <CockpitTestExecutionNode>[
          actionNode('nativeFailure', 'main', plane: CockpitTestPlane.native),
        ],
      ),
      control: CockpitCaseExecutionControl(),
    );

    expect(result.outcome, CockpitTestOutcome.failed);
    expect(
      recorder.steps
          .singleWhere((step) => step.stepId == 'nativeFailure')
          .requestedPlane,
      CockpitTestPlane.native,
    );
  });

  test(
    'stalled condition probe does not consume its parent step deadline',
    () async {
      final clock = ManualCockpitClock();
      final delegate = DeterministicCaseDelegate();
      delegate.hangingConditions['stalledIf'] =
          Completer<CockpitTestKernelConditionResult>();
      final recorder = CockpitTestAttemptRecorder(clock: clock);
      final future = _kernel(clock, delegate, recorder).run(
        plan: testExecutionPlan(
          steps: <CockpitTestExecutionNode>[
            _controlNode(
              'stalledIf',
              CockpitTestIfPlanOperation(
                condition: _visibleCondition(),
                thenSteps: <CockpitTestExecutionNode>[
                  actionNode('stalledThen', 'main'),
                ],
                elseSteps: <CockpitTestExecutionNode>[
                  actionNode('stalledElse', 'main'),
                ],
              ),
              timeoutMs: 10000,
            ),
          ],
        ),
        control: CockpitCaseExecutionControl(),
      );

      await _pump();
      expect(
        delegate.conditionTimeouts['stalledIf'],
        const Duration(milliseconds: 500),
      );
      clock.elapse(const Duration(milliseconds: 6500));
      final result = await future;

      expect(result.primaryError?.code, CockpitTestErrorCode.conditionError);
      expect(clock.elapsed, const Duration(milliseconds: 6500));
      expect(delegate.events, isNot(contains('action:stalledThen:primary')));
      expect(delegate.events, isNot(contains('action:stalledElse:primary')));
    },
  );

  test('condition probe timeout follows the requested plane', () async {
    final clock = ManualCockpitClock();
    final delegate = DeterministicCaseDelegate()
      ..conditionResults.addAll(
        List<CockpitTestKernelConditionResult>.filled(
          5,
          const CockpitTestKernelConditionResult(
            evaluation: CockpitTestConditionEvaluation.matched(),
          ),
        ),
      );
    final recorder = CockpitTestAttemptRecorder(clock: clock);
    final result = await _kernel(clock, delegate, recorder).run(
      plan: testExecutionPlan(
        steps: <CockpitTestExecutionNode>[
          _ifNode('semanticIf', 'semanticThen', 'semanticElse'),
          _controlNode(
            'nativeIf',
            CockpitTestIfPlanOperation(
              condition: _visibleCondition(),
              thenSteps: const <CockpitTestExecutionNode>[],
              elseSteps: const <CockpitTestExecutionNode>[],
            ),
            plane: CockpitTestPlane.native,
            timeoutMs: 30000,
          ),
          _controlNode(
            'visualIf',
            CockpitTestIfPlanOperation(
              condition: _visibleCondition(),
              thenSteps: const <CockpitTestExecutionNode>[],
              elseSteps: const <CockpitTestExecutionNode>[],
            ),
            plane: CockpitTestPlane.visual,
            timeoutMs: 30000,
          ),
          _controlNode(
            'coordinateIf',
            CockpitTestIfPlanOperation(
              condition: _visibleCondition(),
              thenSteps: const <CockpitTestExecutionNode>[],
              elseSteps: const <CockpitTestExecutionNode>[],
            ),
            plane: CockpitTestPlane.coordinate,
            timeoutMs: 30000,
          ),
          _controlNode(
            'boundedNativeIf',
            CockpitTestIfPlanOperation(
              condition: _visibleCondition(),
              thenSteps: const <CockpitTestExecutionNode>[],
              elseSteps: const <CockpitTestExecutionNode>[],
            ),
            plane: CockpitTestPlane.native,
            timeoutMs: 8000,
          ),
        ],
      ),
      control: CockpitCaseExecutionControl(),
    );

    expect(result.outcome, CockpitTestOutcome.passed);
    expect(
      delegate.conditionTimeouts,
      containsPair('semanticIf', const Duration(milliseconds: 500)),
    );
    for (final id in <String>['nativeIf', 'visualIf', 'coordinateIf']) {
      expect(
        delegate.conditionTimeouts,
        containsPair(id, const Duration(seconds: 15)),
      );
    }
    expect(
      delegate.conditionTimeouts,
      containsPair('boundedNativeIf', const Duration(seconds: 8)),
    );
  });

  test('stalled native condition remains bounded by its guard', () async {
    final clock = ManualCockpitClock();
    final delegate = DeterministicCaseDelegate();
    delegate.hangingConditions['stalledNativeIf'] =
        Completer<CockpitTestKernelConditionResult>();
    final recorder = CockpitTestAttemptRecorder(clock: clock);
    final future = _kernel(clock, delegate, recorder).run(
      plan: testExecutionPlan(
        steps: <CockpitTestExecutionNode>[
          _controlNode(
            'stalledNativeIf',
            CockpitTestIfPlanOperation(
              condition: _visibleCondition(),
              thenSteps: <CockpitTestExecutionNode>[
                actionNode('stalledNativeThen', 'main'),
              ],
              elseSteps: <CockpitTestExecutionNode>[
                actionNode('stalledNativeElse', 'main'),
              ],
            ),
            plane: CockpitTestPlane.native,
            timeoutMs: 30000,
          ),
        ],
      ),
      control: CockpitCaseExecutionControl(),
    );

    await _pump();
    expect(
      delegate.conditionTimeouts['stalledNativeIf'],
      const Duration(seconds: 15),
    );
    clock.elapse(const Duration(seconds: 21));
    final result = await future;

    expect(result.primaryError?.code, CockpitTestErrorCode.conditionError);
    expect(result.primaryError?.details, <String, Object?>{
      'plane': 'native',
      'commandTimeoutMs': 15000,
      'probeTimeoutMs': 21000,
    });
    expect(clock.elapsed, const Duration(seconds: 21));
    expect(
      delegate.events,
      isNot(contains('action:stalledNativeThen:primary')),
    );
    expect(
      delegate.events,
      isNot(contains('action:stalledNativeElse:primary')),
    );
  });

  test(
    'action timeout result wins after the logical command deadline',
    () async {
      final clock = ManualCockpitClock();
      final delegate = DeterministicCaseDelegate();
      final completion = Completer<CockpitTestKernelOperationResult>();
      delegate.hangingActions['lateTimeout'] = completion;
      final recorder = CockpitTestAttemptRecorder(clock: clock);
      final future = _kernel(clock, delegate, recorder).run(
        plan: testExecutionPlan(
          steps: <CockpitTestExecutionNode>[actionNode('lateTimeout', 'main')],
        ),
        control: CockpitCaseExecutionControl(),
      );

      await _pump();
      expect(
        delegate.actionTimeouts['lateTimeout'],
        const Duration(seconds: 1),
      );
      clock.elapse(const Duration(seconds: 1));
      await _pump();
      completion.complete(
        CockpitTestKernelOperationResult.failure(
          CockpitTestError(
            code: CockpitTestErrorCode.timeout,
            message: 'Detailed driver timeout.',
            stepId: 'lateTimeout',
            details: const <String, Object?>{'driverTimeout': true},
          ),
        ),
      );
      final result = await future;

      expect(result.primaryError?.message, 'Detailed driver timeout.');
      expect(result.primaryError?.details['driverTimeout'], isTrue);
    },
  );

  test('action guard remains bounded when the driver never returns', () async {
    final clock = ManualCockpitClock();
    final delegate = DeterministicCaseDelegate();
    delegate.hangingActions['neverReturns'] =
        Completer<CockpitTestKernelOperationResult>();
    final recorder = CockpitTestAttemptRecorder(clock: clock);
    final future = _kernel(clock, delegate, recorder).run(
      plan: testExecutionPlan(
        steps: <CockpitTestExecutionNode>[actionNode('neverReturns', 'main')],
      ),
      control: CockpitCaseExecutionControl(),
    );

    await _pump();
    clock.elapse(const Duration(milliseconds: 7250));
    final result = await future;

    expect(result.primaryError?.code, CockpitTestErrorCode.timeout);
    expect(
      result.primaryError?.message,
      'Step exceeded its monotonic deadline.',
    );
  });

  test('retry and loop keep occurrences separate from execution ids', () async {
    final clock = ManualCockpitClock();
    final delegate = DeterministicCaseDelegate()
      ..actionResults['retryChild'] = <CockpitTestKernelOperationResult>[
        CockpitTestKernelOperationResult.failure(testDriverError('retryChild')),
        const CockpitTestKernelOperationResult.success(),
      ]
      ..conditionResults.addAll(<CockpitTestKernelConditionResult>[
        const CockpitTestKernelConditionResult(
          evaluation: CockpitTestConditionEvaluation.matched(),
        ),
        const CockpitTestKernelConditionResult(
          evaluation: CockpitTestConditionEvaluation.notMatched(),
        ),
      ]);
    final recorder = CockpitTestAttemptRecorder(clock: clock);
    final result = await _kernel(clock, delegate, recorder).run(
      plan: testExecutionPlan(
        steps: <CockpitTestExecutionNode>[_retryNode(), _loopNode()],
      ),
      control: CockpitCaseExecutionControl(),
    );

    expect(result.outcome, CockpitTestOutcome.passed);
    final retry = recorder.steps.where((step) => step.stepId == 'retryChild');
    expect(retry.map((step) => step.occurrence.retryAttempt), <int?>[1, 2]);
    expect(retry.map((step) => step.executionId).toSet(), <String>{
      'main/retry/retryChild',
    });
    final loop = recorder.steps.where((step) => step.stepId == 'loopChild');
    expect(loop.single.occurrence.loopIteration, 1);
  });

  test('loop rechecks the condition after its final action', () async {
    final clock = ManualCockpitClock();
    final delegate = DeterministicCaseDelegate()
      ..conditionResults.addAll(<CockpitTestKernelConditionResult>[
        const CockpitTestKernelConditionResult(
          evaluation: CockpitTestConditionEvaluation.matched(),
        ),
        const CockpitTestKernelConditionResult(
          evaluation: CockpitTestConditionEvaluation.matched(),
        ),
        const CockpitTestKernelConditionResult(
          evaluation: CockpitTestConditionEvaluation.notMatched(),
        ),
      ]);
    final recorder = CockpitTestAttemptRecorder(clock: clock);

    final result = await _kernel(clock, delegate, recorder).run(
      plan: testExecutionPlan(steps: <CockpitTestExecutionNode>[_loopNode()]),
      control: CockpitCaseExecutionControl(),
    );

    expect(result.outcome, CockpitTestOutcome.passed);
    expect(
      recorder.steps.where((step) => step.stepId == 'loopChild'),
      hasLength(2),
    );
    expect(
      delegate.events,
      containsAllInOrder(<String>[
        'condition:loop:primary',
        'action:loopChild:primary',
        'condition:loop:primary',
        'action:loopChild:primary',
        'condition:loop:primary',
      ]),
    );
  });

  test(
    'ordinary cancellation force-aborts primary then runs cleanup',
    () async {
      final clock = ManualCockpitClock();
      final delegate = DeterministicCaseDelegate();
      delegate.hangingActions['hang'] =
          Completer<CockpitTestKernelOperationResult>();
      final recorder = CockpitTestAttemptRecorder(clock: clock);
      var abortCount = 0;
      final control = CockpitCaseExecutionControl(
        cancellationGrace: const Duration(milliseconds: 100),
        forceAbort: () async => abortCount += 1,
      );
      final future = _kernel(clock, delegate, recorder).run(
        plan: testExecutionPlan(
          steps: <CockpitTestExecutionNode>[actionNode('hang', 'main')],
          finallySteps: <CockpitTestExecutionNode>[
            actionNode('cleanup', 'finally'),
          ],
        ),
        control: control,
      );
      await _pump();
      control.cancel();
      await _pump();
      clock.elapse(const Duration(milliseconds: 100));
      final result = await future;

      expect(abortCount, 1);
      expect(result.outcome, CockpitTestOutcome.cancelled);
      expect(delegate.events, contains('action:cleanup:cleanup'));
    },
  );

  test(
    'cleanup deadline records timeout and does not report success',
    () async {
      final clock = ManualCockpitClock();
      final delegate = DeterministicCaseDelegate();
      delegate.hangingActions['cleanupHang'] =
          Completer<CockpitTestKernelOperationResult>();
      final recorder = CockpitTestAttemptRecorder(clock: clock);
      final future = _kernel(clock, delegate, recorder).run(
        plan: testExecutionPlan(
          cleanupTimeoutMs: 50,
          steps: <CockpitTestExecutionNode>[actionNode('main', 'main')],
          finallySteps: <CockpitTestExecutionNode>[
            actionNode('cleanupHang', 'finally'),
          ],
        ),
        control: CockpitCaseExecutionControl(),
      );
      await _pump();
      clock.elapse(const Duration(milliseconds: 50));
      final result = await future;

      expect(result.outcome, CockpitTestOutcome.failed);
      expect(
        result.cleanupErrors.map((error) => error.code),
        everyElement(CockpitTestErrorCode.timeout),
      );
    },
  );

  test('expired step deadline does not start the next operation', () async {
    final clock = ManualCockpitClock();
    final delegate = DeterministicCaseDelegate();
    final recorder = CockpitTestAttemptRecorder(clock: clock);
    final future = _kernel(clock, delegate, recorder).run(
      plan: testExecutionPlan(
        steps: <CockpitTestExecutionNode>[
          CockpitTestExecutionNode(
            stepId: 'stopRecording',
            executionId: 'main/stopRecording',
            section: 'main',
            timeoutMs: 50,
            evidence: const CockpitTestEvidencePolicy(
              screenshot: CockpitTestEvidenceMode.none,
              snapshot: CockpitTestEvidenceMode.none,
            ),
            safety: CockpitTestSafetyDeclaration(),
            sourcePath: r'$.steps[0]',
            operation: const CockpitTestStopRecordingPlanOperation(
              settleMs: 50,
            ),
          ),
        ],
      ),
      control: CockpitCaseExecutionControl(),
    );
    await _pump();
    clock.elapse(const Duration(milliseconds: 50));
    final result = await future;

    expect(result.primaryError?.code, CockpitTestErrorCode.timeout);
    expect(delegate.events, isNot(contains('recording:stop:stopRecording')));
  });
}

CockpitCaseExecutionKernel _kernel(
  ManualCockpitClock clock,
  DeterministicCaseDelegate delegate,
  CockpitTestAttemptRecorder recorder,
) => CockpitCaseExecutionKernel(
  clock: clock,
  delegate: delegate,
  recorder: recorder,
);

Future<void> _pump() async {
  await Future<void>.value();
  await Future<void>.value();
}

CockpitTestCondition _visibleCondition() => CockpitTestCondition(
  kind: CockpitTestConditionKind.visible,
  locator: CockpitTestLocator(testId: 'target'),
);

CockpitTestExecutionNode _ifNode(String id, String thenId, String elseId) =>
    _controlNode(
      id,
      CockpitTestIfPlanOperation(
        condition: _visibleCondition(),
        thenSteps: <CockpitTestExecutionNode>[actionNode(thenId, 'main')],
        elseSteps: <CockpitTestExecutionNode>[actionNode(elseId, 'main')],
      ),
    );

CockpitTestExecutionNode _retryNode() => _controlNode(
  'retry',
  CockpitTestRetryPlanOperation(
    maxAttempts: 2,
    delayMs: 0,
    steps: <CockpitTestExecutionNode>[
      actionNode('retryChild', 'main', executionId: 'main/retry/retryChild'),
    ],
  ),
);

CockpitTestExecutionNode _loopNode() => _controlNode(
  'loop',
  CockpitTestLoopPlanOperation(
    maxIterations: 2,
    condition: _visibleCondition(),
    steps: <CockpitTestExecutionNode>[
      actionNode('loopChild', 'main', executionId: 'main/loop/loopChild'),
    ],
  ),
);

CockpitTestExecutionNode _controlNode(
  String id,
  CockpitTestPlanOperation operation, {
  CockpitTestPlane? plane,
  int timeoutMs = 1000,
}) => CockpitTestExecutionNode(
  stepId: id,
  executionId: 'main/$id',
  section: 'main',
  plane: plane,
  timeoutMs: timeoutMs,
  evidence: const CockpitTestEvidencePolicy(
    screenshot: CockpitTestEvidenceMode.none,
    snapshot: CockpitTestEvidenceMode.none,
  ),
  safety: CockpitTestSafetyDeclaration(),
  sourcePath: '\$.steps[0]',
  operation: operation,
);
