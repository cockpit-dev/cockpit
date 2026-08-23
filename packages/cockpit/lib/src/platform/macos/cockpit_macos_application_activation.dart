import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../infrastructure/cockpit_process_manager.dart';

const String cockpitMacosApplicationActivationCommandExecutable =
    '__cockpit_macos_application_activation__';

typedef CockpitMacosApplicationActivator =
    Future<CockpitMacosApplicationActivation> Function({
      required String? appId,
      required int? processId,
      required Duration timeout,
    });

final class CockpitMacosApplicationActivation {
  const CockpitMacosApplicationActivation({
    required this.processId,
    required this.appId,
    required this.bundlePath,
    required this.changed,
  });

  final int processId;
  final String appId;
  final String bundlePath;
  final bool changed;
}

final class CockpitMacosApplicationActivationException implements Exception {
  const CockpitMacosApplicationActivationException({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;

  @override
  String toString() => message;
}

Future<CockpitMacosApplicationActivation> cockpitActivateMacosApplication({
  required String? appId,
  required int? processId,
  required Duration timeout,
  CockpitProcessManager processManager = const LocalCockpitProcessManager(),
}) async {
  if (!Platform.isMacOS) {
    throw UnsupportedError('macOS application activation requires macOS.');
  }
  if (timeout <= Duration.zero) {
    throw TimeoutException('macOS application activation deadline elapsed.');
  }
  final normalizedAppId = appId?.trim();
  if ((normalizedAppId == null || normalizedAppId.isEmpty) &&
      (processId == null || processId <= 0)) {
    throw const CockpitMacosApplicationActivationException(
      code: 'missingSystemActionTarget',
      message: 'macOS application activation requires an app id or process id.',
    );
  }

  final stopwatch = Stopwatch()..start();
  Duration remaining() {
    final value = timeout - stopwatch.elapsed;
    if (value <= Duration.zero) {
      throw TimeoutException('macOS application activation deadline elapsed.');
    }
    return value;
  }

  final targetResult = await cockpitRunManagedProcessWithTimeout(
    processManager,
    'osascript',
    <String>[
      '-l',
      'JavaScript',
      '-e',
      _resolveMacosApplicationTargetScript,
      normalizedAppId ?? '',
      processId?.toString() ?? '',
    ],
    timeout: remaining(),
  );
  if (targetResult.exitCode != 0) {
    throw CockpitMacosApplicationActivationException(
      code: 'macosApplicationTargetNotFound',
      message: _processFailureMessage(
        targetResult,
        fallback: 'Unable to resolve the requested macOS application.',
      ),
    );
  }
  final target = _decodeMacosApplicationTarget(targetResult.stdout);
  if (target.frontmost) {
    return CockpitMacosApplicationActivation(
      processId: target.processId,
      appId: target.appId,
      bundlePath: target.bundlePath,
      changed: false,
    );
  }

  final openResult = await cockpitRunManagedProcessWithTimeout(
    processManager,
    'open',
    <String>[target.bundlePath],
    timeout: remaining(),
  );
  if (openResult.exitCode != 0) {
    throw CockpitMacosApplicationActivationException(
      code: 'macosApplicationActivationFailed',
      message: _processFailureMessage(
        openResult,
        fallback: 'Unable to activate macOS application ${target.appId}.',
      ),
    );
  }

  final focusBudget = remaining() < const Duration(seconds: 3)
      ? remaining()
      : const Duration(seconds: 3);
  final focusResult = await cockpitRunManagedProcessWithTimeout(
    processManager,
    'osascript',
    <String>[
      '-l',
      'JavaScript',
      '-e',
      _waitForMacosApplicationFocusScript,
      '${target.processId}',
      '${focusBudget.inMilliseconds}',
    ],
    timeout: remaining(),
  );
  if (focusResult.exitCode != 0) {
    throw CockpitMacosApplicationActivationException(
      code: 'macosApplicationActivationFailed',
      message: _processFailureMessage(
        focusResult,
        fallback: 'macOS application ${target.appId} did not become frontmost.',
      ),
    );
  }
  final focus = _decodeMacosApplicationFocus(focusResult.stdout);
  if (!focus.targetFrontmost) {
    final foreground = focus.frontmostAppId.isEmpty
        ? 'process ${focus.frontmostProcessId}'
        : '${focus.frontmostAppId} (${focus.frontmostProcessId})';
    throw CockpitMacosApplicationActivationException(
      code: 'macosApplicationActivationFailed',
      message:
          'macOS application ${target.appId} did not become frontmost; '
          'current foreground is $foreground.',
    );
  }
  return CockpitMacosApplicationActivation(
    processId: target.processId,
    appId: target.appId,
    bundlePath: target.bundlePath,
    changed: true,
  );
}

({int processId, String appId, String bundlePath, bool frontmost})
_decodeMacosApplicationTarget(Object? stdout) {
  try {
    final value = jsonDecode('$stdout'.trim());
    if (value is! Map<String, Object?> ||
        value['processId'] is! int ||
        value['appId'] is! String ||
        value['bundlePath'] is! String ||
        value['frontmost'] is! bool) {
      throw const FormatException('invalid macOS application target');
    }
    final processId = value['processId']! as int;
    final appId = value['appId']! as String;
    final bundlePath = value['bundlePath']! as String;
    if (processId <= 0 || appId.isEmpty || bundlePath.isEmpty) {
      throw const FormatException('incomplete macOS application target');
    }
    return (
      processId: processId,
      appId: appId,
      bundlePath: bundlePath,
      frontmost: value['frontmost']! as bool,
    );
  } on FormatException catch (error) {
    throw CockpitMacosApplicationActivationException(
      code: 'macosApplicationTargetInvalid',
      message: 'Unable to decode the macOS application target: $error',
    );
  }
}

({bool targetFrontmost, int frontmostProcessId, String frontmostAppId})
_decodeMacosApplicationFocus(Object? stdout) {
  try {
    final value = jsonDecode('$stdout'.trim());
    if (value is! Map<String, Object?> ||
        value['targetFrontmost'] is! bool ||
        value['frontmostProcessId'] is! int ||
        value['frontmostAppId'] is! String) {
      throw const FormatException('invalid macOS application focus');
    }
    return (
      targetFrontmost: value['targetFrontmost']! as bool,
      frontmostProcessId: value['frontmostProcessId']! as int,
      frontmostAppId: value['frontmostAppId']! as String,
    );
  } on FormatException catch (error) {
    throw CockpitMacosApplicationActivationException(
      code: 'macosApplicationFocusInvalid',
      message: 'Unable to decode the macOS application focus: $error',
    );
  }
}

String _processFailureMessage(
  ProcessResult result, {
  required String fallback,
}) {
  final stderr = '${result.stderr}'.trim();
  if (stderr.isNotEmpty) return stderr;
  final stdout = '${result.stdout}'.trim();
  return stdout.isEmpty ? fallback : stdout;
}

const String _resolveMacosApplicationTargetScript = r'''
ObjC.import('AppKit')

function run(argv) {
  const requestedAppId = argv[0]
  const requestedProcessId = argv[1] === '' ? null : Number(argv[1])
  let app = null
  if (requestedProcessId !== null) {
    app = $.NSRunningApplication.runningApplicationWithProcessIdentifier(
      requestedProcessId,
    )
    if (!app || app.terminated) {
      throw new Error(
        `No running macOS application matches process ${requestedProcessId}`,
      )
    }
  } else {
    const apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier(
      requestedAppId,
    )
    if (Number(apps.count) !== 1) {
      throw new Error(
        `Expected one running macOS application for ${requestedAppId}, found ${Number(apps.count)}`,
      )
    }
    app = apps.objectAtIndex(0)
  }
  const rawResolvedAppId = app.bundleIdentifier
    ? ObjC.unwrap(app.bundleIdentifier)
    : ''
  const resolvedAppId = typeof rawResolvedAppId === 'string'
    ? rawResolvedAppId
    : ''
  if (requestedAppId !== '' && resolvedAppId !== requestedAppId) {
    throw new Error(
      `macOS process ${Number(app.processIdentifier)} belongs to ${resolvedAppId}, not ${requestedAppId}`,
    )
  }
  const rawBundlePath = app.bundleURL && app.bundleURL.path
    ? ObjC.unwrap(app.bundleURL.path)
    : ''
  const bundlePath = typeof rawBundlePath === 'string' ? rawBundlePath : ''
  if (resolvedAppId === '' || bundlePath === '') {
    throw new Error(
      `macOS process ${Number(app.processIdentifier)} has no application bundle`,
    )
  }
  const frontmost = $.NSWorkspace.sharedWorkspace.frontmostApplication
  return JSON.stringify({
    processId: Number(app.processIdentifier),
    appId: resolvedAppId,
    bundlePath,
    frontmost:
      frontmost &&
      Number(frontmost.processIdentifier) === Number(app.processIdentifier),
  })
}
''';

const String _waitForMacosApplicationFocusScript = r'''
ObjC.import('AppKit')

function run(argv) {
  const processId = Number(argv[0])
  const deadline = Date.now() + Math.max(0, Number(argv[1]))
  let frontmost = $.NSWorkspace.sharedWorkspace.frontmostApplication
  while (
    frontmost &&
    Number(frontmost.processIdentifier) !== processId &&
    Date.now() < deadline
  ) {
    delay(0.01)
    frontmost = $.NSWorkspace.sharedWorkspace.frontmostApplication
  }
  const frontmostProcessId = frontmost
    ? Number(frontmost.processIdentifier)
    : 0
  const rawFrontmostAppId = frontmost && frontmost.bundleIdentifier
    ? ObjC.unwrap(frontmost.bundleIdentifier)
    : ''
  const frontmostAppId = typeof rawFrontmostAppId === 'string'
    ? rawFrontmostAppId
    : ''
  return JSON.stringify({
    targetFrontmost: frontmostProcessId === processId,
    frontmostProcessId,
    frontmostAppId,
  })
}
''';
