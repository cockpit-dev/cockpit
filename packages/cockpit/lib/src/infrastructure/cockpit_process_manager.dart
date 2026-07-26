import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:process/process.dart';

import 'cockpit_process_output_collector.dart';

const Set<String> _cockpitMinimumChildEnvironmentNames = <String>{
  'PATH',
  'HOME',
  'USERPROFILE',
  'TMPDIR',
  'TMP',
  'TEMP',
  'SystemDrive',
  'SystemRoot',
  'WINDIR',
  'LANG',
  'LC_ALL',
  'DISPLAY',
  'XAUTHORITY',
  'DBUS_SESSION_BUS_ADDRESS',
  'WAYLAND_DISPLAY',
  'XDG_RUNTIME_DIR',
  'XDG_SESSION_TYPE',
  'XDG_CURRENT_DESKTOP',
  'CHROME_EXECUTABLE',
  'FLUTTER_ROOT',
  'PUB_CACHE',
  'ANDROID_HOME',
  'ANDROID_SDK_ROOT',
  'JAVA_HOME',
  'DEVELOPER_DIR',
  'Path',
  'ProgramFiles',
  'ProgramFiles(x86)',
  'ProgramW6432',
  'ProgramData',
  'CommonProgramFiles',
  'CommonProgramFiles(x86)',
  'CommonProgramW6432',
  'ALLUSERSPROFILE',
  'APPDATA',
  'LOCALAPPDATA',
  'COMSPEC',
  'PATHEXT',
  'USERNAME',
  'USERDOMAIN',
  'HOMEDRIVE',
  'HOMEPATH',
  'PROCESSOR_ARCHITECTURE',
  'OS',
  'PUBLIC',
};

const Set<String> _cockpitWindowsToolchainEnvironmentNames = <String>{
  'CommandPromptType',
  'DevEnvDir',
  'ExtensionSdkDir',
  'EXTERNAL_INCLUDE',
  'Framework40Version',
  'FrameworkDir',
  'FrameworkDir64',
  'FrameworkVersion',
  'FrameworkVersion64',
  'IFCPATH',
  'INCLUDE',
  'LIB',
  'LIBPATH',
  'NETFXSDKDir',
  'Platform',
  'UCRTVersion',
  'UniversalCRTSdkDir',
  'VCIDEInstallDir',
  'VCINSTALLDIR',
  'VCToolsInstallDir',
  'VCToolsRedistDir',
  'VCToolsVersion',
  'VisualStudioVersion',
  'VSCMD_ARG_app_plat',
  'VSCMD_ARG_HOST_ARCH',
  'VSCMD_ARG_TGT_ARCH',
  'VSCMD_VER',
  'VSINSTALLDIR',
  'WindowsLibPath',
  'WindowsSdkBinPath',
  'WindowsSdkDir',
  'WindowsSDKLibVersion',
  'WindowsSdkVerBinPath',
  'WindowsSDKVersion',
  'WindowsSDK_ExecutablePath_x64',
  'WindowsSDK_ExecutablePath_x86',
};

Map<String, String> cockpitMinimumChildEnvironment({
  Map<String, String>? environment,
  Map<String, String>? parentEnvironment,
  bool? windows,
}) {
  final parent = parentEnvironment ?? Platform.environment;
  final useWindowsSemantics = windows ?? Platform.isWindows;
  final allowedWindowsNames = useWindowsSemantics
      ? <String>{
          ..._cockpitMinimumChildEnvironmentNames,
          ..._cockpitWindowsToolchainEnvironmentNames,
        }.map((name) => name.toLowerCase()).toSet()
      : const <String>{};
  final result = <String, String>{};

  void add(String name, String value) {
    if (useWindowsSemantics) {
      String? duplicate;
      for (final existing in result.keys) {
        if (existing.toLowerCase() == name.toLowerCase()) {
          duplicate = existing;
          break;
        }
      }
      if (duplicate != null) result.remove(duplicate);
    }
    result[name] = value;
  }

  for (final entry in parent.entries) {
    final allowed = useWindowsSemantics
        ? allowedWindowsNames.contains(entry.key.toLowerCase())
        : _cockpitMinimumChildEnvironmentNames.contains(entry.key);
    if (allowed) add(entry.key, entry.value);
  }
  for (final entry in environment?.entries ?? const Iterable.empty()) {
    add(entry.key, entry.value);
  }
  return result;
}

Future<Process> cockpitStartIsolatedProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool runInShell = false,
  ProcessStartMode mode = ProcessStartMode.normal,
}) {
  return Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: cockpitMinimumChildEnvironment(environment: environment),
    includeParentEnvironment: false,
    runInShell: runInShell,
    mode: mode,
  );
}

Future<ProcessResult> cockpitRunIsolatedProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool runInShell = false,
  Encoding? stdoutEncoding = systemEncoding,
  Encoding? stderrEncoding = systemEncoding,
}) {
  return Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: cockpitMinimumChildEnvironment(environment: environment),
    includeParentEnvironment: false,
    runInShell: runInShell,
    stdoutEncoding: stdoutEncoding,
    stderrEncoding: stderrEncoding,
  );
}

abstract interface class CockpitProcessManager {
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  });

  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  });
}

final class CockpitManagedProcessTimeoutException implements TimeoutException {
  const CockpitManagedProcessTimeoutException({
    required this.executable,
    required this.arguments,
    required this.stdout,
    required this.stderr,
    required Duration timeout,
  }) : duration = timeout,
       message = 'Managed process timed out.';

  final String executable;
  final List<String> arguments;
  final String stdout;
  final String stderr;

  @override
  final String message;

  @override
  final Duration duration;

  @override
  String toString() =>
      'TimeoutException after ${duration.inMilliseconds}ms: '
      '$executable ${arguments.join(' ')}';
}

final class LocalCockpitProcessManager implements CockpitProcessManager {
  const LocalCockpitProcessManager({
    ProcessManager processManager = const LocalProcessManager(),
  }) : _processManager = processManager;

  final ProcessManager _processManager;

  bool get usesHostProcessManager => _processManager is LocalProcessManager;

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) {
    return _processManager.run(
      <Object>[executable, ...arguments],
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: runInShell,
      stdoutEncoding: stdoutEncoding,
      stderrEncoding: stderrEncoding,
    );
  }

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) {
    return _processManager.start(
      <Object>[executable, ...arguments],
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: runInShell,
      mode: mode,
    );
  }
}

Future<ProcessResult> cockpitRunManagedProcessWithTimeout(
  CockpitProcessManager processManager,
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final process = await processManager.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  final stdoutCollector = CockpitProcessOutputCollector(process.stdout);
  final stderrCollector = CockpitProcessOutputCollector(process.stderr);
  try {
    final exitCode = await process.exitCode.timeout(timeout);
    final output = await Future.wait(<Future<String>>[
      stdoutCollector.collectText(),
      stderrCollector.collectText(),
    ]);
    return ProcessResult(process.pid, exitCode, output[0], output[1]);
  } on TimeoutException {
    if (process.pid != 0) {
      if (processManager case final LocalCockpitProcessManager manager
          when manager.usesHostProcessManager) {
        await cockpitKillLocalProcessDescendants(process.pid);
      }
      process.kill(ProcessSignal.sigkill);
    }
    await process.exitCode.timeout(
      const Duration(milliseconds: 500),
      onTimeout: () => -1,
    );
    final output = await Future.wait(<Future<String>>[
      stdoutCollector.collectText(),
      stderrCollector.collectText(),
    ]);
    throw CockpitManagedProcessTimeoutException(
      executable: executable,
      arguments: List<String>.unmodifiable(arguments),
      stdout: output[0],
      stderr: output[1],
      timeout: timeout,
    );
  } finally {
    await Future.wait(<Future<void>>[
      stdoutCollector.cancel(),
      stderrCollector.cancel(),
    ]);
  }
}

Future<void> cockpitKillLocalProcessDescendants(int rootPid) async {
  if (rootPid <= 1) return;
  try {
    if (Platform.isWindows) {
      await Process.run(
        'taskkill',
        <String>['/PID', '$rootPid', '/T', '/F'],
        environment: cockpitMinimumChildEnvironment(),
        includeParentEnvironment: false,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(const Duration(milliseconds: 800));
      return;
    }

    final result = await Process.run(
      'ps',
      const <String>['-axo', 'pid=,ppid='],
      environment: cockpitMinimumChildEnvironment(),
      includeParentEnvironment: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    ).timeout(const Duration(milliseconds: 800));
    final descendants = cockpitProcessDescendantsFromPs(
      '${result.stdout}',
      rootPid,
    );
    for (final pid in descendants.toList().reversed) {
      if (pid > 0 && pid != rootPid) {
        Process.killPid(pid, ProcessSignal.sigkill);
      }
    }
  } on Object {
    // Timeout cleanup is best-effort. The direct process is still killed by the
    // caller, and the original timeout remains the reported failure.
  }
}

List<int> cockpitProcessDescendantsFromPs(String psOutput, int rootPid) {
  final childrenByParent = <int, List<int>>{};
  for (final line in const LineSplitter().convert(psOutput)) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) continue;
    final pid = int.tryParse(parts[0]);
    final parentPid = int.tryParse(parts[1]);
    if (pid == null || parentPid == null || pid == rootPid) continue;
    childrenByParent.putIfAbsent(parentPid, () => <int>[]).add(pid);
  }

  final descendants = <int>[];
  final pending = <int>[rootPid];
  final seen = <int>{rootPid};
  while (pending.isNotEmpty) {
    final parent = pending.removeLast();
    for (final child in childrenByParent[parent] ?? const <int>[]) {
      if (!seen.add(child)) continue;
      descendants.add(child);
      pending.add(child);
    }
  }
  return descendants;
}
