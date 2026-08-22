import 'dart:io';

import 'package:path/path.dart' as p;

import '../foundation/cockpit_internal_process.dart';
import 'cockpit_runtime_resources.dart';

const String _runtimeDirectoryName = 'cockpit-runtime';
const String _runtimeReleasesDirectoryName = 'releases';

const Map<String, List<String>> cockpitManagedLauncherArguments =
    <String, List<String>>{
      'cockpit': <String>[],
      'cockpit_mcp': <String>['serve-mcp'],
      'cockpit_worker': <String>[cockpitInternalWorkerCommand],
      'cockpitd': <String>[cockpitInternalDaemonCommand],
    };

String? _currentExecutableOverride;

String cockpitCurrentExecutable() =>
    _currentExecutableOverride ?? Platform.resolvedExecutable;

void cockpitUseCurrentExecutable(String executablePath) {
  _currentExecutableOverride = File(executablePath).absolute.path;
}

void cockpitResetCurrentExecutable() {
  _currentExecutableOverride = null;
}

String? cockpitPubCacheRoot(
  Map<String, String> environment, {
  required bool windows,
}) {
  final configured = environment['PUB_CACHE']?.trim();
  if (configured != null && configured.isNotEmpty) {
    return Directory(configured).absolute.path;
  }
  if (windows) {
    final local = environment['LOCALAPPDATA']?.trim();
    return local == null || local.isEmpty
        ? null
        : Directory(local).uri.resolve('Pub/Cache/').toFilePath();
  }
  final home = environment['HOME']?.trim();
  return home == null || home.isEmpty
      ? null
      : Directory(home).uri.resolve('.pub-cache/').toFilePath();
}

bool cockpitPathIsWithin(String path, String directory) {
  final normalizedPath = p.normalize(p.absolute(path));
  final normalizedDirectory = p.normalize(p.absolute(directory));
  return normalizedPath == normalizedDirectory ||
      p.isWithin(normalizedDirectory, normalizedPath);
}

bool cockpitPathsMatch(String left, String right, {required bool windows}) {
  final a = _resolvedPath(left);
  final b = _resolvedPath(right);
  return windows ? a.toLowerCase() == b.toLowerCase() : a == b;
}

final class CockpitInstalledRuntimePaths {
  CockpitInstalledRuntimePaths({
    required String pubCacheRoot,
    required this.windows,
  }) : pubCache = Directory(pubCacheRoot).absolute;

  final Directory pubCache;
  final bool windows;

  Directory get root =>
      Directory.fromUri(pubCache.uri.resolve('$_runtimeDirectoryName/'));

  Directory get releases =>
      Directory.fromUri(root.uri.resolve('$_runtimeReleasesDirectoryName/'));

  File launcherFor(String executable) => File.fromUri(
    pubCache.uri.resolve(windows ? 'bin/$executable.bat' : 'bin/$executable'),
  );

  Map<String, File> get launchers => <String, File>{
    for (final executable in cockpitManagedLauncherArguments.keys)
      executable: launcherFor(executable),
  };

  File get launcher => launcherFor('cockpit');

  File get legacyNative => File.fromUri(
    pubCache.uri.resolve(windows ? 'bin/cockpit.exe' : 'bin/cockpit'),
  );

  String get executableName => windows ? 'cockpit.exe' : 'cockpit';
}

final class CockpitInstalledRuntime {
  const CockpitInstalledRuntime({
    required this.paths,
    required this.release,
    required this.executable,
    required this.resources,
  });

  final CockpitInstalledRuntimePaths paths;
  final Directory release;
  final File executable;
  final Directory resources;
}

String cockpitRuntimeLauncherContents({
  required String executablePath,
  required String version,
  required bool windows,
  String executableName = 'cockpit',
  List<String> fixedArguments = const <String>[],
}) {
  if (windows) {
    final quoted = '"${executablePath.replaceAll('"', '""')}"';
    final arguments = fixedArguments
        .map((argument) => '"${argument.replaceAll('"', '""')}"')
        .join(' ');
    final invocation = arguments.isEmpty
        ? '$quoted %*'
        : '$quoted $arguments %*';
    return '@echo off\r\n'
        'rem This file was created by Cockpit.\r\n'
        'rem Package: cockpit\r\n'
        'rem Version: $version\r\n'
        'rem Executable: $executableName\r\n'
        'rem Script: $executableName\r\n'
        '$invocation\r\n'
        'exit /b %errorlevel%\r\n';
  }
  final quoted = "'${executablePath.replaceAll("'", "'\"'\"'")}'";
  final arguments = fixedArguments
      .map((argument) => "'${argument.replaceAll("'", "'\"'\"'")}'")
      .join(' ');
  final invocation = arguments.isEmpty
      ? 'exec $quoted "\$@"'
      : 'exec $quoted $arguments "\$@"';
  return '#!/usr/bin/env sh\n'
      '# This file was created by Cockpit.\n'
      '# Package: cockpit\n'
      '# Version: $version\n'
      '# Executable: $executableName\n'
      '# Script: $executableName\n'
      '$invocation\n';
}

Future<CockpitInstalledRuntime?> cockpitReadCanonicalInstalledRuntime({
  required Map<String, String> environment,
  required bool windows,
  required String resolvedExecutable,
  required String version,
  bool allowLegacyNative = false,
}) async {
  try {
    final pubCache = cockpitPubCacheRoot(environment, windows: windows);
    if (pubCache == null) return null;
    final paths = CockpitInstalledRuntimePaths(
      pubCacheRoot: pubCache,
      windows: windows,
    );
    final executable = File(resolvedExecutable).absolute;
    if (!await executable.exists() ||
        !cockpitPathIsWithin(executable.path, paths.releases.path) ||
        p.basename(executable.path).toLowerCase() !=
            paths.executableName.toLowerCase()) {
      return null;
    }
    final release = executable.parent;
    if (!cockpitPathsMatch(
      release.parent.path,
      paths.releases.path,
      windows: windows,
    )) {
      return null;
    }
    final resources = Directory(
      cockpitRuntimeResourceDirectoryPath(executable.path, windows: windows),
    );
    if (!await cockpitHasValidRuntimeResourceDirectory(
      resources,
      version: version,
    )) {
      return null;
    }
    if (windows && !allowLegacyNative && await paths.legacyNative.exists()) {
      return null;
    }
    for (final launcher in paths.launchers.entries) {
      if (!await launcher.value.exists() ||
          await launcher.value.readAsString() !=
              cockpitRuntimeLauncherContents(
                executablePath: executable.path,
                version: version,
                windows: windows,
                executableName: launcher.key,
                fixedArguments: cockpitManagedLauncherArguments[launcher.key]!,
              )) {
        return null;
      }
    }
    return CockpitInstalledRuntime(
      paths: paths,
      release: release,
      executable: executable,
      resources: resources,
    );
  } on Object {
    return null;
  }
}

Future<CockpitInstalledRuntime?> cockpitFindActiveInstalledRuntime({
  required Map<String, String> environment,
  required bool windows,
  required String version,
  bool allowLegacyNative = false,
}) async {
  final pubCache = cockpitPubCacheRoot(environment, windows: windows);
  if (pubCache == null) return null;
  final paths = CockpitInstalledRuntimePaths(
    pubCacheRoot: pubCache,
    windows: windows,
  );
  if (!await paths.releases.exists()) return null;
  await for (final entity in paths.releases.list(followLinks: false)) {
    if (entity is! Directory) continue;
    final executable = File.fromUri(entity.uri.resolve(paths.executableName));
    final installed = await cockpitReadCanonicalInstalledRuntime(
      environment: environment,
      windows: windows,
      resolvedExecutable: executable.path,
      version: version,
      allowLegacyNative: allowLegacyNative,
    );
    if (installed != null) return installed;
  }
  return null;
}

typedef CockpitInstalledRuntimeVerifier =
    Future<void> Function(File executable);

Future<CockpitInstalledRuntime> cockpitInstallRuntimeRelease({
  required Map<String, String> environment,
  required bool windows,
  required File stagedExecutable,
  required Directory stagedResources,
  required String version,
  required CockpitInstalledRuntimeVerifier verify,
}) async {
  final pubCache = cockpitPubCacheRoot(environment, windows: windows);
  if (pubCache == null) {
    throw const FileSystemException('Unable to locate the Pub cache.');
  }
  if (!await stagedExecutable.exists()) {
    throw FileSystemException(
      'Cockpit runtime executable staging file is missing.',
      stagedExecutable.path,
    );
  }
  if (!await cockpitHasValidRuntimeResourceDirectory(
    stagedResources,
    version: version,
  )) {
    throw FileSystemException(
      'Cockpit runtime resource staging directory is invalid.',
      stagedResources.path,
    );
  }

  final paths = CockpitInstalledRuntimePaths(
    pubCacheRoot: pubCache,
    windows: windows,
  );
  await paths.releases.create(recursive: true);
  final release = await _createReleaseDirectory(paths.releases);
  final executable = File.fromUri(release.uri.resolve(paths.executableName));
  final resources = Directory(
    cockpitRuntimeResourceDirectoryPath(executable.path, windows: windows),
  );
  var launcherInstalled = false;
  try {
    await stagedExecutable.rename(executable.path);
    await stagedResources.rename(resources.path);
    if (!windows) await _makeExecutable(executable);
    await verify(executable);
    if (!await cockpitHasValidRuntimeResources(
      executablePath: executable.path,
      version: version,
      windows: windows,
    )) {
      throw FileSystemException(
        'Installed Cockpit runtime resources could not be verified.',
        resources.path,
      );
    }
    await _replaceLaunchers(<File, String>{
      for (final launcher in paths.launchers.entries)
        launcher.value: cockpitRuntimeLauncherContents(
          executablePath: executable.path,
          version: version,
          windows: windows,
          executableName: launcher.key,
          fixedArguments: cockpitManagedLauncherArguments[launcher.key]!,
        ),
    }, windows: windows);
    launcherInstalled = true;
    return CockpitInstalledRuntime(
      paths: paths,
      release: release,
      executable: executable,
      resources: resources,
    );
  } finally {
    if (!launcherInstalled && await release.exists()) {
      await release.delete(recursive: true);
    }
  }
}

Future<Directory> _createReleaseDirectory(Directory releases) async {
  final base =
      'r${DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36)}-$pid';
  for (var attempt = 0; attempt < 100; attempt += 1) {
    final name = attempt == 0 ? base : '$base-$attempt';
    final candidate = Directory.fromUri(releases.uri.resolve('$name/'));
    if (await candidate.exists()) continue;
    return candidate.create();
  }
  throw FileSystemException(
    'Unable to allocate a Cockpit runtime release directory.',
    releases.path,
  );
}

Future<void> _replaceLaunchers(
  Map<File, String> launchers, {
  required bool windows,
}) async {
  final suffix = '$pid-${DateTime.now().microsecondsSinceEpoch}';
  final staged = <String, File>{};
  final backups = <String, File>{};
  final installed = <String>{};
  var committed = false;
  try {
    for (final launcher in launchers.entries) {
      await launcher.key.parent.create(recursive: true);
      final candidate = File('${launcher.key.path}.install-$suffix');
      await candidate.writeAsString(launcher.value, flush: true);
      if (!windows) await _makeExecutable(candidate);
      staged[launcher.key.path] = candidate;
    }

    try {
      for (final launcher in launchers.keys) {
        if (!await launcher.exists()) continue;
        final backup = File('${launcher.path}.backup-$suffix');
        await launcher.rename(backup.path);
        backups[launcher.path] = backup;
      }
      for (final launcher in launchers.keys) {
        await staged[launcher.path]!.rename(launcher.path);
        installed.add(launcher.path);
      }
      committed = true;
    } on Object {
      for (final path in installed) {
        final launcher = File(path);
        if (await launcher.exists()) await launcher.delete();
      }
      for (final backup in backups.entries) {
        final launcher = File(backup.key);
        if (!await launcher.exists() && await backup.value.exists()) {
          await backup.value.rename(launcher.path);
        }
      }
      rethrow;
    }

    for (final backup in backups.values) {
      if (!await backup.exists()) continue;
      try {
        await backup.delete();
      } on FileSystemException {
        // The launchers are already committed. A later install removes the
        // bounded sibling backup without invalidating the active runtime.
      }
    }
  } finally {
    for (final candidate in staged.values) {
      if (await candidate.exists()) await candidate.delete();
    }
    if (!committed) {
      for (final backup in backups.entries) {
        final launcher = File(backup.key);
        if (!await launcher.exists() && await backup.value.exists()) {
          await backup.value.rename(launcher.path);
        }
      }
    }
  }
}

Future<void> _makeExecutable(File file) async {
  final result = await Process.run('chmod', <String>['755', file.path]);
  if (result.exitCode != 0) {
    throw FileSystemException(
      'Unable to make the Cockpit runtime executable.',
      file.path,
    );
  }
}

String _resolvedPath(String path) {
  try {
    return File(path).resolveSymbolicLinksSync();
  } on FileSystemException {
    return p.normalize(p.absolute(path));
  }
}
