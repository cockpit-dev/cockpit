import 'package:args/command_runner.dart';

import '../../mcp/cockpit_mcp_server.dart';
import '../../mcp/core/cockpit_mcp_feature_configuration.dart';
import '../cockpit_cli_runtime.dart';

final class CockpitServeMcpCommand extends Command<int> {
  CockpitServeMcpCommand({CockpitMcpServer? server}) : _server = server {
    argParser
      ..addOption(
        'profile',
        allowed: CockpitMcpProfile.values.map((profile) => profile.name),
        defaultsTo: CockpitMcpProfile.core.name,
      )
      ..addMultiOption('enable')
      ..addMultiOption('disable', abbr: 'x');
  }

  final CockpitMcpServer? _server;

  @override
  String get name => 'serve-mcp';

  @override
  String get description => 'Serve the Cockpit 2.0 MCP transport over stdio.';

  @override
  Future<int> run() async {
    final options = argResults!;
    final server =
        _server ??
        CockpitMcpServer.standard(
          featureConfiguration: CockpitMcpFeatureConfiguration.forProfile(
            CockpitMcpProfile.parse(options.option('profile')!),
            enabledNames: options.multiOption('enable').toSet(),
            disabledNames: options.multiOption('disable').toSet(),
          ),
        );
    await server.serveStdio();
    return cockpitSuccessExitCode;
  }
}
