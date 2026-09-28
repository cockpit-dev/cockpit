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

  test('command result carries appAction results and equality', () {
    final result = CockpitCommandResult(
      success: true,
      commandId: 'action',
      commandType: CockpitCommandType.appAction,
      durationMs: 5,
      actionResult: const <String, Object?>{
        'applied': true,
        'locale': 'zh_Hant_TW',
        'nested': <String, Object?>{'brightness': 'dark'},
      },
    );

    final decoded = CockpitCommandResult.fromJson(result.toJson());
    expect(decoded, result);
    expect(decoded.actionResult, result.actionResult);

    final withoutResult = CockpitCommandResult.fromJson(
      CockpitCommandResult(
        success: true,
        commandId: 'action',
        commandType: CockpitCommandType.appAction,
        durationMs: 5,
      ).toJson(),
    );
    expect(withoutResult.actionResult, isNull);
    expect(withoutResult == result, isFalse);
  });
}
