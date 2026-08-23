import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_cockpit/src/runtime/cockpit_semantics_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'resolves the matching semantics node through the SemanticsOwner tree',
    (tester) async {
      var confirmCount = 0;
      var cancelCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  ElevatedButton(
                    key: const ValueKey<String>('cancel-button'),
                    onPressed: () => cancelCount += 1,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 24),
                  ElevatedButton(
                    key: const ValueKey<String>('confirm-button'),
                    onPressed: () => confirmCount += 1,
                    child: const Text('Confirm'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final element = tester.element(
        find.byKey(const ValueKey<String>('confirm-button')),
      );
      final node = cockpitResolveSemanticsNodeFromOwnerTree(element);
      final directInfo = cockpitResolveSemanticsTargetInfo(element);
      final ownerTreeInfo = cockpitResolveSemanticsTargetInfoFromOwnerTree(
        element,
      );

      expect(node, isNotNull);
      expect(directInfo?.inheritedFromAncestor, isFalse);
      expect(ownerTreeInfo?.inheritedFromAncestor, isFalse);
      final data = node!.getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.label, contains('Confirm'));

      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pump();

      expect(confirmCount, 1);
      expect(cancelCount, 0);
    },
  );

  testWidgets('marks merged ancestor semantics as inherited', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MergeSemantics(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const <Widget>[
                  SizedBox(
                    width: 200,
                    height: 40,
                    child: Text('Primary action'),
                  ),
                  SizedBox(
                    width: 200,
                    height: 40,
                    child: Text('Passive status'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final passiveElement = tester.element(find.text('Passive status'));
    final directInfo = cockpitResolveSemanticsTargetInfo(passiveElement);
    final ownerTreeInfo = cockpitResolveSemanticsTargetInfoFromOwnerTree(
      passiveElement,
    );

    expect(directInfo, isNotNull);
    expect(directInfo?.inheritedFromAncestor, isTrue);
    expect(ownerTreeInfo, isNotNull);
    expect(ownerTreeInfo?.inheritedFromAncestor, isTrue);
  });

  testWidgets(
    'returns null when the semantics tree is unavailable',
    semanticsEnabled: false,
    (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox.expand(),
        ),
      );
      await tester.pump();

      final element = tester.element(find.byType(SizedBox));

      expect(cockpitResolveSemanticsNodeFromOwnerTree(element), isNull);
    },
  );
}
