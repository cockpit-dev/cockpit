import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

class _ProgrammaticOnlyScrollPhysics extends ClampingScrollPhysics {
  const _ProgrammaticOnlyScrollPhysics({super.parent});

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) => false;

  @override
  bool get allowUserScrolling => true;

  @override
  _ProgrammaticOnlyScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _ProgrammaticOnlyScrollPhysics(parent: buildParent(ancestor));
  }
}

void main() {
  testWidgets(
    'ensureLocatorVisible can center an element within the viewport',
    (tester) async {
      await tester.pumpWidget(
        WidgetsApp(
          color: const Color(0xFFFFFFFF),
          builder: (context, child) {
            return Center(
              child: SizedBox(
                width: 320,
                height: 320,
                child: CockpitSurface(
                  routeName: '/center-reveal',
                  child: Material(
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: SingleChildScrollView(
                        key: const ValueKey<String>('center-scrollable'),
                        child: Column(
                          children: List<Widget>.generate(30, (index) {
                            return SizedBox(
                              key: ValueKey<String>('center-task-$index'),
                              height: 88,
                              child: ListTile(title: Text('Task $index')),
                            );
                          }),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      final surfaceState = tester.state<CockpitSurfaceState>(
        find.byType(CockpitSurface),
      );

      final didReveal = await surfaceState.ensureLocatorVisible(
        const CockpitLocator(text: 'Task 18'),
        alignment: CockpitRevealAlignment.center,
      );
      await tester.pumpAndSettle();

      final viewportRect = tester.getRect(
        find.byKey(const ValueKey<String>('center-scrollable')),
      );
      final targetRect = tester.getRect(find.text('Task 18'));

      expect(didReveal, isTrue);
      expect(targetRect.center.dy, closeTo(viewportRect.center.dy, 40));
    },
  );

  testWidgets(
    'ensureLocatorVisible can keep an end padding from the viewport edge',
    (tester) async {
      await tester.pumpWidget(
        WidgetsApp(
          color: const Color(0xFFFFFFFF),
          builder: (context, child) {
            return Center(
              child: SizedBox(
                width: 320,
                height: 320,
                child: CockpitSurface(
                  routeName: '/end-reveal',
                  child: Material(
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: SingleChildScrollView(
                        key: const ValueKey<String>('end-scrollable'),
                        child: Column(
                          children: List<Widget>.generate(30, (index) {
                            return SizedBox(
                              key: ValueKey<String>('end-task-$index'),
                              height: 88,
                              child: ListTile(title: Text('Task $index')),
                            );
                          }),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      final surfaceState = tester.state<CockpitSurfaceState>(
        find.byType(CockpitSurface),
      );

      final didReveal = await surfaceState.ensureLocatorVisible(
        const CockpitLocator(text: 'Task 18'),
        alignment: CockpitRevealAlignment.end,
        padding: 32,
      );
      await tester.pumpAndSettle();

      final viewportRect = tester.getRect(
        find.byKey(const ValueKey<String>('end-scrollable')),
      );
      final targetRect = tester.getRect(find.text('Task 18'));

      expect(didReveal, isTrue);
      expect(targetRect.bottom, lessThanOrEqualTo(viewportRect.bottom - 24));
      expect(targetRect.bottom, greaterThan(viewportRect.bottom - 88));
    },
  );

  testWidgets(
    'ensureLocatorVisible does not throw for visible text outside a scrollable viewport',
    (tester) async {
      await tester.pumpWidget(
        WidgetsApp(
          color: const Color(0xFFFFFFFF),
          builder: (context, child) {
            return CockpitSurface(
              routeName: '/fixed-footer',
              child: Material(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Column(
                    children: <Widget>[
                      const Expanded(
                        child: SingleChildScrollView(
                          child: SizedBox(height: 600),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Save settings'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      final surfaceState = tester.state<CockpitSurfaceState>(
        find.byType(CockpitSurface),
      );

      final didReveal = await surfaceState.ensureLocatorVisible(
        const CockpitLocator(text: 'Save settings'),
        alignment: CockpitRevealAlignment.center,
      );

      expect(didReveal, isTrue);
      expect(find.text('Save settings'), findsOneWidget);
    },
  );

  testWidgets(
    'scrollByViewport returns false when user-like scrolling cannot move the scrollable',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        WidgetsApp(
          color: const Color(0xFFFFFFFF),
          builder: (context, child) {
            return CockpitSurface(
              routeName: '/locked-list',
              child: Material(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: ListView.builder(
                    key: const ValueKey<String>('locked-scrollable'),
                    controller: controller,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 40,
                    itemBuilder: (context, index) {
                      return SizedBox(
                        height: 96,
                        child: ListTile(title: Text('Task $index')),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      final surfaceState = tester.state<CockpitSurfaceState>(
        find.byType(CockpitSurface),
      );

      final didScroll = await surfaceState.scrollByViewport(
        viewportFraction: 0.9,
        scrollableKey: 'locked-scrollable',
      );

      expect(didScroll.didScroll, isFalse);
      expect(controller.offset, 0);
    },
  );

  testWidgets(
    'scrollByViewport falls back to programmatic scrolling when user offset is rejected',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: CockpitSurface(
            routeName: '/programmatic-scroll',
            child: Material(
              child: RefreshIndicator(
                onRefresh: () async {},
                child: ListView.builder(
                  key: const ValueKey<String>('programmatic-scrollable'),
                  controller: controller,
                  physics: const _ProgrammaticOnlyScrollPhysics(),
                  itemCount: 40,
                  itemBuilder: (context, index) {
                    return SizedBox(
                      height: 96,
                      child: ListTile(title: Text('Task $index')),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final surfaceState = tester.state<CockpitSurfaceState>(
        find.byType(CockpitSurface),
      );

      final didScroll = await surfaceState.scrollByViewport(
        viewportFraction: 0.9,
        scrollableKey: 'programmatic-scrollable',
        duration: Duration.zero,
      );
      await tester.pumpAndSettle();

      expect(didScroll.didScroll, isTrue);
      expect(controller.offset, greaterThan(0));
    },
  );

  testWidgets(
    'scrollByViewport matches semantic list boundaries for mixed path scroll locators',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: CockpitSurface(
            routeName: '/semantic-scrollable',
            child: Material(
              child: RefreshIndicator(
                onRefresh: () async {},
                child: ListView.builder(
                  key: const ValueKey<String>('semantic-scrollable'),
                  controller: controller,
                  itemCount: 40,
                  itemBuilder: (context, index) {
                    return SizedBox(
                      height: 96,
                      child: ListTile(title: Text('Task $index')),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final surfaceState = tester.state<CockpitSurfaceState>(
        find.byType(CockpitSurface),
      );

      final didScroll = await surfaceState.scrollByViewport(
        viewportFraction: 0.9,
        duration: Duration.zero,
        scrollableLocator: const CockpitLocator(
          key: 'semantic-scrollable',
          type: 'list_view',
          path: 'scaffold.body/list_view.children/0',
        ),
      );
      await tester.pumpAndSettle();

      expect(didScroll.didScroll, isTrue);
      expect(didScroll.scrollableKey, 'semantic-scrollable');
      expect(didScroll.scrollableTypeName, 'ListView');
      expect(didScroll.scrollablePath, contains('/listview'));
      expect(controller.offset, greaterThan(0));
    },
  );

  testWidgets(
    'scrollByViewport uses programmatic segmented probing for target-driven search',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: CockpitSurface(
            routeName: '/probe-scrollable',
            child: Material(
              child: ListView.builder(
                key: const ValueKey<String>('probe-scrollable'),
                controller: controller,
                itemCount: 60,
                itemBuilder: (context, index) {
                  return SizedBox(
                    height: 96,
                    child: ListTile(title: Text('Task $index')),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final surfaceState = tester.state<CockpitSurfaceState>(
        find.byType(CockpitSurface),
      );

      final didScroll = await surfaceState.scrollByViewport(
        viewportFraction: 0.8,
        duration: const Duration(milliseconds: 220),
        scrollableKey: 'probe-scrollable',
        targetLocator: const CockpitLocator(key: 'task-59'),
      );
      await tester.pumpAndSettle();

      expect(didScroll.didScroll, isTrue);
      expect(didScroll.strategy, 'jumpTo_probe');
      expect(didScroll.hadSemanticAction, isFalse);
      expect(controller.offset, greaterThan(0));
    },
  );
}
