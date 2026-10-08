import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../remote/cockpit_remote_session_client.dart';
import 'cockpit_application_service_exception.dart';

/// Executes one `recorder.*` supervisor operation with the session-scoped
/// input the interaction recording service assembled.
typedef CockpitInteractionRecorderOperation =
    Future<CockpitOperationResult> Function(
      String kind,
      Map<String, Object?> input,
    );

/// Drives the interaction recorder on one resolved session and returns the
/// printable payload maps shared by every external surface.
///
/// Supervised sessions use the operation mode ([CockpitInteractionRecordingService.forOperations]):
/// every call executes the matching `recorder.*` supervisor operation, which
/// the workspace worker proxies to the app's recorder endpoints — the app's
/// bridge address never leaves the worker. `forBaseUri` keeps a
/// direct-connection mode for apps launched outside a managed session
/// (`cockpit record --endpoint`).
final class CockpitInteractionRecordingService {
  CockpitInteractionRecordingService.forOperations({
    required CockpitInteractionRecorderOperation execute,
    required String sessionId,
  }) : _execute = execute,
       _sessionId = sessionId,
       _client = null;

  factory CockpitInteractionRecordingService.forBaseUri(
    Uri baseUri, {
    String authToken = '',
    Duration requestTimeout = const Duration(seconds: 30),
  }) => CockpitInteractionRecordingService._direct(
    CockpitRemoteSessionClient(
      baseUri: baseUri,
      authToken: authToken,
      requestTimeout: requestTimeout,
    ),
  );

  CockpitInteractionRecordingService._direct(CockpitRemoteSessionClient client)
    : _execute = null,
      _sessionId = null,
      _client = client;

  final CockpitInteractionRecorderOperation? _execute;
  final String? _sessionId;
  final CockpitRemoteSessionClient? _client;

  Future<Map<String, Object?>> start({String? name}) async {
    final client = _client;
    if (client != null) {
      return (await client.startInteractionRecording(name: name)).toJson();
    }
    return _invoke('recorder.start', <String, Object?>{'name': ?name});
  }

  Future<Map<String, Object?>> pause() async {
    final client = _client;
    if (client != null) {
      return (await client.pauseInteractionRecording()).toJson();
    }
    return _invoke('recorder.pause', const <String, Object?>{});
  }

  Future<Map<String, Object?>> resume() async {
    final client = _client;
    if (client != null) {
      return (await client.resumeInteractionRecording()).toJson();
    }
    return _invoke('recorder.resume', const <String, Object?>{});
  }

  Future<Map<String, Object?>> stop() async {
    final client = _client;
    if (client != null) {
      return (await client.stopInteractionRecording()).toJson();
    }
    return _invoke('recorder.stop', const <String, Object?>{});
  }

  /// Reads the current session, or the minimal idle payload while no session
  /// has started.
  Future<Map<String, Object?>> status() async {
    final client = _client;
    if (client != null) {
      final session = await client.interactionRecordingSession();
      return session?.toJson() ?? const <String, Object?>{'phase': 'idle'};
    }
    return _invoke('recorder.get', const <String, Object?>{});
  }

  /// Reads the recorded steps after the caller's consumed-step cursor.
  Future<Map<String, Object?>> steps({int after = 0}) async {
    if (after < 0 || after > 1000000) {
      throw const FormatException(
        'Steps cursor after must be between 0 and 1000000.',
      );
    }
    final client = _client;
    if (client != null) {
      final drained = await client.interactionRecordingSteps(after: after);
      return <String, Object?>{
        'steps': <Object?>[for (final step in drained.steps) step.toJson()],
        'total': drained.total,
      };
    }
    return _invoke('recorder.steps', <String, Object?>{'after': after});
  }

  Future<CockpitRecordedFlowBundle> export() async {
    final client = _client;
    if (client != null) {
      return client.exportInteractionRecording();
    }
    return CockpitRecordedFlowBundle.fromJson(
      await _invoke('recorder.export', const <String, Object?>{}),
    );
  }

  /// Shapes one exported flow document: the case YAML, or the complete flow
  /// bundle as JSON.
  Map<String, Object?> exportDocument(
    CockpitRecordedFlowBundle bundle, {
    String format = 'yaml',
  }) => <String, Object?>{
    'format': format,
    'document': format == 'yaml' ? bundle.caseYaml : bundle.toJson(),
  };

  Future<Map<String, Object?>> _invoke(
    String kind,
    Map<String, Object?> extra,
  ) async {
    final result = await _execute!(kind, <String, Object?>{
      'sessionId': _sessionId,
      ...extra,
    });
    if (result.lifecycle != CockpitOperationLifecycle.completed ||
        result.outcome != CockpitOperationOutcome.succeeded) {
      final failure = result.failure?.primary;
      throw CockpitApplicationServiceException(
        code: failure?.code ?? 'recorderOperationFailed',
        message: failure == null
            ? 'Interaction recorder operation $kind did not complete for '
                  'session $_sessionId.'
            : 'Interaction recorder operation $kind failed for session '
                  '$_sessionId: ${failure.message}',
        details: <String, Object?>{'kind': kind},
      );
    }
    return result.output ?? const <String, Object?>{};
  }
}
