import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// A snapshot of Flutter's runtime debugging switches that DevTools exposes.
final class CockpitDebugToolsState {
  const CockpitDebugToolsState({
    required this.paintSize,
    required this.paintBaselines,
    required this.paintPointers,
    required this.repaintRainbow,
    required this.performanceOverlay,
    required this.profileBuilds,
    required this.profileUserBuilds,
    required this.profileLayouts,
    required this.profilePaints,
    required this.printRebuilds,
    required this.timeDilation,
  });

  final bool paintSize;
  final bool paintBaselines;
  final bool paintPointers;
  final bool repaintRainbow;
  final bool performanceOverlay;
  final bool profileBuilds;
  final bool profileUserBuilds;
  final bool profileLayouts;
  final bool profilePaints;
  final bool printRebuilds;
  final double timeDilation;

  Map<String, Object?> toJson() => <String, Object?>{
    'paintSize': paintSize,
    'paintBaselines': paintBaselines,
    'paintPointers': paintPointers,
    'repaintRainbow': repaintRainbow,
    'performanceOverlay': performanceOverlay,
    'profileBuilds': profileBuilds,
    'profileUserBuilds': profileUserBuilds,
    'profileLayouts': profileLayouts,
    'profilePaints': profilePaints,
    'printRebuilds': printRebuilds,
    'timeDilation': timeDilation,
  };
}

/// Controls the same visual and timeline switches used by Flutter DevTools.
///
/// Values are process-global in Flutter. The facade snapshots them when it is
/// created and restores that snapshot explicitly at test tear-down, preventing
/// one integration test from leaking debug overlays or slowed animations into
/// the next test.
final class CockpitDebugTools {
  CockpitDebugTools() : _initial = _readCurrent();

  final CockpitDebugToolsState _initial;

  CockpitDebugToolsState get current => CockpitDebugToolsState(
    paintSize: debugPaintSizeEnabled,
    paintBaselines: debugPaintBaselinesEnabled,
    paintPointers: debugPaintPointersEnabled,
    repaintRainbow: debugRepaintRainbowEnabled,
    performanceOverlay: WidgetsApp.showPerformanceOverlayOverride,
    profileBuilds: debugProfileBuildsEnabled,
    profileUserBuilds: debugProfileBuildsEnabledUserWidgets,
    profileLayouts: debugProfileLayoutsEnabled,
    profilePaints: debugProfilePaintsEnabled,
    printRebuilds: debugPrintRebuildDirtyWidgets,
    timeDilation: timeDilation,
  );

  static CockpitDebugToolsState _readCurrent() => CockpitDebugToolsState(
    paintSize: debugPaintSizeEnabled,
    paintBaselines: debugPaintBaselinesEnabled,
    paintPointers: debugPaintPointersEnabled,
    repaintRainbow: debugRepaintRainbowEnabled,
    performanceOverlay: WidgetsApp.showPerformanceOverlayOverride,
    profileBuilds: debugProfileBuildsEnabled,
    profileUserBuilds: debugProfileBuildsEnabledUserWidgets,
    profileLayouts: debugProfileLayoutsEnabled,
    profilePaints: debugProfilePaintsEnabled,
    printRebuilds: debugPrintRebuildDirtyWidgets,
    timeDilation: timeDilation,
  );

  CockpitDebugToolsState apply({
    bool? paintSize,
    bool? paintBaselines,
    bool? paintPointers,
    bool? repaintRainbow,
    bool? performanceOverlay,
    bool? profileBuilds,
    bool? profileUserBuilds,
    bool? profileLayouts,
    bool? profilePaints,
    bool? printRebuilds,
    double? timeScale,
  }) {
    if (timeScale != null && (!timeScale.isFinite || timeScale <= 0)) {
      throw ArgumentError.value(
        timeScale,
        'timeScale',
        'Must be positive and finite.',
      );
    }
    if (paintSize != null) debugPaintSizeEnabled = paintSize;
    if (paintBaselines != null) debugPaintBaselinesEnabled = paintBaselines;
    if (paintPointers != null) debugPaintPointersEnabled = paintPointers;
    if (repaintRainbow != null) debugRepaintRainbowEnabled = repaintRainbow;
    if (performanceOverlay != null) {
      WidgetsApp.showPerformanceOverlayOverride = performanceOverlay;
    }
    if (profileBuilds != null) debugProfileBuildsEnabled = profileBuilds;
    if (profileUserBuilds != null) {
      debugProfileBuildsEnabledUserWidgets = profileUserBuilds;
    }
    if (profileLayouts != null) debugProfileLayoutsEnabled = profileLayouts;
    if (profilePaints != null) debugProfilePaintsEnabled = profilePaints;
    if (printRebuilds != null) debugPrintRebuildDirtyWidgets = printRebuilds;
    if (timeScale != null) timeDilation = timeScale;
    return current;
  }

  CockpitDebugToolsState restore() {
    final value = _initial;
    return apply(
      paintSize: value.paintSize,
      paintBaselines: value.paintBaselines,
      paintPointers: value.paintPointers,
      repaintRainbow: value.repaintRainbow,
      performanceOverlay: value.performanceOverlay,
      profileBuilds: value.profileBuilds,
      profileUserBuilds: value.profileUserBuilds,
      profileLayouts: value.profileLayouts,
      profilePaints: value.profilePaints,
      printRebuilds: value.printRebuilds,
      timeScale: value.timeDilation,
    );
  }
}
