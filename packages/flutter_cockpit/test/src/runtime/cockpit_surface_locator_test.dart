import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('action probes ignore passive targets with the same text', (
    tester,
  ) async {
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFFFFFFFF),
        builder: (context, child) => CockpitSurface(
          routeName: '/actions',
          child: Material(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                children: <Widget>[
                  const Text('Continue'),
                  TextButton(
                    key: const ValueKey<String>('continue-button'),
                    onPressed: () {},
                    child: const Text('Continue'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final surface = tester.state<CockpitSurfaceState>(
      find.byType(CockpitSurface),
    );
    final result = surface.probeVisibleLocator(
      const CockpitLocator(text: 'Continue'),
      requiredCommand: CockpitCommandType.tap,
    );

    expect(result.isSuccess, isTrue, reason: '${result.error?.details}');
    expect(result.target?.keyValue, 'continue-button');
  });

  testWidgets('indexed probes use visual order instead of element order', (
    tester,
  ) async {
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFFFFFFFF),
        builder: (context, child) => CockpitSurface(
          routeName: '/stack',
          child: Material(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Stack(
                children: <Widget>[
                  Positioned(
                    left: 20,
                    top: 140,
                    child: TextButton(
                      key: const ValueKey<String>('lower-button'),
                      onPressed: () {},
                      child: const Text('Continue'),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    top: 20,
                    child: TextButton(
                      key: const ValueKey<String>('upper-button'),
                      onPressed: () {},
                      child: const Text('Continue'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final surface = tester.state<CockpitSurfaceState>(
      find.byType(CockpitSurface),
    );
    final first = surface.probeVisibleLocator(
      const CockpitLocator(text: 'Continue', index: 0),
      requiredCommand: CockpitCommandType.tap,
    );
    final second = surface.probeVisibleLocator(
      const CockpitLocator(text: 'Continue', index: 1),
      requiredCommand: CockpitCommandType.tap,
    );

    expect(first.isSuccess, isTrue, reason: '${first.error?.details}');
    expect(second.isSuccess, isTrue, reason: '${second.error?.details}');
    expect(first.target?.keyValue, 'upper-button');
    expect(second.target?.keyValue, 'lower-button');
  });

  testWidgets('fuzzy probes prefer the tightest matching element', (
    tester,
  ) async {
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFFFFFFFF),
        builder: (context, child) => CockpitSurface(
          routeName: '/fuzzy',
          child: const Material(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                children: <Widget>[
                  Text('Save task'),
                  Text('Save task permanently'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final surface = tester.state<CockpitSurfaceState>(
      find.byType(CockpitSurface),
    );
    final result = surface.probeVisibleLocator(
      const CockpitLocator(
        text: 'Svae task',
        matchMode: CockpitTextMatchMode.fuzzy,
      ),
    );

    expect(result.isSuccess, isTrue, reason: '${result.error?.details}');
    expect(result.target?.text, 'Save task');
  });

  testWidgets('semantic label probes do not depend on a Tooltip widget', (
    tester,
  ) async {
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFFFFFFFF),
        builder: (context, child) => CockpitSurface(
          routeName: '/dashboard',
          child: Material(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Semantics(
                label: 'Open Dashboard navigation',
                button: true,
                child: InkWell(
                  key: const ValueKey<String>('dashboard-navigation'),
                  onTap: () {},
                  child: const Text('Dashboard'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final surface = tester.state<CockpitSurfaceState>(
      find.byType(CockpitSurface),
    );
    final result = surface.probeVisibleLocator(
      const CockpitLocator(
        semanticId: 'Dashboard navigation',
        matchMode: CockpitTextMatchMode.contains,
      ),
      requiredCommand: CockpitCommandType.tap,
    );

    expect(result.isSuccess, isTrue, reason: '${result.error?.details}');
    expect(result.target?.keyValue, 'dashboard-navigation');
    expect(result.target?.tooltip, isNull);
  });
}
