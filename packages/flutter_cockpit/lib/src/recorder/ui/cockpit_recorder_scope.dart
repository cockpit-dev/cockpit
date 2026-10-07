import 'package:flutter/widgets.dart';

import 'cockpit_recorder_controller.dart';

/// Provides the [CockpitRecorderController] to recorder panels.
///
/// Mounted by `FlutterCockpitRoot` around its whole subtree (app plus HUD
/// host) whenever the recorder is enabled, so a panel embedded anywhere in
/// the app — and the default floating-ball host — resolve the same
/// controller.
final class CockpitRecorderScope extends InheritedWidget {
  /// Creates a scope exposing [controller].
  const CockpitRecorderScope({required this.controller, required super.child});

  /// The controller panels below this scope bind to.
  final CockpitRecorderController controller;

  /// The nearest scope's controller, or `null` when the recorder is
  /// disabled or no scope is mounted.
  static CockpitRecorderController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<CockpitRecorderScope>()
        ?.controller;
  }

  /// The nearest scope's controller; throws when no scope is mounted.
  static CockpitRecorderController of(BuildContext context) {
    final controller = maybeOf(context);
    if (controller == null) {
      throw FlutterError(
        'CockpitRecorderScope.of called with a context that has no '
        'CockpitRecorderScope ancestor. Enable the interaction recorder in '
        'FlutterCockpitConfiguration, or mount a scope around the panel.',
      );
    }
    return controller;
  }

  @override
  bool updateShouldNotify(CockpitRecorderScope oldWidget) {
    return oldWidget.controller != controller;
  }
}
