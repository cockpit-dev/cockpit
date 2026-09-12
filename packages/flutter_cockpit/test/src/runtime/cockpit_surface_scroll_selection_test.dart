import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

// Public wrapper widget whose slug stays in locator paths.
class SelectionScreen extends StatelessWidget {
  const SelectionScreen({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

// A public branching section whose slug stays in locator paths, so a deep
// spine of these exercises selection across thousands of elements.
class SelectionSpine extends StatelessWidget {
  const SelectionSpine({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: children);
}

void main() {
  testWidgets(
    'scrollable selection keeps target distance and extent ordering stable',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CockpitSurface(
            routeName: '/scroll-selection-order',
            child: Material(
              child: SelectionScreen(
                child: Column(
                  children: <Widget>[
                    const Text('stage header'),
                    SizedBox(
                      height: 170,
                      child: ListView(
                        key: const ValueKey<String>('near-list'),
                        children: <Widget>[
                          const Text('near target'),
                          ...List<Widget>.generate(
                            12,
                            (_) => const SizedBox(height: 60),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 170,
                      child: ListView(
                        key: const ValueKey<String>('far-list'),
                        children: List<Widget>.generate(
                          24,
                          (_) => const SizedBox(height: 60),
                        ),
                      ),
                    ),
                    const SizedBox(
                      height: 170,
                      child: CustomScrollView(
                        key: ValueKey<String>('wide-scroll'),
                        slivers: <Widget>[
                          SliverToBoxAdapter(
                            child: SizedBox(height: 2000, width: 64),
                          ),
                        ],
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

      final surfaceState = tester.state<CockpitSurfaceState>(
        find.byType(CockpitSurface),
      );

      // A resolvable text target collapses the field to the scrollables
      // that contain it and picks the nearest one.
      final byText = await surfaceState.scrollByViewport(
        duration: Duration.zero,
        targetLocator: const CockpitLocator(text: 'near target'),
      );
      expect(byText.scrollableKey, 'near-list');
      expect(byText.scrollableCandidateCount, 1);

      // A pure type locator with no target falls through to the extent
      // tie-break, which prefers the largest scrollable extent.
      final byType = await surfaceState.scrollByViewport(
        duration: Duration.zero,
        scrollableLocator: const CockpitLocator(type: 'ListView'),
      );
      expect(byType.scrollableKey, 'far-list');
      expect(byType.scrollableCandidateCount, 2);

      // A type target that resolves to the widest scroller's semantic
      // boundary matches it at distance zero and collapses the field.
      final byTypeTarget = await surfaceState.scrollByViewport(
        duration: Duration.zero,
        targetLocator: const CockpitLocator(type: 'CustomScrollView'),
      );
      expect(byTypeTarget.scrollableKey, 'wide-scroll');
      expect(byTypeTarget.scrollableCandidateCount, 1);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('scrollable selection prefers keyed candidates on score ties', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CockpitSurface(
          routeName: '/scroll-selection-keyed',
          child: Material(
            child: SelectionScreen(
              child: Column(
                children: <Widget>[
                  SizedBox(
                    height: 220,
                    child: ListView(
                      key: const ValueKey<String>('keyed-twin'),
                      children: List<Widget>.generate(
                        12,
                        (_) => const SizedBox(height: 60),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 220,
                    child: ListView(
                      children: List<Widget>.generate(
                        12,
                        (_) => const SizedBox(height: 60),
                      ),
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

    final surfaceState = tester.state<CockpitSurfaceState>(
      find.byType(CockpitSurface),
    );

    // Both twins match the type signal with identical extents; only the
    // key bonus separates them.
    final selected = await surfaceState.scrollByViewport(
      duration: Duration.zero,
      scrollableLocator: const CockpitLocator(type: 'ListView'),
    );
    await tester.pumpAndSettle();

    expect(selected.scrollableKey, 'keyed-twin');
    expect(selected.scrollableCandidateCount, 2);
  });

  testWidgets(
    'scrollable target context scores subtree text but not path-only locators',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CockpitSurface(
            routeName: '/scroll-selection-context',
            child: Material(
              child: SelectionScreen(
                child: Column(
                  children: <Widget>[
                    const Text('stage header'),
                    SizedBox(
                      height: 170,
                      child: ListView(
                        key: const ValueKey<String>('needle-list'),
                        children: <Widget>[
                          Semantics(
                            label: 'prefix deep needle suffix',
                            child: const SizedBox(height: 40),
                          ),
                          ...List<Widget>.generate(
                            12,
                            (_) => const SizedBox(height: 60),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 170,
                      child: ListView(
                        key: const ValueKey<String>('blank-list'),
                        children: List<Widget>.generate(
                          24,
                          (_) => const SizedBox(height: 60),
                        ),
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

      final surfaceState = tester.state<CockpitSurfaceState>(
        find.byType(CockpitSurface),
      );

      // The containing (not exact) label keeps the target element null, so
      // only the subtree context walk can prefer the smaller scrollable.
      final byText = await surfaceState.scrollByViewport(
        duration: Duration.zero,
        targetLocator: const CockpitLocator(text: 'deep needle'),
      );
      expect(byText.scrollableKey, 'needle-list');
      expect(byText.scrollableCandidateCount, 2);

      // Path-only and ancestor-bearing targets contribute no context score,
      // so the larger extent wins instead.
      final byPath = await surfaceState.scrollByViewport(
        duration: Duration.zero,
        targetLocator: const CockpitLocator(path: 'selectionscreen/nowhere'),
      );
      expect(byPath.scrollableKey, 'blank-list');
      expect(byPath.scrollableCandidateCount, 2);

      final byPathWithAncestor = await surfaceState.scrollByViewport(
        duration: Duration.zero,
        targetLocator: const CockpitLocator(
          path: 'selectionscreen/nowhere',
          ancestor: CockpitLocator(type: 'SelectionScreen'),
        ),
      );
      expect(byPathWithAncestor.scrollableKey, 'blank-list');
      await tester.pumpAndSettle();
    },
  );

  testWidgets('scrollable selection stays linear on a deep wide element tree', (
    tester,
  ) async {
    const spineDepth = 200;

    Widget buildLevel(int remaining) {
      return SelectionSpine(
        children: <Widget>[
          for (var index = 0; index < 2; index += 1)
            SizedBox(
              height: 120,
              child: ListView(
                children: List<Widget>.generate(
                  12,
                  (_) => const SizedBox(height: 40),
                ),
              ),
            ),
          if (remaining == 0)
            SizedBox(
              height: 240,
              child: ListView(
                key: const ValueKey<String>('deep-scroll'),
                children: List<Widget>.generate(
                  12,
                  (_) => const SizedBox(height: 80),
                ),
              ),
            )
          else
            buildLevel(remaining - 1),
        ],
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: CockpitSurface(
          routeName: '/scroll-selection-scale',
          child: Material(
            child: SingleChildScrollView(child: buildLevel(spineDepth - 1)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final surfaceState = tester.state<CockpitSurfaceState>(
      find.byType(CockpitSurface),
    );

    // The absent type keeps the target element null so every candidate
    // stays in the ordered field, each with a type-signal context walk.
    final stopwatch = Stopwatch()..start();
    final selected = await surfaceState.scrollByViewport(
      duration: Duration.zero,
      targetLocator: const CockpitLocator(type: 'NestedScrollView'),
    );
    stopwatch.stop();
    await tester.pumpAndSettle();

    expect(selected.scrollableCandidateCount, spineDepth * 2 + 2);
    // The comparator used to recompute each candidate's context-walking
    // priority score per comparison, which kept this call near six seconds;
    // the stopwatch still covers discovery and the target probes, so the
    // bound stays generous relative to the measured post-fix time.
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
  });
}
