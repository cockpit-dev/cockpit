// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

// Public branching spine whose slug survives locator paths, so a deep chain
// of these exercises ancestor extraction across thousands of shared scopes.
class AncestorSpine extends StatelessWidget {
  const AncestorSpine({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: children);
}

// Public inherited wrapper that must never leak into locator ancestors.
class AncestorScopeData extends InheritedWidget {
  const AncestorScopeData({super.key, required super.child});

  @override
  bool updateShouldNotify(AncestorScopeData oldWidget) => false;
}

void main() {
  testWidgets('locator ancestors keep scope order and filter wrapper noise', (
    tester,
  ) async {
    await tester.pumpWidget(
      CockpitSurface(
        routeName: '/ancestors',
        child: MaterialApp(
          home: Scaffold(
            body: AncestorScopeData(
              child: Focus(
                child: GestureDetector(
                  onTap: () {},
                  child: Stack(
                    key: const ValueKey<String>('layer-stack'),
                    children: <Widget>[
                      const Positioned(
                        left: 8,
                        top: 8,
                        child: Text('Leaf A', key: ValueKey<String>('leaf-a')),
                      ),
                      Positioned(
                        left: 200,
                        top: 8,
                        child: Tooltip(
                          message: 'leaf-b-hint',
                          child: Semantics(
                            label: 'leaf-b-scope',
                            child: const Text(
                              'Leaf B',
                              key: ValueKey<String>('leaf-b'),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final registry = tester
        .state<CockpitSurfaceState>(find.byType(CockpitSurface))
        .registry;
    final leafA = registry.resolve(const CockpitLocator(key: 'leaf-a')).target!;
    final leafB = registry.resolve(const CockpitLocator(key: 'leaf-b')).target!;

    // Wrapper ancestors are filtered; the branching scopes survive in
    // nearest-to-root order.
    const wrapperTypeNames = <String>{
      'GestureDetector',
      'Focus',
      'Semantics',
      'AncestorScopeData',
    };
    final leafATypeNames = leafA.locatorAncestors
        .map((ancestor) => ancestor.typeName)
        .toList(growable: false);
    final leafBTypeNames = leafB.locatorAncestors
        .map((ancestor) => ancestor.typeName)
        .toList(growable: false);

    // The app-owned region nearest the target is exactly these scopes, in
    // nearest-to-root order.
    expect(leafATypeNames.take(4), <String>[
      'Positioned',
      'Stack',
      'CustomMultiChildLayout',
      'Scaffold',
    ]);
    expect(leafBTypeNames.take(7), <String>[
      'OverlayPortal',
      'RawTooltip',
      'Tooltip',
      'Positioned',
      'Stack',
      'CustomMultiChildLayout',
      'Scaffold',
    ]);
    expect(leafATypeNames.last, 'CockpitSurface');
    expect(leafBTypeNames.last, 'CockpitSurface');
    expect(
      leafATypeNames,
      containsAllInOrder(<String>['Overlay', 'Navigator']),
    );
    for (final typeNames in <List<String>>[leafATypeNames, leafBTypeNames]) {
      expect(
        typeNames.any(wrapperTypeNames.contains),
        isFalse,
        reason: typeNames.join(', '),
      );
      expect(typeNames, everyElement(isNot(startsWith('_'))));
      expect(
        leafA.locatorAncestors.every(
          (ancestor) => ancestor.routeName == leafA.routeName,
        ),
        isTrue,
      );
    }

    final positionedAncestor = leafA.locatorAncestors.firstWhere(
      (ancestor) => ancestor.typeName == 'Positioned',
    );
    expect(positionedAncestor.keyValue, isNull);
    expect(positionedAncestor.cockpitId, isNull);
    expect(
      positionedAncestor.path,
      '/scaffold/custommultichildlayout/gesturedetector/stack/positioned',
    );

    final stackAncestor = leafA.locatorAncestors.firstWhere(
      (ancestor) => ancestor.typeName == 'Stack',
    );
    expect(stackAncestor.keyValue, 'layer-stack');
    expect(stackAncestor.cockpitId, 'layer-stack');
    expect(stackAncestor.semanticId, isNull);
    expect(stackAncestor.tooltip, isNull);
    expect(stackAncestor.textPreview, isNull);
    expect(
      stackAncestor.path,
      '/scaffold/custommultichildlayout/gesturedetector/stack',
    );

    final scaffoldAncestor = leafA.locatorAncestors.firstWhere(
      (ancestor) => ancestor.typeName == 'Scaffold',
    );
    expect(scaffoldAncestor.path, '/scaffold');

    // The Tooltip scope exports its message to its own record and to the
    // framework mirrors it renders through.
    final tooltipAncestors = leafB.locatorAncestors
        .takeWhile((ancestor) => ancestor.typeName != 'Positioned')
        .toList(growable: false);
    expect(tooltipAncestors.map((ancestor) => ancestor.typeName), <String>[
      'OverlayPortal',
      'RawTooltip',
      'Tooltip',
    ]);
    for (final ancestor in tooltipAncestors) {
      expect(ancestor.tooltip, 'leaf-b-hint', reason: ancestor.typeName);
      expect(ancestor.textPreview, 'leaf-b-hint', reason: ancestor.typeName);
      expect(ancestor.keyValue, isNull, reason: ancestor.typeName);
    }
    expect(
      tooltipAncestors.last.path,
      '/scaffold/custommultichildlayout/gesturedetector/stack/positioned/tooltip',
    );

    // Both leaves resolve their shared scopes below the Tooltip branch to
    // identical records, including order and paths.
    final leafAScopes = leafA.locatorAncestors
        .skipWhile((ancestor) => ancestor.typeName != 'Positioned')
        .toList(growable: false);
    final leafBScopes = leafB.locatorAncestors
        .skipWhile((ancestor) => ancestor.typeName != 'Positioned')
        .toList(growable: false);
    expect(leafBScopes, equals(leafAScopes));
  });

  testWidgets('locator ancestor extraction stays linear on a deep wide tree', (
    tester,
  ) async {
    const spineDepth = 350;
    const leavesPerLevel = 6;

    Widget buildLevel(int remaining) {
      return AncestorSpine(
        children: <Widget>[
          for (var index = 0; index < leavesPerLevel; index += 1)
            Text('leaf-$remaining-$index'),
          if (remaining > 0) buildLevel(remaining - 1),
        ],
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: CockpitSurface(
          routeName: '/discovery-scale',
          child: SingleChildScrollView(child: buildLevel(spineDepth - 1)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final engine = const CockpitDiscoveryEngine();
    final stopwatch = Stopwatch()..start();
    final targets = engine.discover(
      rootContext: tester.element(find.byType(CockpitSurface)),
      routeName: '/discovery-scale',
      includeClippedTargets: true,
    );
    stopwatch.stop();

    expect(
      targets.where((target) => target.typeName == 'RichText'),
      hasLength(spineDepth * leavesPerLevel),
    );
    // Ancestor extraction used to re-walk every target's full ancestor
    // chain and rebuild each shared ancestor record, which kept this
    // discovery above two seconds on ~5k-element trees (measured 2.25s);
    // memoizing the shared chains keeps discovery linear.
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
  });
}
