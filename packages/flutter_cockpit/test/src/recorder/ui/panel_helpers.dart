import 'package:flutter/material.dart';
import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shared fixtures for the recorder UI tests: pending-step builders, a
/// replay-capable engine, a recording gateway, and panel pump helpers.

CockpitLocatorCandidate keyCandidate(String key) => CockpitLocatorCandidate(
  kind: 'key',
  selector: CockpitSelector.format(CockpitLocator(key: key)),
  score: 4,
);

/// The shared capture clock steps build offsets against: the engine's
/// wall-clock `recordedAt` is diagnostic, so tests pin one origin.
DateTime sessionClock([Duration offset = Duration.zero]) {
  return DateTime.utc(2026, 10, 7, 9).add(offset);
}

CockpitInteractionStep stepWithCandidates(
  CockpitInteractionStepKind kind, [
  List<CockpitLocatorCandidate> candidates = const <CockpitLocatorCandidate>[],
  DateTime? recordedAt,
]) {
  return CockpitInteractionStep(
    stepId: 'pending',
    kind: kind,
    locatorCandidates: candidates,
    phase: CockpitRecorderPhase.recording,
    recordedAt: recordedAt ?? sessionClock(),
  );
}

CockpitInteractionStep unresolvedStep(
  CockpitInteractionStepKind kind, {
  DateTime? recordedAt,
}) {
  return CockpitInteractionStep(
    stepId: 'pending',
    kind: kind,
    unresolved: true,
    phase: CockpitRecorderPhase.recording,
    recordedAt: recordedAt ?? sessionClock(),
  );
}

/// An engine whose verify-replay pass resolves the `replay-zone` key and
/// performs no real gestures — `passed` without a widget tree.
CockpitInteractionRecorder replayableRecorder() {
  final registry = CockpitTargetRegistry()
    ..register(
      CockpitTarget(
        registrationId: 'replay-zone',
        keyValue: 'replay-zone',
        routeName: '/',
      ),
    );
  return CockpitInteractionRecorder(
    registry: registry,
    waitForIdle:
        ({required Duration quietWindow, required Duration timeout}) async =>
            true,
    gesturePerformer: (_) async {},
  );
}

CockpitRecorderController newController({
  CockpitInteractionRecorder? recorder,
  CockpitRecorderExportGateway? gateway,
}) {
  return CockpitRecorderController(
    recorder: recorder ?? CockpitInteractionRecorder(),
    exportGateway: gateway,
  );
}

/// Fake gateway recording every persisted bundle.
final class RecordingGateway implements CockpitRecorderExportGateway {
  Object? error;
  String result = '/tmp/saved.yaml';
  final List<CockpitRecordedFlowBundle> bundles = <CockpitRecordedFlowBundle>[];

  @override
  Future<String> persist(CockpitRecordedFlowBundle bundle) async {
    if (error != null) {
      throw error!;
    }
    bundles.add(bundle);
    return result;
  }
}

/// Pumps [CockpitRecorderPanel] inside a sized container and returns its
/// controller. The default size keeps every section inside the 800x600
/// test surface, so bottom-area buttons stay tappable.
Future<CockpitRecorderController> pumpPanel(
  WidgetTester tester, {
  CockpitInteractionRecorder? recorder,
  CockpitRecorderExportGateway? gateway,
  Size size = const Size(480, 560),
}) async {
  final controller = newController(recorder: recorder, gateway: gateway);
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: CockpitRecorderScope(
            controller: controller,
            child: const CockpitRecorderPanel(),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return controller;
}

/// Whether the panel button showing [label] is currently enabled.
bool isButtonEnabled(WidgetTester tester, String label) {
  final gesture = find
      .ancestor(of: find.text(label), matching: find.byType(GestureDetector))
      .first;
  return tester.widget<GestureDetector>(gesture).onTap != null;
}

/// The stroke color of a step row's leading glyph — where replay outcomes
/// and unresolved targets tint the row.
Color stepGlyphColor(WidgetTester tester, Finder row) {
  final glyph = find
      .descendant(of: row, matching: find.byType(CockpitRecorderStepGlyph))
      .evaluate()
      .single;
  return (glyph.widget as CockpitRecorderStepGlyph).color;
}
