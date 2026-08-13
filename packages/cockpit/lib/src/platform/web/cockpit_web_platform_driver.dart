import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../../bridge/cockpit_browser_recording_adapter_resolver.dart';
import '../cockpit_platform_driver.dart';

/// Describes the static capabilities of a Flutter Web launch target.
///
/// Generic browser-page DOM automation is advertised separately by the live
/// system-control profile only after its registered CDP endpoint is reachable.
final class CockpitWebPlatformDriver implements CockpitPlatformDriver {
  CockpitWebPlatformDriver({
    required String deviceId,
    bool Function(String deviceId) browserRecordingSupportResolver =
        cockpitSupportsBrowserRecordingDeviceId,
  }) : _deviceId = deviceId,
       _browserRecordingSupportResolver = browserRecordingSupportResolver;

  final String _deviceId;
  final bool Function(String deviceId) _browserRecordingSupportResolver;

  @override
  String get platform => 'web';

  @override
  Future<CockpitCapabilityProfile> describeCapabilities() async {
    final supportsBrowserRecording = _browserRecordingSupportResolver(
      _deviceId,
    );
    return CockpitCapabilityProfile(
      targetKind: CockpitTargetKind.browserPage,
      surfaceKinds: <CockpitSurfaceKind>{CockpitSurfaceKind.browserDom},
      actionCapabilities: <CockpitActionCapability>{
        CockpitActionCapability.captureScreenshot,
        if (supportsBrowserRecording) CockpitActionCapability.startRecording,
        if (supportsBrowserRecording) CockpitActionCapability.stopRecording,
        CockpitActionCapability.readLogs,
      },
      evidenceCapabilities: <CockpitEvidenceCapability>{
        if (supportsBrowserRecording) CockpitEvidenceCapability.screenRecording,
        CockpitEvidenceCapability.runtimeErrors,
        CockpitEvidenceCapability.networkSignals,
      },
      qualityFlags: <CockpitQualityFlag>{
        CockpitQualityFlag.requiresBrowserDriver,
      },
    );
  }
}
