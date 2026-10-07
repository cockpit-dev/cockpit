import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [child] under a [FlutterCockpitRoot] whose recorder is enabled and
/// returns the mounted recorder. [defaults] injects capture thresholds.
Future<CockpitInteractionRecorder> pumpRecordingApp(
  WidgetTester tester, {
  required Widget child,
  CockpitInteractionCaptureDefaults defaults =
      const CockpitInteractionCaptureDefaults(),
}) async {
  FlutterCockpit.initialize(
    FlutterCockpitConfiguration(
      recorder: FlutterCockpitRecorderConfig(enabled: true, defaults: defaults),
    ),
  );
  final rootKey = GlobalKey<FlutterCockpitRootState>();
  await tester.pumpWidget(FlutterCockpitRoot(key: rootKey, child: child));
  await tester.pumpAndSettle();
  final recorder = rootKey.currentState!.interactionRecorder;
  assert(recorder != null, 'The recorder must mount when enabled.');
  return recorder!;
}

/// Advances the fake clock past the default settle window so pending settle
/// watches finish before the test ends.
Future<void> pumpSettleWindow(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 700));
}

Widget _homeApp({required Widget body}) {
  return MaterialApp(
    navigatorObservers: [FlutterCockpit.navigatorObserver],
    home: Scaffold(body: Center(child: body)),
  );
}

void main() {
  tearDown(FlutterCockpit.dispose);

  group('pointer capture', () {
    testWidgets('records a tap with ordered candidates and settle time', (
      tester,
    ) async {
      final recorder = await pumpRecordingApp(
        tester,
        child: _homeApp(
          body: const SizedBox(
            key: ValueKey<String>('zone'),
            width: 200,
            height: 80,
            child: ColoredBox(color: Colors.blue),
          ),
        ),
      );
      final zoneElement = tester.element<Element>(
        find.byKey(const ValueKey<String>('zone')),
      );
      FlutterCockpit.binding.registry.register(
        CockpitTarget(
          registrationId: 'explicit-zone',
          keyValue: 'save-button',
          semanticId: 'save',
          text: 'Save',
          tooltip: 'Saves the form',
          typeName: 'CustomZone',
          routeName: '/',
          diagnosticNodeProvider: () => zoneElement,
        ),
      );

      recorder.start();
      await tester.tap(find.byKey(const ValueKey<String>('zone')));
      await tester.pumpAndSettle();

      expect(recorder.steps, hasLength(1));
      final step = recorder.steps.single;
      expect(step.kind, CockpitInteractionStepKind.tap);
      expect(step.unresolved, isFalse);
      expect(step.routeName, '/');
      expect(
        step.locatorCandidates.map((candidate) => candidate.selector),
        equals(<String>[
          CockpitSelector.format(const CockpitLocator(key: 'save-button')),
          CockpitSelector.format(const CockpitLocator(semanticId: 'save')),
          CockpitSelector.format(const CockpitLocator(text: 'Save')),
          CockpitSelector.format(
            const CockpitLocator(tooltip: 'Saves the form'),
          ),
          CockpitSelector.format(const CockpitLocator(type: 'CustomZone')),
        ]),
      );
      expect(
        step.locatorCandidates.map((candidate) => candidate.score),
        equals(const <int>[4, 3, 2, 1, 0]),
      );
      final zoneCenter = tester.getCenter(
        find.byKey(const ValueKey<String>('zone')),
      );
      expect(step.positionDx, zoneCenter.dx);
      expect(step.positionDy, zoneCenter.dy);

      await pumpSettleWindow(tester);
      expect(recorder.steps.single.settledAfterMs, greaterThanOrEqualTo(300));
    });

    testWidgets('records a discovered keyed button tap with the key first', (
      tester,
    ) async {
      final recorder = await pumpRecordingApp(
        tester,
        child: _homeApp(
          body: ElevatedButton(
            key: const ValueKey<String>('compose-button'),
            onPressed: () {},
            child: const Text('Compose'),
          ),
        ),
      );

      recorder.start();
      await tester.tap(find.text('Compose'));
      await tester.pumpAndSettle();
      await pumpSettleWindow(tester);

      expect(recorder.steps, hasLength(1));
      final step = recorder.steps.single;
      expect(step.kind, CockpitInteractionStepKind.tap);
      expect(step.unresolved, isFalse);
      expect(
        step.locatorCandidates.first.selector,
        CockpitSelector.format(const CockpitLocator(key: 'compose-button')),
      );
    });

    testWidgets('records a long press when the hold reaches the threshold', (
      tester,
    ) async {
      final recorder = await pumpRecordingApp(
        tester,
        child: _homeApp(
          body: ElevatedButton(
            key: const ValueKey<String>('hold-button'),
            onPressed: () {},
            child: const Text('Hold'),
          ),
        ),
        defaults: const CockpitInteractionCaptureDefaults(longPressMs: 0),
      );

      recorder.start();
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Hold')),
      );
      await tester.pump(const Duration(milliseconds: 20));
      await gesture.up();
      await tester.pumpAndSettle();
      await pumpSettleWindow(tester);

      expect(recorder.steps, hasLength(1));
      expect(recorder.steps.single.kind, CockpitInteractionStepKind.longPress);
    });

    testWidgets('records a scroll with the dominant-axis direction', (
      tester,
    ) async {
      final recorder = await pumpRecordingApp(
        tester,
        child: MaterialApp(
          navigatorObservers: [FlutterCockpit.navigatorObserver],
          home: Scaffold(
            body: ListView.builder(
              itemCount: 40,
              itemBuilder: (context, index) => ListTile(
                key: ValueKey<String>('item-$index'),
                title: Text('Item $index'),
              ),
            ),
          ),
        ),
      );

      recorder.start();
      await tester.drag(find.text('Item 3'), const Offset(0, -240));
      await tester.pumpAndSettle();
      await pumpSettleWindow(tester);

      final steps = recorder.steps;
      expect(steps, isNotEmpty);
      final scrollStep = steps.firstWhere(
        (step) => step.kind == CockpitInteractionStepKind.scroll,
      );
      expect(scrollStep.scrollDirection, CockpitInteractionScrollDirection.up);
      expect(scrollStep.unresolved, isFalse);
    });

    testWidgets('drops gestures whose hit path is exclusion-marked', (
      tester,
    ) async {
      final recorder = await pumpRecordingApp(
        tester,
        child: _homeApp(
          body: const CockpitRecorderExclude(
            child: SizedBox(
              key: ValueKey<String>('excluded-zone'),
              width: 200,
              height: 80,
              child: ColoredBox(color: Colors.red),
            ),
          ),
        ),
      );

      recorder.start();
      await tester.tap(find.byKey(const ValueKey<String>('excluded-zone')));
      await tester.pumpAndSettle();
      await pumpSettleWindow(tester);

      expect(recorder.steps, isEmpty);
    });

    testWidgets('drops gestures inside a registry-excluded subtree', (
      tester,
    ) async {
      final recorder = await pumpRecordingApp(
        tester,
        child: _homeApp(
          body: const SizedBox(
            key: ValueKey<String>('registry-zone'),
            width: 200,
            height: 80,
            child: ColoredBox(color: Colors.green),
          ),
        ),
      );
      final zoneRenderObject = tester.renderObject<RenderObject>(
        find.byKey(const ValueKey<String>('registry-zone')),
      );

      recorder.start();
      recorder.exclusions.register(zoneRenderObject);
      await tester.tap(find.byKey(const ValueKey<String>('registry-zone')));
      await tester.pumpAndSettle();
      expect(recorder.steps, isEmpty);

      recorder.exclusions.unregister(zoneRenderObject);
      await tester.tap(find.byKey(const ValueKey<String>('registry-zone')));
      await tester.pumpAndSettle();
      await pumpSettleWindow(tester);
      expect(recorder.steps, hasLength(1));
      // The keyed zone is a discovered target once the exclusion lifts.
      expect(recorder.steps.single.unresolved, isFalse);
      expect(
        recorder.steps.single.locatorCandidates.first.selector,
        CockpitSelector.format(const CockpitLocator(key: 'registry-zone')),
      );
    });

    testWidgets('records an unresolved step for taps hitting no target', (
      tester,
    ) async {
      final recorder = await pumpRecordingApp(
        tester,
        child: _homeApp(
          body: const ElevatedButton(onPressed: null, child: Text('Far away')),
        ),
      );

      recorder.start();
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      await pumpSettleWindow(tester);

      expect(recorder.steps, hasLength(1));
      final step = recorder.steps.single;
      expect(step.kind, CockpitInteractionStepKind.tap);
      expect(step.unresolved, isTrue);
      expect(step.locatorCandidates, isEmpty);
      expect(step.positionDx, 4);
      expect(step.positionDy, 4);
    });

    testWidgets('drops cancelled gestures', (tester) async {
      final recorder = await pumpRecordingApp(
        tester,
        child: _homeApp(
          body: ElevatedButton(
            key: const ValueKey<String>('cancel-button'),
            onPressed: () {},
            child: const Text('Cancel me'),
          ),
        ),
      );

      recorder.start();
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Cancel me')),
      );
      await gesture.cancel();
      await tester.pumpAndSettle();
      await pumpSettleWindow(tester);

      expect(recorder.steps, isEmpty);
    });

    testWidgets('ignores concurrent pointers while the first is active', (
      tester,
    ) async {
      final recorder = await pumpRecordingApp(
        tester,
        child: _homeApp(
          body: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                key: const ValueKey<String>('first-zone'),
                width: 200,
                height: 60,
                child: const ColoredBox(color: Colors.blue),
              ),
              SizedBox(
                key: const ValueKey<String>('second-zone'),
                width: 200,
                height: 60,
                child: const ColoredBox(color: Colors.purple),
              ),
            ],
          ),
        ),
      );

      recorder.start();
      final first = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey<String>('first-zone'))),
        pointer: 7,
      );
      final second = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey<String>('second-zone'))),
        pointer: 8,
      );
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      await pumpSettleWindow(tester);

      expect(recorder.steps, hasLength(1));
      // Only the first pointer records; its keyed zone is a discovered
      // target, so the step resolves through the key signal.
      expect(recorder.steps.single.unresolved, isFalse);
      expect(
        recorder.steps.single.locatorCandidates.first.selector,
        CockpitSelector.format(const CockpitLocator(key: 'first-zone')),
      );
    });

    testWidgets('suppresses taps while paused and records after resume', (
      tester,
    ) async {
      final recorder = await pumpRecordingApp(
        tester,
        child: _homeApp(
          body: const SizedBox(
            key: ValueKey<String>('pause-zone'),
            width: 200,
            height: 80,
            child: ColoredBox(color: Colors.blue),
          ),
        ),
      );

      recorder.start();
      recorder.pause();
      await tester.tap(find.byKey(const ValueKey<String>('pause-zone')));
      await tester.pumpAndSettle();
      expect(recorder.steps, isEmpty);

      recorder.resume();
      await tester.tap(find.byKey(const ValueKey<String>('pause-zone')));
      await tester.pumpAndSettle();
      await pumpSettleWindow(tester);
      expect(recorder.steps, hasLength(1));
    });

    testWidgets('skips the settle back-fill once the session stopped', (
      tester,
    ) async {
      final recorder = await pumpRecordingApp(
        tester,
        child: _homeApp(
          body: const SizedBox(
            key: ValueKey<String>('stop-zone'),
            width: 200,
            height: 80,
            child: ColoredBox(color: Colors.blue),
          ),
        ),
      );

      recorder.start();
      await tester.tap(find.byKey(const ValueKey<String>('stop-zone')));
      await tester.pumpAndSettle();
      recorder.stop();

      await pumpSettleWindow(tester);
      expect(recorder.steps.single.settledAfterMs, isNull);
    });

    testWidgets('skips the settle back-fill for a discarded step', (
      tester,
    ) async {
      final recorder = await pumpRecordingApp(
        tester,
        child: _homeApp(
          body: const SizedBox(
            key: ValueKey<String>('discard-zone'),
            width: 200,
            height: 80,
            child: ColoredBox(color: Colors.blue),
          ),
        ),
      );

      recorder.start();
      await tester.tap(find.byKey(const ValueKey<String>('discard-zone')));
      await tester.pumpAndSettle();
      recorder.discardLastStep();

      await pumpSettleWindow(tester);
      expect(recorder.steps, isEmpty);
    });
  });

  group('text capture', () {
    testWidgets('records one text step with the field value and candidates', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final recorder = await pumpRecordingApp(
        tester,
        child: _homeApp(
          body: TextField(
            key: const ValueKey<String>('task-input'),
            controller: controller,
          ),
        ),
      );

      recorder.start();
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pumpAndSettle();

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      expect(recorder.steps, hasLength(1));
      final step = recorder.steps.single;
      expect(step.kind, CockpitInteractionStepKind.text);
      expect(step.resolvedValue, 'hello');
      expect(step.unresolved, isFalse);
      expect(
        step.locatorCandidates.first.selector,
        CockpitSelector.format(const CockpitLocator(key: 'task-input')),
      );
    });

    testWidgets('skips empty text values', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final recorder = await pumpRecordingApp(
        tester,
        child: _homeApp(
          body: TextField(
            key: const ValueKey<String>('empty-input'),
            controller: controller,
          ),
        ),
      );

      recorder.start();
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      expect(recorder.steps, isEmpty);
    });

    testWidgets('stop flushes a still-focused field into the result', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final recorder = await pumpRecordingApp(
        tester,
        child: _homeApp(
          body: TextField(
            key: const ValueKey<String>('stop-input'),
            controller: controller,
          ),
        ),
      );

      recorder.start();
      await tester.enterText(find.byType(TextField), 'draft');
      await tester.pumpAndSettle();
      // Stop without unfocusing: the before-stop hook flushes the pending
      // field while the session still accepts steps, so the text lands in
      // the result.
      final result = recorder.stop();
      expect(
        result.steps
            .where((step) => step.kind == CockpitInteractionStepKind.text)
            .single
            .resolvedValue,
        'draft',
      );

      // The flushed field is no longer tracked; a later focus change adds
      // nothing to a stopped session.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(
        recorder.steps.where(
          (step) => step.kind == CockpitInteractionStepKind.text,
        ),
        hasLength(1),
      );
    });
  });

  group('route capture', () {
    testWidgets('records a route change while recording', (tester) async {
      final recorder = await pumpRecordingApp(
        tester,
        child: MaterialApp(
          navigatorObservers: [FlutterCockpit.navigatorObserver],
          routes: <String, WidgetBuilder>{
            '/': (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pushNamed('/details'),
                  child: const Text('Open details'),
                ),
              ),
            ),
            '/details': (_) =>
                const Scaffold(body: Center(child: Text('Details'))),
          },
        ),
      );

      recorder.start();
      await tester.tap(find.text('Open details'));
      await tester.pumpAndSettle();
      await pumpSettleWindow(tester);

      final routeSteps = recorder.steps
          .where((step) => step.kind == CockpitInteractionStepKind.routeChange)
          .toList();
      expect(routeSteps, hasLength(1));
      expect(routeSteps.single.fromRouteName, '/');
      expect(routeSteps.single.routeName, '/details');
    });

    testWidgets('suppresses route changes while paused', (tester) async {
      final recorder = await pumpRecordingApp(
        tester,
        child: MaterialApp(
          navigatorObservers: [FlutterCockpit.navigatorObserver],
          routes: <String, WidgetBuilder>{
            '/': (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pushNamed('/details'),
                  child: const Text('Open details'),
                ),
              ),
            ),
            '/details': (_) =>
                const Scaffold(body: Center(child: Text('Details'))),
          },
        ),
      );

      recorder.start();
      recorder.pause();
      await tester.tap(find.text('Open details'));
      await tester.pumpAndSettle();
      await pumpSettleWindow(tester);

      expect(recorder.steps, isEmpty);
    });
  });

  group('configuration', () {
    testWidgets('mounts no recorder or capture when disabled', (tester) async {
      FlutterCockpit.initialize(const FlutterCockpitConfiguration());
      final rootKey = GlobalKey<FlutterCockpitRootState>();
      await tester.pumpWidget(
        FlutterCockpitRoot(key: rootKey, child: const SizedBox.shrink()),
      );
      await tester.pumpAndSettle();

      expect(rootKey.currentState!.interactionRecorder, isNull);
      expect(find.byType(CockpitInteractionCapture), findsNothing);
    });

    testWidgets('mounts the recorder and capture when enabled', (tester) async {
      final recorder = await pumpRecordingApp(
        tester,
        child: const SizedBox.shrink(),
      );
      expect(recorder.phase, CockpitRecorderPhase.idle);
      expect(find.byType(CockpitInteractionCapture), findsOneWidget);
    });

    test('release-mode guard rejects an enabled recorder', () {
      const config = FlutterCockpitRecorderConfig(enabled: true);
      expect(
        () => assertFlutterCockpitRecorderBuildMode(
          config: config,
          releaseMode: true,
        ),
        throwsFlutterError,
      );
      expect(
        () => assertFlutterCockpitRecorderBuildMode(
          config: config,
          releaseMode: false,
        ),
        returnsNormally,
      );
      expect(
        () => assertFlutterCockpitRecorderBuildMode(
          config: const FlutterCockpitRecorderConfig(),
          releaseMode: true,
        ),
        returnsNormally,
      );
    });

    test('recorder config supports copyWith and value equality', () {
      const defaults = CockpitInteractionCaptureDefaults(longPressMs: 250);
      const config = FlutterCockpitRecorderConfig(defaults: defaults);
      const enabled = FlutterCockpitRecorderConfig(enabled: true);

      expect(config.enabled, isFalse);
      expect(config.host, CockpitRecorderHostMode.floatingBall);
      expect(config.defaults, defaults);

      final updated = enabled.copyWith(
        host: CockpitRecorderHostMode.headless,
        defaults: defaults,
      );
      expect(
        updated,
        const FlutterCockpitRecorderConfig(
          enabled: true,
          host: CockpitRecorderHostMode.headless,
          defaults: defaults,
        ),
      );
      expect(updated.host, CockpitRecorderHostMode.headless);
      expect(updated == enabled, isFalse);
      expect(updated.hashCode, isNot(equals(enabled.hashCode)));
    });

    test('defaults carry the documented thresholds', () {
      const defaults = CockpitInteractionCaptureDefaults();
      expect(defaults.tapSlopPx, 8.0);
      expect(defaults.longPressMs, 500);
      expect(defaults.scrollMinPx, 8.0);
      expect(defaults.settleQuietWindowMs, 300);
      expect(defaults.settleTimeoutMs, 5000);
      expect(
        defaults,
        equals(
          const CockpitInteractionCaptureDefaults(
            tapSlopPx: 8,
            longPressMs: 500,
            scrollMinPx: 8,
            settleQuietWindowMs: 300,
            settleTimeoutMs: 5000,
          ),
        ),
      );
      expect(
        const CockpitInteractionCaptureDefaults(longPressMs: 1).hashCode,
        isNot(equals(defaults.hashCode)),
      );
    });

    test('recorder config round-trips through both config classes', () {
      const recorder = FlutterCockpitRecorderConfig(
        enabled: true,
        host: CockpitRecorderHostMode.guest,
        defaults: CockpitInteractionCaptureDefaults(tapSlopPx: 12),
      );
      const config = FlutterCockpitConfig(recorder: recorder);
      final runtime = config.toRuntimeConfiguration();

      expect(runtime.recorder, recorder);
      expect(
        FlutterCockpitConfig.fromRuntimeConfiguration(runtime).recorder,
        recorder,
      );
      expect(
        runtime
            .copyWith(recorder: const FlutterCockpitRecorderConfig())
            .recorder
            .enabled,
        isFalse,
      );
      expect(
        runtime.copyWith(clearRecorder: true).recorder,
        const FlutterCockpitRecorderConfig(),
      );
    });
  });
}
