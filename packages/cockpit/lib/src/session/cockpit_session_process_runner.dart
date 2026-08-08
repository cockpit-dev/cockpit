import 'dart:async';
import 'dart:io';

import '../infrastructure/cockpit_process_output_collector.dart';
import '../infrastructure/cockpit_process_manager.dart';

Future<ProcessResult> cockpitRunProcessWithTimeout(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  required Duration timeout,
}) async {
  final process = await cockpitStartIsolatedProcess(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    runInShell: cockpitShouldRunExecutableInShell(executable),
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
    try {
      await _killProcessTree(process);
    } finally {
      await Future.wait(<Future<void>>[
        stdoutCollector.cancel(),
        stderrCollector.cancel(),
      ]);
    }
    throw TimeoutException(
      '$executable ${arguments.join(' ')} timed out.',
      timeout,
    );
  }
}

bool cockpitShouldRunExecutableInShell(String executable) {
  if (!Platform.isWindows) {
    return false;
  }
  final lower = executable.toLowerCase();
  return lower.endsWith('.bat') || lower.endsWith('.cmd');
}

Future<ProcessResult> cockpitRunShortProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) {
  return cockpitRunProcessWithTimeout(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    timeout: const Duration(seconds: 30),
  );
}

Future<void> _killProcessTree(Process process) async {
  if (Platform.isWindows) {
    try {
      await _runKillHelperProcess('taskkill', <String>[
        '/PID',
        '${process.pid}',
        '/T',
        '/F',
      ], timeout: const Duration(seconds: 5));
    } on Object {
      // Fall back to direct process termination below.
    }
    process.kill(ProcessSignal.sigkill);
    await process.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () => -1,
    );
    return;
  }

  final rootPid = process.pid;
  var descendants = const <int>[];
  if (rootPid > 0) {
    try {
      process.kill(ProcessSignal.sigstop);
    } on Object {
      // The process may already have exited.
    }
    descendants = await _collectProcessDescendants(rootPid);
  }
  process.kill(ProcessSignal.sigkill);
  for (final pid in descendants.reversed) {
    try {
      Process.killPid(pid, ProcessSignal.sigkill);
    } on Object {
      // The process may already have exited.
    }
  }
  await _waitForProcessTreeExit(process, descendants);
}

Future<void> _waitForProcessTreeExit(
  Process process,
  List<int> descendants,
) async {
  final tracked = <int>{process.pid, ...descendants}
    ..removeWhere((pid) => pid <= 0);
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (tracked.isNotEmpty && DateTime.now().isBefore(deadline)) {
    final live = await _liveProcessIds(tracked);
    if (live.isEmpty) break;
    for (final pid in live) {
      try {
        Process.killPid(pid, ProcessSignal.sigkill);
      } on Object {
        // The process may already have exited.
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  final remaining = await _liveProcessIds(tracked);
  if (remaining.isNotEmpty) {
    for (final pid in remaining) {
      try {
        Process.killPid(pid, ProcessSignal.sigkill);
      } on Object {
        // Preserve the cleanup failure below with every remaining PID.
      }
    }
    throw StateError(
      'Timed-out process tree did not terminate: '
      '${remaining.toList()..sort()}.',
    );
  }
  await process.exitCode.timeout(
    const Duration(seconds: 2),
    onTimeout: () => -1,
  );
}

Future<List<int>> _collectProcessDescendants(int parentPid) async {
  try {
    final result = await _runKillHelperProcess('ps', const <String>[
      '-axo',
      'pid=,ppid=',
    ], timeout: const Duration(seconds: 5));
    if (result.exitCode != 0) {
      return const <int>[];
    }
    return cockpitProcessDescendantsFromPs('${result.stdout}', parentPid);
  } on Object {
    return const <int>[];
  }
}

Future<Set<int>> _liveProcessIds(Set<int> processIds) async {
  if (processIds.isEmpty) return const <int>{};
  try {
    final result = await _runKillHelperProcess('ps', const <String>[
      '-axo',
      'pid=,stat=',
    ], timeout: const Duration(seconds: 2));
    if (result.exitCode != 0) return processIds;
    final live = <int>{};
    for (final line in '${result.stdout}'.split('\n')) {
      final match = RegExp(r'^\s*(\d+)\s+(\S+)').firstMatch(line);
      if (match == null) continue;
      final pid = int.parse(match.group(1)!);
      if (processIds.contains(pid) && !match.group(2)!.startsWith('Z')) {
        live.add(pid);
      }
    }
    return live;
  } on Object {
    return processIds;
  }
}

Future<ProcessResult> _runKillHelperProcess(
  String executable,
  List<String> arguments, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final process = await cockpitStartIsolatedProcess(executable, arguments);
  final stdoutCollector = CockpitProcessOutputCollector(process.stdout);
  final stderrCollector = CockpitProcessOutputCollector(process.stderr);
  try {
    final exitCode = await process.exitCode.timeout(timeout);
    final output = await Future.wait(<Future<String>>[
      stdoutCollector.collectText(),
      stderrCollector.collectText(),
    ]);
    return ProcessResult(process.pid, exitCode, output[0], output[1]);
  } on Object {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode.timeout(
      const Duration(milliseconds: 200),
      onTimeout: () => -1,
    );
    return ProcessResult(process.pid, -1, '', '');
  } finally {
    await Future.wait(<Future<void>>[
      stdoutCollector.cancel(),
      stderrCollector.cancel(),
    ]);
  }
}
