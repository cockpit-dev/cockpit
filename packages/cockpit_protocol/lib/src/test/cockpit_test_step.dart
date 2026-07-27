import 'cockpit_test_action.dart';
import 'cockpit_test_condition.dart';
import 'cockpit_test_policy.dart';
import 'cockpit_test_value_reader.dart';

final class CockpitTestStepTemplate {
  CockpitTestStepTemplate({
    required this.stepId,
    this.description,
    this.plane,
    this.timeoutMs,
    this.evidence,
    this.safety,
    required this.operation,
    Map<String, Object?> extensions = const <String, Object?>{},
  }) : extensions = CockpitTestValueReader.extensions(
         extensions,
         r'$.extensions',
       ) {
    CockpitTestValueReader.string(stepId, r'$.stepId', id: true);
    if (description != null) {
      CockpitTestValueReader.string(description, r'$.description');
    }
    if (timeoutMs != null && timeoutMs! <= 0) {
      throw const FormatException('Step timeoutMs must be positive.');
    }
  }

  final String stepId;
  final String? description;
  final CockpitTestPlane? plane;
  final int? timeoutMs;
  final CockpitTestEvidencePolicy? evidence;
  final CockpitTestSafetyDeclaration? safety;
  final CockpitTestOperationTemplate operation;
  final Map<String, Object?> extensions;

  Map<String, Object?> toJson() => <String, Object?>{
    'stepId': stepId,
    if (description != null) 'description': description,
    if (plane != null) 'plane': plane!.name,
    if (timeoutMs != null) 'timeoutMs': timeoutMs,
    if (evidence != null) 'evidence': evidence!.toJson(),
    if (safety != null) 'safety': safety!.toJson(),
    operation.wireName: operation.toJson(),
    ...extensions,
  };

  factory CockpitTestStepTemplate.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = CockpitTestValueReader.object(value, path);
    const operations = <String>{
      'action',
      'startRecording',
      'stopRecording',
      'if',
      'retry',
      'loop',
      'call',
    };
    CockpitTestValueReader.keys(
      json,
      const <String>{
        'stepId',
        'description',
        'plane',
        'timeoutMs',
        'evidence',
        'safety',
        ...operations,
      },
      path,
      required: const <String>{'stepId'},
      allowExtensions: true,
    );
    final present = operations.where(json.containsKey).toList(growable: false);
    if (present.length != 1) {
      throw FormatException('Exactly one step operation is required at $path.');
    }
    final operationName = present.single;
    final operation = switch (operationName) {
      'action' => CockpitTestActionOperationTemplate(
        CockpitTestActionTemplate.fromJson(
          json[operationName],
          path: '$path.$operationName',
        ),
      ),
      'startRecording' => CockpitTestStartRecordingOperationTemplate.fromJson(
        json[operationName],
        path: '$path.$operationName',
      ),
      'stopRecording' => CockpitTestStopRecordingOperationTemplate.fromJson(
        json[operationName],
        path: '$path.$operationName',
      ),
      'if' => CockpitTestIfOperationTemplate.fromJson(
        json[operationName],
        path: '$path.$operationName',
      ),
      'retry' => CockpitTestRetryOperationTemplate.fromJson(
        json[operationName],
        path: '$path.$operationName',
      ),
      'loop' => CockpitTestLoopOperationTemplate.fromJson(
        json[operationName],
        path: '$path.$operationName',
      ),
      'call' => CockpitTestCallOperationTemplate.fromJson(
        json[operationName],
        path: '$path.$operationName',
      ),
      _ => throw StateError('Unreachable step operation $operationName.'),
    };
    return CockpitTestStepTemplate(
      stepId: CockpitTestValueReader.string(
        json['stepId'],
        '$path.stepId',
        id: true,
      ),
      description: CockpitTestValueReader.optionalString(
        json['description'],
        '$path.description',
      ),
      plane: json['plane'] == null
          ? null
          : CockpitTestValueReader.enumeration(
              json['plane'],
              CockpitTestPlane.values,
              '$path.plane',
            ),
      timeoutMs: json['timeoutMs'] == null
          ? null
          : CockpitTestValueReader.integer(
              json['timeoutMs'],
              '$path.timeoutMs',
              minimum: 1,
              maximum: 3600000,
            ),
      evidence: json['evidence'] == null
          ? null
          : CockpitTestEvidencePolicy.fromJson(
              json['evidence'],
              path: '$path.evidence',
            ),
      safety: json['safety'] == null
          ? null
          : CockpitTestSafetyDeclaration.fromJson(
              json['safety'],
              path: '$path.safety',
            ),
      operation: operation,
      extensions: <String, Object?>{
        for (final entry in json.entries)
          if (entry.key.startsWith('x-'))
            entry.key: CockpitTestValueReader.jsonValue(
              entry.value,
              '$path.${entry.key}',
            ),
      },
    );
  }
}

sealed class CockpitTestOperationTemplate {
  const CockpitTestOperationTemplate();

  String get wireName;
  Object? toJson();
}

final class CockpitTestActionOperationTemplate
    extends CockpitTestOperationTemplate {
  const CockpitTestActionOperationTemplate(this.action);

  final CockpitTestActionTemplate action;

  @override
  String get wireName => 'action';

  @override
  Object? toJson() => action.toJson();
}

final class CockpitTestStartRecordingOperationTemplate
    extends CockpitTestOperationTemplate {
  CockpitTestStartRecordingOperationTemplate({
    required this.name,
    this.purpose = 'acceptance',
    this.mode = 'auto',
    this.layer,
    this.allowFallback,
    this.attachToStep = true,
  }) {
    CockpitTestValueReader.string(name, r'$.name', id: true);
    CockpitTestValueReader.string(purpose, r'$.purpose');
    CockpitTestValueReader.string(mode, r'$.mode');
    if (layer != null) {
      CockpitTestValueReader.string(layer, r'$.layer');
    }
    if (!const <String>{'acceptance', 'repro'}.contains(purpose)) {
      throw const FormatException(
        'Recording purpose must be acceptance or repro.',
      );
    }
    if (!const <String>{'auto', 'cheap', 'native', 'full'}.contains(mode)) {
      throw const FormatException('Unsupported recording mode.');
    }
    if (layer != null &&
        !const <String>{
          'flutter',
          'app-window',
          'host-screen',
          'system',
        }.contains(layer)) {
      throw const FormatException('Unsupported recording layer.');
    }
  }

  final String name;
  final String purpose;
  final String mode;
  final String? layer;
  final bool? allowFallback;
  final bool attachToStep;

  @override
  String get wireName => 'startRecording';

  @override
  Object? toJson() => <String, Object?>{
    'name': name,
    'purpose': purpose,
    'mode': mode,
    if (layer != null) 'layer': layer,
    if (allowFallback != null) 'allowFallback': allowFallback,
    'attachToStep': attachToStep,
  };

  factory CockpitTestStartRecordingOperationTemplate.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{
        'name',
        'purpose',
        'mode',
        'layer',
        'allowFallback',
        'attachToStep',
      },
      path,
      required: const <String>{'name'},
    );
    return CockpitTestStartRecordingOperationTemplate(
      name: CockpitTestValueReader.string(json['name'], '$path.name', id: true),
      purpose: json['purpose'] == null
          ? 'acceptance'
          : CockpitTestValueReader.string(json['purpose'], '$path.purpose'),
      mode: json['mode'] == null
          ? 'auto'
          : CockpitTestValueReader.string(json['mode'], '$path.mode'),
      layer: CockpitTestValueReader.optionalString(
        json['layer'],
        '$path.layer',
      ),
      allowFallback: json['allowFallback'] == null
          ? null
          : CockpitTestValueReader.boolean(
              json['allowFallback'],
              '$path.allowFallback',
            ),
      attachToStep: json['attachToStep'] == null
          ? true
          : CockpitTestValueReader.boolean(
              json['attachToStep'],
              '$path.attachToStep',
            ),
    );
  }
}

final class CockpitTestStopRecordingOperationTemplate
    extends CockpitTestOperationTemplate {
  CockpitTestStopRecordingOperationTemplate({this.settleMs = 1400}) {
    if (settleMs < 0 || settleMs > 60000) {
      throw const FormatException('stopRecording settleMs is invalid.');
    }
  }

  final int settleMs;

  @override
  String get wireName => 'stopRecording';

  @override
  Object? toJson() => <String, Object?>{'settleMs': settleMs};

  factory CockpitTestStopRecordingOperationTemplate.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(json, const <String>{'settleMs'}, path);
    return CockpitTestStopRecordingOperationTemplate(
      settleMs: json['settleMs'] == null
          ? 1400
          : CockpitTestValueReader.integer(
              json['settleMs'],
              '$path.settleMs',
              minimum: 0,
              maximum: 60000,
            ),
    );
  }
}

List<CockpitTestStepTemplate> _readSteps(
  Object? value,
  String path, {
  bool allowEmpty = false,
}) {
  final raw = CockpitTestValueReader.list(value, path);
  if (!allowEmpty && raw.isEmpty) {
    throw FormatException('Expected at least one step at $path.');
  }
  return List<CockpitTestStepTemplate>.unmodifiable(<CockpitTestStepTemplate>[
    for (var index = 0; index < raw.length; index += 1)
      CockpitTestStepTemplate.fromJson(raw[index], path: '$path[$index]'),
  ]);
}

final class CockpitTestIfOperationTemplate
    extends CockpitTestOperationTemplate {
  CockpitTestIfOperationTemplate({
    required this.condition,
    required Iterable<CockpitTestStepTemplate> thenSteps,
    Iterable<CockpitTestStepTemplate> elseSteps =
        const <CockpitTestStepTemplate>[],
  }) : thenSteps = List<CockpitTestStepTemplate>.unmodifiable(thenSteps),
       elseSteps = List<CockpitTestStepTemplate>.unmodifiable(elseSteps) {
    if (this.thenSteps.isEmpty && this.elseSteps.isEmpty) {
      throw const FormatException('if requires a non-empty branch.');
    }
  }

  final CockpitTestConditionTemplate condition;
  final List<CockpitTestStepTemplate> thenSteps;
  final List<CockpitTestStepTemplate> elseSteps;

  @override
  String get wireName => 'if';

  @override
  Object? toJson() => <String, Object?>{
    'condition': condition.toJson(),
    'then': thenSteps.map((step) => step.toJson()).toList(),
    if (elseSteps.isNotEmpty)
      'else': elseSteps.map((step) => step.toJson()).toList(),
  };

  factory CockpitTestIfOperationTemplate.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{'condition', 'then', 'else'},
      path,
      required: const <String>{'condition', 'then'},
    );
    return CockpitTestIfOperationTemplate(
      condition: CockpitTestConditionTemplate.fromJson(
        json['condition'],
        path: '$path.condition',
      ),
      thenSteps: _readSteps(json['then'], '$path.then', allowEmpty: true),
      elseSteps: json['else'] == null
          ? const <CockpitTestStepTemplate>[]
          : _readSteps(json['else'], '$path.else', allowEmpty: true),
    );
  }
}

final class CockpitTestRetryOperationTemplate
    extends CockpitTestOperationTemplate {
  CockpitTestRetryOperationTemplate({
    required this.maxAttempts,
    this.delayMs = 0,
    required Iterable<CockpitTestStepTemplate> steps,
  }) : steps = List<CockpitTestStepTemplate>.unmodifiable(steps) {
    if (maxAttempts <= 0 || this.steps.isEmpty || delayMs < 0) {
      throw const FormatException('retry bounds and steps are invalid.');
    }
  }

  final int maxAttempts;
  final int delayMs;
  final List<CockpitTestStepTemplate> steps;

  @override
  String get wireName => 'retry';

  @override
  Object? toJson() => <String, Object?>{
    'maxAttempts': maxAttempts,
    'delayMs': delayMs,
    'steps': steps.map((step) => step.toJson()).toList(),
  };

  factory CockpitTestRetryOperationTemplate.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{'maxAttempts', 'delayMs', 'steps'},
      path,
      required: const <String>{'maxAttempts', 'steps'},
    );
    return CockpitTestRetryOperationTemplate(
      maxAttempts: CockpitTestValueReader.integer(
        json['maxAttempts'],
        '$path.maxAttempts',
        minimum: 1,
        maximum: 100,
      ),
      delayMs: json['delayMs'] == null
          ? 0
          : CockpitTestValueReader.integer(
              json['delayMs'],
              '$path.delayMs',
              minimum: 0,
              maximum: 3600000,
            ),
      steps: _readSteps(json['steps'], '$path.steps'),
    );
  }
}

final class CockpitTestLoopOperationTemplate
    extends CockpitTestOperationTemplate {
  CockpitTestLoopOperationTemplate({
    required this.maxIterations,
    required this.condition,
    required Iterable<CockpitTestStepTemplate> steps,
  }) : steps = List<CockpitTestStepTemplate>.unmodifiable(steps) {
    if (maxIterations <= 0 || this.steps.isEmpty) {
      throw const FormatException('loop bounds and steps are invalid.');
    }
  }

  final int maxIterations;
  final CockpitTestConditionTemplate condition;
  final List<CockpitTestStepTemplate> steps;

  @override
  String get wireName => 'loop';

  @override
  Object? toJson() => <String, Object?>{
    'maxIterations': maxIterations,
    'condition': condition.toJson(),
    'steps': steps.map((step) => step.toJson()).toList(),
  };

  factory CockpitTestLoopOperationTemplate.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{'maxIterations', 'condition', 'steps'},
      path,
      required: const <String>{'maxIterations', 'condition', 'steps'},
    );
    return CockpitTestLoopOperationTemplate(
      maxIterations: CockpitTestValueReader.integer(
        json['maxIterations'],
        '$path.maxIterations',
        minimum: 1,
        maximum: 10000,
      ),
      condition: CockpitTestConditionTemplate.fromJson(
        json['condition'],
        path: '$path.condition',
      ),
      steps: _readSteps(json['steps'], '$path.steps'),
    );
  }
}

final class CockpitTestCallOperationTemplate
    extends CockpitTestOperationTemplate {
  CockpitTestCallOperationTemplate(this.fragment) {
    CockpitTestValueReader.string(fragment, r'$.fragment', id: true);
  }

  final String fragment;

  @override
  String get wireName => 'call';

  @override
  Object? toJson() => <String, Object?>{'fragment': fragment};

  factory CockpitTestCallOperationTemplate.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{'fragment'},
      path,
      required: const <String>{'fragment'},
    );
    return CockpitTestCallOperationTemplate(
      CockpitTestValueReader.string(
        json['fragment'],
        '$path.fragment',
        id: true,
      ),
    );
  }
}
