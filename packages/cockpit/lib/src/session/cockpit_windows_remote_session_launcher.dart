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

typedef CockpitWindowsAppExecutablePathResolver =
    Future<String> Function({required String projectDir});
typedef CockpitDesktopAppStarter =
    Future<int?> Function({
      required String executablePath,
      List<String> arguments,
      String? workingDirectory,
      Map<String, String>? environment,
      required Duration timeout,
    });

final class CockpitWindowsRemoteSessionLauncher
    implements CockpitRemoteSessionLauncher {
  CockpitWindowsRemoteSessionLauncher({
    CockpitWorkingDirectoryProcessRunner? processRunner,
    CockpitWindowsAppExecutablePathResolver appExecutablePathResolver =
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
  final CockpitWindowsAppExecutablePathResolver _appExecutablePathResolver;
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
    if (options.platform != 'windows') {
      throw StateError(
        'CockpitWindowsRemoteSessionLauncher only supports windows options.',
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
        'windows',
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
        appId: executablePathContext.basenameWithoutExtension(executablePath),
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
        'Windows remote session launch timed out before the next stage could start.',
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
      pathContext.join(
        projectDir,
        'build',
        'windows',
        'x64',
        'runner',
        'Debug',
      ),
    );
    if (!outputDirectory.existsSync()) {
      throw StateError(
        'Unable to locate Windows build output at ${outputDirectory.path}.',
      );
    }

    final executables =
        outputDirectory
            .listSync()
            .whereType<File>()
            .map((entry) => entry.path)
            .where((path) => path.toLowerCase().endsWith('.exe'))
            .toList()
          ..sort();
    if (executables.isEmpty) {
      throw StateError(
        'Unable to locate a Windows executable in ${outputDirectory.path}.',
      );
    }
    if (preferredBaseName != null && preferredBaseName.isNotEmpty) {
      for (final candidate in executables) {
        final candidateBaseName = pathContext.basenameWithoutExtension(
          candidate,
        );
        if (candidateBaseName == preferredBaseName) {
          return candidate;
        }
      }
    }
    return executables.first;
  }

  static Future<String?> resolveAppBaseName({
    required String projectDir,
  }) async {
    final executablePath = await _resolveAppExecutablePath(
      projectDir: projectDir,
    );
    final pathContext = cockpitSessionPathContext(executablePath);
    final baseName = pathContext
        .basenameWithoutExtension(executablePath)
        .trim();
    return baseName.isEmpty ? null : baseName;
  }
}
