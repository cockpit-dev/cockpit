import 'package:cockpit_protocol/cockpit_protocol.dart';

void main() {
  final server = CockpitServerInfo(
    instanceId: 'supervisorExample',
    apiVersion: CockpitApiVersion(major: 2, minor: 0),
    engineVersion: '2.0.0',
    startedAt: DateTime.utc(2026, 7, 20),
    features: <CockpitFeatureDescriptor>[
      CockpitFeatureDescriptor(
        id: CockpitFoundationFeature.additiveResponseFields.id,
        revision: 1,
        minimumApiMinor: 0,
      ),
    ],
  );
  final negotiation = CockpitProtocolNegotiator.negotiate(
    request: CockpitNegotiationRequest(
      apiVersion: CockpitApiVersion(major: 2, minor: 0),
      requiredFeatures: <String>[
        CockpitFoundationFeature.additiveResponseFields.id,
      ],
    ),
    server: server,
  );

  final descriptor = CockpitOperationDescriptor(
    kind: 'case.validate',
    title: 'Validate case',
    description: 'Compile and validate one standalone case document.',
    scope: CockpitOperationScope.workspace,
    mutationClass: CockpitMutationClass.readOnly,
    idempotency: CockpitIdempotencyBehavior.prohibited,
    executionMode: CockpitOperationExecutionMode.synchronous,
    defaultTimeoutMs: 30000,
    maximumTimeoutMs: 300000,
    requestSchemaRef: '#/\$defs/DocumentValidationRequest',
    responseSchemaRef: '#/\$defs/DocumentValidationResult',
  );
  final invocation = CockpitOperationInvocation(
    kind: descriptor.kind,
    workspaceId: 'workspaceExample',
    input: const <String, Object?>{
      'format': 'yaml',
      'sourceText': 'schemaVersion: cockpit.test/v2',
    },
  );
  CockpitOperationCatalog(<CockpitOperationContract<Object?>>[
    CockpitOperationContract.documentValidation(descriptor: descriptor),
  ]).admit(invocation, negotiatedFeatureIds: negotiation.featureIds);

  print(server.toJson());
}
