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
    // Roughly 5k mounted elements: 42 branches x 15 rows of wrapped text
    // plus the main scroll spine.
    expect(tester.allElements.length, greaterThan(4500));

    // Warm every code path once so the guard measures steady-state scoring,
    // not first-run JIT or lazy static initialization.
    surfaceState.probeVisibleLocator(
      const CockpitLocator(type: 'CustomScrollView'),
    );
    surfaceState.probeVisibleLocator(const CockpitLocator(text: 'Perf needle'));

    final typeStopwatch = Stopwatch()..start();
    final byType = surfaceState.probeVisibleLocator(
      const CockpitLocator(type: 'CustomScrollView'),
    );
    typeStopwatch.stop();

    final textStopwatch = Stopwatch()..start();
    final byText = surfaceState.probeVisibleLocator(
      const CockpitLocator(text: 'Perf needle'),
    );
    textStopwatch.stop();

    expect(byType.isSuccess, isTrue, reason: 'type probe must stay correct');
    expect(byType.target?.typeName, 'CustomScrollView');
    expect(byText.isSuccess, isTrue, reason: 'text probe must stay correct');
    expect(byText.target?.text, 'Perf needle');

    // Before the prepared-locator walk (flattened signals, static patterns,
    // memoized type-name normalization), these probes took ~40ms (type) and
    // ~31ms (text) on this tree; the bound leaves ~2x headroom over the
    // post-fix numbers (~8ms and ~13ms).
    expect(typeStopwatch.elapsed, lessThan(const Duration(milliseconds: 25)));
    expect(textStopwatch.elapsed, lessThan(const Duration(milliseconds: 25)));
  });
}
