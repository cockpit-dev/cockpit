import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../infrastructure/cockpit_process_manager.dart';
import '../session/cockpit_remote_session_launcher.dart';

typedef CockpitIosPortForwardProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
    });

/// Owns USB port-forward processes used to reach an iOS physical app.
///
/// Flutter's iOS tool uses the same bundled `iproxy` transport for its VM
/// service. Cockpit must use it for the app-owned HTTP bridge as well; a
/// device tunnel address is not a host loopback endpoint for every transport.
final class CockpitIosPortForwarder {
  CockpitIosPortForwarder({
    CockpitIosPortForwardProcessStarter? processStarter,
    String Function()? flutterExecutableResolver,
  }) : _processStarter = processStarter ?? _startProcess,
       _flutterExecutableResolver =
           flutterExecutableResolver ?? (() => cockpitFlutterExecutable());

  final CockpitIosPortForwardProcessStarter _processStarter;
  final String Function() _flutterExecutableResolver;
  final Map<String, _IosForwardedPort> _forwards =
      <String, _IosForwardedPort>{};

  Future<int> ensureForwarded({
    required String deviceId,
    required int preferredHostPort,
    required int devicePort,
    String? flutterExecutable,
  }) async {
    final existing = _findForward(deviceId: deviceId, devicePort: devicePort);
    if (existing != null) return existing.hostPort;

    final hostPort = await _resolveHostPort(preferredHostPort);
    final executable = flutterExecutable ?? _flutterExecutableResolver();
    final flutterRoot = _resolveFlutterRoot(executable);
    if (flutterRoot == null) {
      throw StateError(
        'Unable to resolve the Flutter SDK for iOS port forwarding. '
        'Use an absolute Flutter executable or set FLUTTER_ROOT.',
      );
    }
    final artifacts = p.join(flutterRoot, 'bin', 'cache', 'artifacts');
    final iproxy = File(p.join(artifacts, 'libusbmuxd', 'iproxy'));
    if (!iproxy.existsSync()) {
      throw StateError(
        'Flutter iOS port forwarder is unavailable at ${iproxy.path}. '
        'Run `flutter precache --ios` and retry.',
      );
    }

    final environment = <String, String>{
      'DYLD_LIBRARY_PATH': <String>[
        'libimobiledevice',
        'libusbmuxd',
        'libplist',
        'openssl',
        'libimobiledeviceglue',
      ].map((name) => p.join(artifacts, name)).join(':'),
    };
    final process = await _processStarter(iproxy.path, <String>[
      '$hostPort:$devicePort',
      '--udid',
      deviceId,
    ], environment: environment);
    final forwarded = _IosForwardedPort(
      key: _forwardKey(deviceId, devicePort),
      deviceId: deviceId,
      devicePort: devicePort,
      hostPort: hostPort,
      process: process,
    );
    _forwards[forwarded.key] = forwarded;
    try {
      await _waitUntilListening(forwarded);
      return hostPort;
    } on Object {
      _forwards.remove(forwarded.key);
      await _closeForward(forwarded);
      rethrow;
    }
  }

  Future<void> removeForwarded({
    required String deviceId,
    required int hostPort,
  }) async {
    final entries = _forwards.values
        .where(
          (forward) =>
              forward.deviceId == deviceId && forward.hostPort == hostPort,
        )
        .toList(growable: false);
    for (final forward in entries) {
      _forwards.remove(forward.key);
      await _closeForward(forward);
    }
  }

  Future<void> close() async {
    final entries = _forwards.values.toList(growable: false);
    _forwards.clear();
    await Future.wait<void>(entries.map(_closeForward));
  }

  _IosForwardedPort? _findForward({
    required String deviceId,
    required int devicePort,
  }) {
    return _forwards[_forwardKey(deviceId, devicePort)];
  }

  Future<int> _resolveHostPort(int preferredHostPort) async {
    if (preferredHostPort > 0 &&
        await _isHostPortAvailable(preferredHostPort)) {
      return preferredHostPort;
    }
    return _allocateHostPort();
  }

  Future<void> _waitUntilListening(_IosForwardedPort forward) async {
    forward.stdoutSubscription = forward.process.stdout.listen(
      forward.appendDiagnostic,
    );
    forward.stderrSubscription = forward.process.stderr.listen(
      forward.appendDiagnostic,
    );
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    unawaited(
      forward.process.exitCode.then((code) {
        forward.exitCode = code;
      }),
    );
    while (DateTime.now().isBefore(deadline)) {
      final exitCode = forward.exitCode;
      if (exitCode != null) {
        throw StateError(
          'iproxy exited before forwarding iOS port ${forward.devicePort} '
          '(exitCode=$exitCode${forward.diagnostics.isEmpty ? '' : ': ${forward.diagnostics}'}).',
        );
      }
      try {
        final socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          forward.hostPort,
          timeout: const Duration(milliseconds: 100),
        );
        await socket.close();
        return;
      } on SocketException {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
    throw TimeoutException(
      'iproxy did not open host port ${forward.hostPort} for iOS device '
      '${forward.deviceId}.',
    );
  }

  Future<void> _closeForward(_IosForwardedPort forward) async {
    await forward.stdoutSubscription?.cancel();
    await forward.stderrSubscription?.cancel();
    if (!forward.process.kill(ProcessSignal.sigterm)) return;
    await Future.any<Object?>(<Future<Object?>>[
      forward.process.exitCode,
      Future<Object?>.delayed(const Duration(milliseconds: 500)),
    ]);
    if (forward.exitCode == null) {
      forward.process.kill(ProcessSignal.sigkill);
    }
  }

  static String _forwardKey(String deviceId, int devicePort) =>
      '$deviceId:$devicePort';

  static Future<Process> _startProcess(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  }) {
    return cockpitStartIsolatedProcess(
      executable,
      arguments,
      environment: environment,
    );
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

  static Future<int> _allocateHostPort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    try {
      return socket.port;
    } finally {
      await socket.close();
    }
  }

  static String? _resolveFlutterRoot(String executable) {
    final value = executable.trim();
    final candidates = <String>[];
    if (value.isNotEmpty && (p.isAbsolute(value) || p.dirname(value) != '.')) {
      candidates.add(value);
    } else {
      final path = Platform.environment['PATH'];
      if (path != null) {
        for (final directory in path.split(':')) {
          if (directory.isNotEmpty) candidates.add(p.join(directory, value));
        }
      }
    }
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot != null && flutterRoot.trim().isNotEmpty) {
      candidates.add(p.join(flutterRoot.trim(), 'bin', 'flutter'));
    }
    for (final candidate in candidates) {
      try {
        final resolved = File(candidate).resolveSymbolicLinksSync();
        final bin = p.dirname(resolved);
        if (p.basename(bin) == 'bin') return p.dirname(bin);
      } on FileSystemException {
        continue;
      }
    }
    return null;
  }
}

final class _IosForwardedPort {
  _IosForwardedPort({
    required this.key,
    required this.deviceId,
    required this.devicePort,
    required this.hostPort,
    required this.process,
  });

  final String key;
  final String deviceId;
  final int devicePort;
  final int hostPort;
  final Process process;
  StreamSubscription<List<int>>? stdoutSubscription;
  StreamSubscription<List<int>>? stderrSubscription;
  int? exitCode;
  final StringBuffer _diagnosticBuffer = StringBuffer();

  String get diagnostics => _diagnosticBuffer.toString().trim();

  void appendDiagnostic(List<int> bytes) {
    if (_diagnosticBuffer.length >= 400) return;
    final text = utf8.decode(bytes, allowMalformed: true).trim();
    if (text.isEmpty) return;
    _diagnosticBuffer.write(
      text.substring(
        0,
        text.length > 400 - _diagnosticBuffer.length
            ? 400 - _diagnosticBuffer.length
            : text.length,
      ),
    );
  }
}
