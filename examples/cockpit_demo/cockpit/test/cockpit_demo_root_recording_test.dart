import 'dart:io';

import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:cockpit_demo/src/data/cockpit_demo_database.dart';

import 'support/cockpit_demo_test_support.dart';

void main() {
  testWidgets('records a root-level Todo acceptance video', (tester) async {
    final outputDirectory = Directory.systemTemp.createTempSync(
      'cockpit_demo_recording_test',
    );
    addTearDown(() => deleteDirectory(outputDirectory));

    final tempRecording = File(p.join(outputDirectory.path, 'recording.mp4'));
    tempRecording.parent.createSync(recursive: true);
    tempRecording.writeAsBytesSync(validMp4Bytes);

    final controller = buildTestController(
      sessionId: 'root-recording-session',
      taskId: 'root-recording-task',
      platform: 'android',
    );
    final database = CockpitDemoDatabase.inMemory();
    addCockpitDemoDatabaseTearDown(tester, database);

    await pumpTodoApp(
      tester,
      controller: controller,
      database: database,
      configuration: FlutterCockpitConfiguration(
        initialRouteName: '/inbox',
        nativeRecording: FakeCockpitNativeRecording(
          sourceFilePath: tempRecording.path,
        ),
      ),
    );

    final rootState = tester.state<FlutterCockpitRootState>(
      find.byType(FlutterCockpitRoot),
    );

    final session = await tester.runAsync(() {
      return rootState.startRecording(
        const CockpitRecordingRequest(
          purpose: CockpitRecordingPurpose.acceptance,
          name: 'todo_acceptance',
          attachToStep: true,
        ),
      );
    });
    expect(session, isNotNull);

    await createTaskThroughUi(
      tester,
      title: 'Record Todo acceptance',
      notes: 'Persist the finished recording into the bundle',
      priorityLabel: 'URGENT',
      dueLabel: 'Tomorrow',
    );

    final result = await tester.runAsync(rootState.stopRecording);

    expect(find.text('Record Todo acceptance'), findsWidgets);
    expect(result!.state, CockpitRecordingState.completed);
    expect(result.durationMs, 2600);
    expect(File(result.sourceFilePath!).readAsBytesSync(), validMp4Bytes);
    expect(result.artifact!.relativePath, 'recordings/todo_acceptance.mp4');
  });
}
