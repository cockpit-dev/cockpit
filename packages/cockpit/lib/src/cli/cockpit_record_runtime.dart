import '../application/cockpit_interaction_recording_service.dart';
import 'cockpit_cli_runtime.dart';
import 'cockpit_dev_runtime.dart';

/// Resolves the live app endpoint behind the `record` command group.
///
/// Session resolution mirrors `cockpit dev` exactly: the bound CLI session
/// handle is reconciled through the supervisor `session.development.get`
/// operation and the live remote bridge base URL is read from its output, so
/// no second discovery path exists. `--endpoint` bypasses discovery for apps
/// launched outside a development session.
final class CockpitRecordRuntime {
  CockpitRecordRuntime(this.runtime, this.dev);

  final CockpitCliRuntime runtime;
  final CockpitDevRuntime dev;

  /// Resolves the recording service for one recorder operation.
  ///
  /// Returns the service, or the exit code of the failure envelope that was
  /// already written.
  Future<(CockpitInteractionRecordingService?, int)> resolve({
    required String action,
    String? session,
    String? endpoint,
  }) async {
    if (endpoint != null) {
      return (
        CockpitInteractionRecordingService.forBaseUri(
          _endpointUri(endpoint),
          requestTimeout: runtime.operationTimeout,
        ),
        cockpitSuccessExitCode,
      );
    }
    final handle = await runtime.resolveDevelopmentSession(session);
    final read = await dev.invokeRead(
      handle,
      'session.development.get',
      const <String, Object?>{},
    );
    final unavailable = read.unavailable;
    if (unavailable != null) {
      return (
        null,
        await dev.writeUnavailable(action: action, resolution: unavailable),
      );
    }
    final result = read.result!;
    if (!dev.operationSucceeded(result)) {
      return (
        null,
        await dev.writeOperation(
          action: action,
          session: read.session,
          result: result,
          state: result.output,
          changed: read.changed,
        ),
      );
    }
    final resolved = read.session;
    return (
      CockpitInteractionRecordingService.forBaseUri(
        cockpitInteractionRecorderBaseUri(result.output),
        authToken: resolved.authenticationEnabled ? resolved.authToken : '',
        requestTimeout: runtime.operationTimeout,
      ),
      cockpitSuccessExitCode,
    );
  }
}

Uri _endpointUri(String raw) {
  final uri = Uri.tryParse(raw.trim());
  final scheme = uri?.scheme.toLowerCase();
  if (uri == null ||
      (scheme != 'http' && scheme != 'https') ||
      uri.host.isEmpty) {
    throw const FormatException('--endpoint must be an absolute http(s) URL.');
  }
  return uri;
}
