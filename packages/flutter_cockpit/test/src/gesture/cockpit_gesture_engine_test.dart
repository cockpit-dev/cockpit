import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tap clamps edge-aligned targets back into the viewport', (
    tester,
  ) async {
    var tapCount = 0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Material(
          child: SizedBox(
            width: 320,
            height: 240,
            child: Stack(
              children: <Widget>[
                Positioned(
                  left: 24,
                  bottom: -1,
                  child: GestureDetector(
                    key: const ValueKey<String>('edge-tap-target'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => tapCount += 1,
                    child: const SizedBox(width: 132, height: 48),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final target = _targetFor(tester, 'edge-tap-target');
    final engine = CockpitGestureEngine(delay: tester.pump);

    await engine.perform(CockpitGestureAction.tap(target: target));
    await tester.pumpAndSettle();

    expect(tapCount, 1);
  });

  testWidgets('longPress dispatches a real long-press gesture', (tester) async {
    var longPressCount = 0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: GestureDetector(
            key: const ValueKey<String>('long-press-target'),
            behavior: HitTestBehavior.opaque,
            onLongPress: () => longPressCount += 1,
            child: const SizedBox(width: 140, height: 140),
          ),
        ),
      ),
    );
    await tester.pump();

    final target = _targetFor(tester, 'long-press-target');
    final engine = CockpitGestureEngine(delay: tester.pump);

    await engine.perform(
      CockpitGestureAction.longPress(
        target: target,
        duration: const Duration(milliseconds: 650),
      ),
    );
    await tester.pumpAndSettle();

    expect(longPressCount, 1);
  });

  testWidgets('doubleTap dispatches a real double-tap gesture', (tester) async {
    var doubleTapCount = 0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: GestureDetector(
            key: const ValueKey<String>('double-tap-target'),
            behavior: HitTestBehavior.opaque,
            onDoubleTap: () => doubleTapCount += 1,
            child: const SizedBox(width: 140, height: 140),
          ),
        ),
      ),
    );
    await tester.pump();

    final target = _targetFor(tester, 'double-tap-target');
    final engine = CockpitGestureEngine(delay: tester.pump);

    await engine.perform(CockpitGestureAction.doubleTap(target: target));
    await tester.pumpAndSettle();

    expect(doubleTapCount, 1);
  });

  testWidgets('hover dispatches a real mouse transition', (tester) async {
    var entered = 0;
    var hovered = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MouseRegion(
          key: const ValueKey<String>('hover-target'),
          onEnter: (_) => entered += 1,
          onHover: (_) => hovered += 1,
          child: const SizedBox(width: 140, height: 80),
        ),
      ),
    );
    await tester.pump();

    final target = _targetFor(tester, 'hover-target');
    final engine = CockpitGestureEngine(delay: tester.pump);
    await engine.perform(CockpitGestureAction.hover(target: target));
    await tester.pump();

    expect(entered, 1);
    expect(hovered, greaterThanOrEqualTo(1));
  });

  testWidgets('wheel dispatches real pointer scroll signals', (tester) async {
    final deltas = <Offset>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Listener(
          key: const ValueKey<String>('wheel-target'),
          behavior: HitTestBehavior.opaque,
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              deltas.add(event.scrollDelta);
            }
          },
          child: const SizedBox(width: 180, height: 120),
        ),
      ),
    );
    await tester.pump();

    final target = _targetFor(tester, 'wheel-target');
    final engine = CockpitGestureEngine(delay: tester.pump);
    await engine.perform(
      CockpitGestureAction.wheel(
        target: target,
        delta: const Offset(0, 40),
        steps: 3,
      ),
    );
    await tester.pump();

    expect(deltas, <Offset>[
      const Offset(0, 40),
      const Offset(0, 40),
      const Offset(0, 40),
    ]);
  });

  testWidgets('tap can target the top-right anchor of a larger shell', (
    tester,
  ) async {
    var tapCount = 0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Material(
          child: Center(
            child: SizedBox(
              key: const ValueKey<String>('card-shell'),
              width: 220,
              height: 140,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  const ColoredBox(color: Color(0xFF101414)),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => tapCount += 1,
                      child: const SizedBox(width: 44, height: 44),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final shell = _targetFor(tester, 'card-shell');
    final engine = CockpitGestureEngine(delay: tester.pump);

    await engine.perform(
      CockpitGestureAction.tap(
        target: shell,
        anchor: CockpitGestureAnchor.topRight,
      ),
    );
    await tester.pumpAndSettle();

    expect(tapCount, 1);
  });

  testWidgets('drag dispatches a real pan gesture', (tester) async {
    var totalDx = 0.0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: GestureDetector(
            key: const ValueKey<String>('drag-target'),
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (details) {
              totalDx += details.delta.dx;
            },
            child: const SizedBox(width: 140, height: 140),
          ),
        ),
      ),
    );
    await tester.pump();

    final target = _targetFor(tester, 'drag-target');
    final engine = CockpitGestureEngine(delay: tester.pump);

    await engine.perform(
      CockpitGestureAction.drag(
        target: target,
        delta: const Offset(96, 0),
        duration: const Duration(milliseconds: 220),
      ),
    );
    await tester.pumpAndSettle();

    expect(totalDx, greaterThan(40));
  });

  testWidgets('gesture profiles adjust drag sampling density', (tester) async {
    final fastDurations = <Duration>[];
    final preciseDurations = <Duration>[];

    Future<void> pumpAndRecord(
      List<Duration> durations, [
      Duration? duration,
    ]) async {
      final resolved = duration ?? Duration.zero;
      durations.add(resolved);
      await tester.pump(resolved);
    }

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            key: ValueKey<String>('profile-target'),
            width: 160,
            height: 160,
          ),
        ),
      ),
    );
    await tester.pump();

    final target = _targetFor(tester, 'profile-target');
    final fastEngine = CockpitGestureEngine(
      delay: ([duration]) => pumpAndRecord(fastDurations, duration),
    );
    final preciseEngine = CockpitGestureEngine(
      delay: ([duration]) => pumpAndRecord(preciseDurations, duration),
    );

    await fastEngine.perform(
      CockpitGestureAction.drag(
        target: target,
        delta: const Offset(140, 0),
        duration: const Duration(milliseconds: 240),
        profile: CockpitGestureProfile.fast,
      ),
    );
    await preciseEngine.perform(
      CockpitGestureAction.drag(
        target: target,
        delta: const Offset(140, 0),
        duration: const Duration(milliseconds: 240),
        profile: CockpitGestureProfile.precise,
      ),
    );

    final fastMoveTicks = fastDurations
        .where((it) => it > Duration.zero)
        .length;
    final preciseMoveTicks = preciseDurations
        .where((it) => it > Duration.zero)
        .length;

    expect(preciseMoveTicks, greaterThan(fastMoveTicks));
  });

  testWidgets('gesture sampling can be overridden with frameIntervalMs', (
    tester,
  ) async {
    final sampledDurations = <Duration>[];

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            key: ValueKey<String>('frame-interval-target'),
            width: 160,
            height: 160,
          ),
        ),
      ),
    );
    await tester.pump();

    final target = _targetFor(tester, 'frame-interval-target');
    final engine = CockpitGestureEngine(
      delay: ([duration]) async {
        final resolved = duration ?? Duration.zero;
        sampledDurations.add(resolved);
        await tester.pump(resolved);
      },
    );

    await engine.perform(
      CockpitGestureAction.drag(
        target: target,
        delta: const Offset(120, 0),
        duration: const Duration(milliseconds: 200),
        frameInterval: const Duration(milliseconds: 25),
      ),
    );

    final moveTicks = sampledDurations.where((it) => it > Duration.zero).length;
    expect(moveTicks, inInclusiveRange(7, 9));
  });

  testWidgets('drag can honor a long-press hold before movement', (
    tester,
  ) async {
    var longPressMoveCount = 0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: GestureDetector(
            key: const ValueKey<String>('held-drag-target'),
            behavior: HitTestBehavior.opaque,
            onLongPressMoveUpdate: (_) {
              longPressMoveCount += 1;
            },
            child: const SizedBox(width: 160, height: 160),
          ),
        ),
      ),
    );
    await tester.pump();

    final target = _targetFor(tester, 'held-drag-target');
    final engine = CockpitGestureEngine(delay: tester.pump);

    await engine.perform(
      CockpitGestureAction.drag(
        target: target,
        delta: const Offset(120, 0),
        holdDuration: kLongPressTimeout + const Duration(milliseconds: 40),
        duration: const Duration(milliseconds: 220),
      ),
    );
    await tester.pumpAndSettle();

    expect(longPressMoveCount, greaterThan(0));
  });

  testWidgets('swipe can dismiss a production-style card', (tester) async {
    var dismissed = false;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Material(
          child: StatefulBuilder(
            builder: (context, setState) {
              return dismissed
                  ? const SizedBox.shrink()
                  : Dismissible(
                      key: const ValueKey<String>('swipe-target'),
                      onDismissed: (_) {
                        setState(() {
                          dismissed = true;
                        });
                      },
                      child: const SizedBox(width: 220, height: 120),
                    );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    final target = _targetFor(tester, 'swipe-target');
    final engine = CockpitGestureEngine(delay: tester.pump);

    await engine.perform(
      CockpitGestureAction.swipe(
        target: target,
        direction: AxisDirection.right,
      ),
    );
    await tester.pumpAndSettle();

    expect(dismissed, isTrue);
  });

  testWidgets('fling dispatches a momentum-style drag gesture', (tester) async {
    var dragEndCount = 0;
    Velocity? latestVelocity;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: GestureDetector(
            key: const ValueKey<String>('fling-target'),
            behavior: HitTestBehavior.opaque,
            onPanEnd: (details) {
              dragEndCount += 1;
              latestVelocity = details.velocity;
            },
            child: const SizedBox(width: 180, height: 180),
          ),
        ),
      ),
    );
    await tester.pump();

    final target = _targetFor(tester, 'fling-target');
    final engine = CockpitGestureEngine(delay: tester.pump);

    await engine.perform(
      CockpitGestureAction.fling(
        target: target,
        delta: const Offset(0, -220),
        duration: const Duration(milliseconds: 88),
      ),
    );
    await tester.pumpAndSettle();

    expect(dragEndCount, 1);
    expect(latestVelocity, isNotNull);
  });

  testWidgets('pinchZoom dispatches a scale gesture', (tester) async {
    var latestScale = 1.0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: GestureDetector(
            key: const ValueKey<String>('pinch-target'),
            behavior: HitTestBehavior.opaque,
            onScaleUpdate: (details) {
              latestScale = details.scale;
            },
            child: const SizedBox(width: 220, height: 220),
          ),
        ),
      ),
    );
    await tester.pump();

    final target = _targetFor(tester, 'pinch-target');
    final engine = CockpitGestureEngine(delay: tester.pump);

    await engine.perform(
      CockpitGestureAction.pinchZoom(target: target, scale: 1.8, startSpan: 56),
    );
    await tester.pumpAndSettle();

    expect(latestScale, greaterThan(1.2));
  });

  testWidgets('pinchZoom supports an explicit viewport coordinate', (
    tester,
  ) async {
    var latestScale = 1.0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: GestureDetector(
            key: const ValueKey<String>('coordinate-pinch-target'),
            behavior: HitTestBehavior.opaque,
            onScaleUpdate: (details) {
              latestScale = details.scale;
            },
            child: const SizedBox(width: 220, height: 220),
          ),
        ),
      ),
    );
    await tester.pump();

    final target = _targetFor(tester, 'coordinate-pinch-target');
    final geometry = CockpitTargetGeometryResolver.maybeFromTarget(target)!;
    final engine = CockpitGestureEngine(
      delay: tester.pump,
      viewportGeometryProvider: () => geometry,
    );

    await engine.perform(
      CockpitGestureAction.pinchZoom(
        origin: Offset(geometry.centerX, geometry.centerY),
        scale: 1.8,
        startSpan: 56,
      ),
    );
    await tester.pumpAndSettle();

    expect(latestScale, greaterThan(1.2));
  });

  testWidgets('rotate dispatches a rotation-aware scale gesture', (
    tester,
  ) async {
    var latestRotation = 0.0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: GestureDetector(
            key: const ValueKey<String>('rotate-target'),
            behavior: HitTestBehavior.opaque,
            onScaleUpdate: (details) {
              latestRotation = details.rotation;
            },
            child: const SizedBox(width: 220, height: 220),
          ),
        ),
      ),
    );
    await tester.pump();

    final target = _targetFor(tester, 'rotate-target');
    final engine = CockpitGestureEngine(delay: tester.pump);

    await engine.perform(
      CockpitGestureAction.rotate(
        target: target,
        rotation: 0.42,
        startSpan: 72,
      ),
    );
    await tester.pumpAndSettle();

    expect(latestRotation.abs(), greaterThan(0.12));
  });

  testWidgets('rotate wins against an enclosing scroll gesture', (
    tester,
  ) async {
    var latestRotation = 0.0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              GestureDetector(
                key: const ValueKey<String>('scrollable-rotate-target'),
                behavior: HitTestBehavior.opaque,
                onScaleUpdate: (details) {
                  latestRotation = details.rotation;
                },
                child: const SizedBox(width: 220, height: 220),
              ),
              const SizedBox(height: 800),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final target = _targetFor(tester, 'scrollable-rotate-target');
    final engine = CockpitGestureEngine(delay: tester.pump);

    await engine.perform(
      CockpitGestureAction.rotate(target: target, rotation: 0.8, startSpan: 56),
    );
    await tester.pumpAndSettle();

    expect(latestRotation.abs(), greaterThan(0.5));
  });

  testWidgets('panZoom dispatches trackpad pan-zoom events', (tester) async {
    var updateCount = 0;
    double latestScale = 1.0;
    double latestRotation = 0.0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerPanZoomUpdate: (event) {
              updateCount += 1;
              latestScale = event.scale;
              latestRotation = event.rotation;
            },
            child: const SizedBox(
              key: ValueKey<String>('panzoom-target'),
              width: 220,
              height: 220,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final target = _targetFor(tester, 'panzoom-target');
    final engine = CockpitGestureEngine(delay: tester.pump);

    await engine.perform(
      CockpitGestureAction.panZoom(
        target: target,
        delta: const Offset(18, -26),
        scale: 1.18,
        rotation: 0.24,
      ),
    );
    await tester.pumpAndSettle();

    expect(updateCount, greaterThan(0));
    expect(latestScale, greaterThan(1.0));
    expect(latestRotation, greaterThan(0.0));
  });

  testWidgets('multiTouch dispatches explicit pointer tracks', (tester) async {
    var latestScale = 1.0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: GestureDetector(
            key: const ValueKey<String>('multitouch-target'),
            behavior: HitTestBehavior.opaque,
            onScaleUpdate: (details) {
              latestScale = details.scale;
            },
            child: const SizedBox(width: 220, height: 220),
          ),
        ),
      ),
    );
    await tester.pump();

    final target = _targetFor(tester, 'multitouch-target');
    final engine = CockpitGestureEngine(delay: tester.pump);

    await engine.perform(
      CockpitGestureAction.multiTouch(
        target: target,
        sequence: const CockpitMultiTouchSequence(
          steps: <CockpitMultiTouchStep>[
            CockpitMultiTouchStep(
              pointer: 0,
              phase: CockpitMultiTouchPhase.down,
              atMs: 0,
              dx: -24,
              dy: 0,
            ),
            CockpitMultiTouchStep(
              pointer: 1,
              phase: CockpitMultiTouchPhase.down,
              atMs: 0,
              dx: 24,
              dy: 0,
            ),
            CockpitMultiTouchStep(
              pointer: 0,
              phase: CockpitMultiTouchPhase.move,
              atMs: 120,
              dx: -72,
              dy: 0,
            ),
            CockpitMultiTouchStep(
              pointer: 1,
              phase: CockpitMultiTouchPhase.move,
              atMs: 120,
              dx: 72,
              dy: 0,
            ),
            CockpitMultiTouchStep(
              pointer: 0,
              phase: CockpitMultiTouchPhase.up,
              atMs: 220,
              dx: -72,
              dy: 0,
            ),
            CockpitMultiTouchStep(
              pointer: 1,
              phase: CockpitMultiTouchPhase.up,
              atMs: 220,
              dx: 72,
              dy: 0,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(latestScale, greaterThan(1.4));
  });

  testWidgets('multiTouch rejects invalid sequences before dispatching', (
    tester,
  ) async {
    var tapCount = 0;
    final observedEvents = <PointerEvent>[];
    void recordEvent(PointerEvent event) => observedEvents.add(event);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: GestureDetector(
            key: const ValueKey<String>('multitouch-invalid-target'),
            behavior: HitTestBehavior.opaque,
            onTap: () => tapCount += 1,
            child: const SizedBox(width: 220, height: 220),
          ),
        ),
      ),
    );
    await tester.pump();

    GestureBinding.instance.pointerRouter.addGlobalRoute(recordEvent);
    addTearDown(
      () =>
          GestureBinding.instance.pointerRouter.removeGlobalRoute(recordEvent),
    );

    final target = _targetFor(tester, 'multitouch-invalid-target');
    final engine = CockpitGestureEngine(delay: tester.pump);

    await expectLater(
      engine.perform(
        CockpitGestureAction.multiTouch(
          target: target,
          sequence: const CockpitMultiTouchSequence(
            steps: <CockpitMultiTouchStep>[
              CockpitMultiTouchStep(
                pointer: 1,
                phase: CockpitMultiTouchPhase.down,
                atMs: 0,
                dx: 0,
                dy: 0,
              ),
              CockpitMultiTouchStep(
                pointer: 2,
                phase: CockpitMultiTouchPhase.move,
                atMs: 60,
                dx: 12,
                dy: 0,
              ),
              CockpitMultiTouchStep(
                pointer: 1,
                phase: CockpitMultiTouchPhase.up,
                atMs: 120,
                dx: 0,
                dy: 0,
              ),
            ],
          ),
        ),
      ),
      throwsArgumentError,
    );

    expect(
      observedEvents,
      isEmpty,
      reason: 'Validation must reject the sequence before any dispatch.',
    );

    await engine.perform(CockpitGestureAction.tap(target: target));
    await tester.pumpAndSettle();

    expect(tapCount, 1);
  });

  testWidgets('multiTouch preserves authored order for tied pointer events', (
    tester,
  ) async {
    final phases = <String>[];
    void recordEvent(PointerEvent event) {
      if (event.pointer != 0) return;
      if (event is PointerDownEvent) phases.add('down');
      if (event is PointerUpEvent) phases.add('up');
    }

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            key: const ValueKey<String>('multitouch-order-target'),
            width: 220,
            height: 220,
          ),
        ),
      ),
    );
    await tester.pump();

    GestureBinding.instance.pointerRouter.addGlobalRoute(recordEvent);
    addTearDown(
      () =>
          GestureBinding.instance.pointerRouter.removeGlobalRoute(recordEvent),
    );

    final target = _targetFor(tester, 'multitouch-order-target');
    final engine = CockpitGestureEngine(delay: tester.pump);
    await engine.perform(
      CockpitGestureAction.multiTouch(
        target: target,
        sequence: const CockpitMultiTouchSequence(
          steps: <CockpitMultiTouchStep>[
            CockpitMultiTouchStep(
              pointer: 0,
              phase: CockpitMultiTouchPhase.down,
              atMs: 0,
              dx: 0,
              dy: 0,
            ),
            CockpitMultiTouchStep(
              pointer: 0,
              phase: CockpitMultiTouchPhase.up,
              atMs: 0,
              dx: 0,
              dy: 0,
            ),
          ],
        ),
      ),
    );

    expect(phases, <String>['down', 'up']);
  });

  testWidgets(
    'multiTouch cancels active pointers when dispatch fails mid-sequence',
    (tester) async {
      var tapCount = 0;
      final cancelledPointers = <int>[];
      void recordEvent(PointerEvent event) {
        if (event is PointerCancelEvent) {
          cancelledPointers.add(event.pointer);
        }
      }

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: GestureDetector(
              key: const ValueKey<String>('multitouch-cancel-target'),
              behavior: HitTestBehavior.opaque,
              onTap: () => tapCount += 1,
              child: const SizedBox(width: 220, height: 220),
            ),
          ),
        ),
      );
      await tester.pump();

      GestureBinding.instance.pointerRouter.addGlobalRoute(recordEvent);
      addTearDown(
        () => GestureBinding.instance.pointerRouter.removeGlobalRoute(
          recordEvent,
        ),
      );

      final target = _targetFor(tester, 'multitouch-cancel-target');
      var delayCalls = 0;
      final failingEngine = CockpitGestureEngine(
        delay: ([duration]) {
          delayCalls += 1;
          if (delayCalls > 2) {
            throw StateError('Injected mid-sequence dispatch failure.');
          }
          return tester.pump(duration);
        },
      );

      Object? thrown;
      try {
        await failingEngine.perform(
          CockpitGestureAction.multiTouch(
            target: target,
            sequence: const CockpitMultiTouchSequence(
              steps: <CockpitMultiTouchStep>[
                CockpitMultiTouchStep(
                  pointer: 1,
                  phase: CockpitMultiTouchPhase.down,
                  atMs: 0,
                  dx: -24,
                  dy: 0,
                ),
                CockpitMultiTouchStep(
                  pointer: 2,
                  phase: CockpitMultiTouchPhase.down,
                  atMs: 0,
                  dx: 24,
                  dy: 0,
                ),
                CockpitMultiTouchStep(
                  pointer: 1,
                  phase: CockpitMultiTouchPhase.move,
                  atMs: 80,
                  dx: -48,
                  dy: 0,
                ),
                CockpitMultiTouchStep(
                  pointer: 1,
                  phase: CockpitMultiTouchPhase.up,
                  atMs: 160,
                  dx: -48,
                  dy: 0,
                ),
                CockpitMultiTouchStep(
                  pointer: 2,
                  phase: CockpitMultiTouchPhase.up,
                  atMs: 160,
                  dx: 24,
                  dy: 0,
                ),
              ],
            ),
          ),
        );
      } on StateError catch (error) {
        thrown = error;
      }
      expect(thrown, isA<StateError>());

      expect(
        cancelledPointers,
        unorderedEquals(<int>[1, 2]),
        reason:
            'Every pointer that was down when the sequence failed must '
            'receive a PointerCancel.',
      );

      final engine = CockpitGestureEngine(delay: tester.pump);
      await engine.perform(CockpitGestureAction.tap(target: target));
      await tester.pumpAndSettle();

      expect(tapCount, 1);
    },
  );
}

CockpitTarget _targetFor(WidgetTester tester, String keyValue) {
  final finder = find.byKey(ValueKey<String>(keyValue));
  final element = tester.element(finder);

  return CockpitTarget(
    registrationId: keyValue,
    keyValue: keyValue,
    routeName: '/',
    diagnosticNodeProvider: () => element,
  );
}
