import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../foundation/cockpit_ids.dart';
import '../foundation/cockpit_locked_json_store.dart';
import '../foundation/cockpit_permissions.dart';
import '../suite/cockpit_suite_compiler.dart';
import '../test/cockpit_test_document_compiler.dart';
import 'cockpit_case_run_adapter.dart';
import 'cockpit_worker_resource_grant.dart';
import 'cockpit_worker_value_reader.dart';
import 'cockpit_workspace_operation_registry.dart';

final class CockpitWorkerDocumentIndex
    implements CockpitWorkerCaseIndex, CockpitSuiteCaseResolver {
  CockpitWorkerDocumentIndex({
    this.workspaceId = 'workspace-local',
    required this.workspaceRoot,
    required this.stateRoot,
    required CockpitPermissionHardener permissionHardener,
    required CockpitDirectorySyncer directorySyncer,
    CockpitTokenGenerator? tokenGenerator,
    p.Context? pathContext,
  }) : _tokenGenerator = tokenGenerator ?? CockpitSecureTokenGenerator(),
       _permissionHardener = permissionHardener,
       _directorySyncer = directorySyncer,
       _atomicFile = CockpitAtomicJsonFile(
         permissionHardener: permissionHardener,
         directorySyncer: directorySyncer,
       ),
       _paths = pathContext ?? p.context;

  static const int maximumFiles = 10000;
  static const int maximumIndexedFileBytes = 1048576;
  static const int maximumIndexBytes = 16 * 1024 * 1024;
  static const Set<String> _extensions = <String>{
    '.dart',
    '.yaml',
    '.yml',
    '.json',
    '.lon',
  };
  static const Set<String> _excludedDirectoryNames = <String>{
    '.dart_tool',
    '.git',
    '.gradle',
    '.idea',
    '.pub-cache',
    '.symlinks',
    '.vscode',
    'build',
    'coverage',
    'deriveddata',
    'ephemeral',
    'node_modules',
    'pods',
  };

  final String workspaceId;
  final String workspaceRoot;
  final String stateRoot;
  final CockpitTokenGenerator _tokenGenerator;
  final CockpitPermissionHardener _permissionHardener;
  final CockpitDirectorySyncer _directorySyncer;
  final CockpitAtomicJsonFile _atomicFile;
  final p.Context _paths;
  final Map<String, _IndexedDocument> _byId = <String, _IndexedDocument>{};
  var _loaded = false;

  CockpitWorkspaceOperationAdapter operationAdapter() =>
      CockpitWorkspaceOperationAdapter(
        kind: 'document.index',
        mutationClass: CockpitMutationClass.mutating,
        resourceKinds: const <String>['workspace.documents'],
        prepare: (context, input) {
          workerKeys(input, const <String>{'kind', 'relativePath'}, r'$.input');
          final kind = input['kind'] == null
              ? null
              : workerString(input['kind'], r'$.input.kind', maximum: 16);
          if (kind != null &&
              !const <String>{
                'source',
                'case',
                'suite',
                'project',
              }.contains(kind)) {
            throw const FormatException('Invalid indexed document kind.');
          }
          final relativePath = input['relativePath'] == null
              ? null
              : workerString(input['relativePath'], r'$.input.relativePath');
          if (relativePath != null && !_isConfinedRelative(relativePath)) {
            throw const FormatException(
              'Indexed document path must be workspace-relative and confined.',
            );
          }
          return CockpitPreparedWorkspaceOperation(
            resources: <CockpitWorkerResourceRequest>[
              CockpitWorkerResourceRequest(
                resourceKind: CockpitLeaseResourceKind.workspaceMutation,
                resourceId: context.workspaceId,
              ),
            ],
            execute: (_) async {
              final documents = await refresh();
              return <String, Object?>{
                'documentCount': documents.length,
                if (kind != null || relativePath != null)
                  'matchedCount': documents
                      .where(
                        (document) =>
                            (kind == null || document['kind'] == kind) &&
                            (relativePath == null ||
                                document['relativePath'] == relativePath),
                      )
                      .length,
              };
            },
          );
        },
      );

  CockpitWorkspaceOperationAdapter listOperationAdapter() =>
      CockpitWorkspaceOperationAdapter(
        kind: 'document.list',
        mutationClass: CockpitMutationClass.readOnly,
        resourceKinds: const <String>['workspace.documents'],
        prepare: (context, input) {
          workerKeys(
            input,
            const <String>{'kind', 'relativePath', 'offset', 'limit'},
            r'$.input',
            required: const <String>{'offset', 'limit'},
          );
          final kind = input['kind'] == null
              ? null
              : workerString(input['kind'], r'$.input.kind', maximum: 16);
          if (kind != null &&
              !const <String>{
                'source',
                'case',
                'suite',
                'project',
                'authored',
              }.contains(kind)) {
            throw const FormatException('Invalid indexed document kind.');
          }
          final relativePath = input['relativePath'] == null
              ? null
              : workerString(input['relativePath'], r'$.input.relativePath');
          if (relativePath != null && !_isConfinedRelative(relativePath)) {
            throw const FormatException(
              'Indexed document path must be workspace-relative and confined.',
            );
          }
          final offset = workerInteger(
            input['offset'],
            r'$.input.offset',
            minimum: 0,
            maximum: maximumFiles,
          );
          final limit = workerInteger(
            input['limit'],
            r'$.input.limit',
            minimum: 1,
            maximum: 100,
          );
          return CockpitPreparedWorkspaceOperation(
            resources: const <CockpitWorkerResourceRequest>[],
            execute: (_) async {
              final page = await list(
                kind: kind,
                relativePath: relativePath,
                offset: offset,
                limit: limit,
              );
              return <String, Object?>{
                'documents': page.documents,
                'totalCount': page.totalCount,
              };
            },
          );
        },
      );

  Future<List<Map<String, Object?>>> refresh() async {
    final previous = await _loadPersistedMetadata();
    final root = Directory(workspaceRoot);
    if (!await root.exists()) {
      throw const FormatException('Registered workspace root is unavailable.');
    }
    final next = <String, _IndexedDocument>{};
    var visited = 0;
    final pendingDirectories = <Directory>[root];
    while (pendingDirectories.isNotEmpty) {
      final directory = pendingDirectories.removeLast();
      await for (final entity in directory.list(followLinks: false)) {
        final relativePath = p.posix.joinAll(
          _paths.split(_paths.relative(entity.path, from: workspaceRoot)),
        );
        if (!_isConfinedRelative(relativePath)) continue;
        if (entity is Directory) {
          if (!_excludedDirectoryNames.contains(
            _paths.basename(entity.path).toLowerCase(),
          )) {
            pendingDirectories.add(entity);
          }
          continue;
        }
        if (entity is! File ||
            !_extensions.contains(_paths.extension(entity.path))) {
          continue;
        }
        visited += 1;
        if (visited > maximumFiles) {
          throw const FormatException(
            'Workspace document index exceeds bounds.',
          );
        }
        final resolved = await _readConfinedDocument(relativePath);
        if (resolved == null) continue;
        final bytes = resolved.bytes;
        final sourceSha256 = resolved.sourceSha256;
        final documentId =
            previous[relativePath]?.documentId ?? _newDocumentId();
        CockpitCompiledTestDocument? compiled;
        if (_paths.extension(entity.path) != '.dart') {
          try {
            final candidate = const CockpitTestDocumentCompiler()
                .compile(
                  utf8.decode(bytes, allowMalformed: false),
                  format: _documentFormat(entity.path),
                )
                .compiled;
            compiled = candidate;
          } on Object {
            compiled = null;
          }
        }
        next[documentId] = _IndexedDocument(
          documentId: documentId,
          relativePath: relativePath,
          sourceSha256: sourceSha256,
          compiled: compiled,
        );
      }
    }
    final previousById = Map<String, _IndexedDocument>.from(_byId);
    final wasLoaded = _loaded;
    _byId
      ..clear()
      ..addAll(next);
    _loaded = true;
    try {
      await _persist();
    } catch (_) {
      _byId
        ..clear()
        ..addAll(previousById);
      _loaded = wasLoaded;
      rethrow;
    }
    final summaries = <Map<String, Object?>>[];
    for (final document in _byId.values) {
      final stat = await File(
        _paths.join(workspaceRoot, document.relativePath),
      ).stat();
      summaries.add(<String, Object?>{
        'documentId': document.documentId,
        'workspaceId': workspaceId,
        'relativePath': document.relativePath,
        'sha256': document.sourceSha256,
        'sourceSha256': document.sourceSha256,
        'modifiedAt': stat.modified.toUtc().toIso8601String(),
        ..._documentSummary(document),
      });
    }
    summaries.sort(
      (left, right) => (left['documentId']! as String).compareTo(
        right['documentId']! as String,
      ),
    );
    return summaries;
  }

  Future<({List<Map<String, Object?>> documents, int totalCount})> list({
    String? kind,
    String? relativePath,
    int offset = 0,
    int limit = 100,
  }) async {
    await _ensureLoaded();
    final matches =
        _byId.values
            .where(
              (document) =>
                  _matchesKind(document, kind) &&
                  (relativePath == null ||
                      document.relativePath == relativePath),
            )
            .toList(growable: false)
          ..sort((left, right) => left.documentId.compareTo(right.documentId));
    if (offset > matches.length) {
      throw const FormatException('Document page offset is stale.');
    }
    final end = (offset + limit).clamp(0, matches.length);
    final documents = <Map<String, Object?>>[];
    for (final document in matches.sublist(offset, end)) {
      final stat = await File(
        _paths.join(workspaceRoot, document.relativePath),
      ).stat();
      documents.add(<String, Object?>{
        'documentId': document.documentId,
        'workspaceId': workspaceId,
        'relativePath': document.relativePath,
        'sha256': document.sourceSha256,
        'sourceSha256': document.sourceSha256,
        'modifiedAt': stat.modified.toUtc().toIso8601String(),
        ..._documentSummary(document),
      });
    }
    return (documents: documents, totalCount: matches.length);
  }

  Future<List<String>> resolvePaths(Iterable<String> documentIds) async {
    final documents = await resolveDocuments(documentIds);
    return documents.map((document) => document.absolutePath).toList();
  }

  Future<List<CockpitResolvedWorkerDocument>> resolveDocuments(
    Iterable<String> documentIds,
  ) async {
    await _ensureLoaded();
    final unique = <String>{};
    final resolved = <CockpitResolvedWorkerDocument>[];
    for (final documentId in documentIds) {
      workerId(documentId, r'$.documentIds[]');
      if (!unique.add(documentId)) {
        throw FormatException('Duplicate document id $documentId.');
      }
      final document = _byId[documentId];
      if (document == null) {
        throw FormatException('Unknown document id $documentId.');
      }
      final current = await _readConfinedDocument(
        document.relativePath,
        expectedSha256: document.sourceSha256,
      );
      if (current == null) {
        throw FormatException('Indexed document $documentId is stale.');
      }
      resolved.add(
        CockpitResolvedWorkerDocument(
          documentId: documentId,
          absolutePath: current.absolutePath,
          sourceSha256: current.sourceSha256,
        ),
      );
    }
    return resolved;
  }

  @override
  Future<CockpitCompiledTestCase> resolve(
    CockpitIndexedCaseReference reference,
  ) async {
    await _ensureLoaded();
    final document = _byId[reference.documentId];
    final compiled = document?.compiled;
    if (document == null ||
        compiled is! CockpitCompiledTestCase ||
        document.sourceSha256 != reference.documentSha256 ||
        compiled.testCase.id != reference.caseId) {
      throw const FormatException(
        'Indexed case reference is stale or invalid.',
      );
    }
    final current = await _readConfinedDocument(
      document.relativePath,
      expectedSha256: document.sourceSha256,
    );
    if (current == null) {
      throw const FormatException('Indexed case source is stale or invalid.');
    }
    return compiled;
  }

  Future<CockpitCompiledTestSuite> resolveSuite(
    CockpitIndexedSuiteReference reference,
  ) async {
    await _ensureLoaded();
    final document = _byId[reference.documentId];
    final compiled = document?.compiled;
    if (document == null ||
        compiled is! CockpitCompiledTestSuite ||
        document.sourceSha256 != reference.documentSha256 ||
        compiled.suite.id != reference.suiteId) {
      throw const FormatException(
        'Indexed suite reference is stale or invalid.',
      );
    }
    final current = await _readConfinedDocument(
      document.relativePath,
      expectedSha256: document.sourceSha256,
    );
    if (current == null) {
      throw const FormatException('Indexed suite source is stale or invalid.');
    }
    return compiled;
  }

  @override
  Future<CockpitCompiledTestCase> resolveFile(
    CockpitTestSuiteFileCaseSource source,
  ) async {
    await _ensureLoaded();
    final document = _byId.values
        .where((candidate) => candidate.relativePath == source.relativePath)
        .singleOrNull;
    final compiled = document?.compiled;
    if (document == null ||
        compiled is! CockpitCompiledTestCase ||
        compiled.testCase.id != source.caseId) {
      throw const FormatException(
        'Suite file case source is stale or invalid.',
      );
    }
    final current = await _readConfinedDocument(
      document.relativePath,
      expectedSha256: document.sourceSha256,
    );
    if (current == null) {
      throw const FormatException(
        'Suite file case source is stale or invalid.',
      );
    }
    return compiled;
  }

  Future<_ResolvedDocumentFile?> _readConfinedDocument(
    String relativePath, {
    String? expectedSha256,
  }) async {
    if (!_isConfinedRelative(relativePath)) {
      throw const FormatException('Document path is not confined.');
    }
    final root = p.normalize(
      await Directory(workspaceRoot).resolveSymbolicLinks(),
    );
    if (!p.equals(root, p.normalize(workspaceRoot))) {
      throw const FormatException('Workspace root is no longer canonical.');
    }
    final candidate = p.normalize(p.join(root, relativePath));
    if (!p.isWithin(root, candidate) ||
        await FileSystemEntity.type(candidate, followLinks: false) !=
            FileSystemEntityType.file) {
      throw const FormatException(
        'Document source is no longer a regular file.',
      );
    }
    final canonical = p.normalize(await File(candidate).resolveSymbolicLinks());
    if (!p.equals(canonical, candidate) || !p.isWithin(root, canonical)) {
      throw const FormatException('Document source escapes the workspace.');
    }
    RandomAccessFile? handle;
    try {
      handle = await File(canonical).open(mode: FileMode.read);
      final length = await handle.length();
      if (length > maximumIndexedFileBytes) return null;
      final bytes = await handle.read(length);
      if (bytes.length != length) {
        throw const FormatException('Document source changed while reading.');
      }
      final afterType = await FileSystemEntity.type(
        candidate,
        followLinks: false,
      );
      final afterCanonical = afterType == FileSystemEntityType.file
          ? p.normalize(await File(candidate).resolveSymbolicLinks())
          : null;
      if (afterCanonical == null || !p.equals(afterCanonical, canonical)) {
        throw const FormatException('Document source changed while reading.');
      }
      final digest = sha256.convert(bytes).toString();
      if (expectedSha256 != null && digest != expectedSha256) return null;
      return _ResolvedDocumentFile(canonical, bytes, digest);
    } finally {
      await handle?.close();
    }
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final persisted = await _loadPersistedMetadata();
    final loaded = <String, _IndexedDocument>{};
    for (final document in persisted.values) {
      final current = await _readConfinedDocument(
        document.relativePath,
        expectedSha256: document.sourceSha256,
      );
      CockpitCompiledTestDocument? compiled;
      if (current != null &&
          document.kind != CockpitIndexedDocumentKind.source) {
        try {
          final candidate = const CockpitTestDocumentCompiler()
              .compile(
                utf8.decode(current.bytes, allowMalformed: false),
                format: _documentFormat(document.relativePath),
              )
              .compiled;
          if (candidate != null &&
              _documentKind(candidate.document) == document.kind &&
              candidate.document.id == document.authoredId) {
            compiled = candidate;
          }
        } on FormatException {
          compiled = null;
        }
      }
      loaded[document.documentId] = _IndexedDocument(
        documentId: document.documentId,
        relativePath: document.relativePath,
        sourceSha256: document.sourceSha256,
        compiled: compiled,
      );
    }
    _byId
      ..clear()
      ..addAll(loaded);
    _loaded = true;
  }

  Future<Map<String, _PersistedDocument>> _loadPersistedMetadata() async {
    await _prepareStorageDirectory();
    final file = File(_indexPath);
    if (await FileSystemEntity.type(file.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return const <String, _PersistedDocument>{};
    }
    await cockpitValidateCanonicalRegularFile(
      file.path,
      diagnostic: 'Worker document index is not canonical and regular.',
    );
    final decoded = jsonDecode(await _readBoundedIndex(file));
    final json = workerObject(decoded, r'$');
    workerKeys(
      json,
      const <String>{'schemaVersion', 'documents'},
      r'$',
      required: const <String>{'schemaVersion', 'documents'},
    );
    if (json['schemaVersion'] != 'cockpit.worker.documents/v4') {
      throw const FormatException('Unsupported worker document index.');
    }
    final raw = workerList(
      json['documents'],
      r'$.documents',
      maximum: maximumFiles,
    );
    final result = <String, _PersistedDocument>{};
    final documentIds = <String>{};
    for (var index = 0; index < raw.length; index += 1) {
      final document = _persisted(raw[index], index);
      if (!documentIds.add(document.documentId) ||
          result.putIfAbsent(document.relativePath, () => document) !=
              document) {
        throw const FormatException(
          'Worker document index contains duplicate capabilities.',
        );
      }
    }
    return result;
  }

  _PersistedDocument _persisted(Object? value, int index) {
    final path = '\$.documents[$index]';
    final json = workerObject(value, path);
    workerKeys(
      json,
      const <String>{
        'documentId',
        'relativePath',
        'sourceSha256',
        'kind',
        'authoredId',
      },
      path,
      required: const <String>{
        'documentId',
        'relativePath',
        'sourceSha256',
        'kind',
      },
    );
    final relativePath = workerString(
      json['relativePath'],
      '$path.relativePath',
      maximum: 32768,
    );
    if (!_isConfinedRelative(relativePath)) {
      throw const FormatException('Persisted document path is not confined.');
    }
    final sourceSha256 = workerString(
      json['sourceSha256'],
      '$path.sourceSha256',
      minimum: 64,
      maximum: 64,
    );
    if (!_isLowercaseHex(sourceSha256, length: 64)) {
      throw FormatException('Invalid document hash at $path.sourceSha256.');
    }
    return _PersistedDocument(
      documentId: workerId(json['documentId'], '$path.documentId'),
      relativePath: relativePath,
      sourceSha256: sourceSha256,
      kind: _workerDocumentKind(json['kind'], '$path.kind'),
      authoredId: json['authoredId'] == null
          ? null
          : workerId(json['authoredId'], '$path.authoredId'),
    );
  }

  Future<void> _persist() async {
    await _prepareStorageDirectory();
    final contents = <String, Object?>{
      'schemaVersion': 'cockpit.worker.documents/v4',
      'documents': <Map<String, Object?>>[
        for (final document in _byId.values)
          <String, Object?>{
            'documentId': document.documentId,
            'relativePath': document.relativePath,
            'sourceSha256': document.sourceSha256,
            'kind': document.compiled == null
                ? 'source'
                : _documentKindWire(_documentKind(document.compiled!.document)),
            if (document.compiled != null)
              'authoredId': document.compiled!.document.id,
          },
      ],
    };
    await _atomicFile.write(
      _indexPath,
      contents,
      maximumBytes: maximumIndexBytes,
    );
  }

  Future<void> _prepareStorageDirectory() async {
    final normalizedStateRoot = _paths.normalize(_paths.absolute(stateRoot));
    if (!_paths.isAbsolute(stateRoot) || normalizedStateRoot != stateRoot) {
      throw const FormatException(
        'Worker document state root must be absolute and normalized.',
      );
    }
    final stateDirectory = Directory(stateRoot);
    final stateCanonical = _paths.normalize(
      await stateDirectory.resolveSymbolicLinks(),
    );
    if (!_paths.equals(stateCanonical, stateRoot)) {
      throw const FormatException(
        'Worker document state root is no longer canonical.',
      );
    }
    final directory = Directory(_paths.dirname(_indexPath));
    final originalType = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    final created = originalType == FileSystemEntityType.notFound;
    if (created) {
      await directory.create();
    } else if (originalType != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Worker document storage entry is not a directory.',
        directory.path,
      );
    }
    final canonical = _paths.normalize(await directory.resolveSymbolicLinks());
    if (!_paths.equals(canonical, directory.path) ||
        !_paths.isWithin(stateCanonical, canonical)) {
      throw FileSystemException(
        'Worker document storage directory is not canonical and confined.',
        directory.path,
      );
    }
    await _permissionHardener.hardenDirectory(directory);
    if (created) await _directorySyncer.sync(stateCanonical);
    await _scanStorageDirectory(directory);
  }

  Future<void> _scanStorageDirectory(Directory directory) async {
    await for (final entity in directory.list(followLinks: false)) {
      final name = _paths.basename(entity.path);
      if (name == 'index.json') {
        await cockpitValidateCanonicalRegularFile(
          entity.path,
          diagnostic: 'Worker document index is not canonical and regular.',
        );
        continue;
      }
      if (cockpitAtomicJsonTemporaryTargetName(name) == 'index.json') {
        await cockpitDeleteAtomicJsonTemporary(
          path: entity.path,
          directorySyncer: _directorySyncer,
        );
        continue;
      }
      throw FileSystemException(
        'Worker document storage contains an unexpected entry.',
        entity.path,
      );
    }
  }

  Future<String> _readBoundedIndex(File file) async {
    RandomAccessFile? handle;
    try {
      handle = await file.open(mode: FileMode.read);
      final length = await handle.length();
      if (length > maximumIndexBytes) {
        throw CockpitStorageException(
          code: 'storageTooLarge',
          path: file.path,
          diagnostic: 'Worker document index exceeds $maximumIndexBytes bytes.',
        );
      }
      final bytes = await handle.read(length);
      if (bytes.length != length) {
        throw const FormatException(
          'Worker document index changed while reading.',
        );
      }
      final type = await FileSystemEntity.type(file.path, followLinks: false);
      final canonical = type == FileSystemEntityType.file
          ? _paths.normalize(await file.resolveSymbolicLinks())
          : null;
      if (canonical == null || !_paths.equals(canonical, file.path)) {
        throw const FormatException(
          'Worker document index changed while reading.',
        );
      }
      return utf8.decode(bytes, allowMalformed: false);
    } finally {
      await handle?.close();
    }
  }

  bool _isConfinedRelative(String relativePath) =>
      !_paths.isAbsolute(relativePath) &&
      relativePath != '..' &&
      !relativePath.startsWith('../') &&
      !relativePath.startsWith('..${_paths.separator}');

  String get _indexPath => _paths.join(stateRoot, 'documents', 'index.json');

  String _newDocumentId() => 'dc-${_tokenGenerator.nextResourceIdToken()}';
}

bool _matchesKind(_IndexedDocument document, String? kind) {
  if (kind == null) return true;
  if (kind == 'authored') return document.compiled != null;
  return _documentSummary(document)['kind'] == kind;
}

Map<String, Object?> _documentSummary(_IndexedDocument indexed) {
  final compiled = indexed.compiled;
  if (compiled == null) {
    return const <String, Object?>{
      'kind': 'source',
      'cases': <Map<String, Object?>>[],
    };
  }
  final document = compiled.document;
  final cases = switch (compiled) {
    CockpitCompiledTestCase(:final testCase) => <Map<String, Object?>>[
      <String, Object?>{
        'caseId': testCase.id,
        if (testCase.name != null) 'title': testCase.name,
      },
    ],
    CockpitCompiledTestSuite(:final suite) => <Map<String, Object?>>[
      for (final entry in suite.cases)
        <String, Object?>{
          'caseId': entry.source.caseId,
          if (entry.source case CockpitTestSuiteInlineCaseSource(
            :final testCase,
          ) when testCase.name != null)
            'title': testCase.name,
        },
    ],
    CockpitCompiledTestProject() => const <Map<String, Object?>>[],
  };
  return <String, Object?>{
    'kind': _documentKindWire(_documentKind(document)),
    'authoredId': document.id,
    if (document.name != null) 'title': document.name,
    'cases': cases,
  };
}

CockpitIndexedDocumentKind _documentKind(CockpitTestDocument document) =>
    switch (document) {
      CockpitTestCase() => CockpitIndexedDocumentKind.testCase,
      CockpitTestSuite() => CockpitIndexedDocumentKind.suite,
      CockpitTestProject() => CockpitIndexedDocumentKind.project,
      _ => throw StateError('Unsupported indexed document ${document.kind}.'),
    };

CockpitDocumentFormat _documentFormat(String path) =>
    switch (p.extension(path).toLowerCase()) {
      '.lon' => CockpitDocumentFormat.lon,
      '.json' => CockpitDocumentFormat.json,
      '.yaml' || '.yml' => CockpitDocumentFormat.yaml,
      _ => throw const FormatException('Unsupported authored document format.'),
    };

String _documentKindWire(CockpitIndexedDocumentKind kind) =>
    kind == CockpitIndexedDocumentKind.testCase ? 'case' : kind.name;

CockpitIndexedDocumentKind _workerDocumentKind(Object? value, String path) {
  final name = workerString(value, path, maximum: 16);
  return switch (name) {
    'source' => CockpitIndexedDocumentKind.source,
    'case' => CockpitIndexedDocumentKind.testCase,
    'suite' => CockpitIndexedDocumentKind.suite,
    'project' => CockpitIndexedDocumentKind.project,
    _ => throw FormatException('Invalid indexed document kind at $path.'),
  };
}

bool _isLowercaseHex(String value, {required int length}) {
  if (value.length != length) return false;
  for (final codeUnit in value.codeUnits) {
    if ((codeUnit < 48 || codeUnit > 57) && (codeUnit < 97 || codeUnit > 102)) {
      return false;
    }
  }
  return true;
}

final class CockpitResolvedWorkerDocument {
  const CockpitResolvedWorkerDocument({
    required this.documentId,
    required this.absolutePath,
    required this.sourceSha256,
  });

  final String documentId;
  final String absolutePath;
  final String sourceSha256;
}

final class _ResolvedDocumentFile {
  const _ResolvedDocumentFile(this.absolutePath, this.bytes, this.sourceSha256);

  final String absolutePath;
  final List<int> bytes;
  final String sourceSha256;
}

final class _IndexedDocument {
  const _IndexedDocument({
    required this.documentId,
    required this.relativePath,
    required this.sourceSha256,
    required this.compiled,
  });

  final String documentId;
  final String relativePath;
  final String sourceSha256;
  final CockpitCompiledTestDocument? compiled;
}

final class _PersistedDocument {
  const _PersistedDocument({
    required this.documentId,
    required this.relativePath,
    required this.sourceSha256,
    required this.kind,
    required this.authoredId,
  }) : assert(
         (kind == CockpitIndexedDocumentKind.source) == (authoredId == null),
       );

  final String documentId;
  final String relativePath;
  final String sourceSha256;
  final CockpitIndexedDocumentKind kind;
  final String? authoredId;
}
