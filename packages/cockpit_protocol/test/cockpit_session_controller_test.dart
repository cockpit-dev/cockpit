import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('recording into a closed session throws the dedicated error', () {
    final controller = CockpitSessionController(
      sessionId: 'session-1',
      taskId: 'task-1',
      platform: 'macos',
    );
    controller.finish(
      environment: const CockpitEnvironment(
        platform: 'macos',
        flutterVersion: '3.35.0',
        dartVersion: '3.9.0',
      ),
    );

    expect(
      () => controller.recordStep(
        actionType: 'tap',
        actionArgs: const <String, Object?>{},
      ),
      throwsA(isA<CockpitSessionClosedError>()),
    );
    expect(
      () => controller.importStepRecords(const <CockpitStepRecord>[]),
      throwsA(isA<CockpitSessionClosedError>()),
    );
    expect(
      () => controller.finish(
        environment: const CockpitEnvironment(
          platform: 'macos',
          flutterVersion: '3.35.0',
          dartVersion: '3.9.0',
        ),
      ),
      throwsA(isA<CockpitSessionClosedError>()),
    );
  });

  test(
    'the closed-session error stays compatible with StateError catchers',
    () {
      final controller = CockpitSessionController(
        sessionId: 'session-1',
        taskId: 'task-1',
        platform: 'macos',
      );
      controller.finishWithFailure(
        environment: const CockpitEnvironment(
          platform: 'macos',
          flutterVersion: '3.35.0',
          dartVersion: '3.9.0',
        ),
        failureSummary: 'boom',
      );

      expect(
        () => controller.recordStep(
          actionType: 'tap',
          actionArgs: const <String, Object?>{},
        ),
        throwsA(isA<StateError>()),
      );
    },
  );
}
