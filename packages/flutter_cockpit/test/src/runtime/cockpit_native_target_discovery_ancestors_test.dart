// ignore_for_file: deprecated_member_use

// This file asserts wall-clock-sensitive discovery timings, so it carries the
// `perf` tag and runs in a dedicated serial invocation without concurrent
// suites (see the melos and CI test gates).
@Tags(['perf'])
library;

import 'package:flutter/cupertino.dart';
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
  testWidgets(
    'handler family resolves identically through the shared ancestor chains',
    (tester) async {
      var filledTapped = false;
      var iconTapped = false;
      var gestureTapped = false;
      var tileTapped = false;
      var tileLongPressed = false;
      var segmentGestureTapped = false;
      var selectedSegment = 0;
      var tooltipButtonTapped = false;
      var tooltipIconTapped = false;
      final editor = TextEditingController();
      addTearDown(editor.dispose);

      await tester.pumpWidget(
        CockpitSurface(
          routeName: '/handlers',
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: <Widget>[
                  FilledButton(
                    key: const ValueKey<String>('filled'),
                    onPressed: () => filledTapped = true,
                    child: const Text('Filled'),
                  ),
                  IconButton(
                    key: const ValueKey<String>('icon'),
                    onPressed: () => iconTapped = true,
                    icon: const SizedBox(width: 24, height: 24),
                  ),
                  GestureDetector(
                    key: const ValueKey<String>('gesture'),
                    onTap: () => gestureTapped = true,
                    onDoubleTap: () {},
                    child: const Text('Gesture'),
                  ),
                  ListTile(
                    key: const ValueKey<String>('tile'),
                    title: const Text('Tile'),
                    onTap: () => tileTapped = true,
                    onLongPress: () => tileLongPressed = true,
                  ),
                  CupertinoSegmentedControl<int>(
                    key: const ValueKey<String>('segments'),
                    children: <int, Widget>{
                      0: GestureDetector(
                        key: const ValueKey<String>('segment-gesture'),
                        onTap: () => segmentGestureTapped = true,
                        child: const Text('Segment Zero'),
                      ),
                      1: const Text('Segment One'),
                    },
                    groupValue: selectedSegment,
                    onValueChanged: (value) => selectedSegment = value,
                  ),
                  Tooltip(
                    message: 'save-hint',
                    child: FilledButton(
                      key: const ValueKey<String>('tooltip-button'),
                      onPressed: () => tooltipButtonTapped = true,
                      child: const Text('Save'),
                    ),
                  ),
                  Tooltip(
                    message: 'star-hint',
                    child: IconButton(
                      key: const ValueKey<String>('tooltip-icon'),
                      onPressed: () => tooltipIconTapped = true,
                      icon: const SizedBox(width: 24, height: 24),
                    ),
                  ),
                  TextField(
                    key: const ValueKey<String>('editor'),
                    controller: editor,
                    decoration: const InputDecoration(labelText: 'Editor'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final state = tester.state<CockpitSurfaceState>(
        find.byType(CockpitSurface),
      );
      CockpitTarget targetForKey(String key) =>
          state.registry.resolve(CockpitLocator(key: key)).target!;

      final filled = targetForKey('filled');
      expect(filled.typeName, 'FilledButton');
      expect(filled.supportedCommands, contains(CockpitCommandType.tap));
      filled.onTap?.call();
      expect(filledTapped, isTrue);

      final icon = targetForKey('icon');
      expect(icon.typeName, 'IconButton');
      icon.onTap?.call();
      expect(iconTapped, isTrue);

      final gesture = targetForKey('gesture');
      expect(
        gesture.supportedCommands,
        containsAll(<CockpitCommandType>[
          CockpitCommandType.tap,
          CockpitCommandType.doubleTap,
        ]),
      );
      gesture.onTap?.call();
      expect(gestureTapped, isTrue);

      final tile = targetForKey('tile');
      expect(tile.typeName, 'ListTile');
      expect(
        tile.supportedCommands,
        containsAll(<CockpitCommandType>[
          CockpitCommandType.tap,
          CockpitCommandType.longPress,
        ]),
      );
      tile.onTap?.call();
      tile.onLongPress?.call();
      expect(tileTapped, isTrue);
      expect(tileLongPressed, isTrue);

      // The enclosing segment control owns the tap before the local
      // GestureDetector: the child surfaces as a CupertinoSegment whose
      // handler routes to onValueChanged, never to the local onTap.
      final segmentZero = state.registry
          .resolve(const CockpitLocator(text: 'Segment Zero'))
          .target!;
      expect(segmentZero.typeName, 'CupertinoSegment');
      expect(segmentZero.supportedCommands, contains(CockpitCommandType.tap));
      segmentZero.onTap?.call();
      await tester.pumpAndSettle();
      expect(selectedSegment, 0); // tapping the selected segment is a no-op.
      expect(segmentGestureTapped, isFalse);

      state.registry
          .resolve(const CockpitLocator(text: 'Segment One'))
          .target!
          .onTap
          ?.call();
      await tester.pumpAndSettle();
      expect(selectedSegment, 1);
      expect(segmentGestureTapped, isFalse);
      // The keyed GestureDetector leaf never surfaces as its own target; the
      // segment owns the interaction.
      expect(
        state.registry.visibleTargets.where(
          (target) => target.keyValue == 'segment-gesture',
        ),
        isEmpty,
      );

      // Tooltip inheritance rides the same shared ancestor chain.
      final tooltipButton = targetForKey('tooltip-button');
      expect(tooltipButton.tooltip, 'save-hint');
      expect(tooltipButton.supportedCommands, contains(CockpitCommandType.tap));
      tooltipButton.onTap?.call();
      expect(tooltipButtonTapped, isTrue);

      final tooltipIcon = targetForKey('tooltip-icon');
      expect(tooltipIcon.tooltip, 'star-hint');
      tooltipIcon.onTap?.call();
      expect(tooltipIconTapped, isTrue);

      final editorTarget = targetForKey('editor');
      expect(editorTarget.typeName, 'TextField');
      expect(
        editorTarget.supportedCommands,
        containsAll(<CockpitCommandType>[
          CockpitCommandType.tap,
          CockpitCommandType.enterText,
          CockpitCommandType.setTextEditingValue,
        ]),
      );
      editorTarget.onEnterText?.call('typed');
      await tester.pumpAndSettle();
      expect(editor.text, 'typed');
    },
  );

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
    const shallowSpineDepth = 50;
    const deepSpineDepth = 200;
    const leavesPerLevel = 2;
    // Component-only wrappers stretch the element chain without adding render
    // objects, so the per-element ancestor scans dominate discovery the same
    // way they do on real deep element trees.
    const componentWrappersPerLevel = 6;

    Widget wrapComponents(int remaining, Widget child) => remaining == 0
        ? child
        : KeyedSubtree(
            child: Builder(
              builder: (_) => wrapComponents(remaining - 1, child),
            ),
          );

    Widget buildLevel(int remaining) {
      return AncestorSpine(
        children: <Widget>[
          for (var index = 0; index < leavesPerLevel; index += 1)
            Text('leaf-$remaining-$index'),
          // Actionable leaves keep the per-element handler family (segment,
          // scrollable, label, hover ancestor scans) hot at every depth.
          FilledButton(
            onPressed: () {},
            child: const SizedBox(width: 24, height: 24),
          ),
          ChoiceChip(
            label: const SizedBox(width: 24, height: 24),
            selected: false,
            onSelected: (_) {},
          ),
          GestureDetector(
            onDoubleTap: () {},
            child: const SizedBox(width: 24, height: 24),
          ),
          if (remaining > 0)
            wrapComponents(
              componentWrappersPerLevel,
              buildLevel(remaining - 1),
            ),
        ],
      );
    }

    final engine = const CockpitDiscoveryEngine();

    Future<Duration> measureDiscovery(int spineDepth) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CockpitSurface(
            routeName: '/discovery-scale',
            child: Material(
              child: SingleChildScrollView(child: buildLevel(spineDepth - 1)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // One warm pass absorbs lazy cache population and JIT warmup so the
      // shallow and deep measurements stay comparable; each discover call is
      // its own session, so per-session ancestor memoization is not warmed.
      engine.discover(
        rootContext: tester.element(find.byType(CockpitSurface)),
        routeName: '/discovery-scale',
        includeClippedTargets: true,
      );
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
      expect(
        targets.where((target) => target.typeName == 'FilledButton'),
        hasLength(spineDepth),
      );
      expect(
        targets.where((target) => target.typeName == 'ChoiceChip'),
        hasLength(spineDepth),
      );
      expect(
        targets.where((target) => target.typeName == 'GestureDetector').length,
        greaterThanOrEqualTo(spineDepth),
      );
      return stopwatch.elapsed;
    }

    final shallow = await measureDiscovery(shallowSpineDepth);
    final deep = await measureDiscovery(deepSpineDepth);
    // Before the session-level ancestor memoization, every actionable leaf
    // re-walked its full ancestor chain per handler family (segment control,
    // scrollable, inherited label, key), which scaled quadratically with
    // depth and measured 15.2s on a 350-level tree. Memoized extraction is
    // linear, so the 4x deeper tree must stay well under the ~16x a
    // quadratic regression would show; the 10x bound separates both regimes
    // and, unlike an absolute wall-clock threshold, stays reproducible while
    // other test suites run concurrently.
    expect(deep, lessThan(shallow * 10));
  });
}
