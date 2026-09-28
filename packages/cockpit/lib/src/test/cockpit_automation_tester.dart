import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit_test/cockpit_test.dart';

import '../adapters/cockpit_automation_adapter.dart';
import '../adapters/cockpit_performance_adapter.dart';

/// Shared implementation for testers backed by a Cockpit automation adapter.
///
/// The adapter owns transport and platform details. This class only maps the
/// stable, platform-neutral tester API to protocol commands, so scenarios can
/// run unchanged against a Flutter in-app bridge, an integrated release app,
/// or a native black-box driver.
class CockpitAutomationTester
    implements CockpitTester, CockpitTestFeatureProvider {
  CockpitAutomationTester({
    required CockpitAutomationAdapter automation,
    required CockpitLocaleProfile initialLocale,
    CockpitLocaleProfile Function()? localeProvider,
    CockpitPerformanceAdapter? performance,
  }) : _automation = automation,
       _initialLocale = initialLocale,
       _localeProvider = localeProvider,
       _performance = performance;

  final CockpitAutomationAdapter _automation;
  final CockpitLocaleProfile _initialLocale;
  final CockpitLocaleProfile Function()? _localeProvider;
  final CockpitPerformanceAdapter? _performance;
  int _sequence = 0;

  @override
  CockpitLocaleProfile get locale => _localeProvider?.call() ?? _initialLocale;

  @override
  Future<CockpitCapabilities> describeCapabilities() =>
      _automation.describeCapabilities();

  @override
  Future<Set<CockpitTestFeature>> describeFeatures() async {
    final capabilities = await describeCapabilities();
    return <CockpitTestFeature>{
      if (capabilities.supportsInAppControl) CockpitTestFeature.inAppControl,
      if (capabilities.supportsFlutterViewCapture)
        CockpitTestFeature.flutterViewCapture,
      if (capabilities.supportsNativeScreenCapture)
        CockpitTestFeature.nativeScreenCapture,
      if (capabilities.supportsHostAutomation)
        CockpitTestFeature.hostAutomation,
      if (capabilities.supportsViewportResize)
        CockpitTestFeature.viewportResize,
      if (_performance != null) CockpitTestFeature.performanceCapture,
    };
  }

  @override
  Future<CockpitCommandExecution> execute(CockpitCommand command) =>
      _automation.execute(command);

  @override
  Future<CockpitCommandExecution> tap(Object? target) =>
      _run(CockpitCommandType.tap, target: target);

  @override
  Future<CockpitCommandExecution> type(String value, {required Object into}) =>
      _run(
        CockpitCommandType.enterText,
        target: into,
        parameters: <String, Object?>{'text': value},
      );

  @override
  Future<CockpitCommandExecution> clear(Object target) =>
      _run(CockpitCommandType.eraseText, target: target);

  @override
  Future<CockpitCommandExecution> focus(Object target) =>
      _run(CockpitCommandType.focusTextInput, target: target);

  @override
  Future<CockpitCommandExecution> press(
    CockpitTextInputAction action, {
    Object? target,
  }) => _run(
    CockpitCommandType.sendTextInputAction,
    target: target,
    parameters: <String, Object?>{'inputAction': action.name},
  );

  @override
  Future<CockpitCommandExecution> scroll(Object target) =>
      _run(CockpitCommandType.scrollUntilVisible, target: target);

  @override
  Future<CockpitCommandExecution> waitForUi() =>
      _run(CockpitCommandType.waitForUiIdle);

  @override
  Future<CockpitCommandExecution> waitFor(
    Object target, {
    bool absent = false,
  }) => _run(
    CockpitCommandType.waitFor,
    target: target,
    parameters: <String, Object?>{if (absent) 'absent': true},
  );

  @override
  Future<CockpitCommandExecution> expectVisible(Object target) =>
      _run(CockpitCommandType.assertVisible, target: target);

  @override
  Future<CockpitCommandExecution> expectText(
    Object target,
    Object expected, {
    CockpitTextMatchMode match = CockpitTextMatchMode.exact,
  }) {
    final resolved = expected is CockpitLocalizedText
        ? expected.resolve(locale)
        : expected.toString();
    return _run(
      CockpitCommandType.assertText,
      target: target,
      parameters: <String, Object?>{
        'text': resolved,
        if (match != CockpitTextMatchMode.exact) 'matchMode': match.name,
      },
    );
  }

  @override
  Future<CockpitSnapshot> collectSnapshot({
    CockpitSnapshotOptions options = const CockpitSnapshotOptions.baseline(),
  }) async {
    final execution = await _run(
      CockpitCommandType.collectSnapshot,
      snapshotOptions: options,
    );
    final snapshot = execution.result.snapshot;
    if (snapshot == null) {
      throw StateError('Cockpit snapshot command returned no snapshot.');
    }
    return CockpitSnapshot.fromJson(snapshot);
  }

  @override
  Future<Map<String, Object?>> describeApp() async {
    final execution = await _run(CockpitCommandType.describeApp);
    return execution.result.appState ?? const <String, Object?>{};
  }

  @override
  Future<CockpitCommandExecution> screenshot() =>
      _run(CockpitCommandType.captureScreenshot);

  @override
  Future<CockpitPerformanceReport> profile(
    Future<void> Function() action, {
    String name = 'performance',
  }) async {
    final performance = _performance;
    if (performance == null) {
      throw const CockpitTestCapabilityException('performance');
    }
    final request = CockpitPerformanceCaptureRequest(name: name);
    await performance.startPerformance(request);
    Object? actionError;
    StackTrace? actionStackTrace;
    try {
      await action();
    } on Object catch (error, stackTrace) {
      actionError = error;
      actionStackTrace = stackTrace;
    }

    late final CockpitPerformanceReport report;
    try {
      report = await performance.stopPerformance();
    } on Object catch (cleanupError, cleanupStackTrace) {
      if (actionError != null) {
        throw CockpitTestCleanupException(
          primaryError: actionError,
          primaryStackTrace: actionStackTrace!,
          cleanupError: cleanupError,
          cleanupStackTrace: cleanupStackTrace,
        );
      }
      rethrow;
    }
    if (actionError != null) {
      Error.throwWithStackTrace(actionError, actionStackTrace!);
    }
    return report;
  }

  Future<CockpitCommandExecution> _run(
    CockpitCommandType type, {
    Object? target,
    Map<String, Object?> parameters = const <String, Object?>{},
    CockpitSnapshotOptions? snapshotOptions,
  }) async {
    final command = CockpitCommand(
      commandId: 'programmatic-${++_sequence}-${type.name}',
      commandType: type,
      locator: _locator(target),
      parameters: parameters,
      snapshotOptions: snapshotOptions,
    );
    final execution = await execute(command);
    if (!execution.result.success) {
      throw CockpitTestCommandException(command: command, execution: execution);
    }
    return execution;
  }

  CockpitLocator? _locator(Object? target) {
    if (target == null) return null;
    if (target is CockpitLocator) return target;
    if (target is String) return CockpitSelector.parse(target);
    throw ArgumentError.value(
      target,
      'target',
      'A target must be a selector String or CockpitLocator.',
    );
  }
}
