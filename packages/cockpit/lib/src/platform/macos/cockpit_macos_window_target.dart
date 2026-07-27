import 'dart:async';

import '../../capture/cockpit_host_capture_adapter.dart';

typedef CockpitMacosWindowTargetResolver =
    Future<CockpitMacosWindowTarget> Function({
      required String appId,
      required String osascriptExecutable,
      required CockpitCaptureProcessRunner processRunner,
      required Duration timeout,
      required Duration activationSettleDelay,
    });

final class CockpitMacosWindowTarget {
  const CockpitMacosWindowTarget({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final int left;
  final int top;
  final int width;
  final int height;
}

Future<CockpitMacosWindowTarget> cockpitResolveMacosWindowTarget({
  required String appId,
  required String osascriptExecutable,
  required CockpitCaptureProcessRunner processRunner,
  required Duration timeout,
  required Duration activationSettleDelay,
}) async {
  final result = await processRunner(osascriptExecutable, <String>[
    '-l',
    'JavaScript',
    '-e',
    _windowTargetScript,
    appId,
    activationSettleDelay.inMilliseconds.toString(),
  ]).timeout(timeout);
  if (result.exitCode != 0) {
    throw StateError(
      'Unable to resolve the active macOS window for $appId: '
      '${result.stderr ?? result.stdout}',
    );
  }

  final stdout = '${result.stdout}'.trim();
  final parts = stdout.split(',');
  if (parts.length != 4) {
    throw StateError(
      'Unable to resolve the active macOS window for $appId: invalid payload.',
    );
  }
  final left = int.tryParse(parts[0].trim());
  final top = int.tryParse(parts[1].trim());
  final width = int.tryParse(parts[2].trim());
  final height = int.tryParse(parts[3].trim());
  if (left == null ||
      top == null ||
      width == null ||
      height == null ||
      width <= 0 ||
      height <= 0) {
    throw StateError(
      'Unable to resolve the active macOS window for $appId: invalid bounds.',
    );
  }

  return CockpitMacosWindowTarget(
    left: left,
    top: top,
    width: width,
    height: height,
  );
}

const String _windowTargetScript = r'''
ObjC.import('AppKit')
ObjC.import('CoreGraphics')
ObjC.import('IOKit')
ObjC.bindFunction('CGWindowListCopyWindowInfo', ['id', ['uint32', 'uint32']])
ObjC.bindFunction('IOPMAssertionDeclareUserActivity', ['int', ['id', 'uint32', 'uint32*']])

function run(argv) {
  const appId = argv[0]
  const settleMs = Math.max(0, Number(argv[1] || '0'))
  const assertionId = Ref()
  const wakeResult = $.IOPMAssertionDeclareUserActivity(
    $('Cockpit application capture'),
    0,
    assertionId,
  )
  if (Number(wakeResult) !== 0) {
    throw new Error(`Unable to wake the macOS display for ${appId}: ${wakeResult}`)
  }
  const apps = $.NSRunningApplication.runningApplicationsWithBundleIdentifier(appId)
  if (apps.count === 0) {
    throw new Error(`No running macOS application was found for ${appId}`)
  }

  const app = apps.objectAtIndex(0)
  if (!app.activateWithOptions($.NSApplicationActivateIgnoringOtherApps)) {
    throw new Error(`Unable to activate macOS application ${appId}`)
  }
  if (settleMs > 0) delay(settleMs / 1000.0)

  const pid = Number(app.processIdentifier)
  const windows = $.CGWindowListCopyWindowInfo(17, 0)
  let best = null
  for (let index = 0; index < Number(windows.count); index += 1) {
    const window = ObjC.deepUnwrap(windows.objectAtIndex(index))
    const bounds = window.kCGWindowBounds || {}
    const width = Number(bounds.Width)
    const height = Number(bounds.Height)
    if (Number(window.kCGWindowOwnerPID) !== pid ||
        Number(window.kCGWindowLayer) !== 0 ||
        window.kCGWindowIsOnscreen !== true ||
        width <= 0 || height <= 0) {
      continue
    }
    const area = width * height
    if (best === null || area > best.area) {
      best = {
        left: Math.round(Number(bounds.X)),
        top: Math.round(Number(bounds.Y)),
        width: Math.round(width),
        height: Math.round(height),
        area: area,
      }
    }
  }
  if (best === null) {
    throw new Error(`No visible macOS window was found for ${appId}`)
  }
  return [best.left, best.top, best.width, best.height].join(',')
}
''';
