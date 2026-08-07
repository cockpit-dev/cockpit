import 'package:cockpit/src/worker/cockpit_worker_protocol_request.dart';
import 'package:cockpit/src/worker/cockpit_worker_protocol_result.dart';
import 'package:cockpit/src/worker/cockpit_worker_protocol_schema.dart';
import 'package:cockpit/src/worker/cockpit_worker_value_reader.dart';
import 'package:test/test.dart';

void main() {
  test('session artifact worker request is strict and ownership scoped', () {
    final request = CockpitWorkerReadSessionArtifactRequest(
      protocolVersion: cockpitWorkerProtocolVersion,
      workspaceId: 'workspace-1',
      requestId: 'request-1',
      deadline: DateTime.utc(2026, 8, 4, 12),
      idempotencyKey: 'read-1',
      sessionId: 'session-1',
      artifactId: 'artifact-1',
    );

    CockpitWorkerProtocolSchema.validateRequest(
      request.method,
      request.toJson(),
    );
    final decoded =
        CockpitWorkerProtocolRequest.fromJson(request.method, request.toJson())
            as CockpitWorkerReadSessionArtifactRequest;
    expect(decoded.workspaceId, 'workspace-1');
    expect(decoded.sessionId, 'session-1');
    expect(decoded.artifactId, 'artifact-1');
  });

  test('session artifact worker result carries integrity metadata only', () {
    final digest = List<String>.filled(64, 'a').join();
    final result = CockpitWorkerReadSessionArtifactResult(
      sessionId: 'session-1',
      artifactId: 'artifact-1',
      kind: 'screenshot',
      name: 'current.png',
      mediaType: 'image/png',
      retainedPath: '/tmp/cockpit/current.png',
      sizeBytes: 128,
      sha256: digest,
    );

    CockpitWorkerProtocolSchema.validateResult(result.method, result.toJson());
    final decoded =
        CockpitWorkerProtocolResult.fromJson(result.method, result.toJson())
            as CockpitWorkerReadSessionArtifactResult;
    expect(decoded.mediaType, 'image/png');
    expect(decoded.sizeBytes, 128);
    expect(decoded.sha256, digest);
  });
}
