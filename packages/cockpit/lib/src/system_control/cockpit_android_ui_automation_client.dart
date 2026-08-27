import 'dart:async';
import 'dart:io';

import '../infrastructure/cockpit_process_manager.dart';
import '../infrastructure/cockpit_runtime_resources.dart';

const String cockpitAndroidUiAutomationCommandExecutable =
    '__cockpit_android_ui_automation';

typedef CockpitAndroidDriverAssetResolver = Future<Uri?> Function(Uri uri);

abstract interface class CockpitAndroidUiAutomation {
  Future<String> readUiTree({
    required String deviceId,
    required int maxDepth,
    required int maxNodes,
    required Duration timeout,
  });

  Future<String> dismissSystemDialog({
    required String deviceId,
    required String decision,
    String? appId,
    required Duration timeout,
  });

  Future<String> tapNotification({
    required String deviceId,
    required String text,
    required Duration timeout,
  });
}

final class CockpitAndroidUiAutomationClient
    implements CockpitAndroidUiAutomation {
  CockpitAndroidUiAutomationClient({
    CockpitProcessManager? processManager,
    CockpitAndroidDriverAssetResolver? assetResolver,
  }) : _processManager = processManager ?? const LocalCockpitProcessManager(),
       _assetResolver = assetResolver ?? cockpitResolveRuntimePackageAsset;

  static const String _driverPackage = 'dev.cockpit.driver';
  static const String _testPackage = 'dev.cockpit.driver.test';
  static const int _driverVersionCode = 5;
  static const int _testDriverVersionCode = 0;
  static const String _runner = 'androidx.test.runner.AndroidJUnitRunner';
  static const String _testClass = 'dev.cockpit.driver.CockpitDriverTest';

  final CockpitProcessManager _processManager;
  final CockpitAndroidDriverAssetResolver _assetResolver;

  @override
  Future<String> readUiTree({
    required String deviceId,
    required int maxDepth,
    required int maxNodes,
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    await _ensureInstalled(deviceId, deadline);
    await _runInstrumentation(deviceId, 'dumpUiTree', <String, String>{
      'maxDepth': '$maxDepth',
      'maxNodes': '$maxNodes',
    }, deadline);
    final hierarchy = await _run(deviceId, const <String>[
      'shell',
      'run-as',
      _driverPackage,
      'cat',
      'files/window.xml',
    ], deadline);
    final xml = '${hierarchy.stdout}'.trim();
    if (hierarchy.exitCode != 0 || !xml.startsWith('<?xml')) {
      throw StateError(
        _failureMessage('Android UI tree output is unavailable', hierarchy),
      );
    }
    return xml;
  }

  @override
  Future<String> dismissSystemDialog({
    required String deviceId,
    required String decision,
    String? appId,
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    await _ensureInstalled(deviceId, deadline);
    final output =
        await _runInstrumentation(deviceId, 'tapSystemDialog', <String, String>{
          'decision': decision,
          if (appId != null && appId.trim().isNotEmpty) 'appId': appId.trim(),
        }, deadline);
    final handled = RegExp(
      r'INSTRUMENTATION_STATUS: cockpitHandled=(true|false)',
    ).firstMatch(output)?.group(1);
    if (handled == null) {
      throw StateError(
        'Android UI Automation did not report whether a system dialog was handled.',
      );
    }
    return 'dismissSystemDialog decision=$decision handled=$handled';
  }

  @override
  Future<String> tapNotification({
    required String deviceId,
    required String text,
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    await _ensureInstalled(deviceId, deadline);
    final expand = await _run(deviceId, const <String>[
      'shell',
      'cmd',
      'statusbar',
      'expand-notifications',
    ], deadline);
    if (expand.exitCode != 0) {
      throw StateError(
        _failureMessage('Android notification shade could not open', expand),
      );
    }
    await _runInstrumentation(deviceId, 'tapNotification', <String, String>{
      'text': text,
    }, deadline);
    return 'tapNotification text=$text handled=true';
  }

  Future<String> _runInstrumentation(
    String deviceId,
    String method,
    Map<String, String> parameters,
    DateTime deadline,
  ) async {
    final instrumentation = await _run(deviceId, <String>[
      'shell',
      'am',
      'instrument',
      '-w',
      '-r',
      '-e',
      'class',
      '$_testClass#$method',
      for (final parameter in parameters.entries) ...<String>[
        '-e',
        parameter.key,
        parameter.value,
      ],
      '$_testPackage/$_runner',
    ], deadline);
    final output = '${instrumentation.stdout}';
    if (instrumentation.exitCode != 0 ||
        !output.contains('OK (1 test)') ||
        output.contains('INSTRUMENTATION_FAILED')) {
      throw StateError(
        _failureMessage(
          'Android UI Automation action $method failed',
          instrumentation,
        ),
      );
    }
    return output;
  }

  Future<void> _ensureInstalled(String deviceId, DateTime deadline) async {
    final driverCurrent = await _hasExpectedVersion(
      deviceId,
      _driverPackage,
      _driverVersionCode,
      deadline,
    );
    final testDriverCurrent = await _hasExpectedVersion(
      deviceId,
      _testPackage,
      _testDriverVersionCode,
      deadline,
    );
    if (driverCurrent && testDriverCurrent) return;

    final driver = await _resolveAsset('cockpit-driver.apk');
    final testDriver = await _resolveAsset('cockpit-driver-test.apk');
    await _install(deviceId, driver, deadline);
    await _install(deviceId, testDriver, deadline);
  }

  Future<bool> _hasExpectedVersion(
    String deviceId,
    String packageName,
    int versionCode,
    DateTime deadline,
  ) async {
    final probe = await _run(deviceId, <String>[
      'shell',
      'dumpsys',
      'package',
      packageName,
    ], deadline);
    return probe.exitCode == 0 &&
        RegExp(
          '(?:^|\\s)versionCode=$versionCode(?:\\s|\$)',
          multiLine: true,
        ).hasMatch('${probe.stdout}');
  }

  Future<String> _resolveAsset(String name) async {
    final uri = await _assetResolver(
      Uri.parse('package:cockpit/src/system_control/resources/android/$name'),
    );
    if (uri == null || uri.scheme != 'file') {
      throw StateError('Bundled Android UI Automation asset $name is missing.');
    }
    return uri.toFilePath();
  }

  Future<void> _install(
    String deviceId,
    String apkPath,
    DateTime deadline,
  ) async {
    final result = await _run(deviceId, <String>[
      'install',
      '-r',
      '-t',
      apkPath,
    ], deadline);
    if (result.exitCode != 0 || !'${result.stdout}'.contains('Success')) {
      throw StateError(
        _failureMessage('Android UI Automation driver install failed', result),
      );
    }
  }

  Future<ProcessResult> _run(
    String deviceId,
    List<String> arguments,
    DateTime deadline,
  ) {
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      throw TimeoutException('Android UI Automation timed out.');
    }
    return cockpitRunManagedProcessWithTimeout(_processManager, 'adb', <String>[
      '-s',
      deviceId,
      ...arguments,
    ], timeout: remaining);
  }
}

String _failureMessage(String message, ProcessResult result) {
  final stderr = '${result.stderr}'.trim();
  final stdout = '${result.stdout}'.trim();
  final detail = stderr.isNotEmpty ? stderr : stdout;
  return detail.isEmpty ? message : '$message: $detail';
}
