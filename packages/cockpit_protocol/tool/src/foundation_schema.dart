import 'foundation_schema_common.dart';
import 'foundation_schema_execution.dart';
import 'foundation_schema_helpers.dart';
import 'foundation_schema_resources.dart';

Map<String, Object?> buildFoundationSchema() {
  final definitions = <String, Object?>{
    ...foundationCommonDefinitions(),
    ...foundationResourceDefinitions(),
    ...foundationExecutionDefinitions(),
  };
  return <String, Object?>{
    r'$schema': 'https://json-schema.org/draft/2020-12/schema',
    r'$id':
        'https://github.com/cockpit-dev/cockpit/packages/cockpit_protocol/schema/cockpit.foundation.v2.schema.json',
    'title': 'Cockpit 2.0 foundation API contracts',
    'description':
        'Strict platform-neutral contracts for Cockpit Supervisor clients, resources, operations, case and suite runs, events, artifacts, reports, and leases.',
    'oneOf': <Object?>[
      for (final definition in const <String>[
        'ServerInfo',
        'CapabilityDocument',
        'RootResource',
        'WorkspaceResource',
        'AutomationTargetResource',
        'DocumentResource',
        'DocumentValidationResult',
        'OperationInvocation',
        'OperationResult',
        'RunSubmission',
        'RunAccepted',
        'RunResource',
        'RunEvent',
        'ArtifactResource',
        'LeaseResource',
        'ApiErrorResponse',
      ])
        schemaRef(definition),
    ],
    r'$defs': definitions,
  };
}
