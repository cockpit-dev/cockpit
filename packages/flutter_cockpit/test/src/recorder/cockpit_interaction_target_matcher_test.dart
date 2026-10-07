import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cockpit/src/recorder/cockpit_interaction_target_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('locatorCandidates', () {
    test('orders key, semanticId, text, tooltip, then type', () {
      const target = CockpitTarget(
        registrationId: 'zone',
        routeName: '/',
        keyValue: 'save-button',
        semanticId: 'save',
        text: 'Save',
        tooltip: 'Saves the form',
        typeName: 'CustomZone',
      );

      final candidates = CockpitInteractionTargetMatcher.locatorCandidates(
        target,
      );

      expect(candidates.map((candidate) => candidate.kind), <String>[
        'key',
        'semanticId',
        'text',
        'tooltip',
        'type',
      ]);
      expect(candidates.map((candidate) => candidate.score), const <int>[
        4,
        3,
        2,
        1,
        0,
      ]);
      expect(
        candidates.map((candidate) => candidate.selector),
        equals(<String>[
          CockpitSelector.format(const CockpitLocator(key: 'save-button')),
          CockpitSelector.format(const CockpitLocator(semanticId: 'save')),
          CockpitSelector.format(const CockpitLocator(text: 'Save')),
          CockpitSelector.format(
            const CockpitLocator(tooltip: 'Saves the form'),
          ),
          CockpitSelector.format(const CockpitLocator(type: 'CustomZone')),
        ]),
      );
    });

    test('skips blank signals and yields nothing without any signal', () {
      const blank = CockpitTarget(
        registrationId: 'blank',
        routeName: '/',
        keyValue: '  ',
        semanticId: '',
        text: ' \t ',
      );
      const silent = CockpitTarget(registrationId: 'silent', routeName: '/');

      expect(CockpitInteractionTargetMatcher.locatorCandidates(blank), isEmpty);
      expect(
        CockpitInteractionTargetMatcher.locatorCandidates(silent),
        isEmpty,
      );
    });
  });

  group('matchHitPath', () {
    testWidgets('signal strength beats depth', (tester) async {
      // A keyed ancestor and a deeper plain-text target both participate in
      // the hit path; the key signal must win even though the text target
      // sits deeper.
      final registry = CockpitTargetRegistry();
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            key: const Key('keyed-host'),
            child: const Text('deep label'),
          ),
        ),
      );
      final hostElement = tester.element<Element>(
        find.byKey(const Key('keyed-host')),
      );
      registry
        ..register(
          CockpitTarget(
            registrationId: 'keyed',
            routeName: '/',
            keyValue: 'keyed-host',
            diagnosticNodeProvider: () => hostElement,
          ),
        )
        ..register(
          CockpitTarget(
            registrationId: 'labeled',
            routeName: '/',
            text: 'deep label',
            diagnosticNodeProvider: () =>
                tester.element<Element>(find.text('deep label')),
          ),
        );

      final hostRenderObject = hostElement.findRenderObject()!;
      final textRenderObject = tester.renderObject(find.text('deep label'));
      // Hit paths run deepest-first, like the real hit-test result.
      final match = CockpitInteractionTargetMatcher.matchHitPath(registry, [
        textRenderObject,
        hostRenderObject,
      ]);

      expect(match!.keyValue, 'keyed-host');
    });

    testWidgets('a tooltip signal outranks a deeper type-only target', (
      tester,
    ) async {
      final registry = CockpitTargetRegistry();
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(key: Key('tip-host'), child: Text('deep label')),
        ),
      );
      final host = tester.element<Element>(find.byKey(const Key('tip-host')));
      registry
        ..register(
          CockpitTarget(
            registrationId: 'tipped',
            routeName: '/',
            tooltip: 'Opens menu',
            diagnosticNodeProvider: () => host,
          ),
        )
        ..register(
          CockpitTarget(
            registrationId: 'typed',
            routeName: '/',
            typeName: 'Text',
            diagnosticNodeProvider: () =>
                tester.element<Element>(find.text('deep label')),
          ),
        );

      final match = CockpitInteractionTargetMatcher.matchHitPath(registry, [
        tester.renderObject(find.text('deep label')),
        host.findRenderObject()!,
      ]);

      // The shallower tooltip target (score 1) beats the deeper type-only
      // target (score 0) on signal strength alone.
      expect(match!.registrationId, 'tipped');
    });

    testWidgets('equal signals resolve to the deepest participant', (
      tester,
    ) async {
      final registry = CockpitTargetRegistry();
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(key: Key('outer'), child: Text('leaf')),
        ),
      );
      final outer = tester.element<Element>(find.byKey(const Key('outer')));
      final leaf = tester.element<Element>(find.text('leaf'));
      registry
        ..register(
          CockpitTarget(
            registrationId: 'outer',
            routeName: '/',
            text: 'same',
            diagnosticNodeProvider: () => outer,
          ),
        )
        ..register(
          CockpitTarget(
            registrationId: 'leaf',
            routeName: '/',
            text: 'same',
            diagnosticNodeProvider: () => leaf,
          ),
        );

      final match = CockpitInteractionTargetMatcher.matchHitPath(registry, [
        leaf.findRenderObject()!,
        outer.findRenderObject()!,
      ]);

      // Deeper in the hit path (smaller index) wins the tie.
      expect(match!.registrationId, 'leaf');
    });

    testWidgets('skips unmounted elements and returns null without a match', (
      tester,
    ) async {
      final registry = CockpitTargetRegistry();
      late StateSetter setState;
      var mounted = true;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, update) {
              setState = update;
              return Center(
                key: const Key('gone'),
                child: mounted ? const Text('vanishing') : const SizedBox(),
              );
            },
          ),
        ),
      );
      final vanishing = tester.element<Element>(find.text('vanishing'));
      registry.register(
        CockpitTarget(
          registrationId: 'vanishing',
          routeName: '/',
          keyValue: 'gone',
          diagnosticNodeProvider: () => vanishing,
        ),
      );

      setState(() => mounted = false);
      await tester.pumpAndSettle();

      final stillThere = tester.renderObject(find.byKey(const Key('gone')));
      expect(
        CockpitInteractionTargetMatcher.matchHitPath(registry, [stillThere]),
        isNull,
      );
      expect(
        CockpitInteractionTargetMatcher.matchHitPath(registry, const []),
        isNull,
      );
    });
  });

  group('matchElementAncestry', () {
    testWidgets('prefers the element itself over its ancestors', (
      tester,
    ) async {
      final registry = CockpitTargetRegistry();
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(key: Key('field-host'), child: Text('field')),
        ),
      );
      final host = tester.element<Element>(find.byKey(const Key('field-host')));
      final field = tester.element<Element>(find.text('field'));
      registry
        ..register(
          CockpitTarget(
            registrationId: 'host',
            routeName: '/',
            semanticId: 'host-scope',
            diagnosticNodeProvider: () => host,
          ),
        )
        ..register(
          CockpitTarget(
            registrationId: 'field',
            routeName: '/',
            semanticId: 'field-scope',
            diagnosticNodeProvider: () => field,
          ),
        );

      expect(
        CockpitInteractionTargetMatcher.matchElementAncestry(
          registry,
          field,
        )!.registrationId,
        'field',
      );
      // Ancestry only walks upward: the field is a descendant of the host,
      // so matching from the host sees the host itself, never the field.
      expect(
        CockpitInteractionTargetMatcher.matchElementAncestry(
          registry,
          host,
        )!.registrationId,
        'host',
      );
    });

    testWidgets('returns null for unrelated elements', (tester) async {
      final registry = CockpitTargetRegistry();
      await tester.pumpWidget(
        const MaterialApp(
          home: Column(
            children: <Widget>[
              Center(key: Key('tracked'), child: Text('tracked')),
              Center(key: Key('other'), child: Text('other')),
            ],
          ),
        ),
      );
      registry.register(
        CockpitTarget(
          registrationId: 'tracked',
          routeName: '/',
          keyValue: 'tracked',
          diagnosticNodeProvider: () =>
              tester.element<Element>(find.byKey(const Key('tracked'))),
        ),
      );

      expect(
        CockpitInteractionTargetMatcher.matchElementAncestry(
          registry,
          tester.element<Element>(find.byKey(const Key('other'))),
        ),
        isNull,
      );
    });
  });
}
