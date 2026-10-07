import '../control/cockpit_locator.dart';
import '../control/cockpit_selector.dart';
import '../test/cockpit_test_action.dart';
import '../test/cockpit_test_action_contract.dart';
import '../test/cockpit_test_case.dart';
import '../test/cockpit_test_condition.dart';
import '../test/cockpit_test_locator.dart';
import '../test/cockpit_test_policy.dart';
import '../test/cockpit_test_step.dart';
import '../test/cockpit_test_value.dart';
import 'cockpit_interaction_step.dart';
import 'cockpit_locator_candidate.dart';

/// One exportable recorded step paired with its document locator chain.
final class _ExportableStep {
  const _ExportableStep(this.step, this.locator, {required this.isSetup});

  final CockpitInteractionStep step;

  /// Primary locator plus the remaining candidates as the fallbacks chain,
  /// or `null` when the step carries no usable locator (`routeChange`,
  /// `back`) or none of its candidates is document-representable.
  final CockpitTestLocatorTemplate? locator;

  final bool isSetup;
}

CockpitTestTemplateValue? _string(String? value) => value == null
    ? null
    : CockpitTestTemplateValue.literal(
        value,
        expectedType: CockpitTestValueType.string,
      );

/// Converts recorded interaction steps into a schema-valid
/// [CockpitTestCase], built exclusively through the `lib/src/test/`
/// templates so the document is valid by construction.
///
/// The converter is pure: no clocks, no I/O, and deterministic output for a
/// given input. Mapping rules (see `docs/recorder/interaction-recorder.md`,
/// "Converter"):
///
/// - `unresolved` steps, `marker` steps, and `note` steps are dropped —
///   markers are timeline aids whose segment labels already live on each
///   step's `segments`; steps whose segments contain `setup` go to the case
///   `setup` block, the rest to `steps`.
/// - `tap`/`longPress`/`text`/`scroll` map to the action kinds `tap`,
///   `longPress`, `enterText`, and `scrollUntilVisible`. The first locator
///   candidate becomes the primary locator; the remaining candidates become
///   its `fallbacks` chain. A candidate whose only signal has no document
///   representation (`semanticId` — the test document's locator has no
///   semantic slot) is skipped; a locator-requiring action whose candidates
///   are all unrepresentable is dropped like unresolved noise. For `text`
///   steps the final value becomes the action's `text` argument.
/// - `scroll` maps to `scrollUntilVisible` because that is the only scroll
///   action whose required arguments (`locator` + `direction`) are exactly
///   what the recorder captured — `swipe` would require inventing a
///   distance. A `scroll` step immediately before a `tap` stays a separate
///   step: folding the pair is over-optimization when both steps already
///   replay correctly on their own.
/// - `routeChange` maps to a `waitFor` action with a `route` condition —
///   the document has no dedicated `waitForRoute` kind; the route condition
///   on `waitFor` is the waiting mechanism. `back` maps to the `back`
///   action kind.
/// - Weak assertions are auto-emitted as `waitFor` actions with `visible`
///   conditions (again the document's only visibility-waiting form;
///   `assertVisible` is a hard assertion, not a wait): after each action
///   step on the *next* step's primary locator, and a terminal wait on the
///   last action's own locator. A step whose next step is a `routeChange`
///   needs no extra wait — the route step is itself one.
/// - The case `extensions` record `x-cockpit-origin: recorded` and, when
///   [sessionId] is given, `x-cockpit-recorder-session`, so consumers know
///   a human or agent should strengthen the assertions.
/// - No guarded (`if`) steps are emitted: the known-interruption pattern
///   table depends on native-plane capture, which does not exist yet. This
///   is a documented v1 limitation, not a stub.
final class CockpitRecordedFlowConverter {
  /// Creates a CockpitRecordedFlowConverter.
  const CockpitRecordedFlowConverter();

  /// Converts [steps] into a [CockpitTestCase] identified by [caseId].
  ///
  /// Throws [ArgumentError] when no exportable step remains outside the
  /// `setup` segment: the case template requires at least one main step, so
  /// an empty main block cannot produce a valid document.
  CockpitTestCase convert({
    required String caseId,
    required List<CockpitInteractionStep> steps,
    String? name,
    String? sessionId,
  }) {
    final exportable = _exportableSteps(steps);
    final emitted = <(bool, CockpitTestStepTemplate)>[];
    var sequence = 0;
    String nextStepId() => 'st${sequence += 1}';

    for (var index = 0; index < exportable.length; index += 1) {
      final current = exportable[index];
      emitted.add((current.isSetup, _actionStep(nextStepId(), current)));
      final assertion = _weakAssertion(
        current: current,
        next: index + 1 < exportable.length ? exportable[index + 1] : null,
      );
      if (assertion != null) {
        emitted.add((current.isSetup, _step(assertion, stepId: nextStepId())));
      }
    }

    final setup = <CockpitTestStepTemplate>[
      for (final entry in emitted)
        if (entry.$1) entry.$2,
    ];
    final main = <CockpitTestStepTemplate>[
      for (final entry in emitted)
        if (!entry.$1) entry.$2,
    ];
    if (main.isEmpty) {
      throw ArgumentError.value(
        steps,
        'steps',
        'No exportable interaction step outside the setup segment; a case '
            'requires at least one main step.',
      );
    }
    return CockpitTestCase(
      id: caseId,
      name: name,
      target: CockpitTestTargetRequirements(
        platform: 'flutter',
        targetKind: 'flutterApp',
        plane: CockpitTestPlane.semantic,
      ),
      setup: setup,
      steps: main,
      extensions: <String, Object?>{
        'x-cockpit-origin': 'recorded',
        'x-cockpit-recorder-session': ?sessionId,
      },
    );
  }

  List<_ExportableStep> _exportableSteps(List<CockpitInteractionStep> steps) {
    return <_ExportableStep>[for (final step in steps) ?_exportableEntry(step)];
  }

  _ExportableStep? _exportableEntry(CockpitInteractionStep step) {
    if (step.unresolved) {
      return null;
    }
    final isSetup = step.segments.contains('setup');
    switch (step.kind) {
      case CockpitInteractionStepKind.marker || CockpitInteractionStepKind.note:
        return null;
      case CockpitInteractionStepKind.routeChange:
        if (step.routeName == null) {
          return null;
        }
        return _ExportableStep(step, null, isSetup: isSetup);
      case CockpitInteractionStepKind.back:
        return _ExportableStep(step, null, isSetup: isSetup);
      case CockpitInteractionStepKind.text:
        // Empty values carry nothing to type; the capture layer never
        // records them, but the model does not promise it.
        final value = step.resolvedValue;
        if (value == null || value.isEmpty) {
          return null;
        }
        return _ExportableStep(
          step,
          _locator(step.locatorCandidates),
          isSetup: isSetup,
        );
      case CockpitInteractionStepKind.scroll:
        final direction = step.scrollDirection;
        if (direction == null) {
          return null;
        }
        final locator = _locator(step.locatorCandidates);
        // tap/longPress/scroll all require a locator at the action level;
        // without a representable one the step cannot replay.
        return locator == null
            ? null
            : _ExportableStep(step, locator, isSetup: isSetup);
      case CockpitInteractionStepKind.tap ||
          CockpitInteractionStepKind.longPress:
        final locator = _locator(step.locatorCandidates);
        return locator == null
            ? null
            : _ExportableStep(step, locator, isSetup: isSetup);
    }
  }

  CockpitTestStepTemplate _actionStep(String stepId, _ExportableStep entry) {
    final step = entry.step;
    return _step(switch (step.kind) {
      CockpitInteractionStepKind.tap => CockpitTestActionTemplate(
        kind: CockpitTestActionKind.tap,
        locator: entry.locator,
      ),
      CockpitInteractionStepKind.longPress => CockpitTestActionTemplate(
        kind: CockpitTestActionKind.longPress,
        locator: entry.locator,
      ),
      CockpitInteractionStepKind.text => CockpitTestActionTemplate(
        kind: CockpitTestActionKind.enterText,
        locator: entry.locator,
        values: <CockpitTestActionField, CockpitTestTemplateValue>{
          CockpitTestActionField.text: _string(step.resolvedValue)!,
        },
      ),
      CockpitInteractionStepKind.scroll => CockpitTestActionTemplate(
        kind: CockpitTestActionKind.scrollUntilVisible,
        locator: entry.locator,
        values: <CockpitTestActionField, CockpitTestTemplateValue>{
          CockpitTestActionField.direction: _string(
            step.scrollDirection!.name,
          )!,
        },
      ),
      CockpitInteractionStepKind.routeChange => CockpitTestActionTemplate(
        kind: CockpitTestActionKind.waitFor,
        condition: CockpitTestConditionTemplate(
          kind: CockpitTestConditionKind.route,
          route: _string(step.routeName),
        ),
      ),
      CockpitInteractionStepKind.back => CockpitTestActionTemplate(
        kind: CockpitTestActionKind.back,
      ),
      CockpitInteractionStepKind.marker ||
      CockpitInteractionStepKind.note => throw StateError(
        'Unreachable: marker and note steps are filtered before emission.',
      ),
    }, stepId: stepId);
  }

  /// The weak assertion emitted after [current]: a visible wait on the next
  /// step's locator, or — for the last exported step — on its own.
  CockpitTestActionTemplate? _weakAssertion({
    required _ExportableStep current,
    required _ExportableStep? next,
  }) {
    if (current.step.kind == CockpitInteractionStepKind.routeChange) {
      // The route wait is the step itself.
      return null;
    }
    CockpitTestLocatorTemplate? target;
    if (next == null) {
      target = current.locator;
    } else if (next.step.kind != CockpitInteractionStepKind.routeChange &&
        next.step.kind != CockpitInteractionStepKind.back) {
      // A following routeChange/back step is itself the transition wait.
      target = next.locator;
    }
    if (target == null) {
      return null;
    }
    return CockpitTestActionTemplate(
      kind: CockpitTestActionKind.waitFor,
      condition: CockpitTestConditionTemplate(
        kind: CockpitTestConditionKind.visible,
        locator: target,
      ),
    );
  }

  CockpitTestStepTemplate _step(
    CockpitTestActionTemplate action, {
    required String stepId,
  }) => CockpitTestStepTemplate(
    stepId: stepId,
    operation: CockpitTestActionOperationTemplate(action),
  );

  /// Builds the locator chain from ordered candidates: the first
  /// representable candidate is primary, the rest are its fallbacks.
  CockpitTestLocatorTemplate? _locator(
    List<CockpitLocatorCandidate> candidates,
  ) {
    final mapped = <CockpitTestLocatorTemplate?>[
      for (final candidate in candidates)
        _locatorFromSelector(candidate.selector),
    ].whereType<CockpitTestLocatorTemplate>().toList(growable: false);
    if (mapped.isEmpty) {
      return null;
    }
    final primary = mapped.first;
    return CockpitTestLocatorTemplate(
      text: primary.text,
      label: primary.label,
      nativeId: primary.nativeId,
      testId: primary.testId,
      role: primary.role,
      type: primary.type,
      path: primary.path,
      fallbacks: mapped.skip(1).toList(growable: false),
    );
  }

  /// Maps one candidate selector to a locator template. Selectors recorded
  /// by the matcher are always single-signal `CockpitSelector.format`
  /// output, so the parsed locator maps to exactly one template field.
  /// Signals without a document slot (`semanticId` and other runtime-only
  /// kinds) yield `null`.
  CockpitTestLocatorTemplate? _locatorFromSelector(String selector) {
    final locator = CockpitSelector.parse(selector);
    String? text;
    String? label;
    String? nativeId;
    String? testId;
    String? role;
    String? type;
    String? path;
    var representable = false;
    for (final signal in locator.signals) {
      switch (signal.kind) {
        case CockpitLocatorKind.text:
          text = signal.value;
          representable = true;
        case CockpitLocatorKind.tooltip:
          label = signal.value;
          representable = true;
        case CockpitLocatorKind.nativeId:
          nativeId = signal.value;
          representable = true;
        case CockpitLocatorKind.key ||
            CockpitLocatorKind.cockpitId ||
            CockpitLocatorKind.testId:
          testId = signal.value;
          representable = true;
        case CockpitLocatorKind.role:
          role = signal.value;
          representable = true;
        case CockpitLocatorKind.type:
          type = signal.value;
          representable = true;
        case CockpitLocatorKind.path:
          path = signal.value;
          representable = true;
        case CockpitLocatorKind.semanticId ||
            CockpitLocatorKind.ref ||
            CockpitLocatorKind.route ||
            CockpitLocatorKind.registrationId ||
            CockpitLocatorKind.coordinate ||
            CockpitLocatorKind.visual:
          break;
      }
    }
    if (!representable) {
      return null;
    }
    return CockpitTestLocatorTemplate(
      text: _string(text),
      label: _string(label),
      nativeId: _string(nativeId),
      testId: _string(testId),
      role: _string(role),
      type: _string(type),
      path: _string(path),
    );
  }
}
