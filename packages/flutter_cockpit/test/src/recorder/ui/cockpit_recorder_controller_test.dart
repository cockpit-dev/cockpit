import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'panel_helpers.dart';

void main() {
  group('delegation and derived state', () {
    test('phase, steps, and segments mirror the engine', () {
      final controller = newController();

      expect(controller.phase, CockpitRecorderPhase.idle);
      expect(controller.canStart, isTrue);
      expect(controller.canPause, isFalse);
      expect(controller.canResume, isFalse);
      expect(controller.canStop, isFalse);
      expect(controller.canDiscardLast, isFalse);
      expect(controller.canVerifyReplay, isFalse);
      expect(controller.session, isNull);

      controller.start();

      expect(controller.phase, CockpitRecorderPhase.recording);
      expect(controller.canStart, isFalse);
      expect(controller.canPause, isTrue);
      expect(controller.canResume, isFalse);
      expect(controller.canStop, isTrue);
      expect(controller.session!.sessionId, 'r1');

      controller.beginSegment('setup');
      expect(controller.openSegments, <String>['setup']);

      controller.pause();
      expect(controller.canResume, isTrue);
      expect(controller.canPause, isFalse);

      controller.resume();
      controller.recorder.recordInteractionStep(_tapStep('s1'));
      expect(controller.steps, hasLength(1));
      expect(controller.canDiscardLast, isTrue);
      expect(controller.canVerifyReplay, isTrue);

      controller.endSegment();
      expect(controller.openSegments, isEmpty);

      controller.stop();
      expect(controller.canStart, isTrue);
      expect(controller.canStop, isFalse);
    });

    test('relays engine notifications', () {
      final controller = newController();
      var notifications = 0;
      controller.addListener(() => notifications += 1);

      controller.recorder.start();
      expect(notifications, greaterThan(0));
    });

    test('verifyReplay needs an actionable step', () {
      final controller = newController();
      controller.start();
      controller.recorder.recordInteractionStep(
        unresolvedStep(CockpitInteractionStepKind.tap),
      );
      expect(controller.canVerifyReplay, isFalse);
    });
  });

  group('error surfacing', () {
    test('captures StateError and clears it on demand', () {
      final controller = newController();

      controller.pause();

      expect(controller.lastError, contains('Cannot pause'));
      expect(controller.lastError, contains('idle'));

      controller.clearError();
      expect(controller.lastError, isNull);
    });

    test('a successful command clears a previous error', () {
      final controller = newController();
      controller.pause();
      expect(controller.lastError, isNotNull);

      controller.start();
      expect(controller.lastError, isNull);
    });

    test('export failures surface instead of throwing', () {
      final controller = newController();
      controller.start();

      // No exportable step: the converter throws ArgumentError.
      controller.exportBundle();

      expect(controller.lastError, isNotNull);
      expect(controller.lastBundle, isNull);
    });
  });

  group('results storage', () {
    test('export stores the bundle and re-export replaces it', () {
      final controller = newController();
      controller.start();
      controller.recorder.recordInteractionStep(_tapStep('s1'));

      controller.exportBundle();

      expect(controller.lastBundle, isNotNull);
      expect(controller.lastBundle!.caseDocument['id'], 'recorded-r1');

      controller.recorder.recordInteractionStep(_tapStep('s2'));
      controller.exportBundle();
      expect(controller.lastBundle!.steps, hasLength(2));
    });

    test('verifyReplay stores the reports', () async {
      final controller = newController(recorder: replayableRecorder());
      controller.start();
      controller.recorder.recordInteractionStep(_tapStep('s1'));
      controller.recorder.recordInteractionStep(
        stepWithCandidates(
          CockpitInteractionStepKind.tap,
          <CockpitLocatorCandidate>[keyCandidate('vanished')],
        ),
      );

      await controller.verifyReplay();

      expect(controller.replayReports, hasLength(2));
      expect(
        controller.replayReports!.map((report) => report.status.name),
        <String>['passed', 'deviated'],
      );
      expect(controller.isReplaying, isFalse);
    });

    test('verifyReplay failures surface', () async {
      final controller = newController();
      controller.start();
      controller.recorder.recordInteractionStep(_tapStep('s1'));

      // No registry wired on this engine.
      await controller.verifyReplay();

      expect(controller.lastError, contains('no target registry'));
      expect(controller.replayReports, isNull);
    });

    test('saveBundle persists through the gateway', () async {
      final gateway = RecordingGateway()..result = '/tmp/recorded-r1.yaml';
      final controller = newController(gateway: gateway);
      controller.start();
      controller.recorder.recordInteractionStep(_tapStep('s1'));
      controller.exportBundle();

      await controller.saveBundle();

      expect(gateway.bundles, hasLength(1));
      expect(gateway.bundles.single.caseYaml, controller.lastBundle!.caseYaml);
      expect(controller.savedPath, '/tmp/recorded-r1.yaml');
      expect(controller.isSaving, isFalse);
    });

    test('saveBundle without a bundle is a no-op', () async {
      final gateway = RecordingGateway();
      final controller = newController(gateway: gateway);

      await controller.saveBundle();

      expect(gateway.bundles, isEmpty);
      expect(controller.savedPath, isNull);
    });

    test('saveBundle surfaces gateway errors', () async {
      final gateway = RecordingGateway()..error = StateError('disk on fire');
      final controller = newController(gateway: gateway);
      controller.start();
      controller.recorder.recordInteractionStep(_tapStep('s1'));
      controller.exportBundle();

      await controller.saveBundle();

      expect(controller.savedPath, isNull);
      expect(controller.lastError, contains('disk on fire'));
    });
  });

  group('lifecycle', () {
    test('dispose detaches from the engine without disposing it', () {
      final controller = newController();
      final recorder = controller.recorder;

      controller.dispose();

      // The root owns the engine; it stays usable afterwards.
      recorder.start();
      expect(recorder.phase, CockpitRecorderPhase.recording);
    });
  });
}

CockpitInteractionStep _tapStep(String stepId) {
  return stepWithCandidates(
    CockpitInteractionStepKind.tap,
    <CockpitLocatorCandidate>[keyCandidate('replay-zone')],
  );
}
