import '../remote/cockpit_remote_session_client.dart';
import 'cockpit_app_handle.dart';

/// Drives the interaction recorder of one resolved live app for the worker's
/// `recorder.*` operations.
///
/// The worker owns the un-sanitized app handle, so it can dial the app's
/// recorder endpoints directly through [CockpitRemoteSessionClient] and return
/// each endpoint's raw JSON. App error envelopes (for example a recorder that
/// is not enabled) surface as [CockpitApplicationServiceException] with the
/// app's error code, which the worker reports as the operation failure.
final class CockpitInteractionRecorderAppService {
  Future<Map<String, Object?>> start(
    CockpitAppHandle app, {
    String? name,
    Duration? requestTimeout,
  }) async => (await _client(
    app,
    requestTimeout,
  ).startInteractionRecording(name: name)).toJson();

  Future<Map<String, Object?>> pause(
    CockpitAppHandle app, {
    Duration? requestTimeout,
  }) async =>
      (await _client(app, requestTimeout).pauseInteractionRecording()).toJson();

  Future<Map<String, Object?>> resume(
    CockpitAppHandle app, {
    Duration? requestTimeout,
  }) async => (await _client(
    app,
    requestTimeout,
  ).resumeInteractionRecording()).toJson();

  Future<Map<String, Object?>> stop(
    CockpitAppHandle app, {
    Duration? requestTimeout,
  }) async =>
      (await _client(app, requestTimeout).stopInteractionRecording()).toJson();

  /// Reads the current session snapshot, or the minimal idle payload while no
  /// session has started.
  Future<Map<String, Object?>> session(
    CockpitAppHandle app, {
    Duration? requestTimeout,
  }) async {
    final session = await _client(
      app,
      requestTimeout,
    ).interactionRecordingSession();
    return session?.toJson() ?? const <String, Object?>{'phase': 'idle'};
  }

  /// Reads the recorded steps after the caller's consumed-step cursor.
  Future<Map<String, Object?>> steps(
    CockpitAppHandle app, {
    int after = 0,
    Duration? requestTimeout,
  }) async {
    final drained = await _client(
      app,
      requestTimeout,
    ).interactionRecordingSteps(after: after);
    return <String, Object?>{
      'steps': <Object?>[for (final step in drained.steps) step.toJson()],
      'total': drained.total,
    };
  }

  /// Exports the recorded interaction flow as a bundle JSON object.
  Future<Map<String, Object?>> export(
    CockpitAppHandle app, {
    Duration? requestTimeout,
  }) async => (await _client(
    app,
    requestTimeout,
  ).exportInteractionRecording()).toJson();

  CockpitRemoteSessionClient _client(CockpitAppHandle app, Duration? timeout) =>
      CockpitRemoteSessionClient(
        baseUri: app.baseUri,
        authToken: app.authToken,
        requestTimeout: timeout,
      );
}
