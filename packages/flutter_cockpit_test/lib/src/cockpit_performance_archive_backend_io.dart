import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'cockpit_performance_archive_backend.dart';
import 'cockpit_performance_archive_options.dart';

final class _JsonlPerformanceArchive
    implements CockpitPerformanceArchiveBackend {
  _JsonlPerformanceArchive({
    required this.directory,
    required this.name,
    required this.options,
  });

  final String directory;
  final String name;
  final CockpitPerformanceArchiveOptions options;
  late final Directory _root;
  late final File _manifestFile;
  IOSink? _sink;
  File? _partFile;
  var _chunk = 0;
  var _chunkBytes = 0;
  var _chunkRecords = 0;
  var _bytes = 0;
  var _records = 0;
  var _events = 0;
  var _frames = 0;
  var _dropped = 0;
  var _errors = 0;
  var _closed = false;
  var _opened = false;
  Future<void>? _flushFuture;
  var _pendingBytes = 0;
  var _busy = false;
  String? _reason;
  Future<void> _manifestQueue = Future<void>.value();
  Timer? _flushTimer;
  final List<String> _chunks = <String>[];
  final List<_ArchiveRecord> _deferred = <_ArchiveRecord>[];

  @override
  Future<void> open() async {
    if (_opened) return;
    options.validate();
    _root = Directory(directory).absolute;
    await _root.create(recursive: true);
    _manifestFile = File('${_root.path}/$name.manifest.json');
    if (await _manifestFile.exists()) {
      throw StateError(
        'Performance archive already exists: ${_manifestFile.absolute.path}',
      );
    }
    _opened = true;
    await _openChunk();
    _writeManifest('active');
    _flushTimer = Timer.periodic(options.flushEvery, (_) {
      unawaited(flush());
    });
  }

  @override
  void add(String kind, Map<String, Object?> value) {
    if (!_opened || _closed) {
      _errors += 1;
      _reason ??= 'archive is not open';
      return;
    }
    // `q` is reserved for the JSONL record type; payloads keep their native
    // compact keys (an isolate event already uses `k` for its lifecycle kind).
    final payload = <String, Object?>{'q': kind, ...value};
    final line = '${jsonEncode(payload)}\n';
    final bytes = utf8.encode(line).length;
    final maxPendingBytes = options.maxPendingBytes;
    if (options.mode == CockpitPerformanceArchiveMode.low &&
        maxPendingBytes != null &&
        _pendingBytes + bytes > maxPendingBytes) {
      _dropped += 1;
      return;
    }
    if (_sink == null) {
      _errors += 1;
      _reason ??= 'archive sink is unavailable';
      return;
    }
    final record = _ArchiveRecord(kind: kind, line: line, bytes: bytes);
    _pendingBytes += bytes;
    if (_busy) {
      _deferred.add(record);
      return;
    }
    _writeRecord(record);
  }

  void _writeRecord(_ArchiveRecord record) {
    final sink = _sink;
    if (sink == null) {
      _errors += 1;
      _reason ??= 'archive sink is unavailable';
      return;
    }
    try {
      sink.write(record.line);
      _bytes += record.bytes;
      _records += 1;
      _chunkBytes += record.bytes;
      _chunkRecords += 1;
      if (record.kind == 'e') _events += 1;
      if (record.kind == 'f') _frames += 1;
    } on Object catch (error) {
      _errors += 1;
      _reason ??= _shortReason(error);
    }
  }

  void _drainDeferred() {
    if (_deferred.isEmpty) return;
    final records = List<_ArchiveRecord>.of(_deferred);
    _deferred.clear();
    for (final record in records) {
      _writeRecord(record);
    }
  }

  @override
  Future<void> flush() async {
    final active = _flushFuture;
    if (active != null) return active;
    if (!_opened || _closed) return;
    final sink = _sink;
    if (sink == null) return;
    final operation = _flushImpl(sink);
    _flushFuture = operation;
    try {
      await operation;
    } finally {
      if (identical(_flushFuture, operation)) _flushFuture = null;
    }
  }

  Future<void> _flushImpl(IOSink sink) async {
    _busy = true;
    try {
      await _flushUntilIdle(sink);
      if (_chunkBytes >= options.chunkBytes && _chunkRecords > 0) {
        await _rotateChunk();
        final rotatedSink = _sink;
        if (rotatedSink != null) {
          await _flushUntilIdle(rotatedSink);
        }
      }
      _pendingBytes = 0;
      _writeManifest('active');
    } on Object catch (error) {
      _errors += 1;
      _reason ??= _shortReason(error);
    } finally {
      _busy = false;
    }
  }

  Future<void> _flushUntilIdle(IOSink sink) async {
    var activeSink = sink;
    while (true) {
      await activeSink.flush();
      _drainDeferred();
      if (_deferred.isEmpty) return;
      activeSink = _sink ?? activeSink;
    }
  }

  @override
  Future<CockpitPerformanceArchiveInfo> close() async {
    if (!_opened) {
      throw StateError('Performance archive has not been opened.');
    }
    if (_closed) return snapshot();
    _flushTimer?.cancel();
    _flushTimer = null;
    await flush();
    _busy = true;
    final sink = _sink;
    final part = _partFile;
    try {
      if (sink != null) {
        try {
          await _flushUntilIdle(sink);
          // Reject late records once the final flush is complete. A frame
          // listener arriving during close must not be queued behind a sink
          // that is already being closed.
          _closed = true;
          await sink.close();
          _pendingBytes = 0;
        } on Object catch (error) {
          _errors += 1;
          _reason ??= _shortReason(error);
        }
      }
      if (part != null && await part.exists()) {
        final finalFile = File(part.path.replaceFirst(RegExp(r'\.part$'), ''));
        try {
          if (_chunkRecords > 0) {
            await part.rename(finalFile.path);
            if (!_chunks.contains(finalFile.path)) _chunks.add(finalFile.path);
          } else {
            await part.delete();
          }
        } on Object catch (error) {
          _errors += 1;
          _reason ??= _shortReason(error);
        }
      }
      _sink = null;
      _partFile = null;
      _closed = true;
      await _manifestQueue;
      _writeManifest(_errors == 0 ? 'done' : 'failed');
      await _manifestQueue;
      return snapshot();
    } finally {
      _busy = false;
    }
  }

  @override
  CockpitPerformanceArchiveInfo snapshot() => CockpitPerformanceArchiveInfo(
    format: 'jsonl',
    mode: options.mode.value,
    state: _closed ? (_errors == 0 ? 'done' : 'failed') : 'active',
    manifest: _manifestFile.absolute.path,
    chunks: _allChunkPaths(),
    events: _events,
    frames: _frames,
    records: _records,
    bytes: _bytes,
    dropped: _dropped,
    errors: _errors,
    reason: _reason,
  );

  Future<void> _openChunk() async {
    _chunk += 1;
    _chunkBytes = 0;
    _chunkRecords = 0;
    final stem = '$name-${_chunk.toString().padLeft(6, '0')}.jsonl';
    final part = File('${_root.path}/$stem.part');
    _partFile = part;
    _sink = part.openWrite(mode: FileMode.write, encoding: utf8);
  }

  Future<void> _rotateChunk() async {
    final sink = _sink;
    final part = _partFile;
    if (sink == null || part == null) return;
    await sink.flush();
    await sink.close();
    final finalFile = File(part.path.replaceFirst(RegExp(r'\.part$'), ''));
    await part.rename(finalFile.path);
    _chunks.add(finalFile.absolute.path);
    _sink = null;
    _partFile = null;
    await _openChunk();
  }

  void _writeManifest(String state) {
    if (!_opened) return;
    final json = <String, Object?>{
      'schema': 'cockpit.performance.stream/v1',
      'format': 'jsonl',
      'mode': options.mode.value,
      'state': state,
      'manifest': _manifestFile.absolute.path,
      'chunk': options.chunkBytes,
      'flushMs': options.flushEvery.inMilliseconds,
      'pollMs': options.pollEvery.inMilliseconds,
      if (options.maxPendingBytes != null) 'pending': options.maxPendingBytes,
      'chunks': _allChunkPaths(),
      'records': _records,
      'events': _events,
      'frames': _frames,
      'bytes': _bytes,
      if (_dropped > 0) 'dropped': _dropped,
      if (_errors > 0) 'errors': _errors,
      if (_reason != null) 'reason': _reason,
    };
    final temporary = File('${_manifestFile.path}.part');
    // Serialize tiny index updates so close cannot race a periodic flush.
    _manifestQueue = _manifestQueue.then((_) async {
      try {
        await temporary.writeAsString(jsonEncode(json), flush: true);
        await temporary.rename(_manifestFile.path);
      } on Object catch (error) {
        _errors += 1;
        _reason ??= _shortReason(error);
      }
    });
  }

  List<String> _allChunkPaths() {
    final paths = List<String>.of(_chunks);
    final part = _partFile;
    if (part != null) {
      paths.add(part.path.replaceFirst(RegExp(r'\.part$'), ''));
    }
    return paths;
  }
}

final class _ArchiveRecord {
  const _ArchiveRecord({
    required this.kind,
    required this.line,
    required this.bytes,
  });

  final String kind;
  final String line;
  final int bytes;
}

CockpitPerformanceArchiveBackend createCockpitPerformanceArchiveBackend({
  required String directory,
  required String name,
  required CockpitPerformanceArchiveOptions options,
}) => _JsonlPerformanceArchive(
  directory: directory,
  name: name,
  options: options,
);

String _shortReason(Object error) {
  final value = error.toString().trim();
  if (value.isEmpty) return 'archive write failed';
  return value.length <= 512 ? value : '${value.substring(0, 511)}…';
}
