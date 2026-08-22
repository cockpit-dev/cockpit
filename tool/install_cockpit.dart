import 'dart:async';
import 'dart:io';

import 'package:cockpit/src/foundation/cockpit_version.dart';
import 'package:cockpit/src/infrastructure/cockpit_installed_runtime.dart';
import 'package:cockpit/src/infrastructure/cockpit_installed_runtime_cleanup.dart';
import 'package:cockpit/src/infrastructure/cockpit_runtime_resources.dart';

Future<void> main(List<String> arguments) async {
  try {
    final output = _outputPath(arguments);
    final root = File.fromUri(Platform.script).parent.parent;
    final entrypoint = File.fromUri(
      root.uri.resolve('packages/cockpit/bin/cockpit.dart'),
    );
    if (!await entrypoint.exists()) {
      throw FileSystemException(
        'Cockpit CLI entrypoint was not found.',
        entrypoint.path,
      );
    }
    if (output == null) {
      await _installManagedRuntime(root: root, entrypoint: entrypoint);
      return;
    }

    final destination = File(output);
    await destination.parent.create(recursive: true);
    final suffix = '$pid-${DateTime.now().microsecondsSinceEpoch}';
    final buildId =
        'src-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-$pid';
    final staging = File('${destination.path}.install-$suffix');
    final backup = File('${destination.path}.backup-$suffix');
    final resourceDestination = Directory(
      cockpitRuntimeResourceDirectoryPath(destination.path),
    );
    final resourceStaging = Directory(
      '${resourceDestination.path}.install-$suffix',
    );
    final resourceBackup = Directory(
      '${resourceDestination.path}.backup-$suffix',
    );

    try {
      final compiler = await Process.run(Platform.resolvedExecutable, <String>[
        'compile',
        'exe',
        '-DCOCKPIT_BUILD_ID=$buildId',
        entrypoint.path,
        '-o',
        staging.path,
      ], workingDirectory: root.path);
      if (compiler.exitCode != 0 || !await staging.exists()) {
        final details = '${compiler.stderr}'.trim();
        throw ProcessException(
          Platform.resolvedExecutable,
          <String>['compile', 'exe', entrypoint.path, '-o', staging.path],
          details.isEmpty ? 'Cockpit AOT compilation failed.' : details,
          compiler.exitCode,
        );
      }

      final payloadProbe = await Process.run(staging.path, const <String>[
        '--help',
      ]);
      if (payloadProbe.exitCode != 0) {
        throw ProcessException(
          staging.path,
          const <String>['--help'],
          'Compiled Cockpit executable did not start successfully.',
          payloadProbe.exitCode,
        );
      }

      await cockpitWriteRuntimeResources(
        packageRoot: Directory.fromUri(root.uri.resolve('packages/cockpit/')),
        destination: resourceStaging,
        version: cockpitVersion,
      );

      final replaced = await destination.exists();
      final resourcesReplaced = await resourceDestination.exists();
      if (replaced) await destination.rename(backup.path);
      if (resourcesReplaced) {
        await resourceDestination.rename(resourceBackup.path);
      }
      try {
        await staging.rename(destination.path);
        await resourceStaging.rename(resourceDestination.path);
        final probe = await Process.run(destination.path, const <String>[
          '--help',
        ]);
        if (probe.exitCode != 0 ||
            !await cockpitHasValidRuntimeResources(
              executablePath: destination.path,
              version: cockpitVersion,
            )) {
          throw ProcessException(
            destination.path,
            const <String>['--help'],
            'Installed Cockpit executable or runtime resources could not be verified.',
            probe.exitCode,
          );
        }
      } on Object {
        if (await destination.exists()) await destination.delete();
        if (await resourceDestination.exists()) {
          await resourceDestination.delete(recursive: true);
        }
        if (replaced && await backup.exists()) {
          await backup.rename(destination.path);
        }
        if (resourcesReplaced && await resourceBackup.exists()) {
          await resourceBackup.rename(resourceDestination.path);
        }
        rethrow;
      }
      if (await backup.exists()) await backup.delete();
      if (await resourceBackup.exists()) {
        await resourceBackup.delete(recursive: true);
      }
      stdout.writeln(destination.path);
    } finally {
      if (await staging.exists()) await staging.delete();
      if (await resourceStaging.exists()) {
        await resourceStaging.delete(recursive: true);
      }
      if (await backup.exists() && !await destination.exists()) {
        await backup.rename(destination.path);
      }
      if (await resourceBackup.exists() &&
          !await resourceDestination.exists()) {
        await resourceBackup.rename(resourceDestination.path);
      }
    }
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
  } on Object catch (error) {
    stderr.writeln('Cockpit installation failed: $error');
    exitCode = 1;
  }
}

Future<void> _installManagedRuntime({
  required Directory root,
  required File entrypoint,
}) async {
  final pubCachePath = cockpitPubCacheRoot(
    Platform.environment,
    windows: Platform.isWindows,
  );
  if (pubCachePath == null) {
    throw const FormatException(
      'Unable to locate the Pub cache; pass --output PATH.',
    );
  }
  final paths = CockpitInstalledRuntimePaths(
    pubCacheRoot: pubCachePath,
    windows: Platform.isWindows,
  );
  await paths.root.create(recursive: true);
  final suffix = '$pid-${DateTime.now().microsecondsSinceEpoch}';
  final workspace = await Directory.fromUri(
    paths.root.uri.resolve('.install-$suffix/'),
  ).create();
  final executable = File.fromUri(workspace.uri.resolve(paths.executableName));
  final resources = Directory.fromUri(
    workspace.uri.resolve('cockpit-resources/'),
  );
  final buildId =
      'src-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-$pid';
  try {
    final compiler = await Process.run(Platform.resolvedExecutable, <String>[
      'compile',
      'exe',
      '-DCOCKPIT_BUILD_ID=$buildId',
      entrypoint.path,
      '-o',
      executable.path,
    ], workingDirectory: root.path);
    if (compiler.exitCode != 0 || !await executable.exists()) {
      final details = '${compiler.stderr}'.trim();
      throw ProcessException(
        Platform.resolvedExecutable,
        <String>['compile', 'exe', entrypoint.path, '-o', executable.path],
        details.isEmpty ? 'Cockpit AOT compilation failed.' : details,
        compiler.exitCode,
      );
    }
    await cockpitWriteRuntimeResources(
      packageRoot: Directory.fromUri(root.uri.resolve('packages/cockpit/')),
      destination: resources,
      version: cockpitVersion,
    );
    final installed = await cockpitInstallRuntimeRelease(
      environment: Platform.environment,
      windows: Platform.isWindows,
      stagedExecutable: executable,
      stagedResources: resources,
      version: cockpitVersion,
      verify: (candidate) => _verifyManagedRuntime(candidate),
    );
    await cockpitCleanupInstalledRuntime(installed);
    await _deleteLegacyPayload(paths.pubCache);
    stdout.writeln(paths.launcher.path);
  } finally {
    if (await workspace.exists()) await workspace.delete(recursive: true);
  }
}

Future<void> _verifyManagedRuntime(File executable) async {
  final probe = await Process.run(
    executable.path,
    const <String>['--version'],
  ).timeout(const Duration(seconds: 10));
  if (probe.exitCode != 0 ||
      '${probe.stdout}'.trim() != 'cockpit $cockpitVersion') {
    throw ProcessException(
      executable.path,
      const <String>['--version'],
      'Installed Cockpit executable returned an invalid version.',
      probe.exitCode,
    );
  }
}

Future<void> _deleteLegacyPayload(Directory pubCache) async {
  final legacy = Directory.fromUri(pubCache.uri.resolve('cockpit-aot/'));
  if (await legacy.exists()) await legacy.delete(recursive: true);
}

String? _outputPath(List<String> arguments) {
  if (arguments.length == 2 && arguments.first == '--output') {
    final value = arguments.last.trim();
    if (value.isEmpty) {
      throw const FormatException('--output must not be empty.');
    }
    return File(value).absolute.path;
  }
  if (arguments.isNotEmpty) {
    throw const FormatException(
      'Usage: dart run tool/install_cockpit.dart [--output PATH]',
    );
  }
  return null;
}
