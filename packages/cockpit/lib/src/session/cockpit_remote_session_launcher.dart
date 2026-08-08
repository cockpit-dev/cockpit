import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;

import '../application/cockpit_application_service_exception.dart';
import '../infrastructure/cockpit_process_manager.dart';
import '../platform/ios/cockpit_ios_device_connection.dart';
import '../remote/cockpit_remote_session_client.dart';
import 'cockpit_android_remote_session_launcher.dart';
import 'cockpit_ios_physical_remote_session_launcher.dart';
import 'cockpit_ios_simulator_remote_session_launcher.dart';
import 'cockpit_linux_remote_session_launcher.dart';
import 'cockpit_macos_remote_session_launcher.dart';
import 'cockpit_remote_session_handle.dart';
import 'cockpit_remote_session_launch_options.dart';
import 'cockpit_windows_remote_session_launcher.dart';

typedef CockpitRemoteSessionStatusReader =
    Future<CockpitRemoteSessionStatus> Function(Uri baseUri);
typedef CockpitFlutterVersionReader = Future<String> Function();
typedef CockpitFlutterExecutableVersionReader =
    Future<String> Function(String flutterExecutable);
typedef CockpitFlutterCommandRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);
typedef CockpitExecutableLookupRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

abstract interface class CockpitRemoteSessionLauncher {
  Future<CockpitRemoteSessionHandle> launch(
    CockpitRemoteSessionLaunchOptions options,
  );
}

final class CockpitPlatformRemoteSessionLauncher
    implements CockpitRemoteSessionLauncher {
  CockpitPlatformRemoteSessionLauncher({
    CockpitRemoteSessionLauncher? androidLauncher,
    CockpitRemoteSessionLauncher? iosLauncher,
    CockpitRemoteSessionLauncher? iosPhysicalLauncher,
    CockpitRemoteSessionLauncher? macosLauncher,
    CockpitRemoteSessionLauncher? windowsLauncher,
    CockpitRemoteSessionLauncher? linuxLauncher,
  }) : _androidLauncher =
           androidLauncher ?? CockpitAndroidRemoteSessionLauncher(),
       _iosSimulatorLauncher =
           iosLauncher ?? CockpitIosSimulatorRemoteSessionLauncher(),
       _iosPhysicalLauncher =
           iosPhysicalLauncher ?? CockpitIosPhysicalRemoteSessionLauncher(),
       _macosLauncher = macosLauncher ?? CockpitMacosRemoteSessionLauncher(),
       _windowsLauncher =
           windowsLauncher ?? CockpitWindowsRemoteSessionLauncher(),
       _linuxLauncher = linuxLauncher ?? CockpitLinuxRemoteSessionLauncher();

  final CockpitRemoteSessionLauncher _androidLauncher;
  final CockpitRemoteSessionLauncher _iosSimulatorLauncher;
  final CockpitRemoteSessionLauncher _iosPhysicalLauncher;
  final CockpitRemoteSessionLauncher _macosLauncher;
  final CockpitRemoteSessionLauncher _windowsLauncher;
  final CockpitRemoteSessionLauncher _linuxLauncher;

  @override
  Future<CockpitRemoteSessionHandle> launch(
    CockpitRemoteSessionLaunchOptions options,
  ) {
    switch (options.platform) {
      case 'android':
        return _androidLauncher.launch(options);
      case 'ios':
        return cockpitLooksLikeIosSimulatorDeviceId(options.deviceId)
            ? _iosSimulatorLauncher.launch(options)
            : _iosPhysicalLauncher.launch(options);
      case 'macos':
        return _macosLauncher.launch(options);
      case 'windows':
        return _windowsLauncher.launch(options);
      case 'linux':
        return _linuxLauncher.launch(options);
      case 'web':
        throw const CockpitApplicationServiceException(
          code: 'unsupportedAutomationPlatform',
          message:
              'Web automation launch is not supported. Use development '
              'mode with an explicit browser device ID from list-targets.',
          details: <String, Object?>{
            'platform': 'web',
            'mode': 'automation',
            'recommendedMode': 'development',
          },
        );
      default:
        throw CockpitApplicationServiceException(
          code: 'unsupportedPlatform',
          message: 'Unsupported remote session launch platform.',
          details: <String, Object?>{'platform': options.platform},
        );
    }
  }
}

Future<CockpitRemoteSessionStatus> cockpitReadRemoteSessionStatus(Uri baseUri) {
  return CockpitRemoteSessionClient(baseUri: baseUri).readStatus();
}

String cockpitFlutterExecutable({bool? isWindows}) {
  return (isWindows ?? Platform.isWindows) ? 'flutter.bat' : 'flutter';
}

String cockpitDartExecutable({bool? isWindows}) {
  return (isWindows ?? Platform.isWindows) ? 'dart.exe' : 'dart';
}

String cockpitRemoteBindHostForPlatform(String platform) {
  return switch (platform) {
    'android' => '0.0.0.0',
    'ios' => '0.0.0.0',
    'web' => cockpitRemotePublicHostForPlatform(platform),
    _ => cockpitRemotePublicHostForPlatform(platform),
  };
}

String cockpitRemotePublicHostForPlatform(String platform) {
  return '127.0.0.1';
}

Future<String> cockpitResolveActiveFlutterExecutable({
  CockpitFlutterCommandRunner processRunner = cockpitRunIsolatedProcess,
  bool? isWindows,
}) async {
  final defaultExecutable = cockpitFlutterExecutable(isWindows: isWindows);
  final lookupExecutable = (isWindows ?? Platform.isWindows)
      ? 'where'
      : 'which';
  final result = await processRunner(lookupExecutable, <String>[
    defaultExecutable,
  ]);
  if (result.exitCode != 0) {
    return defaultExecutable;
  }
  final resolved = '${result.stdout}'
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => defaultExecutable);
  return resolved.isEmpty ? defaultExecutable : resolved;
}

Future<String> cockpitResolveActiveDartExecutable({
  CockpitExecutableLookupRunner processRunner = cockpitRunIsolatedProcess,
  bool? isWindows,
  String? currentExecutable,
}) async {
  final windows = isWindows ?? Platform.isWindows;
  final pathContext = p.Context(
    style: windows ? p.Style.windows : p.Style.posix,
  );
  final resolvedCurrentExecutable =
      currentExecutable ?? Platform.resolvedExecutable;
  final currentBasename = pathContext
      .basename(resolvedCurrentExecutable)
      .toLowerCase();
  if (currentBasename == 'dart' ||
      currentBasename == 'dart.exe' ||
      currentBasename == 'dart.bat') {
    return resolvedCurrentExecutable;
  }

  final defaultExecutable = cockpitDartExecutable(isWindows: windows);
  final lookupExecutable = windows ? 'where' : 'which';
  final result = await processRunner(lookupExecutable, <String>[
    defaultExecutable,
  ]);
  if (result.exitCode != 0) {
    return defaultExecutable;
  }
  final resolved = '${result.stdout}'
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => defaultExecutable);
  return resolved.isEmpty ? defaultExecutable : resolved;
}

Future<String> cockpitReadActiveFlutterVersion({
  CockpitFlutterCommandRunner processRunner = cockpitRunIsolatedProcess,
  bool? isWindows,
}) async {
  return cockpitReadFlutterVersion(
    cockpitFlutterExecutable(isWindows: isWindows),
    processRunner: processRunner,
  );
}

Future<String> cockpitReadFlutterVersion(
  String flutterExecutable, {
  CockpitFlutterCommandRunner? processRunner,
  String? workingDirectory,
}) async {
  final arguments = <String>['--version', '--machine'];
  final processDirectory =
      workingDirectory != null && Directory(workingDirectory).existsSync()
      ? workingDirectory
      : null;
  final result = processRunner == null
      ? await cockpitRunIsolatedProcess(
          flutterExecutable,
          arguments,
          workingDirectory: processDirectory,
        )
      : await processRunner(flutterExecutable, arguments);
  if (result.exitCode != 0) {
    throw StateError(
      'Unable to resolve Flutter version: ${result.stderr ?? result.stdout}',
    );
  }

  final decoded = jsonDecode('${result.stdout}');
  if (decoded is! Map<Object?, Object?>) {
    throw StateError('Unable to resolve Flutter version from machine output.');
  }

  final frameworkVersion = decoded['frameworkVersion'];
  if (frameworkVersion is! String || frameworkVersion.trim().isEmpty) {
    throw StateError(
      'Flutter machine output did not include frameworkVersion.',
    );
  }

  return frameworkVersion.trim();
}

Future<String> cockpitResolveFlutterVersionForLaunch({
  required String flutterExecutable,
  String? explicitFlutterVersion,
  CockpitFlutterVersionReader? legacyFlutterVersionReader,
  CockpitFlutterExecutableVersionReader flutterVersionForExecutableReader =
      cockpitReadFlutterVersion,
}) async {
  if (explicitFlutterVersion != null && explicitFlutterVersion.isNotEmpty) {
    return explicitFlutterVersion;
  }
  if (legacyFlutterVersionReader != null) {
    return legacyFlutterVersionReader();
  }
  return flutterVersionForExecutableReader(flutterExecutable);
}

Future<CockpitRemoteSessionStatus> cockpitWaitForRemoteSessionReady({
  required Uri baseUri,
  required Duration timeout,
  required CockpitRemoteSessionStatusReader statusReader,
  String? expectedSessionId,
  String? expectedPlatform,
  Duration pollInterval = const Duration(milliseconds: 500),
}) async {
  final deadline = DateTime.now().add(timeout);
  String? lastRejectedStatus;

  while (true) {
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      break;
    }
    try {
      final status = await statusReader(baseUri).timeout(remaining);
      if (_remoteSessionStatusMatches(
        status,
        expectedSessionId: expectedSessionId,
        expectedPlatform: expectedPlatform,
      )) {
        return status;
      }
      lastRejectedStatus =
          'sessionId=${status.sessionId}, expectedSessionId=${expectedSessionId ?? ''}, '
          'platform=${status.platform}, expectedPlatform=${expectedPlatform ?? ''}';
    } on Object {
      // Keep polling until the new app exposes its remote endpoint.
    }
    final retryDelay = deadline.difference(DateTime.now());
    if (retryDelay <= Duration.zero) {
      break;
    }
    await Future<void>.delayed(
      retryDelay < pollInterval ? retryDelay : pollInterval,
    );
  }

  throw TimeoutException(
    'Remote session did not become ready at $baseUri'
    '${lastRejectedStatus == null ? '' : ' (last rejected health: $lastRejectedStatus)'}.',
    timeout,
  );
}

bool _remoteSessionStatusMatches(
  CockpitRemoteSessionStatus status, {
  required String? expectedSessionId,
  required String? expectedPlatform,
}) {
  final normalizedExpectedSessionId = expectedSessionId?.trim();
  if (normalizedExpectedSessionId != null &&
      normalizedExpectedSessionId.isNotEmpty &&
      status.sessionId != normalizedExpectedSessionId) {
    return false;
  }
  final normalizedExpectedPlatform = expectedPlatform?.trim().toLowerCase();
  if (normalizedExpectedPlatform != null &&
      normalizedExpectedPlatform.isNotEmpty &&
      status.platform.trim().toLowerCase() != normalizedExpectedPlatform) {
    return false;
  }
  return true;
}
