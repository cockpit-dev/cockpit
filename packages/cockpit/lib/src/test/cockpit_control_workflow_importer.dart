import 'dart:convert';
import 'dart:math' as math;

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:crypto/crypto.dart';

import '../cli/cockpit_control_script.dart';
import '../runner/cockpit_workflow_step.dart';

final class CockpitControlWorkflowImportException implements Exception {
  const CockpitControlWorkflowImportException(this.error);

  final CockpitTestError error;

  @override
  String toString() =>
      'CockpitControlWorkflowImportException: ${error.message}';
}

final class CockpitControlWorkflowImporter {
  const CockpitControlWorkflowImporter();

  CockpitTestImportResult import(CockpitTestImportRequest request) {
    CockpitControlScript source;
    try {
      final sourceJson = cockpitScriptMapFromText(request.sourceText);
      _validateLegacyScriptShape(sourceJson);
      source = CockpitControlScript.fromJson(sourceJson);
    } catch (_) {
      throw _migrationError('The 1.x control script is invalid.');
    }
    if (source.schemaVersion != request.sourceVersion) {
      throw _migrationError(
        'The source schema version does not match request.',
      );
    }
    try {
      if (source.environment != null &&
          source.environment!.platform != source.platform) {
        throw _migrationError(
          'Legacy environment platform does not match the script platform.',
        );
      }
      _validateImportedStepIds(
        source.effectiveWorkflowSteps,
        hasDocumentRecording: source.recording != null,
      );
      final mappings = <CockpitTestImportMapping>[];
      final setup = <CockpitTestStepTemplate>[];
      final finallySteps = <CockpitTestStepTemplate>[];
      if (source.recording != null) {
        setup.add(
          _startRecordingStep(
            source.recording!,
            stepId: 'importedRecordingStart',
          ),
        );
        finallySteps.add(
          CockpitTestStepTemplate(
            stepId: 'importedRecordingStop',
            operation: CockpitTestStopRecordingOperationTemplate(
              settleMs: source.recording!.tailStabilizationDelay.inMilliseconds,
            ),
          ),
        );
        mappings.add(
          CockpitTestImportMapping(
            sourcePath: r'$.recording',
            destinationPath: r'$.setup[0].startRecording',
          ),
        );
      }
      final steps = <CockpitTestStepTemplate>[];
      final sourceStepBase = source.workflowSteps.isNotEmpty
          ? r'$.steps'
          : r'$.commands';
      for (
        var index = 0;
        index < source.effectiveWorkflowSteps.length;
        index++
      ) {
        final sourcePath = '$sourceStepBase[$index]';
        final destinationPath = '\$.steps[$index]';
        steps.add(
          _step(
            source.effectiveWorkflowSteps[index],
            sourcePath: sourcePath,
            destinationPath: destinationPath,
            mappings: mappings,
          ),
        );
      }
      final testCase = CockpitTestCase(
        id: request.caseId,
        name: 'Imported ${request.caseId}',
        description: 'Imported from Cockpit control schema version 1.',
        target: CockpitTestTargetRequirements(
          platform: source.platform,
          targetKind: 'flutterApp',
          plane: CockpitTestPlane.semantic,
        ),
        defaults: CockpitTestCaseDefaults(failFast: source.failFast),
        setup: setup,
        steps: steps,
        finallySteps: finallySteps,
      );
      final manifest = CockpitTestImportManifest(
        sourceVersion: request.sourceVersion,
        sourceSha256: sha256
            .convert(utf8.encode(request.sourceText))
            .toString(),
        projectId: request.projectId,
        workspaceId: request.workspaceId,
        caseId: request.caseId,
        engineVersion: request.engineVersion,
        mappings: mappings,
        warnings: <String>[
          'Legacy sessionId and taskId were intentionally discarded.',
          if (source.environment != null)
            'Legacy Flutter and Dart version observations were not converted '
                'into target requirements.',
        ],
      );
      return CockpitTestImportResult(testCase: testCase, manifest: manifest);
    } on CockpitControlWorkflowImportException {
      rethrow;
    } on FormatException {
      throw _migrationError(
        'The legacy script contains a value that is invalid in V2.',
      );
    } on ArgumentError {
      throw _migrationError(
        'The legacy script requests behavior that is not representable in V2.',
      );
    }
  }
}

void _validateLegacyScriptShape(Map<String, Object?> json) {
  _requireLegacyKeys(json, r'$', const <String>{
    'schemaVersion',
    'sessionId',
    'taskId',
    'platform',
    'environment',
    'recording',
    'commands',
    'steps',
    'failFast',
  });
  if (json.containsKey('commands') && json.containsKey('steps')) {
    throw const FormatException(
      'Legacy script cannot contain both commands and steps.',
    );
  }
  if (json['environment'] != null) {
    _validateLegacyEnvironment(json['environment'], r'$.environment');
  }
  if (json['recording'] != null) {
    _validateLegacyRecording(json['recording'], r'$.recording');
  }
  if (json['commands'] case final List<Object?> commands) {
    for (var index = 0; index < commands.length; index += 1) {
      _validateLegacyCommand(commands[index], '\$.commands[$index]');
    }
  }
  if (json['steps'] case final List<Object?> steps) {
    _validateLegacySteps(steps, r'$.steps');
  }
}

void _validateLegacySteps(List<Object?> steps, String path) {
  for (var index = 0; index < steps.length; index += 1) {
    final stepPath = '$path[$index]';
    final step = _legacyMap(steps[index], stepPath);
    final hasStepType = step.containsKey('stepType');
    final hasType = step.containsKey('type');
    if (hasStepType == hasType) {
      throw FormatException(
        'Legacy step must define exactly one type field at $stepPath.',
      );
    }
    final type = step[hasStepType ? 'stepType' : 'type'];
    if (type is! String) {
      throw FormatException('Legacy step type must be a string at $stepPath.');
    }
    final operationFields = switch (type) {
      'command' => const <String>{'command'},
      'startRecording' => const <String>{'recording'},
      'stopRecording' => const <String>{'settleMs'},
      'if' => const <String>{'condition', 'thenSteps', 'elseSteps'},
      'loop' => const <String>{'maxIterations', 'condition', 'steps'},
      'retry' => const <String>{'maxAttempts', 'delayMs', 'step'},
      _ => throw FormatException('Unsupported legacy step type at $stepPath.'),
    };
    _requireLegacyKeys(step, stepPath, <String>{
      'stepId',
      if (hasStepType) 'stepType' else 'type',
      'description',
      ...operationFields,
    });
    switch (type) {
      case 'command':
        _validateLegacyCommand(step['command'], '$stepPath.command');
      case 'if':
        _validateLegacyCommand(step['condition'], '$stepPath.condition');
        _validateLegacySteps(
          _legacyList(step['thenSteps'], '$stepPath.thenSteps'),
          '$stepPath.thenSteps',
        );
        if (step['elseSteps'] != null) {
          _validateLegacySteps(
            _legacyList(step['elseSteps'], '$stepPath.elseSteps'),
            '$stepPath.elseSteps',
          );
        }
      case 'loop':
        _validateLegacyCommand(step['condition'], '$stepPath.condition');
        _validateLegacySteps(
          _legacyList(step['steps'], '$stepPath.steps'),
          '$stepPath.steps',
        );
      case 'retry':
        _validateLegacySteps(<Object?>[step['step']], '$stepPath.retry');
      case 'startRecording':
        _validateLegacyRecording(step['recording'], '$stepPath.recording');
      case 'stopRecording':
        break;
    }
  }
}

void _validateLegacyCommand(Object? value, String path) {
  final command = _legacyMap(value, path);
  _requireLegacyKeys(command, path, const <String>{
    'commandId',
    'commandType',
    'locator',
    'parameters',
    'capturePolicy',
    'captureFailurePolicy',
    'timeoutMs',
    'snapshotOptions',
    'screenshotRequest',
  });
  if (command['locator'] != null) {
    _validateLegacyLocator(command['locator'], '$path.locator');
  }
  if (command['snapshotOptions'] != null) {
    _validateLegacySnapshotOptions(
      command['snapshotOptions'],
      '$path.snapshotOptions',
    );
  }
  if (command['screenshotRequest'] != null) {
    _validateLegacyScreenshotRequest(
      command['screenshotRequest'],
      '$path.screenshotRequest',
    );
  }
}

void _validateLegacyEnvironment(Object? value, String path) {
  _requireLegacyKeys(_legacyMap(value, path), path, const <String>{
    'platform',
    'flutterVersion',
    'dartVersion',
  });
}

void _validateLegacyRecording(Object? value, String path) {
  _requireLegacyKeys(_legacyMap(value, path), path, const <String>{
    'purpose',
    'name',
    'mode',
    'layer',
    'allowFallback',
    'attachToStep',
    'tailStabilizationMs',
  });
}

void _validateLegacyScreenshotRequest(Object? value, String path) {
  final request = _legacyMap(value, path);
  _requireLegacyKeys(request, path, const <String>{
    'reason',
    'name',
    'includeSnapshot',
    'attachToStep',
    'snapshotOptions',
    'profile',
    'allowFallback',
  });
  if (request['snapshotOptions'] != null) {
    _validateLegacySnapshotOptions(
      request['snapshotOptions'],
      '$path.snapshotOptions',
    );
  }
}

void _validateLegacySnapshotOptions(Object? value, String path) {
  final options = _legacyMap(value, path);
  _requireLegacyKeys(options, path, const <String>{
    'profile',
    'maxTargets',
    'maxAncestorsPerTarget',
    'maxPropertiesPerTarget',
    'includeStyleDetails',
    'includeDiagnosticProperties',
    'emitArtifactWhenLarge',
    'includeRebuildActivity',
    'maxRebuildEntries',
    'includeNetworkActivity',
    'maxNetworkEntries',
    'networkQuery',
    'includeRuntimeActivity',
    'maxRuntimeEntries',
    'runtimeQuery',
    'includeAccessibilitySummary',
    'maxAccessibilityEntries',
  });
  if (options['networkQuery'] != null) {
    final queryPath = '$path.networkQuery';
    _requireLegacyKeys(
      _legacyMap(options['networkQuery'], queryPath),
      queryPath,
      const <String>{
        'method',
        'uriContains',
        'onlyFailures',
        'statusCodeAtLeast',
      },
    );
  }
  if (options['runtimeQuery'] != null) {
    final queryPath = '$path.runtimeQuery';
    _requireLegacyKeys(
      _legacyMap(options['runtimeQuery'], queryPath),
      queryPath,
      const <String>{'onlyErrors', 'messageContains'},
    );
  }
}

void _validateLegacyLocator(Object? value, String path) {
  final locator = _legacyMap(value, path);
  _requireLegacyKeys(locator, path, const <String>{
    'cockpitId',
    'semanticId',
    'key',
    'text',
    'tooltip',
    'type',
    'route',
    'registrationId',
    'path',
    'index',
    'ancestor',
    'fallbacks',
  });
  if (locator['ancestor'] != null) {
    _validateLegacyLocator(locator['ancestor'], '$path.ancestor');
  }
  if (locator['fallbacks'] case final List<Object?> fallbacks) {
    for (var index = 0; index < fallbacks.length; index += 1) {
      _validateLegacyLocator(fallbacks[index], '$path.fallbacks[$index]');
    }
  }
}

Map<String, Object?> _legacyMap(Object? value, String path) {
  if (value is! Map<Object?, Object?>) {
    throw FormatException('Expected legacy object at $path.');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('Expected legacy string key at $path.');
    }
    result[entry.key! as String] = entry.value;
  }
  return result;
}

List<Object?> _legacyList(Object? value, String path) {
  if (value is! List<Object?>) {
    throw FormatException('Expected legacy list at $path.');
  }
  return value;
}

void _requireLegacyKeys(
  Map<String, Object?> json,
  String path,
  Set<String> allowed,
) {
  final unknown = json.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw FormatException('Unsupported legacy field $path.${unknown.first}.');
  }
}

void _validateImportedStepIds(
  List<CockpitWorkflowStep> steps, {
  required bool hasDocumentRecording,
}) {
  final sourceById = <String, String>{};

  void add(String sourceId, String path) {
    final imported = _importId(sourceId);
    final existing = sourceById[imported];
    if (existing != null) {
      throw _migrationError(
        'Legacy step ids at $existing and $path both normalize to '
        '"$imported". Rename one before importing.',
      );
    }
    sourceById[imported] = path;
  }

  void walk(List<CockpitWorkflowStep> nested, String base) {
    for (var index = 0; index < nested.length; index += 1) {
      final step = nested[index];
      final path = '$base[$index]';
      add(step.stepId, '$path.stepId');
      switch (step) {
        case CockpitIfWorkflowStep(:final thenSteps, :final elseSteps):
          walk(thenSteps, '$path.thenSteps');
          walk(elseSteps, '$path.elseSteps');
        case CockpitLoopWorkflowStep(:final steps):
          walk(steps, '$path.steps');
        case CockpitRetryWorkflowStep(:final step):
          walk(<CockpitWorkflowStep>[step], '$path.retryStep');
        case CockpitCommandWorkflowStep() ||
            CockpitStartRecordingWorkflowStep() ||
            CockpitStopRecordingWorkflowStep():
          break;
      }
    }
  }

  if (hasDocumentRecording) {
    add('importedRecordingStart', r'$.recording.start');
    add('importedRecordingStop', r'$.recording.stop');
  }
  walk(steps, r'$.steps');
}

CockpitTestStepTemplate _step(
  CockpitWorkflowStep source, {
  required String sourcePath,
  required String destinationPath,
  required List<CockpitTestImportMapping> mappings,
}) {
  mappings.add(
    CockpitTestImportMapping(
      sourcePath: sourcePath,
      destinationPath: destinationPath,
    ),
  );
  final common = (
    stepId: _importId(source.stepId),
    description: source.description,
  );
  return switch (source) {
    CockpitCommandWorkflowStep(:final command) => CockpitTestStepTemplate(
      stepId: common.stepId,
      description: common.description,
      timeoutMs: command.timeoutMs,
      evidence: _evidence(command.capturePolicy, command.captureFailurePolicy),
      operation: CockpitTestActionOperationTemplate(
        _action(command, path: '$sourcePath.command'),
      ),
    ),
    CockpitStartRecordingWorkflowStep(:final recording) => _startRecordingStep(
      recording,
      stepId: common.stepId,
      description: common.description,
    ),
    CockpitStopRecordingWorkflowStep(:final settleDelay) =>
      CockpitTestStepTemplate(
        stepId: common.stepId,
        description: common.description,
        operation: CockpitTestStopRecordingOperationTemplate(
          settleMs: settleDelay.inMilliseconds,
        ),
      ),
    CockpitIfWorkflowStep(
      :final condition,
      :final thenSteps,
      :final elseSteps,
    ) =>
      CockpitTestStepTemplate(
        stepId: common.stepId,
        description: common.description,
        operation: CockpitTestIfOperationTemplate(
          condition: _condition(condition, path: '$sourcePath.condition'),
          thenSteps: <CockpitTestStepTemplate>[
            for (var index = 0; index < thenSteps.length; index++)
              _step(
                thenSteps[index],
                sourcePath: '$sourcePath.thenSteps[$index]',
                destinationPath: '$destinationPath.if.then[$index]',
                mappings: mappings,
              ),
          ],
          elseSteps: <CockpitTestStepTemplate>[
            for (var index = 0; index < elseSteps.length; index++)
              _step(
                elseSteps[index],
                sourcePath: '$sourcePath.elseSteps[$index]',
                destinationPath: '$destinationPath.if.else[$index]',
                mappings: mappings,
              ),
          ],
        ),
      ),
    CockpitLoopWorkflowStep(
      :final maxIterations,
      :final condition,
      :final steps,
    ) =>
      CockpitTestStepTemplate(
        stepId: common.stepId,
        description: common.description,
        operation: CockpitTestLoopOperationTemplate(
          maxIterations: maxIterations,
          condition: _condition(condition, path: '$sourcePath.condition'),
          steps: <CockpitTestStepTemplate>[
            for (var index = 0; index < steps.length; index++)
              _step(
                steps[index],
                sourcePath: '$sourcePath.steps[$index]',
                destinationPath: '$destinationPath.loop.steps[$index]',
                mappings: mappings,
              ),
          ],
        ),
      ),
    CockpitRetryWorkflowStep(:final maxAttempts, :final delayMs, :final step) =>
      CockpitTestStepTemplate(
        stepId: common.stepId,
        description: common.description,
        operation: CockpitTestRetryOperationTemplate(
          maxAttempts: maxAttempts,
          delayMs: delayMs,
          steps: <CockpitTestStepTemplate>[
            _step(
              step,
              sourcePath: '$sourcePath.step',
              destinationPath: '$destinationPath.retry.steps[0]',
              mappings: mappings,
            ),
          ],
        ),
      ),
  };
}

CockpitTestActionTemplate _action(
  CockpitCommand command, {
  required String path,
}) {
  final kind = CockpitTestActionKind.values.firstWhere(
    (candidate) => candidate.name == command.commandType.name,
    orElse: () => throw _migrationError(
      'Command ${command.commandType.name} is not representable in V2.',
    ),
  );
  final parameters = Map<String, Object?>.from(command.parameters);
  final values = <CockpitTestActionField, CockpitTestTemplateValue>{};
  void take(CockpitTestActionField field, [String? sourceName]) {
    final name = sourceName ?? field.wireName;
    if (!parameters.containsKey(name)) return;
    values[field] = CockpitTestTemplateValue.literal(
      parameters.remove(name),
      expectedType: field.valueType,
    );
  }

  CockpitTestConditionTemplate? condition;
  switch (kind) {
    case CockpitTestActionKind.tap:
      take(CockpitTestActionField.activation);
    case CockpitTestActionKind.longPress:
      take(CockpitTestActionField.durationMs);
    case CockpitTestActionKind.doubleTap ||
        CockpitTestActionKind.focusTextInput ||
        CockpitTestActionKind.back ||
        CockpitTestActionKind.increase ||
        CockpitTestActionKind.decrease ||
        CockpitTestActionKind.dismiss ||
        CockpitTestActionKind.dismissKeyboard ||
        CockpitTestActionKind.clearNetworkActivity:
      break;
    case CockpitTestActionKind.enterText:
      take(CockpitTestActionField.text);
    case CockpitTestActionKind.eraseText:
      take(CockpitTestActionField.characters);
    case CockpitTestActionKind.copyText || CockpitTestActionKind.pasteText:
      break;
    case CockpitTestActionKind.setTextEditingValue:
      take(CockpitTestActionField.text);
      take(CockpitTestActionField.selectionStart, 'selectionBase');
      take(CockpitTestActionField.selectionEnd, 'selectionExtent');
      if (parameters.remove('requestFocus') == false ||
          parameters.remove('clearExisting') == true) {
        throw _migrationError(
          'setTextEditingValue focus/clear flags require manual migration.',
        );
      }
    case CockpitTestActionKind.sendTextInputAction:
      take(CockpitTestActionField.inputAction);
      if (parameters.containsKey('requestFocus') &&
          parameters.remove('requestFocus') != true) {
        throw _migrationError(
          'sendTextInputAction requestFocus=false is not representable at '
          '$path.',
        );
      }
    case CockpitTestActionKind.sendKeyEvent ||
        CockpitTestActionKind.sendKeyDownEvent ||
        CockpitTestActionKind.sendKeyUpEvent:
      final keyRequest = <String, Object?>{};
      for (final key in const <String>{
        'logicalKey',
        'physicalKey',
        'character',
      }) {
        if (parameters.containsKey(key)) {
          keyRequest[key] = parameters.remove(key);
        }
      }
      values[CockpitTestActionField.keyRequest] =
          CockpitTestTemplateValue.literal(
            keyRequest,
            expectedType: CockpitTestValueType.json,
          );
    case CockpitTestActionKind.drag:
      take(CockpitTestActionField.dx);
      take(CockpitTestActionField.dy);
      take(CockpitTestActionField.durationMs);
    case CockpitTestActionKind.fling:
      take(CockpitTestActionField.dx);
      take(CockpitTestActionField.dy);
      final durationMs = (parameters.remove('durationMs') as int?) ?? 96;
      final dx = (values[CockpitTestActionField.dx]!.value! as num).toDouble();
      final dy = (values[CockpitTestActionField.dy]!.value! as num).toDouble();
      final velocity = math.sqrt(dx * dx + dy * dy) / durationMs * 1000;
      values[CockpitTestActionField.velocity] =
          CockpitTestTemplateValue.literal(
            velocity,
            expectedType: CockpitTestValueType.number,
          );
    case CockpitTestActionKind.swipe:
      take(CockpitTestActionField.direction);
      take(CockpitTestActionField.distance, 'distanceFactor');
      values.putIfAbsent(
        CockpitTestActionField.distance,
        () => CockpitTestTemplateValue.literal(
          0.82,
          expectedType: CockpitTestValueType.number,
        ),
      );
      take(CockpitTestActionField.durationMs);
    case CockpitTestActionKind.pinchZoom:
      take(CockpitTestActionField.scale);
    case CockpitTestActionKind.rotate:
      take(CockpitTestActionField.rotationRadians);
    case CockpitTestActionKind.panZoom:
      take(CockpitTestActionField.panDx);
      take(CockpitTestActionField.panDy);
      take(CockpitTestActionField.scale);
      take(CockpitTestActionField.rotationRadians);
    case CockpitTestActionKind.multiTouch:
      take(CockpitTestActionField.sequence);
    case CockpitTestActionKind.scrollUntilVisible:
      final reverse = parameters.remove('reverse') == true;
      final rawDirection = parameters.remove('direction');
      values[CockpitTestActionField.direction] =
          CockpitTestTemplateValue.literal(
            rawDirection ?? (reverse ? 'up' : 'down'),
            expectedType: CockpitTestValueType.string,
          );
      take(CockpitTestActionField.maxScrolls);
      take(CockpitTestActionField.durationMs, 'durationPerStepMs');
      take(CockpitTestActionField.revealAlignment);
    case CockpitTestActionKind.showOnScreen:
      take(CockpitTestActionField.revealAlignment);
    case CockpitTestActionKind.waitForNetworkIdle ||
        CockpitTestActionKind.waitForUiIdle:
      take(CockpitTestActionField.quietMs);
    case CockpitTestActionKind.waitFor:
      condition = _condition(command, path: path);
      parameters.clear();
    case CockpitTestActionKind.assertVisible:
      values[CockpitTestActionField.expected] =
          CockpitTestTemplateValue.literal(
            true,
            expectedType: CockpitTestValueType.boolean,
          );
    case CockpitTestActionKind.assertText:
      take(CockpitTestActionField.text);
    case CockpitTestActionKind.assertScreenshot:
      take(CockpitTestActionField.baseline);
      take(CockpitTestActionField.similarity);
      take(CockpitTestActionField.artifactName);
    case CockpitTestActionKind.travel:
      take(CockpitTestActionField.route);
      take(CockpitTestActionField.intervalMs);
    case CockpitTestActionKind.system:
      take(CockpitTestActionField.systemName, 'action');
      take(CockpitTestActionField.systemParameters, 'parameters');
    case CockpitTestActionKind.captureScreenshot:
      final request = command.screenshotRequest;
      final captureOptions = <String, Object?>{};
      String artifactName;
      if (request == null) {
        artifactName =
            _removeOptionalString(parameters, 'name', path) ??
            command.commandId;
        final reasonValue = _removeCaptureReason(parameters, path);
        if (reasonValue != null && reasonValue != 'acceptance') {
          captureOptions['reason'] = reasonValue;
        }
        final includeSnapshot = _removeOptionalBool(
          parameters,
          'includeSnapshot',
          path,
        );
        if (includeSnapshot != null) {
          captureOptions['includeSnapshot'] = includeSnapshot;
        }
        final attachToStep = _removeOptionalBool(
          parameters,
          'attachToStep',
          path,
        );
        if (attachToStep != null) {
          captureOptions['attachToStep'] = attachToStep;
        }
        if (command.snapshotOptions != null) {
          captureOptions['snapshotOptions'] = command.snapshotOptions!.toJson();
        }
      } else {
        artifactName = request.name;
        if (request.reason != CockpitScreenshotReason.acceptance) {
          captureOptions['reason'] = request.reason.jsonValue;
        }
        if (request.includeSnapshot) {
          captureOptions['includeSnapshot'] = true;
        }
        if (!request.attachToStep) {
          captureOptions['attachToStep'] = false;
        }
        if (request.snapshotOptions != null) {
          captureOptions['snapshotOptions'] = request.snapshotOptions!.toJson();
        }
        if (request.profile != null) {
          captureOptions['profile'] = request.profile!.name;
        }
        if (request.allowFallback != null) {
          captureOptions['allowFallback'] = request.allowFallback;
        }
      }
      values[CockpitTestActionField.artifactName] =
          CockpitTestTemplateValue.literal(
            artifactName,
            expectedType: CockpitTestValueType.string,
          );
      if (captureOptions.isNotEmpty) {
        values[CockpitTestActionField.captureOptions] =
            CockpitTestTemplateValue.literal(
              captureOptions,
              expectedType: CockpitTestValueType.json,
            );
      }
    case CockpitTestActionKind.collectSnapshot:
      if (command.snapshotOptions != null) {
        values[CockpitTestActionField.snapshotOptions] =
            CockpitTestTemplateValue.literal(
              command.snapshotOptions!.toJson(),
              expectedType: CockpitTestValueType.json,
            );
      }
  }
  if (parameters.isNotEmpty) {
    throw _migrationError(
      'Command ${command.commandType.name} has unsupported parameters at '
      '$path: ${parameters.keys.join(', ')}.',
    );
  }
  return CockpitTestActionTemplate(
    kind: kind,
    locator: kind == CockpitTestActionKind.waitFor || command.locator == null
        ? null
        : _locator(command.locator!, path: '$path.locator'),
    condition: condition,
    values: values,
  );
}

CockpitTestStepTemplate _startRecordingStep(
  CockpitRecordingRequest recording, {
  required String stepId,
  String? description,
}) => CockpitTestStepTemplate(
  stepId: stepId,
  description: description,
  operation: CockpitTestStartRecordingOperationTemplate(
    name: recording.name,
    purpose: recording.purpose.name,
    mode: recording.mode.jsonValue,
    layer: recording.layer?.jsonValue,
    allowFallback: recording.allowFallback,
    attachToStep: recording.attachToStep,
  ),
);

CockpitTestEvidencePolicy _evidence(
  CockpitCapturePolicy capture,
  CockpitCaptureFailurePolicy failure,
) => CockpitTestEvidencePolicy(
  screenshot: switch (capture) {
    CockpitCapturePolicy.none => CockpitTestEvidenceMode.none,
    CockpitCapturePolicy.onFailure => CockpitTestEvidenceMode.onFailure,
    CockpitCapturePolicy.afterAction ||
    CockpitCapturePolicy.afterActionAndFailure =>
      CockpitTestEvidenceMode.always,
  },
  snapshot: CockpitTestEvidenceMode.none,
  failurePolicy: switch (failure) {
    CockpitCaptureFailurePolicy.failCommand =>
      CockpitTestEvidenceFailurePolicy.failStep,
    CockpitCaptureFailurePolicy.degradeCommand =>
      CockpitTestEvidenceFailurePolicy.recordWarning,
  },
);

void _requireNoParameters(
  Map<String, Object?> parameters,
  CockpitCommand command,
  String path,
) {
  if (parameters.isNotEmpty) {
    throw _migrationError(
      'Condition ${command.commandType.name} has unsupported parameters at '
      '$path: ${parameters.keys.join(', ')}.',
    );
  }
}

String? _removeOptionalString(
  Map<String, Object?> parameters,
  String name,
  String path,
) {
  if (!parameters.containsKey(name)) return null;
  final value = parameters.remove(name);
  if (value is! String || value.trim().isEmpty) {
    throw _migrationError('$name must be a non-empty string at $path.');
  }
  return value;
}

bool? _removeOptionalBool(
  Map<String, Object?> parameters,
  String name,
  String path,
) {
  if (!parameters.containsKey(name)) return null;
  final value = parameters.remove(name);
  if (value is! bool) {
    throw _migrationError('$name must be a boolean at $path.');
  }
  return value;
}

String? _removeCaptureReason(Map<String, Object?> parameters, String path) {
  final hasReason = parameters.containsKey('reason');
  final hasPurpose = parameters.containsKey('purpose');
  if (hasReason && hasPurpose) {
    throw _migrationError(
      'captureScreenshot cannot define both reason and purpose at $path.',
    );
  }
  final value = _removeOptionalString(
    parameters,
    hasReason ? 'reason' : 'purpose',
    path,
  );
  if (value == null) return null;
  final normalized = value.trim().toLowerCase();
  return switch (normalized) {
    'diagnostic' ||
    'diagnostics' ||
    'debug' ||
    'investigation' => 'assertion_failure',
    'baseline' ||
    'before_action' ||
    'after_action' ||
    'assertion_failure' ||
    'acceptance' => normalized,
    _ => throw _migrationError('Unsupported capture reason "$value" at $path.'),
  };
}

String _importId(String source) {
  var value = source.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  if (value.isEmpty || !RegExp(r'^[A-Za-z]').hasMatch(value)) {
    value = 'imported_$value';
  }
  if (value.length > 128) {
    final suffix = sha256
        .convert(utf8.encode(source))
        .toString()
        .substring(0, 12);
    value = '${value.substring(0, 115)}_$suffix';
  }
  return value;
}

CockpitControlWorkflowImportException _migrationError(String message) =>
    CockpitControlWorkflowImportException(
      CockpitTestError(
        code: CockpitTestErrorCode.validationFailed,
        message: message,
      ),
    );

CockpitTestConditionTemplate _condition(
  CockpitCommand command, {
  required String path,
}) {
  final parameters = Map<String, Object?>.from(command.parameters);
  switch (command.commandType) {
    case CockpitCommandType.assertVisible:
      _requireNoParameters(parameters, command, path);
      return CockpitTestConditionTemplate(
        kind: CockpitTestConditionKind.visible,
        locator: _requiredLocator(command, path),
      );
    case CockpitCommandType.assertText:
      final text = parameters.remove('text');
      final expected = text is String && text.trim().isNotEmpty
          ? text
          : command.locator?.text;
      if (expected == null) {
        throw _migrationError('assertText requires expected text at $path.');
      }
      _requireNoParameters(parameters, command, path);
      return CockpitTestConditionTemplate(
        kind: CockpitTestConditionKind.text,
        locator: command.locator == null
            ? CockpitTestLocatorTemplate(
                text: CockpitTestTemplateValue.literal(
                  expected,
                  expectedType: CockpitTestValueType.string,
                ),
              )
            : _locator(command.locator!, path: '$path.locator'),
        text: CockpitTestTemplateValue.literal(
          expected,
          expectedType: CockpitTestValueType.string,
        ),
        matchMode: CockpitTextMatchMode.exact,
      );
    case CockpitCommandType.waitFor:
      final absent = parameters.remove('absent') == true;
      final route =
          parameters.remove('routeName') ??
          parameters.remove('expectedRouteName') ??
          parameters.remove('route');
      final text = parameters.remove('text');
      if (parameters.containsKey('minVisibleTargets')) {
        throw _migrationError(
          'waitFor minVisibleTargets at $path is not representable in V2.',
        );
      }
      _requireNoParameters(parameters, command, path);
      if (route is String && route.trim().isNotEmpty) {
        if (command.locator != null || text != null || absent) {
          throw _migrationError('Ambiguous waitFor condition at $path.');
        }
        return CockpitTestConditionTemplate(
          kind: CockpitTestConditionKind.route,
          route: CockpitTestTemplateValue.literal(
            route,
            expectedType: CockpitTestValueType.string,
          ),
        );
      }
      if (text is String && text.trim().isNotEmpty) {
        final locator = command.locator ?? CockpitLocator(text: text);
        return CockpitTestConditionTemplate(
          kind: CockpitTestConditionKind.text,
          locator: _locator(locator, path: '$path.locator'),
          text: CockpitTestTemplateValue.literal(
            text,
            expectedType: CockpitTestValueType.string,
          ),
          matchMode: CockpitTextMatchMode.exact,
        );
      }
      return CockpitTestConditionTemplate(
        kind: CockpitTestConditionKind.visible,
        locator: _requiredLocator(command, path),
        expected: CockpitTestTemplateValue.literal(
          !absent,
          expectedType: CockpitTestValueType.boolean,
        ),
      );
    case CockpitCommandType.waitForUiIdle:
      final quietMs = parameters.remove('quietMs');
      _requireNoParameters(parameters, command, path);
      return CockpitTestConditionTemplate(
        kind: CockpitTestConditionKind.uiIdle,
        quietMs: quietMs == null
            ? null
            : CockpitTestTemplateValue.literal(
                quietMs,
                expectedType: CockpitTestValueType.integer,
              ),
      );
    case CockpitCommandType.waitForNetworkIdle:
      final quietMs = parameters.remove('quietMs');
      _requireNoParameters(parameters, command, path);
      return CockpitTestConditionTemplate(
        kind: CockpitTestConditionKind.networkIdle,
        quietMs: quietMs == null
            ? null
            : CockpitTestTemplateValue.literal(
                quietMs,
                expectedType: CockpitTestValueType.integer,
              ),
      );
    default:
      throw _migrationError(
        'Command ${command.commandType.name} cannot be used as a V2 condition.',
      );
  }
}

CockpitTestLocatorTemplate _requiredLocator(
  CockpitCommand command,
  String path,
) {
  final locator = command.locator;
  if (locator == null) {
    throw _migrationError(
      '${command.commandType.name} requires locator at $path.',
    );
  }
  return _locator(locator, path: '$path.locator');
}

CockpitTestLocatorTemplate _locator(
  CockpitLocator source, {
  required String path,
}) {
  final ancestor = source.ancestor == null
      ? null
      : _locator(source.ancestor!, path: '$path.ancestor');
  final signals = <CockpitTestLocatorStrategy, CockpitTestTemplateValue>{};
  for (final signal in source.signals) {
    final strategy = switch (signal.kind) {
      CockpitLocatorKind.cockpitId => CockpitTestLocatorStrategy.testId,
      CockpitLocatorKind.nativeId => CockpitTestLocatorStrategy.nativeId,
      CockpitLocatorKind.testId => CockpitTestLocatorStrategy.testId,
      CockpitLocatorKind.role => CockpitTestLocatorStrategy.role,
      CockpitLocatorKind.text => CockpitTestLocatorStrategy.text,
      CockpitLocatorKind.tooltip => CockpitTestLocatorStrategy.label,
      CockpitLocatorKind.type => CockpitTestLocatorStrategy.type,
      CockpitLocatorKind.path => CockpitTestLocatorStrategy.path,
      CockpitLocatorKind.semanticId ||
      CockpitLocatorKind.key ||
      CockpitLocatorKind.route ||
      CockpitLocatorKind.registrationId ||
      CockpitLocatorKind.coordinate ||
      CockpitLocatorKind.visual => throw _migrationError(
        'Locator ${signal.kind.name} at $path requires manual migration.',
      ),
    };
    signals[strategy] = CockpitTestTemplateValue.literal(
      signal.value,
      expectedType: CockpitTestValueType.string,
    );
  }
  if (signals.isEmpty) {
    throw _migrationError('Locator has no supported signal at $path.');
  }
  final fallbacks = <CockpitTestLocatorTemplate>[];
  for (var index = 0; index < source.fallbacks.length; index++) {
    fallbacks.add(
      _locator(source.fallbacks[index], path: '$path.fallbacks[$index]'),
    );
  }
  return CockpitTestLocatorTemplate(
    text: signals[CockpitTestLocatorStrategy.text],
    label: signals[CockpitTestLocatorStrategy.label],
    matchMode: source.matchMode == CockpitTextMatchMode.exact
        ? null
        : CockpitTestTemplateValue.literal(
            source.matchMode.name,
            expectedType: CockpitTestValueType.string,
          ),
    nativeId: signals[CockpitTestLocatorStrategy.nativeId],
    testId: signals[CockpitTestLocatorStrategy.testId],
    role: signals[CockpitTestLocatorStrategy.role],
    type: signals[CockpitTestLocatorStrategy.type],
    path: signals[CockpitTestLocatorStrategy.path],
    index: source.index == null
        ? null
        : CockpitTestTemplateValue.literal(
            source.index,
            expectedType: CockpitTestValueType.integer,
          ),
    ancestor: ancestor,
    fallbacks: fallbacks,
  );
}
