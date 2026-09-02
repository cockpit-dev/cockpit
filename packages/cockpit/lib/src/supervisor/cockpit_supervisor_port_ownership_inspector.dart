import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../infrastructure/cockpit_process_manager.dart';
import '../platform/windows/cockpit_windows_process_snapshot.dart';

final class CockpitSupervisorPortOwnershipEvidence {
  const CockpitSupervisorPortOwnershipEvidence({
    required this.listenerProcessId,
    required this.listenerStartIdentity,
    required this.ownedByWorker,
  });

  final int listenerProcessId;
  final String listenerStartIdentity;
  final bool ownedByWorker;
}

abstract interface class CockpitSupervisorPortOwnershipInspector {
  Future<CockpitSupervisorPortOwnershipEvidence?> inspect({
    required InternetAddress address,
    required int port,
    required DateTime deadline,
  });
}

final class CockpitSystemSupervisorPortOwnershipInspector
    implements CockpitSupervisorPortOwnershipInspector {
  CockpitSystemSupervisorPortOwnershipInspector._({
    required this.workerProcessId,
    required String workerStartIdentity,
  }) : _workerStartIdentity = workerStartIdentity;

  static Future<CockpitSystemSupervisorPortOwnershipInspector> capture({
    required int workerProcessId,
  }) async {
    if (workerProcessId <= 1) {
      throw const FormatException('Worker process id is invalid.');
    }
    final snapshot = await _waitForProcessSnapshot(
      workerProcessId,
      DateTime.now().toUtc().add(const Duration(seconds: 15)),
    );
    if (snapshot == null) {
      throw StateError('Unable to capture the worker process start identity.');
    }
    return CockpitSystemSupervisorPortOwnershipInspector._(
      workerProcessId: workerProcessId,
      workerStartIdentity: snapshot.startIdentity,
    );
  }

  final int workerProcessId;
  final String _workerStartIdentity;

  @override
  Future<CockpitSupervisorPortOwnershipEvidence?> inspect({
    required InternetAddress address,
    required int port,
    required DateTime deadline,
  }) async {
    if (!address.isLoopback ||
        port < 1 ||
        port > 65535 ||
        !deadline.isAfter(DateTime.now().toUtc())) {
      throw const FormatException('Port ownership probe is invalid.');
    }
    final worker = await _readProcessSnapshot(workerProcessId, deadline);
    if (worker == null) {
      throw StateError(
        'Unable to inspect the worker process during port handoff.',
      );
    }
    if (worker.startIdentity != _workerStartIdentity) {
      throw StateError('Worker process identity changed during port handoff.');
    }
    // A single logical loopback endpoint can be reported by more than one
    // process on mobile simulators and port-forwarding proxies (for example,
    // the simulator host proxy and the app process).  PID cardinality is not
    // an ownership proof.  Inspect every visible listener, preferring one in
    // the worker tree when available, and let the authenticated handoff plus
    // remote-session health check establish the actual owner.
    final listenerProcessIds = await _readListenerProcessIds(port, deadline);
    if (listenerProcessIds.isEmpty) return null;
    _ProcessSnapshot? listener;
    var owned = false;
    for (final listenerProcessId in listenerProcessIds.toList()..sort()) {
      final candidate = await _readProcessSnapshot(listenerProcessId, deadline);
      if (candidate == null) continue;
      final candidateOwned = await _belongsToWorker(candidate, deadline);
      if (listener == null || (candidateOwned && !owned)) {
        listener = candidate;
        owned = candidateOwned;
      }
      if (owned) break;
    }
    if (listener == null) return null;
    return CockpitSupervisorPortOwnershipEvidence(
      listenerProcessId: listener.processId,
      listenerStartIdentity: listener.startIdentity,
      ownedByWorker: owned,
    );
  }

  Future<bool> _belongsToWorker(
    _ProcessSnapshot listener,
    DateTime deadline,
  ) async {
    var current = listener;
    final visited = <int>{};
    while (current.processId > 1 && visited.add(current.processId)) {
      if (current.processId == workerProcessId) {
        return current.startIdentity == _workerStartIdentity;
      }
      final parentProcessId = current.parentProcessId;
      if (parentProcessId <= 1) return false;
      final parent = await _readProcessSnapshot(parentProcessId, deadline);
      if (parent == null) return false;
      current = parent;
    }
    return false;
  }

  static Future<Set<int>> _readListenerProcessIds(
    int port,
    DateTime deadline,
  ) => Platform.isWindows
      ? _readWindowsListenerProcessIds(port, deadline)
      : _readPosixListenerProcessIds(port, deadline);

  static Future<Set<int>> _readPosixListenerProcessIds(
    int port,
    DateTime deadline,
  ) async {
    final result = await _run(
      'lsof',
      <String>['-nP', '-a', '-iTCP:$port', '-sTCP:LISTEN', '-Fp'],
      deadline,
      allowFailure: true,
    );
    if (result.exitCode != 0 && '${result.stdout}'.trim().isEmpty) {
      if (Platform.isLinux) {
        return _readLinuxListenerProcessIdsWithSs(port, deadline);
      }
      return <int>{};
    }
    return cockpitParsePosixLsofListenerProcessIds('${result.stdout}');
  }

  static Future<Set<int>> _readLinuxListenerProcessIdsWithSs(
    int port,
    DateTime deadline,
  ) async {
    final result = await _run(
      'ss',
      <String>['-H', '-ltnp', 'sport', '=', ':$port'],
      deadline,
      allowFailure: true,
    );
    if (result.exitCode != 0) return <int>{};
    return RegExp(r'pid=(\d+)')
        .allMatches('${result.stdout}')
        .map((match) => int.parse(match[1]!))
        .toSet();
  }

  static Future<Set<int>> _readWindowsListenerProcessIds(
    int port,
    DateTime deadline,
  ) async {
    final result = await _run(
      'netstat.exe',
      const <String>['-ano', '-p', 'tcp'],
      deadline,
      allowFailure: true,
    );
    if (result.exitCode != 0) return <int>{};
    return cockpitParseWindowsNetstatListenerProcessIds(
      '${result.stdout}',
      port: port,
    );
  }

  static Future<_ProcessSnapshot?> _readProcessSnapshot(
    int processId,
    DateTime deadline,
  ) async {
    if (processId <= 1) return null;
    return Platform.isWindows
        ? _readWindowsProcessSnapshot(processId, deadline)
        : _readPosixProcessSnapshot(processId, deadline);
  }

  static Future<_ProcessSnapshot?> _waitForProcessSnapshot(
    int processId,
    DateTime deadline,
  ) async {
    while (deadline.isAfter(DateTime.now().toUtc())) {
      final snapshot = await _readProcessSnapshot(processId, deadline);
      if (snapshot != null) return snapshot;
      final remaining = deadline.difference(DateTime.now().toUtc());
      if (remaining <= Duration.zero) break;
      await Future<void>.delayed(
        remaining < const Duration(milliseconds: 100)
            ? remaining
            : const Duration(milliseconds: 100),
      );
    }
    return null;
  }

  static Future<_ProcessSnapshot?> _readPosixProcessSnapshot(
    int processId,
    DateTime deadline,
  ) async {
    final result = await _run(
      'ps',
      <String>['-o', 'pid=,ppid=,lstart=', '-p', '$processId'],
      deadline,
      allowFailure: true,
    );
    if (result.exitCode != 0) return null;
    final line = '${result.stdout}'.trim();
    final match = RegExp(r'^(\d+)\s+(\d+)\s+(.+)$').firstMatch(line);
    if (match == null) return null;
    return _ProcessSnapshot(
      processId: int.parse(match[1]!),
      parentProcessId: int.parse(match[2]!),
      startIdentity: match[3]!.trim(),
    );
  }

  static Future<_ProcessSnapshot?> _readWindowsProcessSnapshot(
    int processId,
    DateTime deadline,
  ) async {
    if (!deadline.isAfter(DateTime.now().toUtc())) {
      throw TimeoutException('OS ownership probe deadline expired.');
    }
    final snapshot = cockpitReadWindowsProcessSnapshot(processId);
    if (snapshot == null) return null;
    return _ProcessSnapshot(
      processId: snapshot.processId,
      parentProcessId: snapshot.parentProcessId,
      startIdentity: snapshot.startIdentity,
    );
  }

  static Future<ProcessResult> _run(
    String executable,
    List<String> arguments,
    DateTime deadline, {
    required bool allowFailure,
  }) async {
    final remaining = deadline.difference(DateTime.now().toUtc());
    if (remaining <= Duration.zero) {
      throw TimeoutException('OS ownership probe deadline expired.');
    }
    final process = await Process.start(
      executable,
      arguments,
      environment: _probeEnvironment(),
      includeParentEnvironment: false,
    );
    await process.stdin.close();
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    try {
      final exitCode = await process.exitCode.timeout(remaining);
      final result = ProcessResult(
        process.pid,
        exitCode,
        await stdout,
        await stderr,
      );
      if (!allowFailure && result.exitCode != 0) {
        throw StateError('$executable process inspection failed.');
      }
      return result;
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode.timeout(
        const Duration(seconds: 1),
        onTimeout: () => -1,
      );
      rethrow;
    }
  }
}

final class _ProcessSnapshot {
  const _ProcessSnapshot({
    required this.processId,
    required this.parentProcessId,
    required this.startIdentity,
  });

  final int processId;
  final int parentProcessId;
  final String startIdentity;
}

Map<String, String> _probeEnvironment() {
  return cockpitMinimumChildEnvironment();
}

Set<int> cockpitParseWindowsNetstatListenerProcessIds(
  String output, {
  required int port,
}) {
  if (port < 1 || port > 65535) {
    throw ArgumentError.value(port, 'port');
  }
  final processIds = <int>{};
  for (final line in const LineSplitter().convert(output)) {
    final fields = line.trim().split(RegExp(r'\s+'));
    if (fields.length < 5 || fields.first.toUpperCase() != 'TCP') continue;
    if (_windowsEndpointPort(fields[1]) != port ||
        _windowsEndpointPort(fields[2]) != 0) {
      continue;
    }
    final processId = int.tryParse(fields.last);
    if (processId != null && processId > 1) processIds.add(processId);
  }
  return processIds;
}

Set<int> cockpitParsePosixLsofListenerProcessIds(String output) {
  final processIds = <int>{};
  for (final line in const LineSplitter().convert(output)) {
    if (!line.startsWith('p')) continue;
    final processId = int.tryParse(line.substring(1));
    if (processId != null && processId > 1) processIds.add(processId);
  }
  return processIds;
}

int? _windowsEndpointPort(String endpoint) {
  final separator = endpoint.lastIndexOf(':');
  if (separator < 0 || separator == endpoint.length - 1) return null;
  return int.tryParse(endpoint.substring(separator + 1));
}
