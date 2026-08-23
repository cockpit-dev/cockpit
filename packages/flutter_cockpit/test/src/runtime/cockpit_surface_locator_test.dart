import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('resolves the dismiss intent for an open MenuAnchor', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CockpitSurface(
          routeName: '/menu',
          child: Scaffold(
            body: MenuAnchor(
              menuChildren: const <Widget>[
                MenuItemButton(child: Text('English')),
              ],
              builder: (context, controller, child) => TextButton(
                onPressed: controller.open,
                child: const Text('Language'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    expect(find.text('English'), findsOneWidget);

    final surface = tester.state<CockpitSurfaceState>(
      find.byType(CockpitSurface),
    );
    final dismiss = surface.resolveDismissAction();
    expect(dismiss, isNotNull);
    dismiss!();
    await tester.pumpAndSettle();

    expect(find.text('English'), findsNothing);
  });

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

  testWidgets('unique keyed action probes skip full target discovery', (
    tester,
  ) async {
    final registry = CockpitTargetRegistry(routeName: '/actions');
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFFFFFFFF),
        builder: (context, child) => CockpitSurface(
          routeName: '/actions',
          registry: registry,
          child: Material(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: TextButton(
                key: const ValueKey<String>('continue-button'),
                onPressed: () {},
                child: const Text('Continue'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final discoveredTargetsProvider = registry.discoveredTargetsProvider!;
    var fullDiscoveryCount = 0;
    registry.discoveredTargetsProvider = () {
      fullDiscoveryCount += 1;
      return discoveredTargetsProvider();
    };
    final surface = tester.state<CockpitSurfaceState>(
      find.byType(CockpitSurface),
    );
    final result = surface.probeVisibleLocator(
      const CockpitLocator(key: 'continue-button'),
      requiredCommand: CockpitCommandType.tap,
    );

    expect(result.isSuccess, isTrue, reason: '${result.error?.details}');
    expect(result.target?.keyValue, 'continue-button');
    expect(result.target?.supportedCommands, contains(CockpitCommandType.tap));
    expect(fullDiscoveryCount, 0);
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

  testWidgets(
    'source-derived structure can gesture a custom control without keys or semantics',
    (tester) async {
      var activated = false;
      await tester.pumpWidget(
        WidgetsApp(
          color: const Color(0xFFFFFFFF),
          builder: (context, child) => CockpitSurface(
            routeName: '/source-control',
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: ExcludeSemantics(
                child: SourceOnlyButton(
                  onPressed: () => activated = true,
                  child: const Text('Run source action'),
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
      final passive = surface.probeVisibleLocator(
        const CockpitLocator(text: 'Run source action'),
        requiredCommand: CockpitCommandType.tap,
      );
      expect(passive.isSuccess, isTrue, reason: '${passive.error?.details}');
      expect(
        passive.target?.supportedCommands,
        isNot(contains(CockpitCommandType.tap)),
      );

      final locator = CockpitSelector.parse(
        'SourceOnlyButton >> Text["Run source action"]',
      );
      final sourceTarget = surface.probeVisibleLocator(
        locator,
        requiredCommand: CockpitCommandType.tap,
      );
      expect(
        sourceTarget.isSuccess,
        isTrue,
        reason: '${sourceTarget.error?.details}',
      );
      expect(
        sourceTarget.target?.supportedCommands,
        contains(CockpitCommandType.tap),
      );

      final executor = InAppCockpitCommandExecutor(
        registry: surface.registry,
        locatorProbe: surface.probeVisibleLocator,
        gestureHandler: surface.performGesture,
      );
      final result = await executor.execute(
        CockpitCommand(
          commandId: 'source-gesture-tap',
          commandType: CockpitCommandType.tap,
          locator: locator,
        ),
      );
      await tester.pump();

      expect(result.success, isTrue, reason: '${result.error?.details}');
      expect(activated, isTrue);
    },
  );

  testWidgets('source-derived structure retains GestureDetector ancestors', (
    tester,
  ) async {
    var activated = false;
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFFFFFFFF),
        builder: (context, child) => CockpitSurface(
          routeName: '/gesture-source',
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: ExcludeSemantics(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: () => activated = true,
                child: const SizedBox(
                  width: 220,
                  height: 48,
                  child: Center(child: Text('Run source gesture')),
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
    final locator = CockpitSelector.parse(
      'GestureDetector >> Text["Run source gesture"]',
    );
    final sourceTarget = surface.probeVisibleLocator(
      locator,
      requiredCommand: CockpitCommandType.doubleTap,
    );
    expect(
      sourceTarget.isSuccess,
      isTrue,
      reason: '${sourceTarget.error?.details}',
    );

    final executor = InAppCockpitCommandExecutor(
      registry: surface.registry,
      locatorProbe: surface.probeVisibleLocator,
      gestureHandler: surface.performGesture,
    );
    final result = await executor.execute(
      CockpitCommand(
        commandId: 'source-gesture-double',
        commandType: CockpitCommandType.doubleTap,
        locator: locator,
      ),
    );
    await tester.pump();

    expect(result.success, isTrue, reason: '${result.error?.details}');
    expect(activated, isTrue);
  });
}

final class SourceOnlyButton extends StatelessWidget {
  const SourceOnlyButton({required this.onPressed, required this.child});

  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerUp: (_) => onPressed(),
      child: SizedBox(width: 220, height: 48, child: Center(child: child)),
    );
  }
}
