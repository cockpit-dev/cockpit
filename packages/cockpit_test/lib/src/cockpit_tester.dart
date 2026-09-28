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

  /// Waits until [target] is present, or until it is gone when [absent] is
  /// true. Waiting for absence is the shared way to assert that something
  /// disappeared: every runner surfaces it as the same protocol wait.
  Future<CockpitCommandExecution> waitFor(Object target, {bool absent});

  Future<CockpitCommandExecution> expectVisible(Object target);

  /// Asserts [target]'s text matches [expected] using [match]; the localized
  /// text form resolves against the active locale first.
  Future<CockpitCommandExecution> expectText(
    Object target,
    Object expected, {
    CockpitTextMatchMode match,
  });

  /// Reads the current target tree back as a [CockpitSnapshot] so scenario
  /// code can inspect real state instead of only issuing assertions.
  Future<CockpitSnapshot> collectSnapshot({CockpitSnapshotOptions options});

  /// Reads app-authored state — whatever the application chose to expose
  /// through its app state provider, evaluated at call time. Targets without
  /// a provider answer with an unsupported-capability failure, which the
  /// runner reports as a blocked attempt.
  Future<Map<String, Object?>> describeApp();

  Future<CockpitCommandExecution> screenshot();

  Future<CockpitPerformanceReport> profile(
    Future<void> Function() action, {
    String name,
  });
}
