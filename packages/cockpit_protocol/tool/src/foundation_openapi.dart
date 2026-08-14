import 'package:cockpit_protocol/src/foundation/cockpit_foundation_constraints.dart';

import 'foundation_openapi_helpers.dart';
import 'foundation_openapi_paths.dart';

Map<String, Object?> buildFoundationOpenApi() => <String, Object?>{
  'openapi': '3.1.0',
  'jsonSchemaDialect': 'https://json-schema.org/draft/2020-12/schema',
  'info': <String, Object?>{
    'title': 'Cockpit Supervisor API',
    'version': '2.0.0',
    'description':
        'Authenticated Cockpit foundation v2 loopback API for discovery, workspaces, typed operations, case and suite runs, durable events, immutable artifacts, and aggregate reports.',
  },
  'servers': <Object?>[
    <String, Object?>{
      'url': 'http://127.0.0.1:{port}',
      'variables': <String, Object?>{
        'port': <String, Object?>{
          'default': '0',
          'description': 'Ephemeral port published in daemon discovery.',
        },
      },
    },
  ],
  'security': <Object?>[
    <String, Object?>{'bearerAuth': <Object?>[]},
  ],
  'paths': buildFoundationApiPaths(),
  'components': <String, Object?>{
    'securitySchemes': <String, Object?>{
      'bearerAuth': <String, Object?>{
        'type': 'http',
        'scheme': 'bearer',
        'bearerFormat': 'opaque current-user token',
        'description':
            'Read from the current-user daemon discovery file. Tokens are never accepted in URLs.',
      },
    },
    'parameters': <String, Object?>{
      'ApiVersion': <String, Object?>{
        'name': 'Cockpit-API-Version',
        'in': 'header',
        'required': true,
        'description': 'Requested API major and maximum supported minor.',
        'schema': <String, Object?>{
          'type': 'string',
          'pattern': r'^2\.[0-9]+$',
        },
      },
      'RequiredFeatures': <String, Object?>{
        'name': 'Cockpit-Required-Features',
        'in': 'header',
        'required': false,
        'description': 'Comma-separated required feature ids.',
        'schema': <String, Object?>{'type': 'string', 'maxLength': 4096},
      },
      ...pageParameters(),
    },
    'schemas': <String, Object?>{
      for (final name in const <String>[
        'ServerInfo',
        'CapabilityDocument',
        'RootPage',
        'RootRegistration',
        'RootResource',
        'RootRemoval',
        'OperationPage',
        'OperationInvocation',
        'OperationResult',
        'WorkspacePage',
        'WorkspaceRegistration',
        'WorkspaceRebind',
        'WorkspaceRemoval',
        'WorkspaceResource',
        'AutomationTargetPage',
        'AutomationTargetResource',
        'DocumentPage',
        'DocumentValidationRequest',
        'DocumentValidationResult',
        'CasePage',
        'RunSubmission',
        'RunAccepted',
        'RunPage',
        'RunResource',
        'RunCancellationRequest',
        'RunCancellation',
        'RunCasePage',
        'RunEvent',
        'ArtifactPage',
        'ArtifactResource',
        'ApiErrorResponse',
      ])
        name: <String, Object?>{
          r'$ref': '../schema/cockpit.foundation.v2.schema.json#/\$defs/$name',
        },
    },
    'responses': _errorResponses(),
  },
  'x-cockpit-request-limit-bytes': cockpitFoundationRequestMaximumBytes,
  'x-cockpit-json-maximum-depth': cockpitFoundationJsonMaximumDepth,
  'x-cockpit-json-maximum-nodes': cockpitFoundationJsonMaximumNodes,
  'x-cockpit-cors': 'deny',
  'x-cockpit-deferred-capabilities': <String>['aiExploration'],
  'x-cockpit-error-statuses': <String, Object?>{
    '400': <String>['invalidInput'],
    '401': <String>['authenticationRequired'],
    '404': <String>['notFound'],
    '409': <String>['conflict', 'staleReference', 'eventGap'],
    '413': <String>['requestTooLarge'],
    '415': <String>['unsupportedMediaType'],
    '422': <String>[
      'driver',
      'locator',
      'assertion',
      'application',
      'evidence',
    ],
    '426': <String>['upgradeRequired'],
    '429': <String>['resourceBusy'],
    '500': <String>['internal'],
    '503': <String>['environment', 'interrupted'],
  },
};

Map<String, Object?> _errorResponses() => <String, Object?>{
  'BadRequest': _errorResponse('Invalid request or schema.', 'invalidInput'),
  'Unauthorized': _errorResponse(
    'Missing or invalid bearer token.',
    'authenticationRequired',
  ),
  'NotFound': _errorResponse('Unknown or unauthorized resource.', 'notFound'),
  'Conflict': _errorResponse(
    'Ownership, state, idempotency, or replay conflict.',
    'conflict',
  ),
  'TooLarge': _errorResponse('Request exceeds one MiB.', 'requestTooLarge'),
  'UnsupportedMedia': _errorResponse(
    'Content-Type is not application/json.',
    'unsupportedMediaType',
  ),
  'Unprocessable': _errorResponse(
    'Typed request was admitted but execution failed.',
    'executionFailed',
  ),
  'UpgradeRequired': _errorResponse(
    'API major or required feature is unavailable.',
    'upgradeRequired',
  ),
  'ResourceBusy': _errorResponse(
    'A required exclusive resource is unavailable.',
    'resourceBusy',
  ),
  'Internal': _errorResponse('Cockpit internal failure.', 'internalError'),
  'Unavailable': _errorResponse(
    'Supervisor, worker, provider, or environment unavailable.',
    'environmentUnavailable',
  ),
};

Map<String, Object?> _errorResponse(String description, String exampleCode) =>
    <String, Object?>{
      'description': description,
      'content': <String, Object?>{
        'application/json': <String, Object?>{
          'schema': componentSchemaRef('ApiErrorResponse'),
          'examples': <String, Object?>{
            exampleCode: <String, Object?>{
              'summary': exampleCode,
              'value': <String, Object?>{
                'schemaVersion': 'cockpit.foundation/v2',
                'requestId': 'requestExample',
                'timestamp': '2026-07-20T00:00:00.000Z',
                'failure': <String, Object?>{
                  'primary': <String, Object?>{
                    'code': exampleCode,
                    'category': _exampleCategory(exampleCode),
                    'message': description,
                    'retryable': false,
                    'responsibleLayer': 'supervisor',
                  },
                },
              },
            },
          },
        },
      },
    };

String _exampleCategory(String code) {
  if (code == 'upgradeRequired') {
    return 'unsupported';
  }
  if (code == 'resourceBusy') {
    return 'resource';
  }
  if (code == 'internalError') {
    return 'internal';
  }
  if (code == 'environmentUnavailable') {
    return 'environment';
  }
  return 'invalidInput';
}
