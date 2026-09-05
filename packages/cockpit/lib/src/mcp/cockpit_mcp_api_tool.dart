import 'dart:convert';

import '../supervisor/cockpit_supervisor_api_client.dart';
import 'cockpit_mcp_api_resources.dart';
import 'cockpit_mcp_error.dart';
import 'cockpit_mcp_tool.dart';

typedef CockpitMcpApiToolAction =
    Future<Map<String, Object?>> Function(
      CockpitSupervisorApiClient api,
      Map<String, Object?> arguments,
    );

final class CockpitMcpApiTool extends CockpitMcpTool {
  CockpitMcpApiTool({
    required this.client,
    required this.name,
    required this.description,
    required this.inputSchema,
    required CockpitMcpApiToolAction action,
    this.toolAnnotations = CockpitMcpToolAnnotations.defaults,
    this.featureCategories = const <CockpitMcpFeatureCategory>[
      CockpitMcpFeatureCategory.all,
    ],
    this.isEnabledByDefault = true,
  }) : _action = action;

  final CockpitMcpClientProvider client;

  @override
  final String name;

  @override
  final String description;

  @override
  final Map<String, Object?> inputSchema;

  final CockpitMcpApiToolAction _action;
  final CockpitMcpToolAnnotations toolAnnotations;
  final List<CockpitMcpFeatureCategory> featureCategories;
  final bool isEnabledByDefault;

  @override
  CockpitMcpToolAnnotations get annotations => toolAnnotations;

  @override
  List<CockpitMcpFeatureCategory> get categories => featureCategories;

  @override
  bool get enabledByDefault => isEnabledByDefault;

  @override
  Future<Map<String, Object?>> call(Map<String, Object?> arguments) async {
    try {
      final value = await _action(await client(), arguments);
      if (utf8.encode(jsonEncode(value)).length >
          cockpitSupervisorMaximumResponseBytes) {
        throw const CockpitMcpError(
          code: -32000,
          message: 'MCP tool output exceeds 1 MiB.',
        );
      }
      return <String, Object?>{
        'content': <Object?>[
          <String, Object?>{
            'type': 'text',
            'text': cockpitMcpCompactToolSummary(name, value),
          },
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

String cockpitMcpCompactToolSummary(
  String toolName,
  Map<String, Object?> value,
) {
  final facts = <String>[];
  void add(String key, Object? candidate) {
    if (candidate is String || candidate is num || candidate is bool) {
      facts.add('$key=$candidate');
    }
  }

  for (final key in const <String>[
    'outcome',
    'status',
    'runId',
    'operationId',
    'workspaceId',
    'targetId',
    'sessionId',
    'path',
    'sizeBytes',
    'truncated',
  ]) {
    add(key, value[key]);
    if (facts.length >= 5) break;
  }

  final output = value['output'];
  if (output is Map<Object?, Object?>) {
    for (final key in const <String>[
      'exitCode',
      'diagnosticCount',
      'errorCount',
      'testCount',
      'matchedFileCount',
      'totalMatches',
      'truncated',
    ]) {
      add(key, output[key]);
      if (facts.length >= 7) break;
    }
  }

  final failure = value['failure'];
  if (failure is Map<Object?, Object?>) {
    final primary = failure['primary'];
    if (primary is Map<Object?, Object?>) {
      add('code', primary['code']);
      add('message', primary['message']);
    }
  }

  return facts.isEmpty
      ? '$toolName completed.'
      : '$toolName: ${facts.join(' ')}';
}
