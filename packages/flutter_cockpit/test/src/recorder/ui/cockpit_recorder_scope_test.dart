import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'panel_helpers.dart';

void main() {
  testWidgets('maybeOf returns null without a scope', (tester) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(CockpitRecorderScope.maybeOf(capturedContext), isNull);
  });

  testWidgets('of throws without a scope', (tester) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(() => CockpitRecorderScope.of(capturedContext), throwsFlutterError);
  });

  testWidgets('maybeOf resolves the nearest scope', (tester) async {
    final controller = newController();
    await tester.pumpWidget(
      MaterialApp(
        home: CockpitRecorderScope(
          controller: controller,
          child: Builder(
            builder: (context) => Text(
              CockpitRecorderScope.of(context).phase.name,
              key: const Key('phase-label'),
            ),
          ),
        ),
      ),
    );

    expect(
      CockpitRecorderScope.maybeOf(
        tester.element(find.byKey(const Key('phase-label'))),
      ),
      controller,
    );
    expect(find.text('idle'), findsOneWidget);
  });

  test('updateShouldNotify only fires for a different controller', () {
    final controller = newController();
    final scope = CockpitRecorderScope(
      controller: controller,
      child: const SizedBox(),
    );

    final sameController = CockpitRecorderScope(
      controller: controller,
      child: const SizedBox(),
    );
    expect(scope.updateShouldNotify(sameController), isFalse);

    final differentController = CockpitRecorderScope(
      controller: newController(),
      child: const SizedBox(),
    );
    expect(scope.updateShouldNotify(differentController), isTrue);
  });
}
