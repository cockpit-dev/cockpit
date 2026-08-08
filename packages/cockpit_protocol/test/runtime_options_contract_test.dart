import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('snapshot options decode the exact published contract', () {
    final options = const CockpitSnapshotOptions.forensic().copyWith(
      networkQuery: const CockpitNetworkQuery(
        id: '37',
        before: '36',
        method: 'POST',
        uriContains: '/sync',
        onlyFailures: true,
        statusCodeAtLeast: 500,
      ),
      runtimeQuery: const CockpitRuntimeQuery(
        onlyErrors: true,
        messageContains: 'RenderFlex',
      ),
    );

    expect(CockpitSnapshotOptions.fromJson(options.toJson()), options);
  });

  test('snapshot options reject unknown, mistyped, and unbounded input', () {
    expect(
      () => CockpitSnapshotOptions.fromJson(const <String, Object?>{
        'includeSemantics': true,
      }),
      throwsFormatException,
    );
    expect(
      () => CockpitSnapshotOptions.fromJson(const <String, Object?>{
        'maxTargets': -1,
      }),
      throwsFormatException,
    );
    expect(
      () => CockpitSnapshotOptions.fromJson(const <String, Object?>{
        'maxRuntimeEntries': 10001,
      }),
      throwsFormatException,
    );
    expect(
      () => CockpitSnapshotOptions.fromJson(const <String, Object?>{
        'includeRuntimeActivity': 'yes',
      }),
      throwsFormatException,
    );
  });

  test('nested network and runtime queries reject invalid input', () {
    expect(
      () => CockpitNetworkQuery.fromJson(const <String, Object?>{
        'id': 'request-37',
      }),
      throwsFormatException,
    );
    expect(
      () => CockpitNetworkQuery.fromJson(const <String, Object?>{
        'statusCodeAtLeast': 99,
      }),
      throwsFormatException,
    );
    expect(
      () => CockpitRuntimeQuery.fromJson(const <String, Object?>{
        'messageContains': '   ',
      }),
      throwsFormatException,
    );
    expect(
      () => CockpitRuntimeQuery.fromJson(const <String, Object?>{
        'unknown': true,
      }),
      throwsFormatException,
    );
  });

  test('recording requests accept only the canonical bounded contract', () {
    final request = CockpitRecordingRequest(
      purpose: CockpitRecordingPurpose.acceptance,
      name: 'release-proof',
      mode: CockpitRecordingMode.full,
      layer: CockpitRecordingLayer.system,
      allowFallback: false,
      attachToStep: true,
      tailStabilizationDelay: const Duration(milliseconds: 1600),
    );
    expect(CockpitRecordingRequest.fromJson(request.toJson()), request);
    expect(
      () => CockpitRecordingRequest.fromJson(const <String, Object?>{
        'purpose': 'diagnostic',
        'name': 'legacy',
      }),
      throwsArgumentError,
    );
    expect(
      () => CockpitRecordingRequest.fromJson(const <String, Object?>{
        'purpose': 'acceptance',
      }),
      throwsFormatException,
    );
    expect(
      () => CockpitRecordingRequest.fromJson(const <String, Object?>{
        'purpose': 'acceptance',
        'name': 'release-proof',
        'tailStabilizationMs': 60001,
      }),
      throwsFormatException,
    );
  });
}
