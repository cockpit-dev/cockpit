import 'package:cockpit/cockpit.dart';

final class RecordingAutomationAdapter implements CockpitAutomationAdapter {
  RecordingAutomationAdapter({List<bool> outcomes = const <bool>[]})
    : outcomes = List<bool>.from(outcomes);

  final List<bool> outcomes;
  final List<CockpitCommand> commands = <CockpitCommand>[];

  @override
  Future<CockpitCapabilities> describeCapabilities() async =>
      CockpitCapabilities(
        platform: 'android',
        transportType: 'inApp',
        supportsInAppControl: true,
        supportsFlutterViewCapture: true,
        supportsNativeScreenCapture: false,
        supportsHostAutomation: false,
        supportedCommands: CockpitCommandType.values,
        supportedLocatorStrategies: CockpitLocatorKind.values,
      );

  @override
  Future<CockpitCommandExecution> execute(CockpitCommand command) async {
    commands.add(command);
    final success = outcomes.isEmpty ? true : outcomes.removeAt(0);
    return CockpitCommandExecution(
      result: CockpitCommandResult(
        success: success,
        commandId: command.commandId,
        commandType: command.commandType,
        durationMs: 1,
        error: success
            ? null
            : CockpitCommandError.assertionFailed(
                message: 'Deterministic command failure.',
              ),
      ),
    );
  }
}

final class RecordingSecretResolver implements CockpitTestSecretResolver {
  RecordingSecretResolver(this.value);

  final String value;
  final List<String> references = <String>[];

  @override
  Future<String> resolve(String reference) async {
    references.add(reference);
    return value;
  }
}

final class RecordingSafetyPolicy implements CockpitTestSafetyPolicy {
  RecordingSafetyPolicy({this.denyDispatch = false});

  final bool denyDispatch;
  final List<CockpitTestSafetyRequest> requests = <CockpitTestSafetyRequest>[];

  @override
  Future<CockpitTestSafetyDecision> authorize(
    CockpitTestSafetyRequest request,
  ) async {
    requests.add(request);
    if (denyDispatch && request.phase == CockpitTestSafetyPhase.dispatch) {
      return const CockpitTestSafetyDecision.deny(
        'Dispatch was denied by the deterministic policy.',
      );
    }
    return const CockpitTestSafetyDecision.allow();
  }
}
