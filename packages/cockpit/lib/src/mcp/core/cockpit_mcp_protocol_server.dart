import 'dart:async';

import 'package:dart_mcp/server.dart';

import '../cockpit_mcp_tool.dart';
import 'cockpit_mcp_resource.dart';
import 'cockpit_mcp_resource_adapter.dart';
import 'cockpit_mcp_roots_tracker.dart';
import 'cockpit_mcp_tool_adapter.dart';

final class CockpitMcpProtocolServer extends MCPServer
    with LoggingSupport, ToolsSupport, ResourcesSupport {
  CockpitMcpProtocolServer(
    super.channel, {
    required List<CockpitMcpTool> tools,
    List<CockpitMcpResource> resources = const <CockpitMcpResource>[],
    required CockpitMcpRootsTracker rootsTracker,
    required this.featureConfiguration,
    required this.serverName,
    required this.serverVersion,
    super.protocolLogSink,
  }) : _tools = List<CockpitMcpTool>.unmodifiable(tools),
       _resources = List<CockpitMcpResource>.unmodifiable(resources),
       _rootsTracker = rootsTracker,
       super.fromStreamChannel(
         implementation: Implementation(
           name: serverName,
           version: serverVersion,
         ),
         instructions:
             'Use the resources to read workspace context and the tools to '
             'execute flutter_cockpit sessions, task workflows, and evidence '
             'bundles.',
       ) {
    for (final tool in _enabledTools) {
      registerTool(
        CockpitMcpToolAdapter.protocolToolFor(tool),
        (request) => _invoke(tool, request),
      );
    }
    for (final resource in _enabledResources) {
      final fixedResource = CockpitMcpResourceAdapter.fixedResourceFor(
        resource,
      );
      if (fixedResource != null) {
        addResource(
          fixedResource,
          (request) async =>
              (await CockpitMcpResourceAdapter.invoke(resource, request)) ??
              (throw StateError('Fixed resource returned no content.')),
        );
        continue;
      }

      final template = CockpitMcpResourceAdapter.templateFor(resource);
      if (template != null) {
        addResourceTemplate(
          template,
          (request) => CockpitMcpResourceAdapter.invoke(resource, request),
        );
      }
    }
    initialized.then((_) async {
      await _rootsTracker.bind(
        clientSupportsRoots: clientCapabilities.roots != null,
        readRoots: () async => (await listRoots(ListRootsRequest())).roots,
        rootsChanged: rootsListChanged?.map((_) {}),
      );
    });
  }

  final List<CockpitMcpTool> _tools;
  final List<CockpitMcpResource> _resources;
  final CockpitMcpRootsTracker _rootsTracker;
  final CockpitMcpFeatureConfiguration featureConfiguration;
  final String serverName;
  final String serverVersion;

  List<CockpitMcpTool> get _enabledTools => _tools
      .where((tool) => featureConfiguration.isEnabled(tool.definition))
      .toList(growable: false);

  List<CockpitMcpResource> get _enabledResources => _resources
      .where((resource) => featureConfiguration.isEnabled(resource.definition))
      .toList(growable: false);

  Future<CallToolResult> _invoke(
    CockpitMcpTool tool,
    CallToolRequest request,
  ) async {
    final progressToken = request.meta?.progressToken;
    if (progressToken != null && tool.definition.annotations.longRunning) {
      notifyProgress(
        ProgressNotification(
          progressToken: progressToken,
          progress: 0,
          total: 100,
          message: '${tool.name} started',
        ),
      );
    }

    final result = await CockpitMcpToolAdapter.invoke(
      tool,
      request.arguments ?? const <String, Object?>{},
    );

    if (progressToken != null && tool.definition.annotations.longRunning) {
      notifyProgress(
        ProgressNotification(
          progressToken: progressToken,
          progress: 100,
          total: 100,
          message: '${tool.name} completed',
        ),
      );
    }

    return result;
  }
}
