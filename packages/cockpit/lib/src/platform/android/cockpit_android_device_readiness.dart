import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../session/cockpit_session_process_runner.dart';

typedef CockpitAndroidDeviceProbeRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      required Duration timeout,
    });

final class CockpitAndroidDeviceReadinessException implements Exception {
  const CockpitAndroidDeviceReadinessException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

Future<void> cockpitRequireAndroidDeviceReady({
  required String deviceId,
  Duration timeout = const Duration(seconds: 8),
  CockpitAndroidDeviceProbeRunner processRunner = cockpitRunProcessWithTimeout,
}) async {
  final normalizedDeviceId = deviceId.trim();
  if (normalizedDeviceId.isEmpty) {
    throw const CockpitAndroidDeviceReadinessException(
      'androidDeviceMissing',
      'Android development requires an exact device ID.',
    );
  }

  late final ProcessResult result;
  try {
    result = await processRunner('adb', <String>[
      '-s',
      normalizedDeviceId,
      'shell',
      'getprop',
      'sys.boot_completed',
    ], timeout: timeout);
  } on TimeoutException {
    throw CockpitAndroidDeviceReadinessException(
      'androidDeviceUnresponsive',
      'Android device $normalizedDeviceId is listed by ADB but does not '
          'respond to shell commands within ${timeout.inSeconds}s. Restore '
          'the emulator or device connection, then retry the same development '
          'session.',
    );
  } on ProcessException catch (error) {
    throw CockpitAndroidDeviceReadinessException(
      'androidAdbUnavailable',
      'ADB could not probe Android device $normalizedDeviceId: '
          '${error.message}. Restore the Android platform tools, then retry '
          'the same development session.',
    );
  }

  final stdout = _processOutput(result.stdout).trim();
  final stderr = _processOutput(result.stderr).trim();
  final output = stderr.isNotEmpty ? stderr : stdout;
  if (result.exitCode != 0) {
    final normalizedOutput = output.toLowerCase();
    final code = normalizedOutput.contains('unauthorized')
        ? 'androidDeviceUnauthorized'
        : normalizedOutput.contains('offline')
        ? 'androidDeviceOffline'
        : normalizedOutput.contains('not found') ||
              normalizedOutput.contains('no devices')
        ? 'androidDeviceUnavailable'
        : 'androidDeviceProbeFailed';
    throw CockpitAndroidDeviceReadinessException(
      code,
      'Android device $normalizedDeviceId is not ready for Flutter '
      'development${output.isEmpty ? '.' : ': $output'}',
    );
  }
  if (stdout != '1') {
    throw CockpitAndroidDeviceReadinessException(
      'androidDeviceNotBooted',
      'Android device $normalizedDeviceId has not completed booting. Wait for '
          'the system UI to become usable, then retry the same development '
          'session.',
    );
  }
}

String _processOutput(Object? value) {
  return switch (value) {
    null => '',
    String value => value,
    List<int> value => utf8.decode(value, allowMalformed: true),
    _ => '$value',
  };
}
