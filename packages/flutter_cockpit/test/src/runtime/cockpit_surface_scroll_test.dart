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
        offset: 24,
      );
      await tester.pumpAndSettle();

      final viewportRect = tester.getRect(
        find.byKey(const ValueKey<String>('center-scrollable')),
      );
      final targetRect = tester.getRect(find.text('Task 18'));

      expect(didReveal, isTrue);
      expect(targetRect.center.dy, closeTo(viewportRect.center.dy + 24, 4));
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

  testWidgets('ensureLocatorVisible reveals text excluded from semantics', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 320,
          child: CockpitSurface(
            routeName: '/semantic-field',
            child: Material(
              child: SingleChildScrollView(
                controller: controller,
                child: Column(
                  children: <Widget>[
                    const SizedBox(height: 520),
                    const ExcludeSemantics(child: Text('Idempotency key')),
                    Semantics(
                      container: true,
                      label: 'Request identifier',
                      child: const SizedBox(height: 40, child: TextField()),
                    ),
                    const SizedBox(height: 320),
                  ],
                ),
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
    final revealed = await surfaceState.ensureLocatorVisible(
      const CockpitLocator(text: 'Idempotency key'),
      alignment: CockpitRevealAlignment.center,
      duration: Duration.zero,
    );
    await tester.pumpAndSettle();

    expect(revealed, isTrue);
    expect(controller.offset, greaterThan(0));
  });

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
        targetLocator: const CockpitLocator(text: 'Missing task'),
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
    'scrollByViewport uses a controlled jump for target-driven search',
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
      expect(didScroll.strategy, 'jumpTo');
      expect(didScroll.hadSemanticAction, isFalse);
      expect(controller.offset, greaterThan(0));
    },
  );

  testWidgets(
    'scrollByViewport prioritizes the scrollable whose subtree mentions the target',
    (tester) async {
      final leftController = ScrollController();
      final rightController = ScrollController();
      addTearDown(leftController.dispose);
      addTearDown(rightController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: CockpitSurface(
            routeName: '/parallel-scrollables',
            child: Row(
              children: <Widget>[
                Expanded(
                  child: ListView.builder(
                    key: const ValueKey<String>('unrelated-list'),
                    controller: leftController,
                    itemCount: 60,
                    itemBuilder: (context, index) => SizedBox(
                      height: 72,
                      child: Text('Unrelated item $index'),
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    key: const ValueKey<String>('matching-details'),
                    controller: rightController,
                    child: const Column(
                      children: <Widget>[
                        SizedBox(height: 420),
                        Text(
                          'Configure the Idempotency key before invoking this '
                          'mutating operation.',
                        ),
                        SizedBox(height: 720),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final surfaceState = tester.state<CockpitSurfaceState>(
        find.byType(CockpitSurface),
      );
      final result = await surfaceState.scrollByViewport(
        targetLocator: const CockpitLocator(text: 'Idempotency key'),
        scrollableLocator: const CockpitLocator(index: 0),
        duration: Duration.zero,
      );
      await tester.pump();

      expect(result.didScroll, isTrue);
      expect(result.scrollableCandidateIndex, 0);
      expect(result.scrollableCandidateCount, 2);
      expect(result.scrollableKey, 'matching-details');
      expect(rightController.offset, greaterThan(0));
      expect(leftController.offset, 0);
    },
  );

  testWidgets(
    'scrollByViewport ignores scrollables from inactive navigator routes',
    (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      final inboxController = ScrollController();
      final settingsController = ScrollController();
      addTearDown(inboxController.dispose);
      addTearDown(settingsController.dispose);

      await tester.pumpWidget(
        CockpitSurface(
          routeName: '/settings',
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: ListView.builder(
              controller: inboxController,
              itemCount: 60,
              itemBuilder: (context, index) =>
                  SizedBox(height: 72, child: Text('Inbox task $index')),
            ),
            routes: <String, WidgetBuilder>{
              '/settings': (context) => ListView.builder(
                controller: settingsController,
                itemCount: 40,
                itemBuilder: (context, index) =>
                    SizedBox(height: 72, child: Text('Settings task $index')),
              ),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      navigatorKey.currentState!.pushNamed('/settings');
      await tester.pumpAndSettle();

      final surfaceState = tester.state<CockpitSurfaceState>(
        find.byType(CockpitSurface),
      );
      final result = await surfaceState.scrollByViewport(
        targetLocator: const CockpitLocator(text: 'Settings task 20'),
        duration: Duration.zero,
      );
      await tester.pump();

      expect(result.didScroll, isTrue);
      expect(inboxController.offset, 0);
      expect(settingsController.offset, greaterThan(0));
    },
  );

  testWidgets(
    'ensureLocatorVisible reveals a target through nested scrollable ancestors',
    (tester) async {
      final outerController = ScrollController();
      final innerController = ScrollController();
      addTearDown(outerController.dispose);
      addTearDown(innerController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 320,
              height: 320,
              child: CockpitSurface(
                routeName: '/nested-scrollables',
                child: SingleChildScrollView(
                  key: const ValueKey<String>('outer-scrollable'),
                  controller: outerController,
                  child: Column(
                    children: <Widget>[
                      const SizedBox(height: 520),
                      SizedBox(
                        height: 220,
                        child: SingleChildScrollView(
                          key: const ValueKey<String>('inner-scrollable'),
                          controller: innerController,
                          child: Column(
                            children: List<Widget>.generate(
                              18,
                              (index) => SizedBox(
                                height: 72,
                                child: Text('Nested task $index'),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 420),
                    ],
                  ),
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
      final revealed = await surfaceState.ensureLocatorVisible(
        const CockpitLocator(text: 'Nested task 14'),
        alignment: CockpitRevealAlignment.center,
        offset: 12,
        duration: Duration.zero,
      );
      await tester.pumpAndSettle();

      final outerRect = tester.getRect(
        find.byKey(const ValueKey<String>('outer-scrollable')),
      );
      final innerRect = tester.getRect(
        find.byKey(const ValueKey<String>('inner-scrollable')),
      );
      final targetRect = tester.getRect(find.text('Nested task 14'));

      expect(revealed, isTrue);
      expect(outerController.offset, greaterThan(0));
      expect(innerController.offset, greaterThan(0));
      expect(targetRect.left, greaterThanOrEqualTo(outerRect.left - 0.5));
      expect(targetRect.top, greaterThanOrEqualTo(outerRect.top - 0.5));
      expect(targetRect.right, lessThanOrEqualTo(outerRect.right + 0.5));
      expect(targetRect.bottom, lessThanOrEqualTo(outerRect.bottom + 0.5));
      expect(targetRect.left, greaterThanOrEqualTo(innerRect.left - 0.5));
      expect(targetRect.top, greaterThanOrEqualTo(innerRect.top - 0.5));
      expect(targetRect.right, lessThanOrEqualTo(innerRect.right + 0.5));
      expect(targetRect.bottom, lessThanOrEqualTo(innerRect.bottom + 0.5));
      expect(targetRect.center.dy, closeTo(innerRect.center.dy + 12, 4));
    },
  );

  testWidgets(
    'scrollByViewport exposes nested target ancestors from inner to outer',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 320,
            height: 320,
            child: CockpitSurface(
              routeName: '/nested-candidates',
              child: SingleChildScrollView(
                key: const ValueKey<String>('outer-candidate'),
                child: Column(
                  children: <Widget>[
                    const SizedBox(height: 440),
                    SizedBox(
                      height: 200,
                      child: SingleChildScrollView(
                        key: const ValueKey<String>('inner-candidate'),
                        child: Column(
                          children: List<Widget>.generate(
                            16,
                            (index) => SizedBox(
                              height: 64,
                              child: Text('Candidate task $index'),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 360),
                  ],
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
      const target = CockpitLocator(text: 'Candidate task 12');
      final innerStep = await surfaceState.scrollByViewport(
        targetLocator: target,
        scrollableLocator: const CockpitLocator(index: 0),
        duration: Duration.zero,
        probeDuringScroll: false,
      );
      final outerStep = await surfaceState.scrollByViewport(
        targetLocator: target,
        scrollableLocator: const CockpitLocator(index: 1),
        duration: Duration.zero,
        probeDuringScroll: false,
      );

      expect(innerStep.scrollableCandidateIndex, 0);
      expect(innerStep.scrollableCandidateCount, 2);
      expect(innerStep.scrollableKey, 'inner-candidate');
      expect(outerStep.scrollableCandidateIndex, 1);
      expect(outerStep.scrollableCandidateCount, 2);
      expect(outerStep.scrollableKey, 'outer-candidate');
    },
  );

  testWidgets(
    'scrollByViewport preserves mounted target state when ranking narrows',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 640,
            height: 320,
            child: CockpitSurface(
              routeName: '/mounted-target',
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: const <Widget>[
                          SizedBox(height: 900),
                          Text('Unrelated target'),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: const <Widget>[
                          SizedBox(height: 700),
                          Text('Mounted target'),
                          SizedBox(height: 200),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final surfaceState = tester.state<CockpitSurfaceState>(
        find.byType(CockpitSurface),
      );
      final result = await surfaceState.scrollByViewport(
        targetLocator: const CockpitLocator(text: 'Mounted target'),
        scrollableLocator: const CockpitLocator(index: 1),
        duration: Duration.zero,
        probeDuringScroll: false,
      );

      expect(result.didScroll, isFalse);
      expect(result.scrollableCandidateCount, 2);
      expect(result.targetVisibilityObserved, isTrue);
      expect(result.targetMounted, isTrue);
      expect(result.targetVisible, isFalse);
    },
  );
}
