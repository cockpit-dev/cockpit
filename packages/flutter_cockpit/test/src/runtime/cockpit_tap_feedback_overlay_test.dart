import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tap feedback sidecar is absent by default', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 280,
          height: 360,
          child: FlutterCockpitApp(child: ColoredBox(color: Color(0xFF101414))),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('cockpit_tap_feedback_overlay')),
      findsNothing,
    );
  });

  testWidgets(
    'tap feedback sidecar can be enabled through diagnostics config',
    (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 280,
            height: 360,
            child: FlutterCockpitApp(
              config: FlutterCockpitConfig(
                diagnostics: CockpitDiagnosticsConfig(enableTapFeedback: true),
              ),
              child: ColoredBox(color: Color(0xFF101414)),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey<String>('cockpit_tap_feedback_overlay')),
        findsOneWidget,
      );
    },
  );

  testWidgets('tap feedback sidecar does not block interaction', (
    tester,
  ) async {
    var tapCount = 0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 280,
          height: 360,
          child: FlutterCockpitApp(
            config: const FlutterCockpitConfig(
              diagnostics: CockpitDiagnosticsConfig(enableTapFeedback: true),
            ),
            child: Center(
              child: GestureDetector(
                onTap: () => tapCount += 1,
                child: const SizedBox(
                  width: 120,
                  height: 48,
                  child: ColoredBox(color: Color(0xFF3A5AE0)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(GestureDetector));
    await tester.pump();

    expect(tapCount, 1);
  });

  testWidgets('tap feedback markers render only after actions are emitted', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 280,
          height: 360,
          child: FlutterCockpitApp(
            config: FlutterCockpitConfig(
              diagnostics: CockpitDiagnosticsConfig(enableTapFeedback: true),
            ),
            child: ColoredBox(color: Color(0xFF101414)),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('cockpit_tap_feedback_marker')),
      findsNothing,
    );

    final rootState = tester.state<FlutterCockpitRootState>(
      find.byType(FlutterCockpitRoot),
    );

    await rootState.performGesture(
      const CockpitGestureAction.tap(origin: Offset(140, 180)),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('cockpit_tap_feedback_marker')),
      findsOneWidget,
    );
  });

  testWidgets('route changes clear tap feedback markers before their TTL', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 280,
          height: 360,
          child: FlutterCockpitApp(
            config: const FlutterCockpitConfig(
              diagnostics: CockpitDiagnosticsConfig(enableTapFeedback: true),
            ),
            child: const ColoredBox(color: Color(0xFF101414)),
          ),
        ),
      ),
    );
    await tester.pump();

    final rootState = tester.state<FlutterCockpitRootState>(
      find.byType(FlutterCockpitRoot),
    );

    await rootState.performGesture(
      const CockpitGestureAction.tap(origin: Offset(140, 180)),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('cockpit_tap_feedback_marker')),
      findsOneWidget,
    );

    // Route changes notify currentRouteName listeners; the surface binds
    // controller.clear to that signal so a stale crosshair cannot outlive
    // the widget it pointed at.
    FlutterCockpit.binding.currentRouteName.value = '/after-navigation';
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('cockpit_tap_feedback_marker')),
      findsNothing,
    );
  });
}
