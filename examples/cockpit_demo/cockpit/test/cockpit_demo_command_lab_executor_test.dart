import 'package:cockpit_demo/src/ui/screens/command_lab_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'Cockpit executor resolves gesture targets and semantic slider wrappers',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CockpitSurface(
            routeName: '/command-lab',
            child: const CommandLabScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final surface = tester.state<CockpitSurfaceState>(
        find.byType(CockpitSurface),
      );
      final executor = InAppCockpitCommandExecutor(
        registry: surface.registry,
        locatorProbe: surface.probeVisibleLocator,
        snapshotProvider: surface.snapshot,
        ensureVisibleHandler:
            ({
              required locator,
              required duration,
              required alignment,
              required padding,
              required offset,
            }) {
              return surface.ensureLocatorVisible(
                locator,
                duration: duration,
                alignment: alignment,
                padding: padding,
                offset: offset,
              );
            },
        postActionSettler: tester.pump,
        gestureHandler: surface.performGesture,
      );

      final initialGestureTap = await executor.execute(
        CockpitCommand(
          commandId: 'initial-gesture-tap-pad',
          commandType: CockpitCommandType.tap,
          locator: const CockpitLocator(key: 'lab-gesture-detector'),
          parameters: const <String, Object?>{'activation': 'gesture'},
        ),
      );
      await tester.pumpAndSettle();
      expect(
        initialGestureTap.success,
        isTrue,
        reason: '${initialGestureTap.error?.details}',
      );
      expect(find.text('gesture:tap'), findsOneWidget);

      final revealSlider = await executor.execute(
        CockpitCommand(
          commandId: 'reveal-slider-wrapper',
          commandType: CockpitCommandType.showOnScreen,
          locator: const CockpitLocator(key: 'lab-slider-semantics'),
          parameters: const <String, Object?>{'revealAlignment': 'center'},
        ),
      );
      expect(
        revealSlider.success,
        isTrue,
        reason: '${revealSlider.error?.details}',
      );
      await tester.pumpAndSettle();

      final increase = await executor.execute(
        CockpitCommand(
          commandId: 'increase-slider-wrapper',
          commandType: CockpitCommandType.increase,
          locator: const CockpitLocator(key: 'lab-slider-semantics'),
        ),
      );
      await tester.pumpAndSettle();
      expect(increase.success, isTrue, reason: '${increase.error?.details}');
      expect(find.text('slider:60'), findsOneWidget);

      final decrease = await executor.execute(
        CockpitCommand(
          commandId: 'decrease-slider-wrapper',
          commandType: CockpitCommandType.decrease,
          locator: const CockpitLocator(key: 'lab-slider-semantics'),
        ),
      );
      await tester.pumpAndSettle();
      expect(decrease.success, isTrue, reason: '${decrease.error?.details}');
      expect(find.text('slider:50'), findsOneWidget);

      final hover = await executor.execute(
        CockpitCommand(
          commandId: 'hover-command-lab-pad',
          commandType: CockpitCommandType.hover,
          locator: const CockpitLocator(key: 'lab-hover-region'),
        ),
      );
      await tester.pumpAndSettle();
      expect(hover.success, isTrue, reason: '${hover.error?.details}');
      expect(find.text('hover:entered'), findsOneWidget);

      final wheel = await executor.execute(
        CockpitCommand(
          commandId: 'wheel-command-lab-pad',
          commandType: CockpitCommandType.wheel,
          locator: const CockpitLocator(key: 'lab-wheel-listener'),
          parameters: const <String, Object?>{'dy': 120.0},
        ),
      );
      await tester.pumpAndSettle();
      expect(wheel.success, isTrue, reason: '${wheel.error?.details}');
      expect(find.text('wheel:down-1'), findsOneWidget);

      final gestureTap = await executor.execute(
        CockpitCommand(
          commandId: 'gesture-tap-pad',
          commandType: CockpitCommandType.tap,
          locator: const CockpitLocator(key: 'lab-gesture-detector'),
          parameters: const <String, Object?>{'activation': 'gesture'},
        ),
      );
      await tester.pumpAndSettle();
      expect(
        gestureTap.success,
        isTrue,
        reason: '${gestureTap.error?.details}',
      );
      expect(find.text('gesture:tap'), findsOneWidget);

      expect(
        await surface.ensureLocatorVisible(
          const CockpitLocator(key: 'lab-key-pad-activator'),
          alignment: CockpitRevealAlignment.center,
        ),
        isTrue,
      );
      await tester.pumpAndSettle();
      final focusTap = await executor.execute(
        CockpitCommand(
          commandId: 'gesture-focus-key-pad',
          commandType: CockpitCommandType.tap,
          locator: const CockpitLocator(key: 'lab-key-pad-activator'),
          parameters: const <String, Object?>{'activation': 'gesture'},
        ),
      );
      await tester.pumpAndSettle();
      expect(focusTap.success, isTrue, reason: '${focusTap.error?.details}');
      expect(find.text('keyFocus:yes'), findsOneWidget);
    },
  );
}
