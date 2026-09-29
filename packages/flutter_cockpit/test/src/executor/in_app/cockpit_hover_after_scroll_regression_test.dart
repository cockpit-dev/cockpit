import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hover regressions: the command must dispatch a mouse hover event at the
/// locator-matched region, even when the region was revealed by scrolling or
/// when an enclosing hover-tracking ancestor (for example a desktop
/// Scrollbar's tracker MouseRegion) also handles hover.
void main() {
  Widget labScreen(
    List<String> hoverStates, {
    int rows = 3,
    Widget Function(Widget child)? scrollWrapper,
  }) {
    final body = ListView(
      children: <Widget>[
        for (var i = 0; i < rows; i++) ListTile(title: Text('Row $i')),
        Card(
          key: const Key('lab-hover-pad'),
          clipBehavior: Clip.antiAlias,
          child: Semantics(
            label: 'Hover pad',
            container: true,
            child: MouseRegion(
              key: const Key('lab-hover-region'),
              opaque: true,
              onEnter: (_) => hoverStates.add('entered'),
              onHover: (_) => hoverStates.add('hovered'),
              onExit: (_) => hoverStates.add('exited'),
              child: const SizedBox(
                height: 88,
                child: Center(child: Text('Move a pointer across this pad')),
              ),
            ),
          ),
        ),
      ],
    );
    return Scaffold(body: scrollWrapper == null ? body : scrollWrapper(body));
  }

  Widget labApp(
    List<String> hoverStates, {
    int rows = 3,
    Widget Function(Widget child)? scrollWrapper,
  }) {
    return CockpitSurface(
      routeName: '/lab',
      child: MaterialApp(
        home: labScreen(hoverStates, rows: rows, scrollWrapper: scrollWrapper),
      ),
    );
  }

  InAppCockpitCommandExecutor executorFor(
    WidgetTester tester,
    CockpitSurfaceState surfaceState,
  ) {
    return InAppCockpitCommandExecutor(
      registry: surfaceState.registry,
      locatorProbe: surfaceState.probeVisibleLocator,
      snapshotProvider: surfaceState.snapshot,
      gestureHandler: surfaceState.performGesture,
      postActionSettler: () async {
        await tester.pump();
        await tester.pump();
      },
      scrollStepHandler:
          ({
            required reverse,
            required viewportFraction,
            scrollableKey,
            targetLocator,
            scrollableLocator,
            required duration,
            required gestureProfile,
            required continuous,
            required postScrollEnsureVisible,
          }) {
            return surfaceState.scrollByViewport(
              reverse: reverse,
              viewportFraction: viewportFraction,
              scrollableKey: scrollableKey,
              duration: duration,
              gestureProfile: gestureProfile,
              continuous: continuous,
              postScrollEnsureVisible: postScrollEnsureVisible,
            );
          },
    );
  }

  Future<CockpitCommandResult> hoverRegion(
    InAppCockpitCommandExecutor executor,
  ) {
    return executor.execute(
      CockpitCommand(
        commandId: 'hover',
        commandType: CockpitCommandType.hover,
        locator: const CockpitLocator(key: 'lab-hover-region'),
      ),
    );
  }

  testWidgets('hover enters a MouseRegion already on screen', (tester) async {
    final hoverStates = <String>[];

    await tester.pumpWidget(labApp(hoverStates));
    await tester.pumpAndSettle();

    final surfaceState = tester.state<CockpitSurfaceState>(
      find.byType(CockpitSurface),
    );
    final hover = await hoverRegion(executorFor(tester, surfaceState));

    expect(hover.success, isTrue, reason: 'hover command should succeed');
    expect(
      hoverStates,
      contains('entered'),
      reason: 'implicit hover device kind must be a mouse pointer',
    );
  });

  testWidgets('hover enters a MouseRegion revealed by scrolling', (
    tester,
  ) async {
    final hoverStates = <String>[];

    await tester.pumpWidget(labApp(hoverStates, rows: 30));
    await tester.pumpAndSettle();

    final surfaceState = tester.state<CockpitSurfaceState>(
      find.byType(CockpitSurface),
    );
    final executor = executorFor(tester, surfaceState);

    final reveal = await executor.execute(
      CockpitCommand(
        commandId: 'reveal',
        commandType: CockpitCommandType.scrollUntilVisible,
        locator: const CockpitLocator(key: 'lab-hover-region'),
        parameters: const <String, Object?>{'maxScrolls': 20},
      ),
    );
    expect(reveal.success, isTrue, reason: 'reveal should succeed');

    final hover = await hoverRegion(executor);

    expect(hover.success, isTrue, reason: 'hover command should succeed');
    expect(
      hoverStates,
      contains('entered'),
      reason: 'hover must anchor at the region after it has been revealed',
    );
  });

  testWidgets('hover anchors at the region inside a hover-tracking ancestor', (
    tester,
  ) async {
    final hoverStates = <String>[];
    final ancestorStates = <String>[];

    await tester.pumpWidget(
      labApp(
        hoverStates,
        scrollWrapper: (child) {
          return MouseRegion(
            opaque: false,
            onEnter: (_) => ancestorStates.add('ancestor-entered'),
            onExit: (_) => ancestorStates.add('ancestor-exited'),
            child: child,
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    final surfaceState = tester.state<CockpitSurfaceState>(
      find.byType(CockpitSurface),
    );
    final hover = await hoverRegion(executorFor(tester, surfaceState));

    expect(hover.success, isTrue, reason: 'hover command should succeed');
    expect(
      hoverStates,
      contains('entered'),
      reason:
          'an ancestor that also handles hover (e.g. a Scrollbar tracker) '
          'must not steal the hover anchor from the matched region',
    );
    expect(
      ancestorStates,
      contains('ancestor-entered'),
      reason: 'the enclosing hover region still receives the same event',
    );
  });
}
