import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../foundation/cockpit_permissions.dart';

const String cockpitRemotePasswordDartDefineName =
    'FLUTTER_COCKPIT_REMOTE_PASSWORD';

final class CockpitRemotePasswordDartDefineFile {
  CockpitRemotePasswordDartDefineFile._({
    required this.path,
    required Directory directory,
  }) : _directory = directory;

  final String path;
  final Directory _directory;
  bool _deleted = false;
  Future<void>? _deleting;

  static Future<CockpitRemotePasswordDartDefineFile> create(
    String password, {
    CockpitPermissionHardener? permissionHardener,
  }) async {
    if (password.isEmpty) {
      throw ArgumentError.value(
        password,
        'password',
        'The password cannot be empty.',
      );
    }
    final hardener =
        permissionHardener ??
        (Platform.isWindows
            ? const CockpitWindowsAclPermissionHardener()
            : const CockpitPosixPermissionHardener());
    final directory = await Directory.systemTemp.createTemp(
      'cockpit-remote-auth-',
    );
    try {
      await hardener.hardenDirectory(directory);
      final file = File(p.join(directory.path, 'defines.json'));
      await file.writeAsString(
        '${jsonEncode(<String, String>{cockpitRemotePasswordDartDefineName: password})}\n',
        flush: true,
      );
      await hardener.hardenFile(file);
      return CockpitRemotePasswordDartDefineFile._(
        path: file.path,
        directory: directory,
      );
    } on Object {
      await _bestEffortDelete(directory);
      rethrow;
    }
  }

  Future<void> delete() {
    if (_deleted) return Future<void>.value();
    final deleting = _deleting;
    if (deleting != null) return deleting;

    late final Future<void> operation;
    operation = _deleteDirectory().whenComplete(() {
      if (identical(_deleting, operation)) {
        _deleting = null;
      }
    });
    _deleting = operation;
    return operation;
  }

  Future<void> _deleteDirectory() async {
    final type = await FileSystemEntity.type(
      _directory.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) {
      _deleted = true;
      return;
    }
    if (type != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Remote authentication temporary path is not a directory.',
        _directory.path,
      );
    }
    await _directory.delete(recursive: true);
    _deleted = true;
  }

  static Future<void> _bestEffortDelete(Directory directory) async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } on Object {
      // Preserve the creation failure that explains why no safe file exists.
    }
  }
}
