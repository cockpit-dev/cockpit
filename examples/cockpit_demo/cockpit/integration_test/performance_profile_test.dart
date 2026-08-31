import 'package:cockpit_demo/src/data/cockpit_demo_database.dart';
import 'package:cockpit_demo/src/cockpit_demo_app.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cockpit_test/flutter_cockpit_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  cockpitTestWidgets(
    'exports a complete report for a complex task workflow',
    app: () {
      final database = CockpitDemoDatabase.inMemory();
      addTearDown(database.close);
      return CockpitDemoApp(database: database);
    },
    body: (cockpit) async {
      const taskTitle = 'Profile complex task flow';
      const tagName = 'Performance';

      await cockpit.expectVisible('New task');
      final report = await cockpit.profile(
        () async {
          await cockpit.tap('New task');
          await cockpit.waitForRoute('/editor');
          await cockpit.type(taskTitle, into: 'Task title');
          await cockpit.type(
            'Measure a realistic Flutter workflow with navigation, editing, '
            'filtering, scrolling, and gesture-driven layout changes.',
            into: 'Notes',
          );

          await cockpit.scroll('HIGH', align: 'center');
          await cockpit.tap('HIGH');
          await cockpit.scroll('Today', align: 'center');
          await cockpit.tap('Today');

          await cockpit.scroll('Create tag', align: 'center');
          await cockpit.tap('Create tag');
          await cockpit.type(tagName, into: 'Tag name');
          await cockpit.press(CockpitTextInputAction.done, target: 'Tag name');
          await cockpit.scroll('Save task', align: 'center');
          await cockpit.tap('Save task');

          await cockpit.waitForRoute('/inbox');
          await cockpit.expectVisible(taskTitle);
          await cockpit.tap('Dismiss latest update');

          await cockpit.scroll('Planning surface', align: 'center');
          await cockpit.pinch(
            target: '[type="PlanningSurfaceCard"] >> [type="GestureDetector"]',
            scale: 1.2,
          );
          await cockpit.tap('Reset');

          const taskAction = '[type="TaskListItem"] >> [type="InkWell"]';
          await cockpit.scroll(taskAction, align: 'center');
          await cockpit.longPress(taskAction);
          await cockpit.expectVisible('1 selected');
          await cockpit.tap('Priority');
          await cockpit.tap('Urgent priority');
          await cockpit.waitForUi();
        },
        name: 'complex-task-flow',
        streams: const <String>['Dart', 'GC', 'Embedder'],
        timeout: const Duration(minutes: 2),
      );

      expect(report.stepId, 'complex-task-flow');
      expect(report.durationUs, greaterThan(0));
      expect(report.frames, isNotEmpty);
      expect(report.summary.frameCount, report.frames.length);
      if (kIsWeb) {
        expect(report.memory, isNull);
      } else {
        expect(report.memory, isNotNull);
        expect(report.memory!.summary.sampleCount, greaterThan(0));
      }
      if (kIsWeb) {
        expect(report.timelineSource, 'unavailable:web');
      } else if (report.timelineSource == 'vm') {
        expect(report.timelineSource, 'vm');
        expect(report.events, isNotEmpty);
      } else {
        expect(report.timelineSource, 'unavailable:vm');
        expect(report.events, isEmpty);
      }
      expect(report.devTools, isNotNull);
      expect(
        report.devTools!.state,
        anyOf('available', 'unavailable', 'unsupported'),
      );

      final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
      final exported =
          binding.reportData?['cockpit.performance.complex-task-flow'];
      expect(exported, isA<Map<Object?, Object?>>());
      final decoded = CockpitPerformanceReport.fromJson(exported);
      expect(decoded.stepId, 'complex-task-flow');
      expect(decoded.frames, isNotEmpty);
      expect(decoded.summary.frameCount, decoded.frames.length);
      expect(decoded.timelineSource, report.timelineSource);
      expect(decoded.memory, report.memory);
      expect(decoded.devTools!.toJson(), report.devTools!.toJson());
    },
  );
}
