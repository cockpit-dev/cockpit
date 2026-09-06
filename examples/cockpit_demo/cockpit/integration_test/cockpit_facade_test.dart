import 'package:flutter_cockpit_test/flutter_cockpit_test.dart';
import 'package:cockpit_demo/src/data/cockpit_demo_database.dart';
import 'package:cockpit_demo/src/data/todo_repository.dart';
import 'package:cockpit_demo/src/model/todo_filter.dart';
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

  late CockpitDemoDatabase reorderDatabase;
  cockpitTestWidgets(
    'uses target-to-target drag for manual queue reorder',
    app: () {
      reorderDatabase = CockpitDemoDatabase.inMemory();
      addTearDown(reorderDatabase.close);
      return buildCockpitDemoApp(database: reorderDatabase);
    },
    body: (cockpit) async {
      final repository = TodoRepository(reorderDatabase);
      await repository.createTask(title: 'Queue first');
      await repository.createTask(title: 'Queue second');
      await repository.createTask(title: 'Queue third');
      await cockpit.waitForUi();
      await cockpit.scroll('Manual queue', align: 'center');

      final result = await cockpit.dragTo(
        from: 'Reorder task Queue third',
        to: 'Reorder task Queue first',
        placement: 'before',
      );
      expect(
        result.result.success,
        isTrue,
        reason: result.result.error?.message,
      );
      await cockpit.waitForUi();

      final reordered = await repository.fetchTasks(const TodoFilter.inbox());
      expect(
        reordered.map((task) => task.title).toList(growable: false),
        <String>['Queue third', 'Queue first', 'Queue second'],
      );
    },
  );
}
