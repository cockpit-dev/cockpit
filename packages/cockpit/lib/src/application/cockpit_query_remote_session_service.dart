export 'cockpit_application_service_exception.dart';

import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../session/cockpit_remote_session_handle.dart';
import '../session/cockpit_remote_session_launcher.dart';
import 'cockpit_session_reference_resolver.dart';

final class CockpitQueryRemoteSessionRequest {
  const CockpitQueryRemoteSessionRequest({
    this.baseUri,
    this.sessionHandle,
    this.sessionHandlePath,
    this.androidDeviceId,
    this.iosDeviceId,
  });

  final Uri? baseUri;
  final CockpitRemoteSessionHandle? sessionHandle;
  final String? sessionHandlePath;
  final String? androidDeviceId;
  final String? iosDeviceId;
}

final class CockpitQueryRemoteSessionResult {
  const CockpitQueryRemoteSessionResult({
    required this.status,
    required this.recommendedNextStep,
    this.sessionHandle,
  });

  final CockpitRemoteSessionStatus status;
  final CockpitRemoteSessionHandle? sessionHandle;
  final String recommendedNextStep;
}

final class CockpitQueryRemoteSessionService {
  CockpitQueryRemoteSessionService({
    CockpitRemoteSessionStatusReader? statusReader,
    CockpitSessionReferenceResolver? sessionReferenceResolver,
  }) : _statusReader = statusReader ?? cockpitReadRemoteSessionStatus,
       _sessionReferenceResolver =
           sessionReferenceResolver ?? CockpitSessionReferenceResolver();

  final CockpitRemoteSessionStatusReader _statusReader;
  final CockpitSessionReferenceResolver _sessionReferenceResolver;

  Future<CockpitQueryRemoteSessionResult> query(
    CockpitQueryRemoteSessionRequest request,
  ) async {
    final resolved = await _sessionReferenceResolver.resolve(
      baseUri: request.baseUri,
      sessionHandle: request.sessionHandle,
      sessionHandlePath: request.sessionHandlePath,
      androidDeviceId: request.androidDeviceId,
      iosDeviceId: request.iosDeviceId,
    );
    final status = await _statusReader(
      resolved.baseUri,
      authToken: resolved.sessionHandle?.authToken ?? '',
    );

    return CockpitQueryRemoteSessionResult(
      status: status,
      sessionHandle: resolved.sessionHandle,
      recommendedNextStep: _recommendedNextStep(status),
    );
  }

  String _recommendedNextStep(CockpitRemoteSessionStatus status) {
    if (status.capabilities.supportsInAppControl) {
      return 'ready_for_commands';
    }
    return 'limited_capabilities';
  }
}
