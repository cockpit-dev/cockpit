import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [child] under a [FlutterCockpitRoot] whose recorder is enabled and
/// returns the mounted recorder.
Future<CockpitInteractionRecorder> pumpRecordingApp(
  WidgetTester tester, {
  required Widget child,
}) async {
  FlutterCockpit.initialize(
    FlutterCockpitConfiguration(
      recorder: const FlutterCockpitRecorderConfig(enabled: true),
    ),
  );
  final rootKey = GlobalKey<FlutterCockpitRootState>();
  await tester.pumpWidget(FlutterCockpitRoot(key: rootKey, child: child));
  await tester.pumpAndSettle();
  final recorder = rootKey.currentState!.interactionRecorder;
  assert(recorder != null, 'The recorder must mount when enabled.');
  return recorder!;
}

Widget _homeApp({required Widget body}) {
  return MaterialApp(
    navigatorObservers: [FlutterCockpit.navigatorObserver],
    home: Scaffold(body: Center(child: body)),
  );
}

/// A button that counts its own presses so replay has an observable effect.
final class _CountingButton extends StatefulWidget {
  const _CountingButton({this.onChanged});

  final void Function(int count)? onChanged;

  @override
  State<_CountingButton> createState() => _CountingButtonState();
}

final class _CountingButtonState extends State<_CountingButton> {
  int _count = 0;

  void _press() {
    setState(() => _count += 1);
    widget.onChanged?.call(_count);
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      key: const ValueKey<String>('count-button'),
      onPressed: _press,
      child: Text('Pressed $_count'),
    );
  }
}

CockpitLocatorCandidate _keyCandidate(String key) => CockpitLocatorCandidate(
  kind: 'key',
  selector: CockpitSelector.format(CockpitLocator(key: key)),
  score: 4,
);

CockpitInteractionStep _pendingStep(
  CockpitInteractionStepKind kind, {
  List<CockpitLocatorCandidate> candidates = const <CockpitLocatorCandidate>[],
  bool unresolved = false,
  String? routeName,
}) => CockpitInteractionStep(
  stepId: 'pending',
  kind: kind,
  locatorCandidates: candidates,
  routeName: routeName,
  unresolved: unresolved,
  phase: CockpitRecorderPhase.recording,
  recordedAt: DateTime.utc(2026, 10, 7, 9),
);

void main() {
  tearDown(FlutterCockpit.dispose);

  group('export', () {
    test('throws before any session started', () {
      final recorder = CockpitInteractionRecorder();
      expect(recorder.export, throwsStateError);
      expect(recorder.verifyReplay, throwsStateError);
    });

    test('builds the bundle with document and YAML while recording', () {
      final recorder = CockpitInteractionRecorder();
      recorder.start(
        const CockpitInteractionRecordingRequest(name: 'login flow'),
      );
      recorder.recordInteractionStep(
        _pendingStep(
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[_keyCandidate('save')],
        ),
      );

      final bundle = recorder.export();

      expect(bundle.session.sessionId, 'r1');
      expect(bundle.steps, hasLength(1));
      expect(bundle.caseDocument['id'], 'recorded-r1');
      // The session id is engine-generated, so the derived case id always
      // satisfies the case id pattern by construction.
      expect(
        RegExp(
          r'^[A-Za-z][A-Za-z0-9._-]{0,127}$',
        ).hasMatch(bundle.caseDocument['id']! as String),
        isTrue,
      );
      expect(bundle.caseDocument['x-cockpit-recorder-session'], 'r1');
      expect(bundle.caseYaml, startsWith('schemaVersion: cockpit.test/v2\n'));
      expect(bundle.caseYaml, contains('id: recorded-r1\n'));
      expect(bundle.caseYaml, contains('name: login flow\n'));
      expect(bundle.caseYaml, contains('x-cockpit-origin: recorded\n'));
      expect(bundle.caseYaml, contains('testId: save\n'));
    });

    test('works while paused and after stop, and reflects a fresh session', () {
      final recorder = CockpitInteractionRecorder();
      recorder.start();
      recorder.recordInteractionStep(
        _pendingStep(
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[_keyCandidate('save')],
        ),
      );

      recorder.pause();
      final paused = recorder.export();
      expect(paused.caseDocument['id'], 'recorded-r1');

      recorder.resume();
      recorder.stop();
      final stopped = recorder.export();
      expect(stopped.caseDocument, paused.caseDocument);
      expect(stopped.caseYaml, paused.caseYaml);

      // A fresh session clears the steps, so nothing remains to export.
      recorder.start();
      expect(recorder.export, throwsArgumentError);
    });

    test('refuses to export a session with no exportable step', () {
      final recorder = CockpitInteractionRecorder();
      recorder.start();
      recorder.recordInteractionStep(
        _pendingStep(CockpitInteractionStepKind.tap, unresolved: true),
      );
      expect(recorder.export, throwsArgumentError);
    });
  });

  group('CockpitReplayReport', () {
    test('round-trips through json with equality', () {
      const report = CockpitReplayReport(
        stepId: 's2',
        kind: CockpitInteractionStepKind.tap,
        status: CockpitReplayStatus.deviated,
        reason: 'No locator candidate resolved against the live registry.',
      );

      expect(report.toJson(), <String, Object?>{
        'stepId': 's2',
        'kind': 'tap',
        'status': 'deviated',
        'reason': 'No locator candidate resolved against the live registry.',
      });
      expect(CockpitReplayReport.fromJson(report.toJson()), report);
      expect(
        CockpitReplayReport.fromJson(report.toJson()).hashCode,
        report.hashCode,
      );
    });

    test('decoding rejects malformed payloads', () {
      expect(
        () => CockpitReplayReport.fromJson(<String, Object?>{
          'stepId': 's1',
          'kind': 'tap',
        }),
        throwsFormatException,
      );
      expect(
        () => CockpitReplayReport.fromJson(<String, Object?>{
          'stepId': 's1',
          'kind': 'tap',
          'status': 'exploded',
        }),
        throwsFormatException,
      );
    });
  });

  group('verifyReplay', () {
    testWidgets('replays a recorded tap and suppresses re-capture', (
      tester,
    ) async {
      var presses = 0;
      final recorder = await pumpRecordingApp(
        tester,
        child: _homeApp(
          body: _CountingButton(onChanged: (count) => presses = count),
        ),
      );

      recorder.start();
      await tester.tap(find.byKey(const ValueKey<String>('count-button')));
      await tester.pumpAndSettle();
      expect(recorder.steps, hasLength(1));
      expect(presses, 1);

      final reports = await recorder.verifyReplay();
      await tester.pumpAndSettle();

      expect(reports, hasLength(1));
      expect(reports.single.status, CockpitReplayStatus.passed);
      expect(reports.single.stepId, 's1');
      // The replayed tap really reached the app...
      expect(presses, 2);
      // ...but the capture layer dropped its own synthetic pointer events.
      expect(recorder.steps, hasLength(1));
      expect(recorder.phase, CockpitRecorderPhase.recording);
      expect(recorder.isReplaying, isFalse);
    });

    testWidgets('still replays from a stopped session', (tester) async {
      var presses = 0;
      final recorder = await pumpRecordingApp(
        tester,
        child: _homeApp(
          body: _CountingButton(onChanged: (count) => presses = count),
        ),
      );

      recorder.start();
      await tester.tap(find.byKey(const ValueKey<String>('count-button')));
      await tester.pumpAndSettle();
      recorder.stop();

      final reports = await recorder.verifyReplay();
      await tester.pumpAndSettle();

      expect(reports.single.status, CockpitReplayStatus.passed);
      expect(presses, 2);
      expect(recorder.phase, CockpitRecorderPhase.stopped);
    });

    testWidgets('deviates when no locator candidate resolves', (tester) async {
      final recorder = await pumpRecordingApp(
        tester,
        child: _homeApp(body: const SizedBox.shrink()),
      );

      recorder.start();
      recorder.recordInteractionStep(
        _pendingStep(
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[_keyCandidate('vanished')],
        ),
      );

      final reports = await recorder.verifyReplay();

      expect(reports.single.status, CockpitReplayStatus.deviated);
      expect(reports.single.reason, contains('vanished'));
      expect(reports.single.reason, contains('No locator candidate'));
    });

    testWidgets('skips non-actionable kinds and unresolved noise', (
      tester,
    ) async {
      var presses = 0;
      final recorder = await pumpRecordingApp(
        tester,
        child: _homeApp(
          body: _CountingButton(onChanged: (count) => presses = count),
        ),
      );

      recorder.start();
      recorder.recordInteractionStep(
        _pendingStep(CockpitInteractionStepKind.tap, unresolved: true),
      );
      recorder.recordInteractionStep(
        _pendingStep(
          CockpitInteractionStepKind.routeChange,
          routeName: '/details',
        ),
      );
      recorder.recordInteractionStep(
        _pendingStep(
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[_keyCandidate('count-button')],
        ),
      );

      final reports = await recorder.verifyReplay();
      await tester.pumpAndSettle();

      expect(
        reports.map((report) => '${report.stepId}:${report.status.name}'),
        <String>['s1:skipped', 's2:skipped', 's3:passed'],
      );
      expect(reports[1].reason, contains('routeChange'));
      expect(presses, 1);
    });

    test('throws without a registry or without actionable steps', () async {
      final recorder = CockpitInteractionRecorder();
      recorder.start();
      // No registry wired.
      await expectLater(recorder.verifyReplay(), throwsStateError);

      final wired = CockpitInteractionRecorder(
        registry: CockpitTargetRegistry(),
      );
      wired.start();
      // No step at all.
      await expectLater(wired.verifyReplay(), throwsStateError);
      // Only non-actionable steps.
      wired.recordInteractionStep(
        _pendingStep(
          CockpitInteractionStepKind.routeChange,
          routeName: '/details',
        ),
      );
      await expectLater(wired.verifyReplay(), throwsStateError);
    });

    test(
      'exposes the replaying flag to the performer and drops engine-fed steps',
      () async {
        final registry = CockpitTargetRegistry();
        registry.register(
          CockpitTarget(
            registrationId: 'zone',
            keyValue: 'zone',
            routeName: '/',
          ),
        );
        late final CockpitInteractionRecorder recorder;
        var sawReplayingFlag = false;
        recorder = CockpitInteractionRecorder(
          registry: registry,
          waitForIdle:
              ({
                required Duration quietWindow,
                required Duration timeout,
              }) async => true,
          gesturePerformer: (action) async {
            sawReplayingFlag = recorder.isReplaying;
            // A capture feed racing the replay must be dropped by the engine.
            recorder.recordInteractionStep(
              _pendingStep(CockpitInteractionStepKind.tap),
            );
          },
        );
        recorder.start();
        recorder.recordInteractionStep(
          _pendingStep(
            CockpitInteractionStepKind.tap,
            candidates: <CockpitLocatorCandidate>[_keyCandidate('zone')],
          ),
        );

        final reports = await recorder.verifyReplay();

        expect(sawReplayingFlag, isTrue);
        expect(reports.single.status, CockpitReplayStatus.passed);
        // Only the original step survived; the replay-fed step was dropped.
        expect(recorder.steps, hasLength(1));
        expect(recorder.isReplaying, isFalse);
      },
    );
  });
}
