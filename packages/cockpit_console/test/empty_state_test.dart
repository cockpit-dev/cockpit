import 'package:cockpit_console/src/ui/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('empty state remains bounded in a short vertical slot', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          height: 55,
          child: EmptyStateView(
            icon: Icons.play_circle_outline,
            title: 'No active run',
            description:
                'Select a document and case, then submit to start watching the event stream.',
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('No active run'), findsOneWidget);
  });
}
