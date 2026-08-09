import 'dart:io';

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

    final destination = File(output);
    await destination.parent.create(recursive: true);
    final usesLauncher = arguments.isEmpty && !Platform.isWindows;
    final payload = usesLauncher
        ? File.fromUri(
            destination.parent.parent.uri.resolve('cockpit-aot/cockpit'),
          )
        : destination;
    await payload.parent.create(recursive: true);
    final suffix = '$pid-${DateTime.now().microsecondsSinceEpoch}';
    final payloadStaging = File('${payload.path}.install-$suffix');
    final payloadBackup = File('${payload.path}.backup-$suffix');
    final launcherStaging = usesLauncher
        ? File('${destination.path}.install-$suffix')
        : null;
    final launcherBackup = usesLauncher
        ? File('${destination.path}.backup-$suffix')
        : null;

    try {
      final compiler = await Process.run(Platform.resolvedExecutable, <String>[
        'compile',
        'exe',
        entrypoint.path,
        '-o',
        payloadStaging.path,
      ], workingDirectory: root.path);
      if (compiler.exitCode != 0 || !await payloadStaging.exists()) {
        final details = '${compiler.stderr}'.trim();
        throw ProcessException(
          Platform.resolvedExecutable,
          <String>[
            'compile',
            'exe',
            entrypoint.path,
            '-o',
            payloadStaging.path,
          ],
          details.isEmpty ? 'Cockpit AOT compilation failed.' : details,
          compiler.exitCode,
        );
      }

      final payloadProbe = await Process.run(
        payloadStaging.path,
        const <String>['--help'],
      );
      if (payloadProbe.exitCode != 0) {
        throw ProcessException(
          payloadStaging.path,
          const <String>['--help'],
          'Compiled Cockpit executable did not start successfully.',
          payloadProbe.exitCode,
        );
      }

      if (launcherStaging != null) {
        await launcherStaging.writeAsString(
          _launcherScript(payload.path),
          flush: true,
        );
        final chmod = await Process.run('chmod', <String>[
          '755',
          launcherStaging.path,
        ]);
        if (chmod.exitCode != 0) {
          throw ProcessException(
            'chmod',
            <String>['755', launcherStaging.path],
            '${chmod.stderr}'.trim(),
            chmod.exitCode,
          );
        }
      }

      final replacedPayload = await payload.exists();
      final replacedLauncher =
          launcherBackup != null && await destination.exists();
      if (replacedPayload) await payload.rename(payloadBackup.path);
      if (replacedLauncher) {
        await destination.rename(launcherBackup.path);
      }
      try {
        await payloadStaging.rename(payload.path);
        if (launcherStaging != null) {
          await launcherStaging.rename(destination.path);
        }
        final probe = await Process.run(destination.path, const <String>[
          '--help',
        ]);
        if (probe.exitCode != 0) {
          throw ProcessException(
            destination.path,
            const <String>['--help'],
            'Installed Cockpit executable did not start successfully.',
            probe.exitCode,
          );
        }
      } on Object {
        if (launcherStaging != null && await destination.exists()) {
          await destination.delete();
        }
        if (await payload.exists()) await payload.delete();
        if (replacedPayload && await payloadBackup.exists()) {
          await payloadBackup.rename(payload.path);
        }
        if (replacedLauncher && await launcherBackup.exists()) {
          await launcherBackup.rename(destination.path);
        }
        rethrow;
      }
      if (await payloadBackup.exists()) await payloadBackup.delete();
      if (launcherBackup != null && await launcherBackup.exists()) {
        await launcherBackup.delete();
      }
      stdout.writeln(destination.path);
    } finally {
      if (await payloadStaging.exists()) await payloadStaging.delete();
      if (launcherStaging != null && await launcherStaging.exists()) {
        await launcherStaging.delete();
      }
      if (await payloadBackup.exists() && !await payload.exists()) {
        await payloadBackup.rename(payload.path);
      }
      if (launcherBackup != null &&
          await launcherBackup.exists() &&
          !await destination.exists()) {
        await launcherBackup.rename(destination.path);
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

String _launcherScript(String payloadPath) {
  final quoted = "'${payloadPath.replaceAll("'", "'\"'\"'")}'";
  return '#!/bin/sh\nexec $quoted "\$@"\n';
}

String _outputPath(List<String> arguments) {
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
  final environment = Platform.environment;
  final configured = environment['PUB_CACHE']?.trim();
  final home = environment[Platform.isWindows ? 'USERPROFILE' : 'HOME']?.trim();
  final localAppData = environment['LOCALAPPDATA']?.trim();
  final cache = configured != null && configured.isNotEmpty
      ? configured
      : Platform.isWindows
      ? localAppData == null || localAppData.isEmpty
            ? null
            : Directory(localAppData).uri.resolve('Pub/Cache/').toFilePath()
      : home == null || home.isEmpty
      ? null
      : Directory(home).uri.resolve('.pub-cache/').toFilePath();
  if (cache == null) {
    throw const FormatException(
      'Unable to locate the Pub cache; pass --output PATH.',
    );
  }
  final name = Platform.isWindows ? 'cockpit.exe' : 'cockpit';
  return Directory(cache).uri.resolve('bin/$name').toFilePath();
}
