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
  var _deferredBytes = 0;
  static const _maxDeferredBytes = 4 * 1024 * 1024;
  IOSink? _spillSink;
  File? _spillFile;
  var _spillSequence = 0;
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
      if (_deferredBytes + bytes <=
          (options.maxPendingBytes ?? _maxDeferredBytes)) {
        _deferredBytes += bytes;
        _deferred.add(record);
      } else {
        _writeSpill(record);
      }
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
      await _drainDeferredAndSpill();
      final current = _sink;
      if (current != null && !identical(current, sink)) {
        await _flushUntilIdle(current);
      }
      if (_chunkBytes >= options.chunkBytes && _chunkRecords > 0) {
        await _rotateChunk();
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
    await sink.flush();
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
    if (_deferred.isNotEmpty || _spillSink != null) {
      _busy = true;
      try {
        await _drainDeferredAndSpill();
        final current = _sink;
        if (current != null) await _flushUntilIdle(current);
      } on Object catch (error) {
        _errors += 1;
        _reason ??= _shortReason(error);
      } finally {
        _busy = false;
      }
    }
    final sink = _sink;
    final part = _partFile;
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
    final spillSink = _spillSink;
    if (spillSink != null) {
      try {
        await spillSink.close();
      } on Object catch (error) {
        _errors += 1;
        _reason ??= _shortReason(error);
      }
    }
    _closed = true;
    await _manifestQueue;
    _writeManifest(_errors == 0 ? 'done' : 'failed');
    await _manifestQueue;
    return snapshot();
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
    final oldSink = _sink;
    final oldPart = _partFile;
    final oldRecords = _chunkRecords;
    if (oldSink == null || oldPart == null || oldRecords == 0) return;

    // Open the next chunk before awaiting the old sink. Event producers stay
    // non-blocking and never accumulate an in-memory deferred list while a
    // slow filesystem flush or rename is in progress. The old `.part` path is
    // included in the live manifest and is replaced with its final path after
    // the close succeeds, so a runner crash still leaves recoverable data.
    final oldChunkIndex = _chunks.length;
    _chunks.add(oldPart.absolute.path);
    _sink = null;
    _partFile = null;
    _chunkBytes = 0;
    _chunkRecords = 0;
    await _openChunk();

    try {
      await oldSink.flush();
      await oldSink.close();
      final finalFile = File(oldPart.path.replaceFirst(RegExp(r'\.part$'), ''));
      await oldPart.rename(finalFile.path);
      _chunks[oldChunkIndex] = finalFile.absolute.path;
    } on Object catch (error) {
      _errors += 1;
      _reason ??= _shortReason(error);
    }
    await _drainDeferredAndSpill();
    final current = _sink;
    if (current != null) await _flushUntilIdle(current);
  }

  Future<void> _drainDeferredAndSpill() async {
    while (true) {
      final sink = _sink;
      if (sink == null) return;
      if (_deferred.isNotEmpty) {
        final records = List<_ArchiveRecord>.of(_deferred);
        _deferred.clear();
        _deferredBytes = 0;
        for (final record in records) {
          _writeRecord(record);
        }
      }

      final spillSink = _spillSink;
      final spillFile = _spillFile;
      if (spillSink == null || spillFile == null) return;
      _spillSink = null;
      _spillFile = null;
      try {
        await spillSink.flush();
        await spillSink.close();
        await for (final line
            in spillFile
                .openRead()
                .transform(utf8.decoder)
                .transform(const LineSplitter())) {
          if (line.isEmpty) continue;
          final value = jsonDecode(line);
          final kind = value is Map ? value['q'] as String? : null;
          _writeRecord(
            _ArchiveRecord(
              kind: kind ?? 'e',
              line: '$line\n',
              bytes: utf8.encode('$line\n').length,
            ),
          );
        }
        await spillFile.delete();
      } on Object catch (error) {
        _errors += 1;
        _reason ??= _shortReason(error);
        // Keep the file path in the manifest when draining fails. It is a
        // valid JSONL recovery artifact even when the primary chunk failed.
        _spillFile = spillFile;
        return;
      }
    }
  }

  void _writeSpill(_ArchiveRecord record) {
    try {
      final sink = _spillSink ??= _openSpillSink();
      sink.write(record.line);
    } on Object catch (error) {
      _errors += 1;
      _reason ??= _shortReason(error);
    }
  }

  IOSink _openSpillSink() {
    _spillSequence += 1;
    final file = File(
      '${_root.path}/$name-spill-${_spillSequence.toString().padLeft(6, '0')}.jsonl.part',
    );
    _spillFile = file;
    return file.openWrite(mode: FileMode.write, encoding: utf8);
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
      // Keep the manifest portable across CI artifact downloads. The public
      // archive info still exposes absolute paths for direct local use, while
      // manifest consumers resolve chunk names relative to the manifest file.
      'chunks': _manifestChunkPaths(),
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
      paths.add(
        _closed ? part.path.replaceFirst(RegExp(r'\.part$'), '') : part.path,
      );
    }
    final spill = _spillFile;
    if (spill != null) paths.add(spill.absolute.path);
    return paths;
  }

  List<String> _manifestChunkPaths() {
    return _allChunkPaths().map(_relativeToRoot).toList(growable: false);
  }

  String _relativeToRoot(String path) {
    final root = _root.absolute.path;
    final absolute = File(path).absolute.path;
    final prefix = root.endsWith(Platform.pathSeparator)
        ? root
        : '$root${Platform.pathSeparator}';
    if (!absolute.startsWith(prefix)) return absolute;
    return absolute
        .substring(prefix.length)
        .replaceAll(Platform.pathSeparator, '/');
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

Future<String> mergeCockpitPerformanceArchives(
  Iterable<String> sources, {
  required String? directory,
  required String name,
  required CockpitPerformanceArchiveOptions options,
}) async {
  final inputs = sources
      .map((source) => source.trim())
      .where((source) => source.isNotEmpty)
      .toList(growable: false);
  if (inputs.isEmpty) {
    throw ArgumentError.value(sources, 'sources', 'Must not be empty.');
  }
  options.validate();
  final root = directory == null || directory.trim().isEmpty
      ? Directory(
          'build/cockpit/performance/$name-merged-'
          '${DateTime.now().toUtc().microsecondsSinceEpoch}',
        )
      : Directory(directory.trim());
  final backend = _JsonlPerformanceArchive(
    directory: root.path,
    name: name,
    options: options,
  );
  await backend.open();
  try {
    for (var index = 0; index < inputs.length; index += 1) {
      final chunks = await _resolveArchiveChunks(inputs[index]);
      for (final chunk in chunks) {
        await _copyArchiveChunk(backend, chunk, sourceIndex: index);
      }
    }
    return (await backend.close()).manifest;
  } catch (_) {
    try {
      await backend.close();
    } on Object {
      // Preserve the original merge failure.
    }
    rethrow;
  }
}

const Set<String> _archiveRecordKinds = <String>{
  's',
  'f',
  'e',
  'm',
  'h',
  'i',
  'l',
  'd',
  'x',
};

Future<List<File>> _resolveArchiveChunks(String source) async {
  final file = File(source).absolute;
  if (!await file.exists()) {
    throw StateError('Performance archive source does not exist: ${file.path}');
  }
  final isManifest = file.path.endsWith('.manifest.json');
  if (!isManifest) return <File>[file];
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map<Object?, Object?>) {
    throw const FormatException(
      'Performance archive manifest must be an object.',
    );
  }
  if (decoded['schema'] != 'cockpit.performance.stream/v1') {
    throw const FormatException(
      'Unsupported performance archive manifest schema.',
    );
  }
  final rawChunks = decoded['chunks'];
  if (rawChunks is! List<Object?> || rawChunks.isEmpty) {
    throw const FormatException('Performance archive manifest has no chunks.');
  }
  final resolved = <File>[];
  final seen = <String>{};
  for (final raw in rawChunks) {
    if (raw is! String || raw.trim().isEmpty) {
      throw const FormatException('Performance archive chunk path is invalid.');
    }
    final chunk = File(raw.trim()).isAbsolute
        ? File(raw.trim())
        : File('${file.parent.path}/${raw.trim()}');
    final absolute = chunk.absolute;
    if (!await absolute.exists()) {
      throw StateError(
        'Performance archive chunk does not exist: ${absolute.path}',
      );
    }
    if (seen.add(absolute.path)) resolved.add(absolute);
  }
  if (resolved.isEmpty) {
    throw const FormatException(
      'Performance archive manifest has no usable chunks.',
    );
  }
  return resolved;
}

Future<void> _copyArchiveChunk(
  _JsonlPerformanceArchive backend,
  File chunk, {
  required int sourceIndex,
}) async {
  var lineNumber = 0;
  final prefix = 'm${(sourceIndex + 1).toRadixString(36)}-';
  await for (final line
      in chunk
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    lineNumber += 1;
    if (line.trim().isEmpty) continue;
    final decoded = jsonDecode(line);
    if (decoded is! Map<Object?, Object?>) {
      throw FormatException(
        'Performance archive record must be an object: '
        '${chunk.path}:$lineNumber',
      );
    }
    final value = Map<String, Object?>.from(decoded);
    final kind = value.remove('q');
    if (kind is! String || !_archiveRecordKinds.contains(kind)) {
      throw FormatException(
        'Unknown performance archive record kind at '
        '${chunk.path}:$lineNumber.',
      );
    }
    if (kind == 's' || kind == 'x') {
      final id = value['id'];
      if (id is! String || id.trim().isEmpty) {
        throw FormatException(
          'Performance archive $kind record has no capture id at '
          '${chunk.path}:$lineNumber.',
        );
      }
      value['id'] = '$prefix${id.trim()}';
    }
    backend.add(kind, value);
  }
}

String _shortReason(Object error) {
  final value = error.toString().trim();
  if (value.isEmpty) return 'archive write failed';
  return value.length <= 512 ? value : '${value.substring(0, 511)}…';
}
