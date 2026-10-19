import 'dart:ui' show Offset;

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
  /// [routeNameProvider] surfaces the live route during replay so recorded
  /// route changes can act as navigation sync points, and
  /// [viewportGeometryProvider] lets the internal gesture engine resolve
  /// coordinate-only gestures — reveal swipes from a recorded press
  /// position — against the live viewport.
  CockpitInteractionRecorder({
    DateTime Function()? now,
    CockpitTargetRegistry? registry,
    CockpitReplayIdleWaiter? waitForIdle,
    CockpitReplayGesturePerformer? gesturePerformer,
    String? Function()? routeNameProvider,
    CockpitViewportGeometryProvider? viewportGeometryProvider,
  }) : _now = now ?? DateTime.now,
       _registry = registry,
       _waitForIdle = waitForIdle,
       _gesturePerformer = gesturePerformer,
       _routeNameProvider = routeNameProvider,
       _viewportGeometryProvider = viewportGeometryProvider;

  static const Duration _replayQuietWindow = Duration(milliseconds: 300);
  static const Duration _replaySettleTimeout = Duration(seconds: 5);

  /// How often the route sync point polls the wired route provider.
  static const Duration _routePollInterval = Duration(milliseconds: 50);

  /// Upper bound on goal-directed scroll swipes before a step reports
  /// deviation: each swipe travels roughly a viewport, so six covers about
  /// five screens of travel — beyond that the flow is not about scrolling
  /// anymore.
  static const int _maxScrollReplayAttempts = 6;

  final DateTime Function() _now;
  final CockpitTargetRegistry? _registry;
  final CockpitReplayIdleWaiter? _waitForIdle;
  final CockpitReplayGesturePerformer? _gesturePerformer;
  final String? Function()? _routeNameProvider;
  final CockpitViewportGeometryProvider? _viewportGeometryProvider;
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
      final reports = <CockpitReplayReport>[];
      for (var index = 0; index < _steps.length; index += 1) {
        final step = _steps[index];
        reports.add(
          await _replayStep(
            step,
            registry,
            scrollToward: step.kind == CockpitInteractionStepKind.scroll
                ? _scrollToward(index)
                : null,
          ),
        );
      }
      return reports;
    } finally {
      _replaying = false;
      notifyListeners();
    }
  }

  /// What a scroll step at [index] exists to reveal: the first resolved
  /// candidate-bearing action after it, mirroring the converter's
  /// scroll-target borrowing so in-process verification and the exported
  /// case replay one flow. Route boundaries end the search — scrolling
  /// toward a target on another screen is meaningless — and trailing
  /// scrolls find nothing, replaying as a single swipe on their own
  /// candidate.
  CockpitInteractionStep? _scrollToward(int index) {
    for (var next = index + 1; next < _steps.length; next += 1) {
      final step = _steps[next];
      switch (step.kind) {
        case CockpitInteractionStepKind.routeChange ||
            CockpitInteractionStepKind.back:
          return null;
        case CockpitInteractionStepKind.tap ||
            CockpitInteractionStepKind.longPress ||
            CockpitInteractionStepKind.text:
          return step.unresolved || step.locatorCandidates.isEmpty
              ? null
              : step;
        case CockpitInteractionStepKind.scroll ||
            CockpitInteractionStepKind.marker ||
            CockpitInteractionStepKind.note:
          continue;
      }
    }
    return null;
  }

  Future<CockpitReplayReport> _replayStep(
    CockpitInteractionStep step,
    CockpitTargetRegistry registry, {
    CockpitInteractionStep? scrollToward,
  }) async {
    if (!isActionable(step)) {
      // A recorded route change is not replayable itself — the action that
      // caused it already replayed — but it is the flow's navigation sync
      // point: the push or pop it documents is asynchronous, and without
      // waiting for it the next step resolves against the outgoing screen
      // on a slow device. Await the recorded destination, then settle so
      // the incoming screen's targets join the registry before the flow
      // continues.
      if (step.routeName != null &&
          (step.kind == CockpitInteractionStepKind.routeChange ||
              step.kind == CockpitInteractionStepKind.back)) {
        await _awaitRouteArrival(step.routeName!);
        await _replaySettle();
      }
      return CockpitReplayReport(
        stepId: step.stepId,
        kind: step.kind,
        status: CockpitReplayStatus.skipped,
        reason: 'Kind ${step.kind.name} is not replayable in-process.',
      );
    }
    if (step.kind == CockpitInteractionStepKind.scroll) {
      if (scrollToward != null) {
        return _replayScrollUntilVisible(step, registry, toward: scrollToward);
      }
      if (step.locatorCandidates.isEmpty) {
        // A trailing scroll with no locator of its own: the converter
        // drops it from the exported case, so in-process verification
        // skips it instead of deviating on a step that never replays.
        return CockpitReplayReport(
          stepId: step.stepId,
          kind: step.kind,
          status: CockpitReplayStatus.skipped,
          reason: 'Trailing scroll without a locator candidate.',
        );
      }
      if (_resolveCandidate(step, registry) == null) {
        // The scroll's own grab-point anchor sits off-screen at replay
        // width, and nothing follows it to borrow a goal from: replay it
        // goal-directed toward itself, the same fallback the exported
        // case's `scrollUntilVisible` uses. A resolvable anchor keeps the
        // direct dispatch below — one swipe on the target, exactly the
        // gesture that was recorded.
        return _replayScrollUntilVisible(step, registry, toward: step);
      }
    }
    var target = _resolveCandidate(step, registry);
    if (target == null && step.kind != CockpitInteractionStepKind.scroll) {
      // A target that was visible while recording can sit below the fold on
      // replay: a narrower layout makes list rows taller and pushes the row
      // out of the viewport before this step runs. Reveal it with the same
      // bounded, goal-directed scrolling the recorded scroll steps replay
      // with, then resolve again before deviating.
      final revealed = await _revealForStep(step, registry);
      if (revealed) {
        target = _resolveCandidate(step, registry);
      }
    }
    if (target == null) {
      return CockpitReplayReport(
        stepId: step.stepId,
        kind: step.kind,
        status: CockpitReplayStatus.deviated,
        reason:
            'No locator candidate resolved against the live registry '
            '(tried ${step.locatorCandidates.map((c) => c.selector).join(', ')}, '
            'bounded scrolling did not reveal it).',
      );
    }
    try {
      await _performStep(step, target);
      await _replaySettle();
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

  /// The scroll's goal-directed replay: swipe the recorded direction until
  /// the step it existed to reveal resolves against the live registry —
  /// the in-process mirror of the exported `scrollUntilVisible`. Each
  /// swipe prefers the scroll's own grab-point candidate; without one it
  /// falls back to the recorded grab coordinates (the gesture engine
  /// resolves a target-less swipe against the viewport), which is exactly
  /// where the user's finger pulled the list.
  Future<CockpitReplayReport> _replayScrollUntilVisible(
    CockpitInteractionStep step,
    CockpitTargetRegistry registry, {
    required CockpitInteractionStep toward,
  }) async {
    for (var attempt = 0; attempt < _maxScrollReplayAttempts; attempt += 1) {
      if (_resolveCandidate(toward, registry) != null) {
        return CockpitReplayReport(
          stepId: step.stepId,
          kind: step.kind,
          status: CockpitReplayStatus.passed,
        );
      }
      try {
        await _scrollOnce(step, registry);
        await _replaySettle();
      } on Object catch (error) {
        return CockpitReplayReport(
          stepId: step.stepId,
          kind: step.kind,
          status: CockpitReplayStatus.deviated,
          reason: 'Scroll action failed: $error',
        );
      }
    }
    return CockpitReplayReport(
      stepId: step.stepId,
      kind: step.kind,
      status: CockpitReplayStatus.deviated,
      reason:
          'Scrolled $_maxScrollReplayAttempts times without bringing the '
          'next step into the registry (tried '
          '${toward.locatorCandidates.map((c) => c.selector).join(', ')}).',
    );
  }

  /// Reveals a step's target with bounded scrolling after its candidates
  /// failed to resolve: the step was recorded against a target that was
  /// visible then, so the same list — scrolled or re-laid-out at a different
  /// width — usually still holds it one or two swipes away. Swipes start
  /// from the recorded press position (inside the same scrollable) and try
  /// each vertical direction in turn. The first direction gets
  /// [_maxScrollReplayAttempts] swipes; the second gets twice that, because
  /// it must first walk back over the first direction's ground before it can
  /// explore past the starting position — otherwise it could only ever
  /// return to where the reveal began, never beyond it.
  Future<bool> _revealForStep(
    CockpitInteractionStep step,
    CockpitTargetRegistry registry,
  ) async {
    final origin = step.positionDx != null && step.positionDy != null
        ? Offset(step.positionDx!, step.positionDy!)
        : null;
    const directions = <CockpitInteractionScrollDirection>[
      CockpitInteractionScrollDirection.up,
      CockpitInteractionScrollDirection.down,
    ];
    for (var phase = 0; phase < directions.length; phase += 1) {
      final direction = directions[phase];
      final attempts = phase == 0
          ? _maxScrollReplayAttempts
          : _maxScrollReplayAttempts * 2;
      for (var attempt = 0; attempt < attempts; attempt += 1) {
        if (_resolveCandidate(step, registry) != null) {
          return true;
        }
        if (origin == null) {
          return false;
        }
        try {
          await _performGesture(
            CockpitGestureAction.swipe(
              origin: origin,
              direction: _axisDirection(direction),
            ),
          );
          await _replaySettle();
        } on Object {
          // A swipe off the live viewport (the recorded press position may
          // not exist at this layout) is not a deviation of the step itself;
          // stop revealing and let the resolution verdict speak.
          return false;
        }
      }
    }
    return _resolveCandidate(step, registry) != null;
  }

  /// One recorded-direction swipe: on the scroll's own resolved candidate
  /// when it has one, otherwise from the recorded grab position.
  Future<void> _scrollOnce(
    CockpitInteractionStep step,
    CockpitTargetRegistry registry,
  ) {
    final direction = _axisDirection(step.scrollDirection!);
    final target = _resolveCandidate(step, registry);
    final grab =
        target == null && step.positionDx != null && step.positionDy != null
        ? Offset(step.positionDx!, step.positionDy!)
        : null;
    return _performGesture(
      CockpitGestureAction.swipe(
        target: target,
        origin: grab,
        direction: direction,
      ),
    );
  }

  Future<void> _replaySettle() {
    return (_waitForIdle ?? _defaultWaitForIdle)(
      quietWindow: _replayQuietWindow,
      timeout: _replaySettleTimeout,
    );
  }

  /// Bounded wait for the live route to reach [expected]. Navigation
  /// triggered by a replayed action is asynchronous, and the recorded
  /// route change that follows it is the only proof of when the new
  /// screen is in place. Each poll runs one settle beat — the wired idle
  /// wait pumps the frame queue under a test binding, which also advances
  /// the test clock the beat needs — and the poll count bounds the whole
  /// wait to the settle timeout's worth of beats. On exhaustion the
  /// verdict is left to the next step's resolution instead of failing the
  /// (non-replayable) route change itself.
  Future<void> _awaitRouteArrival(String expected) async {
    final provider = _routeNameProvider;
    if (provider == null || provider() == expected) {
      return;
    }
    final maxPolls =
        _replaySettleTimeout.inMilliseconds ~/
        _routePollInterval.inMilliseconds;
    for (var poll = 0; poll < maxPolls; poll += 1) {
      await (_waitForIdle ?? _defaultWaitForIdle)(
        quietWindow: _routePollInterval,
        timeout: _replaySettleTimeout,
      );
      if (provider() == expected) {
        return;
      }
    }
  }

  /// Resolves the first candidate of [step] that the live registry can
  /// serve the step's command from.
  CockpitTarget? _resolveCandidate(
    CockpitInteractionStep step,
    CockpitTargetRegistry registry,
  ) {
    for (final candidate in step.locatorCandidates) {
      final resolution = registry.resolve(
        CockpitSelector.parse(candidate.selector),
        requiredCommand: _commandForStep(step),
      );
      if (resolution.isSuccess) {
        return resolution.target;
      }
    }
    return null;
  }

  Future<void> _performStep(CockpitInteractionStep step, CockpitTarget target) {
    switch (step.kind) {
      case CockpitInteractionStepKind.tap:
        return _performGesture(CockpitGestureAction.tap(target: target));
      case CockpitInteractionStepKind.longPress:
        return _performGesture(CockpitGestureAction.longPress(target: target));
      case CockpitInteractionStepKind.scroll:
        return _performGesture(
          CockpitGestureAction.swipe(
            target: target,
            direction: _axisDirection(step.scrollDirection!),
          ),
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
    final performer = _gesturePerformer;
    if (performer != null) {
      return performer(action);
    }
    return (_gestureEngine ??= CockpitGestureEngine(
      viewportGeometryProvider: _viewportGeometryProvider,
    )).perform(action);
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

  /// The command a replayed [step] dispatches, so resolution prefers targets
  /// that can actually perform it. Replaying a recorded flow mutates app
  /// state, and a locator that was unique at record time can later match
  /// several passive look-alikes (two labels sharing the recorded text, for
  /// example); requiring the step's command resolves toward the actionable
  /// control instead of failing on the tie. Targets that support nothing
  /// fall back to plain locator matches inside the registry.
  static CockpitCommandType? _commandForStep(CockpitInteractionStep step) {
    return switch (step.kind) {
      CockpitInteractionStepKind.tap => CockpitCommandType.tap,
      CockpitInteractionStepKind.longPress => CockpitCommandType.longPress,
      CockpitInteractionStepKind.scroll => CockpitCommandType.swipe,
      CockpitInteractionStepKind.text => CockpitCommandType.enterText,
      CockpitInteractionStepKind.routeChange ||
      CockpitInteractionStepKind.back ||
      CockpitInteractionStepKind.marker ||
      CockpitInteractionStepKind.note => null,
    };
  }

  static AxisDirection _axisDirection(CockpitInteractionScrollDirection d) {
    return switch (d) {
      CockpitInteractionScrollDirection.up => AxisDirection.up,
      CockpitInteractionScrollDirection.down => AxisDirection.down,
      CockpitInteractionScrollDirection.left => AxisDirection.left,
      CockpitInteractionScrollDirection.right => AxisDirection.right,
    };
  }

  /// Whether [step] is replayable in-process: an actionable kind (`tap`,
  /// `longPress`, `scroll`, `text`) that resolved to at least one locator
  /// candidate. Everything else — non-actionable kinds and unresolved noise —
  /// reports `skipped` during [verifyReplay]. Public so the panel can derive
  /// its replay affordance from the same rule the engine enforces.
  static bool isActionable(CockpitInteractionStep step) {
    if (step.kind == CockpitInteractionStepKind.scroll) {
      // A scroll replays through its direction even without locator
      // candidates: its target can be borrowed from the next step (the
      // converter does the same) and a swipe can run from the recorded
      // grab position alone.
      return step.scrollDirection != null;
    }
    if (step.unresolved) {
      return false;
    }
    return switch (step.kind) {
      // Unreachable behind the direction check above, kept for
      // exhaustiveness.
      CockpitInteractionStepKind.scroll => true,
      CockpitInteractionStepKind.tap ||
      CockpitInteractionStepKind.longPress ||
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
