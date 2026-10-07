import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CockpitRecorderExclusionRegistry', () {
    test('register and unregister are idempotent', () {
      final registry = CockpitRecorderExclusionRegistry();
      final root = RenderProxyBox();

      expect(registry.isEmpty, isTrue);

      registry.register(root);
      registry.register(root);
      expect(registry.isEmpty, isFalse);
      expect(registry.isRegistered(root), isTrue);

      registry.unregister(root);
      registry.unregister(root);
      expect(registry.isEmpty, isTrue);
      expect(registry.isRegistered(root), isFalse);
    });

    test('coversPath is false for an empty path and unregistered nodes', () {
      final registry = CockpitRecorderExclusionRegistry();
      final unrelated = RenderProxyBox();

      expect(registry.coversPath(const <RenderObject>[]), isFalse);
      expect(registry.coversPath(<RenderObject>[unrelated]), isFalse);
    });

    testWidgets('coversPath is true for a registered root itself', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: Text('app')),
        ),
      );
      final registry = CockpitRecorderExclusionRegistry();
      final root = tester.renderObject<RenderObject>(find.text('app'));

      expect(registry.coversPath(<RenderObject>[root]), isFalse);
      registry.register(root);
      expect(registry.coversPath(<RenderObject>[root]), isTrue);
    });

    testWidgets('coversPath is true for descendants of a registered root', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: <Widget>[
              Center(key: Key('registered'), child: Text('registered')),
              Center(key: Key('unrelated'), child: Text('unrelated')),
            ],
          ),
        ),
      );
      final registry = CockpitRecorderExclusionRegistry();
      final registeredRoot = tester.renderObject<RenderObject>(
        find.byKey(const Key('registered')),
      );
      registry.register(registeredRoot);

      // The paragraph is a strict descendant of the registered Center.
      final descendant = tester.renderObject<RenderObject>(
        find.descendant(
          of: find.byKey(const Key('registered')),
          matching: find.text('registered'),
        ),
      );
      final unrelated = tester.renderObject<RenderObject>(
        find.descendant(
          of: find.byKey(const Key('unrelated')),
          matching: find.text('unrelated'),
        ),
      );

      expect(registry.coversPath(<RenderObject>[descendant]), isTrue);
      expect(registry.coversPath(<RenderObject>[unrelated]), isFalse);

      registry.unregister(registeredRoot);
      expect(registry.coversPath(<RenderObject>[descendant]), isFalse);
    });
  });

  group('CockpitRecorderExclude', () {
    testWidgets('installs the marker render object around its child', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: CockpitRecorderExclude(child: Text('excluded content')),
        ),
      );

      final marker = tester.renderObject<RenderObject>(
        find.byType(CockpitRecorderExclude),
      );
      expect(marker, isA<CockpitRecorderExcludeRenderObject>());

      // The child still renders through the proxy box.
      expect(find.text('excluded content'), findsOneWidget);

      // A registry sees a hit path inside the marker as covered.
      final registry = CockpitRecorderExclusionRegistry();
      final child = tester.renderObject<RenderObject>(
        find.text('excluded content'),
      );
      expect(registry.coversPath(<RenderObject>[child]), isTrue);
    });
  });
}
