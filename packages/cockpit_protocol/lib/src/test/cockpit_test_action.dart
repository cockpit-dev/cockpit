import 'package:collection/collection.dart';

import '../control/cockpit_locator.dart';
import 'cockpit_test_action_contract.dart';
import 'cockpit_test_condition.dart';
import 'cockpit_test_locator.dart';
import 'cockpit_test_value.dart';
import 'cockpit_test_value_reader.dart';
import 'cockpit_test_variable.dart';

final class CockpitTestActionTemplate {
  CockpitTestActionTemplate({
    required this.kind,
    this.locator,
    this.condition,
    Map<CockpitTestActionField, CockpitTestTemplateValue> values =
        const <CockpitTestActionField, CockpitTestTemplateValue>{},
    Map<String, Object?> extensions = const <String, Object?>{},
  }) : values =
           Map<CockpitTestActionField, CockpitTestTemplateValue>.unmodifiable(
             values,
           ),
       extensions = CockpitTestValueReader.extensions(
         extensions,
         r'$.extensions',
       ) {
    _validateShape();
    _validateLiteralValues();
  }

  final CockpitTestActionKind kind;
  final CockpitTestLocatorTemplate? locator;
  final CockpitTestConditionTemplate? condition;
  final Map<CockpitTestActionField, CockpitTestTemplateValue> values;
  final Map<String, Object?> extensions;

  CockpitTestActionSpec get spec => cockpitTestActionSpecs[kind]!;

  Map<String, Object?> toJson() => <String, Object?>{
    'type': kind.name,
    if (locator != null) 'locator': locator!.toJson(),
    if (condition != null) 'condition': condition!.toJson(),
    for (final entry in values.entries)
      entry.key.wireName: entry.value.toJson(),
    ...extensions,
  };

  factory CockpitTestActionTemplate.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = CockpitTestValueReader.object(value, path);
    final kind = CockpitTestValueReader.enumeration(
      json['type'],
      CockpitTestActionKind.values,
      '$path.type',
    );
    final spec = cockpitTestActionSpecs[kind]!;
    final allowed = <String>{
      'type',
      'locator',
      'condition',
      ...spec.allowedFields.map((field) => field.wireName),
    };
    CockpitTestValueReader.keys(
      json,
      allowed,
      path,
      required: const <String>{'type'},
      allowExtensions: true,
    );
    final values = <CockpitTestActionField, CockpitTestTemplateValue>{};
    for (final field in spec.allowedFields) {
      if (json.containsKey(field.wireName)) {
        values[field] = CockpitTestTemplateValue.fromJson(
          json[field.wireName],
          expectedType: field.valueType,
          path: '$path.${field.wireName}',
        );
      }
    }
    return CockpitTestActionTemplate(
      kind: kind,
      locator: json['locator'] == null
          ? null
          : CockpitTestLocatorTemplate.fromJson(
              json['locator'],
              path: '$path.locator',
            ),
      condition: json['condition'] == null
          ? null
          : CockpitTestConditionTemplate.fromJson(
              json['condition'],
              path: '$path.condition',
            ),
      values: values,
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

  void _validateShape() {
    if (cockpitTestActionSpecs.length != CockpitTestActionKind.values.length) {
      throw StateError('The Cockpit test action contract is not exhaustive.');
    }
    final actionSpec = spec;
    if (!actionSpec.allowedFields.containsAll(actionSpec.secretFields) ||
        actionSpec.secretFields.any(
          (field) => field.valueType != CockpitTestValueType.string,
        )) {
      throw StateError('Secret action fields must be allowed string fields.');
    }
    switch (actionSpec.locator) {
      case CockpitTestLocatorRequirement.required:
        if (locator == null) {
          throw FormatException('${kind.name} requires locator.');
        }
      case CockpitTestLocatorRequirement.forbidden:
        if (locator != null) {
          throw FormatException('${kind.name} forbids locator.');
        }
      case CockpitTestLocatorRequirement.optional:
        break;
    }
    if (actionSpec.conditionRequired != (condition != null)) {
      throw FormatException(
        '${kind.name} ${actionSpec.conditionRequired ? 'requires' : 'forbids'} '
        'condition.',
      );
    }
    if (!actionSpec.allowedFields.containsAll(values.keys)) {
      throw FormatException('${kind.name} contains a forbidden action field.');
    }
    final missing = actionSpec.requiredFields.difference(values.keys.toSet());
    if (missing.isNotEmpty) {
      throw FormatException(
        '${kind.name} requires ${missing.map((field) => field.wireName).join(', ')}.',
      );
    }
  }

  void _validateLiteralValues() {
    final literals = <CockpitTestActionField, Object?>{
      for (final entry in values.entries)
        if (entry.value.kind == CockpitTestTemplateValueKind.literal)
          entry.key: entry.value.value,
    };
    _validateActionValues(
      kind,
      literals,
      declaredFields: values.keys.toSet(),
      partial: true,
    );
  }
}

final class CockpitTestAction {
  CockpitTestAction({
    required this.kind,
    this.locator,
    this.condition,
    Map<CockpitTestActionField, Object?> values =
        const <CockpitTestActionField, Object?>{},
    Map<String, Object?> extensions = const <String, Object?>{},
  }) : values = _copyBoundActionValues(kind, values),
       extensions = CockpitTestValueReader.extensions(
         extensions,
         r'$.extensions',
       ) {
    final template = CockpitTestActionTemplate(
      kind: kind,
      locator: locator == null
          ? null
          : CockpitTestLocatorTemplate.fromJson(
              locator!.toJson(),
              path: r'$.locator',
            ),
      condition: condition == null
          ? null
          : CockpitTestConditionTemplate.fromJson(
              condition!.toJson(),
              path: r'$.condition',
            ),
      values: <CockpitTestActionField, CockpitTestTemplateValue>{
        for (final entry in values.entries)
          entry.key: entry.value is CockpitTestSecretToken
              ? CockpitTestTemplateValue.variable(
                  'secretToken',
                  expectedType: entry.key.valueType,
                )
              : CockpitTestTemplateValue.literal(
                  entry.value,
                  expectedType: entry.key.valueType,
                ),
      },
      extensions: extensions,
    );
    template._validateShape();
    _validateActionValues(
      kind,
      this.values,
      declaredFields: this.values.keys.toSet(),
      partial: false,
    );
  }

  final CockpitTestActionKind kind;
  final CockpitTestLocator? locator;
  final CockpitTestCondition? condition;
  final Map<CockpitTestActionField, Object?> values;
  final Map<String, Object?> extensions;

  CockpitTestActionSpec get spec => cockpitTestActionSpecs[kind]!;

  T? value<T>(CockpitTestActionField field) => values[field] as T?;

  bool get containsSecret =>
      values.values.any((value) => value is CockpitTestSecretToken);

  Map<String, Object?> toJson() => <String, Object?>{
    'type': kind.name,
    if (locator != null) 'locator': locator!.toJson(),
    if (condition != null) 'condition': condition!.toJson(),
    for (final entry in values.entries)
      entry.key.wireName: entry.value is CockpitTestSecretToken
          ? '<secret>'
          : entry.value,
    ...extensions,
  };

  CockpitTestAction copyWithValues(
    Map<CockpitTestActionField, Object?> values,
  ) {
    return CockpitTestAction(
      kind: kind,
      locator: locator,
      condition: condition,
      values: values,
      extensions: extensions,
    );
  }

  factory CockpitTestAction.fromJson(Object? value, {required String path}) {
    final template = CockpitTestActionTemplate.fromJson(value, path: path);
    final boundValues = <CockpitTestActionField, Object?>{};
    for (final entry in template.values.entries) {
      if (entry.value.kind != CockpitTestTemplateValueKind.literal) {
        throw FormatException(
          'Unbound action value at $path.${entry.key.wireName}.',
        );
      }
      boundValues[entry.key] = entry.value.value;
    }
    return CockpitTestAction(
      kind: template.kind,
      locator: template.locator == null
          ? null
          : CockpitTestLocator.fromJson(
              template.locator!.toJson(),
              path: '$path.locator',
            ),
      condition: template.condition == null
          ? null
          : CockpitTestCondition.fromJson(
              template.condition!.toJson(),
              path: '$path.condition',
            ),
      values: boundValues,
      extensions: template.extensions,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CockpitTestAction &&
      other.kind == kind &&
      other.locator == locator &&
      const DeepCollectionEquality().equals(
        other.condition?.toJson(),
        condition?.toJson(),
      ) &&
      const DeepCollectionEquality().equals(other.values, values) &&
      const DeepCollectionEquality().equals(other.extensions, extensions);

  @override
  int get hashCode => Object.hash(
    kind,
    locator,
    const DeepCollectionEquality().hash(condition?.toJson()),
    const DeepCollectionEquality().hash(values),
    const DeepCollectionEquality().hash(extensions),
  );
}

void _validateBoundValue(
  CockpitTestActionSpec spec,
  CockpitTestActionField field,
  Object? value,
) {
  if (value is CockpitTestSecretToken) {
    if (!spec.secretFields.contains(field)) {
      throw FormatException(
        '${field.wireName} cannot contain a secret token for this action.',
      );
    }
    return;
  }
  CockpitTestTemplateValue.literal(value, expectedType: field.valueType);
}

Map<CockpitTestActionField, Object?> _copyBoundActionValues(
  CockpitTestActionKind kind,
  Map<CockpitTestActionField, Object?> values,
) {
  final spec = cockpitTestActionSpecs[kind]!;
  return Map<CockpitTestActionField, Object?>.unmodifiable(
    <CockpitTestActionField, Object?>{
      for (final entry in values.entries)
        entry.key: switch (entry.value) {
          final CockpitTestSecretToken token => () {
            _validateBoundValue(spec, entry.key, token);
            return token;
          }(),
          final value => CockpitTestTemplateValue.literal(
            value,
            expectedType: entry.key.valueType,
          ).value,
        },
    },
  );
}

void _validateActionValues(
  CockpitTestActionKind kind,
  Map<CockpitTestActionField, Object?> values, {
  required Set<CockpitTestActionField> declaredFields,
  required bool partial,
}) {
  bool concrete(CockpitTestActionField field) =>
      values[field] != null && values[field] is! CockpitTestSecretToken;
  num? number(CockpitTestActionField field) =>
      concrete(field) ? values[field]! as num : null;
  int? integer(CockpitTestActionField field) =>
      concrete(field) ? values[field]! as int : null;
  String? string(CockpitTestActionField field) =>
      concrete(field) ? values[field]! as String : null;

  for (final field in const <CockpitTestActionField>{
    CockpitTestActionField.durationMs,
    CockpitTestActionField.velocity,
    CockpitTestActionField.distance,
    CockpitTestActionField.maxScrolls,
    CockpitTestActionField.quietMs,
    CockpitTestActionField.characters,
    CockpitTestActionField.intervalMs,
  }) {
    final value = number(field);
    if (value != null && value <= 0) {
      throw FormatException('${field.wireName} must be positive.');
    }
  }
  for (final field in const <CockpitTestActionField>{
    CockpitTestActionField.selectionStart,
    CockpitTestActionField.selectionEnd,
    CockpitTestActionField.composingStart,
    CockpitTestActionField.composingEnd,
  }) {
    final value = integer(field);
    if (value != null && value < -1) {
      throw FormatException('${field.wireName} must be at least -1.');
    }
  }
  final revealAlignment = string(CockpitTestActionField.revealAlignment);
  if (revealAlignment != null &&
      !const <String>{
        'nearest',
        'start',
        'center',
        'end',
      }.contains(revealAlignment)) {
    throw const FormatException('Unsupported revealAlignment.');
  }
  final distance = number(CockpitTestActionField.distance);
  if (distance != null && (distance <= 0 || distance > 1)) {
    throw const FormatException('distance must be normalized in (0, 1].');
  }
  final direction = string(CockpitTestActionField.direction);
  if (direction != null &&
      !const <String>{'up', 'down', 'left', 'right'}.contains(direction)) {
    throw const FormatException(
      'direction must be one of up, down, left, or right.',
    );
  }
  final activation = string(CockpitTestActionField.activation);
  if (activation != null &&
      !const <String>{
        'auto',
        'semantic',
        'direct',
        'gesture',
      }.contains(activation)) {
    throw const FormatException('Unsupported tap activation.');
  }
  final matchMode = string(CockpitTestActionField.matchMode);
  if (matchMode != null &&
      !CockpitTextMatchMode.values.any((mode) => mode.name == matchMode)) {
    throw const FormatException('Unsupported text matchMode.');
  }
  final similarity = number(CockpitTestActionField.similarity);
  if (similarity != null && (similarity <= 0 || similarity > 1)) {
    throw const FormatException('similarity must be normalized in (0, 1].');
  }
  final inputAction = string(CockpitTestActionField.inputAction);
  if (inputAction != null &&
      !const <String>{
        'none',
        'unspecified',
        'done',
        'go',
        'search',
        'send',
        'next',
        'previous',
        'continueAction',
        'join',
        'route',
        'emergencyCall',
        'newline',
      }.contains(inputAction)) {
    throw const FormatException('Unsupported text input action.');
  }

  switch (kind) {
    case CockpitTestActionKind.setTextEditingValue:
      if (declaredFields.isEmpty) {
        throw const FormatException(
          'setTextEditingValue requires at least one edit field.',
        );
      }
      _validateRangePair(
        declaredFields,
        values,
        CockpitTestActionField.selectionStart,
        CockpitTestActionField.selectionEnd,
      );
      _validateRangePair(
        declaredFields,
        values,
        CockpitTestActionField.composingStart,
        CockpitTestActionField.composingEnd,
      );
    case CockpitTestActionKind.drag || CockpitTestActionKind.fling:
      final dx = number(CockpitTestActionField.dx);
      final dy = number(CockpitTestActionField.dy);
      if (dx != null && dy != null && dx == 0 && dy == 0) {
        throw FormatException('${kind.name} requires non-zero movement.');
      }
    case CockpitTestActionKind.pinchZoom:
      final scale = number(CockpitTestActionField.scale);
      if (scale != null && (scale <= 0 || scale == 1)) {
        throw const FormatException(
          'pinchZoom scale must be positive and non-unit.',
        );
      }
    case CockpitTestActionKind.rotate:
      if (number(CockpitTestActionField.rotationRadians) == 0) {
        throw const FormatException('rotate requires a non-zero rotation.');
      }
    case CockpitTestActionKind.panZoom:
      final panDx = number(CockpitTestActionField.panDx) ?? 0;
      final panDy = number(CockpitTestActionField.panDy) ?? 0;
      final scale = number(CockpitTestActionField.scale) ?? 1;
      final rotation = number(CockpitTestActionField.rotationRadians) ?? 0;
      if (scale <= 0) {
        throw const FormatException('panZoom scale must be positive.');
      }
      final hasDeferredValue =
          partial && declaredFields.any((field) => !values.containsKey(field));
      if (!hasDeferredValue &&
          panDx == 0 &&
          panDy == 0 &&
          scale == 1 &&
          rotation == 0) {
        throw const FormatException('panZoom requires at least one change.');
      }
    case CockpitTestActionKind.multiTouch:
      final sequence = values[CockpitTestActionField.sequence];
      if (sequence != null || !partial) {
        _validateMultiTouchSequence(sequence);
      }
    case CockpitTestActionKind.sendKeyEvent ||
        CockpitTestActionKind.sendKeyDownEvent ||
        CockpitTestActionKind.sendKeyUpEvent:
      final request = values[CockpitTestActionField.keyRequest];
      if (request != null || !partial) {
        _validateKeyRequest(request);
      }
    case CockpitTestActionKind.assertText:
      if (matchMode == CockpitTextMatchMode.regex.name) {
        final pattern = string(CockpitTestActionField.text);
        if (pattern != null) {
          RegExp(pattern);
        }
      }
    case CockpitTestActionKind.travel:
      final route = values[CockpitTestActionField.route];
      if (route != null || !partial) {
        _validateTravelRoute(route);
      }
    case CockpitTestActionKind.captureScreenshot:
      _validateCaptureOptions(values[CockpitTestActionField.captureOptions]);
    case CockpitTestActionKind.system:
      final parameters = values[CockpitTestActionField.systemParameters];
      if (parameters != null && parameters is! Map<Object?, Object?>) {
        throw const FormatException('system parameters must be an object.');
      }
    case CockpitTestActionKind.collectSnapshot:
      _validateSnapshotOptions(
        values[CockpitTestActionField.snapshotOptions],
        r'$.snapshotOptions',
      );
    default:
      break;
  }
}

void _validateTravelRoute(Object? value) {
  final points = CockpitTestValueReader.list(value, r'$.route');
  if (points.length < 2 || points.length > 10000) {
    throw const FormatException(
      'travel route requires 2 through 10000 points.',
    );
  }
  for (var index = 0; index < points.length; index += 1) {
    final path = '\$.route[$index]';
    final point = CockpitTestValueReader.object(points[index], path);
    CockpitTestValueReader.keys(
      point,
      const <String>{'latitude', 'longitude', 'delayMs'},
      path,
      required: const <String>{'latitude', 'longitude'},
    );
    final latitude = CockpitTestValueReader.number(
      point['latitude'],
      '$path.latitude',
    );
    final longitude = CockpitTestValueReader.number(
      point['longitude'],
      '$path.longitude',
    );
    if (latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw FormatException('Invalid geographic coordinate at $path.');
    }
    if (point.containsKey('delayMs')) {
      CockpitTestValueReader.integer(
        point['delayMs'],
        '$path.delayMs',
        minimum: 0,
        maximum: 3600000,
      );
    }
  }
}

void _validateKeyRequest(Object? value) {
  final request = CockpitTestValueReader.object(value, r'$.keyRequest');
  CockpitTestValueReader.keys(
    request,
    const <String>{'logicalKey', 'physicalKey', 'character'},
    r'$.keyRequest',
    required: const <String>{'logicalKey'},
  );
  void validateKey(Object? candidate, String path) {
    if (candidate is int) return;
    if (candidate is String && candidate.trim().isNotEmpty) return;
    throw FormatException('$path must be an integer or non-empty string.');
  }

  validateKey(request['logicalKey'], r'$.keyRequest.logicalKey');
  if (request.containsKey('physicalKey')) {
    validateKey(request['physicalKey'], r'$.keyRequest.physicalKey');
  }
  if (request.containsKey('character')) {
    CockpitTestValueReader.string(
      request['character'],
      r'$.keyRequest.character',
    );
  }
}

void _validateMultiTouchSequence(Object? value) {
  if (value is! Map<Object?, Object?>) {
    throw const FormatException('multiTouch sequence must be an object.');
  }
  final json = CockpitTestValueReader.object(value, r'$.sequence');
  CockpitTestValueReader.keys(
    json,
    const <String>{'steps'},
    r'$.sequence',
    required: const <String>{'steps'},
  );
  final steps = CockpitTestValueReader.list(json['steps'], r'$.sequence.steps');
  if (steps.isEmpty || steps.length > 32) {
    throw const FormatException(
      'multiTouch sequence must contain from 1 through 32 steps.',
    );
  }
  for (var index = 0; index < steps.length; index += 1) {
    final path = '\$.sequence.steps[$index]';
    final step = CockpitTestValueReader.object(steps[index], path);
    CockpitTestValueReader.keys(
      step,
      const <String>{'pointer', 'phase', 'atMs', 'dx', 'dy'},
      path,
      required: const <String>{'pointer', 'phase', 'atMs', 'dx', 'dy'},
    );
    CockpitTestValueReader.integer(
      step['pointer'],
      '$path.pointer',
      minimum: 0,
    );
    final phase = CockpitTestValueReader.string(step['phase'], '$path.phase');
    if (!const <String>{'down', 'move', 'up'}.contains(phase)) {
      throw FormatException('Unsupported multiTouch phase at $path.phase.');
    }
    CockpitTestValueReader.integer(step['atMs'], '$path.atMs', minimum: 0);
    CockpitTestValueReader.number(step['dx'], '$path.dx');
    CockpitTestValueReader.number(step['dy'], '$path.dy');
  }
}

void _validateCaptureOptions(Object? value) {
  if (value == null) return;
  const field = 'captureOptions';
  final json = CockpitTestValueReader.object(value, r'$.captureOptions');
  CockpitTestValueReader.keys(json, const <String>{
    'reason',
    'includeSnapshot',
    'attachToStep',
    'profile',
    'allowFallback',
    'snapshotOptions',
  }, r'$.captureOptions');
  final reason = json['reason'];
  if (reason != null &&
      !const <String>{
        'baseline',
        'before_action',
        'after_action',
        'assertion_failure',
        'acceptance',
      }.contains(
        CockpitTestValueReader.string(reason, r'$.captureOptions.reason'),
      )) {
    throw const FormatException('Unsupported capture reason.');
  }
  for (final name in const <String>{
    'includeSnapshot',
    'attachToStep',
    'allowFallback',
  }) {
    if (json.containsKey(name)) {
      CockpitTestValueReader.boolean(json[name], '\$.captureOptions.$name');
    }
  }
  final profile = json['profile'];
  if (profile != null &&
      !const <String>{
        'diagnostic',
        'acceptance',
        'flutterPreferred',
        'nativePreferred',
      }.contains(
        CockpitTestValueReader.string(profile, r'$.captureOptions.profile'),
      )) {
    throw const FormatException('Unsupported capture profile.');
  }
  if (json.containsKey('snapshotOptions')) {
    _validateSnapshotOptions(
      json['snapshotOptions'],
      '\$.$field.snapshotOptions',
    );
  }
}

void _validateSnapshotOptions(Object? value, String path) {
  if (value == null) return;
  final json = CockpitTestValueReader.object(value, path);
  CockpitTestValueReader.keys(json, const <String>{
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
  }, path);
  if (json['profile'] case final profile?) {
    final name = CockpitTestValueReader.string(profile, '$path.profile');
    if (!const <String>{
      'live',
      'baseline',
      'investigate',
      'forensic',
    }.contains(name)) {
      throw FormatException('Unsupported snapshot profile at $path.profile.');
    }
  }
  for (final name in const <String>{
    'maxTargets',
    'maxAncestorsPerTarget',
    'maxPropertiesPerTarget',
    'maxRebuildEntries',
    'maxNetworkEntries',
    'maxRuntimeEntries',
    'maxAccessibilityEntries',
  }) {
    if (json.containsKey(name)) {
      CockpitTestValueReader.integer(
        json[name],
        '$path.$name',
        minimum: name == 'maxTargets' ? 1 : 0,
        maximum: 10000,
      );
    }
  }
  for (final name in const <String>{
    'includeStyleDetails',
    'includeDiagnosticProperties',
    'emitArtifactWhenLarge',
    'includeRebuildActivity',
    'includeNetworkActivity',
    'includeRuntimeActivity',
    'includeAccessibilitySummary',
  }) {
    if (json.containsKey(name)) {
      CockpitTestValueReader.boolean(json[name], '$path.$name');
    }
  }
  if (json.containsKey('networkQuery')) {
    _validateQueryOptions(
      json['networkQuery'],
      '$path.networkQuery',
      stringFields: const <String>{'method', 'uriContains'},
      boolFields: const <String>{'onlyFailures'},
      intFields: const <String>{'statusCodeAtLeast'},
    );
  }
  if (json.containsKey('runtimeQuery')) {
    _validateQueryOptions(
      json['runtimeQuery'],
      '$path.runtimeQuery',
      stringFields: const <String>{'messageContains'},
      boolFields: const <String>{'onlyErrors'},
    );
  }
}

void _validateQueryOptions(
  Object? value,
  String path, {
  Set<String> stringFields = const <String>{},
  Set<String> boolFields = const <String>{},
  Set<String> intFields = const <String>{},
}) {
  final json = CockpitTestValueReader.object(value, path);
  CockpitTestValueReader.keys(json, <String>{
    ...stringFields,
    ...boolFields,
    ...intFields,
  }, path);
  for (final field in stringFields) {
    if (json.containsKey(field)) {
      CockpitTestValueReader.string(json[field], '$path.$field');
    }
  }
  for (final field in boolFields) {
    if (json.containsKey(field)) {
      CockpitTestValueReader.boolean(json[field], '$path.$field');
    }
  }
  for (final field in intFields) {
    if (json.containsKey(field)) {
      CockpitTestValueReader.integer(
        json[field],
        '$path.$field',
        minimum: 0,
        maximum: 999,
      );
    }
  }
}

void _validateRangePair(
  Set<CockpitTestActionField> declaredFields,
  Map<CockpitTestActionField, Object?> values,
  CockpitTestActionField start,
  CockpitTestActionField end,
) {
  final hasStart = declaredFields.contains(start);
  final hasEnd = declaredFields.contains(end);
  if (hasStart != hasEnd) {
    throw FormatException(
      '${start.wireName} and ${end.wireName} must be provided together.',
    );
  }
  final startValue = values[start];
  final endValue = values[end];
  if (startValue is int && endValue is int && startValue > endValue) {
    throw FormatException('${start.wireName} must not exceed ${end.wireName}.');
  }
}
