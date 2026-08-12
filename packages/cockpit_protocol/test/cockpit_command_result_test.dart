import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('command result preserves foreground surface diagnostics', () {
    final result = CockpitCommandResult(
      success: true,
      commandId: 'capture',
      commandType: CockpitCommandType.captureScreenshot,
      durationMs: 12,
      resolvedCaptureKind: CockpitCaptureKind.hostSystem,
      degradationReason: 'systemSurfaceMismatch',
      surface: const <String, Object?>{
        'relation': 'differentApp',
        'app': 'dev.cockpit.demo',
        'front': 'com.example.other',
      },
    );

    expect(CockpitCommandResult.fromJson(result.toJson()), result);
  });
}
