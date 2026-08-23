import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../foundation/cockpit_locked_json_store.dart';
import '../foundation/cockpit_permissions.dart';
import 'cockpit_worker_logger.dart';

final class CockpitWorkerSessionLogStore {
  CockpitWorkerSessionLogStore({
    required String root,
    required CockpitWorkerLogRedactor redactor,
    required CockpitPermissionHardener permissionHardener,
    required CockpitDirectorySyncer directorySyncer,
    DateTime Function()? utcNow,
    this.maximumFileBytes = 4 * 1024 * 1024,
    this.maximumLineBytes = 16 * 1024,
  }) : root = p.normalize(p.absolute(root)),
       _redactor = redactor,
       _permissionHardener = permissionHardener,
       _directorySyncer = directorySyncer,
       _utcNow = utcNow ?? (() => DateTime.now().toUtc()) {
    if (maximumFileBytes < 64 * 1024 || maximumFileBytes > 64 * 1024 * 1024) {
      throw ArgumentError.value(maximumFileBytes, 'maximumFileBytes');
    }
    if (maximumLineBytes < 256 || maximumLineBytes > maximumFileBytes ~/ 4) {
      throw ArgumentError.value(maximumLineBytes, 'maximumLineBytes');
    }
  }

  final String root;
  final CockpitWorkerLogRedactor _redactor;
  final CockpitPermissionHardener _permissionHardener;
  final CockpitDirectorySyncer _directorySyncer;
  final DateTime Function() _utcNow;
  final int maximumFileBytes;
  final int maximumLineBytes;
  final Map<String, Future<void>> _tails = <String, Future<void>>{};

  String pathFor(String developmentSessionId) =>
      p.join(root, '${_safeDevelopmentSessionId(developmentSessionId)}.log');

  Future<String> create(String developmentSessionId) async {
    final path = pathFor(developmentSessionId);
    await _enqueue(developmentSessionId, () async {
      final directory = await _prepareRoot();
      final file = File(path);
      final handle = await file.open(mode: FileMode.write);
      try {
        await handle.truncate(0);
        await handle.flush();
      } finally {
        await handle.close();
      }
      await _permissionHardener.hardenFile(file);
      await _directorySyncer.sync(directory.path);
    });
    return path;
  }

  Future<void> append(String developmentSessionId, String message) {
    return _enqueue(developmentSessionId, () async {
      final directory = await _prepareRoot();
      final file = File(pathFor(developmentSessionId));
      final existed = await file.exists();
      final bytes = _encode(message);
      await _appendBounded(file, bytes);
      if (!existed) {
        await _permissionHardener.hardenFile(file);
        await _directorySyncer.sync(directory.path);
      }
    });
  }

  Future<void> flush(String developmentSessionId) async {
    await (_tails[developmentSessionId] ?? Future<void>.value());
  }

  Future<void> flushAll() async {
    await Future.wait<void>(_tails.values.toList(growable: false));
  }

  Future<Directory> _prepareRoot() async {
    final directory = Directory(root);
    final existed = await directory.exists();
    if (!existed) {
      await directory.create(recursive: true);
      await _permissionHardener.hardenDirectory(directory);
      await _directorySyncer.sync(directory.parent.path);
    }
    return directory;
  }

  Future<void> _appendBounded(File file, Uint8List incoming) async {
    final existingLength = await file.exists() ? await file.length() : 0;
    if (existingLength + incoming.length <= maximumFileBytes) {
      final handle = await file.open(mode: FileMode.append);
      try {
        await handle.writeFrom(incoming);
        await handle.flush();
      } finally {
        await handle.close();
      }
      return;
    }

    final retainedBudget = math.max(0, maximumFileBytes - incoming.length);
    final retained = retainedBudget == 0
        ? Uint8List(0)
        : await _readCompleteTail(file, retainedBudget);
    final replacement = BytesBuilder(copy: false)
      ..add(retained)
      ..add(incoming);
    final handle = await file.open(mode: FileMode.write);
    try {
      await handle.writeFrom(replacement.takeBytes());
      await handle.flush();
    } finally {
      await handle.close();
    }
  }

  Future<Uint8List> _readCompleteTail(File file, int maximumBytes) async {
    final length = await file.length();
    if (length <= maximumBytes) {
      return file.readAsBytes();
    }
    final start = length - maximumBytes;
    final handle = await file.open();
    try {
      await handle.setPosition(start);
      final tail = await handle.read(maximumBytes);
      final firstLineEnd = tail.indexOf(0x0a);
      if (firstLineEnd < 0 || firstLineEnd + 1 >= tail.length) {
        return Uint8List(0);
      }
      return Uint8List.sublistView(tail, firstLineEnd + 1);
    } finally {
      await handle.close();
    }
  }

  Uint8List _encode(String message) {
    final timestamp = _utcNow().toIso8601String();
    final safe = _redactor
        .redactText(message)
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final output = BytesBuilder(copy: false);
    for (final sourceLine in safe.split('\n')) {
      final prefix = utf8.encode('[$timestamp] ');
      final suffix = utf8.encode('\n');
      final available = maximumLineBytes - prefix.length - suffix.length;
      final line = _truncateUtf8(sourceLine, available);
      output
        ..add(prefix)
        ..add(line)
        ..add(suffix);
    }
    return output.takeBytes();
  }

  Uint8List _truncateUtf8(String value, int maximumBytes) {
    final bytes = utf8.encode(value);
    if (bytes.length <= maximumBytes) return Uint8List.fromList(bytes);
    const marker = ' [truncated]';
    final markerBytes = utf8.encode(marker);
    final contentBytes = math.max(0, maximumBytes - markerBytes.length);
    var end = contentBytes;
    String prefix;
    while (true) {
      try {
        prefix = utf8.decode(bytes.sublist(0, end), allowMalformed: false);
        break;
      } on FormatException {
        end -= 1;
      }
    }
    return Uint8List.fromList(utf8.encode('$prefix$marker'));
  }

  Future<void> _enqueue(
    String developmentSessionId,
    Future<void> Function() operation,
  ) {
    _safeDevelopmentSessionId(developmentSessionId);
    final previous = _tails[developmentSessionId] ?? Future<void>.value();
    late final Future<void> next;
    next = previous
        .catchError((Object _) {})
        .then((_) => operation())
        .whenComplete(() {
          if (identical(_tails[developmentSessionId], next)) {
            _tails.remove(developmentSessionId);
          }
        });
    _tails[developmentSessionId] = next;
    return next;
  }
}

String _safeDevelopmentSessionId(String value) {
  if (value.isEmpty ||
      value.length > 128 ||
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(value)) {
    throw ArgumentError.value(value, 'developmentSessionId');
  }
  return value;
}
