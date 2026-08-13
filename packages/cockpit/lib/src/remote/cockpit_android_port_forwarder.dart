// ignore_for_file: deprecated_member_use

import 'dart:io';

import '../session/cockpit_session_process_runner.dart';

typedef CockpitProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);
typedef CockpitHostPortAllocator = Future<int> Function();
typedef CockpitHostPortAvailabilityChecker = Future<bool> Function(int port);

class CockpitAndroidPortForwarder {
  const CockpitAndroidPortForwarder({
    CockpitProcessRunner processRunner = _runAdbProcess,
    CockpitHostPortAllocator hostPortAllocator = _allocateHostPort,
    CockpitHostPortAvailabilityChecker hostPortAvailabilityChecker =
        _isHostPortAvailable,
  }) : _processRunner = processRunner,
       _hostPortAllocator = hostPortAllocator,
       _hostPortAvailabilityChecker = hostPortAvailabilityChecker;

  final CockpitProcessRunner _processRunner;
  final CockpitHostPortAllocator _hostPortAllocator;
  final CockpitHostPortAvailabilityChecker _hostPortAvailabilityChecker;

  Future<int> ensureForwarded({
    required String deviceId,
    required int preferredHostPort,
    required int devicePort,
  }) async {
    final existingHostPort = await _existingHostPort(
      deviceId: deviceId,
      devicePort: devicePort,
    );
    if (existingHostPort != null) {
      return existingHostPort;
    }

    final hostPort = await _resolvedHostPort(preferredHostPort);
    final result = await _processRunner('adb', <String>[
      '-s',
      deviceId,
      'forward',
      'tcp:$hostPort',
      'tcp:$devicePort',
    ]);

    if (result.exitCode != 0) {
      final forwardedAfterFailure = await _existingHostPort(
        deviceId: deviceId,
        devicePort: devicePort,
      );
      if (forwardedAfterFailure != null) {
        return forwardedAfterFailure;
      }
      throw StateError(
        'adb forward failed for $deviceId: ${result.stderr ?? result.stdout}',
      );
    }

    return hostPort;
  }

  Future<void> removeForwarded({
    required String deviceId,
    required int hostPort,
  }) async {
    final result = await _processRunner('adb', <String>[
      '-s',
      deviceId,
      'forward',
      '--remove',
      'tcp:$hostPort',
    ]);
    if (result.exitCode != 0) {
      throw StateError(
        'adb forward --remove failed for $deviceId: '
        '${result.stderr ?? result.stdout}',
      );
    }
  }

  Future<int> _resolvedHostPort(int preferredHostPort) async {
    if (await _hostPortAvailabilityChecker(preferredHostPort)) {
      return preferredHostPort;
    }
    return _hostPortAllocator();
  }

  Future<int?> _existingHostPort({
    required String deviceId,
    required int devicePort,
  }) async {
    final result = await _processRunner('adb', <String>[
      '-s',
      deviceId,
      'forward',
      '--list',
    ]);
    if (result.exitCode != 0) {
      throw StateError(
        'adb forward --list failed for $deviceId: ${result.stderr ?? result.stdout}',
      );
    }

    final deviceSpec = 'tcp:$devicePort';
    final lines = '${result.stdout}'.trim().split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }

      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length < 3 ||
          parts[0] != deviceId ||
          parts[2] != deviceSpec ||
          !parts[1].startsWith('tcp:')) {
        continue;
      }

      return int.parse(parts[1].substring(4));
    }

    return null;
  }

  static Future<int> _allocateHostPort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    try {
      return socket.port;
    } finally {
      await socket.close();
    }
  }

  static Future<bool> _isHostPortAvailable(int port) async {
    try {
      final socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      await socket.close();
      return true;
    } on SocketException {
      return false;
    }
  }
}

Future<ProcessResult> _runAdbProcess(
  String executable,
  List<String> arguments,
) => cockpitRunProcessWithTimeout(
  executable,
  arguments,
  timeout: const Duration(seconds: 8),
);
