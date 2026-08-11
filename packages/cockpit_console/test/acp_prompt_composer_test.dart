import 'package:acpd/acpd.dart';
import 'package:cockpit_console/src/providers/acp_state.dart';
import 'package:cockpit_console/src/theme/console_theme.dart';
import 'package:cockpit_console/src/ui/widgets/acp_prompt_composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('available command is inserted and sent as prompt content', (
    tester,
  ) async {
    List<ContentBlock>? sent;
    await tester.pumpWidget(
      MaterialApp(
        theme: ConsoleTheme.build(Brightness.light),
        home: Scaffold(
          body: AcpPromptComposer(
            connection: _connection(
              commands: const [
                AvailableCommand(
                  name: 'inspect',
                  description: 'Inspect the current project',
                  input: UnstructuredCommandInput(hint: 'Optional target'),
                ),
              ],
            ),
            onSend: (content) async {
              sent = content;
              return true;
            },
            onCancel: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Available commands'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('/inspect'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, '/inspect ');
    await tester.enterText(find.byType(TextField), '/inspect lib');
    await tester.tap(find.byTooltip('Send message (Enter)'));
    await tester.pumpAndSettle();

    expect(sent, hasLength(1));
    expect(sent!.single, isA<TextContentBlock>());
    expect((sent!.single as TextContentBlock).text, '/inspect lib');
    expect(field.controller?.text, isEmpty);
  });

  testWidgets('command selection preserves existing composer text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConsoleTheme.build(Brightness.dark),
        home: Scaffold(
          body: AcpPromptComposer(
            connection: _connection(
              commands: const [
                AvailableCommand(
                  name: 'review',
                  description: 'Review a target',
                ),
              ],
            ),
            onSend: (_) async => true,
            onCancel: () {},
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'packages/acpd');
    await tester.tap(find.byTooltip('Available commands'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('/review'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '/review packages/acpd',
    );
  });
}

AcpConnected _connection({required List<AvailableCommand> commands}) {
  return AcpConnected(
    agentInfo: const Implementation(name: 'fixture', version: '1.0.0'),
    protocolVersion: ProtocolVersion.v1,
    capabilities: const AgentCapabilities(),
    activeSession: AcpSessionState(
      sessionId: 'session-1',
      cwd: '/project',
      availableCommands: commands,
    ),
  );
}
