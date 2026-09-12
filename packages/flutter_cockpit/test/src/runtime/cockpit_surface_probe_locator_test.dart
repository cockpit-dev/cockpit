import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

// Public wrapper widgets whose slugs must survive locator-path filtering.
class ProbeScreen extends StatelessWidget {
  const ProbeScreen({super.key, required this.child});

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

// A public branching section whose slug stays in locator paths, so a deep
// spine of these exercises probe path threading across thousands of elements.
class SpineSection extends StatelessWidget {
  const SpineSection({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: children);
}

void main() {
  testWidgets(
    'probe resolves locators by key, text, path, and key fallback identically',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CockpitSurface(
            routeName: '/probe-freeze',
            child: Material(
              child: ProbeScreen(
                child: Column(
                  children: <Widget>[
                    ElevatedButton(
                      key: const ValueKey<String>('primary-action'),
                      onPressed: () {},
                      child: const Text('Confirm'),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: CardShellSection(
                        child: ElevatedButton(
                          key: const ValueKey<String>('nested-action'),
                          onPressed: () {},
                          child: const Text('Confirm'),
                        ),
                      ),
                    ),
                    const Text('Solo label'),
                    ElevatedButton(
                      key: const ValueKey<String>('keyed-fallback'),
                      onPressed: () {},
                      child: const Text('Other label'),
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

      final byKey = surfaceState.probeVisibleLocator(
        const CockpitLocator(key: 'primary-action'),
      );
      expect(byKey.isSuccess, isTrue);
      expect(byKey.target?.keyValue, 'primary-action');
      expect(byKey.target?.typeName, 'ElevatedButton');
      expect(byKey.target?.path, '/probescreen/elevatedbutton');

      final byText = surfaceState.probeVisibleLocator(
        const CockpitLocator(text: 'Solo label'),
      );
      expect(byText.isSuccess, isTrue);
      expect(byText.target?.text, 'Solo label');
      expect(byText.target?.typeName, 'Text');
      expect(byText.target?.path, '/probescreen/text');

      // Suffix path matching resolves the nested button only.
      final byPathSuffix = surfaceState.probeVisibleLocator(
        const CockpitLocator(path: 'cardshellsection/elevatedbutton'),
      );
      expect(byPathSuffix.isSuccess, isTrue);
      expect(byPathSuffix.locatorResolution?.matchedKind.name, 'path');
      expect(byPathSuffix.target?.keyValue, 'nested-action');
      expect(byPathSuffix.target?.typeName, 'ElevatedButton');
      expect(
        byPathSuffix.target?.path,
        '/probescreen/cardshellsection/elevatedbutton',
      );

      // A full-path locator also matches the button's internal elements,
      // whose filtered paths equal the button's own trimmed path; the probe
      // keeps reporting them as one ambiguous best-score group.
      final byPathExact = surfaceState.probeVisibleLocator(
        const CockpitLocator(path: '/probescreen/elevatedbutton'),
      );
      expect(byPathExact.isSuccess, isFalse);
      expect(byPathExact.error?.code, CockpitCommandError.ambiguousTargetCode);
      expect(byPathExact.error?.details['matchedKind'], 'path');
      expect(byPathExact.error?.details['candidateCount'], 8);

      // No visible text carries this label, so the probe falls back to the
      // stable key derived from the exact-text locator.
      final byTextKeyFallback = surfaceState.probeVisibleLocator(
        const CockpitLocator(text: 'keyed-fallback'),
      );
      expect(byTextKeyFallback.isSuccess, isTrue);
      expect(byTextKeyFallback.target?.keyValue, 'keyed-fallback');
      expect(byTextKeyFallback.target?.typeName, 'ElevatedButton');

      final byType = surfaceState.probeVisibleLocator(
        const CockpitLocator(type: 'ElevatedButton'),
      );
      expect(byType.isSuccess, isFalse);
      expect(byType.error?.code, CockpitCommandError.ambiguousTargetCode);
      expect(
        byType.error?.details['candidateCount'],
        3,
        reason: 'three equally scored on-stage buttons stay ambiguous',
      );

      final byDuplicateText = surfaceState.probeVisibleLocator(
        const CockpitLocator(text: 'Confirm'),
      );
      expect(byDuplicateText.isSuccess, isFalse);
      expect(
        byDuplicateText.error?.code,
        CockpitCommandError.ambiguousTargetCode,
      );
      expect(byDuplicateText.error?.details['candidateCount'], 2);
    },
  );

  testWidgets('probe keeps scaffold-anchored locator paths identical', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CockpitSurface(
          routeName: '/probe-scaffold',
          child: Material(
            child: Scaffold(
              body: ProbeScreen(
                child: Center(
                  child: ElevatedButton(
                    key: const ValueKey<String>('scaffold-action'),
                    onPressed: () {},
                    child: const Text('Inside scaffold'),
                  ),
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

    final byKey = surfaceState.probeVisibleLocator(
      const CockpitLocator(key: 'scaffold-action'),
    );
    expect(byKey.isSuccess, isTrue);
    expect(
      byKey.target?.path,
      '/scaffold/custommultichildlayout/probescreen/elevatedbutton',
    );

    // The scaffold anchor also applies to path-signal matching, which trims
    // candidate paths to the innermost scaffold before comparing.
    final byPath = surfaceState.probeVisibleLocator(
      const CockpitLocator(path: 'scaffold/probescreen/elevatedbutton'),
    );
    expect(byPath.isSuccess, isTrue);
    expect(byPath.target?.keyValue, 'scaffold-action');
    expect(
      byPath.target?.path,
      '/scaffold/custommultichildlayout/probescreen/elevatedbutton',
    );
  });

  testWidgets('probe with a path signal stays linear on a deep element tree', (
    tester,
  ) async {
    const spineDepth = 200;

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

    await tester.pumpWidget(
      MaterialApp(
        home: CockpitSurface(
          routeName: '/probe-scale',
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

    // A path signal forces a locator-path derivation for every visited
    // element; the absent value keeps the resolution trivial so the timing
    // isolates the walk itself.
    final stopwatch = Stopwatch()..start();
    final probed = surfaceState.probeVisibleLocator(
      const CockpitLocator(path: 'absent/nowhere'),
    );
    stopwatch.stop();

    expect(probed.isSuccess, isFalse);
    // The old per-element ancestor re-walks made this single probe take
    // more than six seconds on this tree.
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
  });
}
