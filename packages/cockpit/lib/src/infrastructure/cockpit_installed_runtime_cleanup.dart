import 'dart:async';
import 'dart:io';

import '../foundation/cockpit_internal_process.dart';
import '../foundation/cockpit_version.dart';
import 'cockpit_installed_runtime.dart';
import 'cockpit_runtime_resources.dart';

Future<String?> cockpitPrepareInstalledRuntime({
  Map<String, String>? environment,
  bool? windows,
  String? resolvedExecutable,
  required String version,
  CockpitInstalledRuntimeVerifier? verify,
}) async {
  final effectiveEnvironment = environment ?? Platform.environment;
  final effectiveWindows = windows ?? Platform.isWindows;
  final current = File(
    resolvedExecutable ?? Platform.resolvedExecutable,
  ).absolute;
  final canonical = await cockpitReadCanonicalInstalledRuntime(
    environment: effectiveEnvironment,
    windows: effectiveWindows,
    resolvedExecutable: current.path,
    version: version,
  );
  if (canonical != null) {
    cockpitUseCurrentExecutable(canonical.executable.path);
    await cockpitCleanupInstalledRuntime(canonical);
    return canonical.executable.path;
  }

  final pubCache = cockpitPubCacheRoot(
    effectiveEnvironment,
    windows: effectiveWindows,
  );
  if (pubCache == null) return null;
  final paths = CockpitInstalledRuntimePaths(
    pubCacheRoot: pubCache,
    windows: effectiveWindows,
  );
  if (!cockpitPathsMatch(
        current.path,
        paths.legacyNative.path,
        windows: effectiveWindows,
      ) ||
      !await current.exists()) {
    return null;
  }
  final active = await cockpitFindActiveInstalledRuntime(
    environment: effectiveEnvironment,
    windows: effectiveWindows,
    version: version,
    allowLegacyNative: true,
  );
  if (active != null) {
    cockpitUseCurrentExecutable(active.executable.path);
    await cockpitCleanupInstalledRuntime(active);
    return active.executable.path;
  }

  final legacyResources = Directory(
    cockpitRuntimeResourceDirectoryPath(
      current.path,
      windows: effectiveWindows,
    ),
  );
  if (!await cockpitHasValidRuntimeResourceDirectory(
    legacyResources,
    version: version,
  )) {
    throw FileSystemException(
      'The legacy Cockpit runtime resources are invalid.',
      legacyResources.path,
    );
  }

  await paths.root.create(recursive: true);
  final workspace = await Directory.fromUri(
    paths.root.uri.resolve(
      '.migrate-$pid-${DateTime.now().microsecondsSinceEpoch}/',
    ),
  ).create();
  final stagedExecutable = File.fromUri(
    workspace.uri.resolve(paths.executableName),
  );
  final stagedResources = Directory.fromUri(
    workspace.uri.resolve('cockpit-resources/'),
  );
  try {
    await current.copy(stagedExecutable.path);
    await _copyDirectory(legacyResources, stagedResources);
    final installed = await cockpitInstallRuntimeRelease(
      environment: effectiveEnvironment,
      windows: effectiveWindows,
      stagedExecutable: stagedExecutable,
      stagedResources: stagedResources,
      version: version,
      verify: verify ?? (executable) => _verifyVersion(executable, version),
    );
    cockpitUseCurrentExecutable(installed.executable.path);
    await cockpitCleanupInstalledRuntime(installed);
    return installed.executable.path;
  } finally {
    if (await workspace.exists()) await workspace.delete(recursive: true);
  }
}

Future<int> runCockpitInstalledRuntimeCleanup(List<String> arguments) async {
  if (arguments.length != 1) return 64;
  final activePath = File(arguments.single).absolute.path;
  final active = await cockpitReadCanonicalInstalledRuntime(
    environment: Platform.environment,
    windows: Platform.isWindows,
    resolvedExecutable: activePath,
    version: cockpitVersion,
    allowLegacyNative: true,
  );
  if (active == null) return 64;
  final deadline = DateTime.now().add(const Duration(minutes: 5));
  while (true) {
    final pending = await _cleanupRuntime(active);
    if (!pending) return 0;
    if (DateTime.now().isAfter(deadline)) return 1;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<void> cockpitCleanupInstalledRuntime(
  CockpitInstalledRuntime active,
) async {
  if (!await _cleanupRuntime(active)) return;
  await Process.start(active.executable.path, <String>[
    cockpitInternalRuntimeCleanupCommand,
    active.executable.path,
  ], mode: ProcessStartMode.detached);
}

Future<bool> _cleanupRuntime(CockpitInstalledRuntime active) async {
  var pending = false;
  if (active.paths.windows) {
    final legacyPending = await _deleteFile(active.paths.legacyNative);
    pending |= legacyPending;
    if (!legacyPending) {
      final legacyResources = Directory(
        cockpitRuntimeResourceDirectoryPath(
          active.paths.legacyNative.path,
          windows: true,
        ),
      );
      pending |= await _deleteDirectory(legacyResources);
    }
  } else {
    final legacyResources = Directory(
      cockpitRuntimeResourceDirectoryPath(
        active.paths.legacyNative.path,
        windows: false,
      ),
    );
    pending |= await _deleteDirectory(legacyResources);
  }
  if (await active.paths.releases.exists()) {
    await for (final entity in active.paths.releases.list(followLinks: false)) {
      if (entity is! Directory ||
          cockpitPathsMatch(
            entity.path,
            active.release.path,
            windows: active.paths.windows,
          )) {
        continue;
      }
      pending |= await _deleteDirectory(entity);
    }
  }
  if (await active.paths.launcher.parent.exists()) {
    final launcherNames = active.paths.launchers.values
        .map(
          (launcher) => launcher.uri.pathSegments.lastWhere(
            (segment) => segment.isNotEmpty,
          ),
        )
        .toList(growable: false);
    await for (final entity in active.paths.launcher.parent.list(
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.lastWhere(
        (segment) => segment.isNotEmpty,
      );
      if (launcherNames.any(
        (launcherName) =>
            name.startsWith('$launcherName.install-') ||
            name.startsWith('$launcherName.backup-'),
      )) {
        pending |= await _deleteFile(entity);
      }
    }
  }
  return pending;
}

Future<bool> _deleteFile(File file) async {
  if (!await file.exists()) return false;
  try {
    await file.delete();
    return false;
  } on FileSystemException {
    return true;
  }
}

Future<bool> _deleteDirectory(Directory directory) async {
  if (!await directory.exists()) return false;
  try {
    await directory.delete(recursive: true);
    return false;
  } on FileSystemException {
    return true;
  }
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(followLinks: false)) {
    final name = entity.uri.pathSegments.lastWhere(
      (segment) => segment.isNotEmpty,
    );
    if (entity is File) {
      await entity.copy(File.fromUri(destination.uri.resolve(name)).path);
    } else if (entity is Directory) {
      await _copyDirectory(
        entity,
        Directory.fromUri(destination.uri.resolve('$name/')),
      );
    } else {
      throw FileSystemException(
        'Cockpit runtime resources contain an unsupported filesystem entry.',
        entity.path,
      );
    }
  }
}

Future<void> _verifyVersion(File executable, String expected) async {
  final result = await Process.run(executable.path, const <String>[
    '--version',
  ]).timeout(const Duration(seconds: 10));
  if (result.exitCode != 0 ||
      '${result.stdout}'.trim() != 'cockpit $expected') {
    throw FileSystemException(
      'The migrated Cockpit runtime returned an invalid version.',
      executable.path,
    );
  }
}
