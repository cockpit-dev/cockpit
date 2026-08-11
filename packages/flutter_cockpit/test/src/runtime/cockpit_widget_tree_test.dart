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
}
