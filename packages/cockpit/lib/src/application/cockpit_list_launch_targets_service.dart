import 'dart:convert';
import 'dart:io';

import '../infrastructure/cockpit_process_output_collector.dart';
import '../infrastructure/cockpit_process_manager.dart';
import '../infrastructure/cockpit_sdk_environment.dart';
import 'cockpit_application_service_exception.dart';

final class CockpitLaunchTarget {
  const CockpitLaunchTarget({
    required this.id,
    required this.name,
    required this.platform,
    required this.platformType,
    required this.emulator,
    required this.ephemeral,
    this.sdk,
  });

  final String id;
  final String name;
  final String platform;
  final String platformType;
  final bool emulator;
  final bool ephemeral;
  final String? sdk;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'platform': platform,
    'platformType': platformType,
    'emulator': emulator,
    'ephemeral': ephemeral,
    'sdk': sdk,
  };
}

final class CockpitListLaunchTargetsResult {
  const CockpitListLaunchTargetsResult({required this.targets});

  final List<CockpitLaunchTarget> targets;

  Map<String, Object?> toJson() => <String, Object?>{
    'targets': targets.map((target) => target.toJson()).toList(growable: false),
  };
}

final class CockpitListLaunchTargetsService {
  CockpitListLaunchTargetsService({
    CockpitProcessManager? processManager,
    CockpitSdkEnvironment? sdkEnvironment,
    this.defaultTimeout = const Duration(minutes: 3),
  }) : _processManager = processManager ?? const LocalCockpitProcessManager(),
       _sdkEnvironment = sdkEnvironment ?? CockpitSdkEnvironment.current();

  final CockpitProcessManager _processManager;
  final CockpitSdkEnvironment _sdkEnvironment;
  final Duration defaultTimeout;

  Future<CockpitListLaunchTargetsResult> list({Duration? timeout}) async {
    final effectiveTimeout = timeout ?? defaultTimeout;
    final process = await _processManager.start(
      _sdkEnvironment.flutterExecutable,
      const <String>['devices', '--machine'],
    );
    final stdoutCollector = CockpitProcessOutputCollector(process.stdout);
    final stderrCollector = CockpitProcessOutputCollector(process.stderr);
    final exitCode = await process.exitCode.timeout(
      effectiveTimeout,
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    final output = await Future.wait(<Future<String>>[
      stdoutCollector.collectText(),
      stderrCollector.collectText(),
    ]);
    final stdout = output[0];
    final stderr = output[1];

    if (exitCode == -1) {
      throw CockpitApplicationServiceException(
        code: 'listLaunchTargetsTimedOut',
        message: 'Timed out while listing Flutter launch targets.',
        details: <String, Object?>{
          'timeoutMs': effectiveTimeout.inMilliseconds,
          if (stdout.trim().isNotEmpty) 'stdout': stdout,
          if (stderr.trim().isNotEmpty) 'stderr': stderr,
        },
      );
    }

    if (exitCode != 0) {
      throw CockpitApplicationServiceException(
        code: 'listLaunchTargetsFailed',
        message: 'Unable to list Flutter launch targets.',
        details: <String, Object?>{
          'exitCode': exitCode,
          'stdout': stdout,
          'stderr': stderr,
        },
      );
    }

    final decoded = jsonDecode(stdout);
    if (decoded is! List<Object?>) {
      throw const CockpitApplicationServiceException(
        code: 'invalidLaunchTargetsOutput',
        message: 'Flutter devices output was not a JSON list.',
      );
    }

    final targets = decoded
        .whereType<Map<Object?, Object?>>()
        .map((item) => Map<String, Object?>.from(item))
        .map(
          (item) => CockpitLaunchTarget(
            id: item['id'] as String? ?? '',
            name: item['name'] as String? ?? '',
            platform: _normalizeLaunchPlatform(item),
            platformType: _rawPlatformType(item),
            emulator: item['emulator'] as bool? ?? false,
            ephemeral: item['ephemeral'] as bool? ?? false,
            sdk: item['sdk'] as String?,
          ),
        )
        .where((target) => target.id.isNotEmpty && target.name.isNotEmpty)
        .toList(growable: false);

    return CockpitListLaunchTargetsResult(
      targets: List<CockpitLaunchTarget>.unmodifiable(targets),
    );
  }

  static String _rawPlatformType(Map<String, Object?> item) {
    return item['targetPlatform'] as String? ??
        item['platformType'] as String? ??
        '';
  }

  static String _normalizeLaunchPlatform(Map<String, Object?> item) {
    final sdk = (item['sdk'] as String? ?? '').trim().toLowerCase();
    if (sdk == 'android' || sdk == 'ios' || sdk == 'macos' || sdk == 'web') {
      return sdk;
    }

    final platformType = _rawPlatformType(item).trim().toLowerCase();
    if (platformType.startsWith('android')) {
      return 'android';
    }
    if (platformType.startsWith('ios')) {
      return 'ios';
    }
    if (platformType == 'darwin' || platformType.startsWith('darwin-')) {
      return 'macos';
    }
    if (platformType.startsWith('web')) {
      return 'web';
    }
    if (platformType.startsWith('windows')) {
      return 'windows';
    }
    if (platformType.startsWith('linux')) {
      return 'linux';
    }
    return sdk.isNotEmpty ? sdk : platformType;
  }
}
