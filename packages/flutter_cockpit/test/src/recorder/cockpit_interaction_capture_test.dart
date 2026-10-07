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

    testWidgets('records horizontal and downward scrolls', (tester) async {
      final recorder = await pumpRecordingApp(
        tester,
        child: _homeApp(
          body: const SizedBox(
            key: ValueKey<String>('drag-pad'),
            width: 300,
            height: 300,
            child: ColoredBox(color: Colors.blue),
          ),
        ),
      );

      recorder.start();
      Future<void> dragBy(Offset delta) async {
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey<String>('drag-pad'))),
        );
        await tester.pump();
        await gesture.moveBy(delta);
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
      }

      await dragBy(const Offset(40, 0));
      await dragBy(const Offset(-40, 0));
      await dragBy(const Offset(0, 40));
      await pumpSettleWindow(tester);

      expect(
        recorder.steps
            .where((step) => step.kind == CockpitInteractionStepKind.scroll)
            .map((step) => step.scrollDirection),
        <CockpitInteractionScrollDirection>[
          CockpitInteractionScrollDirection.right,
          CockpitInteractionScrollDirection.left,
          CockpitInteractionScrollDirection.down,
        ],
      );
    });

    testWidgets('displacement at the scroll threshold scrolls, below taps', (
      tester,
    ) async {
      final recorder = await pumpRecordingApp(
        tester,
        child: _homeApp(
          body: const SizedBox(
            key: ValueKey<String>('threshold-pad'),
            width: 300,
            height: 300,
            child: ColoredBox(color: Colors.blue),
          ),
        ),
      );

      recorder.start();
      Future<CockpitInteractionStepKind> dragBy(Offset delta) async {
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey<String>('threshold-pad'))),
        );
        await tester.pump();
        await gesture.moveBy(delta);
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
        return recorder.steps.last.kind;
      }

      // Exactly the default scrollMinPx (8.0): a scroll.
      final atThreshold = await dragBy(const Offset(8, 0));
      // Just below it: a stationary-enough tap (real hold time stays far
      // under the 500ms long-press threshold).
      final belowThreshold = await dragBy(const Offset(7.9, 0));
      await pumpSettleWindow(tester);

      expect(atThreshold, CockpitInteractionStepKind.scroll);
      expect(belowThreshold, CockpitInteractionStepKind.tap);
    });

    testWidgets('a hold under the long-press threshold records a tap', (
      tester,
    ) async {
      final recorder = await pumpRecordingApp(
        tester,
        child: _homeApp(
          body: ElevatedButton(
            key: const ValueKey<String>('short-hold-button'),
            onPressed: () {},
            child: const Text('Short hold'),
          ),
        ),
      );

      recorder.start();
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Short hold')),
      );
      // The stopwatch measures real time, which stays far below the 500ms
      // default threshold however far the fake clock advances.
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.up();
      await tester.pumpAndSettle();
      await pumpSettleWindow(tester);

      expect(recorder.steps, hasLength(1));
      expect(recorder.steps.single.kind, CockpitInteractionStepKind.tap);
    });

    testWidgets('an ignored pointer releasing first misclassifies nothing', (
      tester,
    ) async {
      final recorder = await pumpRecordingApp(
        tester,
        child: _homeApp(
          body: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                key: const ValueKey<String>('held-zone'),
                width: 200,
                height: 60,
                child: const ColoredBox(color: Colors.blue),
              ),
              SizedBox(
                key: const ValueKey<String>('early-up-zone'),
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
        tester.getCenter(find.byKey(const ValueKey<String>('held-zone'))),
        pointer: 7,
      );
      final second = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey<String>('early-up-zone'))),
        pointer: 8,
      );
      await tester.pump();
      // The ignored pointer releases while the tracked one is still down.
      await second.up();
      await tester.pump();
      await first.up();
      await tester.pumpAndSettle();
      await pumpSettleWindow(tester);

      expect(recorder.steps, hasLength(1));
      expect(
        recorder.steps.single.locatorCandidates.first.selector,
        CockpitSelector.format(const CockpitLocator(key: 'held-zone')),
      );
    });

    testWidgets('exclusion is decided on pointer-down, not pointer-up', (
      tester,
    ) async {
      final recorder = await pumpRecordingApp(
        tester,
        child: _homeApp(
          body: const SizedBox(
            key: ValueKey<String>('mid-gesture-zone'),
            width: 200,
            height: 80,
            child: ColoredBox(color: Colors.blue),
          ),
        ),
      );
      final zoneRenderObject = tester.renderObject<RenderObject>(
        find.byKey(const ValueKey<String>('mid-gesture-zone')),
      );

      recorder.start();
      // Down inside a registered root, then the registration lifts: the
      // gesture was excluded when it started, so nothing records.
      recorder.exclusions.register(zoneRenderObject);
      var gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(const ValueKey<String>('mid-gesture-zone')),
        ),
      );
      await tester.pump();
      recorder.exclusions.unregister(zoneRenderObject);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(recorder.steps, isEmpty);

      // Down on free ground, then the subtree registers: the gesture was
      // already tracked, so it records normally.
      gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(const ValueKey<String>('mid-gesture-zone')),
        ),
      );
      await tester.pump();
      recorder.exclusions.register(zoneRenderObject);
      await gesture.up();
      await tester.pumpAndSettle();
      await pumpSettleWindow(tester);
      expect(recorder.steps, hasLength(1));
      recorder.exclusions.unregister(zoneRenderObject);
    });

    testWidgets('drops gestures on a marker nested deep in the hit path', (
      tester,
    ) async {
      final recorder = await pumpRecordingApp(
        tester,
        child: _homeApp(
          body: const CockpitRecorderExclude(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: SizedBox(
                  key: ValueKey<String>('deep-excluded-zone'),
                  width: 200,
                  height: 80,
                  child: ColoredBox(color: Colors.red),
                ),
              ),
            ),
          ),
        ),
      );

      recorder.start();
      await tester.tap(
        find.byKey(const ValueKey<String>('deep-excluded-zone')),
      );
      await tester.pumpAndSettle();
      await pumpSettleWindow(tester);

      expect(recorder.steps, isEmpty);
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

    testWidgets('unmounting the capture clears the hook and drops the field', (
      tester,
    ) async {
      // A manually mounted capture with a standalone recorder: the cockpit
      // root would dispose the recorder along with the capture, hiding the
      // detach behavior under test.
      FlutterCockpit.initialize(FlutterCockpitConfiguration());
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final recorder = CockpitInteractionRecorder();
      addTearDown(recorder.dispose);
      TextField field() => TextField(
        key: const ValueKey<String>('gone-input'),
        controller: controller,
      );
      Widget withCapture(Widget child) => CockpitInteractionCapture(
        recorder: recorder,
        registry: FlutterCockpit.binding.registry,
        routeName: '/',
        child: child,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: withCapture(field()))),
        ),
      );
      recorder.start();
      await tester.enterText(find.byType(TextField), 'pending');
      await tester.pumpAndSettle();
      expect(recorder.beforeStopHook, isNotNull);

      // Pump the same app without the capture: it detaches while the field
      // is still focused and tracked.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: field())),
        ),
      );
      await tester.pumpAndSettle();

      expect(recorder.beforeStopHook, isNull);
      final result = recorder.stop();
      expect(
        result.steps.where(
          (step) => step.kind == CockpitInteractionStepKind.text,
        ),
        isEmpty,
      );
    });

    testWidgets('records a bare EditableText, not just material TextField', (
      tester,
    ) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      final recorder = await pumpRecordingApp(
        tester,
        child: _homeApp(
          body: EditableText(
            key: const ValueKey<String>('bare-input'),
            controller: controller,
            focusNode: focusNode,
            style: const TextStyle(color: Colors.black),
            cursorColor: Colors.black,
            backgroundCursorColor: Colors.grey,
          ),
        ),
      );

      recorder.start();
      await tester.enterText(find.byType(EditableText), 'bare value');
      await tester.pumpAndSettle();

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      expect(recorder.steps, hasLength(1));
      final step = recorder.steps.single;
      expect(step.kind, CockpitInteractionStepKind.text);
      expect(step.resolvedValue, 'bare value');
      expect(step.unresolved, isFalse);
    });

    testWidgets('focus juggling two fields records both committed values', (
      tester,
    ) async {
      final first = TextEditingController();
      final second = TextEditingController();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final recorder = await pumpRecordingApp(
        tester,
        child: _homeApp(
          body: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              TextField(
                key: const ValueKey<String>('first-input'),
                controller: first,
              ),
              TextField(
                key: const ValueKey<String>('second-input'),
                controller: second,
              ),
            ],
          ),
        ),
      );

      recorder.start();
      await tester.enterText(
        find.byKey(const ValueKey<String>('first-input')),
        'first value',
      );
      await tester.pumpAndSettle();
      // Typing into the second field moves focus: the first flushes now.
      await tester.enterText(
        find.byKey(const ValueKey<String>('second-input')),
        'second value',
      );
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await pumpSettleWindow(tester);

      final textSteps = recorder.steps
          .where((step) => step.kind == CockpitInteractionStepKind.text)
          .toList();
      expect(textSteps.map((step) => step.resolvedValue), <String>[
        'first value',
        'second value',
      ]);
      expect(
        textSteps.map((step) => step.locatorCandidates.first.selector).toList(),
        <String>[
          CockpitSelector.format(const CockpitLocator(key: 'first-input')),
          CockpitSelector.format(const CockpitLocator(key: 'second-input')),
        ],
      );
    });

    testWidgets('a field unmounting while focused flushes nothing', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'doomed');
      addTearDown(controller.dispose);
      var mountedField = true;
      final recorder = await pumpRecordingApp(
        tester,
        child: _homeApp(
          body: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (mountedField)
                    TextField(
                      key: const ValueKey<String>('vanishing-input'),
                      controller: controller,
                    ),
                  ElevatedButton(
                    onPressed: () => setState(() => mountedField = false),
                    child: const Text('Remove field'),
                  ),
                ],
              );
            },
          ),
        ),
      );

      recorder.start();
      await tester.enterText(
        find.byKey(const ValueKey<String>('vanishing-input')),
        'doomed',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove field'));
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await pumpSettleWindow(tester);

      // The element (and its controller) went away mid-tracking: the flush
      // must drop the field instead of throwing or recording a phantom.
      expect(
        recorder.steps.where(
          (step) => step.kind == CockpitInteractionStepKind.text,
        ),
        isEmpty,
      );
    });

    testWidgets('a field inside an exclude marker records no text step', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final recorder = await pumpRecordingApp(
        tester,
        child: _homeApp(
          body: CockpitRecorderExclude(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                key: const ValueKey<String>('excluded-input'),
                controller: controller,
              ),
            ),
          ),
        ),
      );

      recorder.start();
      await tester.enterText(
        find.byKey(const ValueKey<String>('excluded-input')),
        'secret',
      );
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      // Focus leaving and a stop both stay silent for excluded chrome.
      expect(recorder.steps, isEmpty);
      final result = recorder.stop();
      expect(result.steps, isEmpty);
    });

    testWidgets('a field under a registry-excluded root records no text step', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final recorder = await pumpRecordingApp(
        tester,
        child: _homeApp(
          body: SizedBox(
            key: const ValueKey<String>('registry-text-host'),
            child: TextField(
              key: const ValueKey<String>('registry-input'),
              controller: controller,
            ),
          ),
        ),
      );
      final hostRenderObject = tester.renderObject<RenderObject>(
        find.byKey(const ValueKey<String>('registry-text-host')),
      );

      recorder.start();
      recorder.exclusions.register(hostRenderObject);
      await tester.enterText(
        find.byKey(const ValueKey<String>('registry-input')),
        'inner secret',
      );
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      recorder.exclusions.unregister(hostRenderObject);

      expect(recorder.steps, isEmpty);
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

    testWidgets('records a gesture-driven route change without an observer', (
      tester,
    ) async {
      // Apps that do not pass FlutterCockpit.navigatorObserver surface route
      // names only through read-driven discovery. The capture layer must
      // refresh discovery after the action settles, or a route change caused
      // by the recorded gesture itself stays undiscovered until the next
      // unrelated registry read.
      final recorder = await pumpRecordingApp(
        tester,
        child: MaterialApp(
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

    test('release-mode guard covers every host mode', () {
      for (final host in CockpitRecorderHostMode.values) {
        final enabled = FlutterCockpitRecorderConfig(enabled: true, host: host);
        expect(
          () => assertFlutterCockpitRecorderBuildMode(
            config: enabled,
            releaseMode: true,
          ),
          throwsFlutterError,
          reason: 'enabled ${host.name} in release',
        );
        expect(
          () => assertFlutterCockpitRecorderBuildMode(
            config: enabled,
            releaseMode: false,
          ),
          returnsNormally,
          reason: 'enabled ${host.name} in debug',
        );

        final disabled = FlutterCockpitRecorderConfig(host: host);
        expect(
          () => assertFlutterCockpitRecorderBuildMode(
            config: disabled,
            releaseMode: true,
          ),
          returnsNormally,
          reason: 'disabled ${host.name} in release',
        );
      }
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

      // copyWith with no argument keeps an equal configuration, and each
      // field updates in isolation.
      expect(enabled.copyWith(), enabled);
      expect(config.copyWith(enabled: true).enabled, isTrue);
      expect(
        config.copyWith(host: CockpitRecorderHostMode.guest).host,
        CockpitRecorderHostMode.guest,
      );
      expect(config.copyWith().defaults, defaults);
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

    test('defaults equality compares every field on distinct instances', () {
      // Distinct instances (not const-canonicalized) exercise the == body;
      // const instances would shortcut through identical().
      final a = CockpitInteractionCaptureDefaults(
        tapSlopPx: double.parse('8'),
        longPressMs: int.parse('500'),
        scrollMinPx: double.parse('8'),
        settleQuietWindowMs: int.parse('300'),
        settleTimeoutMs: int.parse('5000'),
      );
      final b = CockpitInteractionCaptureDefaults(
        tapSlopPx: double.parse('8'),
        longPressMs: int.parse('500'),
        scrollMinPx: double.parse('8'),
        settleQuietWindowMs: int.parse('300'),
        settleTimeoutMs: int.parse('5000'),
      );
      expect(identical(a, b), isFalse);
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);

      for (final variant in <CockpitInteractionCaptureDefaults>[
        CockpitInteractionCaptureDefaults(tapSlopPx: double.parse('9')),
        CockpitInteractionCaptureDefaults(longPressMs: int.parse('501')),
        CockpitInteractionCaptureDefaults(scrollMinPx: double.parse('9')),
        CockpitInteractionCaptureDefaults(
          settleQuietWindowMs: int.parse('301'),
        ),
        CockpitInteractionCaptureDefaults(settleTimeoutMs: int.parse('5001')),
      ]) {
        expect(a == variant, isFalse);
      }
      expect(a == Object(), isFalse);
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
