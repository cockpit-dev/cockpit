import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'cockpit_locale.dart';

/// The platform-neutral behavior surface shared by every Cockpit runner.
///
/// Runner lifecycle, process ownership, installation, and cleanup stay
/// outside this interface. Implementations may expose richer platform
/// extensions, but a reusable scenario should only depend on this contract.
abstract interface class CockpitTester {
  CockpitLocaleProfile get locale;

  Future<CockpitCapabilities> describeCapabilities();

  Future<CockpitCommandExecution> execute(CockpitCommand command);

  Future<CockpitCommandExecution> tap(Object? target);

  Future<CockpitCommandExecution> type(String value, {required Object into});

  Future<CockpitCommandExecution> clear(Object target);

  Future<CockpitCommandExecution> focus(Object target);

  Future<CockpitCommandExecution> press(
    CockpitTextInputAction action, {
    Object? target,
  });

  Future<CockpitCommandExecution> scroll(Object target);

  Future<CockpitCommandExecution> waitForUi();

  Future<CockpitCommandExecution> expectVisible(Object target);

  Future<CockpitCommandExecution> expectText(Object target, Object expected);

  Future<CockpitCommandExecution> screenshot();

  Future<CockpitPerformanceReport> profile(
    Future<void> Function() action, {
    String name,
  });
}
