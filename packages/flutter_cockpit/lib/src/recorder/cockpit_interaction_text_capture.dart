import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter/widgets.dart';

import 'cockpit_interaction_recorder.dart';
import 'cockpit_interaction_target_matcher.dart';

/// Tracks focus entering and leaving `EditableText` fields and records one
/// `text` step per field with the field's final committed value.
///
/// The capture owns the focus subscription and the tracked field; the
/// recorder, registry, and route name are read through provider callbacks so
/// a capture created once always flushes through the widget tree's current
/// wiring. Empty values are skipped, and a field whose element unmounted
/// (taking its controller with it) flushes nothing.
final class CockpitInteractionTextCapture {
  /// Creates a detached capture; call [attach] to start observing focus.
  CockpitInteractionTextCapture({
    required CockpitInteractionRecorder Function() recorder,
    required CockpitTargetRegistry Function() registry,
    required String? Function() routeName,
  }) : _recorder = recorder,
       _registry = registry,
       _routeName = routeName;

  final CockpitInteractionRecorder Function() _recorder;
  final CockpitTargetRegistry Function() _registry;
  final String? Function() _routeName;

  Element? _element;
  TextEditingController? _controller;

  /// Subscribes to global focus updates.
  void attach() {
    FocusManager.instance.addListener(_handleFocusUpdate);
  }

  /// Unsubscribes and drops any tracked field without recording it.
  void detach() {
    FocusManager.instance.removeListener(_handleFocusUpdate);
    _element = null;
    _controller = null;
  }

  void _handleFocusUpdate() {
    final focused = _focusedEditable();
    if (identical(_element, focused?.$1)) {
      return;
    }
    _flushTrackedField();
    if (focused != null) {
      _element = focused.$1;
      _controller = focused.$2;
    }
  }

  /// Records the tracked field's value, if any. Effective only while the
  /// engine accepts steps — pause suppression lives in the recorder.
  void _flushTrackedField() {
    final element = _element;
    final controller = _controller;
    _element = null;
    _controller = null;
    if (element == null || controller == null || !element.mounted) {
      return;
    }
    final value = controller.text;
    if (value.trim().isEmpty) {
      return;
    }
    final match = CockpitInteractionTargetMatcher.matchElementAncestry(
      _registry(),
      element,
    );
    final candidates = match == null
        ? const <CockpitLocatorCandidate>[]
        : CockpitInteractionTargetMatcher.locatorCandidates(match);
    _recorder().recordInteractionStep(
      CockpitInteractionStep(
        stepId: 'pending',
        kind: CockpitInteractionStepKind.text,
        locatorCandidates: candidates,
        resolvedValue: value,
        routeName: _routeName(),
        unresolved: candidates.isEmpty,
        phase: CockpitRecorderPhase.recording,
        recordedAt: DateTime.now(),
      ),
    );
  }

  /// Resolves the `EditableText` element and controller behind the focused
  /// node. The node's context usually sits inside the `EditableText`
  /// subtree (the framework attaches the node there), so the ancestor walk
  /// covers both that shape and a context on the element itself.
  (Element, TextEditingController)? _focusedEditable() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context is! Element) {
      return null;
    }
    final widget = context.widget;
    if (widget is EditableText) {
      return (context, widget.controller);
    }
    final state = context.findAncestorStateOfType<EditableTextState>();
    if (state == null || !state.mounted) {
      return null;
    }
    // State.context is its own Element by construction.
    return (state.context as Element, state.widget.controller);
  }
}
