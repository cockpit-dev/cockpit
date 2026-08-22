import 'package:cockpit/cockpit.dart';
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
}
