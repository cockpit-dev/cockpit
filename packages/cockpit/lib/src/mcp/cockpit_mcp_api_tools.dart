import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

import '../supervisor/cockpit_supervisor_api_client.dart';
import 'cockpit_mcp_api_resources.dart';
import 'cockpit_mcp_error.dart';
import 'cockpit_mcp_tool.dart';

List<CockpitMcpTool> cockpitMcpApiTools(
  CockpitMcpClientProvider client,
) => <CockpitMcpTool>[
  _CockpitApiTool(
    client: client,
    name: 'root_register',
    description: 'Register an absolute project root with Supervisor.',
    inputSchema: _schema(
      properties: <String, Object?>{'path': _string(), 'label': _string()},
      required: const <String>['path'],
    ),
    action: (api, arguments) async {
      _only(arguments, const <String>{'path', 'label'});
      return (await api.registerRoot(
        CockpitRootRegistration(
          path: _requiredString(arguments, 'path'),
          label: _optionalString(arguments, 'label'),
        ),
      )).toJson();
    },
  ),
  _CockpitApiTool(
    client: client,
    name: 'root_remove',
    description: 'Unregister an explicit project root.',
    inputSchema: _schema(
      properties: <String, Object?>{
        'rootId': _string(),
        'force': _boolean(),
        'drainTimeoutMs': _integer(minimum: 0, maximum: 300000),
      },
      required: const <String>['rootId'],
    ),
    action: (api, arguments) async {
      _only(arguments, const <String>{'rootId', 'force', 'drainTimeoutMs'});
      return (await api.removeRoot(
        _requiredString(arguments, 'rootId'),
        CockpitRootRemoval(
          force: _optionalBool(arguments, 'force') ?? false,
          drainTimeoutMs: _optionalInt(arguments, 'drainTimeoutMs') ?? 30000,
        ),
      )).toJson();
    },
  ),
  _CockpitApiTool(
    client: client,
    name: 'workspace_register',
    description: 'Register an explicit workspace checkout.',
    inputSchema: _schema(
      properties: <String, Object?>{'rootId': _string(), 'path': _string()},
      required: const <String>['rootId', 'path'],
    ),
    action: (api, arguments) async {
      _only(arguments, const <String>{'rootId', 'path'});
      return (await api.registerWorkspace(
        CockpitWorkspaceRegistration(
          rootId: _requiredString(arguments, 'rootId'),
          path: _requiredString(arguments, 'path'),
        ),
      )).toJson();
    },
  ),
  _CockpitApiTool(
    client: client,
    name: 'workspace_rebind',
    description: 'Rebind an explicit workspace to a checkout identity.',
    inputSchema: _schema(
      properties: <String, Object?>{
        'workspaceId': _string(),
        'path': _string(),
        'expectedCheckoutId': _string(),
      },
      required: const <String>['workspaceId', 'path', 'expectedCheckoutId'],
    ),
    action: (api, arguments) async {
      _only(arguments, const <String>{
        'workspaceId',
        'path',
        'expectedCheckoutId',
      });
      return (await api.rebindWorkspace(
        _requiredString(arguments, 'workspaceId'),
        CockpitWorkspaceRebind(
          path: _requiredString(arguments, 'path'),
          expectedCheckoutId: _requiredString(arguments, 'expectedCheckoutId'),
        ),
      )).toJson();
    },
  ),
  _CockpitApiTool(
    client: client,
    name: 'workspace_unregister',
    description: 'Unregister an explicit workspace.',
    inputSchema: _schema(
      properties: <String, Object?>{
        'workspaceId': _string(),
        'force': _boolean(),
        'drainTimeoutMs': _integer(minimum: 0, maximum: 300000),
      },
      required: const <String>['workspaceId'],
    ),
    action: (api, arguments) async {
      _only(arguments, const <String>{
        'workspaceId',
        'force',
        'drainTimeoutMs',
      });
      return (await api.removeWorkspace(
        _requiredString(arguments, 'workspaceId'),
        CockpitWorkspaceRemoval(
          force: _optionalBool(arguments, 'force') ?? false,
          drainTimeoutMs: _optionalInt(arguments, 'drainTimeoutMs') ?? 30000,
        ),
      )).toJson();
    },
  ),
  ..._executionTools(client),
  ..._suiteTools(client),
  ..._runTools(client),
];

List<CockpitMcpTool> _executionTools(
  CockpitMcpClientProvider client,
) => <CockpitMcpTool>[
  _CockpitApiTool(
    client: client,
    name: 'target_discover',
    description: 'Discover locally available launch targets.',
    inputSchema: _schema(
      properties: <String, Object?>{
        'timeoutMs': _integer(minimum: 1, maximum: 300000),
      },
    ),
    action: (api, arguments) async {
      _only(arguments, const <String>{'timeoutMs'});
      return (await api.executeOperation(
        CockpitOperationInvocation(
          kind: 'target.discover',
          input: <String, Object?>{
            if (_optionalInt(arguments, 'timeoutMs') != null)
              'timeoutMs': _requiredInt(arguments, 'timeoutMs'),
          },
        ),
      )).toJson();
    },
  ),
  _CockpitApiTool(
    client: client,
    name: 'target_list',
    description: 'List registered targets for an explicit workspace.',
    inputSchema: _schema(
      properties: <String, Object?>{'workspaceId': _string()},
      required: const <String>['workspaceId'],
    ),
    action: (api, arguments) async {
      _only(arguments, const <String>{'workspaceId'});
      return <String, Object?>{
        'items': (await api.targets(
          _requiredString(arguments, 'workspaceId'),
        )).map((target) => target.toJson()).toList(),
      };
    },
  ),
  _CockpitApiTool(
    client: client,
    name: 'target_get',
    description: 'Read one registered workspace automation target.',
    inputSchema: _schema(
      properties: <String, Object?>{
        'workspaceId': _string(),
        'targetId': _string(),
      },
      required: const <String>['workspaceId', 'targetId'],
    ),
    action: (api, arguments) async {
      _only(arguments, const <String>{'workspaceId', 'targetId'});
      return (await api.target(
        _requiredString(arguments, 'workspaceId'),
        _requiredString(arguments, 'targetId'),
      )).toJson();
    },
  ),
  _CockpitApiTool(
    client: client,
    name: 'target_inspect',
    description: 'Inspect live capabilities and state for a target.',
    inputSchema: _schema(
      properties: <String, Object?>{
        'workspaceId': _string(),
        'targetId': _string(),
        'profile': const <String, Object?>{
          'type': 'string',
          'enum': <String>['minimal', 'standard', 'inspect', 'evidence'],
        },
      },
      required: const <String>['workspaceId', 'targetId'],
    ),
    action: (api, arguments) async {
      _only(arguments, const <String>{'workspaceId', 'targetId', 'profile'});
      return (await api.executeOperation(
        CockpitOperationInvocation(
          kind: 'target.inspect',
          workspaceId: _requiredString(arguments, 'workspaceId'),
          input: <String, Object?>{
            'targetId': _requiredString(arguments, 'targetId'),
            if (_optionalString(arguments, 'profile') != null)
              'profile': _requiredString(arguments, 'profile'),
          },
        ),
      )).toJson();
    },
  ),
  _CockpitApiTool(
    client: client,
    name: 'target_register',
    description: 'Register a workspace-owned native or host automation target.',
    inputSchema: _schema(
      properties: <String, Object?>{
        'workspaceId': _string(),
        'platform': _string(),
        'deviceId': _string(),
        'targetKind': _enumString(const <String>[
          'flutterApp',
          'nativeApp',
          'desktopApp',
          'browserPage',
          'systemSurface',
          'device',
          'hostWorkspace',
        ]),
        'environment': _string(),
        'mode': _string(),
        'entrypointDocumentId': _string(),
        'flavor': _string(),
        'appId': _nonBlankString(),
        'wdaUrl': _string(),
        'idempotencyKey': _string(),
      },
      required: const <String>[
        'workspaceId',
        'platform',
        'deviceId',
        'targetKind',
        'idempotencyKey',
      ],
      extra: <String, Object?>{
        'allOf': <Object?>[
          <String, Object?>{
            'if': <String, Object?>{
              'properties': <String, Object?>{
                'targetKind': <String, Object?>{
                  'enum': <String>['nativeApp', 'desktopApp', 'browserPage'],
                },
              },
            },
            'then': <String, Object?>{
              'required': <String>['appId'],
            },
          },
        ],
      },
    ),
    action: (api, arguments) async {
      _only(arguments, const <String>{
        'workspaceId',
        'platform',
        'deviceId',
        'targetKind',
        'environment',
        'mode',
        'entrypointDocumentId',
        'flavor',
        'appId',
        'wdaUrl',
        'idempotencyKey',
      });
      final targetKind = _requiredString(arguments, 'targetKind');
      final appId = _optionalString(arguments, 'appId');
      if (const <String>{
            'nativeApp',
            'desktopApp',
            'browserPage',
          }.contains(targetKind) &&
          appId == null) {
        throw CockpitMcpError.invalidArguments('$targetKind requires appId.');
      }
      return (await api.executeOperation(
        CockpitOperationInvocation(
          kind: 'target.register',
          workspaceId: _requiredString(arguments, 'workspaceId'),
          idempotencyKey: CockpitIdempotencyKey(
            _requiredString(arguments, 'idempotencyKey'),
          ),
          input: <String, Object?>{
            'platform': _requiredString(arguments, 'platform'),
            'deviceId': _requiredString(arguments, 'deviceId'),
            'targetKind': targetKind,
            'environment':
                _optionalString(arguments, 'environment') ?? 'unknown',
            'mode': _optionalString(arguments, 'mode') ?? 'automation',
            if (_optionalString(arguments, 'entrypointDocumentId') != null)
              'entrypointDocumentId': _requiredString(
                arguments,
                'entrypointDocumentId',
              ),
            if (_optionalString(arguments, 'flavor') != null)
              'flavor': _requiredString(arguments, 'flavor'),
            'appId': ?appId,
            if (_optionalString(arguments, 'wdaUrl') != null)
              'wdaUrl': _requiredString(arguments, 'wdaUrl'),
          },
        ),
      )).toJson();
    },
  ),
  _CockpitApiTool(
    client: client,
    name: 'target_launch',
    description: 'Launch or activate one registered automation target.',
    inputSchema: _schema(
      properties: <String, Object?>{
        'workspaceId': _string(),
        'targetId': _string(),
        'mode': const <String, Object?>{
          'type': 'string',
          'enum': <String>['development', 'automation'],
        },
        'launchTimeoutMs': _integer(minimum: 1, maximum: 600000),
        'idempotencyKey': _string(),
      },
      required: const <String>['workspaceId', 'targetId', 'idempotencyKey'],
    ),
    action: (api, arguments) async {
      _only(arguments, const <String>{
        'workspaceId',
        'targetId',
        'mode',
        'launchTimeoutMs',
        'idempotencyKey',
      });
      return (await api.executeOperation(
        CockpitOperationInvocation(
          kind: 'target.launch',
          workspaceId: _requiredString(arguments, 'workspaceId'),
          idempotencyKey: CockpitIdempotencyKey(
            _requiredString(arguments, 'idempotencyKey'),
          ),
          input: <String, Object?>{
            'targetId': _requiredString(arguments, 'targetId'),
            if (_optionalString(arguments, 'mode') != null)
              'mode': _requiredString(arguments, 'mode'),
            if (_optionalInt(arguments, 'launchTimeoutMs') != null)
              'launchTimeoutMs': _requiredInt(arguments, 'launchTimeoutMs'),
          },
        ),
      )).toJson();
    },
  ),
  _CockpitApiTool(
    client: client,
    name: 'operation_execute',
    description: 'Execute an advertised typed Supervisor operation.',
    inputSchema: _schema(
      properties: <String, Object?>{
        'kind': _string(),
        'input': _object(),
        'rootId': _string(),
        'workspaceId': _string(),
        'idempotencyKey': _string(),
        'deadline': _string(),
      },
      required: const <String>['kind', 'input'],
    ),
    action: (api, arguments) async {
      _only(arguments, const <String>{
        'kind',
        'input',
        'rootId',
        'workspaceId',
        'idempotencyKey',
        'deadline',
      });
      return (await api.executeOperation(
        CockpitOperationInvocation(
          kind: _requiredString(arguments, 'kind'),
          input: _requiredObject(arguments, 'input'),
          rootId: _optionalString(arguments, 'rootId'),
          workspaceId: _optionalString(arguments, 'workspaceId'),
          idempotencyKey: _optionalString(arguments, 'idempotencyKey') == null
              ? null
              : CockpitIdempotencyKey(
                  _requiredString(arguments, 'idempotencyKey'),
                ),
          deadline: _optionalString(arguments, 'deadline') == null
              ? null
              : DateTime.parse(_requiredString(arguments, 'deadline')).toUtc(),
        ),
      )).toJson();
    },
  ),
  _CockpitApiTool(
    client: client,
    name: 'case_validate',
    description: 'Validate a bounded case document in a workspace.',
    inputSchema: _schema(
      properties: <String, Object?>{
        'workspaceId': _string(),
        'format': <String, Object?>{
          'type': 'string',
          'enum': const <String>['json', 'yaml'],
        },
        'sourceText': _string(),
        'relativePath': _string(),
      },
      required: const <String>['workspaceId', 'format', 'sourceText'],
    ),
    action: (api, arguments) async {
      _only(arguments, const <String>{
        'workspaceId',
        'format',
        'sourceText',
        'relativePath',
      });
      return (await api.validateCaseDocument(
        _requiredString(arguments, 'workspaceId'),
        CockpitDocumentValidationRequest(
          format: CockpitDocumentFormat.values.byName(
            _requiredString(arguments, 'format'),
          ),
          sourceText: _requiredString(arguments, 'sourceText'),
          relativePath: _optionalString(arguments, 'relativePath'),
        ),
      )).toJson();
    },
  ),
  _CockpitApiTool(
    client: client,
    name: 'case_run',
    description: 'Run an explicitly identified canonical indexed case.',
    inputSchema: _schema(
      properties: <String, Object?>{
        'workspaceId': _string(),
        'documentId': _string(),
        'documentSha256': _sha256Schema(),
        'caseId': _string(),
        'idempotencyKey': _string(),
        'inputs': _object(),
        'targetId': _string(),
      },
      required: const <String>[
        'workspaceId',
        'documentId',
        'documentSha256',
        'caseId',
        'idempotencyKey',
      ],
    ),
    action: (api, arguments) async {
      _only(arguments, const <String>{
        'workspaceId',
        'documentId',
        'documentSha256',
        'caseId',
        'idempotencyKey',
        'inputs',
        'targetId',
      });
      return (await api.submitRun(
        CockpitRunSubmission(
          workspaceId: _requiredString(arguments, 'workspaceId'),
          source: CockpitIndexedCaseSource(
            reference: CockpitIndexedCaseReference(
              documentId: _requiredString(arguments, 'documentId'),
              caseId: _requiredString(arguments, 'caseId'),
              documentSha256: _requiredString(arguments, 'documentSha256'),
            ),
          ),
          idempotencyKey: CockpitIdempotencyKey(
            _requiredString(arguments, 'idempotencyKey'),
          ),
          inputs:
              _optionalObject(arguments, 'inputs') ?? const <String, Object?>{},
          targetId: _optionalString(arguments, 'targetId'),
        ),
      )).toJson();
    },
  ),
];

List<CockpitMcpTool> _runTools(CockpitMcpClientProvider client) =>
    <CockpitMcpTool>[
      _CockpitApiTool(
        client: client,
        name: 'run_get',
        description: 'Read an explicitly identified run.',
        inputSchema: _schema(
          properties: <String, Object?>{'runId': _string()},
          required: const <String>['runId'],
        ),
        action: (api, arguments) async {
          _only(arguments, const <String>{'runId'});
          return (await api.run(_requiredString(arguments, 'runId'))).toJson();
        },
      ),
      _CockpitApiTool(
        client: client,
        name: 'run_cancel',
        description: 'Cancel an explicitly identified run.',
        inputSchema: _schema(
          properties: <String, Object?>{
            'runId': _string(),
            'idempotencyKey': _string(),
            'reason': _string(),
          },
          required: const <String>['runId', 'idempotencyKey'],
        ),
        action: (api, arguments) async {
          _only(arguments, const <String>{'runId', 'idempotencyKey', 'reason'});
          return (await api.cancelRun(
            _requiredString(arguments, 'runId'),
            CockpitRunCancellationRequest(
              idempotencyKey: CockpitIdempotencyKey(
                _requiredString(arguments, 'idempotencyKey'),
              ),
              reason: _optionalString(arguments, 'reason'),
            ),
          )).toJson();
        },
      ),
      _CockpitApiTool(
        client: client,
        name: 'run_events',
        description: 'Read bounded run events through the Supervisor SSE API.',
        inputSchema: _schema(
          properties: <String, Object?>{
            'runId': _string(),
            'afterSequence': _integer(minimum: 0),
            'lastEventId': _string(),
            'maxEvents': _integer(minimum: 1, maximum: 1000),
          },
          required: const <String>['runId'],
        ),
        action: (api, arguments) async {
          _only(arguments, const <String>{
            'runId',
            'afterSequence',
            'lastEventId',
            'maxEvents',
          });
          final items = <Map<String, Object?>>[];
          final maximum = _optionalInt(arguments, 'maxEvents') ?? 1000;
          if (maximum < 1 || maximum > 1000) {
            throw CockpitMcpError.invalidArguments(
              'maxEvents must be between 1 and 1000.',
            );
          }
          final afterSequence = _optionalInt(arguments, 'afterSequence') ?? 0;
          if (afterSequence < 0) {
            throw CockpitMcpError.invalidArguments(
              'afterSequence cannot be negative.',
            );
          }
          await for (final item in api.events(
            _requiredString(arguments, 'runId'),
            afterSequence: afterSequence,
            lastEventId: _optionalString(arguments, 'lastEventId'),
          )) {
            items.add(_streamItem(item));
            if (items.length >= maximum) break;
          }
          return <String, Object?>{'items': items};
        },
      ),
      _CockpitApiTool(
        client: client,
        name: 'artifact_list',
        description: 'List immutable artifact metadata for an explicit run.',
        inputSchema: _schema(
          properties: <String, Object?>{'runId': _string()},
          required: const <String>['runId'],
        ),
        action: (api, arguments) async {
          _only(arguments, const <String>{'runId'});
          return <String, Object?>{
            'items': (await api.artifacts(
              _requiredString(arguments, 'runId'),
            )).map((artifact) => artifact.toJson()).toList(),
          };
        },
      ),
      _CockpitApiTool(
        client: client,
        name: 'artifact_read',
        description: 'Download a verified artifact to an explicit local file.',
        inputSchema: _schema(
          properties: <String, Object?>{
            'runId': _string(),
            'artifactId': _string(),
            'outputPath': _string(),
          },
          required: const <String>['runId', 'artifactId', 'outputPath'],
        ),
        action: (api, arguments) async {
          _only(arguments, const <String>{'runId', 'artifactId', 'outputPath'});
          final runId = _requiredString(arguments, 'runId');
          final artifactId = _requiredString(arguments, 'artifactId');
          final outputPath = _requiredString(arguments, 'outputPath');
          if (!p.isAbsolute(outputPath)) {
            throw const FormatException('outputPath must be absolute.');
          }
          final matches = (await api.artifacts(runId))
              .where((artifact) => artifact.artifactId == artifactId)
              .toList(growable: false);
          if (matches.length != 1) {
            throw CockpitSupervisorClientException(
              code: 'artifactNotFound',
              message: 'Artifact $artifactId was not found for run $runId.',
            );
          }
          final receipt = await api.downloadArtifactToFile(
            artifact: matches.single,
            destination: File(p.normalize(outputPath)),
          );
          return <String, Object?>{
            'path': receipt.file.path,
            'mediaType': receipt.mediaType,
            'sizeBytes': receipt.sizeBytes,
            'sha256': receipt.sha256,
          };
        },
      ),
    ];

List<CockpitMcpTool> _suiteTools(
  CockpitMcpClientProvider client,
) => <CockpitMcpTool>[
  _CockpitApiTool(
    client: client,
    name: 'suite_validate',
    description: 'Validate a bounded suite document in a workspace.',
    inputSchema: _schema(
      properties: <String, Object?>{
        'workspaceId': _string(),
        'format': <String, Object?>{
          'type': 'string',
          'enum': const <String>['json', 'yaml'],
        },
        'sourceText': _string(),
        'relativePath': _string(),
      },
      required: const <String>['workspaceId', 'format', 'sourceText'],
    ),
    action: (api, arguments) async {
      _only(arguments, const <String>{
        'workspaceId',
        'format',
        'sourceText',
        'relativePath',
      });
      return (await api.validateCaseDocument(
        _requiredString(arguments, 'workspaceId'),
        CockpitDocumentValidationRequest(
          format: CockpitDocumentFormat.values.byName(
            _requiredString(arguments, 'format'),
          ),
          sourceText: _requiredString(arguments, 'sourceText'),
          relativePath: _optionalString(arguments, 'relativePath'),
        ),
      )).toJson();
    },
  ),
  _CockpitApiTool(
    client: client,
    name: 'suite_run',
    description: 'Run an explicitly identified canonical indexed suite.',
    inputSchema: _schema(
      properties: <String, Object?>{
        'workspaceId': _string(),
        'documentId': _string(),
        'documentSha256': _sha256Schema(),
        'suiteId': _string(),
        'idempotencyKey': _string(),
        'inputs': _object(),
        'targetId': _string(),
      },
      required: const <String>[
        'workspaceId',
        'documentId',
        'documentSha256',
        'suiteId',
        'idempotencyKey',
      ],
    ),
    action: (api, arguments) async {
      _only(arguments, const <String>{
        'workspaceId',
        'documentId',
        'documentSha256',
        'suiteId',
        'idempotencyKey',
        'inputs',
        'targetId',
      });
      return (await api.submitRun(
        CockpitRunSubmission(
          workspaceId: _requiredString(arguments, 'workspaceId'),
          source: CockpitIndexedSuiteSource(
            reference: CockpitIndexedSuiteReference(
              documentId: _requiredString(arguments, 'documentId'),
              suiteId: _requiredString(arguments, 'suiteId'),
              documentSha256: _requiredString(arguments, 'documentSha256'),
            ),
          ),
          idempotencyKey: CockpitIdempotencyKey(
            _requiredString(arguments, 'idempotencyKey'),
          ),
          inputs:
              _optionalObject(arguments, 'inputs') ?? const <String, Object?>{},
          targetId: _optionalString(arguments, 'targetId'),
        ),
      )).toJson();
    },
  ),
  _CockpitApiTool(
    client: client,
    name: 'suite_report',
    description: 'Read the finalized canonical suite report for a run.',
    inputSchema: _schema(
      properties: <String, Object?>{'runId': _string()},
      required: const <String>['runId'],
    ),
    action: (api, arguments) async {
      _only(arguments, const <String>{'runId'});
      return (await api.report(_requiredString(arguments, 'runId'))).toJson();
    },
  ),
];

typedef _ToolAction =
    Future<Map<String, Object?>> Function(
      CockpitSupervisorApiClient api,
      Map<String, Object?> arguments,
    );

final class _CockpitApiTool extends CockpitMcpTool {
  _CockpitApiTool({
    required this.client,
    required this.name,
    required this.description,
    required this.inputSchema,
    required _ToolAction action,
  }) : _action = action;

  final CockpitMcpClientProvider client;

  @override
  final String name;

  @override
  final String description;

  @override
  final Map<String, Object?> inputSchema;

  final _ToolAction _action;

  @override
  Future<Map<String, Object?>> call(Map<String, Object?> arguments) async {
    try {
      final value = await _action(await client(), arguments);
      final text = jsonEncode(value);
      if (utf8.encode(text).length > cockpitSupervisorMaximumResponseBytes) {
        throw const CockpitMcpError(
          code: -32000,
          message: 'MCP tool output exceeds 1 MiB.',
        );
      }
      return <String, Object?>{
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': text},
        ],
        'structuredContent': value,
      };
    } on CockpitMcpError {
      rethrow;
    } on CockpitSupervisorClientException catch (error) {
      throw CockpitMcpError(
        code: -32000,
        message: error.message,
        data: <String, Object?>{
          'apiCode': error.code,
          if (error.apiError != null) 'apiError': error.apiError!.toJson(),
        },
      );
    } on FormatException catch (error) {
      throw CockpitMcpError.invalidArguments(error.message);
    }
  }
}

Map<String, Object?> _schema({
  required Map<String, Object?> properties,
  List<String> required = const <String>[],
  Map<String, Object?> extra = const <String, Object?>{},
}) => <String, Object?>{
  r'$schema': 'https://json-schema.org/draft/2020-12/schema',
  'type': 'object',
  'properties': properties,
  'required': required,
  'additionalProperties': false,
  ...extra,
};

Map<String, Object?> _string() => const <String, Object?>{
  'type': 'string',
  'minLength': 1,
  'maxLength': 1048576,
};

Map<String, Object?> _nonBlankString() => <String, Object?>{
  ..._string(),
  'pattern': r'\S',
};

Map<String, Object?> _enumString(List<String> values) => <String, Object?>{
  ..._string(),
  'enum': values,
};

Map<String, Object?> _sha256Schema() => const <String, Object?>{
  'type': 'string',
  'pattern': r'^[0-9a-f]{64}$',
};

Map<String, Object?> _boolean() => const <String, Object?>{'type': 'boolean'};

Map<String, Object?> _integer({int? minimum, int? maximum}) =>
    <String, Object?>{
      'type': 'integer',
      'minimum': ?minimum,
      'maximum': ?maximum,
    };

Map<String, Object?> _object() => const <String, Object?>{
  'type': 'object',
  'additionalProperties': true,
};

void _only(Map<String, Object?> arguments, Set<String> allowed) {
  final unknown = arguments.keys.toSet().difference(allowed);
  if (unknown.isNotEmpty) {
    throw CockpitMcpError.invalidArguments(
      'Unknown tool arguments.',
      details: <String, Object?>{'arguments': unknown.toList()..sort()},
    );
  }
}

String _requiredString(Map<String, Object?> arguments, String name) {
  final value = arguments[name];
  if (value is! String || value.isEmpty) {
    throw CockpitMcpError.invalidArguments('$name must be a non-empty string.');
  }
  return value;
}

String? _optionalString(Map<String, Object?> arguments, String name) {
  if (!arguments.containsKey(name)) return null;
  return _requiredString(arguments, name);
}

int _requiredInt(Map<String, Object?> arguments, String name) {
  final value = arguments[name];
  if (value is! int) {
    throw CockpitMcpError.invalidArguments('$name must be an integer.');
  }
  return value;
}

int? _optionalInt(Map<String, Object?> arguments, String name) {
  if (!arguments.containsKey(name)) return null;
  return _requiredInt(arguments, name);
}

bool? _optionalBool(Map<String, Object?> arguments, String name) {
  if (!arguments.containsKey(name)) return null;
  final value = arguments[name];
  if (value is! bool) {
    throw CockpitMcpError.invalidArguments('$name must be a boolean.');
  }
  return value;
}

Map<String, Object?> _requiredObject(
  Map<String, Object?> arguments,
  String name,
) {
  final value = arguments[name];
  if (value is! Map<Object?, Object?> ||
      value.keys.any((key) => key is! String)) {
    throw CockpitMcpError.invalidArguments('$name must be an object.');
  }
  return Map<String, Object?>.from(value);
}

Map<String, Object?>? _optionalObject(
  Map<String, Object?> arguments,
  String name,
) {
  if (!arguments.containsKey(name)) return null;
  return _requiredObject(arguments, name);
}

Map<String, Object?> _streamItem(CockpitRunStreamItem item) => switch (item) {
  CockpitRunStreamEvent() => <String, Object?>{
    'type': 'event',
    'event': item.event.toJson(),
  },
  CockpitRunStreamGap() => <String, Object?>{
    'type': 'gap',
    'boundary': item.boundary.toJson(),
  },
  CockpitRunStreamTerminal() => <String, Object?>{
    'type': 'terminal',
    'afterSequence': item.afterSequence,
  },
  CockpitRunStreamDisconnected() => <String, Object?>{
    'type': 'disconnected',
    'afterSequence': item.afterSequence,
  },
};
