import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show AxisDirection;

import '../gesture/cockpit_gesture_action.dart';
import '../gesture/cockpit_gesture_engine.dart';
import '../runtime/cockpit_target_registry.dart';
import '../runtime/cockpit_ui_idle_waiter.dart';
import 'cockpit_recorder_exclusion.dart';
import 'cockpit_replay_report.dart';

/// Signature of the idle wait verify-replay runs between replayed steps.
typedef CockpitReplayIdleWaiter =
    Future<bool> Function({
      required Duration quietWindow,
      required Duration timeout,
    });

/// Signature of the gesture performer verify-replay dispatches through.
typedef CockpitReplayGesturePerformer =
    Future<void> Function(CockpitGestureAction action);

/// Session engine for in-app interaction recording.
///
/// Owns the phase machine (`idle → recording ⇄ paused → stopped`), the
/// recorded step list, and the segment stack. The capture layer feeds
/// observed interactions through [recordInteractionStep]; the exclusion
/// registry it consults lives at [exclusions]. [export] converts the
/// recorded steps through [CockpitRecordedFlowConverter] and
/// [CockpitTestDocumentYamlWriter]; [verifyReplay] re-dispatches the
/// actionable steps through the live automation path with capture
/// suppressed.
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
  ///
  /// [registry], [waitForIdle], and [gesturePerformer] back [verifyReplay];
  /// the defaults (no registry, scheduler-quiet idle wait, a
  /// [CockpitGestureEngine]) are sufficient everywhere except the registry,
  /// which the owner (the Cockpit root) must wire for replay to be legal.
  CockpitInteractionRecorder({
    DateTime Function()? now,
    CockpitTargetRegistry? registry,
    CockpitReplayIdleWaiter? waitForIdle,
    CockpitReplayGesturePerformer? gesturePerformer,
  }) : _now = now ?? DateTime.now,
       _registry = registry,
       _waitForIdle = waitForIdle,
       _gesturePerformer = gesturePerformer;

  static const Duration _replayQuietWindow = Duration(milliseconds: 300);
  static const Duration _replaySettleTimeout = Duration(seconds: 5);

  final DateTime Function() _now;
  final CockpitTargetRegistry? _registry;
  final CockpitReplayIdleWaiter? _waitForIdle;
  final CockpitReplayGesturePerformer? _gesturePerformer;
  CockpitGestureEngine? _gestureEngine;

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
  bool _replaying = false;

  /// Hook invoked at the top of [stop], while the session is still in the
  /// `recording` or `paused` phase — so a hook's [recordInteractionStep]
  /// calls land in the returned result. The text capture uses this to flush
  /// a still-focused field. A single slot: setting a new hook replaces the
  /// previous one, `null` clears it.
  void Function()? beforeStopHook;

  /// Whether a verify-replay pass is currently executing. Capture feeds
  /// must drop events while this is true — a replay must not re-record
  /// itself.
  bool get isReplaying => _replaying;

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

  /// The currently open segment labels, stack order (bottom first).
  List<String> get openSegments => List<String>.unmodifiable(_segments);

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
  ///
  /// [beforeStopHook] runs first, while the session still accepts steps, so
  /// its recordings are included in the result.
  CockpitInteractionRecordingResult stop() {
    if (_phase != CockpitRecorderPhase.recording &&
        _phase != CockpitRecorderPhase.paused) {
      throw StateError(
        'Cannot stop an interaction recording while ${_phase.name}.',
      );
    }
    beforeStopHook?.call();
    _phase = CockpitRecorderPhase.stopped;
    _endedAt = _now();
    final result = CockpitInteractionRecordingResult(
      session: sessionSnapshot(),
      steps: steps,
    );
    notifyListeners();
    return result;
  }

  /// Builds the export bundle of the current session: the recorded steps,
  /// the converted case document, and its YAML rendering. Legal while
  /// `recording`, `paused`, and `stopped` — steps are retained until the
  /// next [start]. The case id derives from the engine-generated session id
  /// (`recorded-r1`, `recorded-r2`, …), which always satisfies the case id
  /// pattern by construction; the human-facing session name goes to the
  /// case `name`, not the id.
  ///
  /// Throws [StateError] before any session started, and
  /// [ArgumentError] (from the converter) when no exportable step exists.
  CockpitRecordedFlowBundle export() {
    _requireExportableSession('export');
    final sessionId = _sessionId!;
    final testCase = const CockpitRecordedFlowConverter().convert(
      caseId: 'recorded-$sessionId',
      steps: _steps,
      name: _sessionName,
      sessionId: sessionId,
    );
    final document = testCase.toJson();
    return CockpitRecordedFlowBundle(
      session: sessionSnapshot(),
      steps: steps,
      caseDocument: document,
      caseYaml: const CockpitTestDocumentYamlWriter().write(document),
    );
  }

  /// Replays the actionable recorded steps in-process and reports the
  /// per-step outcome.
  ///
  /// Actionable kinds (`tap`, `longPress`, `scroll`, `text`) resolve their
  /// locator candidates against the live registry — first candidate that
  /// resolves wins — and dispatch through the same gesture engine the
  /// automation path uses, or the target's text-input handlers for `text`
  /// steps. Every other recorded step — non-actionable kinds and unresolved
  /// noise — reports `skipped` so the panel timeline stays complete.
  /// Capture is suppressed for the whole pass through [isReplaying] (the
  /// phase machine is untouched — a replay from `stopped` must not pass
  /// through illegal phases), and a short idle wait runs between steps.
  /// Requires a wired registry and at least one actionable step.
  Future<List<CockpitReplayReport>> verifyReplay() async {
    _requireExportableSession('verify a replay for');
    final registry = _registry;
    if (registry == null) {
      throw StateError(
        'Cannot verify a replay: no target registry is wired to the '
        'recorder.',
      );
    }
    if (!_steps.any(isActionable)) {
      throw StateError(
        'Cannot verify a replay: the session has no actionable step.',
      );
    }
    _replaying = true;
    notifyListeners();
    try {
      return <CockpitReplayReport>[
        for (final step in _steps) await _replayStep(step, registry),
      ];
    } finally {
      _replaying = false;
      notifyListeners();
    }
  }

  Future<CockpitReplayReport> _replayStep(
    CockpitInteractionStep step,
    CockpitTargetRegistry registry,
  ) async {
    if (!isActionable(step)) {
      return CockpitReplayReport(
        stepId: step.stepId,
        kind: step.kind,
        status: CockpitReplayStatus.skipped,
        reason: 'Kind ${step.kind.name} is not replayable in-process.',
      );
    }
    CockpitTarget? target;
    for (final candidate in step.locatorCandidates) {
      final resolution = registry.resolve(
        CockpitSelector.parse(candidate.selector),
      );
      if (resolution.isSuccess) {
        target = resolution.target;
        break;
      }
    }
    if (target == null) {
      return CockpitReplayReport(
        stepId: step.stepId,
        kind: step.kind,
        status: CockpitReplayStatus.deviated,
        reason:
            'No locator candidate resolved against the live registry '
            '(tried ${step.locatorCandidates.map((c) => c.selector).join(', ')}).',
      );
    }
    try {
      await _performStep(step, target);
      await (_waitForIdle ?? _defaultWaitForIdle)(
        quietWindow: _replayQuietWindow,
        timeout: _replaySettleTimeout,
      );
      return CockpitReplayReport(
        stepId: step.stepId,
        kind: step.kind,
        status: CockpitReplayStatus.passed,
      );
    } on Object catch (error) {
      return CockpitReplayReport(
        stepId: step.stepId,
        kind: step.kind,
        status: CockpitReplayStatus.deviated,
        reason: 'Action failed: $error',
      );
    }
  }

  Future<void> _performStep(CockpitInteractionStep step, CockpitTarget target) {
    switch (step.kind) {
      case CockpitInteractionStepKind.tap:
        return _performGesture(CockpitGestureAction.tap(target: target));
      case CockpitInteractionStepKind.longPress:
        return _performGesture(CockpitGestureAction.longPress(target: target));
      case CockpitInteractionStepKind.scroll:
        final direction = switch (step.scrollDirection!) {
          CockpitInteractionScrollDirection.up => AxisDirection.up,
          CockpitInteractionScrollDirection.down => AxisDirection.down,
          CockpitInteractionScrollDirection.left => AxisDirection.left,
          CockpitInteractionScrollDirection.right => AxisDirection.right,
        };
        return _performGesture(
          CockpitGestureAction.swipe(target: target, direction: direction),
        );
      case CockpitInteractionStepKind.text:
        return _performTextEntry(step, target);
      case CockpitInteractionStepKind.routeChange ||
          CockpitInteractionStepKind.back ||
          CockpitInteractionStepKind.marker ||
          CockpitInteractionStepKind.note:
        throw StateError(
          'Unreachable: ${step.kind.name} steps are skipped before dispatch.',
        );
    }
  }

  /// Text replay follows the executor's handler preference: the
  /// request-based input handlers first, then the string-based enter-text
  /// handlers.
  Future<void> _performTextEntry(
    CockpitInteractionStep step,
    CockpitTarget target,
  ) {
    final value = step.resolvedValue!;
    final textInput = target.onTextInput ?? target.onSemanticTextInput;
    if (textInput != null) {
      return Future<void>.sync(
        () => textInput(CockpitTextInputRequest(text: value)),
      );
    }
    final enterText = target.onEnterText ?? target.onSemanticEnterText;
    if (enterText != null) {
      return Future<void>.sync(() => enterText(value));
    }
    throw StateError('The resolved target does not accept text entry.');
  }

  Future<void> _performGesture(CockpitGestureAction action) {
    return (_gesturePerformer ??
        (_gestureEngine ??= CockpitGestureEngine()).perform)(action);
  }

  static Future<bool> _defaultWaitForIdle({
    required Duration quietWindow,
    required Duration timeout,
  }) {
    return waitForCockpitUiIdle(
      quietWindow: quietWindow,
      timeout: timeout,
      waitTick: (duration) => Future<void>.delayed(duration),
    );
  }

  /// Whether [step] is replayable in-process: an actionable kind (`tap`,
  /// `longPress`, `scroll`, `text`) that resolved to at least one locator
  /// candidate. Everything else — non-actionable kinds and unresolved noise —
  /// reports `skipped` during [verifyReplay]. Public so the panel can derive
  /// its replay affordance from the same rule the engine enforces.
  static bool isActionable(CockpitInteractionStep step) {
    if (step.unresolved) {
      return false;
    }
    return switch (step.kind) {
      CockpitInteractionStepKind.tap ||
      CockpitInteractionStepKind.longPress ||
      CockpitInteractionStepKind.scroll ||
      CockpitInteractionStepKind.text => true,
      CockpitInteractionStepKind.routeChange ||
      CockpitInteractionStepKind.back ||
      CockpitInteractionStepKind.marker ||
      CockpitInteractionStepKind.note => false,
    };
  }

  void _requireExportableSession(String command) {
    if (_sessionId == null ||
        (_phase != CockpitRecorderPhase.recording &&
            _phase != CockpitRecorderPhase.paused &&
            _phase != CockpitRecorderPhase.stopped)) {
      throw StateError(
        'Cannot $command an interaction recording while '
        '${_phase.name}.',
      );
    }
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
  /// Effective only while `recording`; steps arriving while paused,
  /// stopped, or mid-verify-replay are silently dropped (pause and replay
  /// suppression) and listeners are not notified. See the class
  /// documentation for the step-stamping contract: `stepId`, `phase`,
  /// `segments`, and `settledAfterMs` are engine-owned and re-stamped here.
  void recordInteractionStep(CockpitInteractionStep step) {
    if (_phase != CockpitRecorderPhase.recording || _replaying) {
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
