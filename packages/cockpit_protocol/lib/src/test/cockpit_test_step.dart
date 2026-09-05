import 'cockpit_test_action.dart';
import 'cockpit_test_condition.dart';
import 'cockpit_test_policy.dart';
import 'cockpit_test_value_reader.dart';

final class CockpitTestStepTemplate {
  /// Creates a CockpitTestStepTemplate.
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

  /// Encodes this CockpitTestStepTemplate as a JSON object.
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

  /// Decodes a CockpitTestStepTemplate from a JSON object.
  factory CockpitTestStepTemplate.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = CockpitTestValueReader.object(value, path);
    const operations = <String>{
      'action',
      'startRecording',
      'stopRecording',
      'startPerformance',
      'stopPerformance',
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
      'startPerformance' =>
        CockpitTestStartPerformanceOperationTemplate.fromJson(
          json[operationName],
          path: '$path.$operationName',
        ),
      'stopPerformance' => CockpitTestStopPerformanceOperationTemplate.fromJson(
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
  /// Creates a CockpitTestOperationTemplate.
  const CockpitTestOperationTemplate();

  String get wireName;

  /// Encodes this CockpitTestOperationTemplate as a JSON object.
  Object? toJson();
}

final class CockpitTestActionOperationTemplate
    extends CockpitTestOperationTemplate {
  /// Creates a CockpitTestActionOperationTemplate.
  const CockpitTestActionOperationTemplate(this.action);

  final CockpitTestActionTemplate action;

  @override
  String get wireName => 'action';

  /// Encodes this CockpitTestActionOperationTemplate as a JSON object.
  @override
  Object? toJson() => action.toJson();
}

final class CockpitTestStartRecordingOperationTemplate
    extends CockpitTestOperationTemplate {
  /// Creates a CockpitTestStartRecordingOperationTemplate.
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

  /// Encodes this CockpitTestStartRecordingOperationTemplate as a JSON object.
  @override
  Object? toJson() => <String, Object?>{
    'name': name,
    'purpose': purpose,
    'mode': mode,
    if (layer != null) 'layer': layer,
    if (allowFallback != null) 'allowFallback': allowFallback,
    'attachToStep': attachToStep,
  };

  /// Decodes a CockpitTestStartRecordingOperationTemplate from a JSON object.
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
  /// Creates a CockpitTestStopRecordingOperationTemplate.
  CockpitTestStopRecordingOperationTemplate({this.settleMs = 1400}) {
    if (settleMs < 0 || settleMs > 60000) {
      throw const FormatException('stopRecording settleMs is invalid.');
    }
  }

  final int settleMs;

  @override
  String get wireName => 'stopRecording';

  /// Encodes this CockpitTestStopRecordingOperationTemplate as a JSON object.
  @override
  Object? toJson() => <String, Object?>{'settleMs': settleMs};

  /// Decodes a CockpitTestStopRecordingOperationTemplate from a JSON object.
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

/// Starts an in-app performance capture window.
///
/// Performance captures are runner-owned metadata operations rather than
/// ordinary UI commands. Only one window may be active at a time, but a case
/// may contain any number of sequential windows.
final class CockpitTestStartPerformanceOperationTemplate
    extends CockpitTestOperationTemplate {
  CockpitTestStartPerformanceOperationTemplate({
    required this.name,
    this.mode = 'profile',
  }) {
    CockpitTestValueReader.string(name, r'$.name', id: true);
    if (!const <String>{'light', 'profile'}.contains(mode)) {
      throw const FormatException('Performance mode must be light or profile.');
    }
  }

  final String name;
  final String mode;

  @override
  String get wireName => 'startPerformance';

  @override
  Object? toJson() => <String, Object?>{
    'name': name,
    if (mode != 'profile') 'mode': mode,
  };

  factory CockpitTestStartPerformanceOperationTemplate.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{'name', 'mode'},
      path,
      required: const <String>{'name'},
    );
    return CockpitTestStartPerformanceOperationTemplate(
      name: CockpitTestValueReader.string(json['name'], '$path.name', id: true),
      mode: json['mode'] == null
          ? 'profile'
          : CockpitTestValueReader.string(json['mode'], '$path.mode'),
    );
  }
}

/// Stops the currently active performance capture window.
final class CockpitTestStopPerformanceOperationTemplate
    extends CockpitTestOperationTemplate {
  CockpitTestStopPerformanceOperationTemplate({this.settleMs = 0}) {
    if (settleMs < 0 || settleMs > 60000) {
      throw const FormatException('stopPerformance settleMs is invalid.');
    }
  }

  final int settleMs;

  @override
  String get wireName => 'stopPerformance';

  @override
  Object? toJson() => <String, Object?>{
    if (settleMs != 0) 'settleMs': settleMs,
  };

  factory CockpitTestStopPerformanceOperationTemplate.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(json, const <String>{'settleMs'}, path);
    return CockpitTestStopPerformanceOperationTemplate(
      settleMs: json['settleMs'] == null
          ? 0
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
  /// Creates a CockpitTestIfOperationTemplate.
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

  /// Encodes this CockpitTestIfOperationTemplate as a JSON object.
  @override
  Object? toJson() => <String, Object?>{
    'condition': condition.toJson(),
    'then': thenSteps.map((step) => step.toJson()).toList(),
    if (elseSteps.isNotEmpty)
      'else': elseSteps.map((step) => step.toJson()).toList(),
  };

  /// Decodes a CockpitTestIfOperationTemplate from a JSON object.
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
  /// Creates a CockpitTestRetryOperationTemplate.
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

  /// Encodes this CockpitTestRetryOperationTemplate as a JSON object.
  @override
  Object? toJson() => <String, Object?>{
    'maxAttempts': maxAttempts,
    'delayMs': delayMs,
    'steps': steps.map((step) => step.toJson()).toList(),
  };

  /// Decodes a CockpitTestRetryOperationTemplate from a JSON object.
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
  /// Creates a CockpitTestLoopOperationTemplate.
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

  /// Encodes this CockpitTestLoopOperationTemplate as a JSON object.
  @override
  Object? toJson() => <String, Object?>{
    'maxIterations': maxIterations,
    'condition': condition.toJson(),
    'steps': steps.map((step) => step.toJson()).toList(),
  };

  /// Decodes a CockpitTestLoopOperationTemplate from a JSON object.
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
  /// Creates a CockpitTestCallOperationTemplate.
  CockpitTestCallOperationTemplate(this.fragment) {
    CockpitTestValueReader.string(fragment, r'$.fragment', id: true);
  }

  final String fragment;

  @override
  String get wireName => 'call';

  /// Encodes this CockpitTestCallOperationTemplate as a JSON object.
  @override
  Object? toJson() => <String, Object?>{'fragment': fragment};

  /// Decodes a CockpitTestCallOperationTemplate from a JSON object.
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
