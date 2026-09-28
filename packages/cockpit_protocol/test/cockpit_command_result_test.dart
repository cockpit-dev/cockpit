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

  test('command result carries describeApp state and equality', () {
    final result = CockpitCommandResult(
      success: true,
      commandId: 'describe',
      commandType: CockpitCommandType.describeApp,
      durationMs: 3,
      appState: const <String, Object?>{
        'environment': 'staging',
        'buildNumber': 42,
        'flags': <Object?>{'darkMode', 'newCheckout'},
      },
    );

    final decoded = CockpitCommandResult.fromJson(result.toJson());
    expect(decoded, result);
    expect(decoded.appState, result.appState);

    final withoutState = CockpitCommandResult.fromJson(
      CockpitCommandResult(
        success: true,
        commandId: 'describe',
        commandType: CockpitCommandType.describeApp,
        durationMs: 3,
      ).toJson(),
    );
    expect(withoutState.appState, isNull);
    expect(withoutState == result, isFalse);
  });
}
