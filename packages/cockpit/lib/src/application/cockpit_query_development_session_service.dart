import 'package:cockpit/src/development/cockpit_development_session_handle.dart';
import 'package:cockpit/src/development/cockpit_development_session_reference_resolver.dart';
import 'package:cockpit/src/development/cockpit_development_session_status.dart';
import 'package:cockpit/src/development/cockpit_development_session_supervisor_client.dart';

typedef CockpitDevelopmentSessionStatusReader =
    Future<CockpitDevelopmentSessionSupervisorResponse> Function(
      Uri supervisorBaseUri,
    );

final class CockpitQueryDevelopmentSessionRequest {
  const CockpitQueryDevelopmentSessionRequest({
    this.sessionHandle,
    this.sessionHandlePath,
  });

  final CockpitDevelopmentSessionHandle? sessionHandle;
  final String? sessionHandlePath;
}

final class CockpitQueryDevelopmentSessionResult {
  const CockpitQueryDevelopmentSessionResult({
    required this.status,
    required this.recommendedNextStep,
    this.sessionHandle,
  });

  final CockpitDevelopmentSessionStatus status;
  final CockpitDevelopmentSessionHandle? sessionHandle;
  final String recommendedNextStep;
}

final class CockpitQueryDevelopmentSessionService {
  CockpitQueryDevelopmentSessionService({
    CockpitDevelopmentSessionStatusReader? statusReader,
    CockpitDevelopmentSessionReferenceResolver? sessionReferenceResolver,
    CockpitDevelopmentSessionSupervisorClient? supervisorClient,
  }) : _statusReader =
           statusReader ??
           (supervisorClient ?? CockpitDevelopmentSessionSupervisorClient())
               .readStatus,
       _sessionReferenceResolver =
           sessionReferenceResolver ??
           const CockpitDevelopmentSessionReferenceResolver();

  final CockpitDevelopmentSessionStatusReader _statusReader;
  final CockpitDevelopmentSessionReferenceResolver _sessionReferenceResolver;

  Future<CockpitQueryDevelopmentSessionResult> query(
    CockpitQueryDevelopmentSessionRequest request,
  ) async {
    final resolved = await _sessionReferenceResolver.resolve(
      sessionHandle: request.sessionHandle,
      sessionHandlePath: request.sessionHandlePath,
    );
    final response = await _statusReader(resolved.supervisorBaseUri);

    return CockpitQueryDevelopmentSessionResult(
      status: response.status,
      sessionHandle: response.sessionHandle,
      recommendedNextStep: _recommendedNextStep(response.status),
    );
  }

  String _recommendedNextStep(CockpitDevelopmentSessionStatus status) {
    if (status.state == CockpitDevelopmentSessionState.starting &&
        status.appReachable == null) {
      return 'discover_platform_target';
    }
    return switch (status.state) {
      CockpitDevelopmentSessionState.ready => 'ready_for_incremental_probe',
      CockpitDevelopmentSessionState.starting ||
      CockpitDevelopmentSessionState.reloading ||
      CockpitDevelopmentSessionState.restarting => 'wait_for_ready',
      CockpitDevelopmentSessionState.stopped => 'launch_development_session',
      CockpitDevelopmentSessionState.failed => 'relaunch_development_session',
    };
  }
}
