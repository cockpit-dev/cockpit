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
class CockpitAutomationTester implements CockpitTester {
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

  /// Whether this target can collect a real performance report.
  bool get supportsPerformance => _performance != null;

  @override
  CockpitLocaleProfile get locale => _localeProvider?.call() ?? _initialLocale;

  @override
  Future<CockpitCapabilities> describeCapabilities() =>
      _automation.describeCapabilities();

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
  }) =>
      _run(
        CockpitCommandType.sendTextInputAction,
        target: target,
        parameters: <String, Object?>{'inputAction': action.name},
      );

  @override
  Future<CockpitCommandExecution> scroll(Object target) => _run(
    CockpitCommandType.scrollUntilVisible,
    target: target,
  );

  @override
  Future<CockpitCommandExecution> waitForUi() =>
      _run(CockpitCommandType.waitForUiIdle);

  @override
  Future<CockpitCommandExecution> expectVisible(Object target) =>
      _run(CockpitCommandType.assertVisible, target: target);

  @override
  Future<CockpitCommandExecution> expectText(Object target, Object expected) {
    final resolved = expected is CockpitLocalizedText
        ? expected.resolve(locale)
        : expected.toString();
    return _run(
      CockpitCommandType.assertText,
      target: target,
      parameters: <String, Object?>{'text': resolved},
    );
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
    CockpitPerformanceReport? report;
    try {
      await action();
    } finally {
      // Stop is deliberately awaited even when the action fails so a target
      // never retains an active capture window after a failed scenario.
      report = await performance.stopPerformance();
    }
    return report;
  }

  Future<CockpitCommandExecution> _run(
    CockpitCommandType type, {
    Object? target,
    Map<String, Object?> parameters = const <String, Object?>{},
  }) async {
    final command = CockpitCommand(
      commandId: 'programmatic-${++_sequence}-${type.name}',
      commandType: type,
      locator: _locator(target),
      parameters: parameters,
    );
    final execution = await execute(command);
    if (!execution.result.success) {
      throw CockpitTestCommandException(
        command: command,
        execution: execution,
      );
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
