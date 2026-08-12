import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'live and baseline profiles expose different diagnostic density',
    (tester) async {
      final rootKey = GlobalKey<CockpitSurfaceState>();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: CockpitSurface(
            key: rootKey,
            routeName: '/diagnostics',
            child: Center(
              child: CockpitTargetNode(
                registrationId: 'diagnostics.submit',
                cockpitId: 'submit_button',
                text: 'Submit order',
                typeName: 'DecoratedBox',
                supportedCommands: const <CockpitCommandType>{
                  CockpitCommandType.tap,
                },
                onTap: () {},
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Submit order',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final live = rootKey.currentState!.snapshot();
      final baseline = rootKey.currentState!.snapshot(
        options: const CockpitSnapshotOptions.baseline(),
      );

      expect(live.diagnosticLevel, CockpitSnapshotProfile.live);
      expect(live.visibleTargets.single.layout, isNull);
      expect(live.visibleTargets.single.style, isNull);
      expect(live.visibleTargets.single.ancestors, isEmpty);

      expect(baseline.diagnosticLevel, CockpitSnapshotProfile.baseline);
      expect(baseline.visibleTargets.single.layout, isNotNull);
      expect(
        baseline.visibleTargets.single.content?.displayLabel,
        'submit_button',
      );
      expect(baseline.visibleTargets.single.ancestors, isNotEmpty);
    },
  );

  testWidgets('deduplicating passive text does not mark snapshots partial', (
    tester,
  ) async {
    final rootKey = GlobalKey<CockpitSurfaceState>();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CockpitSurface(
          key: rootKey,
          routeName: '/deduplication',
          child: const Column(
            children: <Widget>[Text('Repeated'), Text('Repeated')],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final snapshot = rootKey.currentState!.snapshot(
      options: const CockpitSnapshotOptions(
        profile: CockpitSnapshotProfile.baseline,
        maxTargets: 20,
      ),
    );

    expect(snapshot.visibleTargets, hasLength(1));
    expect(snapshot.truncated, isFalse);
  });

  testWidgets('query filters targets before applying the snapshot limit', (
    tester,
  ) async {
    final rootKey = GlobalKey<CockpitSurfaceState>();
    final registry = CockpitTargetRegistry(routeName: '/large');
    for (var index = 0; index < 200; index += 1) {
      registry.register(
        CockpitTarget(
          registrationId: 'large.noise.$index',
          cockpitId: 'noise-$index',
          semanticId: 'semantic-noise-$index',
          keyValue: 'noise-key-$index',
          text: 'Noise $index',
          tooltip: 'Noise tooltip $index',
          routeName: '/large',
          supportedCommands: const <CockpitCommandType>{CockpitCommandType.tap},
        ),
      );
    }
    registry.register(
      const CockpitTarget(
        registrationId: 'large.save',
        keyValue: 'save-key',
        text: 'Save changes',
        typeName: 'FilledButton',
        routeName: '/large',
        supportedCommands: <CockpitCommandType>{CockpitCommandType.tap},
      ),
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CockpitSurface(
          key: rootKey,
          routeName: '/large',
          registry: registry,
          child: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump();

    final snapshot = rootKey.currentState!.snapshot(
      options: const CockpitSnapshotOptions(
        profile: CockpitSnapshotProfile.baseline,
        query: 'SAVE-KEY',
        maxTargets: 1,
      ),
    );

    expect(snapshot.visibleTargets, hasLength(1));
    expect(snapshot.visibleTargets.single.keyValue, 'save-key');
    expect(snapshot.truncated, isFalse);
    expect(snapshot.summary?.visibleTargetCount, 1);
  });

  testWidgets('investigate profile includes bounded diagnostic properties', (
    tester,
  ) async {
    final rootKey = GlobalKey<CockpitSurfaceState>();

    await tester.pumpWidget(
      MaterialApp(
        home: CockpitSurface(
          key: rootKey,
          routeName: '/diagnostics',
          child: Scaffold(
            body: CockpitTargetNode(
              registrationId: 'diagnostics.name_input',
              cockpitId: 'name_input',
              text: 'Name',
              typeName: 'TextField',
              supportedCommands: const <CockpitCommandType>{
                CockpitCommandType.enterText,
              },
              onEnterText: (_) {},
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: TextField(
                  decoration: InputDecoration(labelText: 'Name'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final snapshot = rootKey.currentState!.snapshot(
      options: const CockpitSnapshotOptions.investigate(),
    );
    final target = snapshot.visibleTargets.singleWhere(
      (candidate) => candidate.cockpitId == 'name_input',
    );

    expect(snapshot.diagnosticLevel, CockpitSnapshotProfile.investigate);
    expect(target.layout, isNotNull);
    expect(target.diagnosticProperties, isNotEmpty);
    expect(target.diagnosticProperties.length, lessThanOrEqualTo(12));
  });

  testWidgets(
    'investigate profile extracts normalized widget-specific diagnostics',
    (tester) async {
      final rootKey = GlobalKey<CockpitSurfaceState>();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: CockpitSurface(
            key: rootKey,
            routeName: '/diagnostics',
            child: Column(
              children: <Widget>[
                CockpitTargetNode(
                  registrationId: 'diagnostics.padded_box',
                  cockpitId: 'padded_box',
                  text: 'Padded box',
                  typeName: 'Padding',
                  child: const Padding(
                    padding: EdgeInsets.only(
                      top: 8,
                      right: 12,
                      bottom: 16,
                      left: 20,
                    ),
                    child: Text('Padded box'),
                  ),
                ),
                CockpitTargetNode(
                  registrationId: 'diagnostics.aligned_box',
                  cockpitId: 'aligned_box',
                  text: 'Aligned box',
                  typeName: 'Align',
                  child: const Align(
                    alignment: Alignment.topRight,
                    child: SizedBox(width: 24, height: 12),
                  ),
                ),
                CockpitTargetNode(
                  registrationId: 'diagnostics.decorated_box',
                  cockpitId: 'decorated_box',
                  text: 'Decorated box',
                  typeName: 'DecoratedBox',
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      border: Border.all(color: Colors.red, width: 2),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 6,
                          offset: Offset(1, 2),
                        ),
                      ],
                    ),
                    child: const SizedBox(width: 24, height: 24),
                  ),
                ),
                CockpitTargetNode(
                  registrationId: 'diagnostics.faded_icon',
                  cockpitId: 'faded_icon',
                  typeName: 'Opacity',
                  child: const Opacity(
                    opacity: 0.72,
                    child: Icon(Icons.add, size: 18, color: Colors.green),
                  ),
                ),
                GestureDetector(
                  key: const ValueKey<String>('tight-box-target'),
                  onTap: null,
                  child: const SizedBox(
                    width: 120,
                    height: 48,
                    child: ColoredBox(color: Colors.indigo),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final snapshot = rootKey.currentState!.snapshot(
        options: const CockpitSnapshotOptions.investigate(),
      );
      final paddedTarget = snapshot.visibleTargets.firstWhere(
        (target) => target.cockpitId == 'padded_box',
      );
      final alignedTarget = snapshot.visibleTargets.firstWhere(
        (target) => target.cockpitId == 'aligned_box',
      );
      final decoratedTarget = snapshot.visibleTargets.firstWhere(
        (target) => target.cockpitId == 'decorated_box',
      );
      final fadedIconTarget = snapshot.visibleTargets.firstWhere(
        (target) => target.cockpitId == 'faded_icon',
      );
      final tightBoxTarget = snapshot.visibleTargets.firstWhere(
        (target) => target.keyValue == 'tight-box-target',
      );

      expect(_propertyValue(paddedTarget, 'Padding Top'), equals('8.0px'));
      expect(
        _propertyCategory(paddedTarget, 'Padding Top'),
        CockpitDiagnosticCategory.spacing,
      );
      expect(
        _propertyValue(alignedTarget, 'Alignment'),
        equals('x:1.00, y:-1.00'),
      );
      expect(
        _propertyCategory(alignedTarget, 'Alignment'),
        CockpitDiagnosticCategory.layout,
      );
      expect(
        _propertyValue(decoratedTarget, 'Background Color'),
        startsWith('#'),
      );
      expect(
        _propertyValue(decoratedTarget, 'Border Radius'),
        equals('TL:10 TR:10 BR:10 BL:10'),
      );
      expect(_propertyValue(fadedIconTarget, 'Opacity'), equals('0.72'));
      expect(_propertyValue(fadedIconTarget, 'Icon Size'), equals('18px'));
      expect(_propertyValue(fadedIconTarget, 'Icon Color'), startsWith('#'));
      expect(_propertyValue(tightBoxTarget, 'Min Width'), isNotNull);
      expect(_propertyValue(tightBoxTarget, 'Max Width'), isNotNull);
      expect(_propertyValue(tightBoxTarget, 'Min Height'), isNotNull);
      expect(_propertyValue(tightBoxTarget, 'Max Height'), isNotNull);
      expect(_propertyValue(tightBoxTarget, 'Is Tight'), isNotNull);
      expect(
        _propertyCategory(tightBoxTarget, 'Min Width'),
        CockpitDiagnosticCategory.layout,
      );
    },
  );

  testWidgets(
    'investigate profile extracts normalized typography diagnostics',
    (tester) async {
      final rootKey = GlobalKey<CockpitSurfaceState>();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: CockpitSurface(
            key: rootKey,
            routeName: '/diagnostics',
            child: Column(
              children: <Widget>[
                CockpitTargetNode(
                  registrationId: 'diagnostics.styled_text',
                  cockpitId: 'styled_text',
                  text: 'Styled text',
                  typeName: 'Text',
                  child: const Text(
                    'Styled text',
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      height: 1.4,
                      color: Colors.purple,
                    ),
                  ),
                ),
                CockpitTargetNode(
                  registrationId: 'diagnostics.rich_text',
                  cockpitId: 'rich_text',
                  typeName: 'RichText',
                  child: RichText(
                    text: const TextSpan(
                      text: 'Rich text',
                      style: TextStyle(
                        fontSize: 15,
                        letterSpacing: 0.5,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final snapshot = rootKey.currentState!.snapshot(
        options: const CockpitSnapshotOptions.investigate(),
      );
      final styledTextTarget = snapshot.visibleTargets.firstWhere(
        (target) => target.cockpitId == 'styled_text',
      );
      final richTextTarget = snapshot.visibleTargets.firstWhere(
        (target) => target.cockpitId == 'rich_text',
      );

      expect(_propertyValue(styledTextTarget, 'Font Family'), equals('Roboto'));
      expect(_propertyValue(styledTextTarget, 'Font Size'), equals('17.0px'));
      expect(
        _propertyCategory(styledTextTarget, 'Font Size'),
        CockpitDiagnosticCategory.typography,
      );
      expect(_propertyValue(styledTextTarget, 'Font Weight'), equals('w700'));
      expect(
        _propertyValue(styledTextTarget, 'Letter Spacing'),
        equals('1.5px'),
      );
      expect(_propertyValue(styledTextTarget, 'Line Height'), equals('1.40'));
      expect(_propertyValue(styledTextTarget, 'Text Color'), startsWith('#'));

      expect(_propertyValue(richTextTarget, 'Font Size'), equals('15.0px'));
      expect(_propertyValue(richTextTarget, 'Letter Spacing'), equals('0.5px'));
      expect(_propertyValue(richTextTarget, 'Text Color'), startsWith('#'));
    },
  );

  testWidgets('investigate profile filters noisy ancestors from summaries', (
    tester,
  ) async {
    final rootKey = GlobalKey<CockpitSurfaceState>();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CockpitSurface(
          key: rootKey,
          routeName: '/diagnostics',
          child: _PrivateDiagnosticWrapper(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                label: 'Meaningful content',
                child: Listener(
                  onPointerDown: (_) {},
                  child: GestureDetector(
                    key: const ValueKey<String>('cleaned-ancestors-target'),
                    onTap: () {},
                    child: IgnorePointer(
                      ignoring: false,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        color: Colors.blueGrey,
                        child: const Text('Meaningful content'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final snapshot = rootKey.currentState!.snapshot(
      options: const CockpitSnapshotOptions.investigate(),
    );
    final target = snapshot.visibleTargets.firstWhere(
      (candidate) => candidate.keyValue == 'cleaned-ancestors-target',
    );
    final ancestorTypes = target.ancestors.map((ancestor) => ancestor.typeName);

    expect(ancestorTypes, contains('Align'));
    expect(ancestorTypes.any((typeName) => typeName.startsWith('_')), isFalse);
    expect(
      ancestorTypes.any((typeName) => typeName.contains('Semantics')),
      isFalse,
    );
    expect(
      ancestorTypes.any((typeName) => typeName.contains('Listener')),
      isFalse,
    );
    expect(
      ancestorTypes.any((typeName) => typeName.contains('GestureDetector')),
      isFalse,
    );
    expect(
      ancestorTypes.any((typeName) => typeName.contains('IgnorePointer')),
      isFalse,
    );
  });

  testWidgets(
    'investigate profile can expose bounded accessibility summaries',
    (tester) async {
      final rootKey = GlobalKey<CockpitSurfaceState>();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: CockpitSurface(
            key: rootKey,
            routeName: '/a11y',
            child: Column(
              children: <Widget>[
                CockpitTargetNode(
                  registrationId: 'a11y.primary',
                  cockpitId: 'primary-action',
                  child: Semantics(
                    label: 'Primary action',
                    child: const Text('Primary action'),
                  ),
                ),
                CockpitTargetNode(
                  registrationId: 'a11y.secondary',
                  cockpitId: 'secondary-action',
                  child: Semantics(
                    label: 'Secondary action',
                    child: const Text('Secondary action'),
                  ),
                ),
                CockpitTargetNode(
                  registrationId: 'a11y.tertiary',
                  cockpitId: 'tertiary-action',
                  child: Semantics(
                    label: 'Tertiary action',
                    child: const Text('Tertiary action'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final snapshot = rootKey.currentState!.snapshot(
        options: const CockpitSnapshotOptions.investigate().copyWith(
          includeAccessibilitySummary: true,
          maxAccessibilityEntries: 2,
        ),
      );

      expect(snapshot.summary?.accessibilitySummaryIncluded, isTrue);
      expect(snapshot.accessibility, isNotNull);
      expect(snapshot.accessibility!.totalAccessibleTargetCount, 3);
      expect(snapshot.accessibility!.truncated, isTrue);
      expect(snapshot.accessibility!.traversalEntries, hasLength(2));
      expect(
        snapshot.accessibility!.traversalEntries.first.label,
        'Primary action',
      );
      expect(
        snapshot.accessibility!.traversalEntries.last.label,
        'Secondary action',
      );
    },
  );

  testWidgets(
    'accessibility summary filters empty semantics entries before truncation',
    (tester) async {
      final rootKey = GlobalKey<CockpitSurfaceState>();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: CockpitSurface(
            key: rootKey,
            routeName: '/a11y',
            child: Column(
              children: <Widget>[
                CockpitTargetNode(
                  registrationId: 'a11y.empty',
                  cockpitId: 'empty-node',
                  child: Semantics(
                    container: true,
                    child: SizedBox(width: 20, height: 20),
                  ),
                ),
                CockpitTargetNode(
                  registrationId: 'a11y.primary',
                  cockpitId: 'primary-action',
                  child: Semantics(
                    label: 'Primary action',
                    child: const Text('Primary action'),
                  ),
                ),
                CockpitTargetNode(
                  registrationId: 'a11y.hint-only',
                  cockpitId: 'hint-only',
                  child: Semantics(
                    hint: 'Open settings',
                    child: SizedBox(width: 20, height: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final snapshot = rootKey.currentState!.snapshot(
        options: const CockpitSnapshotOptions.investigate().copyWith(
          includeAccessibilitySummary: true,
          maxAccessibilityEntries: 2,
        ),
      );

      expect(snapshot.accessibility, isNotNull);
      expect(snapshot.accessibility!.totalAccessibleTargetCount, 2);
      expect(snapshot.accessibility!.truncated, isFalse);
      expect(snapshot.accessibility!.traversalEntries, hasLength(2));
      expect(
        snapshot.accessibility!.traversalEntries.first.label,
        'Primary action',
      );
      expect(snapshot.accessibility!.traversalEntries.last.label, isNull);
      expect(
        snapshot.accessibility!.traversalEntries.last.hint,
        'Open settings',
      );
    },
  );
}

String? _propertyValue(CockpitSnapshotTarget target, String name) {
  return target.diagnosticProperties
      .where((property) => property.name == name)
      .map((property) => property.value)
      .firstOrNull;
}

CockpitDiagnosticCategory? _propertyCategory(
  CockpitSnapshotTarget target,
  String name,
) {
  return target.diagnosticProperties
      .where((property) => property.name == name)
      .map((property) => property.category)
      .firstOrNull;
}

final class _PrivateDiagnosticWrapper extends StatelessWidget {
  const _PrivateDiagnosticWrapper({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
