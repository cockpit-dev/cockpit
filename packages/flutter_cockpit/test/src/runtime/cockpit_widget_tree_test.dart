import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'widget tree traverses mounted Elements without Semantics labels',
    (tester) async {
      final surfaceKey = GlobalKey<CockpitSurfaceState>();

      await tester.pumpWidget(
        CockpitSurface(
          key: surfaceKey,
          routeName: '/tree',
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: <Widget>[
                  ExcludeSemantics(
                    child: TextButton(
                      onPressed: () {},
                      child: const Text('No semantics required'),
                    ),
                  ),
                  const Offstage(
                    offstage: true,
                    child: Text('Mounted offstage node'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final surface = surfaceKey.currentState!;
      final resolution = surface.probeVisibleLocator(
        const CockpitLocator(text: 'No semantics required'),
      );
      expect(resolution.isSuccess, isTrue);

      final minimal = surface.snapshot(
        options: const CockpitSnapshotOptions(
          tree: CockpitWidgetTreeOptions.minimal(),
        ),
      );
      final full = surface.snapshot(
        options: const CockpitSnapshotOptions(
          tree: CockpitWidgetTreeOptions.full(),
        ),
      );

      expect(minimal.tree, isNotNull);
      expect(full.tree, isNotNull);
      expect(full.tree!.total, greaterThan(minimal.tree!.nodes.length));
      expect(
        full.tree!.nodes.map((node) => node.node).toSet().length,
        full.tree!.nodes.length,
      );

      final actionable = minimal.tree!.nodes.firstWhere(
        (node) =>
            node.text == 'No semantics required' && node.actions.isNotEmpty,
      );
      expect(actionable.actions, contains(CockpitCommandType.tap));
      expect(actionable.loc, isNotNull);
      expect(actionable.visible, isTrue);

      final offstage = full.tree!.nodes.firstWhere(
        (node) => node.text == 'Mounted offstage node',
      );
      expect(offstage.offstage, isTrue);
      expect(offstage.visible, isFalse);
      expect(offstage.element, isNotNull);
    },
  );

  testWidgets('widget tree can be scoped to one mounted subtree and depth', (
    tester,
  ) async {
    final surfaceKey = GlobalKey<CockpitSurfaceState>();
    await tester.pumpWidget(
      CockpitSurface(
        key: surfaceKey,
        routeName: '/tree',
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                Container(
                  key: const ValueKey<String>('settings-root'),
                  child: const Column(
                    children: <Widget>[
                      Text('Direct child'),
                      Row(children: <Widget>[Text('Nested child')]),
                    ],
                  ),
                ),
                const Text('Outside scope'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scoped = surfaceKey.currentState!.snapshot(
      options: const CockpitSnapshotOptions(
        tree: CockpitWidgetTreeOptions(
          profile: CockpitWidgetTreeProfile.full,
          maxNodes: 100,
          maxProps: 0,
          under: CockpitLocator(key: 'settings-root'),
          depth: 1,
        ),
      ),
    );

    final tree = scoped.tree!;
    expect(tree.under, const CockpitLocator(key: 'settings-root'));
    expect(tree.depth, 1);
    expect(tree.nodes, isNotEmpty);
    expect(tree.nodes.first.depth, 0);
    expect(tree.nodes.where((node) => node.depth > 1), isEmpty);
    expect(
      tree.nodes.map((node) => node.text),
      isNot(contains('Outside scope')),
    );

    final rootOnly = surfaceKey.currentState!.snapshot(
      options: const CockpitSnapshotOptions(
        tree: CockpitWidgetTreeOptions(
          profile: CockpitWidgetTreeProfile.full,
          under: CockpitLocator(key: 'settings-root'),
          depth: 0,
        ),
      ),
    );
    expect(rootOnly.tree!.nodes, hasLength(1));
    expect(rootOnly.tree!.nodes.single.depth, 0);
    expect(rootOnly.tree!.nodes.single.key, 'settings-root');
  });

  testWidgets(
    'widget tree scope fails closed for missing and ambiguous roots',
    (tester) async {
      final surfaceKey = GlobalKey<CockpitSurfaceState>();
      await tester.pumpWidget(
        CockpitSurface(
          key: surfaceKey,
          routeName: '/tree',
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: <Widget>[
                  Container(
                    key: const ValueKey<String>('duplicate-root'),
                    height: 20,
                  ),
                  Container(
                    key: const ValueKey<String>('duplicate-root-2'),
                    height: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final surface = surfaceKey.currentState!;
      expect(
        () => surface.snapshot(
          options: const CockpitSnapshotOptions(
            tree: CockpitWidgetTreeOptions(
              profile: CockpitWidgetTreeProfile.full,
              under: CockpitLocator(key: 'missing-root'),
            ),
          ),
        ),
        throwsA(isA<StateError>()),
      );

      // Two independently mounted nodes with the same type are ambiguous when
      // the scope uses only that type; tree capture must never choose one.
      expect(
        () => surface.snapshot(
          options: const CockpitSnapshotOptions(
            tree: CockpitWidgetTreeOptions(
              profile: CockpitWidgetTreeProfile.full,
              under: CockpitLocator(type: 'Container'),
            ),
          ),
        ),
        throwsA(isA<StateError>()),
      );
    },
  );
}
