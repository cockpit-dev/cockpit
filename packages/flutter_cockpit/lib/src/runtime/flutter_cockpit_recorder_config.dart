import 'package:flutter/foundation.dart';

import '../recorder/cockpit_interaction_capture.dart';

/// How the recorder host presents itself once mounted.
enum CockpitRecorderHostMode {
  /// Draggable floating ball that expands into the default panel sheet.
  floatingBall,

  /// No entry of its own; the panel content embeds into an existing host
  /// window.
  guest,

  /// No UI at all — the recorder runs through commands only.
  headless,
}

/// Configuration for the in-app interaction recorder.
///
/// Recording is a development capability: `enabled` defaults to `false`, and
/// requesting it in a release build is a configuration error (see
/// [assertFlutterCockpitRecorderBuildMode]).
final class FlutterCockpitRecorderConfig {
  /// Creates a recorder configuration.
  const FlutterCockpitRecorderConfig({
    this.enabled = false,
    this.host = CockpitRecorderHostMode.floatingBall,
    this.defaults = const CockpitInteractionCaptureDefaults(),
  });

  /// Whether the runtime mounts the interaction recorder and its capture
  /// layer.
  final bool enabled;

  /// Presentation mode of the recorder host.
  final CockpitRecorderHostMode host;

  /// Classification and settle thresholds for the capture layer.
  final CockpitInteractionCaptureDefaults defaults;

  FlutterCockpitRecorderConfig copyWith({
    bool? enabled,
    CockpitRecorderHostMode? host,
    CockpitInteractionCaptureDefaults? defaults,
  }) {
    return FlutterCockpitRecorderConfig(
      enabled: enabled ?? this.enabled,
      host: host ?? this.host,
      defaults: defaults ?? this.defaults,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is FlutterCockpitRecorderConfig &&
            other.enabled == enabled &&
            other.host == host &&
            other.defaults == defaults;
  }

  @override
  int get hashCode => Object.hash(enabled, host, defaults);
}

/// Rejects recorder configurations the current build mode cannot honor.
///
/// Invoked at runtime initialization (`FlutterCockpit.initialize`) — the
/// earliest point every configuration path funnels through. [releaseMode] is
/// a parameter so the guard stays testable in debug builds.
void assertFlutterCockpitRecorderBuildMode({
  required FlutterCockpitRecorderConfig config,
  required bool releaseMode,
}) {
  if (config.enabled && releaseMode) {
    throw FlutterError(
      'FlutterCockpitRecorderConfig.enabled must be false in release mode: '
      'interaction recording is a development capability and is not compiled '
      'into release builds.',
    );
  }
}
