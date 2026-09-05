import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter/widgets.dart';

/// Default budget for one in-app integration-test command.
const Duration cockpitIntegrationTestDefaultTimeout = Duration(seconds: 10);

/// Default budget for native capture, recording, and viewport calls.
///
/// Native calls may cross a platform boundary or wait for an OS consent
/// surface, so they intentionally get a wider budget than ordinary UI
/// commands. Individual calls can still provide a smaller or larger timeout.
const Duration cockpitIntegrationTestNativeTimeout = Duration(minutes: 2);

/// Hard upper bound for a single integration-test operation.
const Duration cockpitIntegrationTestMaximumTimeout = Duration(hours: 1);

/// Builds the application child mounted inside [FlutterCockpitApp].
typedef CockpitTestAppBuilder = Widget Function();

/// Handles a host-side Cockpit command when a Dart integration test needs to
/// cross from Flutter into an OS or device automation plane.
///
/// The callback is explicit by design: native/system actions can affect the
/// device or host and must never be hidden behind an in-app assertion helper.
typedef CockpitHostCommandHandler =
    Future<CockpitCommandExecution> Function(CockpitCommand command);

/// Configuration for [cockpitTestWidgets].
final class CockpitTestOptions {
  const CockpitTestOptions({
    this.config = const FlutterCockpitConfig.production(),
    this.platform,
    this.commandTimeout = cockpitIntegrationTestDefaultTimeout,
    this.nativeTimeout = cockpitIntegrationTestNativeTimeout,
    this.initialPump = const Duration(milliseconds: 120),
    this.pumpAfterCommand = true,
    this.failFast = true,
    this.hostCommand,
    this.requiredBuildMode,
  });

  /// Runtime configuration used by the development-only Cockpit wrapper.
  final FlutterCockpitConfig config;

  /// Optional platform label reported by the in-app executor.
  final String? platform;

  /// Default timeout applied to commands created by the facade.
  final Duration commandTimeout;

  /// Default timeout applied to native capture, recording, viewport, and
  /// host-boundary calls exposed by [CockpitTester.native].
  final Duration nativeTimeout;

  /// Advances the test clock once after the first frame so async app bootstrap
  /// work can publish its initial UI without requiring an unbounded settle.
  final Duration initialPump;

  /// Pumps one frame after a command to expose synchronous widget mutations.
  final bool pumpAfterCommand;

  /// Converts an unsuccessful command into a Flutter test failure.
  final bool failFast;

  /// Optional explicit bridge for host/system-plane actions.
  final CockpitHostCommandHandler? hostCommand;

  /// Fails the test before the body when the runner is not using this mode.
  /// Flutter's official integration runner chooses the mode; this option only
  /// verifies it and never pretends that a debug run is profile or release.
  final CockpitTestBuildMode? requiredBuildMode;
}
