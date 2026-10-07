import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter/foundation.dart';

import 'cockpit_recorder_exclusion.dart';

/// Session engine for in-app interaction recording.
///
/// Owns the phase machine (`idle → recording ⇄ paused → stopped`), the
/// recorded step list, and the segment stack. The capture layer feeds
/// observed interactions through [recordInteractionStep]; the exclusion
/// registry it consults lives at [exclusions]. Export and verify-replay
/// are implemented by later phases; the engine never carries stubs.
///
/// Step-stamping contract: the capture layer builds a
/// [CockpitInteractionStep] with placeholder values for `stepId` (any
/// non-empty string, e.g. `pending`), `phase`, and `segments`, plus a
/// `settledAfterMs` of `null`. [recordInteractionStep] re-stamps those
/// fields with the authoritative engine state — monotonic `s<n>` id, the
/// `recording` phase, and the segment stack open at record time — so step
/// ids are always engine-assigned and steps always carry the context that
/// was active when they were captured.
final class CockpitInteractionRecorder extends ChangeNotifier {
  /// Creates a recorder. Pass [now] to inject a clock; defaults to the
  /// system wall clock.
  CockpitInteractionRecorder({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// Subtree exclusion registry the capture layer consults per event.
  final CockpitRecorderExclusionRegistry exclusions =
      CockpitRecorderExclusionRegistry();

  final List<CockpitInteractionStep> _steps = <CockpitInteractionStep>[];
  final List<String> _segments = <String>[];

  CockpitRecorderPhase _phase = CockpitRecorderPhase.idle;
  String? _sessionName;
  int _sessionSequence = 0;
  int _stepSequence = 0;
  String? _sessionId;
  DateTime? _startedAt;
  DateTime? _pausedAt;
  DateTime? _endedAt;

  /// Current phase of the recording state machine.
  CockpitRecorderPhase get phase => _phase;

  /// Name of the current session, from the [start] request. The session
  /// model carries no name, so the engine keeps it.
  String? get sessionName => _sessionName;

  /// The current session, or `null` before the first [start]. Kept after
  /// [stop] so the finished session stays inspectable until the next
  /// [start] replaces it.
  CockpitInteractionRecordingSession? get activeSession =>
      _sessionId == null ? null : sessionSnapshot();

  /// The recorded steps of the current session, oldest first.
  List<CockpitInteractionStep> get steps =>
      List<CockpitInteractionStep>.unmodifiable(_steps);

  /// A fresh [CockpitInteractionRecordingSession] view of the engine state
  /// with recomputed `stepCount` and `unresolvedCount`.
  ///
  /// Throws [StateError] when no session has been started yet.
  CockpitInteractionRecordingSession sessionSnapshot() {
    if (_sessionId == null) {
      throw StateError(
        'No interaction recording session has been started yet.',
      );
    }
    return CockpitInteractionRecordingSession(
      sessionId: _sessionId!,
      phase: _phase,
      startedAt: _startedAt!,
      pausedAt: _pausedAt,
      endedAt: _endedAt,
      stepCount: _steps.length,
      unresolvedCount: _steps.where((step) => step.unresolved).length,
    );
  }

  /// Starts a new session. Legal from `idle` and `stopped`; resets the
  /// step list, step ids, and the segment stack. Session ids (`r1`,
  /// `r2`, …) stay monotonic across the recorder's lifetime.
  void start([CockpitInteractionRecordingRequest? request]) {
    if (_phase == CockpitRecorderPhase.recording ||
        _phase == CockpitRecorderPhase.paused) {
      throw StateError(
        'Cannot start an interaction recording while the previous session '
        'is ${_phase.name}.',
      );
    }
    _sessionSequence += 1;
    _sessionId = 'r$_sessionSequence';
    _sessionName = request?.name;
    _startedAt = _now();
    _pausedAt = null;
    _endedAt = null;
    _stepSequence = 0;
    _steps.clear();
    _segments.clear();
    _phase = CockpitRecorderPhase.recording;
    notifyListeners();
  }

  /// Pauses the running session. Legal only while `recording`. Capture is
  /// suppressed while paused; `pausedAt` records the latest pause.
  void pause() {
    _requirePhase(CockpitRecorderPhase.recording, 'pause');
    _phase = CockpitRecorderPhase.paused;
    _pausedAt = _now();
    notifyListeners();
  }

  /// Resumes a paused session.
  void resume() {
    _requirePhase(CockpitRecorderPhase.paused, 'resume');
    _phase = CockpitRecorderPhase.recording;
    notifyListeners();
  }

  /// Stops the session. Legal while `recording` or `paused`; `stopped` is
  /// terminal until the next [start]. Returns the finished result.
  CockpitInteractionRecordingResult stop() {
    if (_phase != CockpitRecorderPhase.recording &&
        _phase != CockpitRecorderPhase.paused) {
      throw StateError(
        'Cannot stop an interaction recording while ${_phase.name}.',
      );
    }
    _phase = CockpitRecorderPhase.stopped;
    _endedAt = _now();
    final result = CockpitInteractionRecordingResult(
      session: sessionSnapshot(),
      steps: steps,
    );
    notifyListeners();
    return result;
  }

  /// Opens a segment label. Legal only while `recording`. Segments nest;
  /// concurrent duplicate labels are allowed and each stays on the stack
  /// until its own [endSegment] pops it. Steps record the open labels in
  /// stack order, bottom first.
  void beginSegment(String label) {
    _requirePhase(CockpitRecorderPhase.recording, 'begin a segment');
    _segments.add(label);
    notifyListeners();
  }

  /// Closes the most recently opened segment. Throws [StateError] when no
  /// segment is open.
  void endSegment() {
    _requirePhase(CockpitRecorderPhase.recording, 'end a segment');
    if (_segments.isEmpty) {
      throw StateError('Cannot end a segment: no segment is open.');
    }
    _segments.removeLast();
    notifyListeners();
  }

  /// Replaces [CockpitInteractionStep.annotation] on a recorded step.
  /// Throws [StateError] for an unknown [stepId].
  void annotate(String stepId, String note) {
    _requirePhase(CockpitRecorderPhase.recording, 'annotate a step');
    final index = _indexOfStep(stepId);
    _steps[index] = _rebuildStep(_steps[index], annotation: note);
    notifyListeners();
  }

  /// Removes the most recently recorded step. Throws [StateError] when
  /// no step has been recorded.
  void discardLastStep() {
    _requirePhase(CockpitRecorderPhase.recording, 'discard a step');
    if (_steps.isEmpty) {
      throw StateError('Cannot discard a step: no step has been recorded.');
    }
    _steps.removeLast();
    notifyListeners();
  }

  /// Ingests a step captured by the capture layer.
  ///
  /// Effective only while `recording`; steps arriving while paused or
  /// stopped are silently dropped (pause suppression) and listeners are
  /// not notified. See the class documentation for the step-stamping
  /// contract: `stepId`, `phase`, `segments`, and `settledAfterMs` are
  /// engine-owned and re-stamped here.
  void recordInteractionStep(CockpitInteractionStep step) {
    if (_phase != CockpitRecorderPhase.recording) {
      return;
    }
    _stepSequence += 1;
    _steps.add(_rebuildStep(step, stepId: 's$_stepSequence'));
    notifyListeners();
  }

  /// Back-fills the settle time of a recorded step. Legal while
  /// `recording` or `paused` (a settle watch started before a pause may
  /// complete after it). Throws [StateError] for an unknown [stepId] or a
  /// step that is already settled.
  void markStepSettled(String stepId, int settledAfterMs) {
    if (settledAfterMs < 0) {
      throw ArgumentError.value(settledAfterMs, 'settledAfterMs');
    }
    if (_phase != CockpitRecorderPhase.recording &&
        _phase != CockpitRecorderPhase.paused) {
      throw StateError('Cannot mark a step settled while ${_phase.name}.');
    }
    final index = _indexOfStep(stepId);
    if (_steps[index].settledAfterMs != null) {
      throw StateError('Step $stepId is already settled.');
    }
    _steps[index] = _rebuildStep(_steps[index], settledAfterMs: settledAfterMs);
    notifyListeners();
  }

  int _indexOfStep(String stepId) {
    for (var index = _steps.length - 1; index >= 0; index -= 1) {
      if (_steps[index].stepId == stepId) {
        return index;
      }
    }
    throw StateError('Unknown step id $stepId.');
  }

  void _requirePhase(CockpitRecorderPhase expected, String command) {
    if (_phase != expected) {
      throw StateError(
        'Cannot $command while the interaction recording is ${_phase.name}.',
      );
    }
  }

  /// Rebuilds an immutable step with the engine-owned fields. Fields not
  /// passed keep the incoming step's values; [recordInteractionStep] uses
  /// this to stamp id/phase/segments and settle back-fill uses it to stamp
  /// `settledAfterMs`.
  CockpitInteractionStep _rebuildStep(
    CockpitInteractionStep step, {
    String? stepId,
    String? annotation,
    int? settledAfterMs,
  }) {
    final stamping = stepId != null;
    return CockpitInteractionStep(
      stepId: stepId ?? step.stepId,
      kind: step.kind,
      locatorCandidates: step.locatorCandidates,
      resolvedValue: step.resolvedValue,
      scrollDirection: step.scrollDirection,
      routeName: step.routeName,
      fromRouteName: step.fromRouteName,
      positionDx: step.positionDx,
      positionDy: step.positionDy,
      phase: stamping ? CockpitRecorderPhase.recording : step.phase,
      unresolved: step.unresolved,
      segments: stamping ? _segments : step.segments,
      annotation: annotation ?? step.annotation,
      settledAfterMs: stamping ? null : (settledAfterMs ?? step.settledAfterMs),
      recordedAt: step.recordedAt,
    );
  }
}
