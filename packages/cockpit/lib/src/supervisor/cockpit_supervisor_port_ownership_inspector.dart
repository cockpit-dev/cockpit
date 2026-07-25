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
      final parentProcessId = current.parentProcessId;
      if (parentProcessId <= 1) return false;
      final parent = await _readProcessSnapshot(parentProcessId, deadline);
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
    final result = await _run(
      'netstat.exe',
      const <String>['-ano', '-p', 'tcp'],
      deadline,
      allowFailure: true,
    );
    if (result.exitCode != 0) return null;
    final processIds = cockpitParseWindowsNetstatListenerProcessIds(
      '${result.stdout}',
      port: port,
    );
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
    final result = await _run(
      'powershell.exe',
      const <String>[
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        cockpitWindowsProcessSnapshotPowerShell,
      ],
      deadline,
      allowFailure: true,
      environment: <String, String>{'COCKPIT_PROCESS_ID': '$processId'},
    );
    if (result.exitCode != 0) return null;
    final fields = '${result.stdout}'.trim().split('|');
    if (fields.length != 3) return null;
    final id = int.tryParse(fields[0]);
    final parentId = int.tryParse(fields[1]);
    final startIdentity = fields[2].trim();
    if (id == null || id <= 1 || parentId == null || startIdentity.isEmpty) {
      return null;
    }
    return _ProcessSnapshot(
      processId: id,
      parentProcessId: parentId,
      startIdentity: startIdentity,
    );
  }

  static Future<ProcessResult> _run(
    String executable,
    List<String> arguments,
    DateTime deadline, {
    required bool allowFailure,
    Map<String, String>? environment,
  }) async {
    final remaining = deadline.difference(DateTime.now().toUtc());
    if (remaining <= Duration.zero) {
      throw TimeoutException('OS ownership probe deadline expired.');
    }
    final process = await Process.start(
      executable,
      arguments,
      environment: <String, String>{..._probeEnvironment(), ...?environment},
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

int? _windowsEndpointPort(String endpoint) {
  final separator = endpoint.lastIndexOf(':');
  if (separator < 0 || separator == endpoint.length - 1) return null;
  return int.tryParse(endpoint.substring(separator + 1));
}

const cockpitWindowsProcessSnapshotPowerShell = r'''
$ErrorActionPreference = 'Stop'
if (-not ('Cockpit.NativeProcessSnapshot' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Globalization;
using System.Runtime.InteropServices;

namespace Cockpit {
  [StructLayout(LayoutKind.Sequential)]
  internal struct NativeFileTime {
    public uint Low;
    public uint High;
  }

  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  internal struct NativeProcessEntry {
    public uint Size;
    public uint Usage;
    public uint ProcessId;
    public IntPtr DefaultHeapId;
    public uint ModuleId;
    public uint ThreadCount;
    public uint ParentProcessId;
    public int BasePriority;
    public uint Flags;

    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
    public string ExecutableFile;
  }

  public static class NativeProcessSnapshot {
    private const uint SnapshotProcesses = 0x00000002;
    private const uint QueryLimitedInformation = 0x00001000;
    private static readonly IntPtr InvalidHandle = new IntPtr(-1);

    [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    private static extern IntPtr CreateToolhelp32Snapshot(
      uint flags,
      uint processId
    );

    [DllImport(
      "kernel32.dll",
      CharSet = CharSet.Unicode,
      ExactSpelling = true,
      SetLastError = true
    )]
    private static extern bool Process32FirstW(
      IntPtr snapshot,
      ref NativeProcessEntry entry
    );

    [DllImport(
      "kernel32.dll",
      CharSet = CharSet.Unicode,
      ExactSpelling = true,
      SetLastError = true
    )]
    private static extern bool Process32NextW(
      IntPtr snapshot,
      ref NativeProcessEntry entry
    );

    [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    private static extern IntPtr OpenProcess(
      uint desiredAccess,
      bool inheritHandle,
      uint processId
    );

    [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    private static extern bool GetProcessTimes(
      IntPtr process,
      out NativeFileTime creation,
      out NativeFileTime exit,
      out NativeFileTime kernel,
      out NativeFileTime user
    );

    [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    public static string Read(uint processId) {
      uint parentProcessId = ReadParentProcessId(processId);
      ulong creationTime = ReadCreationTime(processId);
      return processId.ToString(CultureInfo.InvariantCulture) + "|" +
        parentProcessId.ToString(CultureInfo.InvariantCulture) + "|" +
        creationTime.ToString(CultureInfo.InvariantCulture);
    }

    private static uint ReadParentProcessId(uint processId) {
      IntPtr snapshot = CreateToolhelp32Snapshot(SnapshotProcesses, 0);
      if (snapshot == InvalidHandle) {
        throw new Win32Exception(Marshal.GetLastWin32Error());
      }
      try {
        NativeProcessEntry entry = new NativeProcessEntry();
        entry.Size = (uint)Marshal.SizeOf(typeof(NativeProcessEntry));
        if (!Process32FirstW(snapshot, ref entry)) {
          throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        do {
          if (entry.ProcessId == processId) return entry.ParentProcessId;
        } while (Process32NextW(snapshot, ref entry));
        throw new ArgumentException("Process does not exist.", "processId");
      } finally {
        CloseHandle(snapshot);
      }
    }

    private static ulong ReadCreationTime(uint processId) {
      IntPtr process = OpenProcess(
        QueryLimitedInformation,
        false,
        processId
      );
      if (process == IntPtr.Zero) {
        throw new Win32Exception(Marshal.GetLastWin32Error());
      }
      try {
        NativeFileTime creation;
        NativeFileTime exit;
        NativeFileTime kernel;
        NativeFileTime user;
        if (!GetProcessTimes(
          process,
          out creation,
          out exit,
          out kernel,
          out user
        )) {
          throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        return ((ulong)creation.High << 32) | creation.Low;
      } finally {
        CloseHandle(process);
      }
    }
  }
}
'@
}
[Cockpit.NativeProcessSnapshot]::Read(
  [uint32]$env:COCKPIT_PROCESS_ID
)
''';
