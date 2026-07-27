import 'dart:async';
import 'dart:io';

import 'package:stream_channel/stream_channel.dart';

import '../supervisor/cockpit_supervisor_api_client.dart';
import 'cockpit_mcp_api_resources.dart';
import 'cockpit_mcp_api_tools.dart';
import 'cockpit_mcp_development_tools.dart';
import 'cockpit_mcp_tool.dart';
import 'core/cockpit_mcp_protocol_server.dart';
import 'core/cockpit_mcp_resource.dart';
import 'core/cockpit_mcp_roots_tracker.dart';
import 'core/cockpit_mcp_stdio_channel.dart';

final class CockpitMcpServer {
  CockpitMcpServer({
    required List<CockpitMcpTool> tools,
    required List<CockpitMcpResource> resources,
    this.featureConfiguration = const CockpitMcpFeatureConfiguration(),
    CockpitMcpRootsTracker? rootsTracker,
    this.serverName = 'cockpit',
    this.serverVersion = '2.0.0',
  }) : tools = List<CockpitMcpTool>.unmodifiable(tools),
       resources = List<CockpitMcpResource>.unmodifiable(resources),
       rootsTracker = rootsTracker ?? CockpitMcpRootsTracker();

  factory CockpitMcpServer.standard({
    CockpitMcpClientProvider? clientProvider,
    CockpitMcpFeatureConfiguration featureConfiguration =
        const CockpitMcpFeatureConfiguration(),
    String serverName = 'cockpit',
    String serverVersion = '2.0.0',
  }) {
    final create = clientProvider ?? createCockpitSupervisorApiClient;
    Future<CockpitSupervisorApiClient>? cached;
    Future<CockpitSupervisorApiClient> client() => cached ??= create();
    return CockpitMcpServer(
      tools: <CockpitMcpTool>[
        ...cockpitMcpApiTools(client),
        ...cockpitMcpDevelopmentTools(client),
      ],
      resources: cockpitMcpApiResources(client),
      featureConfiguration: featureConfiguration,
      serverName: serverName,
      serverVersion: serverVersion,
    );
  }

  final List<CockpitMcpTool> tools;
  final List<CockpitMcpResource> resources;
  final CockpitMcpFeatureConfiguration featureConfiguration;
  final CockpitMcpRootsTracker rootsTracker;
  final String serverName;
  final String serverVersion;

  CockpitMcpProtocolServer createProtocolServer(
    StreamChannel<String> channel, {
    Sink<String>? protocolLogSink,
  }) => CockpitMcpProtocolServer(
    channel,
    tools: tools,
    resources: resources,
    rootsTracker: rootsTracker,
    featureConfiguration: featureConfiguration,
    serverName: serverName,
    serverVersion: serverVersion,
    protocolLogSink: protocolLogSink,
  );

  Future<void> serveStdio({
    Stream<List<int>>? input,
    StreamSink<List<int>>? output,
    Sink<String>? protocolLogSink,
  }) async {
    final server = createProtocolServer(
      cockpitMcpStdioChannel(input: input ?? stdin, output: output ?? stdout),
      protocolLogSink: protocolLogSink,
    );
    await server.done;
  }
}
