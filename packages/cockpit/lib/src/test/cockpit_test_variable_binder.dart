import 'dart:convert';
import 'dart:math';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'cockpit_test_document_compiler.dart';
import 'cockpit_test_execution_plan.dart';
import 'cockpit_test_secret_resolver.dart';

final class CockpitTestVariableBinder {
  CockpitTestVariableBinder({Random? secureRandom})
    : _random = secureRandom ?? Random.secure();

  final Random _random;

  CockpitTestExecutionPlan bind(
    CockpitCompiledTestCase compiled, {
    Map<String, Object?> inputs = const <String, Object?>{},
  }) {
    final testCase = compiled.testCase;
    final unknownInputs = inputs.keys.toSet().difference(
      testCase.variables.entries
          .where(
            (entry) => entry.value.source == CockpitTestVariableSource.input,
          )
          .map((entry) => entry.key)
          .toSet(),
    );
    if (unknownInputs.isNotEmpty) {
      throw _bindingError(
        'Unknown runtime input${unknownInputs.length == 1 ? '' : 's'}: '
        '${unknownInputs.join(', ')}.',
      );
    }

    final environment = <String, Object?>{};
    final secretReferences = <String, String>{};
    for (final entry in testCase.variables.entries) {
      final name = entry.key;
      final declaration = entry.value;
      switch (declaration.source) {
        case CockpitTestVariableSource.constant:
          environment[name] = declaration.value;
        case CockpitTestVariableSource.input:
          if (inputs.containsKey(name)) {
            environment[name] = _validateInput(
              inputs[name],
              declaration.valueType,
              name,
            );
          } else if (declaration.hasDefaultValue) {
            environment[name] = declaration.defaultValue;
          } else if (declaration.required) {
            throw _bindingError('Required runtime input $name is missing.');
          } else {
            environment[name] = null;
          }
        case CockpitTestVariableSource.secret:
          final token = _newSecretToken(secretReferences);
          secretReferences[token.value] = declaration.secretReference!;
          environment[name] = token;
      }
    }

    final context = _BindingContext(
      compiled: compiled,
      environment: environment,
      fragments: testCase.fragments,
    );
    final resolvedInputs = <String, Object?>{
      for (final entry in testCase.variables.entries)
        if (entry.value.source != CockpitTestVariableSource.secret)
          entry.key: cockpitTestCopyJsonValue(
            environment[entry.key],
            path: '\$.resolvedInputs.${entry.key}',
          ),
    };
    return CockpitTestExecutionPlan(
      caseId: testCase.id,
      sourceSha256: compiled.sourceSha256,
      target: testCase.target,
      defaults: testCase.defaults,
      setup: context.bindSteps(
        testCase.setup,
        sourceBase: r'$.setup',
        executionBase: 'setup',
        section: 'setup',
      ),
      steps: context.bindSteps(
        testCase.steps,
        sourceBase: r'$.steps',
        executionBase: 'main',
        section: 'main',
      ),
      finallySteps: context.bindSteps(
        testCase.finallySteps,
        sourceBase: r'$.finally',
        executionBase: 'finally',
        section: 'finally',
      ),
      resolvedInputs: resolvedInputs,
      secretBindings: CockpitTestSecretBindings(secretReferences),
    );
  }

  Object? _validateInput(
    Object? value,
    CockpitTestValueType type,
    String name,
  ) {
    try {
      return CockpitTestTemplateValue.literal(
        cockpitTestCopyJsonValue(value, path: r'$.inputs.' + name),
        expectedType: type,
      ).value;
    } on FormatException catch (error) {
      throw _bindingError('Input $name is invalid: ${error.message}');
    }
  }

  CockpitTestSecretToken _newSecretToken(Map<String, String> existing) {
    while (true) {
      final bytes = List<int>.generate(24, (_) => _random.nextInt(256));
      final value = base64Url.encode(bytes).replaceAll('=', '');
      if (!existing.containsKey(value)) {
        return CockpitTestSecretToken(value);
      }
    }
  }
}

CockpitTestBindingException _bindingError(String message) =>
    CockpitTestBindingException(
      CockpitTestError(
        code: CockpitTestErrorCode.bindingFailed,
        message: message,
      ),
    );

final class _BindingContext {
  const _BindingContext({
    required this.compiled,
    required this.environment,
    required this.fragments,
  });

  final CockpitCompiledTestCase compiled;
  final Map<String, Object?> environment;
  final Map<String, List<CockpitTestStepTemplate>> fragments;

  List<CockpitTestExecutionNode> bindSteps(
    List<CockpitTestStepTemplate> steps, {
    required String sourceBase,
    required String executionBase,
    required String section,
    List<String> callPath = const <String>[],
    CockpitTestPlane? inheritedPlane,
  }) {
    final result = <CockpitTestExecutionNode>[];
    for (var index = 0; index < steps.length; index += 1) {
      final step = steps[index];
      final plane = step.plane ?? inheritedPlane;
      final sourcePath = '$sourceBase[$index]';
      final operation = step.operation;
      if (operation is CockpitTestCallOperationTemplate) {
        final fragmentSteps = fragments[operation.fragment];
        if (fragmentSteps == null) {
          throw _bindingError('Fragment ${operation.fragment} is missing.');
        }
        result.addAll(
          bindSteps(
            fragmentSteps,
            sourceBase: _childPath(r'$.fragments', operation.fragment),
            executionBase:
                '$executionBase/${step.stepId}@${operation.fragment}',
            section: section,
            callPath: <String>[...callPath, step.stepId],
            inheritedPlane: plane,
          ),
        );
        continue;
      }
      final executionId = '$executionBase/${step.stepId}';
      result.add(
        CockpitTestExecutionNode(
          stepId: step.stepId,
          executionId: executionId,
          section: section,
          description: step.description,
          plane: plane,
          timeoutMs:
              step.timeoutMs ?? compiled.testCase.defaults.commandTimeoutMs,
          evidence: step.evidence ?? compiled.testCase.defaults.evidence,
          safety: step.safety ?? CockpitTestSafetyDeclaration(),
          sourcePath: sourcePath,
          sourceLocation: compiled.locationFor(sourcePath),
          callPath: callPath,
          operation: bindOperation(
            operation,
            sourcePath: sourcePath,
            executionBase: executionId,
            section: section,
            callPath: callPath,
            inheritedPlane: plane,
          ),
        ),
      );
    }
    return List<CockpitTestExecutionNode>.unmodifiable(result);
  }

  CockpitTestPlanOperation bindOperation(
    CockpitTestOperationTemplate operation, {
    required String sourcePath,
    required String executionBase,
    required String section,
    required List<String> callPath,
    required CockpitTestPlane? inheritedPlane,
  }) => switch (operation) {
    CockpitTestActionOperationTemplate(:final action) =>
      CockpitTestActionPlanOperation(bindAction(action)),
    CockpitTestStartRecordingOperationTemplate(
      :final name,
      :final purpose,
      :final mode,
      :final layer,
      :final allowFallback,
      :final attachToStep,
    ) =>
      CockpitTestStartRecordingPlanOperation(
        name: name,
        purpose: purpose,
        mode: mode,
        layer: layer,
        allowFallback: allowFallback,
        attachToStep: attachToStep,
      ),
    CockpitTestStopRecordingOperationTemplate(:final settleMs) =>
      CockpitTestStopRecordingPlanOperation(settleMs: settleMs),
    CockpitTestIfOperationTemplate(
      :final condition,
      :final thenSteps,
      :final elseSteps,
    ) =>
      CockpitTestIfPlanOperation(
        condition: bindCondition(condition),
        thenSteps: bindSteps(
          thenSteps,
          sourceBase: '$sourcePath.if.then',
          executionBase: '$executionBase/then',
          section: section,
          callPath: callPath,
          inheritedPlane: inheritedPlane,
        ),
        elseSteps: bindSteps(
          elseSteps,
          sourceBase: '$sourcePath.if.else',
          executionBase: '$executionBase/else',
          section: section,
          callPath: callPath,
          inheritedPlane: inheritedPlane,
        ),
      ),
    CockpitTestRetryOperationTemplate(
      :final maxAttempts,
      :final delayMs,
      :final steps,
    ) =>
      CockpitTestRetryPlanOperation(
        maxAttempts: maxAttempts,
        delayMs: delayMs,
        steps: bindSteps(
          steps,
          sourceBase: '$sourcePath.retry.steps',
          executionBase: '$executionBase/retry',
          section: section,
          callPath: callPath,
          inheritedPlane: inheritedPlane,
        ),
      ),
    CockpitTestLoopOperationTemplate(
      :final maxIterations,
      :final condition,
      :final steps,
    ) =>
      CockpitTestLoopPlanOperation(
        maxIterations: maxIterations,
        condition: bindCondition(condition),
        steps: bindSteps(
          steps,
          sourceBase: '$sourcePath.loop.steps',
          executionBase: '$executionBase/loop',
          section: section,
          callPath: callPath,
          inheritedPlane: inheritedPlane,
        ),
      ),
    CockpitTestCallOperationTemplate() => throw StateError(
      'Call operations must be expanded before operation binding.',
    ),
  };

  CockpitTestAction bindAction(CockpitTestActionTemplate template) {
    try {
      return CockpitTestAction(
        kind: template.kind,
        locator: template.locator == null
            ? null
            : bindLocator(template.locator!),
        condition: template.condition == null
            ? null
            : bindCondition(template.condition!),
        values: <CockpitTestActionField, Object?>{
          for (final entry in template.values.entries)
            entry.key: bindValue(entry.value),
        },
        extensions: template.extensions,
      );
    } on FormatException catch (error) {
      throw _bindingError(
        'Bound ${template.kind.name} action is invalid: ${error.message}',
      );
    }
  }

  CockpitTestCondition bindCondition(CockpitTestConditionTemplate template) {
    try {
      return CockpitTestCondition(
        kind: template.kind,
        locator: template.locator == null
            ? null
            : bindLocator(template.locator!),
        expected: bindValue(template.expected) as bool?,
        text: bindValue(template.text) as String?,
        matchMode: template.matchMode,
        route: bindValue(template.route) as String?,
        quietMs: bindValue(template.quietMs) as int?,
      );
    } on FormatException catch (error) {
      throw _bindingError(
        'Bound ${template.kind.name} condition is invalid: ${error.message}',
      );
    }
  }

  CockpitTestLocator bindLocator(CockpitTestLocatorTemplate template) {
    try {
      final x = bindValue(template.x);
      final y = bindValue(template.y);
      final threshold = bindValue(template.threshold);
      return CockpitTestLocator(
        text: bindValue(template.text) as String?,
        label: bindValue(template.label) as String?,
        matchMode: template.matchMode == null
            ? CockpitTextMatchMode.exact
            : CockpitTextMatchMode.fromJson(bindValue(template.matchMode)),
        nativeId: bindValue(template.nativeId) as String?,
        testId: bindValue(template.testId) as String?,
        role: bindValue(template.role) as String?,
        type: bindValue(template.type) as String?,
        path: bindValue(template.path) as String?,
        visual: bindValue(template.visual) as String?,
        x: (x as num?)?.toDouble(),
        y: (y as num?)?.toDouble(),
        threshold: (threshold as num?)?.toDouble(),
        index: bindValue(template.index) as int?,
        enabled: bindValue(template.enabled) as bool?,
        selected: bindValue(template.selected) as bool?,
        checked: bindValue(template.checked) as bool?,
        focused: bindValue(template.focused) as bool?,
        clickable: bindValue(template.clickable) as bool?,
        ancestor: template.ancestor == null
            ? null
            : bindLocator(template.ancestor!),
        child: template.child == null ? null : bindLocator(template.child!),
        descendant: template.descendant == null
            ? null
            : bindLocator(template.descendant!),
        above: template.above == null ? null : bindLocator(template.above!),
        below: template.below == null ? null : bindLocator(template.below!),
        leftOf: template.leftOf == null ? null : bindLocator(template.leftOf!),
        rightOf: template.rightOf == null
            ? null
            : bindLocator(template.rightOf!),
        fallbacks: template.fallbacks.map(bindLocator),
      );
    } on FormatException catch (error) {
      throw _bindingError('Bound locator is invalid: ${error.message}');
    }
  }

  Object? bindValue(CockpitTestTemplateValue? template) {
    if (template == null) {
      return null;
    }
    switch (template.kind) {
      case CockpitTestTemplateValueKind.literal:
        return template.value;
      case CockpitTestTemplateValueKind.variable:
        final name = template.variable!;
        if (!environment.containsKey(name)) {
          throw _bindingError('Variable $name is not available.');
        }
        return environment[name];
      case CockpitTestTemplateValueKind.stringTemplate:
        final source = template.value! as String;
        return source.replaceAllMapped(
          RegExp(r'\$\{([A-Za-z][A-Za-z0-9._-]{0,127})\}'),
          (match) {
            final name = match.group(1)!;
            final value = environment[name];
            if (value is! String) {
              throw _bindingError(
                'Interpolated variable $name is not a public string.',
              );
            }
            return value;
          },
        );
    }
  }
}

String _childPath(String parent, String key) {
  if (RegExp(r'^[A-Za-z_][A-Za-z0-9_-]*$').hasMatch(key)) {
    return '$parent.$key';
  }
  return '$parent[${jsonEncode(key)}]';
}
