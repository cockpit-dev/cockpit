import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter/foundation.dart';

import '../cockpit_interaction_recorder.dart';
import '../cockpit_replay_report.dart';
import 'cockpit_recorder_export_gateway.dart';

/// View model over [CockpitInteractionRecorder] for recorder panels.
///
/// The only object panel widgets bind to: it relays engine change
/// notifications, derives the enablement state widgets render, and funnels
/// every command so failures land in [lastError] instead of escaping into a
/// widget build. The engine stays reachable for hosts that drive it through
/// other surfaces (remote endpoints, CLI), but panels never touch it.
final class CockpitRecorderController extends ChangeNotifier {
  /// Creates a controller over [recorder]. [exportGateway] backs
  /// [saveBundle]; the default writes YAML to the system temp directory.
  CockpitRecorderController({
    required this.recorder,
    CockpitRecorderExportGateway? exportGateway,
  }) : _exportGateway = exportGateway ?? CockpitRecorderFileExportGateway() {
    recorder.addListener(_relayEngineChange);
  }

  /// The engine this controller fronts. Owned by the Cockpit root, not by
  /// this controller — disposing the controller only detaches the listener.
  final CockpitInteractionRecorder recorder;
  final CockpitRecorderExportGateway _exportGateway;

  CockpitRecordedFlowBundle? _bundle;
  List<CockpitReplayReport>? _replayReports;
  String? _savedPath;
  String? _lastError;
  bool _isSaving = false;

  /// Current phase of the recording state machine.
  CockpitRecorderPhase get phase => recorder.phase;

  /// The recorded steps of the current session, oldest first.
  List<CockpitInteractionStep> get steps => recorder.steps;

  /// The current session view (with recomputed counts), or `null` before
  /// the first start.
  CockpitInteractionRecordingSession? get session => recorder.activeSession;

  /// The currently open segment labels, bottom first.
  List<String> get openSegments => recorder.openSegments;

  /// Whether a verify-replay pass is currently executing.
  bool get isReplaying => recorder.isReplaying;

  /// The last export bundle, or `null` until [exportBundle] succeeds.
  CockpitRecordedFlowBundle? get lastBundle => _bundle;

  /// The per-step reports of the last [verifyReplay], or `null` before the
  /// first pass.
  List<CockpitReplayReport>? get replayReports => _replayReports;

  /// The path or message returned by the last successful [saveBundle].
  String? get savedPath => _savedPath;

  /// The error of the last failed command, shown inline by panels. Cleared
  /// by the next successful command or by [clearError].
  String? get lastError => _lastError;

  /// Whether a [saveBundle] call is in flight.
  bool get isSaving => _isSaving;

  // Derived enablement for panel affordances.

  /// Whether [start] is legal: from `idle`, or a new session after `stopped`.
  bool get canStart =>
      phase == CockpitRecorderPhase.idle ||
      phase == CockpitRecorderPhase.stopped;

  /// Whether [pause] is legal: only while `recording`.
  bool get canPause => phase == CockpitRecorderPhase.recording;

  /// Whether [resume] is legal: only while `paused`.
  bool get canResume => phase == CockpitRecorderPhase.paused;

  /// Whether [stop] is legal: while `recording` or `paused`.
  bool get canStop =>
      phase == CockpitRecorderPhase.recording ||
      phase == CockpitRecorderPhase.paused;

  /// Whether the newest recorded step can be annotated or deleted: only
  /// while `recording`, and only when a step exists.
  bool get canDiscardLast =>
      phase == CockpitRecorderPhase.recording && steps.isNotEmpty;

  /// Whether [verifyReplay] has work to do: a session with at least one
  /// actionable step, not already replaying.
  bool get canVerifyReplay =>
      session != null &&
      !isReplaying &&
      steps.any(CockpitInteractionRecorder.isActionable);

  // Commands. Every command swallows its failure into [lastError] — a panel
  // button press must never throw into the framework. Result fields
  // ([lastBundle], [replayReports], [savedPath]) keep the outcome of the
  // last run of their action until the next run replaces them.

  /// Starts a new recording session, optionally named [name] (whitespace
  /// trimmed; empty names start an unnamed session). The name surfaces as
  /// the exported case document's `name`.
  void start([String? name]) => _run(() {
    final trimmed = name?.trim();
    recorder.start(
      trimmed == null || trimmed.isEmpty
          ? null
          : CockpitInteractionRecordingRequest(name: trimmed),
    );
  });

  /// Pauses the running session.
  void pause() => _run(() => recorder.pause());

  /// Resumes a paused session.
  void resume() => _run(() => recorder.resume());

  /// Stops the session; `stopped` is terminal until the next [start].
  void stop() => _run(() => recorder.stop());

  /// Opens a nested segment label.
  void beginSegment(String label) =>
      _run(() => recorder.beginSegment(label.trim()));

  /// Closes the most recently opened segment.
  void endSegment() => _run(() => recorder.endSegment());

  /// Replaces the annotation of a recorded step.
  void annotate(String stepId, String note) =>
      _run(() => recorder.annotate(stepId, note));

  /// Removes the most recently recorded step.
  void discardLastStep() => _run(() => recorder.discardLastStep());

  /// Builds the export bundle of the current session and stores it as
  /// [lastBundle]; earlier bundles are replaced, so re-exporting is always
  /// allowed.
  void exportBundle() => _run(() => _bundle = recorder.export());

  /// Replays the recorded steps in-process and stores the per-step reports
  /// as [replayReports]. Ignored while a pass is already running.
  Future<void> verifyReplay() async {
    if (isReplaying) {
      return;
    }
    try {
      _replayReports = await recorder.verifyReplay();
      _lastError = null;
    } on Object catch (error) {
      _lastError = error.toString();
    }
    notifyListeners();
  }

  /// Persists [lastBundle] through the export gateway and stores the
  /// returned path as [savedPath]. Ignored while a save is in flight or no
  /// bundle exists.
  Future<void> saveBundle() async {
    final bundle = _bundle;
    if (_isSaving || bundle == null) {
      return;
    }
    _isSaving = true;
    notifyListeners();
    try {
      _savedPath = await _exportGateway.persist(bundle);
      _lastError = null;
    } on Object catch (error) {
      _lastError = error.toString();
    } finally {
      _isSaving = false;
    }
    notifyListeners();
  }

  /// Clears [lastError].
  void clearError() {
    if (_lastError == null) {
      return;
    }
    _lastError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    recorder.removeListener(_relayEngineChange);
    super.dispose();
  }

  void _relayEngineChange() => notifyListeners();

  /// Runs a synchronous engine command, surfacing failures in [lastError].
  /// A successful command clears [lastError]; the engine's own change
  /// notification has already relayed by the time this returns.
  void _run(VoidCallback command) {
    try {
      command();
    } on Object catch (error) {
      _lastError = error.toString();
      notifyListeners();
      return;
    }
    if (_lastError != null) {
      _lastError = null;
    }
    notifyListeners();
  }
}
