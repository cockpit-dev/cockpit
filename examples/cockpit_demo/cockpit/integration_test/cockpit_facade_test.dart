import 'package:flutter_cockpit_test/flutter_cockpit_test.dart';
import 'package:cockpit_demo/src/data/cockpit_demo_database.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/cockpit_demo_test_support.dart';

void main() {
  cockpitTestWidgets(
    'uses Cockpit selectors from a Dart integration test',
    app: () {
      final database = CockpitDemoDatabase.inMemory();
      addTearDown(database.close);
      return buildCockpitDemoApp(database: database);
    },
    body: (cockpit) async {
      await cockpit.expectVisible('New task');
      await cockpit.tap('New task');
      await cockpit.expectVisible('Task title');
    },
  );
}
