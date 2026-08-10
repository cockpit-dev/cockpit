import 'dart:async';
import 'dart:io';

import '../infrastructure/cockpit_process_manager.dart';
import 'cockpit_android_remote_session_launcher.dart';
import 'cockpit_flutter_launch_configuration.dart';
import 'cockpit_remote_session_handle.dart';
import 'cockpit_remote_session_launch_options.dart';
import 'cockpit_remote_session_launcher.dart';
import 'cockpit_session_process_runner.dart';
import 'cockpit_session_path.dart';
import 'cockpit_windows_remote_session_launcher.dart';

typedef CockpitLinuxAppExecutablePathResolver =
    Future<String> Function({required String projectDir});

final class CockpitLinuxRemoteSessionLauncher
    implements CockpitRemoteSessionLauncher {
  CockpitLinuxRemoteSessionLauncher({
    CockpitWorkingDirectoryProcessRunner? processRunner,
    CockpitLinuxAppExecutablePathResolver appExecutablePathResolver =
        _resolveAppExecutablePath,
    CockpitDesktopAppStarter appStarter = _startDetachedProcess,
    CockpitRemoteSessionStatusReader statusReader =
        cockpitReadRemoteSessionStatus,
    CockpitFlutterVersionReader flutterVersionReader =
        cockpitReadActiveFlutterVersion,
    CockpitFlutterExecutableVersionReader? flutterVersionForExecutableReader,
    DateTime Function()? now,
  }) : _processRunner = processRunner ?? _runProcess,
       _useKillableProcessRunner = processRunner == null,
       _appExecutablePathResolver = appExecutablePathResolver,
       _appStarter = appStarter,
       _statusReader = statusReader,
       _flutterVersionReader = flutterVersionReader,
       _flutterVersionForExecutableReader =
           flutterVersionForExecutableReader ??
           ((flutterExecutable) => cockpitReadFlutterVersion(
             flutterExecutable,
             processRunner: (executable, arguments) =>
                 (processRunner ?? _runProcess)(executable, arguments),
           )),
       _now = now ?? DateTime.now;

  final CockpitWorkingDirectoryProcessRunner _processRunner;
  final bool _useKillableProcessRunner;
  final CockpitLinuxAppExecutablePathResolver _appExecutablePathResolver;
  final CockpitDesktopAppStarter _appStarter;
  final CockpitRemoteSessionStatusReader _statusReader;
  final CockpitFlutterVersionReader _flutterVersionReader;
  final CockpitFlutterExecutableVersionReader
  _flutterVersionForExecutableReader;
  final DateTime Function() _now;

  @override
  Future<CockpitRemoteSessionHandle> launch(
    CockpitRemoteSessionLaunchOptions options,
  ) async {
    if (options.platform != 'linux') {
      throw StateError(
        'CockpitLinuxRemoteSessionLauncher only supports linux options.',
      );
    }

    final deadline = _now().add(options.launchTimeout);
    final flutterExecutable =
        options.flutterExecutable ?? cockpitFlutterExecutable();
    final flutterVersion = await cockpitResolveFlutterVersionForLaunch(
      flutterExecutable: flutterExecutable,
      explicitFlutterVersion: options.flutterVersion,
      legacyFlutterVersionReader: options.flutterExecutable == null
          ? _flutterVersionReader
          : null,
      flutterVersionForExecutableReader: _flutterVersionForExecutableReader,
    );
    await _runRequired(
      flutterExecutable,
      <String>[
        'build',
        'linux',
        '--debug',
        '--target',
        options.target,
        ...cockpitBuildFlutterLaunchArguments(
          userConfiguration: options.launchConfiguration,
          internalArguments: cockpitBuildRemoteControlDartDefineArguments(
            host: '127.0.0.1',
            port: options.sessionPort,
            flutterVersion: flutterVersion,
            launchId: options.launchId,
          ),
        ),
      ],
      workingDirectory: options.projectDir,
      environment: options.launchConfiguration.processEnvironment,
      timeout: _remaining(deadline),
    );

    final executablePath = await _appExecutablePathResolver(
      projectDir: options.projectDir,
    );
    final executablePathContext = cockpitSessionPathContext(executablePath);
    final processId = await _appStarter(
      executablePath: executablePath,
      workingDirectory: executablePathContext.dirname(executablePath),
      environment:
          options.appEnvironment ??
          options.launchConfiguration.processEnvironment,
      timeout: _capTimeout(_remaining(deadline), const Duration(seconds: 10)),
    );

    final baseUri = Uri.parse('http://127.0.0.1:${options.sessionPort}');
    try {
      final status = await cockpitWaitForRemoteSessionReady(
        baseUri: baseUri,
        timeout: _remaining(deadline),
        statusReader: _statusReader,
        expectedSessionId: options.launchId,
        expectedPlatform: options.platform,
      );
      return CockpitRemoteSessionHandle.fromRemoteStatus(
        projectDir: options.projectDir,
        target: options.target,
        deviceId: options.deviceId,
        appId: executablePathContext.basename(executablePath),
        processId: processId,
        host: '127.0.0.1',
        hostPort: options.sessionPort,
        devicePort: options.sessionPort,
        status: status,
        launchedAt: _now(),
      );
    } on Object {
      _bestEffortKillLaunchedApp(processId);
      rethrow;
    }
  }

  void _bestEffortKillLaunchedApp(int? processId) {
    if (processId == null) {
      return;
    }
    try {
      Process.killPid(processId);
    } on Object {
      // Launch failure reporting takes priority over cleanup failures.
    }
  }

  Future<void> _runRequired(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    required Duration timeout,
  }) async {
    final result = _useKillableProcessRunner
        ? await cockpitRunProcessWithTimeout(
            executable,
            arguments,
            workingDirectory: workingDirectory,
            environment: environment,
            timeout: timeout,
          )
        : await _processRunner(
            executable,
            arguments,
            workingDirectory: workingDirectory,
            environment: environment,
          ).timeout(
            timeout,
            onTimeout: () => throw TimeoutException(
              '$executable ${arguments.join(' ')} timed out.',
              timeout,
            ),
          );
    if (result.exitCode != 0) {
      throw StateError(
        '$executable ${arguments.join(' ')} failed: ${result.stderr ?? result.stdout}',
      );
    }
  }

  Duration _remaining(DateTime deadline) {
    final remaining = deadline.difference(_now());
    if (remaining <= Duration.zero) {
      throw TimeoutException(
        'Linux remote session launch timed out before the next stage could start.',
      );
    }
    return remaining;
  }

  Duration _capTimeout(Duration value, Duration max) {
    return value < max ? value : max;
  }

  static Future<ProcessResult> _runProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    return cockpitRunShortProcess(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  }

  static Future<int?> _startDetachedProcess({
    required String executablePath,
    List<String> arguments = const <String>[],
    String? workingDirectory,
    Map<String, String>? environment,
    required Duration timeout,
  }) async {
    final process =
        await cockpitStartIsolatedProcess(
          executablePath,
          arguments,
          workingDirectory: workingDirectory,
          environment: environment,
          mode: ProcessStartMode.detached,
        ).timeout(
          timeout,
          onTimeout: () => throw TimeoutException(
            'Launching $executablePath timed out.',
            timeout,
          ),
        );
    return process.pid == 0 ? null : process.pid;
  }

  static Future<String> _resolveAppExecutablePath({
    required String projectDir,
  }) async {
    final pathContext = cockpitSessionPathContext(projectDir);
    final preferredBaseName = cockpitReadWorkspacePubspecName(projectDir);
    final outputDirectory = Directory(
      pathContext.join(projectDir, 'build', 'linux', 'x64', 'debug', 'bundle'),
    );
    if (!outputDirectory.existsSync()) {
      throw StateError(
        'Unable to locate Linux build output at ${outputDirectory.path}.',
      );
    }

    final candidates = <String>[];
    for (final entity in outputDirectory.listSync()) {
      if (entity is! File) {
        continue;
      }
      final entityPathContext = cockpitSessionPathContext(entity.path);
      final basename = entityPathContext.basename(entity.path);
      if (basename.contains('.')) {
        continue;
      }
      final mode = entity.statSync().mode;
      final executable =
          (mode & 0x40) != 0 || (mode & 0x08) != 0 || (mode & 0x01) != 0;
      if (executable) {
        candidates.add(entity.path);
      }
    }
    candidates.sort();
    if (candidates.isEmpty) {
      throw StateError(
        'Unable to locate a Linux executable in ${outputDirectory.path}.',
      );
    }
    if (preferredBaseName != null && preferredBaseName.isNotEmpty) {
      for (final candidate in candidates) {
        final candidateBaseName = pathContext.basename(candidate);
        if (candidateBaseName == preferredBaseName) {
          return candidate;
        }
      }
    }
    return candidates.first;
  }

  static Future<String?> resolveAppBaseName({
    required String projectDir,
  }) async {
    final executablePath = await _resolveAppExecutablePath(
      projectDir: projectDir,
    );
    final pathContext = cockpitSessionPathContext(executablePath);
    final baseName = pathContext.basename(executablePath).trim();
    return baseName.isEmpty ? null : baseName;
  }
}
