import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../foundation/cockpit_locked_json_store.dart';
import '../foundation/cockpit_permissions.dart';
import '../test/cockpit_test_safety_policy.dart';
import 'cockpit_supervisor_operation_catalog.dart';

final class CockpitSupervisorAuthorizationPolicy {
  CockpitSupervisorAuthorizationPolicy({
    this.mode = CockpitAuthorizationMode.restricted,
    Iterable<String> allowedDangerousOperations = const <String>[],
    Iterable<CockpitSafetyEffect> allowedOperationSafetyEffects = const {},
    Iterable<CockpitTestTargetEnvironment> allowedTargetEnvironments = const {
      CockpitTestTargetEnvironment.development,
      CockpitTestTargetEnvironment.test,
      CockpitTestTargetEnvironment.staging,
    },
    Iterable<CockpitTestSafetyEffect> allowedSafetyEffects = const {},
    Iterable<String> allowedEnvironmentSecretNames = const <String>[],
  }) : allowedDangerousOperations = Set.unmodifiable(
         allowedDangerousOperations,
       ),
       allowedOperationSafetyEffects = Set.unmodifiable(
         allowedOperationSafetyEffects,
       ),
       allowedTargetEnvironments = Set.unmodifiable(allowedTargetEnvironments),
       allowedSafetyEffects = Set.unmodifiable(allowedSafetyEffects),
       allowedEnvironmentSecretNames = Set.unmodifiable(
         allowedEnvironmentSecretNames,
       ) {
    for (final kind in this.allowedDangerousOperations) {
      CockpitSupervisorOperationMetadata metadata;
      try {
        metadata = CockpitSupervisorOperationCatalog.require(kind);
      } on CockpitApiException {
        throw ArgumentError.value(kind, 'allowedDangerousOperations');
      }
      if (!metadata.requiresExplicitAuthorization) {
        throw ArgumentError.value(kind, 'allowedDangerousOperations');
      }
    }
    for (final name in this.allowedEnvironmentSecretNames) {
      if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,127}$').hasMatch(name)) {
        throw ArgumentError.value(name, 'allowedEnvironmentSecretNames');
      }
    }
  }

  final Set<String> allowedDangerousOperations;
  final CockpitAuthorizationMode mode;
  final Set<CockpitSafetyEffect> allowedOperationSafetyEffects;
  final Set<CockpitTestTargetEnvironment> allowedTargetEnvironments;
  final Set<CockpitTestSafetyEffect> allowedSafetyEffects;
  final Set<String> allowedEnvironmentSecretNames;

  bool get isYolo => mode == CockpitAuthorizationMode.yolo;

  Set<CockpitTestTargetEnvironment> get effectiveAllowedTargetEnvironments =>
      isYolo
      ? Set<CockpitTestTargetEnvironment>.unmodifiable(
          CockpitTestTargetEnvironment.values,
        )
      : allowedTargetEnvironments;

  Set<CockpitTestSafetyEffect> get effectiveAllowedSafetyEffects => isYolo
      ? Set<CockpitTestSafetyEffect>.unmodifiable(
          CockpitTestSafetyEffect.values,
        )
      : allowedSafetyEffects;

  bool allowsEnvironmentSecretName(String name) =>
      isYolo || allowedEnvironmentSecretNames.contains(name);

  CockpitSupervisorAuthorizationPolicy withMode(
    CockpitAuthorizationMode value,
  ) => CockpitSupervisorAuthorizationPolicy(
    mode: value,
    allowedDangerousOperations: allowedDangerousOperations,
    allowedOperationSafetyEffects: allowedOperationSafetyEffects,
    allowedTargetEnvironments: allowedTargetEnvironments,
    allowedSafetyEffects: allowedSafetyEffects,
    allowedEnvironmentSecretNames: allowedEnvironmentSecretNames,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 'cockpit.supervisor.authorization/v2',
    'allowedDangerousOperations': allowedDangerousOperations.toList()..sort(),
    'allowedOperationSafetyEffects':
        allowedOperationSafetyEffects.map((value) => value.name).toList()
          ..sort(),
    'allowedTargetEnvironments':
        allowedTargetEnvironments.map((value) => value.name).toList()..sort(),
    'allowedSafetyEffects':
        allowedSafetyEffects.map((value) => value.name).toList()..sort(),
    'allowedEnvironmentSecretNames': allowedEnvironmentSecretNames.toList()
      ..sort(),
  };

  factory CockpitSupervisorAuthorizationPolicy.fromJson(Object? value) {
    if (value is! Map<Object?, Object?> ||
        value.keys.any((key) => key is! String)) {
      throw const FormatException('Authorization policy must be an object.');
    }
    final json = Map<String, Object?>.from(value);
    const fields = <String>{
      'schemaVersion',
      'allowedDangerousOperations',
      'allowedOperationSafetyEffects',
      'allowedTargetEnvironments',
      'allowedSafetyEffects',
      'allowedEnvironmentSecretNames',
    };
    if (json.length != fields.length || !fields.every(json.containsKey)) {
      throw const FormatException('Authorization policy fields are invalid.');
    }
    if (json['schemaVersion'] != 'cockpit.supervisor.authorization/v2') {
      throw const FormatException('Authorization policy schema is invalid.');
    }
    try {
      return CockpitSupervisorAuthorizationPolicy(
        allowedDangerousOperations: _strings(
          json['allowedDangerousOperations'],
          'allowedDangerousOperations',
        ),
        allowedOperationSafetyEffects: _enums(
          json['allowedOperationSafetyEffects'],
          CockpitSafetyEffect.values,
          'allowedOperationSafetyEffects',
        ),
        allowedTargetEnvironments: _enums(
          json['allowedTargetEnvironments'],
          CockpitTestTargetEnvironment.values,
          'allowedTargetEnvironments',
        ),
        allowedSafetyEffects: _enums(
          json['allowedSafetyEffects'],
          CockpitTestSafetyEffect.values,
          'allowedSafetyEffects',
        ),
        allowedEnvironmentSecretNames: _strings(
          json['allowedEnvironmentSecretNames'],
          'allowedEnvironmentSecretNames',
        ),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Authorization policy value is invalid: $error');
    }
  }

  void authorizeOperation(
    CockpitSupervisorOperationMetadata metadata,
    CockpitOperationInvocation invocation,
  ) {
    if (isYolo) return;
    final descriptor = metadata.descriptor;
    if (metadata.requiresExplicitAuthorization &&
        !allowedDangerousOperations.contains(descriptor.kind)) {
      throw CockpitApiException(
        CockpitApiError(
          code: 'operationNotAuthorized',
          category: CockpitErrorCategory.environment,
          message:
              'Operation ${descriptor.kind} is not explicitly authorized by Supervisor policy.',
          retryable: false,
          responsibleLayer: CockpitResponsibleLayer.supervisor,
        ),
      );
    }
    final deniedEffects = descriptor.safetyEffects
        .map((effect) => effect.knownValue)
        .whereType<CockpitSafetyEffect>()
        .where((effect) => !allowedOperationSafetyEffects.contains(effect))
        .toList(growable: false);
    if (deniedEffects.isNotEmpty) {
      throw CockpitApiException(
        CockpitApiError(
          code: CockpitErrorCode.authorizationDenied,
          category: CockpitErrorCategory.environment,
          message:
              'Operation ${descriptor.kind} requests safety effects that are not authorized.',
          retryable: false,
          responsibleLayer: CockpitResponsibleLayer.supervisor,
          redactedDetails: <String, Object?>{
            'safetyEffects': deniedEffects
                .map((effect) => effect.name)
                .toList(),
          },
        ),
      );
    }
    final environment = invocation.input['targetEnvironment'];
    if (environment == null) return;
    if (environment is! String) {
      throw const FormatException('targetEnvironment must be a string.');
    }
    final targetEnvironment = CockpitTestTargetEnvironment.values
        .where((value) => value.name == environment)
        .firstOrNull;
    if (targetEnvironment == null ||
        !allowedTargetEnvironments.contains(targetEnvironment)) {
      throw CockpitApiException(
        CockpitApiError(
          code: CockpitErrorCode.authorizationDenied,
          category: CockpitErrorCategory.environment,
          message: 'Target environment $environment is not authorized.',
          retryable: false,
          responsibleLayer: CockpitResponsibleLayer.supervisor,
        ),
      );
    }
  }
}

List<String> _strings(Object? value, String field) {
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw FormatException('$field must be an array of strings.');
  }
  final result = value.cast<String>();
  if (result.toSet().length != result.length) {
    throw FormatException('$field contains duplicates.');
  }
  return result;
}

List<T> _enums<T extends Enum>(Object? value, List<T> values, String field) =>
    _strings(value, field)
        .map(
          (name) =>
              values.where((value) => value.name == name).firstOrNull ??
              (throw FormatException('$field contains unknown value $name.')),
        )
        .toList(growable: false);

final class CockpitSupervisorAuthorizationPolicyStore {
  CockpitSupervisorAuthorizationPolicyStore({
    required String path,
    required CockpitPermissionHardener permissionHardener,
    required CockpitDirectorySyncer directorySyncer,
  }) : _store = CockpitLockedJsonStore<CockpitSupervisorAuthorizationPolicy>(
         path: path,
         codec: const _AuthorizationPolicyCodec(),
         createInitial: CockpitSupervisorAuthorizationPolicy.new,
         permissionHardener: permissionHardener,
         directorySyncer: directorySyncer,
         maximumBytes: 1024 * 1024,
       );

  final CockpitLockedJsonStore<CockpitSupervisorAuthorizationPolicy> _store;

  Future<CockpitSupervisorAuthorizationPolicy> read() => _store.transact(
    (current) => CockpitLockedJsonUpdate.readOnly(current, current),
  );

  Future<void> replace(CockpitSupervisorAuthorizationPolicy policy) =>
      _store.transact<void>((_) => CockpitLockedJsonUpdate.write(policy, null));
}

final class _AuthorizationPolicyCodec
    implements CockpitJsonCodec<CockpitSupervisorAuthorizationPolicy> {
  const _AuthorizationPolicyCodec();

  @override
  CockpitSupervisorAuthorizationPolicy decode(Object? json) =>
      CockpitSupervisorAuthorizationPolicy.fromJson(json);

  @override
  Object? encode(CockpitSupervisorAuthorizationPolicy value) => value.toJson();
}
