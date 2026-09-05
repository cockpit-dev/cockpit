import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../adapters/cockpit_performance_adapter.dart';
import 'cockpit_remote_session_client.dart';

final class CockpitRemotePerformanceAdapter
    implements CockpitPerformanceAdapter {
  CockpitRemotePerformanceAdapter({required CockpitRemoteSessionClient client})
    : _client = client;

  final CockpitRemoteSessionClient _client;

  @override
  Future<CockpitPerformanceCaptureSession> startPerformance(
    CockpitPerformanceCaptureRequest request,
  ) => _client.startPerformance(request);

  @override
  Future<CockpitPerformanceReport> stopPerformance() =>
      _client.stopPerformance();
}
