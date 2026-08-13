import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('default policy does not create type-based action boundaries', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListTile(onTap: () {}, title: const Text('Open task')),
        ),
      ),
    );
    await tester.pump();

    final element = tester.element(find.byType(ListTile));

    expect(
      const CockpitDiscoveryPolicy().matchesInteractiveWidget(element),
      isFalse,
    );
  });

  testWidgets('material preset recognizes standard Flutter controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              FilledButton(onPressed: () {}, child: const Text('Create')),
              CupertinoButton(onPressed: () {}, child: const Text('Continue')),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final materialElement = tester.element(find.byType(FilledButton));
    final cupertinoElement = tester.element(find.byType(CupertinoButton));
    final policy = CockpitDiscoveryPolicy.material();

    expect(policy.matchesInteractiveWidget(materialElement), isTrue);
    expect(policy.matchesInteractiveWidget(cupertinoElement), isTrue);
  });

  testWidgets('copyWith extends discovery behavior without dropping preset', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              FilledButton(onPressed: () {}, child: const Text('Create')),
              const SizedBox(key: ValueKey<String>('ignored')),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final buttonElement = tester.element(find.byType(FilledButton));
    final ignoredElement = tester.element(
      find.byKey(const ValueKey<String>('ignored')),
    );
    final policy = CockpitDiscoveryPolicy.material().copyWith(
      isIgnoredSubtree: (element) =>
          element.widget.key == const ValueKey<String>('ignored'),
    );

    expect(policy.matchesInteractiveWidget(buttonElement), isTrue);
    expect(policy.ignoresSubtree(ignoredElement), isTrue);
  });

  testWidgets('policy can provide custom tap handling and text extraction', (
    tester,
  ) async {
    var tapped = false;

    await tester.pumpWidget(
      CockpitSurface(
        routeName: '/inbox',
        discoveryPolicy: CockpitDiscoveryPolicy(
          extractText: (element) {
            final widget = element.widget;
            if (widget is _CustomActionTile) {
              return widget.label;
            }
            return null;
          },
          tapHandlerForElement: (element) {
            final widget = element.widget;
            if (widget is _CustomActionTile) {
              return widget.onTap;
            }
            return null;
          },
        ),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: _CustomActionTile(
                label: 'Sync now',
                onTap: () {
                  tapped = true;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final surfaceState = tester.state<CockpitSurfaceState>(
      find.byType(CockpitSurface),
    );
    final resolution = surfaceState.registry.resolve(
      const CockpitLocator(text: 'Sync now'),
    );

    expect(resolution.isSuccess, isTrue);
    final target = resolution.target!;
    expect(target.supportedCommands, contains(CockpitCommandType.tap));

    target.onTap?.call();
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('policy can stop traversal into marked subtrees', (tester) async {
    await tester.pumpWidget(
      CockpitSurface(
        routeName: '/inbox',
        discoveryPolicy: CockpitDiscoveryPolicy(
          shouldStopTraversal: (element) =>
              element.widget.key == const ValueKey<String>('stop-traversal'),
        ),
        child: MaterialApp(
          home: Scaffold(
            body: Container(
              key: const ValueKey<String>('stop-traversal'),
              child: FilledButton(
                onPressed: () {},
                child: const Text('Hidden action'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final surfaceState = tester.state<CockpitSurfaceState>(
      find.byType(CockpitSurface),
    );
    final resolution = surfaceState.registry.resolve(
      const CockpitLocator(text: 'Hidden action'),
    );

    expect(resolution.isSuccess, isFalse);
  });

  testWidgets(
    'policy can mark a scrollable boundary and prevent nested capture',
    (tester) async {
      final outerController = ScrollController();
      final innerController = ScrollController();
      addTearDown(outerController.dispose);
      addTearDown(innerController.dispose);

      await tester.pumpWidget(
        CockpitSurface(
          routeName: '/settings',
          discoveryPolicy: CockpitDiscoveryPolicy(
            isScrollableBoundary: (element) {
              var isBoundary =
                  element.widget.key == const ValueKey<String>('outer-scroll');
              if (isBoundary) {
                return true;
              }
              element.visitAncestorElements((ancestor) {
                isBoundary =
                    ancestor.widget.key ==
                    const ValueKey<String>('outer-scroll');
                return !isBoundary;
              });
              return isBoundary;
            },
          ),
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 300,
                child: ListView(
                  key: const ValueKey<String>('outer-scroll'),
                  controller: outerController,
                  children: <Widget>[
                    SizedBox(
                      height: 300,
                      child: ListView.builder(
                        key: const ValueKey<String>('inner-scroll'),
                        controller: innerController,
                        itemCount: 30,
                        itemBuilder: (context, index) {
                          return SizedBox(
                            height: 56,
                            child: Text('Inner $index'),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 600, child: Text('Outer tail')),
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
      final innerScrolled = await surfaceState.scrollByViewport(
        scrollableKey: 'inner-scroll',
      );
      await tester.pumpAndSettle();

      expect(innerScrolled.didScroll, isFalse);
      expect(innerScrolled.scrollableKey, isNull);
      expect(innerController.offset, equals(0));
      expect(outerController.offset, equals(0));
    },
  );
}

final class _CustomActionTile extends StatelessWidget {
  const _CustomActionTile({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(),
      child: Padding(padding: const EdgeInsets.all(12), child: Text(label)),
    );
  }
}
