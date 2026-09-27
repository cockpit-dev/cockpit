// This file asserts absolute probe timings, so it carries the `perf` tag and
// runs in a dedicated invocation without concurrent suites (see the melos and
// CI test gates).
@Tags(['perf'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

// A shell branch kept mounted behind a visible Offstage wrapper, mirroring
// navigation shells that retain inactive platform branches in the tree.
class ShellBranch extends StatelessWidget {
  const ShellBranch({super.key, required this.label, required this.rowCount});

  final String label;
  final int rowCount;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Text(label),
      for (var index = 0; index < rowCount; index += 1)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: <Widget>[
              const SizedBox(width: 8, height: 12),
              Text('$label row $index'),
              const SizedBox(width: 8),
              const Icon(Icons.star_outline),
            ],
          ),
        ),
    ],
  );
}

void main() {
  testWidgets('probe scoring stays fast on a wide shell tree', (tester) async {
    const branchCount = 42;
    const rowsPerBranch = 15;

    await tester.pumpWidget(
      MaterialApp(
        home: CockpitSurface(
          routeName: '/probe-perf',
          child: Material(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    height: 120,
                    child: CustomScrollView(
                      slivers: <Widget>[
                        const SliverToBoxAdapter(child: SizedBox(height: 40)),
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: 40,
                            child: Center(
                              child: Container(
                                key: const ValueKey<String>('perf-needle'),
                                child: const Text('Perf needle'),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (var index = 0; index < branchCount; index += 1)
                    Offstage(
                      offstage: false,
                      child: ShellBranch(
                        label: 'Branch $index',
                        rowCount: rowsPerBranch,
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
    final engine = const CockpitDiscoveryEngine();
    // Roughly 5k mounted elements: 42 branches x 15 rows of wrapped text
    // plus the main scroll spine.
    expect(tester.allElements.length, greaterThan(4500));

    // Warm every code path once so the guard measures steady-state scoring,
    // not first-run JIT or lazy static initialization.
    surfaceState.probeVisibleLocator(
      const CockpitLocator(type: 'CustomScrollView'),
    );
    surfaceState.probeVisibleLocator(const CockpitLocator(text: 'Perf needle'));

    final byType = surfaceState.probeVisibleLocator(
      const CockpitLocator(type: 'CustomScrollView'),
    );
    final byText = surfaceState.probeVisibleLocator(
      const CockpitLocator(text: 'Perf needle'),
    );

    expect(byType.isSuccess, isTrue, reason: 'type probe must stay correct');
    expect(byType.target?.typeName, 'CustomScrollView');
    expect(byText.isSuccess, isTrue, reason: 'text probe must stay correct');
    expect(byText.target?.text, 'Perf needle');

    // Best-of-five keeps the guard meaningful under load: the minimum
    // approaches the unloaded cost, so transient scheduler spikes cannot
    // fail a healthy build.
    Duration bestOf(void Function() measure, {int attempts = 5}) {
      var best = const Duration(days: 1);
      for (var attempt = 0; attempt < attempts; attempt += 1) {
        final stopwatch = Stopwatch()..start();
        measure();
        stopwatch.stop();
        if (stopwatch.elapsed < best) {
          best = stopwatch.elapsed;
        }
      }
      return best;
    }

    // Absolute probe timings shift several-fold with sustained CPU load and
    // thermal state, so the guard is expressed relative to a full discovery
    // pass over the same tree, measured in the same process: both scale with
    // the machine's current speed, while a scoring regression inflates only
    // the probes. Before the prepared-locator walk (flattened signals,
    // static patterns, memoized type-name normalization) the type probe ran
    // ~5x slower on this tree; healthy probes measure ~0.08 (type) and
    // ~0.05 (text) of a discovery pass even on a fully heat-soaked machine,
    // while the un-prepared type probe lands near ~0.4 of it.
    final discoverBaseline = bestOf(
      () => engine.discover(
        rootContext: tester.element(find.byType(CockpitSurface)),
        routeName: '/probe-perf',
        includeClippedTargets: true,
      ),
      attempts: 3,
    );
    final typeProbe = bestOf(() {
      surfaceState.probeVisibleLocator(
        const CockpitLocator(type: 'CustomScrollView'),
      );
    });
    final textProbe = bestOf(() {
      surfaceState.probeVisibleLocator(
        const CockpitLocator(text: 'Perf needle'),
      );
    });

    expect(typeProbe, lessThan(discoverBaseline * 0.2));
    expect(textProbe, lessThan(discoverBaseline * 0.2));
  });
}
