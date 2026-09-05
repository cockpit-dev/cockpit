import 'package:cockpit/cockpit.dart';
import 'package:cockpit/src/mcp/core/cockpit_mcp_tool_adapter.dart';
import 'package:dart_mcp/server.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

void main() {
  test('MCP server reports the running Cockpit release', () {
    final server = CockpitMcpServer.standard();

    expect(server.serverVersion, cockpitVersion);
    expect(
      CockpitMcpServer.standard(serverVersion: 'custom').serverVersion,
      'custom',
    );
  });

  test('standard tools advertise accurate safety and resume metadata', () {
    final server = CockpitMcpServer.standard();
    final tools = <String, CockpitMcpTool>{
      for (final tool in server.tools) tool.name: tool,
    };

    expect(tools, hasLength(server.tools.length));
    expect(tools['target_discover']!.annotations.readOnly, isTrue);
    expect(tools['target_discover']!.annotations.destructive, isFalse);
    expect(tools['target_register']!.annotations.readOnly, isFalse);
    expect(tools['target_register']!.annotations.idempotent, isTrue);
    expect(tools['root_remove']!.annotations.destructive, isTrue);
    expect(tools['operation_execute']!.annotations.destructive, isTrue);
    expect(tools['artifact_read']!.annotations.readOnly, isFalse);

    final eventSchema =
        tools['run_events']!.inputSchema['properties']! as Map<String, Object?>;
    expect(eventSchema, containsPair('timeoutMs', isA<Map<String, Object?>>()));
    expect(tools, contains('run_list'));

    final resources = <String>{
      for (final resource in server.resources) resource.definition.name,
    };
    expect(resources, contains('workspace_runs'));
  });

  test('MCP protocol validation enforces conditional target arguments', () {
    final target = CockpitMcpServer.standard().tools.singleWhere(
      (tool) => tool.name == 'target_register',
    );
    final schema = CockpitMcpToolAdapter.protocolToolFor(target).inputSchema;
    final errors = schema.validate(<String, Object?>{
      'workspaceId': 'workspace',
      'platform': 'android',
      'deviceId': 'device',
      'targetKind': 'nativeApp',
      'idempotencyKey': 'request',
    });
    expect(errors, isNotEmpty);
  });

  test('MCP instructions describe only registered capabilities', () {
    final server = CockpitMcpServer.standard();
    final channel = StreamChannelController<String>();
    final protocol = server.createProtocolServer(channel.local);
    addTearDown(() async {
      await channel.foreign.sink.close();
      await protocol.done;
    });
    expect(protocol.instructions, isNot(contains('prompts')));
  });
}
