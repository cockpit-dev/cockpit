// This file asserts wall-clock-sensitive discovery timings, so it carries the
// `perf` tag and runs in a dedicated serial invocation without concurrent
// suites (see the melos and CI test gates).
@Tags(['perf'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

// Public wrapper widgets whose slugs must survive locator-path filtering.
class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class CardShellSection extends StatelessWidget {
  const CardShellSection({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

// A scroll view outside the semantic boundary type set, so discovery falls
// back to the inner `Scrollable` element for its locator identity.
class RailView extends ScrollView {
  const RailView({super.key}) : super(primary: false);

  @override
  List<Widget> buildSlivers(BuildContext context) {
    return const <Widget>[
      SliverToBoxAdapter(child: SizedBox(height: 900, width: 64)),
    ];
  }
}

// A public branching section whose slug stays in locator paths, so a deep
// spine of these exercises path threading across thousands of elements.
class SpineSection extends StatelessWidget {
  const SpineSection({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: children);
}

void main() {
  testWidgets(
    'scrollable discovery reports stable locator paths for nested scrollables',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CockpitSurface(
            routeName: '/scroll-discovery-paths',
            child: Material(
              child: FeedScreen(
                child: SingleChildScrollView(
                  key: const ValueKey<String>('root-scroll'),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 220,
                        child: CustomScrollView(
                          key: const ValueKey<String>('feed'),
                          slivers: const <Widget>[
                            SliverToBoxAdapter(
                              child: SizedBox(height: 640, width: 64),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: CardShellSection(
                          child: SizedBox(
                            height: 220,
                            child: ListView(
                              key: const ValueKey<String>('cards'),
                              children: List<Widget>.generate(
                                12,
                                (index) => const SizedBox(height: 80),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 160,
                        child: PageView(
                          key: const ValueKey<String>('pager'),
                          children: const <Widget>[
                            SizedBox(width: 200, height: 120),
                            SizedBox(width: 200, height: 120),
                          ],
                        ),
                      ),
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

      final feed = await surfaceState.scrollByViewport(
        duration: Duration.zero,
        scrollableKey: 'feed',
      );
      final cards = await surfaceState.scrollByViewport(
        duration: Duration.zero,
        scrollableKey: 'cards',
      );
      final pager = await surfaceState.scrollByViewport(
        duration: Duration.zero,
        scrollableKey: 'pager',
      );
      final counted = await surfaceState.scrollByViewport(
        duration: Duration.zero,
        scrollableLocator: const CockpitLocator(index: 0),
      );
      await tester.pumpAndSettle();

      expect(feed.didScroll, isTrue);
      expect(
        feed.scrollablePath,
        startsWith('/feedscreen/singlechildscrollview/'),
      );
      expect(feed.scrollablePath, endsWith('/customscrollview'));
      expect(feed.scrollableTypeName, 'CustomScrollView');

      expect(cards.didScroll, isTrue);
      expect(
        cards.scrollablePath,
        startsWith('/feedscreen/singlechildscrollview/'),
      );
      expect(cards.scrollablePath, endsWith('/cardshellsection/listview'));
      expect(cards.scrollableTypeName, 'ListView');

      expect(pager.didScroll, isTrue);
      expect(
        pager.scrollablePath,
        startsWith('/feedscreen/singlechildscrollview/'),
      );
      expect(pager.scrollablePath, endsWith('/pageview'));
      expect(pager.scrollableTypeName, 'PageView');

      expect(counted.didScroll, isTrue);
      expect(counted.scrollableCandidateCount, 4);
    },
  );

  testWidgets(
    'scrollable discovery keeps ancestor chains usable for scroll locators',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CockpitSurface(
            routeName: '/scroll-discovery-ancestors',
            child: Material(
              child: FeedScreen(
                child: Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: CardShellSection(
                        child: SizedBox(
                          height: 240,
                          child: ListView(
                            key: const ValueKey<String>('cards'),
                            children: List<Widget>.generate(
                              12,
                              (index) => const SizedBox(height: 80),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 240,
                      child: PageView(
                        key: const ValueKey<String>('pager'),
                        children: const <Widget>[
                          SizedBox(width: 200, height: 120),
                          SizedBox(width: 200, height: 120),
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

      final byAncestorType = await surfaceState.scrollByViewport(
        duration: Duration.zero,
        scrollableLocator: const CockpitLocator(
          type: 'ListView',
          ancestor: CockpitLocator(type: 'CardShellSection'),
        ),
      );
      final byAncestorPath = await surfaceState.scrollByViewport(
        duration: Duration.zero,
        scrollableLocator: const CockpitLocator(
          type: 'ListView',
          ancestor: CockpitLocator(path: 'feedscreen/cardshellsection'),
        ),
      );
      final unmatchedAncestor = await surfaceState.scrollByViewport(
        duration: Duration.zero,
        scrollableLocator: const CockpitLocator(
          type: 'PageView',
          ancestor: CockpitLocator(type: 'CardShellSection'),
        ),
      );
      final pagerControl = await surfaceState.scrollByViewport(
        duration: Duration.zero,
        scrollableLocator: const CockpitLocator(type: 'PageView'),
      );
      await tester.pumpAndSettle();

      expect(byAncestorType.didScroll, isTrue);
      expect(byAncestorType.scrollableKey, 'cards');
      expect(byAncestorType.scrollableCandidateCount, 1);

      expect(byAncestorPath.didScroll, isTrue);
      expect(byAncestorPath.scrollableKey, 'cards');
      expect(byAncestorPath.scrollableCandidateCount, 1);

      expect(unmatchedAncestor.didScroll, isFalse);
      expect(pagerControl.didScroll, isTrue);
      expect(pagerControl.scrollableKey, 'pager');
    },
  );

  testWidgets(
    'scrollable discovery falls back to the inner Scrollable locator path',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CockpitSurface(
            routeName: '/scroll-discovery-rail',
            child: Material(
              child: Column(
                children: <Widget>[
                  const SizedBox(
                    height: 320,
                    child: RailView(key: ValueKey<String>('rail')),
                  ),
                  SizedBox(
                    height: 240,
                    child: Scrollable(
                      axisDirection: AxisDirection.down,
                      viewportBuilder: (context, position) => Viewport(
                        offset: position,
                        slivers: <Widget>[
                          SliverToBoxAdapter(
                            child: SizedBox(
                              height: 200,
                              child: ListView(
                                key: const ValueKey<String>('inner-list'),
                                children: List<Widget>.generate(
                                  4,
                                  (index) => const SizedBox(height: 80),
                                ),
                              ),
                            ),
                          ),
                          const SliverToBoxAdapter(
                            child: SizedBox(height: 1800, width: 64),
                          ),
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

      final rail = await surfaceState.scrollByViewport(
        duration: Duration.zero,
        scrollableLocator: const CockpitLocator(type: 'Scrollable'),
      );
      final innerList = await surfaceState.scrollByViewport(
        duration: Duration.zero,
        scrollableKey: 'inner-list',
      );
      await tester.pumpAndSettle();

      expect(rail.didScroll, isTrue);
      expect(rail.scrollablePath, endsWith('/cockpitsurface/railview'));
      expect(rail.scrollableTypeName, 'Scrollable');

      // The raw outer Scrollable resolves its semantic boundary to the inner
      // ListView below it, so both candidates share one locator identity and
      // the wider outer viewport wins the extent tie-break.
      expect(innerList.didScroll, isTrue);
      expect(innerList.scrollableCandidateCount, 2);
      expect(innerList.scrollableTypeName, 'ListView');
      expect(
        innerList.scrollablePath,
        endsWith('/slivertoboxadapter/listview'),
      );
    },
  );

  testWidgets('scrollable discovery stays linear on a deep wide element tree', (
    tester,
  ) async {
    const shallowSpineDepth = 50;
    const deepSpineDepth = 200;

    Widget buildLevel(int remaining) {
      return SpineSection(
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

    Future<Duration> measureScrollDiscovery(int spineDepth) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CockpitSurface(
            routeName: '/scroll-discovery-scale',
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

      final stopwatch = Stopwatch()..start();
      // Both calls re-run full discovery.
      final counted = await surfaceState.scrollByViewport(
        duration: Duration.zero,
        scrollableLocator: const CockpitLocator(index: 0),
      );
      final deepResult = await surfaceState.scrollByViewport(
        duration: Duration.zero,
        scrollableKey: 'deep-scroll',
      );
      stopwatch.stop();
      await tester.pumpAndSettle();

      expect(counted.scrollableCandidateCount, spineDepth * 2 + 2);
      expect(deepResult.didScroll, isTrue);
      expect(deepResult.scrollableKey, 'deep-scroll');
      return stopwatch.elapsed;
    }

    final shallow = await measureScrollDiscovery(shallowSpineDepth);
    final deep = await measureScrollDiscovery(deepSpineDepth);
    // The old per-candidate ancestor re-walks scaled quadratically and took
    // well over half a minute on the deep tree. Linear discovery grows ~4x
    // with this 4x depth, so the 10x bound separates both regimes and,
    // unlike an absolute wall-clock threshold, stays reproducible while
    // other test suites run concurrently.
    expect(deep, lessThan(shallow * 10));
  });
}
