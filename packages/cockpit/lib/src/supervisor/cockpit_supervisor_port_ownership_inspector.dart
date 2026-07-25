import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../infrastructure/cockpit_process_manager.dart';

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
    final listenerProcessId = await _readListenerProcessId(port, deadline);
    if (listenerProcessId == null) return null;
    final listener = await _readProcessSnapshot(listenerProcessId, deadline);
    if (listener == null) return null;
    final owned = await _belongsToWorker(listener, deadline);
    return CockpitSupervisorPortOwnershipEvidence(
      listenerProcessId: listenerProcessId,
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
      final parent = await _readProcessSnapshot(
        current.parentProcessId,
        deadline,
      );
      if (parent == null) return false;
      current = parent;
    }
    return false;
  }

  static Future<int?> _readListenerProcessId(int port, DateTime deadline) =>
      Platform.isWindows
      ? _readWindowsListenerProcessId(port, deadline)
      : _readPosixListenerProcessId(port, deadline);

  static Future<int?> _readPosixListenerProcessId(
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
        return _readLinuxListenerProcessIdWithSs(port, deadline);
      }
      return null;
    }
    final processIds = <int>{};
    for (final line in const LineSplitter().convert('${result.stdout}')) {
      if (!line.startsWith('p')) continue;
      final processId = int.tryParse(line.substring(1));
      if (processId != null && processId > 1) processIds.add(processId);
    }
    if (processIds.isEmpty) return null;
    if (processIds.length != 1) {
      throw StateError('Loopback port has multiple listener processes.');
    }
    return processIds.single;
  }

  static Future<int?> _readLinuxListenerProcessIdWithSs(
    int port,
    DateTime deadline,
  ) async {
    final result = await _run(
      'ss',
      <String>['-H', '-ltnp', 'sport', '=', ':$port'],
      deadline,
      allowFailure: true,
    );
    if (result.exitCode != 0) return null;
    final matches = RegExp(r'pid=(\d+)')
        .allMatches('${result.stdout}')
        .map((match) => int.parse(match[1]!))
        .toSet();
    if (matches.isEmpty) return null;
    if (matches.length != 1) {
      throw StateError('Loopback port has multiple listener processes.');
    }
    return matches.single;
  }

  static Future<int?> _readWindowsListenerProcessId(
    int port,
    DateTime deadline,
  ) async {
    final script =
        '\$ids = @(Get-NetTCPConnection -State Listen -LocalPort $port '
        '-ErrorAction SilentlyContinue | Select-Object -ExpandProperty '
        'OwningProcess -Unique); \$ids -join "`n"';
    final result = await _run(
      'powershell.exe',
      <String>['-NoProfile', '-NonInteractive', '-Command', script],
      deadline,
      allowFailure: true,
    );
    if (result.exitCode != 0) return null;
    final processIds = const LineSplitter()
        .convert('${result.stdout}')
        .map((line) => int.tryParse(line.trim()))
        .whereType<int>()
        .where((processId) => processId > 1)
        .toSet();
    if (processIds.isEmpty) return null;
    if (processIds.length != 1) {
      throw StateError('Loopback port has multiple listener processes.');
    }
    return processIds.single;
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
    final script =
        'Get-CimInstance Win32_Process -Filter "ProcessId = $processId" | '
        'Select-Object ProcessId,ParentProcessId,CreationDate | '
        'ConvertTo-Json -Compress';
    final result = await _run(
      'powershell.exe',
      <String>['-NoProfile', '-NonInteractive', '-Command', script],
      deadline,
      allowFailure: true,
    );
    if (result.exitCode != 0 || '${result.stdout}'.trim().isEmpty) return null;
    final json = jsonDecode('${result.stdout}');
    if (json is! Map<Object?, Object?>) return null;
    final id = json['ProcessId'];
    final parentId = json['ParentProcessId'];
    final creationDate = json['CreationDate'];
    if (id is! int || parentId is! int || creationDate is! String) return null;
    return _ProcessSnapshot(
      processId: id,
      parentProcessId: parentId,
      startIdentity: creationDate,
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
    final result = await Process.run(
      executable,
      arguments,
      environment: _probeEnvironment(),
      includeParentEnvironment: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    ).timeout(remaining);
    if (!allowFailure && result.exitCode != 0) {
      throw StateError('$executable process inspection failed.');
    }
    return result;
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
