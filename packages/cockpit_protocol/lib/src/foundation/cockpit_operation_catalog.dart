import 'cockpit_api_error.dart';
import 'cockpit_operation.dart';
import 'cockpit_operation_contract.dart';
import 'cockpit_operation_descriptor.dart';

final class CockpitOperationCatalog {
  /// Creates a CockpitOperationCatalog.
  CockpitOperationCatalog(Iterable<CockpitOperationContract<Object?>> contracts)
    : _contracts = <String, CockpitOperationContract<Object?>>{} {
    for (final contract in contracts) {
      contract.validateCatalogRegistration();
      final descriptor = contract.descriptor;
      if (_contracts.containsKey(descriptor.kind)) {
        throw FormatException('Duplicate operation kind ${descriptor.kind}.');
      }
      _contracts[descriptor.kind] = contract;
    }
  }

  final Map<String, CockpitOperationContract<Object?>> _contracts;

  List<CockpitOperationDescriptor> get descriptors =>
      List<CockpitOperationDescriptor>.unmodifiable(
        _contracts.values.map((contract) => contract.descriptor),
      );

  CockpitOperationDescriptor admit(
    CockpitOperationInvocation invocation, {
    required Iterable<String> negotiatedFeatureIds,
  }) {
    final contract = _contracts[invocation.kind];
    if (contract == null) {
      throw _admissionError(
        code: CockpitErrorCode.unsupportedOperation,
        category: CockpitErrorCategory.unsupported,
        message: 'Unknown operation kind ${invocation.kind}.',
      );
    }
    final descriptor = contract.descriptor;
    late final CockpitOperationAdmissionProjection projection;
    try {
      projection = contract.decodeAdmission(invocation.input);
    } on FormatException {
      throw _inputAdmissionError(descriptor);
    }
    final scopeValid = switch (descriptor.scope) {
      CockpitOperationScope.supervisor =>
        invocation.rootId == null && invocation.workspaceId == null,
      CockpitOperationScope.root =>
        invocation.rootId != null && invocation.workspaceId == null,
      CockpitOperationScope.workspace =>
        invocation.rootId == null && invocation.workspaceId != null,
    };
    if (!scopeValid) {
      throw _admissionError(
        code: CockpitErrorCode.invalidRequest,
        category: CockpitErrorCategory.invalidInput,
        message: 'Operation scope identifiers are inconsistent.',
      );
    }
    _requireProjectionMatch(
      descriptor: descriptor,
      field: 'rootId',
      projected: projection.rootId,
      envelope: invocation.rootId,
    );
    _requireProjectionMatch(
      descriptor: descriptor,
      field: 'workspaceId',
      projected: projection.workspaceId,
      envelope: invocation.workspaceId,
    );
    _requireProjectionMatch(
      descriptor: descriptor,
      field: 'idempotencyKey',
      projected: projection.idempotencyKey,
      envelope: invocation.idempotencyKey,
    );
    final hasKey = invocation.idempotencyKey != null;
    if ((descriptor.idempotency == CockpitIdempotencyBehavior.required &&
            !hasKey) ||
        (descriptor.idempotency == CockpitIdempotencyBehavior.prohibited &&
            hasKey)) {
      throw _admissionError(
        code: CockpitErrorCode.invalidRequest,
        category: CockpitErrorCategory.invalidInput,
        message: 'Operation idempotency key does not match its descriptor.',
      );
    }
    final features = negotiatedFeatureIds.toSet();
    final missing = <String>{
      ...descriptor.requiredFeatures,
      ...invocation.requiredFeatures,
      ...projection.requiredFeatures,
    }.where((feature) => !features.contains(feature)).toList(growable: false);
    if (missing.isNotEmpty ||
        descriptor.safetyEffects.any((effect) => !effect.isKnown)) {
      throw _admissionError(
        code: CockpitErrorCode.upgradeRequired,
        category: CockpitErrorCategory.unsupported,
        message: missing.isNotEmpty
            ? 'Operation requires unavailable negotiated features.'
            : 'Operation declares an unsupported safety effect.',
        details: <String, Object?>{
          if (missing.isNotEmpty) 'missingFeatures': missing,
          if (descriptor.safetyEffects.any((effect) => !effect.isKnown))
            'unsupportedSafetyEffects': descriptor.safetyEffects
                .where((effect) => !effect.isKnown)
                .map((effect) => effect.wireValue)
                .toList(),
        },
      );
    }
    return descriptor;
  }
}

void _requireProjectionMatch({
  required CockpitOperationDescriptor descriptor,
  required String field,
  required Object? projected,
  required Object? envelope,
}) {
  if (projected != null && projected != envelope) {
    throw _inputAdmissionError(descriptor, field: field);
  }
}

CockpitApiException _inputAdmissionError(
  CockpitOperationDescriptor descriptor, {
  String? field,
}) {
  return _admissionError(
    code: CockpitErrorCode.invalidRequest,
    category: CockpitErrorCategory.invalidInput,
    message: 'Operation input does not match its request contract.',
    details: <String, Object?>{
      'kind': descriptor.kind,
      'requestSchemaRef': descriptor.requestSchemaRef,
      'field': ?field,
    },
  );
}

CockpitApiException _admissionError({
  required String code,
  required CockpitErrorCategory category,
  required String message,
  Map<String, Object?> details = const <String, Object?>{},
}) {
  return CockpitApiException(
    CockpitApiError(
      code: code,
      category: category,
      message: message,
      retryable: false,
      responsibleLayer: CockpitResponsibleLayer.supervisor,
      redactedDetails: details,
    ),
  );
}
