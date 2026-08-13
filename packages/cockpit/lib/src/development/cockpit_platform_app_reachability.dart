import 'dart:io';

import '../session/cockpit_remote_session_handle.dart';
import '../session/cockpit_session_process_runner.dart';
import 'cockpit_development_session_handle.dart';

typedef CockpitAppReachabilityProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      required Duration timeout,
    });

/// Probes the platform process independently from the Flutter control bridge.
///
/// A `null` result is deliberately inconclusive. Callers must not turn a
/// missing platform tool, an offline device, or a timed-out probe into proof
/// that the application exited.
final class CockpitPlatformAppReachability {
  const CockpitPlatformAppReachability({
    CockpitAppReachabilityProcessRunner processRunner =
        cockpitRunProcessWithTimeout,
    Duration timeout = const Duration(seconds: 2),
  }) : _processRunner = processRunner,
       _timeout = timeout;

  final CockpitAppReachabilityProcessRunner _processRunner;
  final Duration _timeout;

  Future<bool?> probe(CockpitDevelopmentSessionHandle handle) async {
    final remote = handle.remoteSessionHandle;
    if (remote == null) return null;
    try {
      return switch (handle.platform.trim().toLowerCase()) {
        'android' => await _probeAndroid(handle, remote),
        'ios' => await _probeIos(handle, remote),
        'macos' || 'linux' => await _probePosix(remote.processId),
        'windows' => await _probeWindows(remote.processId),
        'web' => null,
        _ => null,
      };
    } on Object {
      return null;
    }
  }

  Future<bool?> _probeAndroid(
    CockpitDevelopmentSessionHandle handle,
    CockpitRemoteSessionHandle remote,
  ) async {
    final packageId = remote.effectivePlatformAppId;
    if (packageId == null || packageId.isEmpty || handle.deviceId.isEmpty) {
      return null;
    }
    final prefix = <String>['-s', handle.deviceId, 'shell'];
    final pidof = await _processRunner('adb', <String>[
      ...prefix,
      'pidof',
      packageId,
    ], timeout: _timeout);
    if (pidof.exitCode == 0 && _containsPid(pidof.stdout)) return true;
    if (_androidTransportFailed(pidof)) return null;

    final ps = await _processRunner('adb', <String>[
      ...prefix,
      'ps',
      '-A',
    ], timeout: _timeout);
    if (ps.exitCode != 0) return null;
    return _androidProcessListContains(ps.stdout, packageId);
  }

  Future<bool?> _probeIos(
    CockpitDevelopmentSessionHandle handle,
    CockpitRemoteSessionHandle remote,
  ) async {
    if (!_looksLikeIosSimulatorDeviceId(handle.deviceId)) return null;
    final pid = remote.processId;
    if (pid == null || pid <= 0) return null;
    final result = await _processRunner('xcrun', <String>[
      'simctl',
      'spawn',
      handle.deviceId,
      '/bin/ps',
      '-p',
      '$pid',
      '-o',
      'pid=',
    ], timeout: _timeout);
    if (result.exitCode == 0) return _containsExactPid(result.stdout, pid);
    return _iosSimulatorUnavailable(result) ? null : false;
  }

  Future<bool?> _probePosix(int? pid) async {
    if (pid == null || pid <= 0) return null;
    final result = await _processRunner('ps', <String>[
      '-p',
      '$pid',
      '-o',
      'pid=',
    ], timeout: _timeout);
    if (result.exitCode == 0) return _containsExactPid(result.stdout, pid);
    return result.exitCode == 1 ? false : null;
  }

  Future<bool?> _probeWindows(int? pid) async {
    if (pid == null || pid <= 0) return null;
    final result = await _processRunner('powershell', <String>[
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      'Get-Process -Id $pid -ErrorAction SilentlyContinue | '
          'Select-Object -ExpandProperty Id',
    ], timeout: _timeout);
    if (result.exitCode != 0) return null;
    return _containsExactPid(result.stdout, pid);
  }
}

bool _containsPid(Object? output) => RegExp(r'\b\d+\b').hasMatch('$output');

bool _containsExactPid(Object? output, int pid) => '$output'
    .split(RegExp(r'\s+'))
    .where((value) => value.isNotEmpty)
    .contains('$pid');

bool _androidProcessListContains(Object? output, String packageId) {
  for (final line in '$output'.split('\n')) {
    final columns = line.trim().split(RegExp(r'\s+'));
    if (columns.isEmpty) continue;
    final name = columns.last;
    if (name == packageId || name.startsWith('$packageId:')) return true;
  }
  return false;
}

bool _androidTransportFailed(ProcessResult result) {
  final message = '${result.stderr} ${result.stdout}'.toLowerCase();
  return message.contains('device offline') ||
      message.contains('device unauthorized') ||
      message.contains('device not found') ||
      message.contains('no devices') ||
      message.contains('cannot connect');
}

bool _iosSimulatorUnavailable(ProcessResult result) {
  final message = '${result.stderr} ${result.stdout}'.toLowerCase();
  return message.contains('invalid device') ||
      message.contains('unable to boot') ||
      message.contains('failed to lookup') ||
      message.contains('coresimulator') ||
      message.contains('service connection interrupted');
}

bool _looksLikeIosSimulatorDeviceId(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized == 'booted' ||
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        caseSensitive: false,
      ).hasMatch(normalized);
}
