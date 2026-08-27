import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter_cockpit_test/flutter_cockpit_test.dart';

void main() {
  test('integration commands have bounded defaults', () {
    const options = CockpitTestOptions();
    expect(options.commandTimeout, const Duration(seconds: 10));
    expect(options.nativeTimeout, const Duration(minutes: 2));
  });

  cockpitTestWidgets(
    'runs selector actions through the in-app executor',
    app: () => const _TestApp(),
    body: (cockpit) async {
      final capabilities = await cockpit.describeCapabilities();
      expect(capabilities.supportsInAppControl, isTrue);
      final tap = await cockpit.tap('Save');
      expect(tap.result.success, isTrue, reason: tap.result.error?.message);
      await cockpit.expectText('Saved', 'Saved');
    },
  );

  cockpitTestWidgets(
    'uses the native timeout for explicit host actions',
    app: () => const _TestApp(),
    options: CockpitTestOptions(hostCommand: _successfulHostCommand),
    body: (cockpit) async {
      final result = await cockpit.host.action('dismiss');
      expect(result.result.success, isTrue);
      expect(result.result.commandType, CockpitCommandType.system);
      expect(result.result.durationMs, isNonNegative);
    },
  );
}

Future<CockpitCommandExecution> _successfulHostCommand(
  CockpitCommand command,
) async {
  expect(command.timeoutMs, cockpitIntegrationTestNativeTimeout.inMilliseconds);
  return CockpitCommandExecution(
    result: CockpitCommandResult(
      success: true,
      commandId: command.commandId,
      commandType: command.commandType,
      durationMs: 0,
    ),
  );
}

final class _TestApp extends StatefulWidget {
  const _TestApp();

  @override
  State<_TestApp> createState() => _TestAppState();
}

final class _TestAppState extends State<_TestApp> {
  var _saved = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(_saved ? 'Saved' : 'Ready'),
              TextButton(
                onPressed: () => setState(() => _saved = true),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
