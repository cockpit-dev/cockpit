import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../remote/cockpit_remote_session_client.dart';
import 'cockpit_application_service_exception.dart';

/// Extracts the live remote-session endpoint of a development session from a
/// `session.development.get` operation output.
///
/// Both the `record` CLI command group and the recorder MCP tools resolve
/// their target app through this single function, so a session is proven
/// ready and its bridge base URL is read exactly once per surface.
Uri cockpitInteractionRecorderBaseUri(Map<String, Object?>? output) {
  final status = output?['status'];
  final statusMap = status is Map<Object?, Object?> ? status : null;
  final runtimeIdentity = output?['runtime'];
  final bridge = runtimeIdentity is Map<Object?, Object?>
      ? runtimeIdentity['bridge']
      : null;
  final baseUrl = bridge is Map<Object?, Object?> ? bridge['baseUrl'] : null;
  final ready =
      statusMap?['state'] == 'ready' &&
      statusMap?['appReachable'] == true &&
      statusMap?['remoteSessionReachable'] == true;
  if (!ready || baseUrl is! String || baseUrl.isEmpty) {
    throw CockpitApplicationServiceException(
      code: 'developmentSessionBridgeUnavailable',
      message:
          'The development session has no ready remote bridge; run '
          '`cockpit dev start` and retry.',
      details: <String, Object?>{
        if (statusMap?['state'] is String) 'state': statusMap?['state'],
      },
    );
  }
  return Uri.parse(baseUrl);
}

/// Drives the interaction recorder on one resolved live session and returns
/// printable payload maps shared by every external surface.
final class CockpitInteractionRecordingService {
  CockpitInteractionRecordingService(this._client);

  factory CockpitInteractionRecordingService.forBaseUri(
    Uri baseUri, {
    String authToken = '',
    Duration requestTimeout = const Duration(seconds: 30),
  }) => CockpitInteractionRecordingService(
    CockpitRemoteSessionClient(
      baseUri: baseUri,
      authToken: authToken,
      requestTimeout: requestTimeout,
    ),
  );

  final CockpitRemoteSessionClient _client;

  Future<Map<String, Object?>> start({String? name}) async =>
      (await _client.startInteractionRecording(name: name)).toJson();

  Future<Map<String, Object?>> pause() async =>
      (await _client.pauseInteractionRecording()).toJson();

  Future<Map<String, Object?>> resume() async =>
      (await _client.resumeInteractionRecording()).toJson();

  Future<Map<String, Object?>> stop() async =>
      (await _client.stopInteractionRecording()).toJson();

  /// Reads the current session, or the minimal idle payload while no session
  /// has started.
  Future<Map<String, Object?>> status() async {
    final session = await _client.interactionRecordingSession();
    return session?.toJson() ?? const <String, Object?>{'phase': 'idle'};
  }

  /// Reads the recorded steps after the caller's consumed-step cursor.
  Future<Map<String, Object?>> steps({int after = 0}) async {
    final drained = await _client.interactionRecordingSteps(after: after);
    return <String, Object?>{
      'steps': <Object?>[for (final step in drained.steps) step.toJson()],
      'total': drained.total,
    };
  }

  Future<CockpitRecordedFlowBundle> export() =>
      _client.exportInteractionRecording();

  /// Shapes one exported flow document: the case YAML, or the complete flow
  /// bundle as JSON.
  Map<String, Object?> exportDocument(
    CockpitRecordedFlowBundle bundle, {
    String format = 'yaml',
  }) => <String, Object?>{
    'format': format,
    'document': format == 'yaml' ? bundle.caseYaml : bundle.toJson(),
  };
}
