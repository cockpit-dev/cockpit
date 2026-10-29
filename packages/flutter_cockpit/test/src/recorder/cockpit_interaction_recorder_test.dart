import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

final class FakeClock {
  DateTime current = DateTime.utc(2026, 10, 7, 9);

  DateTime call() => current;

  void advance(Duration duration) {
    current = current.add(duration);
  }
}

CockpitInteractionStep incomingStep({
  CockpitInteractionStepKind kind = CockpitInteractionStepKind.tap,
  bool unresolved = false,
  String? resolvedValue,
  String? annotation,
  int? settledAfterMs,
  DateTime? recordedAt,
}) {
  return CockpitInteractionStep(
    stepId: 'pending',
    kind: kind,
    unresolved: unresolved,
    resolvedValue: resolvedValue,
    annotation: annotation,
    settledAfterMs: settledAfterMs,
    phase: CockpitRecorderPhase.idle,
    segments: const <String>['caller-side-placeholder'],
    recordedAt: recordedAt ?? DateTime.utc(2026, 10, 7, 9, 0, 1),
  );
}

void main() {
  group('phase machine', () {
    test('start moves idle to recording and creates the session', () {
      final clock = FakeClock();
      final recorder = CockpitInteractionRecorder(now: clock.call);

      expect(recorder.phase, CockpitRecorderPhase.idle);
      expect(recorder.activeSession, isNull);
      expect(() => recorder.sessionSnapshot(), throwsStateError);

      recorder.start();

      expect(recorder.phase, CockpitRecorderPhase.recording);
      expect(recorder.sessionName, isNull);
      final session = recorder.sessionSnapshot();
      expect(session.sessionId, 'r1');
      expect(session.phase, CockpitRecorderPhase.recording);
      expect(session.startedAt, clock.current);
      expect(session.stepCount, 0);
      expect(session.unresolvedCount, 0);
      expect(recorder.activeSession, session);
    });

    test('start stores the request name on the engine', () {
      final recorder = CockpitInteractionRecorder(now: FakeClock().call);
      recorder.start(
        const CockpitInteractionRecordingRequest(name: 'login flow'),
      );
      expect(recorder.sessionName, 'login flow');
    });

    test('pause and resume transition through paused', () {
      final clock = FakeClock();
      final recorder = CockpitInteractionRecorder(now: clock.call);
      recorder.start();
      clock.advance(const Duration(seconds: 5));

      recorder.pause();
      expect(recorder.phase, CockpitRecorderPhase.paused);
      expect(recorder.sessionSnapshot().pausedAt, clock.current);

      clock.advance(const Duration(seconds: 5));
      recorder.resume();
      expect(recorder.phase, CockpitRecorderPhase.recording);
      // pausedAt keeps the latest pause as a diagnostic timestamp.
      expect(recorder.sessionSnapshot().pausedAt, isNotNull);
    });

    test('stop returns the result with the finished session', () {
      final clock = FakeClock();
      final recorder = CockpitInteractionRecorder(now: clock.call);
      recorder.start();
      recorder.recordInteractionStep(incomingStep());
      recorder.recordInteractionStep(incomingStep(unresolved: true));
      clock.advance(const Duration(seconds: 10));

      final result = recorder.stop();

      expect(recorder.phase, CockpitRecorderPhase.stopped);
      expect(result.session.phase, CockpitRecorderPhase.stopped);
      expect(result.session.endedAt, clock.current);
      expect(result.session.stepCount, 2);
      expect(result.session.unresolvedCount, 1);
      expect(result.steps, recorder.steps);
      expect(result.steps.map((step) => step.stepId), <String>['s1', 's2']);
    });

    test('stop is legal from paused', () {
      final recorder = CockpitInteractionRecorder(now: FakeClock().call);
      recorder.start();
      recorder.pause();
      final result = recorder.stop();
      expect(result.session.phase, CockpitRecorderPhase.stopped);
    });

    test('start after stop resets the session with monotonic ids', () {
      final recorder = CockpitInteractionRecorder(now: FakeClock().call);
      recorder.start();
      recorder.beginSegment('leftover');
      recorder.recordInteractionStep(incomingStep());
      recorder.stop();

      recorder.start(const CockpitInteractionRecordingRequest(name: 'second'));

      expect(recorder.phase, CockpitRecorderPhase.recording);
      expect(recorder.sessionSnapshot().sessionId, 'r2');
      expect(recorder.steps, isEmpty);

      // Step ids restart per session; segments are reset.
      recorder.recordInteractionStep(incomingStep());
      expect(recorder.steps.single.stepId, 's1');
      expect(recorder.steps.single.segments, isEmpty);
    });

    test('illegal transitions throw StateError', () {
      final recorder = CockpitInteractionRecorder(now: FakeClock().call);

      // idle
      expect(recorder.pause, throwsStateError);
      expect(recorder.resume, throwsStateError);
      expect(recorder.stop, throwsStateError);
      expect(() => recorder.beginSegment('a'), throwsStateError);
      expect(() => recorder.endSegment(), throwsStateError);
      expect(() => recorder.annotate('s1', 'note'), throwsStateError);
      expect(recorder.discardLastStep, throwsStateError);
      expect(() => recorder.markStepSettled('s1', 10), throwsStateError);

      // recording: start and resume are illegal
      recorder.start();
      expect(() => recorder.start(), throwsStateError);
      expect(recorder.resume, throwsStateError);

      // paused: everything except resume, stop, and markStepSettled
      recorder.pause();
      expect(() => recorder.start(), throwsStateError);
      expect(recorder.pause, throwsStateError);
      expect(() => recorder.beginSegment('a'), throwsStateError);
      expect(() => recorder.endSegment(), throwsStateError);
      expect(() => recorder.annotate('s1', 'note'), throwsStateError);
      expect(recorder.discardLastStep, throwsStateError);

      // stopped: terminal except for a fresh start
      recorder.stop();
      expect(recorder.pause, throwsStateError);
      expect(recorder.resume, throwsStateError);
      expect(recorder.stop, throwsStateError);
      expect(() => recorder.beginSegment('a'), throwsStateError);
      expect(() => recorder.annotate('s1', 'note'), throwsStateError);
      expect(recorder.discardLastStep, throwsStateError);
      expect(() => recorder.markStepSettled('s1', 10), throwsStateError);

      recorder.start();
      expect(recorder.phase, CockpitRecorderPhase.recording);
    });
  });

  group('step recording', () {
    test('steps are dropped while not recording', () {
      final recorder = CockpitInteractionRecorder(now: FakeClock().call);

      recorder.recordInteractionStep(incomingStep());
      expect(recorder.steps, isEmpty);

      recorder.start();
      recorder.pause();
      recorder.recordInteractionStep(incomingStep());
      expect(recorder.steps, isEmpty);

      recorder.resume();
      recorder.recordInteractionStep(incomingStep());
      recorder.stop();
      recorder.recordInteractionStep(incomingStep());
      expect(recorder.steps, hasLength(1));
    });

    test('ids stay monotonic across pause gaps', () {
      final recorder = CockpitInteractionRecorder(now: FakeClock().call);
      recorder.start();
      recorder.recordInteractionStep(incomingStep());
      recorder.recordInteractionStep(incomingStep());
      recorder.pause();
      recorder.recordInteractionStep(incomingStep());
      recorder.resume();
      recorder.recordInteractionStep(incomingStep());

      expect(recorder.steps.map((step) => step.stepId), <String>[
        's1',
        's2',
        's3',
      ]);
    });

    test('engine stamps id, phase, and segments over placeholders', () {
      final recorder = CockpitInteractionRecorder(now: FakeClock().call);
      recorder.start();
      recorder.beginSegment('outer');
      recorder.beginSegment('inner');

      final recordedAt = DateTime.utc(2026, 10, 7, 9, 0, 1);
      recorder.recordInteractionStep(
        incomingStep(
          unresolved: true,
          settledAfterMs: 99,
          recordedAt: recordedAt,
        ),
      );

      final step = recorder.steps.single;
      expect(step.stepId, 's1');
      expect(step.phase, CockpitRecorderPhase.recording);
      expect(step.segments, <String>['outer', 'inner']);
      expect(step.unresolved, isTrue);
      expect(step.recordedAt, recordedAt);
      // Settle time only arrives through markStepSettled.
      expect(step.settledAfterMs, isNull);
    });

    test('segments snapshot follows the open stack', () {
      final recorder = CockpitInteractionRecorder(now: FakeClock().call);
      recorder.start();

      recorder.beginSegment('a');
      recorder.recordInteractionStep(incomingStep());
      recorder.beginSegment('b');
      recorder.recordInteractionStep(incomingStep());
      recorder.endSegment();
      recorder.recordInteractionStep(incomingStep());
      recorder.endSegment();
      recorder.recordInteractionStep(incomingStep());

      expect(recorder.steps[0].segments, <String>['a']);
      expect(recorder.steps[1].segments, <String>['a', 'b']);
      expect(recorder.steps[2].segments, <String>['a']);
      expect(recorder.steps[3].segments, isEmpty);
    });

    test('duplicate concurrent segment labels are allowed', () {
      final recorder = CockpitInteractionRecorder(now: FakeClock().call);
      recorder.start();
      recorder.beginSegment('setup');
      recorder.beginSegment('setup');
      recorder.recordInteractionStep(incomingStep());
      expect(recorder.steps.single.segments, <String>['setup', 'setup']);
      recorder.endSegment();
      recorder.endSegment();
      recorder.recordInteractionStep(incomingStep());
      expect(recorder.steps.last.segments, isEmpty);
    });

    test('endSegment throws when no segment is open', () {
      final recorder = CockpitInteractionRecorder(now: FakeClock().call);
      recorder.start();
      expect(recorder.endSegment, throwsStateError);
      recorder.beginSegment('a');
      recorder.endSegment();
      expect(recorder.endSegment, throwsStateError);
    });

    test('annotate replaces the annotation of a recorded step', () {
      final recorder = CockpitInteractionRecorder(now: FakeClock().call);
      recorder.start();
      recorder.recordInteractionStep(incomingStep(annotation: 'draft'));
      recorder.recordInteractionStep(incomingStep());

      recorder.annotate('s1', 'final note');

      expect(recorder.steps[0].annotation, 'final note');
      expect(recorder.steps[1].annotation, isNull);
    });

    test('annotate throws for unknown ids and illegal phases', () {
      final recorder = CockpitInteractionRecorder(now: FakeClock().call);
      recorder.start();
      expect(() => recorder.annotate('s1', 'note'), throwsStateError);
      recorder.recordInteractionStep(incomingStep());
      recorder.pause();
      expect(() => recorder.annotate('s1', 'note'), throwsStateError);
    });

    test('discardLastStep removes the last step and never reuses its id', () {
      final recorder = CockpitInteractionRecorder(now: FakeClock().call);
      recorder.start();
      recorder.recordInteractionStep(incomingStep());
      recorder.recordInteractionStep(incomingStep());

      recorder.discardLastStep();

      expect(recorder.steps.map((step) => step.stepId), <String>['s1']);
      recorder.recordInteractionStep(incomingStep());
      expect(recorder.steps.last.stepId, 's3');
    });

    test('discardLastStep throws when no step is recorded', () {
      final recorder = CockpitInteractionRecorder(now: FakeClock().call);
      recorder.start();
      expect(recorder.discardLastStep, throwsStateError);
      recorder.recordInteractionStep(incomingStep());
      recorder.discardLastStep();
      expect(recorder.discardLastStep, throwsStateError);
    });

    test('markStepSettled back-fills the settle time', () {
      final recorder = CockpitInteractionRecorder(now: FakeClock().call);
      recorder.start();
      recorder.recordInteractionStep(incomingStep());

      recorder.markStepSettled('s1', 120);

      expect(recorder.steps.single.settledAfterMs, 120);
      expect(recorder.sessionSnapshot().stepCount, 1);
    });

    test('markStepSettled throws for unknown, settled, and illegal input', () {
      final recorder = CockpitInteractionRecorder(now: FakeClock().call);
      recorder.start();

      expect(() => recorder.markStepSettled('s1', 10), throwsStateError);

      recorder.recordInteractionStep(incomingStep());
      recorder.markStepSettled('s1', 10);
      expect(() => recorder.markStepSettled('s1', 20), throwsStateError);
      expect(() => recorder.markStepSettled('s2', 10), throwsStateError);
      expect(() => recorder.markStepSettled('s1', -1), throwsArgumentError);

      // A settle watch started before a pause may complete after it.
      recorder.recordInteractionStep(incomingStep());
      recorder.pause();
      recorder.markStepSettled('s2', 15);
      expect(recorder.steps[1].settledAfterMs, 15);

      recorder.stop();
      expect(() => recorder.markStepSettled('s1', 30), throwsStateError);
    });
  });

  group('session snapshot', () {
    test('counts track resolved and unresolved steps', () {
      final recorder = CockpitInteractionRecorder(now: FakeClock().call);
      recorder.start();

      recorder.recordInteractionStep(incomingStep());
      recorder.recordInteractionStep(incomingStep(unresolved: true));
      recorder.recordInteractionStep(incomingStep());
      recorder.recordInteractionStep(incomingStep(unresolved: true));
      recorder.discardLastStep();

      final session = recorder.sessionSnapshot();
      expect(session.stepCount, 3);
      expect(session.unresolvedCount, 1);
    });

    test('steps getter is an unmodifiable view', () {
      final recorder = CockpitInteractionRecorder(now: FakeClock().call);
      recorder.start();
      recorder.recordInteractionStep(incomingStep());

      expect(() => recorder.steps.add(incomingStep()), throwsUnsupportedError);
    });
  });

  group('clock injection', () {
    test('startedAt, pausedAt, and endedAt use the injected clock', () {
      final clock = FakeClock();
      final recorder = CockpitInteractionRecorder(now: clock.call);

      recorder.start();
      expect(recorder.sessionSnapshot().startedAt, clock.current);

      clock.advance(const Duration(seconds: 1));
      recorder.pause();
      expect(recorder.sessionSnapshot().pausedAt, clock.current);

      clock.advance(const Duration(seconds: 1));
      recorder.stop();
      expect(recorder.sessionSnapshot().endedAt, clock.current);
    });
  });

  group('change notification', () {
    test('every effective command notifies listeners exactly once', () {
      final recorder = CockpitInteractionRecorder(now: FakeClock().call);
      var notifications = 0;
      recorder.addListener(() => notifications += 1);

      recorder.start();
      recorder.beginSegment('a');
      recorder.recordInteractionStep(incomingStep());
      recorder.markStepSettled('s1', 10);
      recorder.annotate('s1', 'note');
      recorder.discardLastStep();
      recorder.endSegment();
      recorder.pause();
      // Suppressed ingestion must not notify.
      recorder.recordInteractionStep(incomingStep());
      recorder.resume();
      recorder.stop();

      expect(notifications, 10);
    });

    test('illegal commands throw without notifying', () {
      final recorder = CockpitInteractionRecorder(now: FakeClock().call);
      var notifications = 0;
      recorder.addListener(() => notifications += 1);

      expect(recorder.pause, throwsStateError);
      expect(() => recorder.beginSegment('a'), throwsStateError);

      expect(notifications, 0);
    });
  });

  group('exclusions', () {
    test('the engine owns a registry', () {
      final recorder = CockpitInteractionRecorder(now: FakeClock().call);
      expect(recorder.exclusions, isNotNull);
      expect(recorder.exclusions.isEmpty, isTrue);
    });
  });

  group('beforeStopHook', () {
    test('the latest hook runs and its steps land in the result', () {
      final recorder = CockpitInteractionRecorder(now: FakeClock().call);
      recorder.start();
      var firstRuns = 0;
      var secondRuns = 0;
      recorder.beforeStopHook = () {
        firstRuns += 1;
        recorder.recordInteractionStep(incomingStep());
      };
      // Replacing the single slot mid-session: only the latest hook runs.
      recorder.beforeStopHook = () {
        secondRuns += 1;
        recorder.recordInteractionStep(incomingStep());
      };

      final result = recorder.stop();

      expect(firstRuns, 0);
      expect(secondRuns, 1);
      // The hook ran while the session still accepted steps.
      expect(result.steps, hasLength(1));
      expect(result.session.stepCount, 1);
    });

    test('clearing the hook with null stops it from running', () {
      final recorder = CockpitInteractionRecorder(now: FakeClock().call);
      recorder.start();
      var runs = 0;
      recorder.beforeStopHook = () => runs += 1;
      recorder.beforeStopHook = null;

      recorder.stop();

      expect(runs, 0);
    });

    test('a throwing hook aborts stop and keeps the session open', () {
      final recorder = CockpitInteractionRecorder(now: FakeClock().call);
      recorder.start();
      recorder.beforeStopHook = () => throw StateError('hook exploded');

      expect(recorder.stop, throwsStateError);
      // The phase machine never reached stopped, so a fixed hook can retry.
      expect(recorder.phase, CockpitRecorderPhase.recording);
      recorder.beforeStopHook = null;
      final result = recorder.stop();
      expect(result.session.phase, CockpitRecorderPhase.stopped);
    });
  });

  group('annotate and discard interplay', () {
    test('discardLastStep removes the annotated step', () {
      final recorder = CockpitInteractionRecorder(now: FakeClock().call);
      recorder.start();
      recorder.recordInteractionStep(incomingStep());
      recorder.annotate('s1', 'keep me not');

      recorder.discardLastStep();

      expect(recorder.steps, isEmpty);
      // The id of the discarded step is never resurrected.
      expect(() => recorder.annotate('s1', 'note'), throwsStateError);
    });
  });

  group('isActionable', () {
    test('only actionable kinds with the data a replay needs', () {
      CockpitInteractionStep step(
        CockpitInteractionStepKind kind, {
        bool unresolved = false,
        CockpitInteractionScrollDirection? direction,
      }) => CockpitInteractionStep(
        stepId: 's1',
        kind: kind,
        unresolved: unresolved,
        scrollDirection: direction,
        phase: CockpitRecorderPhase.recording,
        recordedAt: DateTime.utc(2026, 10, 7, 9),
      );

      for (final kind in CockpitInteractionStepKind.values) {
        // A bare step carries no scroll direction, so even scroll reads as
        // not actionable here; the direction cases follow below.
        final actionable =
            kind == CockpitInteractionStepKind.tap ||
            kind == CockpitInteractionStepKind.longPress ||
            kind == CockpitInteractionStepKind.text;
        expect(
          CockpitInteractionRecorder.isActionable(step(kind)),
          actionable,
          reason: kind.name,
        );
        // Unresolved noise never replays, whatever its kind.
        expect(
          CockpitInteractionRecorder.isActionable(step(kind, unresolved: true)),
          isFalse,
          reason: '${kind.name} unresolved',
        );
      }

      // A scroll replays through its direction alone — even unresolved and
      // without candidates, its target is borrowed from the next step and
      // the swipe can run from the recorded grab position.
      expect(
        CockpitInteractionRecorder.isActionable(
          step(
            CockpitInteractionStepKind.scroll,
            unresolved: true,
            direction: CockpitInteractionScrollDirection.up,
          ),
        ),
        isTrue,
      );
      // Without a direction there is nothing to replay.
      expect(
        CockpitInteractionRecorder.isActionable(
          step(CockpitInteractionStepKind.scroll),
        ),
        isFalse,
      );
    });
  });

  group('recorded step cap', () {
    test('stops accepting new steps at maxRecordedSteps and marks the session '
        'truncated', () {
      final recorder = CockpitInteractionRecorder(
        now: FakeClock().call,
        maxRecordedSteps: 3,
      );
      recorder.start();

      for (var i = 0; i < 5; i++) {
        recorder.recordInteractionStep(incomingStep());
      }

      expect(recorder.steps, hasLength(3));
      expect(recorder.stepsTruncated, isTrue);
      expect(recorder.sessionSnapshot().stepCount, 3);
      // The recorded prefix stays intact — no eviction of the head.
      expect(recorder.steps.map((step) => step.stepId).toList(), <String>[
        's1',
        's2',
        's3',
      ]);
    });

    test('a truncated session replays its recorded prefix intact', () {
      final recorder = CockpitInteractionRecorder(
        now: FakeClock().call,
        maxRecordedSteps: 2,
      );
      recorder.start();
      recorder.recordInteractionStep(incomingStep());
      recorder.recordInteractionStep(incomingStep());
      recorder.recordInteractionStep(incomingStep());

      expect(recorder.steps, hasLength(2));
      expect(recorder.stepsTruncated, isTrue);
      // The third step is dropped, not appended with a skipped id.
      expect(recorder.steps.last.stepId, 's2');
    });

    test('the cap resets when a new session starts', () {
      final recorder = CockpitInteractionRecorder(
        now: FakeClock().call,
        maxRecordedSteps: 1,
      );
      recorder.start();
      recorder.recordInteractionStep(incomingStep());
      recorder.recordInteractionStep(incomingStep());
      expect(recorder.stepsTruncated, isTrue);

      recorder.stop();
      recorder.start();
      expect(recorder.stepsTruncated, isFalse);
      recorder.recordInteractionStep(incomingStep());
      expect(recorder.steps, hasLength(1));
    });
  });
}
