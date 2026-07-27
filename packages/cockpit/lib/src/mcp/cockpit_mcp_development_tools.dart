import 'dart:async';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

import '../supervisor/cockpit_supervisor_api_client.dart';
import 'cockpit_mcp_api_resources.dart';
import 'cockpit_mcp_api_tool.dart';
import 'cockpit_mcp_tool.dart';

List<CockpitMcpTool> cockpitMcpDevelopmentTools(
  CockpitMcpClientProvider client,
) => <CockpitMcpTool>[
  ..._qualityTools(client),
  ..._dependencyTools(client),
  ..._projectTools(client),
];

List<CockpitMcpTool> _qualityTools(
  CockpitMcpClientProvider client,
) => <CockpitMcpTool>[
  _operationTool(
    client: client,
    name: 'analyze_files',
    description:
        'Analyze selected Dart files or directories and return bounded diagnostics.',
    kind: 'analyze.files',
    scope: _OperationScope.workspace,
    mutating: false,
    properties: <String, Object?>{
      'paths': _stringList(),
      'maxDiagnostics': _integer(minimum: 1, maximum: 1000),
      'maxOutputChars': _integer(minimum: 100, maximum: 20000),
    },
    required: const <String>['paths'],
    inputKeys: const <String>{'paths', 'maxDiagnostics', 'maxOutputChars'},
    operationInput: (api, arguments) async => <String, Object?>{
      'documentIds': await _documentIds(
        api,
        _requiredString(arguments, 'workspaceId'),
        _requiredStrings(arguments, 'paths'),
      ),
      if (_optionalInt(arguments, 'maxDiagnostics') != null)
        'maxDiagnostics': _optionalInt(arguments, 'maxDiagnostics'),
      if (_optionalInt(arguments, 'maxOutputChars') != null)
        'maxOutputChars': _optionalInt(arguments, 'maxOutputChars'),
    },
    categories: const <CockpitMcpFeatureCategory>[
      CockpitMcpFeatureCategory.dart,
      CockpitMcpFeatureCategory.codeIntelligence,
      CockpitMcpFeatureCategory.workspaceQuality,
    ],
    defaultTimeoutMs: 300000,
    maximumTimeoutMs: 1800000,
    longRunning: true,
  ),
  _operationTool(
    client: client,
    name: 'analyze_workspace',
    description: 'Analyze the complete Dart or Flutter workspace.',
    kind: 'analyze.workspace',
    scope: _OperationScope.workspace,
    mutating: false,
    properties: const <String, Object?>{},
    required: const <String>[],
    inputKeys: const <String>{},
    operationInput: (_, _) => const <String, Object?>{},
    categories: const <CockpitMcpFeatureCategory>[
      CockpitMcpFeatureCategory.dart,
      CockpitMcpFeatureCategory.workspaceQuality,
    ],
    defaultTimeoutMs: 600000,
    maximumTimeoutMs: 3600000,
    longRunning: true,
  ),
  _operationTool(
    client: client,
    name: 'dart_fix',
    description: 'Apply Dart fixes across the workspace.',
    kind: 'fix.workspace',
    scope: _OperationScope.workspace,
    mutating: true,
    properties: const <String, Object?>{},
    required: const <String>[],
    inputKeys: const <String>{},
    operationInput: (_, _) => const <String, Object?>{},
    categories: const <CockpitMcpFeatureCategory>[
      CockpitMcpFeatureCategory.dart,
      CockpitMcpFeatureCategory.workspaceQuality,
    ],
    defaultTimeoutMs: 600000,
    maximumTimeoutMs: 1800000,
    longRunning: true,
  ),
  _operationTool(
    client: client,
    name: 'dart_format',
    description:
        'Format the workspace or selected indexed Dart files and directories.',
    kind: 'format.workspace',
    scope: _OperationScope.workspace,
    mutating: true,
    properties: <String, Object?>{'paths': _stringList()},
    required: const <String>[],
    inputKeys: const <String>{'paths'},
    operationInput: (api, arguments) async => <String, Object?>{
      if (_optionalStrings(arguments, 'paths') case final paths?)
        'documentIds': await _documentIds(
          api,
          _requiredString(arguments, 'workspaceId'),
          paths,
        ),
    },
    categories: const <CockpitMcpFeatureCategory>[
      CockpitMcpFeatureCategory.dart,
      CockpitMcpFeatureCategory.workspaceQuality,
    ],
    defaultTimeoutMs: 600000,
    maximumTimeoutMs: 1800000,
    longRunning: true,
  ),
  _operationTool(
    client: client,
    name: 'run_tests',
    description:
        'Run Dart or Flutter tests for the workspace or selected indexed paths.',
    kind: 'test.workspace',
    scope: _OperationScope.workspace,
    mutating: true,
    destructive: false,
    idempotent: true,
    properties: <String, Object?>{'paths': _stringList(), 'name': _string()},
    required: const <String>[],
    inputKeys: const <String>{'paths', 'name'},
    operationInput: (api, arguments) async => <String, Object?>{
      if (_optionalStrings(arguments, 'paths') case final paths?)
        'paths': (await _documentSelection(
          api,
          _requiredString(arguments, 'workspaceId'),
          paths,
        )).paths,
      'name': ?_optionalString(arguments, 'name'),
    },
    categories: const <CockpitMcpFeatureCategory>[
      CockpitMcpFeatureCategory.dart,
      CockpitMcpFeatureCategory.workspaceQuality,
    ],
    defaultTimeoutMs: 1800000,
    maximumTimeoutMs: 14400000,
    longRunning: true,
  ),
  _operationTool(
    client: client,
    name: 'lsp',
    description:
        'Run bounded Dart code-intelligence requests with 1-based positions.',
    kind: 'lsp.request',
    scope: _OperationScope.workspace,
    mutating: false,
    properties: <String, Object?>{
      'command': const <String, Object?>{
        'type': 'string',
        'enum': <String>[
          'hover',
          'definition',
          'signature_help',
          'document_symbols',
          'workspace_symbols',
        ],
      },
      'path': _string(),
      'line': _integer(minimum: 1, maximum: 10000000),
      'column': _integer(minimum: 1, maximum: 10000000),
      'query': _string(),
      'maxResults': _integer(minimum: 1, maximum: 1000),
      'maxChars': _integer(minimum: 100, maximum: 20000),
    },
    required: const <String>['command'],
    inputKeys: const <String>{
      'command',
      'path',
      'line',
      'column',
      'query',
      'maxResults',
      'maxChars',
    },
    operationInput: (api, arguments) async => <String, Object?>{
      'command': _lspCommand(_requiredString(arguments, 'command')),
      if (_optionalString(arguments, 'path') case final path?)
        'documentId': (await _documentIds(
          api,
          _requiredString(arguments, 'workspaceId'),
          <String>[path],
          requireSingle: true,
        )).single,
      for (final key in const <String>[
        'line',
        'column',
        'maxResults',
        'maxChars',
      ])
        if (_optionalInt(arguments, key) != null)
          key: _optionalInt(arguments, key),
      'query': ?_optionalString(arguments, 'query'),
    },
    categories: const <CockpitMcpFeatureCategory>[
      CockpitMcpFeatureCategory.dart,
      CockpitMcpFeatureCategory.codeIntelligence,
    ],
    defaultTimeoutMs: 30000,
    maximumTimeoutMs: 300000,
  ),
];

List<CockpitMcpTool> _dependencyTools(
  CockpitMcpClientProvider client,
) => <CockpitMcpTool>[
  _operationTool(
    client: client,
    name: 'pub',
    description:
        'Run a bounded pub command in one explicit Dart or Flutter workspace.',
    kind: 'package.pub',
    scope: _OperationScope.workspace,
    mutating: true,
    properties: <String, Object?>{
      'command': const <String, Object?>{
        'type': 'string',
        'enum': <String>['add', 'deps', 'get', 'outdated', 'remove', 'upgrade'],
      },
      'packages': _stringList(maximum: 100),
      'maxOutputChars': _integer(minimum: 100, maximum: 20000),
    },
    required: const <String>['command'],
    inputKeys: const <String>{'command', 'packages', 'maxOutputChars'},
    operationInput: (_, arguments) => <String, Object?>{
      'command': _requiredString(arguments, 'command'),
      'packages': _optionalStrings(arguments, 'packages') ?? const <String>[],
      'maxOutputChars': ?_optionalInt(arguments, 'maxOutputChars'),
    },
    categories: const <CockpitMcpFeatureCategory>[
      CockpitMcpFeatureCategory.dart,
      CockpitMcpFeatureCategory.dependencyIntelligence,
    ],
    defaultTimeoutMs: 1800000,
    maximumTimeoutMs: 7200000,
    longRunning: true,
  ),
  _operationTool(
    client: client,
    name: 'read_package_uris',
    description:
        'Read or list one package: or package-root: URI without printing binary data.',
    kind: 'package.uris.read',
    scope: _OperationScope.workspace,
    mutating: false,
    properties: <String, Object?>{
      'uri': _string(),
      'maxPreviewChars': _integer(minimum: 100, maximum: 20000),
      'maxEntries': _integer(minimum: 1, maximum: 1000),
      'includeFullText': const <String, Object?>{'type': 'boolean'},
    },
    required: const <String>['uri'],
    inputKeys: const <String>{
      'uri',
      'maxPreviewChars',
      'maxEntries',
      'includeFullText',
    },
    operationInput: (_, arguments) => <String, Object?>{
      'uri': _requiredString(arguments, 'uri'),
      for (final key in const <String>['maxPreviewChars', 'maxEntries'])
        key: ?_optionalInt(arguments, key),
      'includeFullText': ?_optionalBool(arguments, 'includeFullText'),
    },
    categories: const <CockpitMcpFeatureCategory>[
      CockpitMcpFeatureCategory.dart,
      CockpitMcpFeatureCategory.dependencyIntelligence,
    ],
    defaultTimeoutMs: 30000,
    maximumTimeoutMs: 300000,
  ),
  _operationTool(
    client: client,
    name: 'rip_grep_packages',
    description:
        'Search selected dependency packages with bounded structured matches.',
    kind: 'package.uris.grep',
    scope: _OperationScope.workspace,
    mutating: false,
    properties: <String, Object?>{
      'packageNames': _stringList(maximum: 100),
      'query': _string(),
      'useRegex': const <String, Object?>{'type': 'boolean'},
      'caseSensitive': const <String, Object?>{'type': 'boolean'},
      'maxMatches': _integer(minimum: 1, maximum: 1000),
    },
    required: const <String>['packageNames', 'query'],
    inputKeys: const <String>{
      'packageNames',
      'query',
      'useRegex',
      'caseSensitive',
      'maxMatches',
    },
    operationInput: (_, arguments) => <String, Object?>{
      'packageNames': _requiredStrings(arguments, 'packageNames'),
      'query': _requiredString(arguments, 'query'),
      for (final key in const <String>['useRegex', 'caseSensitive'])
        key: ?_optionalBool(arguments, key),
      'maxMatches': ?_optionalInt(arguments, 'maxMatches'),
    },
    categories: const <CockpitMcpFeatureCategory>[
      CockpitMcpFeatureCategory.dart,
      CockpitMcpFeatureCategory.dependencyIntelligence,
    ],
    defaultTimeoutMs: 30000,
    maximumTimeoutMs: 300000,
  ),
  _operationTool(
    client: client,
    name: 'pub_dev_search',
    description: 'Search pub.dev for bounded package metadata.',
    kind: 'package.search',
    scope: _OperationScope.root,
    mutating: false,
    properties: <String, Object?>{
      'query': _string(),
      'maxResults': _integer(minimum: 1, maximum: 50),
    },
    required: const <String>['query'],
    inputKeys: const <String>{'query', 'maxResults'},
    operationInput: (_, arguments) => <String, Object?>{
      'query': _requiredString(arguments, 'query'),
      'maxResults': ?_optionalInt(arguments, 'maxResults'),
    },
    categories: const <CockpitMcpFeatureCategory>[
      CockpitMcpFeatureCategory.dart,
      CockpitMcpFeatureCategory.dependencyIntelligence,
    ],
    defaultTimeoutMs: 30000,
    maximumTimeoutMs: 300000,
  ),
];

List<CockpitMcpTool> _projectTools(
  CockpitMcpClientProvider client,
) => <CockpitMcpTool>[
  _operationTool(
    client: client,
    name: 'create_project',
    description:
        'Create a Dart CLI or Flutter app under one registered project root.',
    kind: 'project.create',
    scope: _OperationScope.root,
    mutating: true,
    properties: <String, Object?>{
      'parentDirectory': _string(),
      'projectName': _string(),
      'template': const <String, Object?>{
        'type': 'string',
        'enum': <String>['dart_cli', 'flutter_app'],
      },
      'organization': _string(),
      'platforms': _stringList(maximum: 16),
    },
    required: const <String>['projectName', 'template'],
    inputKeys: const <String>{
      'parentDirectory',
      'projectName',
      'template',
      'organization',
      'platforms',
    },
    operationInput: (_, arguments) => <String, Object?>{
      'parentDirectory': ?_optionalString(arguments, 'parentDirectory'),
      'projectName': _requiredString(arguments, 'projectName'),
      'template': _requiredString(arguments, 'template'),
      'organization': ?_optionalString(arguments, 'organization'),
      'platforms': _optionalStrings(arguments, 'platforms') ?? const <String>[],
    },
    categories: const <CockpitMcpFeatureCategory>[
      CockpitMcpFeatureCategory.dart,
      CockpitMcpFeatureCategory.flutter,
      CockpitMcpFeatureCategory.projectScaffolding,
    ],
    defaultTimeoutMs: 600000,
    maximumTimeoutMs: 1800000,
    longRunning: true,
  ),
];

CockpitMcpApiTool _operationTool({
  required CockpitMcpClientProvider client,
  required String name,
  required String description,
  required String kind,
  required _OperationScope scope,
  required bool mutating,
  required Map<String, Object?> properties,
  required List<String> required,
  required Set<String> inputKeys,
  required FutureOr<Map<String, Object?>> Function(
    CockpitSupervisorApiClient api,
    Map<String, Object?> arguments,
  )
  operationInput,
  required List<CockpitMcpFeatureCategory> categories,
  required int defaultTimeoutMs,
  required int maximumTimeoutMs,
  bool longRunning = false,
  bool? destructive,
  bool? idempotent,
}) {
  final scopeKey = scope == _OperationScope.root ? 'rootId' : 'workspaceId';
  final standardKeys = <String>{
    scopeKey,
    'timeoutMs',
    if (mutating) 'idempotencyKey',
  };
  return CockpitMcpApiTool(
    client: client,
    name: name,
    description: description,
    featureCategories: categories,
    isEnabledByDefault: false,
    toolAnnotations: CockpitMcpToolAnnotations(
      readOnly: !mutating,
      destructive: destructive ?? mutating,
      idempotent: idempotent ?? !mutating,
      longRunning: longRunning,
      requiresSession: false,
      producesBundleEvidence: false,
    ),
    inputSchema: _schema(
      properties: <String, Object?>{
        scopeKey: _string(),
        ...properties,
        if (mutating) 'idempotencyKey': _string(),
        'timeoutMs': _integer(minimum: 1, maximum: maximumTimeoutMs),
      },
      required: <String>[scopeKey, ...required, if (mutating) 'idempotencyKey'],
    ),
    action: (api, arguments) async {
      _only(arguments, <String>{...standardKeys, ...inputKeys});
      final timeoutMs =
          _optionalInt(arguments, 'timeoutMs') ?? defaultTimeoutMs;
      final result = await api.executeOperation(
        CockpitOperationInvocation(
          kind: kind,
          input: await operationInput(api, arguments),
          rootId: scope == _OperationScope.root
              ? _requiredString(arguments, 'rootId')
              : null,
          workspaceId: scope == _OperationScope.workspace
              ? _requiredString(arguments, 'workspaceId')
              : null,
          idempotencyKey: mutating
              ? CockpitIdempotencyKey(
                  _requiredString(arguments, 'idempotencyKey'),
                )
              : null,
          deadline: DateTime.now().toUtc().add(
            Duration(milliseconds: timeoutMs),
          ),
        ),
      );
      return result.toJson();
    },
  );
}

enum _OperationScope { root, workspace }

Map<String, Object?> _schema({
  required Map<String, Object?> properties,
  List<String> required = const <String>[],
}) => <String, Object?>{
  r'$schema': 'https://json-schema.org/draft/2020-12/schema',
  'type': 'object',
  'properties': properties,
  'required': required,
  'additionalProperties': false,
};

Map<String, Object?> _string() => const <String, Object?>{'type': 'string'};

Map<String, Object?> _integer({required int minimum, required int maximum}) =>
    <String, Object?>{
      'type': 'integer',
      'minimum': minimum,
      'maximum': maximum,
    };

Map<String, Object?> _stringList({int maximum = 512}) => <String, Object?>{
  'type': 'array',
  'maxItems': maximum,
  'items': _string(),
};

void _only(Map<String, Object?> arguments, Set<String> allowed) {
  final unknown = arguments.keys.where((key) => !allowed.contains(key));
  if (unknown.isNotEmpty) {
    throw FormatException('Unknown tool argument ${unknown.first}.');
  }
}

String _requiredString(Map<String, Object?> arguments, String key) {
  final value = arguments[key];
  if (value is String && value.trim().isNotEmpty) return value;
  throw FormatException('$key is required.');
}

int? _optionalInt(Map<String, Object?> arguments, String key) {
  final value = arguments[key];
  if (value == null) return null;
  if (value is int) return value;
  throw FormatException('$key must be an integer.');
}

bool? _optionalBool(Map<String, Object?> arguments, String key) {
  final value = arguments[key];
  if (value == null) return null;
  if (value is bool) return value;
  throw FormatException('$key must be a boolean.');
}

String? _optionalString(Map<String, Object?> arguments, String key) {
  final value = arguments[key];
  if (value == null) return null;
  if (value is String && value.trim().isNotEmpty) return value;
  throw FormatException('$key must be a non-empty string.');
}

List<String> _requiredStrings(Map<String, Object?> arguments, String key) {
  final value = arguments[key];
  if (value is! List<Object?> ||
      value.isEmpty ||
      !value.every((e) => e is String)) {
    throw FormatException('$key must be a non-empty string list.');
  }
  return value.cast<String>();
}

List<String>? _optionalStrings(Map<String, Object?> arguments, String key) {
  if (arguments[key] == null) return null;
  return _requiredStrings(arguments, key);
}

Future<List<String>> _documentIds(
  CockpitSupervisorApiClient api,
  String workspaceId,
  List<String> paths, {
  bool requireSingle = false,
}) async => (await _documentSelection(
  api,
  workspaceId,
  paths,
  requireSingle: requireSingle,
)).documentIds;

Future<({List<String> paths, List<String> documentIds})> _documentSelection(
  CockpitSupervisorApiClient api,
  String workspaceId,
  List<String> paths, {
  bool requireSingle = false,
}) async {
  String? workspacePath;
  if (paths.any(_isAbsolutePath)) {
    for (final workspace in await api.workspaces()) {
      if (workspace.workspaceId == workspaceId) {
        workspacePath = workspace.canonicalPath;
        break;
      }
    }
    if (workspacePath == null) {
      throw FormatException('Unknown workspace $workspaceId.');
    }
  }
  final requested = <String>[
    for (final path in paths) _workspaceRelativePosixPath(path, workspacePath),
  ];
  final documents = await api.documents(workspaceId);
  final matches = <String>[];
  for (final path in requested) {
    final pathMatches = documents
        .where((document) {
          if (p.posix.extension(document.relativePath) != '.dart') return false;
          return path == '.' ||
              document.relativePath == path ||
              document.relativePath.startsWith('$path/');
        })
        .toList(growable: false);
    if (pathMatches.isEmpty) {
      throw FormatException('No indexed Dart document matched $path.');
    }
    for (final document in pathMatches) {
      if (!matches.contains(document.documentId)) {
        matches.add(document.documentId);
      }
    }
  }
  if (requireSingle && matches.length != 1) {
    throw const FormatException('path must identify exactly one Dart file.');
  }
  return (paths: requested, documentIds: matches);
}

bool _isAbsolutePath(String value) =>
    p.isAbsolute(value) || p.windows.isAbsolute(value);

String _workspaceRelativePosixPath(String value, String? workspacePath) {
  if (_isAbsolutePath(value)) {
    final root = workspacePath!;
    final candidate = p.normalize(value.trim());
    if (!p.equals(candidate, root) && !p.isWithin(root, candidate)) {
      throw const FormatException('paths must stay inside the workspace.');
    }
    return _relativePosixPath(p.relative(candidate, from: root));
  }
  return _relativePosixPath(value);
}

String _relativePosixPath(String value) {
  final candidate = value.replaceAll('\\', '/').trim();
  if (candidate.isEmpty || p.posix.isAbsolute(candidate)) {
    throw const FormatException('paths must identify workspace documents.');
  }
  final normalized = p.posix.normalize(candidate);
  if (normalized == '..' || normalized.startsWith('../')) {
    throw const FormatException('paths must stay inside the workspace.');
  }
  return normalized;
}

String _lspCommand(String value) => switch (value) {
  'hover' => 'hover',
  'definition' => 'definition',
  'signature_help' => 'signatureHelp',
  'document_symbols' => 'documentSymbols',
  'workspace_symbols' => 'workspaceSymbols',
  _ => throw const FormatException('Unsupported LSP command.'),
};
