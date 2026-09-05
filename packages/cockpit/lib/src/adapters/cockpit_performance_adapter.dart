import 'package:cockpit_protocol/cockpit_protocol.dart';

/// Controls an application-owned performance capture window.
///
/// A case runner owns at most one active window per target. Implementations
/// must close their window on stop and return the report that was actually
/// collected by the target; requested build modes are never substituted into
/// the report.
abstract interface class CockpitPerformanceAdapter {
  Future<CockpitPerformanceCaptureSession> startPerformance(
    CockpitPerformanceCaptureRequest request,
  );

  Future<CockpitPerformanceReport> stopPerformance();
}
