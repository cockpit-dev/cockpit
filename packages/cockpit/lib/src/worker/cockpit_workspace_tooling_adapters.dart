import 'dart:async';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../application/cockpit_analyze_files_service.dart';
import '../application/cockpit_analyze_workspace_service.dart';
import '../application/cockpit_apply_workspace_fixes_service.dart';
import '../application/cockpit_format_workspace_service.dart';
import '../application/cockpit_grep_package_uris_service.dart';
import '../application/cockpit_lsp_service.dart';
import '../application/cockpit_pub_service.dart';
import '../application/cockpit_read_package_uris_service.dart';
import '../application/cockpit_run_workspace_tests_service.dart';
import 'cockpit_worker_document_index.dart';
import 'cockpit_worker_process_manager.dart';
import 'cockpit_worker_resource_grant.dart';
import 'cockpit_worker_value_reader.dart';
import 'cockpit_workspace_operation_registry.dart';

final class CockpitWorkspaceToolingAdapters {
  factory CockpitWorkspaceToolingAdapters({
    required String workspaceId,
    required String workspaceRoot,
    required CockpitWorkerDocumentIndex documents,
    CockpitWorkerProcessManager? processManager,
    CockpitAnalyzeFilesService? analyzeFiles,
    CockpitAnalyzeWorkspaceService? analyzeWorkspace,
    CockpitApplyWorkspaceFixesService? applyFixes,
    CockpitFormatWorkspaceService? formatWorkspace,
    CockpitRunWorkspaceTestsService? runTests,
    CockpitPubService? pub,
    CockpitLspService? lsp,
    CockpitReadPackageUrisService? readPackageUris,
    CockpitGrepPackageUrisService? grepPackageUris,
  }) {
    final manager = processManager ?? CockpitWorkerProcessManager();
    return CockpitWorkspaceToolingAdapters._(
      workspaceId: workspaceId,
      workspaceRoot: workspaceRoot,
      documents: documents,
      processManager: manager,
      analyzeFiles:
          analyzeFiles ?? CockpitAnalyzeFilesService(processManager: manager),
      analyzeWorkspace:
          analyzeWorkspace ??
          CockpitAnalyzeWorkspaceService(processManager: manager),
      applyFixes:
          applyFixes ??
          CockpitApplyWorkspaceFixesService(processManager: manager),
      formatWorkspace:
          formatWorkspace ??
          CockpitFormatWorkspaceService(processManager: manager),
      runTests:
          runTests ?? CockpitRunWorkspaceTestsService(processManager: manager),
      pub: pub ?? CockpitPubService(processManager: manager),
      lsp: lsp ?? CockpitLspService(processManager: manager),
      readPackageUris: readPackageUris ?? CockpitReadPackageUrisService(),
      grepPackageUris:
          grepPackageUris ??
          CockpitGrepPackageUrisService(processManager: manager),
    );
  }

  CockpitWorkspaceToolingAdapters._({
    required this.workspaceId,
    required this.workspaceRoot,
    required CockpitWorkerDocumentIndex documents,
    required CockpitWorkerProcessManager processManager,
    required CockpitAnalyzeFilesService analyzeFiles,
    required CockpitAnalyzeWorkspaceService analyzeWorkspace,
    required CockpitApplyWorkspaceFixesService applyFixes,
    required CockpitFormatWorkspaceService formatWorkspace,
    required CockpitRunWorkspaceTestsService runTests,
    required CockpitPubService pub,
    required CockpitLspService lsp,
    required CockpitReadPackageUrisService readPackageUris,
    required CockpitGrepPackageUrisService grepPackageUris,
  }) : _documents = documents,
       _processManager = processManager,
       _analyzeFiles = analyzeFiles,
       _analyzeWorkspace = analyzeWorkspace,
       _applyFixes = applyFixes,
       _formatWorkspace = formatWorkspace,
       _runTests = runTests,
       _pub = pub,
       _lsp = lsp,
       _readPackageUris = readPackageUris,
       _grepPackageUris = grepPackageUris;

  final String workspaceId;
  final String workspaceRoot;
  final CockpitWorkerDocumentIndex _documents;
  final CockpitWorkerProcessManager _processManager;
  final CockpitAnalyzeFilesService _analyzeFiles;
  final CockpitAnalyzeWorkspaceService _analyzeWorkspace;
  final CockpitApplyWorkspaceFixesService _applyFixes;
  final CockpitFormatWorkspaceService _formatWorkspace;
  final CockpitRunWorkspaceTestsService _runTests;
  final CockpitPubService _pub;
  final CockpitLspService _lsp;
  final CockpitReadPackageUrisService _readPackageUris;
  final CockpitGrepPackageUrisService _grepPackageUris;

  List<CockpitWorkspaceOperationAdapter> create() =>
      <CockpitWorkspaceOperationAdapter>[
        _readAdapter('analyze.files', _analyzeFilesOperation),
        _readAdapter('analyze.workspace', _analyzeWorkspaceOperation),
        _mutationAdapter('fix.workspace', _fixWorkspaceOperation),
        _mutationAdapter('format.workspace', _formatWorkspaceOperation),
        _mutationAdapter('test.workspace', _testWorkspaceOperation),
        _mutationAdapter('package.pub', _pubOperation),
        _readAdapter('lsp.request', _lspOperation),
        _readAdapter('package.uris.read', _readPackageUrisOperation),
        _readAdapter('package.uris.grep', _grepPackageUrisOperation),
      ];

  CockpitWorkspaceOperationAdapter _readAdapter(
    String kind,
    Future<Map<String, Object?>> Function(
      CockpitWorkspaceOperationContext,
      Map<String, Object?>,
    )
    execute,
  ) => CockpitWorkspaceOperationAdapter(
    kind: kind,
    mutationClass: CockpitMutationClass.readOnly,
    resourceKinds: const <String>['workspace.tooling'],
    prepare: (context, input) => CockpitPreparedWorkspaceOperation(
      resources: const <CockpitWorkerResourceRequest>[],
      execute: (_) => execute(context, input),
    ),
  );

  CockpitWorkspaceOperationAdapter _mutationAdapter(
    String kind,
    Future<Map<String, Object?>> Function(
      CockpitWorkspaceOperationContext,
      Map<String, Object?>,
    )
    execute,
  ) => CockpitWorkspaceOperationAdapter(
    kind: kind,
    mutationClass: CockpitMutationClass.mutating,
    resourceKinds: const <String>['workspace.tooling'],
    prepare: (context, input) => CockpitPreparedWorkspaceOperation(
      resources: <CockpitWorkerResourceRequest>[
        CockpitWorkerResourceRequest(
          resourceKind: CockpitLeaseResourceKind.workspaceMutation,
          resourceId: workspaceId,
          ttl: _grantTtl(context),
        ),
      ],
      execute: (_) => execute(context, input),
    ),
  );

  Future<Map<String, Object?>> _analyzeFilesOperation(
    CockpitWorkspaceOperationContext context,
    Map<String, Object?> input,
  ) async {
    workerKeys(
      input,
      const <String>{'documentIds', 'maxDiagnostics', 'maxOutputChars'},
      r'$.input',
      required: const <String>{'documentIds'},
    );
    final rawIds = workerList(
      input['documentIds'],
      r'$.input.documentIds',
      maximum: 512,
    );
    final ids = <String>[
      for (var index = 0; index < rawIds.length; index += 1)
        workerId(rawIds[index], '\$.input.documentIds[$index]'),
    ];
    final paths = await _documents.resolvePaths(ids);
    final result = await _raceCancellation(
      () => _analyzeFiles.analyze(
        CockpitAnalyzeFilesRequest(
          workspaceRoot: workspaceRoot,
          allowedRoots: <String>[workspaceRoot],
          paths: paths,
          maxDiagnostics: _optionalInteger(
            input,
            'maxDiagnostics',
            50,
            1,
            1000,
          ),
          maxOutputChars: _optionalInteger(
            input,
            'maxOutputChars',
            1600,
            100,
            20000,
          ),
          timeout: _timeout(context),
        ),
      ),
      context,
    );
    return _sanitize(result.toJson());
  }

  Future<Map<String, Object?>> _analyzeWorkspaceOperation(
    CockpitWorkspaceOperationContext context,
    Map<String, Object?> input,
  ) async {
    _empty(input);
    final result = await _raceCancellation(
      () => _analyzeWorkspace.analyze(
        CockpitAnalyzeWorkspaceRequest(
          workspaceRoot: workspaceRoot,
          allowedRoots: <String>[workspaceRoot],
          timeout: _timeout(context),
        ),
      ),
      context,
    );
    return _sanitize(result.toJson());
  }

  Future<Map<String, Object?>> _fixWorkspaceOperation(
    CockpitWorkspaceOperationContext context,
    Map<String, Object?> input,
  ) async {
    _empty(input);
    final result = await _raceCancellation(
      () => _applyFixes.apply(
        CockpitApplyWorkspaceFixesRequest(
          workspaceRoot: workspaceRoot,
          allowedRoots: <String>[workspaceRoot],
          timeout: _timeout(context),
        ),
      ),
      context,
    );
    return _sanitize(result.toJson());
  }

  Future<Map<String, Object?>> _formatWorkspaceOperation(
    CockpitWorkspaceOperationContext context,
    Map<String, Object?> input,
  ) async {
    workerKeys(input, const <String>{'documentIds'}, r'$.input');
    final paths = input['documentIds'] == null
        ? const <String>[]
        : await _documents.resolvePaths(
            _documentIds(input['documentIds'], r'$.input.documentIds'),
          );
    final result = await _raceCancellation(
      () => _formatWorkspace.format(
        CockpitFormatWorkspaceRequest(
          workspaceRoot: workspaceRoot,
          allowedRoots: <String>[workspaceRoot],
          paths: paths,
          timeout: _timeout(context),
        ),
      ),
      context,
    );
    return _sanitize(result.toJson());
  }

  Future<Map<String, Object?>> _testWorkspaceOperation(
    CockpitWorkspaceOperationContext context,
    Map<String, Object?> input,
  ) async {
    workerKeys(input, const <String>{'paths', 'name'}, r'$.input');
    final rawPaths = input['paths'] == null
        ? const <Object?>[]
        : workerList(input['paths'], r'$.input.paths', maximum: 512);
    final paths = <String>[
      for (var index = 0; index < rawPaths.length; index += 1)
        workerString(rawPaths[index], '\$.input.paths[$index]', maximum: 32768),
    ];
    final result = await _raceCancellation(
      () => _runTests.run(
        CockpitRunWorkspaceTestsRequest(
          workspaceRoot: workspaceRoot,
          allowedRoots: <String>[workspaceRoot],
          paths: paths,
          name: input['name'] == null
              ? null
              : workerString(input['name'], r'$.input.name', maximum: 1024),
          timeout: _timeout(context),
        ),
      ),
      context,
    );
    return _sanitize(result.toJson());
  }

  Future<Map<String, Object?>> _pubOperation(
    CockpitWorkspaceOperationContext context,
    Map<String, Object?> input,
  ) async {
    workerKeys(
      input,
      const <String>{'command', 'packages', 'maxOutputChars'},
      r'$.input',
      required: const <String>{'command', 'packages'},
    );
    final commandName = workerString(input['command'], r'$.input.command');
    final commands = CockpitPubCommand.values
        .where((command) => command.name == commandName)
        .toList(growable: false);
    if (commands.length != 1) {
      throw const FormatException('Invalid pub command.');
    }
    final rawPackages = workerList(
      input['packages'],
      r'$.input.packages',
      maximum: 100,
    );
    final packages = <String>[
      for (var index = 0; index < rawPackages.length; index += 1)
        workerString(
          rawPackages[index],
          '\$.input.packages[$index]',
          maximum: 256,
        ),
    ];
    final result = await _raceCancellation(
      () => _pub.run(
        CockpitPubRequest(
          workspaceRoot: workspaceRoot,
          allowedRoots: <String>[workspaceRoot],
          command: commands.single,
          packages: packages,
          maxOutputChars: _optionalInteger(
            input,
            'maxOutputChars',
            1600,
            100,
            20000,
          ),
          timeout: _timeout(context),
        ),
      ),
      context,
    );
    return _sanitize(result.toJson());
  }

  Future<Map<String, Object?>> _lspOperation(
    CockpitWorkspaceOperationContext context,
    Map<String, Object?> input,
  ) async {
    workerKeys(
      input,
      const <String>{
        'command',
        'documentId',
        'line',
        'column',
        'query',
        'maxResults',
        'maxChars',
      },
      r'$.input',
      required: const <String>{'command'},
    );
    final commandName = workerString(input['command'], r'$.input.command');
    final commands = CockpitLspCommand.values
        .where((command) => command.name == commandName)
        .toList(growable: false);
    if (commands.length != 1) {
      throw const FormatException('Invalid LSP command.');
    }
    String? path;
    if (input['documentId'] != null) {
      path = (await _documents.resolvePaths(<String>[
        workerId(input['documentId'], r'$.input.documentId'),
      ])).single;
    }
    final result = await _raceCancellation(
      () => _lsp.invoke(
        CockpitLspRequest(
          workspaceRoot: workspaceRoot,
          allowedRoots: <String>[workspaceRoot],
          command: commands.single,
          path: path,
          line: input['line'] == null
              ? null
              : workerInteger(input['line'], r'$.input.line'),
          column: input['column'] == null
              ? null
              : workerInteger(input['column'], r'$.input.column'),
          query: input['query'] == null
              ? null
              : workerString(input['query'], r'$.input.query', maximum: 512),
          maxResults: _optionalInteger(input, 'maxResults', 20, 1, 1000),
          maxChars: _optionalInteger(input, 'maxChars', 1600, 100, 20000),
          timeout: _timeout(context),
        ),
      ),
      context,
    );
    return _sanitize(result.toJson());
  }

  Future<Map<String, Object?>> _readPackageUrisOperation(
    CockpitWorkspaceOperationContext context,
    Map<String, Object?> input,
  ) async {
    workerKeys(
      input,
      const <String>{'uri', 'maxPreviewChars', 'maxEntries', 'includeFullText'},
      r'$.input',
      required: const <String>{'uri'},
    );
    final result = await _raceCancellation(
      () => _readPackageUris.read(
        CockpitReadPackageUrisRequest(
          workspaceRoot: workspaceRoot,
          allowedRoots: <String>[workspaceRoot],
          uri: workerString(input['uri'], r'$.input.uri', maximum: 4096),
          maxPreviewChars: _optionalInteger(
            input,
            'maxPreviewChars',
            1200,
            100,
            20000,
          ),
          maxEntries: _optionalInteger(input, 'maxEntries', 40, 1, 1000),
          includeFullText: input['includeFullText'] == null
              ? false
              : workerBoolean(
                  input['includeFullText'],
                  r'$.input.includeFullText',
                ),
        ),
      ),
      context,
    );
    final uri = workerString(input['uri'], r'$.input.uri', maximum: 4096);
    return <String, Object?>{
      'uri': uri,
      'kind': result.kind.name,
      'contentKind': result.contentKind.name,
      if (result.preview != null) 'preview': result.preview,
      if (result.text != null) 'text': result.text,
      if (result.mediaType != null) 'mediaType': result.mediaType,
      if (result.totalBytes != null) 'totalBytes': result.totalBytes,
      'entryCount': result.entryCount,
      'truncated': result.truncated,
      'entries': <Map<String, Object?>>[
        for (final entry in result.entries)
          <String, Object?>{
            'name': entry.name,
            'isDirectory': entry.isDirectory,
            'packageUri': _packageChildUri(uri, entry.name),
          },
      ],
    };
  }

  Future<Map<String, Object?>> _grepPackageUrisOperation(
    CockpitWorkspaceOperationContext context,
    Map<String, Object?> input,
  ) async {
    workerKeys(
      input,
      const <String>{
        'packageNames',
        'query',
        'useRegex',
        'caseSensitive',
        'maxMatches',
      },
      r'$.input',
      required: const <String>{'packageNames', 'query'},
    );
    final rawNames = workerList(
      input['packageNames'],
      r'$.input.packageNames',
      maximum: 100,
    );
    final result = await _raceCancellation(
      () => _grepPackageUris.grep(
        CockpitGrepPackageUrisRequest(
          workspaceRoot: workspaceRoot,
          allowedRoots: <String>[workspaceRoot],
          packageNames: <String>[
            for (var index = 0; index < rawNames.length; index += 1)
              workerId(rawNames[index], '\$.input.packageNames[$index]'),
          ],
          query: workerString(input['query'], r'$.input.query', maximum: 1024),
          useRegex: input['useRegex'] == null
              ? false
              : workerBoolean(input['useRegex'], r'$.input.useRegex'),
          caseSensitive: input['caseSensitive'] == null
              ? false
              : workerBoolean(input['caseSensitive'], r'$.input.caseSensitive'),
          maxMatches: _optionalInteger(input, 'maxMatches', 60, 1, 1000),
          timeout: _timeout(context),
        ),
      ),
      context,
    );
    return <String, Object?>{
      'query': result.query,
      'searchDir': result.searchDir,
      'useRegex': result.useRegex,
      'caseSensitive': result.caseSensitive,
      'usedRipgrep': result.usedRipgrep,
      'matchedPackageCount': result.matchedPackageCount,
      'matchedFileCount': result.matchedFileCount,
      'totalMatches': result.totalMatches,
      'truncated': result.truncated,
      'summary': result.summary,
      'packages': <Map<String, Object?>>[
        for (final package in result.packages)
          <String, Object?>{
            'packageName': package.packageName,
            'fileCount': package.files.length,
            'matchCount': package.matchCount,
            'truncated': package.truncated,
            if (package.error != null) 'error': package.error,
            'files': <Map<String, Object?>>[
              for (final file in package.files)
                <String, Object?>{
                  'relativePath': file.relativePath,
                  'packageRootUri': file.packageRootUri,
                  if (file.packageUri != null) 'packageUri': file.packageUri,
                  'matchCount': file.matches.length,
                  'matches': <Map<String, Object?>>[
                    for (final match in file.matches) match.toJson(),
                  ],
                },
            ],
          },
      ],
      if (result.warnings.isNotEmpty) 'warnings': result.warnings,
    };
  }

  Duration _timeout(CockpitWorkspaceOperationContext context) {
    final remaining = context.deadline.difference(DateTime.now().toUtc());
    if (remaining <= Duration.zero) throw TimeoutException('Deadline expired.');
    return remaining;
  }

  Duration _grantTtl(CockpitWorkspaceOperationContext context) {
    final timeout = _timeout(context);
    return timeout > const Duration(minutes: 5)
        ? const Duration(minutes: 5)
        : timeout;
  }

  Future<T> _raceCancellation<T>(
    Future<T> Function() operation,
    CockpitWorkspaceOperationContext context,
  ) => _processManager.runScoped(context.cancellation, operation);

  void _empty(Map<String, Object?> input) =>
      workerKeys(input, const <String>{}, r'$.input');

  List<String> _documentIds(Object? value, String path) {
    final raw = workerList(value, path, maximum: 512);
    return <String>[
      for (var index = 0; index < raw.length; index += 1)
        workerId(raw[index], '$path[$index]'),
    ];
  }

  int _optionalInteger(
    Map<String, Object?> input,
    String key,
    int fallback,
    int minimum,
    int maximum,
  ) => input[key] == null
      ? fallback
      : workerInteger(
          input[key],
          '\$.input.$key',
          minimum: minimum,
          maximum: maximum,
        );

  Map<String, Object?> _sanitize(Map<String, Object?> value) =>
      _sanitizeValue(value) as Map<String, Object?>;

  String _packageChildUri(String parent, String name) {
    if (name.isEmpty || name.contains('/') || name.contains(r'\')) {
      throw const FormatException('Package directory entry name is invalid.');
    }
    final separator = parent.endsWith('/') ? '' : '/';
    return '$parent$separator${Uri.encodeComponent(name)}';
  }

  Object? _sanitizeValue(Object? value) {
    if (value is String) {
      return value.replaceAll(workspaceRoot, '<workspace>');
    }
    if (value is List<Object?>) {
      return value.map(_sanitizeValue).toList(growable: false);
    }
    if (value is Map<Object?, Object?>) {
      return <String, Object?>{
        for (final entry in value.entries)
          '${entry.key}': _sanitizeValue(entry.value),
      };
    }
    return value;
  }
}
