import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../foundation/cockpit_ids.dart';
import '../foundation/cockpit_locked_json_store.dart';
import '../foundation/cockpit_permissions.dart';
import 'cockpit_worker_value_reader.dart';

final class CockpitWorkerOperationAdmission {
  const CockpitWorkerOperationAdmission({
    required this.operationId,
    required this.execute,
    this.replay,
  });

  final String operationId;
  final bool execute;
  final CockpitOperationResult? replay;
}

abstract interface class CockpitWorkerOperationJournal {
  Future<void> recover({required DateTime now});

  Future<CockpitWorkerOperationAdmission> admit({
    required CockpitOperationInvocation invocation,
    required DateTime submittedAt,
  });

  Future<void> markRunning({
    required String idempotencyKey,
    required DateTime startedAt,
  });

  Future<void> complete({
    required String idempotencyKey,
    required CockpitOperationResult result,
  });
}

enum CockpitWorkerOperationRecoveryPolicy { interrupt, retryPrepared }

final class CockpitInMemoryWorkerOperationJournal
    implements CockpitWorkerOperationJournal {
  CockpitInMemoryWorkerOperationJournal({
    CockpitTokenGenerator? tokenGenerator,
    Map<String, CockpitWorkerOperationRecoveryPolicy> recoveryPolicies =
        const <String, CockpitWorkerOperationRecoveryPolicy>{},
  }) : _tokenGenerator = tokenGenerator ?? CockpitSecureTokenGenerator(),
       _recoveryPolicies = Map.unmodifiable(recoveryPolicies);

  final CockpitTokenGenerator _tokenGenerator;
  final Map<String, CockpitWorkerOperationRecoveryPolicy> _recoveryPolicies;

  final Map<String, _OperationRecord> _records = <String, _OperationRecord>{};

  @override
  Future<void> recover({required DateTime now}) async {
    for (final entry in _records.entries.toList(growable: false)) {
      if (entry.value.state == _OperationState.running) {
        _records[entry.key] =
            _recoveryPolicy(entry.value.kind) ==
                CockpitWorkerOperationRecoveryPolicy.retryPrepared
            ? entry.value.preparedForRetry()
            : entry.value.completed(
                _interruptedResult(entry.value, now.toUtc()),
              );
      }
    }
  }

  CockpitWorkerOperationRecoveryPolicy _recoveryPolicy(String kind) =>
      _recoveryPolicies[kind] ?? CockpitWorkerOperationRecoveryPolicy.interrupt;

  @override
  Future<CockpitWorkerOperationAdmission> admit({
    required CockpitOperationInvocation invocation,
    required DateTime submittedAt,
  }) async {
    final key = invocation.idempotencyKey?.value;
    if (key == null) throw const FormatException('Idempotency is required.');
    final fingerprint = _fingerprint(invocation);
    final existing = _records[key];
    if (existing != null) {
      if (existing.fingerprint != fingerprint) {
        throw const FormatException('Idempotency key conflicts.');
      }
      if (existing.state == _OperationState.running &&
          existing.result == null) {
        throw StateError(
          'Running operation journal must be recovered before admission.',
        );
      }
      return CockpitWorkerOperationAdmission(
        operationId: existing.operationId,
        execute: existing.result == null,
        replay: existing.result,
      );
    }
    final operationId = _tokenGenerator.nextResourceId('o');
    _records[key] = _OperationRecord(
      idempotencyKey: key,
      fingerprint: fingerprint,
      operationId: operationId,
      kind: invocation.kind,
      workspaceId: invocation.workspaceId!,
      submittedAt: submittedAt.toUtc(),
      state: _OperationState.prepared,
    );
    return CockpitWorkerOperationAdmission(
      operationId: operationId,
      execute: true,
    );
  }

  @override
  Future<void> markRunning({
    required String idempotencyKey,
    required DateTime startedAt,
  }) async {
    final record = _records[idempotencyKey];
    if (record == null || record.state != _OperationState.prepared) {
      throw StateError('Worker operation is not prepared.');
    }
    _records[idempotencyKey] = record.running(startedAt.toUtc());
  }

  @override
  Future<void> complete({
    required String idempotencyKey,
    required CockpitOperationResult result,
  }) async {
    final record = _records[idempotencyKey];
    if (record == null || record.operationId != result.operationId) {
      throw StateError('Worker operation completion is inconsistent.');
    }
    _records[idempotencyKey] = record.completed(result);
  }
}

final class CockpitFileWorkerOperationJournal
    implements CockpitWorkerOperationJournal {
  CockpitFileWorkerOperationJournal({
    required String path,
    required CockpitPermissionHardener permissionHardener,
    required CockpitDirectorySyncer directorySyncer,
    CockpitTokenGenerator? tokenGenerator,
    Map<String, CockpitWorkerOperationRecoveryPolicy> recoveryPolicies =
        const <String, CockpitWorkerOperationRecoveryPolicy>{},
  }) : _root = p.normalize(p.absolute(path)),
       _permissionHardener = permissionHardener,
       _directorySyncer = directorySyncer,
       _tokenGenerator = tokenGenerator ?? CockpitSecureTokenGenerator(),
       _recoveryPolicies = Map.unmodifiable(recoveryPolicies);

  static const String schemaVersion = 'cockpit.worker.operation/v3';
  static const int maximumRecordBytes = 2 * 1024 * 1024;

  final String _root;
  final CockpitPermissionHardener _permissionHardener;
  final CockpitDirectorySyncer _directorySyncer;
  final CockpitTokenGenerator _tokenGenerator;
  final Map<String, CockpitWorkerOperationRecoveryPolicy> _recoveryPolicies;

  String get _activeRoot => p.join(_root, 'active');

  CockpitWorkerOperationRecoveryPolicy _recoveryPolicy(String kind) =>
      _recoveryPolicies[kind] ?? CockpitWorkerOperationRecoveryPolicy.interrupt;

  @override
  Future<void> recover({required DateTime now}) async {
    await _prepareRoot();
    await _prepareActiveRoot();
    await _scanActiveDirectory();
    await _recoverActiveRecords(now.toUtc());
  }

  @override
  Future<CockpitWorkerOperationAdmission> admit({
    required CockpitOperationInvocation invocation,
    required DateTime submittedAt,
  }) async {
    final key = invocation.idempotencyKey?.value;
    if (key == null) {
      throw const FormatException(
        'Durable worker admission requires an idempotency key.',
      );
    }
    final fingerprint = _fingerprint(invocation);
    await _ensureActiveMarker(key);
    final store = await _storeForKey(key);
    final admission = await store.transact<CockpitWorkerOperationAdmission>((
      raw,
    ) {
      final existing = _decodeOptionalRecordState(raw);
      if (existing != null) {
        if (existing.idempotencyKey != key) {
          throw const FormatException(
            'Worker operation journal record identity mismatch.',
          );
        }
        if (existing.fingerprint != fingerprint) {
          throw const FormatException(
            'Worker idempotency key conflicts with another mutation.',
          );
        }
        if (existing.result case final result?) {
          return CockpitLockedJsonUpdate.readOnly(
            raw,
            CockpitWorkerOperationAdmission(
              operationId: existing.operationId,
              execute: false,
              replay: result,
            ),
          );
        }
        if (existing.state == _OperationState.running) {
          throw StateError(
            'Running operation journal must be recovered before admission.',
          );
        }
        return CockpitLockedJsonUpdate.readOnly(
          raw,
          CockpitWorkerOperationAdmission(
            operationId: existing.operationId,
            execute: true,
          ),
        );
      }
      final record = _OperationRecord(
        idempotencyKey: key,
        fingerprint: fingerprint,
        operationId: _tokenGenerator.nextResourceId('o'),
        kind: invocation.kind,
        workspaceId: invocation.workspaceId!,
        submittedAt: submittedAt.toUtc(),
        state: _OperationState.prepared,
      );
      return CockpitLockedJsonUpdate.write(
        _encodeRecordState(record),
        CockpitWorkerOperationAdmission(
          operationId: record.operationId,
          execute: true,
        ),
      );
    });
    if (!admission.execute) await _removeActiveMarker(key);
    return admission;
  }

  @override
  Future<void> markRunning({
    required String idempotencyKey,
    required DateTime startedAt,
  }) async {
    await _ensureActiveMarker(idempotencyKey);
    final store = await _storeForKey(idempotencyKey);
    await store.transact<void>((raw) {
      final record = _decodeOptionalRecordState(raw);
      if (record == null ||
          record.idempotencyKey != idempotencyKey ||
          record.state != _OperationState.prepared) {
        throw StateError('Worker operation is not prepared.');
      }
      return CockpitLockedJsonUpdate.write(
        _encodeRecordState(record.running(startedAt.toUtc())),
        null,
      );
    });
  }

  @override
  Future<void> complete({
    required String idempotencyKey,
    required CockpitOperationResult result,
  }) async {
    final store = await _storeForKey(idempotencyKey);
    await store.transact<void>((raw) {
      final record = _decodeOptionalRecordState(raw);
      if (record == null ||
          record.idempotencyKey != idempotencyKey ||
          record.operationId != result.operationId) {
        throw StateError('Worker operation completion is inconsistent.');
      }
      if (record.result case final existing?) {
        if (_canonicalJson(existing.toJson()) !=
            _canonicalJson(result.toJson())) {
          throw StateError('Worker operation result is immutable.');
        }
        return CockpitLockedJsonUpdate.readOnly(raw, null);
      }
      return CockpitLockedJsonUpdate.write(
        _encodeRecordState(record.completed(result)),
        null,
      );
    });
    await _removeActiveMarker(idempotencyKey);
  }

  Future<CockpitLockedJsonStore<Map<String, Object?>>> _storeForKey(
    String idempotencyKey,
  ) async {
    final hash = _recordHash(idempotencyKey);
    final directory = await _prepareRecordDirectory(hash);
    await _scanRecordDirectory(directory.path, expectedHash: hash);
    final path = p.join(directory.path, 'record.json');
    await _validateStoreFiles(path);
    return _storeAt(path);
  }

  CockpitLockedJsonStore<Map<String, Object?>> _storeAt(String path) =>
      CockpitLockedJsonStore<Map<String, Object?>>(
        path: path,
        codec: const _OperationJournalRecordCodec(),
        createInitial: _emptyRecordState,
        permissionHardener: _permissionHardener,
        directorySyncer: _directorySyncer,
        maximumBytes: maximumRecordBytes,
      );

  Future<void> _recoverActiveRecords(DateTime now) async {
    final active = await _readActiveManifest();
    final retained = <String, String>{};
    for (final entry in active.entries) {
      final hash = entry.key;
      final key = entry.value;
      final recordDirectory = _recordDirectoryForHash(hash);
      final directoryType = await FileSystemEntity.type(
        recordDirectory,
        followLinks: false,
      );
      if (directoryType == FileSystemEntityType.notFound) {
        continue;
      }
      if (directoryType != FileSystemEntityType.directory) {
        throw FileSystemException(
          'Worker operation journal active record directory is invalid.',
          recordDirectory,
        );
      }
      await _validateRecordDirectory(recordDirectory, expectedHash: hash);
      final hasRecordTemporary = await _scanRecordDirectory(
        recordDirectory,
        expectedHash: hash,
      );
      final recordPath = p.join(recordDirectory, 'record.json');
      final recordType = await FileSystemEntity.type(
        recordPath,
        followLinks: false,
      );
      if (recordType == FileSystemEntityType.notFound && !hasRecordTemporary) {
        continue;
      }
      if (recordType != FileSystemEntityType.file &&
          recordType != FileSystemEntityType.notFound) {
        throw FileSystemException(
          'Worker operation journal active record is invalid.',
          recordPath,
        );
      }
      if (recordType == FileSystemEntityType.file) {
        await _validateStoreFiles(recordPath);
      }
      var keepActive = false;
      await _storeAt(recordPath).transact<void>((raw) {
        final record = _decodeRecordState(raw);
        if (record.idempotencyKey != key || _recordHash(key) != hash) {
          throw const FormatException(
            'Worker operation journal active marker identity mismatch.',
          );
        }
        if (record.state == _OperationState.prepared) {
          keepActive = true;
          return CockpitLockedJsonUpdate.readOnly(raw, null);
        }
        if (record.state == _OperationState.completed) {
          return CockpitLockedJsonUpdate.readOnly(raw, null);
        }
        if (_recoveryPolicy(record.kind) ==
            CockpitWorkerOperationRecoveryPolicy.retryPrepared) {
          keepActive = true;
          return CockpitLockedJsonUpdate.write(
            _encodeRecordState(record.preparedForRetry()),
            null,
          );
        }
        return CockpitLockedJsonUpdate.write(
          _encodeRecordState(record.completed(_interruptedResult(record, now))),
          null,
        );
      });
      if (keepActive) retained[hash] = key;
    }
    if (_canonicalJson(active) != _canonicalJson(retained)) {
      await _writeActiveManifest(retained);
    }
  }

  Future<void> _ensureActiveMarker(String idempotencyKey) async {
    workerId(idempotencyKey, r'$.idempotencyKey');
    await _prepareActiveRoot();
    final hash = _recordHash(idempotencyKey);
    await _activeManifestStore().transact<void>((raw) {
      final active = _decodeActiveManifest(raw);
      final existing = active[hash];
      if (existing != null && existing != idempotencyKey) {
        throw const FormatException(
          'Worker operation active manifest identity mismatch.',
        );
      }
      if (existing == idempotencyKey) {
        return CockpitLockedJsonUpdate.readOnly(raw, null);
      }
      active[hash] = idempotencyKey;
      return CockpitLockedJsonUpdate.write(_encodeActiveManifest(active), null);
    });
  }

  Future<void> _removeActiveMarker(String idempotencyKey) async {
    final hash = _recordHash(idempotencyKey);
    await _activeManifestStore().transact<void>((raw) {
      final active = _decodeActiveManifest(raw);
      if (active[hash] != idempotencyKey) {
        return CockpitLockedJsonUpdate.readOnly(raw, null);
      }
      active.remove(hash);
      return CockpitLockedJsonUpdate.write(_encodeActiveManifest(active), null);
    });
  }

  CockpitLockedJsonStore<Map<String, Object?>> _activeManifestStore() =>
      CockpitLockedJsonStore<Map<String, Object?>>(
        path: p.join(_activeRoot, 'manifest.json'),
        codec: const _OperationActiveManifestCodec(),
        createInitial: () => _encodeActiveManifest(const <String, String>{}),
        permissionHardener: _permissionHardener,
        directorySyncer: _directorySyncer,
        maximumBytes: 2 * 1024 * 1024,
      );

  Future<Map<String, String>> _readActiveManifest() async =>
      _decodeActiveManifest(await _activeManifestStore().read());

  Future<void> _writeActiveManifest(Map<String, String> active) async {
    await _activeManifestStore().transact<void>(
      (_) => CockpitLockedJsonUpdate.write(_encodeActiveManifest(active), null),
    );
  }

  Future<bool> _scanRecordDirectory(
    String directoryPath, {
    required String expectedHash,
  }) async {
    await _validateRecordDirectory(directoryPath, expectedHash: expectedHash);
    var hasRecordTemporary = false;
    await for (final entity in Directory(
      directoryPath,
    ).list(followLinks: false)) {
      final name = p.basename(entity.path);
      final temporaryTarget = cockpitAtomicJsonTemporaryTargetName(name);
      if (temporaryTarget != null) {
        if (temporaryTarget != 'record.json') {
          throw FileSystemException(
            'Worker operation journal contains an unknown temporary file.',
            entity.path,
          );
        }
        hasRecordTemporary = true;
        continue;
      }
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type != FileSystemEntityType.file) {
        throw FileSystemException(
          'Worker operation journal shard contains an invalid entry.',
          entity.path,
        );
      }
      await cockpitValidateCanonicalRegularFile(
        entity.path,
        diagnostic: 'Worker operation journal file is not canonical.',
      );
      if (name.endsWith('.json.lock')) {
        if (name != 'record.json.lock') {
          throw FileSystemException(
            'Worker operation journal contains an unknown lock file.',
            entity.path,
          );
        }
      } else if (name != 'record.json') {
        throw FileSystemException(
          'Worker operation journal contains an unknown file.',
          entity.path,
        );
      } else {
        await _validateStoreFiles(entity.path);
      }
    }
    return hasRecordTemporary;
  }

  Future<Directory> _prepareRecordDirectory(String hash) async {
    await _prepareRoot();
    final records = await _prepareOwnedDirectory(
      p.join(_root, 'records'),
      parentPath: _root,
    );
    final shard = await _prepareOwnedDirectory(
      p.join(records.path, hash.substring(0, 2)),
      parentPath: records.path,
    );
    final directory = await _prepareOwnedDirectory(
      p.join(shard.path, hash),
      parentPath: shard.path,
    );
    await _validateRecordDirectory(directory.path, expectedHash: hash);
    return directory;
  }

  Future<Directory> _prepareOwnedDirectory(
    String path, {
    required String parentPath,
  }) async {
    final directory = Directory(path);
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      await directory.create();
      await _permissionHardener.hardenDirectory(directory);
      await _directorySyncer.sync(parentPath);
      return directory;
    }
    if (type != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Worker operation journal record path is not a directory.',
        path,
      );
    }
    await _validateCanonicalDirectory(path);
    await _permissionHardener.hardenDirectory(directory);
    return directory;
  }

  String _recordDirectoryForHash(String hash) =>
      p.join(_root, 'records', hash.substring(0, 2), hash);

  Future<void> _validateRecordDirectory(
    String path, {
    required String expectedHash,
  }) async {
    if (!_isLowercaseHex(expectedHash, length: 64) ||
        !p.equals(path, _recordDirectoryForHash(expectedHash))) {
      throw FileSystemException(
        'Worker operation journal record directory identity is invalid.',
        path,
      );
    }
    await _validateCanonicalDirectory(path);
  }

  Future<void> _scanActiveDirectory() async {
    await for (final entity in Directory(
      _activeRoot,
    ).list(followLinks: false)) {
      final name = p.basename(entity.path);
      final temporaryTarget = cockpitAtomicJsonTemporaryTargetName(name);
      if (temporaryTarget != null) {
        if (temporaryTarget != 'manifest.json') {
          throw FileSystemException(
            'Worker operation active set contains an unknown temporary file.',
            entity.path,
          );
        }
        continue;
      }
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type != FileSystemEntityType.file) {
        throw FileSystemException(
          'Worker operation active set contains an invalid entry.',
          entity.path,
        );
      }
      await cockpitValidateCanonicalRegularFile(
        entity.path,
        diagnostic: 'Worker operation active marker is not canonical.',
      );
      if (name != 'manifest.json' && name != 'manifest.json.lock') {
        throw FileSystemException(
          'Worker operation active set contains an unknown file.',
          entity.path,
        );
      }
    }
  }

  Future<void> _prepareActiveRoot() async {
    await _prepareRoot();
    final directory = Directory(_activeRoot);
    final type = await FileSystemEntity.type(_activeRoot, followLinks: false);
    var created = false;
    if (type == FileSystemEntityType.notFound) {
      if (!await Directory(_root).list(followLinks: false).isEmpty) {
        throw FileSystemException(
          'Worker operation active manifest directory is missing.',
          _activeRoot,
        );
      }
      await directory.create();
      await _permissionHardener.hardenDirectory(directory);
      await _directorySyncer.sync(_root);
      created = true;
    } else if (type != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Worker operation active set is not a directory.',
        _activeRoot,
      );
    } else {
      await _validateCanonicalDirectory(_activeRoot);
      await _permissionHardener.hardenDirectory(directory);
    }
    final manifestPath = p.join(_activeRoot, 'manifest.json');
    final manifestType = await FileSystemEntity.type(
      manifestPath,
      followLinks: false,
    );
    if (manifestType == FileSystemEntityType.notFound) {
      if (!created && !await _canInitializeMissingManifest()) {
        throw FileSystemException(
          'Worker operation active manifest is missing.',
          manifestPath,
        );
      }
      await _activeManifestStore().transact<void>(
        (raw) => CockpitLockedJsonUpdate.write(raw, null),
      );
    } else {
      await cockpitValidateCanonicalRegularFile(
        manifestPath,
        diagnostic: 'Worker operation active manifest is not canonical.',
      );
    }
  }

  Future<bool> _canInitializeMissingManifest() async {
    await _scanActiveDirectory();
    final recordsPath = p.join(_root, 'records');
    final recordsType = await FileSystemEntity.type(
      recordsPath,
      followLinks: false,
    );
    if (recordsType == FileSystemEntityType.notFound) return true;
    if (recordsType != FileSystemEntityType.directory) return false;
    await _validateCanonicalDirectory(recordsPath);
    return Directory(
      recordsPath,
    ).list(recursive: true, followLinks: false).isEmpty;
  }

  Future<void> _validateCanonicalDirectory(String path) async {
    final canonical = p.normalize(await Directory(path).resolveSymbolicLinks());
    if (!p.equals(canonical, p.normalize(path)) ||
        (!p.equals(path, _root) && !p.isWithin(_root, path))) {
      throw FileSystemException(
        'Worker operation journal directory is not canonical.',
        path,
      );
    }
  }

  Future<void> _prepareRoot() async {
    final root = Directory(_root);
    final type = await FileSystemEntity.type(_root, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      await root.create(recursive: true);
      await _permissionHardener.hardenDirectory(root);
      await _directorySyncer.sync(root.parent.path);
      return;
    }
    if (type != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Worker operation journal root is not a directory.',
        _root,
      );
    }
    final canonical = p.normalize(await root.resolveSymbolicLinks());
    if (!p.equals(canonical, _root)) {
      throw FileSystemException(
        'Worker operation journal root is not canonical.',
        _root,
      );
    }
    await _permissionHardener.hardenDirectory(root);
  }

  Future<void> _validateStoreFiles(String path) async {
    for (final candidate in <String>[path, '$path.lock']) {
      final type = await FileSystemEntity.type(candidate, followLinks: false);
      if (type == FileSystemEntityType.notFound) continue;
      if (type != FileSystemEntityType.file) {
        throw FileSystemException(
          'Worker operation journal record has an invalid file type.',
          candidate,
        );
      }
      final canonical = p.normalize(
        await File(candidate).resolveSymbolicLinks(),
      );
      if (!p.equals(canonical, candidate)) {
        throw FileSystemException(
          'Worker operation journal record is not canonical.',
          candidate,
        );
      }
    }
  }
}

enum _OperationState { prepared, running, completed }

final class _OperationRecord {
  const _OperationRecord({
    required this.idempotencyKey,
    required this.fingerprint,
    required this.operationId,
    required this.kind,
    required this.workspaceId,
    required this.submittedAt,
    required this.state,
    this.startedAt,
    this.result,
  });

  final String idempotencyKey;
  final String fingerprint;
  final String operationId;
  final String kind;
  final String workspaceId;
  final DateTime submittedAt;
  final DateTime? startedAt;
  final _OperationState state;
  final CockpitOperationResult? result;

  _OperationRecord running(DateTime value) => _OperationRecord(
    idempotencyKey: idempotencyKey,
    fingerprint: fingerprint,
    operationId: operationId,
    kind: kind,
    workspaceId: workspaceId,
    submittedAt: submittedAt,
    startedAt: value,
    state: _OperationState.running,
  );

  _OperationRecord completed(CockpitOperationResult value) => _OperationRecord(
    idempotencyKey: idempotencyKey,
    fingerprint: fingerprint,
    operationId: operationId,
    kind: kind,
    workspaceId: workspaceId,
    submittedAt: submittedAt,
    startedAt: startedAt ?? value.startedAt,
    state: _OperationState.completed,
    result: value,
  );

  _OperationRecord preparedForRetry() => _OperationRecord(
    idempotencyKey: idempotencyKey,
    fingerprint: fingerprint,
    operationId: operationId,
    kind: kind,
    workspaceId: workspaceId,
    submittedAt: submittedAt,
    state: _OperationState.prepared,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'idempotencyKey': idempotencyKey,
    'fingerprint': fingerprint,
    'operationId': operationId,
    'kind': kind,
    'workspaceId': workspaceId,
    'submittedAt': submittedAt.toUtc().toIso8601String(),
    if (startedAt != null) 'startedAt': startedAt!.toUtc().toIso8601String(),
    'state': state.name,
    if (result != null) 'result': result!.toJson(),
  };
}

Map<String, Object?> _emptyRecordState() => <String, Object?>{
  'schemaVersion': CockpitFileWorkerOperationJournal.schemaVersion,
  'record': null,
};

_OperationRecord? _decodeOptionalRecordState(Map<String, Object?> raw) {
  final json = workerObject(raw, r'$');
  workerKeys(
    json,
    const <String>{'schemaVersion', 'record'},
    r'$',
    required: const <String>{'schemaVersion', 'record'},
  );
  if (json['schemaVersion'] !=
      CockpitFileWorkerOperationJournal.schemaVersion) {
    throw const FormatException('Unsupported worker operation record.');
  }
  final value = json['record'];
  return value == null ? null : _decodeRecord(value, r'$.record');
}

_OperationRecord _decodeRecordState(Map<String, Object?> raw) =>
    _decodeOptionalRecordState(raw) ??
    (throw const FormatException('Worker operation record is missing.'));

Map<String, Object?> _encodeRecordState(_OperationRecord record) =>
    <String, Object?>{
      'schemaVersion': CockpitFileWorkerOperationJournal.schemaVersion,
      'record': record.toJson(),
    };

_OperationRecord _decodeRecord(Object? value, String path) {
  final json = workerObject(value, path);
  workerKeys(
    json,
    const <String>{
      'idempotencyKey',
      'fingerprint',
      'operationId',
      'kind',
      'workspaceId',
      'submittedAt',
      'startedAt',
      'state',
      'result',
    },
    path,
    required: const <String>{
      'idempotencyKey',
      'fingerprint',
      'operationId',
      'kind',
      'workspaceId',
      'submittedAt',
      'state',
    },
  );
  final fingerprint = workerString(
    json['fingerprint'],
    '$path.fingerprint',
    minimum: 64,
    maximum: 64,
  );
  if (!_isLowercaseHex(fingerprint, length: 64)) {
    throw FormatException('Invalid operation fingerprint at $path.');
  }
  final stateName = workerString(json['state'], '$path.state', maximum: 32);
  final states = _OperationState.values
      .where((candidate) => candidate.name == stateName)
      .toList(growable: false);
  if (states.length != 1) {
    throw FormatException('Invalid operation state at $path.');
  }
  final state = states.single;
  final startedAt = json['startedAt'] == null
      ? null
      : workerUtcDateTime(json['startedAt'], '$path.startedAt');
  final result = json['result'] == null
      ? null
      : CockpitOperationResult.fromJson(json['result']);
  if ((state == _OperationState.prepared && startedAt != null) ||
      (state == _OperationState.running && startedAt == null) ||
      (state == _OperationState.completed && result == null) ||
      (state != _OperationState.completed && result != null)) {
    throw FormatException('Inconsistent operation state at $path.');
  }
  final record = _OperationRecord(
    idempotencyKey: workerId(json['idempotencyKey'], '$path.idempotencyKey'),
    fingerprint: fingerprint,
    operationId: workerId(json['operationId'], '$path.operationId'),
    kind: workerKind(json['kind'], '$path.kind'),
    workspaceId: workerId(json['workspaceId'], '$path.workspaceId'),
    submittedAt: workerUtcDateTime(json['submittedAt'], '$path.submittedAt'),
    startedAt: startedAt,
    state: state,
    result: result,
  );
  if (result != null &&
      (result.operationId != record.operationId ||
          result.kind != record.kind ||
          result.workspaceId != record.workspaceId)) {
    throw FormatException('Operation result identity mismatch at $path.');
  }
  return record;
}

CockpitOperationResult _interruptedResult(
  _OperationRecord record,
  DateTime finishedAt,
) => CockpitOperationResult(
  operationId: record.operationId,
  kind: record.kind,
  workspaceId: record.workspaceId,
  lifecycle: CockpitOperationLifecycle.completed,
  outcome: CockpitOperationOutcome.failed,
  submittedAt: record.submittedAt,
  startedAt: record.startedAt ?? record.submittedAt,
  finishedAt: finishedAt,
  failure: CockpitFailure(
    primary: CockpitApiError(
      code: 'operationInterrupted',
      category: CockpitErrorCategory.interrupted,
      message: 'Worker restarted before mutation outcome was committed.',
      retryable: false,
      responsibleLayer: CockpitResponsibleLayer.worker,
    ),
  ),
);

String _fingerprint(CockpitOperationInvocation invocation) {
  final canonical = _canonicalJson(<String, Object?>{
    'kind': invocation.kind,
    'workspaceId': invocation.workspaceId,
    'rootId': invocation.rootId,
    'input': invocation.input,
    'requiredFeatures': invocation.requiredFeatures,
    'idempotencyKey': invocation.idempotencyKey?.value,
  });
  return sha256.convert(utf8.encode(canonical)).toString();
}

String _recordHash(String idempotencyKey) =>
    sha256.convert(utf8.encode(idempotencyKey)).toString();

Map<String, Object?> _encodeActiveManifest(Map<String, String> active) =>
    <String, Object?>{
      'schemaVersion': 'cockpit.worker.operation-active/v1',
      'records': <String, Object?>{
        for (final entry in active.entries) entry.key: entry.value,
      },
    };

Map<String, String> _decodeActiveManifest(Map<String, Object?> value) {
  final json = workerObject(value, r'$');
  workerKeys(
    json,
    const <String>{'schemaVersion', 'records'},
    r'$',
    required: const <String>{'schemaVersion', 'records'},
  );
  if (json['schemaVersion'] != 'cockpit.worker.operation-active/v1') {
    throw const FormatException('Unsupported operation active manifest.');
  }
  final records = workerObject(json['records'], r'$.records');
  if (records.length > 10000) {
    throw const FormatException('Operation active manifest exceeds bounds.');
  }
  final result = <String, String>{};
  for (final entry in records.entries) {
    final hash = entry.key;
    final key = workerId(entry.value, '\$.records.$hash');
    if (!_isLowercaseHex(hash, length: 64) || hash != _recordHash(key)) {
      throw const FormatException('Operation active manifest hash is invalid.');
    }
    result[hash] = key;
  }
  return result;
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

String _canonicalJson(Object? value) {
  if (value is Map<Object?, Object?>) {
    final keys = value.keys.cast<String>().toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${_canonicalJson(_canonicalFingerprintField(key, value[key]))}').join(',')}}';
  }
  if (value is List<Object?>) {
    return '[${value.map(_canonicalJson).join(',')}]';
  }
  return jsonEncode(value);
}

Object? _canonicalFingerprintField(String key, Object? value) {
  if (key != 'requiredFeatures' || value is! List<Object?>) return value;
  if (value.any((feature) => feature is! String)) return value;
  return value.cast<String>().toList()..sort();
}

final class _OperationJournalRecordCodec
    implements CockpitJsonCodec<Map<String, Object?>> {
  const _OperationJournalRecordCodec();

  @override
  Map<String, Object?> decode(Object? json) => workerObject(json, r'$');

  @override
  Object? encode(Map<String, Object?> value) => value;
}

final class _OperationActiveManifestCodec
    implements CockpitJsonCodec<Map<String, Object?>> {
  const _OperationActiveManifestCodec();

  @override
  Map<String, Object?> decode(Object? json) => workerObject(json, r'$');

  @override
  Object? encode(Map<String, Object?> value) => value;
}
