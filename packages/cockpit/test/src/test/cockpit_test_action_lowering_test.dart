import 'package:cockpit/src/test/cockpit_test_action_lowerer.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

import '../support/cockpit_test_action_samples.dart';

void main() {
  const flutterLowerer = CockpitTestActionLowerer();
  const systemLowerer = CockpitTestActionLowerer.system();
  final capabilities = _capabilities();

  test('every V2 action lowers exhaustively through its declared backend', () {
    for (final kind in CockpitTestActionKind.values) {
      final usesSystemBackend = kind == CockpitTestActionKind.system;
      final requestedPlane = usesSystemBackend
          ? CockpitTestPlane.native
          : CockpitTestPlane.semantic;
      final result = (usesSystemBackend ? systemLowerer : flutterLowerer).lower(
        action: sampleBoundAction(kind),
        commandId: 'command-${kind.name}',
        timeoutMs: 5000,
        requestedPlane: requestedPlane,
        capabilities: capabilities,
      );
      expect(
        result.isSuccess,
        isTrue,
        reason: '${kind.name}: ${result.error?.message}',
      );
      expect(
        result.value?.command.commandType.name,
        kind.name,
        reason: kind.name,
      );
      expect(result.value?.actualPlane, requestedPlane);
    }
  });

  test('capture options lower without losing authored fields', () {
    final command = flutterLowerer
        .lower(
          action: sampleBoundAction(CockpitTestActionKind.captureScreenshot),
          commandId: 'capture',
          timeoutMs: 5000,
          requestedPlane: CockpitTestPlane.semantic,
          capabilities: capabilities,
        )
        .value!
        .command;

    expect(command.screenshotRequest?.toJson(), <String, Object?>{
      'reason': 'assertion_failure',
      'name': 'acceptanceScreenshot',
      'includeSnapshot': true,
      'attachToStep': false,
      'snapshotOptions': <String, Object?>{
        'profile': 'live',
        'maxTargets': 25,
        'maxAncestorsPerTarget': 0,
        'maxPropertiesPerTarget': 0,
        'includeStyleDetails': false,
        'includeDiagnosticProperties': false,
        'emitArtifactWhenLarge': false,
        'includeRebuildActivity': false,
        'maxRebuildEntries': 8,
        'includeNetworkActivity': false,
        'maxNetworkEntries': 8,
        'networkQuery': <String, Object?>{'onlyFailures': false},
        'includeRuntimeActivity': false,
        'maxRuntimeEntries': 8,
        'runtimeQuery': <String, Object?>{'onlyErrors': false},
        'includeAccessibilitySummary': false,
        'maxAccessibilityEntries': 8,
      },
      'profile': 'diagnostic',
      'allowFallback': false,
    });
  });

  test('unsupported planes, locators, and lossy gestures fail explicitly', () {
    final nativePlane = flutterLowerer.lower(
      action: sampleBoundAction(CockpitTestActionKind.back),
      commandId: 'native',
      timeoutMs: 1000,
      requestedPlane: CockpitTestPlane.native,
      capabilities: capabilities,
    );
    expect(nativePlane.error?.code, CockpitTestErrorCode.unsupportedAction);

    for (final strategy in <CockpitTestLocatorStrategy>[
      CockpitTestLocatorStrategy.nativeId,
      CockpitTestLocatorStrategy.role,
      CockpitTestLocatorStrategy.coordinate,
      CockpitTestLocatorStrategy.visual,
    ]) {
      final action = CockpitTestAction(
        kind: CockpitTestActionKind.tap,
        locator: _locator(strategy),
      );
      final result = flutterLowerer.lower(
        action: action,
        commandId: 'locator-${strategy.name}',
        timeoutMs: 1000,
        requestedPlane: CockpitTestPlane.semantic,
        capabilities: capabilities,
      );
      expect(
        result.error?.code,
        CockpitTestErrorCode.unsupportedLocator,
        reason: strategy.name,
      );
    }

    final swipe = CockpitTestAction.fromJson(<String, Object?>{
      'type': 'swipe',
      'locator': <String, Object?>{'strategy': 'testId', 'value': 'target'},
      'direction': 'up',
      'distance': 0.1,
    }, path: r'$.action');
    final swipeResult = flutterLowerer.lower(
      action: swipe,
      commandId: 'lossy-swipe',
      timeoutMs: 1000,
      requestedPlane: CockpitTestPlane.semantic,
      capabilities: capabilities,
    );
    expect(swipeResult.error?.code, CockpitTestErrorCode.unsupportedAction);
  });

  test('a single unsupported fallback blocks the full locator', () {
    final action = CockpitTestAction(
      kind: CockpitTestActionKind.tap,
      locator: CockpitTestLocator(
        strategy: CockpitTestLocatorStrategy.testId,
        value: 'primary',
        fallbacks: <CockpitTestLocator>[
          CockpitTestLocator(
            strategy: CockpitTestLocatorStrategy.visual,
            value: 'template.png',
          ),
        ],
      ),
    );
    final result = flutterLowerer.lower(
      action: action,
      commandId: 'fallback',
      timeoutMs: 1000,
      requestedPlane: CockpitTestPlane.semantic,
      capabilities: capabilities,
    );
    expect(result.error?.code, CockpitTestErrorCode.unsupportedLocator);
  });
}

CockpitCapabilities _capabilities() => CockpitCapabilities(
  platform: 'android',
  transportType: 'inApp',
  supportsInAppControl: true,
  supportsFlutterViewCapture: true,
  supportsNativeScreenCapture: false,
  supportsHostAutomation: false,
  supportedCommands: CockpitCommandType.values,
  supportedLocatorStrategies: CockpitLocatorKind.values,
);

CockpitTestLocator _locator(CockpitTestLocatorStrategy strategy) =>
    switch (strategy) {
      CockpitTestLocatorStrategy.coordinate => CockpitTestLocator(
        strategy: strategy,
        x: 0.5,
        y: 0.5,
      ),
      CockpitTestLocatorStrategy.visual => CockpitTestLocator(
        strategy: strategy,
        value: 'template.png',
        threshold: 0.9,
      ),
      _ => CockpitTestLocator(strategy: strategy, value: 'target'),
    };
