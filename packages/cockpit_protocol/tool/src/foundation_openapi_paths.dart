import 'foundation_openapi_helpers.dart';

Map<String, Object?> buildFoundationApiPaths() => <String, Object?>{
  '/api/v2/server': <String, Object?>{
    'get': <String, Object?>{
      'operationId': 'getServer',
      'summary': 'Read Supervisor identity and protocol version',
      'responses': <String, Object?>{
        '200': jsonResponse('Server information.', 'ServerInfo'),
        '401': <String, Object?>{
          r'$ref': '#/components/responses/Unauthorized',
        },
        '500': <String, Object?>{r'$ref': '#/components/responses/Internal'},
      },
    },
  },
  '/api/v2/capabilities': <String, Object?>{
    'get': negotiatedOperation(
      operationId: 'getCapabilities',
      summary: 'Discover negotiated features, operations, and resources',
      responses: <String, Object?>{
        '200': jsonResponse('Capability document.', 'CapabilityDocument'),
      },
    ),
  },
  '/api/v2/roots': <String, Object?>{
    'get': negotiatedOperation(
      operationId: 'listRoots',
      summary: 'List registered allowed roots',
      parameters: _pageParameters(),
      responses: <String, Object?>{
        '200': jsonResponse('Registered roots.', 'RootPage'),
      },
    ),
    'post': negotiatedOperation(
      operationId: 'registerRoot',
      summary: 'Register an allowed source root',
      requestSchema: 'RootRegistration',
      responses: <String, Object?>{
        '201': jsonResponse('Registered root.', 'RootResource'),
      },
    ),
  },
  '/api/v2/roots/{rootId}': <String, Object?>{
    'parameters': <Object?>[_pathParameter('rootId')],
    'delete': negotiatedOperation(
      operationId: 'removeRoot',
      summary: 'Drain or retire an allowed root',
      requestSchema: 'RootRemoval',
      responses: <String, Object?>{
        '200': jsonResponse('Retired root.', 'RootResource'),
      },
    ),
  },
  '/api/v2/operations': <String, Object?>{
    'get': negotiatedOperation(
      operationId: 'listSupervisorOperations',
      summary: 'List Supervisor and root operation descriptors',
      parameters: _pageParameters(),
      responses: <String, Object?>{
        '200': jsonResponse('Operation descriptors.', 'OperationPage'),
      },
    ),
    'post': negotiatedOperation(
      operationId: 'executeSupervisorOperation',
      summary: 'Execute a typed Supervisor or root operation',
      requestSchema: 'OperationInvocation',
      responses: <String, Object?>{
        '200': jsonResponse('Synchronous operation result.', 'OperationResult'),
        '202': jsonResponse('Accepted operation job.', 'OperationResult'),
      },
    ),
  },
  '/api/v2/workspaces': <String, Object?>{
    'get': negotiatedOperation(
      operationId: 'listWorkspaces',
      summary: 'List registered workspaces',
      parameters: _pageParameters(),
      responses: <String, Object?>{
        '200': jsonResponse('Registered workspaces.', 'WorkspacePage'),
      },
    ),
  },
  '/api/v2/workspaces/register': <String, Object?>{
    'post': negotiatedOperation(
      operationId: 'registerWorkspace',
      summary: 'Register a checkout under an allowed root',
      requestSchema: 'WorkspaceRegistration',
      responses: <String, Object?>{
        '201': jsonResponse('Registered workspace.', 'WorkspaceResource'),
      },
    ),
  },
  '/api/v2/workspaces/{workspaceId}/rebind': <String, Object?>{
    'parameters': <Object?>[_pathParameter('workspaceId')],
    'post': negotiatedOperation(
      operationId: 'rebindWorkspace',
      summary: 'Explicitly bind a moved checkout path',
      requestSchema: 'WorkspaceRebind',
      responses: <String, Object?>{
        '200': jsonResponse('Rebound workspace.', 'WorkspaceResource'),
      },
    ),
  },
  '/api/v2/workspaces/{workspaceId}': <String, Object?>{
    'parameters': <Object?>[_pathParameter('workspaceId')],
    'delete': negotiatedOperation(
      operationId: 'removeWorkspace',
      summary: 'Drain or unregister a workspace',
      requestSchema: 'WorkspaceRemoval',
      responses: <String, Object?>{
        '200': jsonResponse('Retired workspace.', 'WorkspaceResource'),
      },
    ),
  },
  '/api/v2/workspaces/{workspaceId}/targets': <String, Object?>{
    'parameters': <Object?>[_pathParameter('workspaceId')],
    'get': negotiatedOperation(
      operationId: 'listAutomationTargets',
      summary: 'List registered automation targets for a workspace',
      parameters: _pageParameters(),
      responses: <String, Object?>{
        '200': jsonResponse(
          'Registered automation targets.',
          'AutomationTargetPage',
        ),
      },
    ),
  },
  '/api/v2/workspaces/{workspaceId}/targets/{targetId}': <String, Object?>{
    'parameters': <Object?>[
      _pathParameter('workspaceId'),
      _pathParameter('targetId'),
    ],
    'get': negotiatedOperation(
      operationId: 'getAutomationTarget',
      summary: 'Read one registered workspace automation target',
      responses: <String, Object?>{
        '200': jsonResponse(
          'Registered automation target.',
          'AutomationTargetResource',
        ),
      },
    ),
  },
  '/api/v2/workspaces/{workspaceId}/documents': <String, Object?>{
    'parameters': <Object?>[_pathParameter('workspaceId')],
    'get': negotiatedOperation(
      operationId: 'listDocuments',
      summary: 'List indexed case, suite, and project documents',
      parameters: _pageParameters(),
      responses: <String, Object?>{
        '200': jsonResponse('Indexed documents.', 'DocumentPage'),
      },
    ),
  },
  '/api/v2/workspaces/{workspaceId}/documents/validate': <String, Object?>{
    'parameters': <Object?>[_pathParameter('workspaceId')],
    'post': negotiatedOperation(
      operationId: 'validateDocument',
      summary: 'Compile and validate an inline test document',
      requestSchema: 'DocumentValidationRequest',
      responses: <String, Object?>{
        '200': jsonResponse('Validation result.', 'DocumentValidationResult'),
      },
    ),
  },
  '/api/v2/workspaces/{workspaceId}/cases': <String, Object?>{
    'parameters': <Object?>[_pathParameter('workspaceId')],
    'get': negotiatedOperation(
      operationId: 'listCases',
      summary: 'List indexed standalone cases',
      parameters: _pageParameters(),
      responses: <String, Object?>{
        '200': jsonResponse('Indexed cases.', 'CasePage'),
      },
    ),
  },
  '/api/v2/workspaces/{workspaceId}/operations': <String, Object?>{
    'parameters': <Object?>[_pathParameter('workspaceId')],
    'get': negotiatedOperation(
      operationId: 'listWorkspaceOperations',
      summary: 'List workspace operation descriptors',
      parameters: _pageParameters(),
      responses: <String, Object?>{
        '200': jsonResponse('Workspace operations.', 'OperationPage'),
      },
    ),
    'post': negotiatedOperation(
      operationId: 'executeWorkspaceOperation',
      summary: 'Execute a typed workspace operation',
      requestSchema: 'OperationInvocation',
      responses: <String, Object?>{
        '200': jsonResponse('Synchronous operation result.', 'OperationResult'),
        '202': jsonResponse('Accepted operation job.', 'OperationResult'),
      },
    ),
  },
  '/api/v2/workspaces/{workspaceId}/runs': <String, Object?>{
    'parameters': <Object?>[_pathParameter('workspaceId')],
    'post': negotiatedOperation(
      operationId: 'submitRun',
      summary: 'Submit one inline or indexed case or suite',
      requestSchema: 'RunSubmission',
      responses: <String, Object?>{
        '202': jsonResponse('Accepted run.', 'RunAccepted'),
      },
    ),
  },
  '/api/v2/runs/{runId}': <String, Object?>{
    'parameters': <Object?>[_pathParameter('runId')],
    'get': negotiatedOperation(
      operationId: 'getRun',
      summary: 'Read a run projection',
      responses: <String, Object?>{
        '200': jsonResponse('Run projection.', 'RunResource'),
      },
    ),
  },
  '/api/v2/runs/{runId}/cancel': <String, Object?>{
    'parameters': <Object?>[_pathParameter('runId')],
    'post': negotiatedOperation(
      operationId: 'cancelRun',
      summary: 'Request idempotent run cancellation',
      requestSchema: 'RunCancellationRequest',
      responses: <String, Object?>{
        '202': jsonResponse(
          'Cancellation accepted or replayed.',
          'RunCancellation',
        ),
      },
    ),
  },
  '/api/v2/runs/{runId}/events': <String, Object?>{
    'parameters': <Object?>[_pathParameter('runId')],
    'get': negotiatedOperation(
      operationId: 'streamRunEvents',
      summary: 'Resume and stream durable run events',
      description:
          'Uses strictly increasing sequence ids. Last-Event-ID and afterSequence resume after the named event; a retained-history gap returns 409 with explicit boundary details.',
      parameters: <Map<String, Object?>>[
        <String, Object?>{
          'name': 'afterSequence',
          'in': 'query',
          'required': false,
          'schema': <String, Object?>{'type': 'integer', 'minimum': 0},
        },
        <String, Object?>{
          'name': 'Last-Event-ID',
          'in': 'header',
          'required': false,
          'schema': <String, Object?>{
            'type': 'string',
            'pattern': r'^[A-Za-z][A-Za-z0-9._-]{0,127}$',
          },
        },
      ],
      responses: <String, Object?>{
        '200': <String, Object?>{
          'description':
              'SSE stream. Each data field is one RunEvent JSON value.',
          'content': <String, Object?>{
            'text/event-stream': <String, Object?>{
              'schema': <String, Object?>{'type': 'string'},
            },
          },
        },
      },
    ),
  },
  '/api/v2/runs/{runId}/report': <String, Object?>{
    'parameters': <Object?>[_pathParameter('runId')],
    'get': negotiatedOperation(
      operationId: 'getSuiteReport',
      summary: 'Read the finalized canonical suite report',
      responses: <String, Object?>{
        '200': <String, Object?>{
          'description': 'Finalized cockpit.report/v2 aggregate report.',
          'content': <String, Object?>{
            'application/json': <String, Object?>{
              'schema': <String, Object?>{
                r'$ref':
                    r'../schema/cockpit.test.v2.schema.json#/$defs/suiteReport',
              },
            },
          },
        },
        '404': <String, Object?>{r'$ref': '#/components/responses/NotFound'},
      },
    ),
  },
  '/api/v2/runs/{runId}/cases': <String, Object?>{
    'parameters': <Object?>[_pathParameter('runId')],
    'get': negotiatedOperation(
      operationId: 'listRunCases',
      summary: 'Read cases executed by a case or suite run',
      parameters: _pageParameters(),
      responses: <String, Object?>{
        '200': jsonResponse('Run case collection.', 'RunCasePage'),
      },
    ),
  },
  '/api/v2/runs/{runId}/artifacts': <String, Object?>{
    'parameters': <Object?>[_pathParameter('runId')],
    'get': negotiatedOperation(
      operationId: 'listRunArtifacts',
      summary: 'List immutable artifact metadata for a run',
      parameters: _pageParameters(),
      responses: <String, Object?>{
        '200': jsonResponse(
          'Run artifact metadata collection.',
          'ArtifactPage',
        ),
      },
    ),
  },
  '/api/v2/runs/{runId}/artifacts/{artifactId}': <String, Object?>{
    'parameters': <Object?>[
      _pathParameter('runId'),
      _pathParameter('artifactId'),
    ],
    'get': negotiatedOperation(
      operationId: 'readArtifact',
      summary: 'Read a digest-verified immutable artifact',
      responses: <String, Object?>{
        '200': <String, Object?>{
          'description':
              'Artifact bytes after ownership and SHA-256 verification.',
          'headers': <String, Object?>{
            'Digest': <String, Object?>{
              'required': true,
              'schema': <String, Object?>{
                'type': 'string',
                'pattern': r'^sha-256=.+$',
              },
            },
          },
          'content': <String, Object?>{
            'application/octet-stream': <String, Object?>{
              'schema': <String, Object?>{'type': 'string', 'format': 'binary'},
            },
          },
        },
      },
    ),
  },
};

List<Map<String, Object?>> _pageParameters() => <Map<String, Object?>>[
  parameterRef('Limit'),
  parameterRef('Cursor'),
];

Map<String, Object?> _pathParameter(String name) => <String, Object?>{
  'name': name,
  'in': 'path',
  'required': true,
  'schema': <String, Object?>{
    'type': 'string',
    'pattern': r'^[A-Za-z][A-Za-z0-9._-]{0,127}$',
  },
};
