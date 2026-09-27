enum CockpitTestFeature {
  inAppControl,
  flutterViewCapture,
  nativeScreenCapture,
  hostAutomation,
  viewportResize,
  performanceCapture,
}

abstract interface class CockpitTestFeatureProvider {
  Future<Set<CockpitTestFeature>> describeFeatures();
}
