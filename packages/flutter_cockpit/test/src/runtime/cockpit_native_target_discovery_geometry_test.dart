// ignore_for_file: deprecated_member_use

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixed-size probe whose discovered target bounds are exactly [width] x
/// [height]: actionable probes own a tap handler (0.5 exposure threshold),
/// passive probes have no commands (strict 0.8 threshold).
class ExposureProbe extends StatelessWidget {
  const ExposureProbe(
    this.label, {
    this.width = 100,
    this.height = 100,
    this.actionable = true,
  });

  final String label;
  final double width;
  final double height;
  final bool actionable;

  @override
  Widget build(BuildContext context) {
    final box = SizedBox(
      width: width,
      height: height,
      child: const ColoredBox(color: Color(0x224488FF)),
    );
    // The key rides the element that becomes the discovered target: the
    // gesture detector for actionable probes, the sized box itself for
    // passive ones.
    return actionable
        ? GestureDetector(
            key: ValueKey<String>(label),
            onTap: () {},
            child: box,
          )
        : SizedBox(
            key: ValueKey<String>(label),
            width: width,
            height: height,
            child: box,
          );
  }
}

void main() {
  Future<List<CockpitTarget>> discover(
    WidgetTester tester,
    String route,
  ) async {
    await tester.pumpAndSettle();
    final targets = const CockpitDiscoveryEngine().discover(
      rootContext: tester.element(find.byType(CockpitSurface)),
      routeName: route,
      includeClippedTargets: true,
    );
    return targets;
  }

  Rect globalBoundsOf(Finder finder, WidgetTester tester) {
    final box = tester.element(finder).findRenderObject() as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  // Mirrors the discovery exposure math using direct `localToGlobal` bounds,
  // serving as the oracle the threaded transform must stay identical to.
  bool predictsExposure(Rect bounds, Rect viewport, {required bool strict}) {
    if (!bounds.overlaps(viewport)) {
      return false;
    }
    final intersection = bounds.intersect(viewport);
    if (intersection.isEmpty) {
      return false;
    }
    return intersection.width / bounds.width >= 0.5 &&
        intersection.height / bounds.height >= (strict ? 0.8 : 0.5);
  }

  CockpitTarget targetFor(List<CockpitTarget> targets, String keyValue) {
    return targets.firstWhere((target) => target.keyValue == keyValue);
  }

  testWidgets('vertical exposure thresholds match direct bounds math', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CockpitSurface(
          routeName: '/geometry',
          child: Material(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // Stack top sits exactly at y = 500 in the 800x600 surface.
                  const SizedBox(height: 500, width: 800),
                  Stack(
                    children: <Widget>[
                      const SizedBox(width: 800, height: 1),
                      // 400..500: fully exposed.
                      const Positioned(
                        left: 0,
                        top: -100,
                        child: ExposureProbe('above-band'),
                      ),
                      // 550..650: exactly 50% of a 100-tall actionable probe.
                      const Positioned(
                        left: 150,
                        top: 50,
                        child: ExposureProbe('edge-50'),
                      ),
                      // 550..675: 50/125 = 40% exposed.
                      const Positioned(
                        left: 300,
                        top: 50,
                        child: ExposureProbe('edge-40', height: 125),
                      ),
                      // 550..625: 50/75 ≈ 66.7% — passes 0.5, fails strict 0.8.
                      const Positioned(
                        left: 450,
                        top: 50,
                        child: ExposureProbe('act-two-thirds', height: 75),
                      ),
                      const Positioned(
                        left: 600,
                        top: 50,
                        child: ExposureProbe(
                          'passive-two-thirds',
                          height: 75,
                          actionable: false,
                        ),
                      ),
                      // 520..620: exactly 80% of a passive probe (>= 0.8).
                      const Positioned(
                        left: 0,
                        top: 20,
                        child: ExposureProbe('passive-80', actionable: false),
                      ),
                      // 521..621: 79% — below the strict 0.8 threshold.
                      const Positioned(
                        left: 150,
                        top: 21,
                        child: ExposureProbe('passive-79', actionable: false),
                      ),
                      // 600..700: only touches the viewport bottom edge.
                      const Positioned(
                        left: 300,
                        top: 100,
                        child: ExposureProbe('below-fold'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final targets = await discover(tester, '/geometry');

    final surface = globalBoundsOf(find.byType(CockpitSurface), tester);
    final viewport = surface.intersect(
      globalBoundsOf(find.byType(SingleChildScrollView), tester),
    );
    // Lock the layout assumptions the razor-edge cases depend on.
    expect(
      globalBoundsOf(find.byKey(const ValueKey<String>('edge-50')), tester),
      const Rect.fromLTWH(150, 550, 100, 100),
    );
    expect(
      globalBoundsOf(
        find.byKey(const ValueKey<String>('passive-80')),
        tester,
      ).top,
      520,
    );

    final expectations = <String, bool>{
      'above-band': true,
      'edge-50': true,
      'edge-40': false,
      'act-two-thirds': true,
      'passive-two-thirds': false,
      'passive-80': true,
      'passive-79': false,
      'below-fold': false,
    };
    for (final entry in expectations.entries) {
      final target = targetFor(targets, entry.key);
      // The oracle must agree with the locked expectation, then discovery
      // must agree with both — a bound off by 1ulp at the >= thresholds
      // flips these flags.
      final bounds = globalBoundsOf(
        find.byKey(ValueKey<String>(entry.key)),
        tester,
      );
      final actionable = !entry.key.startsWith('passive-');
      expect(
        predictsExposure(bounds, viewport, strict: !actionable),
        entry.value,
        reason: '${entry.key} oracle disagreed with the locked expectation',
      );
      expect(
        target.isVisible,
        entry.value,
        reason: '${entry.key} discovery visibility diverged',
      );
    }
  });

  testWidgets('horizontal width clipping matches direct bounds math', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CockpitSurface(
          routeName: '/geometry-h',
          child: Material(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 200,
                  height: 100,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: const <Widget>[
                      ExposureProbe('h-full', width: 150),
                    ],
                  ),
                ),
                SizedBox(
                  width: 200,
                  height: 100,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: const <Widget>[
                      // Exactly 200/400 = 50% width exposed (>= 0.5).
                      ExposureProbe('h-half', width: 400),
                    ],
                  ),
                ),
                SizedBox(
                  width: 200,
                  height: 100,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: const <Widget>[
                      ExposureProbe('h-quarter', width: 800),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final targets = await discover(tester, '/geometry-h');

    final surface = globalBoundsOf(find.byType(CockpitSurface), tester);
    final viewports = find
        .byType(ListView)
        .evaluate()
        .map(
          (element) => surface.intersect(
            (element.findRenderObject() as RenderBox).localToGlobal(
                  Offset.zero,
                ) &
                (element.findRenderObject() as RenderBox).size,
          ),
        )
        .toList(growable: false);

    final expectations = <String, (int, bool)>{
      'h-full': (0, true),
      'h-half': (1, true),
      'h-quarter': (2, false),
    };
    for (final entry in expectations.entries) {
      final bounds = globalBoundsOf(
        find.byKey(ValueKey<String>(entry.key)),
        tester,
      );
      final predicted = predictsExposure(
        bounds,
        viewports[entry.value.$1],
        strict: false,
      );
      expect(predicted, entry.value.$2, reason: '${entry.key} oracle');
      expect(
        targetFor(targets, entry.key).isVisible,
        entry.value.$2,
        reason: '${entry.key} discovery visibility diverged',
      );
    }
  });

  testWidgets('transformed subtrees keep direct localToGlobal outcomes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CockpitSurface(
          routeName: '/geometry-t',
          child: Material(
            child: Stack(
              children: <Widget>[
                const SizedBox(width: 800, height: 600),
                // Rotated 100x100 centered at (750, 170): the 45-degree
                // matrix maps the origin to x = 750 exactly
                // (50*cos - 50*sin == 0), leaving width exposure 50/100.
                Positioned(
                  left: 700,
                  top: 120,
                  child: Transform.rotate(
                    angle: pi / 4,
                    child: const ExposureProbe('rot'),
                  ),
                ),
                // Same width razor as 'rot' but the origin sits at
                // y = 545: height exposure is 0.55, which passes the normal
                // 0.5 threshold and fails the passive 0.8 one.
                Positioned(
                  left: 700,
                  top: 565.71067811865475,
                  child: Transform.rotate(
                    angle: pi / 4,
                    child: const ExposureProbe(
                      'rot-passive',
                      actionable: false,
                    ),
                  ),
                ),
                // Scaled 2x about its center at (825, 325): origin lands on
                // x = 775, so the 50-wide probe is exactly half exposed.
                Positioned(
                  left: 800,
                  top: 300,
                  child: Transform.scale(
                    scale: 2,
                    child: const ExposureProbe('scale-edge', width: 50),
                  ),
                ),
                const Positioned(
                  left: 100,
                  top: 480,
                  child: FractionalTranslation(
                    translation: Offset(0.5, 0.5),
                    child: ExposureProbe('fractional'),
                  ),
                ),
                const Positioned(
                  left: 300,
                  top: 480,
                  child: FractionalTranslation(
                    translation: Offset(0.5, 0.5),
                    child: ExposureProbe(
                      'fractional-passive',
                      actionable: false,
                    ),
                  ),
                ),
                const Positioned(
                  left: 20,
                  top: 500,
                  child: Opacity(opacity: 0.5, child: ExposureProbe('faded')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final targets = await discover(tester, '/geometry-t');

    final viewport = globalBoundsOf(find.byType(CockpitSurface), tester);
    // Every probe's discovered visibility must equal the prediction from
    // direct `localToGlobal` bounds through the same transform edges
    // (rotation, scale, fractional translation, opacity proxy).
    final expectations = <String, bool>{
      'rot': true,
      'rot-passive': false,
      'scale-edge': true,
      'fractional': true,
      'fractional-passive': false,
      'faded': true,
    };
    for (final entry in expectations.entries) {
      final bounds = globalBoundsOf(
        find.byKey(ValueKey<String>(entry.key)),
        tester,
      );
      final strict = entry.key.contains('passive');
      expect(
        predictsExposure(bounds, viewport, strict: strict),
        entry.value,
        reason: '${entry.key} oracle disagreed with the locked expectation',
      );
      expect(
        targetFor(targets, entry.key).isVisible,
        entry.value,
        reason: '${entry.key} discovery visibility diverged',
      );
    }
  });

  testWidgets('zero-size boxes never surface as targets', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CockpitSurface(
          routeName: '/geometry-zero',
          child: const Material(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ExposureProbe('zero', width: 0, height: 0),
                ExposureProbe('zero-width', width: 0),
                ExposureProbe('zero-neighbor'),
              ],
            ),
          ),
        ),
      ),
    );
    final targets = await discover(tester, '/geometry-zero');

    expect(targets.where((target) => target.keyValue == 'zero'), isEmpty);
    expect(targets.where((target) => target.keyValue == 'zero-width'), isEmpty);
    final neighbor = targetFor(targets, 'zero-neighbor');
    expect(neighbor.isVisible, isTrue);
  });

  testWidgets('viewport geometry stays linear on a render-deep tree', (
    tester,
  ) async {
    // Nested Padding/ColoredBox wrappers grow the RENDER depth one box per
    // wrapper, so every element's bounds sit ~3 boxes per level deeper than
    // its parent. A per-element `localToGlobal` root walk then costs
    // O(elements x depth): this ~29k-element / ~4.2k-render-deep tree
    // measured 2742ms per discovery pass before threaded transforms and
    // ~83ms after. The 300ms guard keeps ~3.6x margin for slower CI
    // hardware while still failing the un-threaded implementation by 9x.
    const spineDepth = 600;

    Widget renderWrappers(int remaining, Widget child) => remaining == 0
        ? child
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: ColoredBox(
              color: const Color(0x01000000),
              child: renderWrappers(remaining - 1, child),
            ),
          );

    Widget buildLevel(int remaining) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('leaf-$remaining'),
          FilledButton(
            onPressed: () {},
            child: const SizedBox(width: 24, height: 24),
          ),
          if (remaining > 0) renderWrappers(3, buildLevel(remaining - 1)),
        ],
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: CockpitSurface(
          routeName: '/geometry-scale',
          child: Material(
            child: SingleChildScrollView(child: buildLevel(spineDepth - 1)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rootContext = tester.element(find.byType(CockpitSurface));
    final engine = const CockpitDiscoveryEngine();
    // Verify the tree is real with an unclipped pass, then warm up the JIT
    // so the guard measures steady state on the clipped wheel path.
    final unclipped = engine.discover(
      rootContext: rootContext,
      routeName: '/geometry-scale',
      includeClippedTargets: true,
    );
    expect(
      unclipped.where((target) => target.typeName == 'RichText'),
      hasLength(spineDepth),
    );
    expect(
      unclipped.where((target) => target.typeName == 'FilledButton'),
      hasLength(spineDepth),
    );
    engine.discover(rootContext: rootContext, routeName: '/geometry-scale');

    final stopwatch = Stopwatch()..start();
    final targets = engine.discover(
      rootContext: rootContext,
      routeName: '/geometry-scale',
    );
    stopwatch.stop();
    expect(targets, isNotEmpty);
    expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 300)));
  });
}
