import 'cockpit_document_validation.dart';
import 'cockpit_foundation_value_reader.dart';
import 'cockpit_idempotency.dart';
import 'cockpit_operation_descriptor.dart';
import 'cockpit_run_submission.dart';

const String _runSubmissionKind = 'case.run';
const String _runSubmissionRequestSchemaRef = r'#/$defs/RunSubmission';
const String _documentValidationKind = 'case.validate';
const String _documentValidationRequestSchemaRef =
    r'#/$defs/DocumentValidationRequest';

const Set<String> _coreOperationKinds = <String>{
  _runSubmissionKind,
  _documentValidationKind,
};
const Set<String> _coreRequestSchemaRefs = <String>{
  _runSubmissionRequestSchemaRef,
  _documentValidationRequestSchemaRef,
};

typedef CockpitOperationInputDecoder<T> = T Function(Object? value);
typedef CockpitOperationAdmissionProjector<T> =
    CockpitOperationAdmissionProjection Function(T value);

final class CockpitOperationAdmissionProjection {
  /// Creates a CockpitOperationAdmissionProjection.
  CockpitOperationAdmissionProjection({
    required this.rootId,
    required this.workspaceId,
    required this.idempotencyKey,
    required Iterable<String> requiredFeatures,
  }) : requiredFeatures = List<String>.unmodifiable(requiredFeatures) {
    if (rootId != null) {
      CockpitFoundationValueReader.id(rootId, r'$.rootId');
    }
    if (workspaceId != null) {
      CockpitFoundationValueReader.id(workspaceId, r'$.workspaceId');
    }
    CockpitFoundationValueReader.ids(
      this.requiredFeatures,
      r'$.requiredFeatures',
    );
  }

  /// Creates a CockpitOperationAdmissionProjection using the named constructor `empty`.
  const CockpitOperationAdmissionProjection.empty()
    : rootId = null,
      workspaceId = null,
      idempotencyKey = null,
      requiredFeatures = const <String>[];

  final String? rootId;
  final String? workspaceId;
  final CockpitIdempotencyKey? idempotencyKey;
  final List<String> requiredFeatures;
}

final class CockpitOperationContract<T> {
  CockpitOperationContract._({
    required this.descriptor,
    required this.requestSchemaRef,
    required CockpitOperationInputDecoder<T> inputDecoder,
    required CockpitOperationAdmissionProjector<T> admissionProjector,
    required _CockpitOperationCodec codec,
  }) : _inputDecoder = inputDecoder,
       _admissionProjector = admissionProjector,
       _codec = codec {
    CockpitFoundationValueReader.schemaReference(
      requestSchemaRef,
      r'$.requestSchemaRef',
    );
    if (requestSchemaRef != descriptor.requestSchemaRef) {
      throw const FormatException(
        'Operation contract request schema does not match its descriptor.',
      );
    }
    _validateCodecBinding();
  }

  static CockpitOperationContract<CockpitRunSubmission> runSubmission({
    required CockpitOperationDescriptor descriptor,
  }) => CockpitOperationContract<CockpitRunSubmission>._(
    descriptor: descriptor,
    requestSchemaRef: _runSubmissionRequestSchemaRef,
    inputDecoder: CockpitRunSubmission.fromJson,
    admissionProjector: _projectRunSubmission,
    codec: _CockpitOperationCodec.runSubmission,
  );

  static CockpitOperationContract<CockpitDocumentValidationRequest>
  documentValidation({required CockpitOperationDescriptor descriptor}) =>
      CockpitOperationContract<CockpitDocumentValidationRequest>._(
        descriptor: descriptor,
        requestSchemaRef: _documentValidationRequestSchemaRef,
        inputDecoder: CockpitDocumentValidationRequest.fromJson,
        admissionProjector: _projectDocumentValidation,
        codec: _CockpitOperationCodec.documentValidation,
      );

  static CockpitOperationContract<T> custom<T>({
    required CockpitOperationDescriptor descriptor,
    required String requestSchemaRef,
    required CockpitOperationInputDecoder<T> inputDecoder,
    required CockpitOperationAdmissionProjector<T> admissionProjector,
  }) {
    if (_coreOperationKinds.contains(descriptor.kind) ||
        _coreRequestSchemaRefs.contains(requestSchemaRef)) {
      throw const FormatException(
        'Custom operation contracts cannot use reserved core bindings.',
      );
    }
    return CockpitOperationContract<T>._(
      descriptor: descriptor,
      requestSchemaRef: requestSchemaRef,
      inputDecoder: inputDecoder,
      admissionProjector: admissionProjector,
      codec: _CockpitOperationCodec.custom,
    );
  }

  final CockpitOperationDescriptor descriptor;
  final String requestSchemaRef;
  final CockpitOperationInputDecoder<T> _inputDecoder;
  final CockpitOperationAdmissionProjector<T> _admissionProjector;
  final _CockpitOperationCodec _codec;

  CockpitOperationAdmissionProjection decodeAdmission(Object? input) {
    return _admissionProjector(_inputDecoder(input));
  }

  void validateCatalogRegistration() {
    _validateCodecBinding();
  }

  void _validateCodecBinding() {
    final valid = switch (_codec) {
      _CockpitOperationCodec.runSubmission =>
        descriptor.kind == _runSubmissionKind &&
            requestSchemaRef == _runSubmissionRequestSchemaRef,
      _CockpitOperationCodec.documentValidation =>
        descriptor.kind == _documentValidationKind &&
            requestSchemaRef == _documentValidationRequestSchemaRef,
      _CockpitOperationCodec.custom =>
        !_coreOperationKinds.contains(descriptor.kind) &&
            !_coreRequestSchemaRefs.contains(requestSchemaRef),
    };
    if (!valid) {
      throw const FormatException(
        'Operation contract codec does not match its descriptor.',
      );
    }
  }
}

enum _CockpitOperationCodec { runSubmission, documentValidation, custom }

CockpitOperationAdmissionProjection _projectRunSubmission(
  CockpitRunSubmission submission,
) => CockpitOperationAdmissionProjection(
  rootId: null,
  workspaceId: submission.workspaceId,
  idempotencyKey: submission.idempotencyKey,
  requiredFeatures: submission.requiredFeatures,
);

CockpitOperationAdmissionProjection _projectDocumentValidation(
  CockpitDocumentValidationRequest _,
) => const CockpitOperationAdmissionProjection.empty();
