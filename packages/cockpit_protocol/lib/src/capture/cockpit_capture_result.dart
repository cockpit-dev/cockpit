import 'cockpit_captured_screenshot.dart';
import 'cockpit_capture_kind.dart';
import 'cockpit_capture_profile.dart';

final class CockpitCaptureResult {
  /// Creates a CockpitCaptureResult.
  const CockpitCaptureResult({
    required this.screenshot,
    required this.requestedProfile,
    required this.resolvedCaptureKind,
    this.usedFallback = false,
    this.degradationReason,
  });

  final CockpitCapturedScreenshot screenshot;
  final CockpitCaptureProfile requestedProfile;
  final CockpitCaptureKind resolvedCaptureKind;
  final bool usedFallback;
  final String? degradationReason;
}
