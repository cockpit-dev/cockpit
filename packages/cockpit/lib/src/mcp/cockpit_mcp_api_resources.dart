import 'dart:convert';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../supervisor/cockpit_supervisor_api_client.dart';
import 'core/cockpit_mcp_resource.dart';
import 'core/cockpit_mcp_resource_definition.dart';

typedef CockpitMcpClientProvider =
    Future<CockpitSupervisorApiClient> Function();

List<CockpitMcpResource> cockpitMcpApiResources(
  CockpitMcpClientProvider client,
) => <CockpitMcpResource>[
  _CockpitApiResource.fixed(
    client: client,
    name: 'server',
    uri: 'cockpit://server',
    description: 'Cockpit Supervisor server identity and API version.',
    read: (api, _) async => (await api.server()).toJson(),
  ),
  _CockpitApiResource.fixed(
    client: client,
    name: 'capabilities',
    uri: 'cockpit://capabilities',
    description: 'Negotiated Supervisor capabilities and public surfaces.',
    read: (api, _) async => (await api.capabilities()).toJson(),
  ),
  _CockpitApiResource.fixed(
    client: client,
    name: 'roots',
    uri: 'cockpit://roots',
    description: 'Registered Cockpit project roots.',
    read: (api, _) async => <String, Object?>{
      'items': (await api.roots()).map((item) => item.toJson()).toList(),
    },
  ),
  _CockpitApiResource.fixed(
    client: client,
    name: 'workspaces',
    uri: 'cockpit://workspaces',
    description: 'Registered Cockpit workspace checkouts.',
    read: (api, _) async => <String, Object?>{
      'items': (await api.workspaces()).map((item) => item.toJson()).toList(),
    },
  ),
  _CockpitApiResource.fixed(
    client: client,
    name: 'operations',
    uri: 'cockpit://operations',
    description: 'Advertised Supervisor and root operations.',
    read: (api, _) async => <String, Object?>{
      'items': (await api.operations()).map((item) => item.toJson()).toList(),
    },
  ),
  _CockpitApiResource.fixed(
    client: client,
    name: 'operation_schema',
    uri: 'cockpit://operations/schema',
    description:
        'Live request and response contracts for every advertised operation.',
    read: (api, _) => api.operationSchema(),
  ),
  _CockpitApiResource.template(
    client: client,
    name: 'workspace_operations',
    uriTemplate: 'cockpit://workspaces/{workspaceId}/operations',
    description: 'Advertised operations for an explicit workspace.',
    read: (api, uri) async => <String, Object?>{
      'items': (await api.operations(
        workspaceId: _identifier(uri, 0, 'workspaceId'),
      )).map((item) => item.toJson()).toList(),
    },
  ),
  _CockpitApiResource.template(
    client: client,
    name: 'workspace_targets',
    uriTemplate: 'cockpit://workspaces/{workspaceId}/targets',
    description: 'Registered automation targets for an explicit workspace.',
    read: (api, uri) async => <String, Object?>{
      'items': (await api.targets(
        _identifier(uri, 0, 'workspaceId'),
      )).map((item) => item.toJson()).toList(),
    },
  ),
  _CockpitApiResource.template(
    client: client,
    name: 'workspace_target',
    uriTemplate: 'cockpit://workspaces/{workspaceId}/targets/{targetId}',
    description: 'One registered workspace automation target.',
    read: (api, uri) async => (await api.target(
      _identifier(uri, 0, 'workspaceId'),
      _identifier(uri, 2, 'targetId'),
    )).toJson(),
  ),
  _CockpitApiResource.template(
    client: client,
    name: 'workspace_suites',
    uriTemplate: 'cockpit://workspaces/{workspaceId}/suites',
    description: 'Indexed suites for an explicit workspace.',
    read: (api, uri) async => <String, Object?>{
      'items': (await api.documents(_identifier(uri, 0, 'workspaceId')))
          .where(
            (document) => document.kind == CockpitIndexedDocumentKind.suite,
          )
          .map((document) => document.toJson())
          .toList(growable: false),
    },
  ),
  _CockpitApiResource.template(
    client: client,
    name: 'workspace_cases',
    uriTemplate: 'cockpit://workspaces/{workspaceId}/cases',
    description: 'Indexed cases for an explicit workspace.',
    read: (api, uri) async => <String, Object?>{
      'items': (await api.cases(
        _identifier(uri, 0, 'workspaceId'),
      )).map((item) => item.toJson()).toList(),
    },
  ),
  _CockpitApiResource.template(
    client: client,
    name: 'workspace_runs',
    uriTemplate: 'cockpit://workspaces/{workspaceId}/runs',
    description: 'Recent runs for an explicit workspace.',
    read: (api, uri) async {
      final page = await api.runs(_identifier(uri, 0, 'workspaceId'));
      return page.toJson((run) => run.toJson());
    },
  ),
  _CockpitApiResource.template(
    client: client,
    name: 'run_artifacts',
    uriTemplate: 'cockpit://runs/{runId}/artifacts',
    description: 'Immutable artifact metadata for an explicit run.',
    read: (api, uri) async => <String, Object?>{
      'items': (await api.artifacts(
        _identifier(uri, 0, 'runId'),
      )).map((item) => item.toJson()).toList(),
    },
  ),
  _CockpitApiResource.template(
    client: client,
    name: 'run_report',
    uriTemplate: 'cockpit://runs/{runId}/report',
    description: 'Finalized canonical suite report for a run.',
    read: (api, uri) async =>
        (await api.report(_identifier(uri, 0, 'runId'))).toJson(),
  ),
  _CockpitApiResource.template(
    client: client,
    name: 'run',
    uriTemplate: 'cockpit://runs/{runId}',
    description: 'A run resource addressed by explicit run id.',
    read: (api, uri) async =>
        (await api.run(_identifier(uri, 0, 'runId'))).toJson(),
  ),
];

typedef _ResourceRead =
    Future<Object?> Function(CockpitSupervisorApiClient api, Uri uri);

final class _CockpitApiResource extends CockpitMcpResource {
  const _CockpitApiResource._({
    required this.client,
    required this.definition,
    required _ResourceRead read,
  }) : _read = read;

  factory _CockpitApiResource.fixed({
    required CockpitMcpClientProvider client,
    required String name,
    required String uri,
    required String description,
    required _ResourceRead read,
  }) => _CockpitApiResource._(
    client: client,
    definition: CockpitMcpResourceDefinition.fixed(
      name: name,
      uri: uri,
      description: description,
      mimeType: 'application/json',
    ),
    read: read,
  );

  factory _CockpitApiResource.template({
    required CockpitMcpClientProvider client,
    required String name,
    required String uriTemplate,
    required String description,
    required _ResourceRead read,
  }) => _CockpitApiResource._(
    client: client,
    definition: CockpitMcpResourceDefinition.template(
      name: name,
      uriTemplate: uriTemplate,
      description: description,
      mimeType: 'application/json',
    ),
    read: read,
  );

  final CockpitMcpClientProvider client;

  @override
  final CockpitMcpResourceDefinition definition;
  final _ResourceRead _read;

  @override
  Future<CockpitMcpResourceResult?> read(
    CockpitMcpResourceRequest request,
  ) async {
    final uri = request.parsedUri;
    final fixed = definition.uri;
    if (fixed != null && request.uri != fixed) return null;
    if (fixed == null && !_matchesTemplate(uri, definition.name)) return null;
    final value = await _read(await client(), uri);
    final text = jsonEncode(value);
    if (utf8.encode(text).length > cockpitSupervisorMaximumResponseBytes) {
      throw const CockpitSupervisorClientException(
        code: 'outputTooLarge',
        message: 'MCP resource output exceeds 1 MiB.',
      );
    }
    return CockpitMcpResourceResult(
      contents: <CockpitMcpResourceContents>[
        CockpitMcpTextResourceContents(
          uri: request.uri,
          text: text,
          mimeType: 'application/json',
        ),
      ],
    );
  }
}

bool _matchesTemplate(Uri uri, String name) {
  if (uri.scheme != 'cockpit') return false;
  return switch (name) {
    'workspace_operations' =>
      uri.host == 'workspaces' &&
          uri.pathSegments.length == 2 &&
          uri.pathSegments[1] == 'operations',
    'workspace_targets' =>
      uri.host == 'workspaces' &&
          uri.pathSegments.length == 2 &&
          uri.pathSegments[1] == 'targets',
    'workspace_target' =>
      uri.host == 'workspaces' &&
          uri.pathSegments.length == 3 &&
          uri.pathSegments[1] == 'targets',
    'workspace_cases' =>
      uri.host == 'workspaces' &&
          uri.pathSegments.length == 2 &&
          uri.pathSegments[1] == 'cases',
    'workspace_runs' =>
      uri.host == 'workspaces' &&
          uri.pathSegments.length == 2 &&
          uri.pathSegments[1] == 'runs',
    'workspace_suites' =>
      uri.host == 'workspaces' &&
          uri.pathSegments.length == 2 &&
          uri.pathSegments[1] == 'suites',
    'run' => uri.host == 'runs' && uri.pathSegments.length == 1,
    'run_report' =>
      uri.host == 'runs' &&
          uri.pathSegments.length == 2 &&
          uri.pathSegments[1] == 'report',
    'run_artifacts' =>
      uri.host == 'runs' &&
          uri.pathSegments.length == 2 &&
          uri.pathSegments[1] == 'artifacts',
    _ => false,
  };
}

String _identifier(Uri uri, int index, String name) {
  if (uri.hasQuery || uri.hasFragment || index >= uri.pathSegments.length) {
    throw FormatException('Invalid $name resource URI.');
  }
  final value = uri.pathSegments[index];
  if (!RegExp(r'^[A-Za-z][A-Za-z0-9._-]{0,127}$').hasMatch(value)) {
    throw FormatException('Invalid $name resource URI.');
  }
  return value;
}
