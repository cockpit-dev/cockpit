import 'dart:convert';
import 'dart:io';

import '../foundation/cockpit_internal_process.dart';
import '../infrastructure/cockpit_runtime_resources.dart';
import 'cockpit_update_models.dart';
import 'cockpit_update_support.dart';

const String _updateWorkspacePrefix = 'cockpit-update-';

final class CockpitUpdateInstallation {
  CockpitUpdateInstallation._({
    required CockpitUpdateProcessRunner processRunner,
    required Map<String, String> environment,
    required bool windows,
    required String resolvedExecutable,
  }) : _processRunner = processRunner,
       _windows = windows,
       _resolvedExecutable = resolvedExecutable,
       _pubCacheRoot = cockpitPubCacheRoot(environment, windows: windows);

  static Future<CockpitUpdateInstallation> prepare({
    required CockpitUpdateProcessRunner processRunner,
    required Map<String, String> environment,
    required bool windows,
    required String resolvedExecutable,
  }) async {
    final installation = CockpitUpdateInstallation._(
      processRunner: processRunner,
      environment: environment,
      windows: windows,
      resolvedExecutable: resolvedExecutable,
    );
    await installation._preparePubBinTakeover();
    return installation;
  }

  final CockpitUpdateProcessRunner _processRunner;
  final bool _windows;
  final String _resolvedExecutable;
  final String? _pubCacheRoot;

  Directory? _workspace;
  File? _previousNative;
  File? _previousLauncher;
  File? _fallbackLauncher;
  File? _installedExecutable;
  bool _hostedAccepted = false;
  bool _aotInstalled = false;

  String? get executablePath => _installedExecutable?.path;

  Future<void> acceptHosted() async {
    _hostedAccepted = true;
  }

  Future<void> installHostedAot({
    required String version,
    required DateTime deadline,
  }) async {
    final pubCache = _pubCacheRoot;
    if (pubCache == null) {
      throw const CockpitUpdateException(
        'updateCompileFailed',
        'Cockpit was installed, but its Pub cache could not be located for '
            'AOT compilation.',
      );
    }
    final workspace = await _ensureWorkspace();
    final packageConfig = File.fromUri(
      Directory(
        pubCache,
      ).uri.resolve('global_packages/cockpit/.dart_tool/package_config.json'),
    );
    final entrypoint = await _activatedEntrypoint(packageConfig);
    final packageRoot = entrypoint.parent.parent;
    final staged = File.fromUri(
      workspace.uri.resolve(_windows ? 'cockpit-next.exe' : 'cockpit-next'),
    );
    final stagedResources = Directory.fromUri(
      workspace.uri.resolve('cockpit-resources-next/'),
    );
    final dart = _windows ? 'dart.exe' : 'dart';
    final compile = await _run(
      dart,
      <String>[
        'compile',
        'exe',
        '--packages=${packageConfig.path}',
        entrypoint.path,
        '-o',
        staged.path,
      ],
      deadline,
      code: 'updateCompileFailed',
      message: 'The hosted Cockpit release could not be compiled to AOT.',
    );
    _requireSuccess(
      compile,
      code: 'updateCompileFailed',
      message: 'The hosted Cockpit release could not be compiled to AOT.',
    );
    await _requireVersion(staged, version, deadline);
    await cockpitWriteRuntimeResources(
      packageRoot: packageRoot,
      destination: stagedResources,
      version: version,
    );
    await _installAot(staged, stagedResources, version, deadline);
    _aotInstalled = true;
  }

  Future<void> finish() async {
    final workspace = _workspace;
    if (workspace != null && await workspace.exists()) {
      try {
        await workspace.delete(recursive: true);
      } on FileSystemException {
        await _startDeferredCleanup(workspace);
      }
    }
    await _removeStaleWorkspaces(except: workspace?.path);
  }

  Future<void> abort() async {
    if (!_hostedAccepted) {
      await _restorePreviousInstallation();
    }
    try {
      await finish();
    } on Object {
      // Preserve the original update failure. A later update retries cleanup.
    }
  }

  Future<void> _preparePubBinTakeover() async {
    final pubCache = _pubCacheRoot;
    if (pubCache == null) return;
    final native = File.fromUri(
      Directory(
        pubCache,
      ).uri.resolve(_windows ? 'bin/cockpit.exe' : 'bin/cockpit'),
    );
    final ownsLegacyNative =
        cockpitPathsMatch(
          _resolvedExecutable,
          native.path,
          windows: _windows,
        ) &&
        await native.exists();
    final launcher = _windows
        ? File.fromUri(Directory(pubCache).uri.resolve('bin/cockpit.bat'))
        : native;
    if (!ownsLegacyNative) {
      if (!await launcher.exists()) return;
      final workspace = await _ensureWorkspace();
      final previousLauncher = File.fromUri(
        workspace.uri.resolve(
          _windows ? 'cockpit-previous.bat' : 'cockpit-previous-launcher',
        ),
      );
      await launcher.copy(previousLauncher.path);
      _previousLauncher = previousLauncher;
      return;
    }

    final workspace = await _ensureWorkspace();
    final previousNative = File.fromUri(
      workspace.uri.resolve(
        _windows ? 'cockpit-previous.exe' : 'cockpit-previous',
      ),
    );
    final fallback = File.fromUri(workspace.uri.resolve('cockpit-fallback'));
    await fallback.writeAsString(
      _windows
          ? _windowsFallback(previousNative.path)
          : _unixFallback(previousNative.path),
      flush: true,
    );
    if (!_windows) {
      final chmod = await Process.run('chmod', <String>['755', fallback.path]);
      if (chmod.exitCode != 0) {
        throw FileSystemException(
          'Unable to prepare the Cockpit update fallback launcher.',
          fallback.path,
        );
      }
    }

    File? previousLauncher;
    if (_windows && await launcher.exists()) {
      previousLauncher = File.fromUri(
        workspace.uri.resolve('cockpit-previous.bat'),
      );
      await launcher.copy(previousLauncher.path);
      await launcher.delete();
    }
    try {
      await native.rename(previousNative.path);
      await fallback.rename(launcher.path);
    } on Object {
      if (await previousNative.exists() && !await native.exists()) {
        await previousNative.rename(native.path);
      }
      if (previousLauncher != null &&
          await previousLauncher.exists() &&
          !await launcher.exists()) {
        await previousLauncher.rename(launcher.path);
      }
      rethrow;
    }
    _previousNative = previousNative;
    _previousLauncher = previousLauncher;
    _fallbackLauncher = launcher;
  }

  Future<File> _activatedEntrypoint(File packageConfig) async {
    if (!await packageConfig.exists()) {
      throw CockpitUpdateException(
        'updateCompileFailed',
        'The activated Cockpit package configuration was not found at '
            '${packageConfig.path}.',
      );
    }
    try {
      final decoded = jsonDecode(await packageConfig.readAsString());
      final root = (decoded as Map<String, Object?>)['packages'];
      final packages = root! as List<Object?>;
      final cockpit = packages.cast<Map<String, Object?>>().firstWhere(
        (entry) => entry['name'] == 'cockpit',
      );
      final rootUri = packageConfig.uri.resolve(cockpit['rootUri']! as String);
      final entrypoint = File.fromUri(
        Directory.fromUri(rootUri).uri.resolve('bin/cockpit.dart'),
      );
      if (!await entrypoint.exists()) {
        throw const FormatException('Cockpit entrypoint is missing.');
      }
      return entrypoint;
    } on CockpitUpdateException {
      rethrow;
    } on Object catch (error) {
      throw CockpitUpdateException(
        'updateCompileFailed',
        'The activated Cockpit package configuration is invalid. '
            '${cockpitBoundUpdateText('$error')}',
        retryable: false,
      );
    }
  }

  Future<void> _installAot(
    File staged,
    Directory stagedResources,
    String version,
    DateTime deadline,
  ) async {
    final installed = await cockpitInstallRuntimeRelease(
      environment: <String, String>{'PUB_CACHE': _pubCacheRoot!},
      windows: _windows,
      stagedExecutable: staged,
      stagedResources: stagedResources,
      version: version,
      verify: (executable) => _requireVersion(executable, version, deadline),
    );
    _installedExecutable = installed.executable;
  }

  Future<void> _requireVersion(
    File executable,
    String expected,
    DateTime deadline,
  ) async {
    final probe = await _run(
      executable.path,
      const <String>['--version'],
      deadline,
      code: 'updateVerificationFailed',
      message: 'The installed Cockpit executable could not be verified.',
    );
    _requireSuccess(
      probe,
      code: 'updateVerificationFailed',
      message: 'The installed Cockpit executable could not be verified.',
    );
    String actual;
    try {
      actual = cockpitReadInstalledVersion('${probe.stdout}');
    } on FormatException catch (error) {
      throw CockpitUpdateException(
        'updateVerificationFailed',
        error.message,
        retryable: false,
      );
    }
    if (actual != expected) {
      throw CockpitUpdateException(
        'updateVerificationFailed',
        'The installed Cockpit executable reported $actual instead of '
            '$expected.',
        retryable: false,
      );
    }
  }

  Future<ProcessResult> _run(
    String executable,
    List<String> arguments,
    DateTime deadline, {
    required String code,
    required String message,
  }) async {
    try {
      return await _processRunner(executable, arguments, _remaining(deadline));
    } on Object catch (error) {
      throw CockpitUpdateException(
        code,
        '$message ${cockpitBoundUpdateText('$error')}',
      );
    }
  }

  void _requireSuccess(
    ProcessResult result, {
    required String code,
    required String message,
  }) {
    if (result.exitCode == 0) return;
    final diagnostic = cockpitUpdateDiagnostic(result);
    throw CockpitUpdateException(
      code,
      diagnostic == null ? message : '$message $diagnostic',
    );
  }

  Future<void> _restorePreviousInstallation() async {
    final previousNative = _previousNative;
    final previousLauncher = _previousLauncher;
    final pubCache = _pubCacheRoot;
    if (pubCache == null ||
        (previousNative == null && previousLauncher == null)) {
      return;
    }
    final native = File.fromUri(
      Directory(
        pubCache,
      ).uri.resolve(_windows ? 'bin/cockpit.exe' : 'bin/cockpit'),
    );
    if (previousNative != null && await previousNative.exists()) {
      final fallback = _fallbackLauncher;
      if (fallback != null && await fallback.exists()) await fallback.delete();
      if (await native.exists()) await native.delete();
      try {
        await previousNative.rename(native.path);
      } on FileSystemException {
        if (fallback != null) {
          await fallback.writeAsString(
            _windows
                ? _windowsFallback(previousNative.path)
                : _unixFallback(previousNative.path),
            flush: true,
          );
          if (!_windows) {
            await Process.run('chmod', <String>['755', fallback.path]);
          }
        }
        return;
      }
    }
    if (previousLauncher != null && await previousLauncher.exists()) {
      final launcher = _windows
          ? File.fromUri(Directory(pubCache).uri.resolve('bin/cockpit.bat'))
          : native;
      if (await launcher.exists()) await launcher.delete();
      await previousLauncher.rename(launcher.path);
    }
  }

  Future<Directory> _ensureWorkspace() async {
    final current = _workspace;
    if (current != null) return current;
    final pubCache = _pubCacheRoot;
    final base = pubCache == null
        ? Directory.systemTemp
        : Directory.fromUri(Directory(pubCache).uri.resolve('_temp/'));
    await base.create(recursive: true);
    final created = await Directory.fromUri(
      base.uri.resolve(
        '$_updateWorkspacePrefix$pid-${DateTime.now().microsecondsSinceEpoch}/',
      ),
    ).create();
    _workspace = created;
    return created;
  }

  Future<void> _startDeferredCleanup(Directory workspace) async {
    final pubCache = _pubCacheRoot;
    if (!_aotInstalled || pubCache == null) {
      throw FileSystemException(
        'Cockpit update workspace could not be removed.',
        workspace.path,
      );
    }
    final executable = _installedExecutable;
    if (executable == null) {
      throw FileSystemException(
        'Cockpit update workspace could not be removed.',
        workspace.path,
      );
    }
    await Process.start(executable.path, <String>[
      cockpitInternalUpdateCleanupCommand,
      workspace.path,
    ], mode: ProcessStartMode.detached);
  }

  Future<void> _removeStaleWorkspaces({String? except}) async {
    final pubCache = _pubCacheRoot;
    if (pubCache == null) return;
    final temp = Directory.fromUri(Directory(pubCache).uri.resolve('_temp/'));
    if (!await temp.exists()) return;
    await for (final entity in temp.list(followLinks: false)) {
      if (entity is! Directory ||
          !entity.uri.pathSegments
              .lastWhere((segment) => segment.isNotEmpty)
              .startsWith(_updateWorkspacePrefix) ||
          (except != null &&
              cockpitPathsMatch(entity.path, except, windows: _windows))) {
        continue;
      }
      try {
        await entity.delete(recursive: true);
      } on FileSystemException {
        if (_aotInstalled) await _startDeferredCleanup(entity);
      }
    }
  }
}

Future<int> runCockpitUpdateCleanup(List<String> arguments) async {
  if (arguments.length != 1) return 64;
  final root = cockpitPubCacheRoot(
    Platform.environment,
    windows: Platform.isWindows,
  );
  if (root == null) return 64;
  final workspace = Directory(arguments.single).absolute;
  final temp = Directory.fromUri(Directory(root).uri.resolve('_temp/'));
  final name = workspace.uri.pathSegments.lastWhere(
    (segment) => segment.isNotEmpty,
    orElse: () => '',
  );
  if (!cockpitPathIsWithin(workspace.path, temp.path) ||
      !name.startsWith(_updateWorkspacePrefix)) {
    return 64;
  }
  final deadline = DateTime.now().add(const Duration(minutes: 5));
  while (await workspace.exists()) {
    try {
      await workspace.delete(recursive: true);
    } on FileSystemException {
      if (DateTime.now().isAfter(deadline)) return 1;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
  return 0;
}

Duration _remaining(DateTime deadline) {
  final remaining = deadline.difference(DateTime.now().toUtc());
  if (remaining <= Duration.zero) {
    throw const CockpitUpdateException(
      'updateTimeout',
      'Cockpit update exceeded its timeout.',
    );
  }
  return remaining;
}

String _unixFallback(String executable) {
  final quoted = "'${executable.replaceAll("'", "'\"'\"'")}'";
  return '#!/usr/bin/env sh\n'
      '# This file was created by Cockpit update handoff.\n'
      '# Package: cockpit\n'
      '# Executable: cockpit\n'
      'exec $quoted "\$@"\n';
}

String _windowsFallback(String executable) {
  final quoted = '"${executable.replaceAll('"', '""')}"';
  return '@echo off\r\n'
      'rem This file was created by Cockpit update handoff.\r\n'
      'rem Package: cockpit\r\n'
      'rem Executable: cockpit\r\n'
      '$quoted %*\r\n';
}
