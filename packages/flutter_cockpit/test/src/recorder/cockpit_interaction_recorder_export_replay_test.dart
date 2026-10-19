import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_cockpit/src/runtime/cockpit_ui_idle_waiter.dart';
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
  String? resolvedValue,
  CockpitInteractionScrollDirection? direction,
  double? positionDx,
  double? positionDy,
}) => CockpitInteractionStep(
  stepId: 'pending',
  kind: kind,
  locatorCandidates: candidates,
  routeName: routeName,
  resolvedValue: resolvedValue,
  unresolved: unresolved,
  scrollDirection: direction,
  positionDx: positionDx,
  positionDy: positionDy,
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

    test('carries the open segment stack into the converted document', () {
      final recorder = CockpitInteractionRecorder();
      recorder.start();
      recorder.beginSegment('setup');
      recorder.recordInteractionStep(
        _pendingStep(
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[_keyCandidate('seed')],
        ),
      );
      recorder.endSegment();
      recorder.beginSegment('main');
      recorder.recordInteractionStep(
        _pendingStep(
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[_keyCandidate('save')],
        ),
      );

      final bundle = recorder.export();
      final document = bundle.caseDocument;

      // Steps recorded inside a `setup` segment land in the case's setup
      // block; steps in any other segment stay in the main step list.
      final setup = document['setup']! as List<Object?>;
      final main = document['steps']! as List<Object?>;
      expect(setup, isNotEmpty);
      expect(main, isNotEmpty);
      expect(
        ((setup.first as Map<String, Object?>)['action']
                as Map<String, Object?>)['locator']
            as Map<String, Object?>,
        containsPair('testId', 'seed'),
      );
      expect(
        ((main.first as Map<String, Object?>)['action']
                as Map<String, Object?>)['locator']
            as Map<String, Object?>,
        containsPair('testId', 'save'),
      );
      expect(bundle.caseYaml, contains('testId: seed'));

      // The annotation survives on the recorded steps of the bundle.
      recorder.annotate('s2', 'primary action');
      expect(recorder.export().steps.last.annotation, 'primary action');
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
      expect(() => CockpitReplayReport.fromJson('nope'), throwsFormatException);
      expect(
        () => CockpitReplayReport.fromJson(<String, Object?>{
          'stepId': 's1',
          'kind': 'tap',
          'status': 'passed',
          'reason': 7,
        }),
        throwsFormatException,
      );
      expect(
        () => CockpitReplayReport.fromJson(<String, Object?>{
          'stepId': '',
          'kind': 'tap',
          'status': 'passed',
        }),
        throwsFormatException,
      );
      expect(
        () => CockpitReplayReport.fromJson(<String, Object?>{
          'stepId': 9,
          'kind': 'tap',
          'status': 'passed',
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

    testWidgets('replays steps recorded on a route the flow pushed to', (
      tester,
    ) async {
      // No navigator observer: like apps that rely on read-driven route
      // discovery, the registry's route scope can lag the route a replayed
      // step just navigated to, which used to make that route's steps
      // unresolvable.
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      FlutterCockpit.initialize(
        FlutterCockpitConfiguration(
          recorder: const FlutterCockpitRecorderConfig(enabled: true),
        ),
      );
      final rootKey = GlobalKey<FlutterCockpitRootState>();
      await tester.pumpWidget(
        FlutterCockpitRoot(
          key: rootKey,
          child: MaterialApp(
            routes: <String, WidgetBuilder>{
              '/': (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    key: const ValueKey<String>('open-editor'),
                    onPressed: () => Navigator.of(context).pushNamed('/editor'),
                    child: const Text('Open editor'),
                  ),
                ),
              ),
              '/editor': (context) => Scaffold(
                appBar: AppBar(title: const Text('Editor')),
                body: Center(
                  child: TextField(
                    key: const ValueKey<String>('title-field'),
                    controller: controller,
                  ),
                ),
              ),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A manually wired recorder: replay runs against the live binding
      // registry, and the idle wait mirrors the root's production wiring: a
      // test-binding frame settle first (the network-aware wait is a no-op
      // under a fake clock), so a replayed navigation mounts its route.
      final recorder = CockpitInteractionRecorder(
        registry: FlutterCockpit.binding.registry,
        waitForIdle:
            ({required Duration quietWindow, required Duration timeout}) async {
              await settleCockpitTestBindingFrames(timeout: timeout);
              return waitForCockpitUiIdle(
                quietWindow: quietWindow,
                timeout: timeout,
                waitTick: (duration) => Future<void>.delayed(duration),
              );
            },
      );
      recorder.start();
      recorder.recordInteractionStep(
        _pendingStep(
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[_keyCandidate('open-editor')],
          routeName: '/',
        ),
      );
      recorder.recordInteractionStep(
        _pendingStep(
          CockpitInteractionStepKind.text,
          candidates: <CockpitLocatorCandidate>[_keyCandidate('title-field')],
          routeName: '/editor',
          resolvedValue: 'recorded value',
        ),
      );

      final reports = await recorder.verifyReplay();
      await tester.pumpAndSettle();

      expect(
        reports.where(
          (report) => report.status == CockpitReplayStatus.deviated,
        ),
        isEmpty,
        reason: reports
            .map((report) => '${report.stepId}: ${report.reason}')
            .join('\n'),
      );
      expect(
        reports
            .where((report) => report.status == CockpitReplayStatus.passed)
            .length,
        2,
      );
      // The replayed push really mounted the editor route, and the replayed
      // text entry reached the live field.
      expect(find.text('Editor'), findsOneWidget);
      expect(controller.text, 'recorded value');
    });

    testWidgets(
      'replay resolves a recorded locator that became ambiguous toward the '
      'actionable control',
      (tester) async {
        // Replaying mutates app state, so a text locator that was unique at
        // record time can later match passive look-alikes as well (a status
        // label that now reads the same). Replay resolution must prefer the
        // control that can perform the step's command instead of failing on
        // the tie.
        var completed = false;
        var toggles = 0;
        StateSetter? updateState;
        FlutterCockpit.initialize(
          FlutterCockpitConfiguration(
            recorder: const FlutterCockpitRecorderConfig(enabled: true),
          ),
        );
        final rootKey = GlobalKey<FlutterCockpitRootState>();
        await tester.pumpWidget(
          FlutterCockpitRoot(
            key: rootKey,
            child: MaterialApp(
              home: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) {
                    updateState ??= setState;
                    return Column(
                      children: <Widget>[
                        Text(completed ? 'Completed' : 'In progress'),
                        CheckboxListTile(
                          title: const Text('Completed'),
                          // The subtitle makes the merged row text differ
                          // from the recorded locator, so the row only
                          // contains-matches and cannot outscore the
                          // exact-match labels.
                          subtitle: const Text(
                            'Mark this once the outcome is stable.',
                          ),
                          value: completed,
                          onChanged: (value) {
                            toggles += 1;
                            setState(() => completed = value ?? false);
                          },
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final recorder = CockpitInteractionRecorder(
          registry: FlutterCockpit.binding.registry,
          waitForIdle:
              ({
                required Duration quietWindow,
                required Duration timeout,
              }) async {
                await settleCockpitTestBindingFrames(timeout: timeout);
                return waitForCockpitUiIdle(
                  quietWindow: quietWindow,
                  timeout: timeout,
                  waitTick: (duration) => Future<void>.delayed(duration),
                );
              },
        );
        recorder.start();
        // Recorded while the status label still read 'In progress', so the
        // text locator only matched the checkbox row.
        recorder.recordInteractionStep(
          _pendingStep(
            CockpitInteractionStepKind.tap,
            candidates: <CockpitLocatorCandidate>[
              CockpitLocatorCandidate(
                kind: 'text',
                selector: CockpitSelector.format(
                  CockpitLocator(text: 'Completed'),
                ),
                score: 3,
              ),
            ],
            routeName: '/',
          ),
        );
        recorder.stop();

        // The flow itself completed the task between recording and replay:
        // the status label now reads 'Completed' too, so the locator matches
        // two passive labels plus the actionable checkbox row.
        updateState!(() => completed = true);
        await tester.pumpAndSettle();

        final reports = await recorder.verifyReplay();
        await tester.pumpAndSettle();

        expect(
          reports.single.status,
          CockpitReplayStatus.passed,
          reason: reports.single.reason,
        );
        expect(toggles, 1);
      },
    );

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

    test('a throwing step deviates while the others continue', () async {
      final registry = CockpitTargetRegistry()
        ..register(
          const CockpitTarget(
            registrationId: 'a',
            keyValue: 'a',
            routeName: '/',
          ),
        )
        ..register(
          const CockpitTarget(
            registrationId: 'b',
            keyValue: 'b',
            routeName: '/',
          ),
        )
        ..register(
          const CockpitTarget(
            registrationId: 'c',
            keyValue: 'c',
            routeName: '/',
          ),
        );
      final performerCalls = <String>[];
      final recorder = CockpitInteractionRecorder(
        registry: registry,
        waitForIdle:
            ({
              required Duration quietWindow,
              required Duration timeout,
            }) async => true,
        gesturePerformer: (action) async {
          performerCalls.add(action.target!.keyValue!);
          if (action.target!.keyValue == 'b') {
            throw StateError('pointer device exploded');
          }
        },
      );
      recorder.start();
      for (final key in <String>['a', 'b', 'c']) {
        recorder.recordInteractionStep(
          _pendingStep(
            CockpitInteractionStepKind.tap,
            candidates: <CockpitLocatorCandidate>[_keyCandidate(key)],
          ),
        );
      }

      final reports = await recorder.verifyReplay();

      expect(reports.map((report) => report.status), <CockpitReplayStatus>[
        CockpitReplayStatus.passed,
        CockpitReplayStatus.deviated,
        CockpitReplayStatus.passed,
      ]);
      expect(reports[1].reason, contains('Action failed'));
      expect(reports[1].reason, contains('pointer device exploded'));
      // All three steps really dispatched; one failure stops nothing.
      expect(performerCalls, <String>['a', 'b', 'c']);
    });

    test('a replay from paused leaves the phase machine untouched', () async {
      final registry = CockpitTargetRegistry()
        ..register(
          const CockpitTarget(
            registrationId: 'a',
            keyValue: 'a',
            routeName: '/',
          ),
        );
      final recorder = CockpitInteractionRecorder(
        registry: registry,
        waitForIdle:
            ({
              required Duration quietWindow,
              required Duration timeout,
            }) async => true,
        gesturePerformer: (_) async {},
      );
      recorder.start();
      recorder.recordInteractionStep(
        _pendingStep(
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[_keyCandidate('a')],
        ),
      );
      recorder.pause();

      final reports = await recorder.verifyReplay();

      expect(reports.single.status, CockpitReplayStatus.passed);
      expect(recorder.phase, CockpitRecorderPhase.paused);
      expect(recorder.isReplaying, isFalse);
    });

    test('export stays legal while a replay is in flight', () async {
      final registry = CockpitTargetRegistry()
        ..register(
          const CockpitTarget(
            registrationId: 'a',
            keyValue: 'a',
            routeName: '/',
          ),
        );
      CockpitRecordedFlowBundle? exportedMidReplay;
      late final CockpitInteractionRecorder recorder;
      recorder = CockpitInteractionRecorder(
        registry: registry,
        waitForIdle:
            ({
              required Duration quietWindow,
              required Duration timeout,
            }) async => true,
        gesturePerformer: (_) async {
          exportedMidReplay ??= recorder.export();
        },
      );
      recorder.start();
      recorder.recordInteractionStep(
        _pendingStep(
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[_keyCandidate('a')],
        ),
      );

      final reports = await recorder.verifyReplay();

      expect(reports.single.status, CockpitReplayStatus.passed);
      expect(exportedMidReplay, isNotNull);
      expect(exportedMidReplay!.caseDocument['id'], 'recorded-r1');
    });

    test(
      'dispatches longPress and scroll steps through the performer',
      () async {
        final registry = CockpitTargetRegistry()
          ..register(
            const CockpitTarget(
              registrationId: 'hold',
              keyValue: 'hold',
              routeName: '/',
            ),
          )
          ..register(
            const CockpitTarget(
              registrationId: 'list',
              keyValue: 'list',
              routeName: '/',
            ),
          );
        final actions = <CockpitGestureAction>[];
        final recorder = CockpitInteractionRecorder(
          registry: registry,
          waitForIdle:
              ({
                required Duration quietWindow,
                required Duration timeout,
              }) async => true,
          gesturePerformer: (action) async => actions.add(action),
        );
        recorder.start();
        recorder.recordInteractionStep(
          _pendingStep(
            CockpitInteractionStepKind.longPress,
            candidates: <CockpitLocatorCandidate>[_keyCandidate('hold')],
          ),
        );
        for (final direction in CockpitInteractionScrollDirection.values) {
          recorder.recordInteractionStep(
            CockpitInteractionStep(
              stepId: 'pending',
              kind: CockpitInteractionStepKind.scroll,
              locatorCandidates: <CockpitLocatorCandidate>[
                _keyCandidate('list'),
              ],
              scrollDirection: direction,
              phase: CockpitRecorderPhase.recording,
              recordedAt: DateTime.utc(2026, 10, 7, 9),
            ),
          );
        }

        final reports = await recorder.verifyReplay();

        expect(
          reports.map((report) => report.status),
          everyElement(CockpitReplayStatus.passed),
        );
        expect(actions.map((action) => action.type), <CockpitGestureActionType>[
          CockpitGestureActionType.longPress,
          ...List<CockpitGestureActionType>.filled(
            CockpitInteractionScrollDirection.values.length,
            CockpitGestureActionType.swipe,
          ),
        ]);
        expect(actions[0].target!.keyValue, 'hold');
        expect(
          actions.skip(1).map((action) => action.direction),
          CockpitInteractionScrollDirection.values.map(
            (direction) => switch (direction) {
              CockpitInteractionScrollDirection.up => AxisDirection.up,
              CockpitInteractionScrollDirection.down => AxisDirection.down,
              CockpitInteractionScrollDirection.left => AxisDirection.left,
              CockpitInteractionScrollDirection.right => AxisDirection.right,
            },
          ),
        );
      },
    );

    test(
      'a scroll before a target swipes until the target joins the registry',
      () async {
        final registry = CockpitTargetRegistry();
        var swipes = 0;
        final recorder = CockpitInteractionRecorder(
          registry: registry,
          waitForIdle:
              ({
                required Duration quietWindow,
                required Duration timeout,
              }) async => true,
          gesturePerformer: (action) async {
            if (action.type == CockpitGestureActionType.swipe) {
              swipes += 1;
              if (swipes == 2) {
                // The target sits below the fold and only joins the tree
                // once the list has scrolled.
                registry.register(
                  const CockpitTarget(
                    registrationId: 'buy-now',
                    keyValue: 'buy-now',
                    routeName: '/',
                  ),
                );
              }
            }
          },
        );
        recorder.start();
        // The finger landed on unregistered list content; the flow still
        // needs the scroll to reveal the button below the fold.
        recorder.recordInteractionStep(
          _pendingStep(
            CockpitInteractionStepKind.scroll,
            unresolved: true,
            direction: CockpitInteractionScrollDirection.up,
          ),
        );
        recorder.recordInteractionStep(
          _pendingStep(
            CockpitInteractionStepKind.tap,
            candidates: <CockpitLocatorCandidate>[_keyCandidate('buy-now')],
          ),
        );

        final reports = await recorder.verifyReplay();

        expect(reports[0].status, CockpitReplayStatus.passed);
        expect(swipes, 2);
        expect(reports[1].status, CockpitReplayStatus.passed);
      },
    );

    test(
      'a goal-directed scroll deviates after six swipes without a reveal',
      () async {
        final registry = CockpitTargetRegistry();
        var swipes = 0;
        final recorder = CockpitInteractionRecorder(
          registry: registry,
          waitForIdle:
              ({
                required Duration quietWindow,
                required Duration timeout,
              }) async => true,
          gesturePerformer: (action) async {
            if (action.type == CockpitGestureActionType.swipe) {
              swipes += 1;
            }
          },
        );
        recorder.start();
        recorder.recordInteractionStep(
          _pendingStep(
            CockpitInteractionStepKind.scroll,
            direction: CockpitInteractionScrollDirection.up,
            candidates: <CockpitLocatorCandidate>[_keyCandidate('list')],
          ),
        );
        recorder.recordInteractionStep(
          _pendingStep(
            CockpitInteractionStepKind.tap,
            candidates: <CockpitLocatorCandidate>[_keyCandidate('gone')],
          ),
        );

        final reports = await recorder.verifyReplay();

        expect(swipes, 6);
        expect(reports[0].status, CockpitReplayStatus.deviated);
        expect(reports[0].reason, contains('Scrolled 6 times'));
        expect(reports[1].status, CockpitReplayStatus.deviated);
      },
    );

    test(
      'a goal-directed swipe runs from the recorded grab position',
      () async {
        final registry = CockpitTargetRegistry();
        Offset? swipeOrigin;
        var sawTarget = false;
        final recorder = CockpitInteractionRecorder(
          registry: registry,
          waitForIdle:
              ({
                required Duration quietWindow,
                required Duration timeout,
              }) async => true,
          gesturePerformer: (action) async {
            if (action.type == CockpitGestureActionType.swipe) {
              swipeOrigin = action.origin;
              sawTarget = action.target != null;
              registry.register(
                const CockpitTarget(
                  registrationId: 'buy-now',
                  keyValue: 'buy-now',
                  routeName: '/',
                ),
              );
            }
          },
        );
        recorder.start();
        // The scroll's own candidate never resolves, so the swipe must run
        // from where the finger grabbed the list.
        recorder.recordInteractionStep(
          _pendingStep(
            CockpitInteractionStepKind.scroll,
            direction: CockpitInteractionScrollDirection.up,
            candidates: <CockpitLocatorCandidate>[_keyCandidate('unmade')],
            positionDx: 120,
            positionDy: 420,
          ),
        );
        recorder.recordInteractionStep(
          _pendingStep(
            CockpitInteractionStepKind.tap,
            candidates: <CockpitLocatorCandidate>[_keyCandidate('buy-now')],
          ),
        );

        final reports = await recorder.verifyReplay();

        expect(swipeOrigin, const Offset(120, 420));
        expect(sawTarget, isFalse);
        expect(reports[0].status, CockpitReplayStatus.passed);
      },
    );

    test(
      'a tap whose target left the viewport is revealed by bounded scrolling',
      () async {
        final registry = CockpitTargetRegistry();
        var swipes = 0;
        Offset? swipeOrigin;
        final recorder = CockpitInteractionRecorder(
          registry: registry,
          waitForIdle:
              ({
                required Duration quietWindow,
                required Duration timeout,
              }) async => true,
          gesturePerformer: (action) async {
            if (action.type == CockpitGestureActionType.swipe) {
              swipes += 1;
              swipeOrigin = action.origin;
              if (swipes == 2) {
                // The recorded row was visible while recording; at replay
                // width it sits below the fold and only rejoins the tree
                // once the list has scrolled.
                registry.register(
                  const CockpitTarget(
                    registrationId: 'off-fold',
                    keyValue: 'off-fold',
                    routeName: '/',
                  ),
                );
              }
            }
          },
        );
        recorder.start();
        recorder.recordInteractionStep(
          _pendingStep(
            CockpitInteractionStepKind.tap,
            candidates: <CockpitLocatorCandidate>[_keyCandidate('off-fold')],
            positionDx: 160,
            positionDy: 380,
          ),
        );

        final reports = await recorder.verifyReplay();

        expect(swipes, 2);
        expect(swipeOrigin, const Offset(160, 380));
        expect(reports[0].status, CockpitReplayStatus.passed);
      },
    );

    test('a reveal target above the starting position is reached after '
        'backtracking', () async {
      final registry = CockpitTargetRegistry();
      var swipes = 0;
      final directions = <AxisDirection>[];
      final recorder = CockpitInteractionRecorder(
        registry: registry,
        waitForIdle:
            ({
              required Duration quietWindow,
              required Duration timeout,
            }) async => true,
        gesturePerformer: (action) async {
          if (action.type == CockpitGestureActionType.swipe) {
            swipes += 1;
            directions.add(action.direction);
            if (swipes == 8) {
              // The recorded row sits above the reveal's starting
              // position: the first direction walks away from it, and it
              // only rejoins the tree once the second direction has
              // backtracked past where the reveal began.
              registry.register(
                const CockpitTarget(
                  registrationId: 'off-top',
                  keyValue: 'off-top',
                  routeName: '/',
                ),
              );
            }
          }
        },
      );
      recorder.start();
      recorder.recordInteractionStep(
        _pendingStep(
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[_keyCandidate('off-top')],
          positionDx: 160,
          positionDy: 380,
        ),
      );

      final reports = await recorder.verifyReplay();

      expect(swipes, 8);
      expect(
        directions,
        orderedEquals(
          List<AxisDirection>.filled(6, AxisDirection.up) +
              List<AxisDirection>.filled(2, AxisDirection.down),
        ),
      );
      expect(reports[0].status, CockpitReplayStatus.passed);
    });

    test(
      'a reveal that finds nothing exhausts the doubled second direction',
      () async {
        final registry = CockpitTargetRegistry();
        var swipes = 0;
        final recorder = CockpitInteractionRecorder(
          registry: registry,
          waitForIdle:
              ({
                required Duration quietWindow,
                required Duration timeout,
              }) async => true,
          gesturePerformer: (action) async {
            if (action.type == CockpitGestureActionType.swipe) {
              swipes += 1;
            }
          },
        );
        recorder.start();
        recorder.recordInteractionStep(
          _pendingStep(
            CockpitInteractionStepKind.tap,
            candidates: <CockpitLocatorCandidate>[_keyCandidate('gone')],
            positionDx: 160,
            positionDy: 380,
          ),
        );

        final reports = await recorder.verifyReplay();

        expect(swipes, 18);
        expect(reports[0].status, CockpitReplayStatus.deviated);
      },
    );

    test(
      'a recorded route change waits for the live route to arrive',
      () async {
        final registry = CockpitTargetRegistry()
          ..register(
            const CockpitTarget(
              registrationId: 'open',
              keyValue: 'open',
              routeName: '/inbox',
            ),
          );
        var route = '/inbox';
        var idleCalls = 0;
        final recorder = CockpitInteractionRecorder(
          registry: registry,
          routeNameProvider: () => route,
          gesturePerformer: (action) async {},
          waitForIdle:
              ({
                required Duration quietWindow,
                required Duration timeout,
              }) async {
                idleCalls += 1;
                if (idleCalls == 3) {
                  // The pop the first tap triggered lands a couple of
                  // settle beats later, like real navigation does.
                  route = '/editor';
                  registry.register(
                    const CockpitTarget(
                      registrationId: 'compose',
                      keyValue: 'compose',
                      routeName: '/editor',
                    ),
                  );
                }
                return true;
              },
        );
        recorder.start();
        recorder.recordInteractionStep(
          _pendingStep(
            CockpitInteractionStepKind.tap,
            candidates: <CockpitLocatorCandidate>[_keyCandidate('open')],
          ),
        );
        recorder.recordInteractionStep(
          _pendingStep(
            CockpitInteractionStepKind.routeChange,
            routeName: '/editor',
          ),
        );
        recorder.recordInteractionStep(
          _pendingStep(
            CockpitInteractionStepKind.tap,
            candidates: <CockpitLocatorCandidate>[_keyCandidate('compose')],
          ),
        );

        final reports = await recorder.verifyReplay();

        // Two settle beats ran between the route change and the step after
        // it — without the sync point the compose tap would resolve
        // against the outgoing screen's registry state.
        expect(idleCalls, 5);
        expect(reports.map((report) => report.status), <CockpitReplayStatus>[
          CockpitReplayStatus.passed,
          CockpitReplayStatus.skipped,
          CockpitReplayStatus.passed,
        ]);
      },
    );

    test(
      'a route change that never arrives gives up within its budget',
      () async {
        var idleCalls = 0;
        final recorder = CockpitInteractionRecorder(
          registry: CockpitTargetRegistry()
            ..register(
              const CockpitTarget(
                registrationId: 'open',
                keyValue: 'open',
                routeName: '/inbox',
              ),
            ),
          routeNameProvider: () => '/inbox',
          gesturePerformer: (action) async {},
          waitForIdle:
              ({
                required Duration quietWindow,
                required Duration timeout,
              }) async {
                idleCalls += 1;
                return true;
              },
        );
        recorder.start();
        recorder.recordInteractionStep(
          _pendingStep(
            CockpitInteractionStepKind.tap,
            candidates: <CockpitLocatorCandidate>[_keyCandidate('open')],
          ),
        );
        recorder.recordInteractionStep(
          _pendingStep(
            CockpitInteractionStepKind.routeChange,
            routeName: '/editor',
          ),
        );

        final reports = await recorder.verifyReplay();

        expect(reports[0].status, CockpitReplayStatus.passed);
        // The route change stays non-actionable: 100 poll beats plus the
        // per-step settles bound the wait.
        expect(reports[1].status, CockpitReplayStatus.skipped);
        expect(idleCalls, lessThanOrEqualTo(102));
        expect(idleCalls, greaterThan(100));
      },
    );

    test(
      'a trailing scroll swipes toward its own grab-point candidate',
      () async {
        final registry = CockpitTargetRegistry();
        var swipes = 0;
        final recorder = CockpitInteractionRecorder(
          registry: registry,
          waitForIdle:
              ({
                required Duration quietWindow,
                required Duration timeout,
              }) async => true,
          gesturePerformer: (action) async {
            if (action.type == CockpitGestureActionType.swipe) {
              swipes += 1;
              if (swipes == 2) {
                // The row the finger grabbed sits below the fold at
                // replay; the scroll exists to bring it back.
                registry.register(
                  const CockpitTarget(
                    registrationId: 'filler-row',
                    keyValue: 'filler-row',
                    routeName: '/',
                  ),
                );
              }
            }
          },
        );
        recorder.start();
        recorder.recordInteractionStep(
          _pendingStep(
            CockpitInteractionStepKind.scroll,
            direction: CockpitInteractionScrollDirection.up,
            candidates: <CockpitLocatorCandidate>[_keyCandidate('filler-row')],
            positionDx: 120,
            positionDy: 420,
          ),
        );

        final reports = await recorder.verifyReplay();

        expect(swipes, 2);
        expect(reports.single.status, CockpitReplayStatus.passed);
      },
    );

    test('a route boundary stops the scroll target search', () async {
      final registry = CockpitTargetRegistry()
        ..register(
          const CockpitTarget(
            registrationId: 'list',
            keyValue: 'list',
            routeName: '/',
          ),
        )
        ..register(
          const CockpitTarget(
            registrationId: 'back-arrow',
            keyValue: 'back-arrow',
            routeName: '/details',
          ),
        );
      final swipes = <CockpitGestureAction>[];
      final recorder = CockpitInteractionRecorder(
        registry: registry,
        waitForIdle:
            ({
              required Duration quietWindow,
              required Duration timeout,
            }) async => true,
        gesturePerformer: (action) async => swipes.add(action),
      );
      recorder.start();
      recorder.recordInteractionStep(
        _pendingStep(
          CockpitInteractionStepKind.scroll,
          direction: CockpitInteractionScrollDirection.up,
          candidates: <CockpitLocatorCandidate>[_keyCandidate('list')],
        ),
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
          candidates: <CockpitLocatorCandidate>[_keyCandidate('back-arrow')],
        ),
      );

      final reports = await recorder.verifyReplay();

      // The scroll belongs to the previous screen: one swipe on its own
      // candidate, not a hunt for the next screen's target.
      expect(
        swipes.where((a) => a.type == CockpitGestureActionType.swipe),
        hasLength(1),
      );
      expect(reports[0].status, CockpitReplayStatus.passed);
    });

    test('replays text steps through the handler preference order', () async {
      final entered = <String>[];
      final registry = CockpitTargetRegistry()
        ..register(
          CockpitTarget(
            registrationId: 'enter',
            routeName: '/',
            keyValue: 'enter',
            onEnterText: (text) async => entered.add('enter:$text'),
          ),
        )
        ..register(
          CockpitTarget(
            registrationId: 'semantic-enter',
            routeName: '/',
            keyValue: 'semantic-enter',
            onSemanticEnterText: (text) => entered.add('semantic-enter:$text'),
          ),
        )
        ..register(
          CockpitTarget(
            registrationId: 'mute',
            routeName: '/',
            keyValue: 'mute',
          ),
        );
      final recorder = CockpitInteractionRecorder(
        registry: registry,
        waitForIdle:
            ({
              required Duration quietWindow,
              required Duration timeout,
            }) async => true,
      );
      recorder.start();
      for (final key in <String>['enter', 'semantic-enter', 'mute']) {
        recorder.recordInteractionStep(
          CockpitInteractionStep(
            stepId: 'pending',
            kind: CockpitInteractionStepKind.text,
            locatorCandidates: <CockpitLocatorCandidate>[_keyCandidate(key)],
            resolvedValue: 'typed into $key',
            phase: CockpitRecorderPhase.recording,
            recordedAt: DateTime.utc(2026, 10, 7, 9),
          ),
        );
      }

      final reports = await recorder.verifyReplay();

      // The string-based enter-text handler backs a target without the
      // request-based one, and a target accepting no text at all deviates
      // instead of silently passing.
      expect(reports.map((report) => report.status), <CockpitReplayStatus>[
        CockpitReplayStatus.passed,
        CockpitReplayStatus.passed,
        CockpitReplayStatus.deviated,
      ]);
      expect(reports[2].reason, contains('does not accept text entry'));
      expect(entered, <String>[
        'enter:typed into enter',
        'semantic-enter:typed into semantic-enter',
      ]);
    });

    testWidgets('a bare recorder replays through the default wiring', (
      tester,
    ) async {
      // No injected waiter or performer: the recorder lazily creates its
      // gesture engine and settles through the scheduler-quiet default wait
      // (a no-op shortcut under a test binding, so the awaited pass needs no
      // external pumping). The root stays recorder-disabled (so it wires
      // nothing) while a manually mounted capture layer provides the
      // discovery surface and proves replay suppression end to end.
      var presses = 0;
      FlutterCockpit.initialize(const FlutterCockpitConfiguration());
      final recorder = CockpitInteractionRecorder(
        registry: FlutterCockpit.binding.registry,
      );
      await tester.pumpWidget(
        FlutterCockpitRoot(
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: CockpitInteractionCapture(
                  recorder: recorder,
                  registry: FlutterCockpit.binding.registry,
                  routeName: '/',
                  child: ElevatedButton(
                    key: const ValueKey<String>('bare-button'),
                    onPressed: () => presses += 1,
                    child: const Text('Press'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      recorder.start();
      recorder.recordInteractionStep(
        _pendingStep(
          CockpitInteractionStepKind.tap,
          candidates: <CockpitLocatorCandidate>[_keyCandidate('bare-button')],
          routeName: '/',
        ),
      );

      final reports = await recorder.verifyReplay();
      await tester.pumpAndSettle();

      expect(reports.single.status, CockpitReplayStatus.passed);
      expect(presses, 1);
      expect(recorder.isReplaying, isFalse);
      // The capture layer suppressed the replayed tap from re-recording.
      expect(recorder.steps, hasLength(1));
    });
  });
}
