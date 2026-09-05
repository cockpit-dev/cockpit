import 'cockpit_test_value_reader.dart';

enum CockpitTestPlane { semantic, native, visual, coordinate }

/// Build mode required by a test target.
///
/// A null requirement means that any target build mode is acceptable. The
/// runner still reports the actual mode; it never substitutes a requested mode
/// for one that the target did not provide.
enum CockpitTestBuildMode { debug, profile, release }

enum CockpitTestEvidenceMode { none, onFailure, always }

enum CockpitTestEvidenceFailurePolicy { failStep, recordWarning }

enum CockpitTestSafetyEffect {
  externalNavigation,
  communication,
  financial,
  destructive,
  permissionChange,
  credentialSensitive,
}

final class CockpitTestEvidencePolicy {
  /// Creates a CockpitTestEvidencePolicy.
  const CockpitTestEvidencePolicy({
    this.screenshot = CockpitTestEvidenceMode.onFailure,
    this.snapshot = CockpitTestEvidenceMode.onFailure,
    this.failurePolicy = CockpitTestEvidenceFailurePolicy.failStep,
  });

  final CockpitTestEvidenceMode screenshot;
  final CockpitTestEvidenceMode snapshot;
  final CockpitTestEvidenceFailurePolicy failurePolicy;

  /// Encodes this CockpitTestEvidencePolicy as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'screenshot': screenshot.name,
    'snapshot': snapshot.name,
    'failurePolicy': failurePolicy.name,
  };

  /// Decodes a CockpitTestEvidencePolicy from a JSON object.
  factory CockpitTestEvidencePolicy.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(json, const <String>{
      'screenshot',
      'snapshot',
      'failurePolicy',
    }, path);
    return CockpitTestEvidencePolicy(
      screenshot: json['screenshot'] == null
          ? CockpitTestEvidenceMode.onFailure
          : CockpitTestValueReader.enumeration(
              json['screenshot'],
              CockpitTestEvidenceMode.values,
              '$path.screenshot',
            ),
      snapshot: json['snapshot'] == null
          ? CockpitTestEvidenceMode.onFailure
          : CockpitTestValueReader.enumeration(
              json['snapshot'],
              CockpitTestEvidenceMode.values,
              '$path.snapshot',
            ),
      failurePolicy: json['failurePolicy'] == null
          ? CockpitTestEvidenceFailurePolicy.failStep
          : CockpitTestValueReader.enumeration(
              json['failurePolicy'],
              CockpitTestEvidenceFailurePolicy.values,
              '$path.failurePolicy',
            ),
    );
  }
}

final class CockpitTestSafetyDeclaration {
  /// Creates a CockpitTestSafetyDeclaration.
  CockpitTestSafetyDeclaration({
    Iterable<CockpitTestSafetyEffect> effects =
        const <CockpitTestSafetyEffect>[],
    this.reason,
  }) : effects = Set<CockpitTestSafetyEffect>.unmodifiable(effects) {
    if (reason != null) {
      CockpitTestValueReader.string(reason, r'$.reason');
    }
  }

  final Set<CockpitTestSafetyEffect> effects;
  final String? reason;

  /// Encodes this CockpitTestSafetyDeclaration as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'effects': effects.map((effect) => effect.name).toList(growable: false),
    if (reason != null) 'reason': reason,
  };

  /// Decodes a CockpitTestSafetyDeclaration from a JSON object.
  factory CockpitTestSafetyDeclaration.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{'effects', 'reason'},
      path,
      required: const <String>{'effects'},
    );
    final rawEffects = CockpitTestValueReader.list(
      json['effects'],
      '$path.effects',
    );
    final effects = <CockpitTestSafetyEffect>{};
    for (var index = 0; index < rawEffects.length; index += 1) {
      final effect = CockpitTestValueReader.enumeration(
        rawEffects[index],
        CockpitTestSafetyEffect.values,
        '$path.effects[$index]',
      );
      if (!effects.add(effect)) {
        throw FormatException(
          'Duplicate safety effect at $path.effects[$index].',
        );
      }
    }
    return CockpitTestSafetyDeclaration(
      effects: effects,
      reason: CockpitTestValueReader.optionalString(
        json['reason'],
        '$path.reason',
      ),
    );
  }
}

final class CockpitTestTargetRequirements {
  /// Creates a CockpitTestTargetRequirements.
  CockpitTestTargetRequirements({
    required this.platform,
    required this.targetKind,
    required this.plane,
    this.appId,
    this.buildMode,
    Iterable<String> requiredCapabilities = const <String>[],
  }) : requiredCapabilities = Set<String>.unmodifiable(
         _validatedCapabilities(requiredCapabilities),
       ) {
    CockpitTestValueReader.string(platform, r'$.platform');
    CockpitTestValueReader.string(targetKind, r'$.targetKind');
    if (appId != null) {
      CockpitTestValueReader.string(appId, r'$.appId');
    }
  }

  final String platform;
  final String targetKind;
  final CockpitTestPlane plane;
  final String? appId;
  final CockpitTestBuildMode? buildMode;
  final Set<String> requiredCapabilities;

  /// Encodes this CockpitTestTargetRequirements as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'platform': platform,
    'targetKind': targetKind,
    'plane': plane.name,
    if (appId != null) 'appId': appId,
    if (buildMode != null) 'buildMode': buildMode!.name,
    if (requiredCapabilities.isNotEmpty)
      'requiredCapabilities': requiredCapabilities.toList(growable: false),
  };

  /// Decodes a CockpitTestTargetRequirements from a JSON object.
  factory CockpitTestTargetRequirements.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(
      json,
      const <String>{
        'platform',
        'targetKind',
        'plane',
        'appId',
        'buildMode',
        'requiredCapabilities',
      },
      path,
      required: const <String>{'platform', 'targetKind', 'plane'},
    );
    final rawCapabilities = json['requiredCapabilities'] == null
        ? const <Object?>[]
        : CockpitTestValueReader.list(
            json['requiredCapabilities'],
            '$path.requiredCapabilities',
          );
    return CockpitTestTargetRequirements(
      platform: CockpitTestValueReader.string(
        json['platform'],
        '$path.platform',
      ),
      targetKind: CockpitTestValueReader.string(
        json['targetKind'],
        '$path.targetKind',
      ),
      plane: CockpitTestValueReader.enumeration(
        json['plane'],
        CockpitTestPlane.values,
        '$path.plane',
      ),
      appId: CockpitTestValueReader.optionalString(
        json['appId'],
        '$path.appId',
      ),
      buildMode: json['buildMode'] == null
          ? null
          : CockpitTestValueReader.enumeration(
              json['buildMode'],
              CockpitTestBuildMode.values,
              '$path.buildMode',
            ),
      requiredCapabilities: <String>[
        for (var index = 0; index < rawCapabilities.length; index += 1)
          CockpitTestValueReader.string(
            rawCapabilities[index],
            '$path.requiredCapabilities[$index]',
          ),
      ],
    );
  }
}

final class CockpitTestCompilerLimits {
  /// Creates a CockpitTestCompilerLimits.
  factory CockpitTestCompilerLimits({
    int maxDocumentBytes = 1048576,
    int maxNesting = 16,
    int maxExpandedSteps = 10000,
    int maxLoopIterations = 1000,
    int maxRetryAttempts = 20,
  }) {
    _bounded(maxDocumentBytes, 'maxDocumentBytes', 16777216);
    _bounded(maxNesting, 'maxNesting', 64);
    _bounded(maxExpandedSteps, 'maxExpandedSteps', 100000);
    _bounded(maxLoopIterations, 'maxLoopIterations', 10000);
    _bounded(maxRetryAttempts, 'maxRetryAttempts', 100);
    return CockpitTestCompilerLimits._(
      maxDocumentBytes: maxDocumentBytes,
      maxNesting: maxNesting,
      maxExpandedSteps: maxExpandedSteps,
      maxLoopIterations: maxLoopIterations,
      maxRetryAttempts: maxRetryAttempts,
    );
  }

  const CockpitTestCompilerLimits._({
    required this.maxDocumentBytes,
    required this.maxNesting,
    required this.maxExpandedSteps,
    required this.maxLoopIterations,
    required this.maxRetryAttempts,
  });

  static const standard = CockpitTestCompilerLimits._(
    maxDocumentBytes: 1048576,
    maxNesting: 16,
    maxExpandedSteps: 10000,
    maxLoopIterations: 1000,
    maxRetryAttempts: 20,
  );

  final int maxDocumentBytes;
  final int maxNesting;
  final int maxExpandedSteps;
  final int maxLoopIterations;
  final int maxRetryAttempts;

  /// Encodes this CockpitTestCompilerLimits as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'maxDocumentBytes': maxDocumentBytes,
    'maxNesting': maxNesting,
    'maxExpandedSteps': maxExpandedSteps,
    'maxLoopIterations': maxLoopIterations,
    'maxRetryAttempts': maxRetryAttempts,
  };

  /// Decodes a CockpitTestCompilerLimits from a JSON object.
  factory CockpitTestCompilerLimits.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(json, const <String>{
      'maxDocumentBytes',
      'maxNesting',
      'maxExpandedSteps',
      'maxLoopIterations',
      'maxRetryAttempts',
    }, path);
    int read(String key, int fallback, int maximum) => json[key] == null
        ? fallback
        : CockpitTestValueReader.integer(
            json[key],
            '$path.$key',
            minimum: 1,
            maximum: maximum,
          );
    return CockpitTestCompilerLimits(
      maxDocumentBytes: read('maxDocumentBytes', 1048576, 16777216),
      maxNesting: read('maxNesting', 16, 64),
      maxExpandedSteps: read('maxExpandedSteps', 10000, 100000),
      maxLoopIterations: read('maxLoopIterations', 1000, 10000),
      maxRetryAttempts: read('maxRetryAttempts', 20, 100),
    );
  }
}

final class CockpitTestCaseDefaults {
  /// Creates a CockpitTestCaseDefaults.
  factory CockpitTestCaseDefaults({
    int commandTimeoutMs = 10000,
    int cleanupTimeoutMs = 30000,
    bool failFast = true,
    CockpitTestEvidencePolicy evidence = const CockpitTestEvidencePolicy(),
    CockpitTestCompilerLimits limits = CockpitTestCompilerLimits.standard,
  }) {
    _bounded(commandTimeoutMs, 'commandTimeoutMs', 3600000);
    _bounded(cleanupTimeoutMs, 'cleanupTimeoutMs', 3600000);
    return CockpitTestCaseDefaults._(
      commandTimeoutMs: commandTimeoutMs,
      cleanupTimeoutMs: cleanupTimeoutMs,
      failFast: failFast,
      evidence: evidence,
      limits: limits,
    );
  }

  const CockpitTestCaseDefaults._({
    required this.commandTimeoutMs,
    required this.cleanupTimeoutMs,
    required this.failFast,
    required this.evidence,
    required this.limits,
  });

  static const standard = CockpitTestCaseDefaults._(
    commandTimeoutMs: 10000,
    cleanupTimeoutMs: 30000,
    failFast: true,
    evidence: CockpitTestEvidencePolicy(),
    limits: CockpitTestCompilerLimits.standard,
  );

  final int commandTimeoutMs;
  final int cleanupTimeoutMs;
  final bool failFast;
  final CockpitTestEvidencePolicy evidence;
  final CockpitTestCompilerLimits limits;

  /// Encodes this CockpitTestCaseDefaults as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'commandTimeoutMs': commandTimeoutMs,
    'cleanupTimeoutMs': cleanupTimeoutMs,
    'failFast': failFast,
    'evidence': evidence.toJson(),
    'limits': limits.toJson(),
  };

  /// Decodes a CockpitTestCaseDefaults from a JSON object.
  factory CockpitTestCaseDefaults.fromJson(
    Object? value, {
    required String path,
  }) {
    final json = CockpitTestValueReader.object(value, path);
    CockpitTestValueReader.keys(json, const <String>{
      'commandTimeoutMs',
      'cleanupTimeoutMs',
      'failFast',
      'evidence',
      'limits',
    }, path);
    return CockpitTestCaseDefaults(
      commandTimeoutMs: json['commandTimeoutMs'] == null
          ? 10000
          : CockpitTestValueReader.integer(
              json['commandTimeoutMs'],
              '$path.commandTimeoutMs',
              minimum: 1,
              maximum: 3600000,
            ),
      cleanupTimeoutMs: json['cleanupTimeoutMs'] == null
          ? 30000
          : CockpitTestValueReader.integer(
              json['cleanupTimeoutMs'],
              '$path.cleanupTimeoutMs',
              minimum: 1,
              maximum: 3600000,
            ),
      failFast: json['failFast'] == null
          ? true
          : CockpitTestValueReader.boolean(json['failFast'], '$path.failFast'),
      evidence: json['evidence'] == null
          ? const CockpitTestEvidencePolicy()
          : CockpitTestEvidencePolicy.fromJson(
              json['evidence'],
              path: '$path.evidence',
            ),
      limits: json['limits'] == null
          ? CockpitTestCompilerLimits.standard
          : CockpitTestCompilerLimits.fromJson(
              json['limits'],
              path: '$path.limits',
            ),
    );
  }
}

Set<String> _validatedCapabilities(Iterable<String> values) {
  final result = <String>{};
  var index = 0;
  for (final value in values) {
    final normalized = CockpitTestValueReader.string(
      value,
      '\$.requiredCapabilities[$index]',
    );
    if (!result.add(normalized)) {
      throw FormatException(
        'Duplicate required capability at \$.requiredCapabilities[$index].',
      );
    }
    index += 1;
  }
  return result;
}

void _bounded(int value, String field, int maximum) {
  if (value < 1 || value > maximum) {
    throw FormatException('$field must be from 1 through $maximum.');
  }
}
