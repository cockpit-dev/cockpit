import 'package:acpd/acpd.dart';
import 'package:cockpit_console/src/ui/widgets/console_form_controls.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

enum AcpMcpTransport { stdio, http, sse }

Future<McpServer?> showAcpMcpServerEditor(
  BuildContext context, {
  McpServer? initial,
  McpCapabilities? capabilities,
}) async {
  final initialTransport = switch (initial) {
    McpServerHttp() => AcpMcpTransport.http,
    McpServerSse() => AcpMcpTransport.sse,
    _ => AcpMcpTransport.stdio,
  };
  var transport = initialTransport;
  var error = <String>[];
  final nameController = TextEditingController(text: initial?.name);
  final targetController = TextEditingController(text: _target(initial));
  final argsController = TextEditingController(text: _args(initial));
  final propertiesController = TextEditingController(
    text: _properties(initial),
  );
  try {
    return await showDialog<McpServer>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(initial == null ? 'Add MCP server' : 'Edit MCP server'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConsoleDropdownField<AcpMcpTransport>(
                    key: ValueKey(transport),
                    label: 'Transport',
                    initialValue: transport,
                    items: [
                      const DropdownMenuItem(
                        value: AcpMcpTransport.stdio,
                        child: Text('stdio'),
                      ),
                      DropdownMenuItem(
                        value: AcpMcpTransport.http,
                        enabled: capabilities?.http != false,
                        child: Text('HTTP'),
                      ),
                      DropdownMenuItem(
                        value: AcpMcpTransport.sse,
                        enabled: capabilities?.sse != false,
                        child: Text('SSE'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => transport = value);
                    },
                    supportingText: _transportDescription(transport),
                  ),
                  const SizedBox(height: 10),
                  ConsoleTextField(
                    controller: nameController,
                    autofocus: true,
                    label: 'Name',
                    hint: 'workspace-tools',
                  ),
                  const SizedBox(height: 10),
                  ConsoleTextField(
                    controller: targetController,
                    label: transport == AcpMcpTransport.stdio
                        ? 'Absolute executable path'
                        : 'Server URL',
                    hint: transport == AcpMcpTransport.stdio
                        ? '/absolute/path/to/mcp-server'
                        : 'https://example.test/mcp',
                    autocorrect: false,
                    enableSuggestions: false,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  if (transport == AcpMcpTransport.stdio) ...[
                    const SizedBox(height: 10),
                    ConsoleTextArea(
                      controller: argsController,
                      label: 'Arguments (one per line)',
                      minLines: 2,
                      maxLines: 4,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ],
                  const SizedBox(height: 10),
                  ConsoleTextArea(
                    controller: propertiesController,
                    label: transport == AcpMcpTransport.stdio
                        ? 'Environment (NAME=value)'
                        : 'Headers (Name: value)',
                    minLines: 2,
                    maxLines: 5,
                    autocorrect: false,
                    enableSuggestions: false,
                    supportingText:
                        'Connection-only values. Cockpit Console does not store them.',
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  if (error.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final message in error)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          message,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final result = _buildServer(
                  transport: transport,
                  name: nameController.text,
                  target: targetController.text,
                  arguments: argsController.text,
                  properties: propertiesController.text,
                );
                if (result.errors.isNotEmpty) {
                  setState(() => error = result.errors);
                  return;
                }
                Navigator.pop(context, result.server);
              },
              child: Text(initial == null ? 'Add server' : 'Save server'),
            ),
          ],
        ),
      ),
    );
  } finally {
    nameController.dispose();
    targetController.dispose();
    argsController.dispose();
    propertiesController.dispose();
  }
}

String acpMcpServerSummary(McpServer server) => switch (server) {
  McpServerStdio(:final command) => 'stdio · $command',
  McpServerHttp(:final url) => 'HTTP · $url',
  McpServerSse(:final url) => 'SSE · $url',
};

final class _McpEditorResult {
  const _McpEditorResult({this.server, this.errors = const []});

  final McpServer? server;
  final List<String> errors;
}

_McpEditorResult _buildServer({
  required AcpMcpTransport transport,
  required String name,
  required String target,
  required String arguments,
  required String properties,
}) {
  final cleanName = name.trim();
  final cleanTarget = target.trim();
  final errors = <String>[];
  if (cleanName.isEmpty) errors.add('Enter a server name.');
  if (cleanTarget.isEmpty) {
    errors.add(
      transport == AcpMcpTransport.stdio
          ? 'Enter an executable path.'
          : 'Enter a server URL.',
    );
  }

  if (transport == AcpMcpTransport.stdio &&
      cleanTarget.isNotEmpty &&
      !p.isAbsolute(cleanTarget)) {
    errors.add('The stdio executable must use an absolute path.');
  }
  if (transport != AcpMcpTransport.stdio && cleanTarget.isNotEmpty) {
    final uri = Uri.tryParse(cleanTarget);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      errors.add('The server URL must be an absolute HTTP(S) URL.');
    }
  }

  final parsedProperties = transport == AcpMcpTransport.stdio
      ? _parseEnvironment(properties)
      : _parseHeaders(properties);
  errors.addAll(parsedProperties.errors);
  if (errors.isNotEmpty) return _McpEditorResult(errors: errors);

  return _McpEditorResult(
    server: switch (transport) {
      AcpMcpTransport.stdio => McpServerStdio(
        name: cleanName,
        command: cleanTarget,
        args: _nonEmptyLines(arguments),
        env: parsedProperties.environment,
      ),
      AcpMcpTransport.http => McpServerHttp(
        name: cleanName,
        url: cleanTarget,
        headers: parsedProperties.headers,
      ),
      AcpMcpTransport.sse => McpServerSse(
        name: cleanName,
        url: cleanTarget,
        headers: parsedProperties.headers,
      ),
    },
  );
}

final class _ParsedProperties {
  const _ParsedProperties({
    this.environment = const [],
    this.headers = const [],
    this.errors = const [],
  });

  final List<EnvVariable> environment;
  final List<HttpHeader> headers;
  final List<String> errors;
}

_ParsedProperties _parseEnvironment(String source) {
  final values = <EnvVariable>[];
  final errors = <String>[];
  final names = <String>{};
  for (final (index, line) in _indexedNonEmptyLines(source)) {
    final separator = line.indexOf('=');
    if (separator <= 0) {
      errors.add('Environment line $index must use NAME=value.');
      continue;
    }
    final name = line.substring(0, separator).trim();
    final value = line.substring(separator + 1);
    if (!_environmentName.hasMatch(name)) {
      errors.add('Environment line $index has an invalid variable name.');
    } else if (!names.add(name)) {
      errors.add('Environment variable “$name” is duplicated.');
    } else {
      values.add(EnvVariable(name: name, value: value));
    }
  }
  return _ParsedProperties(environment: values, errors: errors);
}

_ParsedProperties _parseHeaders(String source) {
  final values = <HttpHeader>[];
  final errors = <String>[];
  final names = <String>{};
  for (final (index, line) in _indexedNonEmptyLines(source)) {
    final separator = line.indexOf(':');
    if (separator <= 0) {
      errors.add('Header line $index must use Name: value.');
      continue;
    }
    final name = line.substring(0, separator).trim();
    final value = line.substring(separator + 1).trimLeft();
    final identity = name.toLowerCase();
    if (!_headerName.hasMatch(name)) {
      errors.add('Header line $index has an invalid name.');
    } else if (!names.add(identity)) {
      errors.add('Header “$name” is duplicated.');
    } else {
      values.add(HttpHeader(name: name, value: value));
    }
  }
  return _ParsedProperties(headers: values, errors: errors);
}

Iterable<(int, String)> _indexedNonEmptyLines(String source) sync* {
  final lines = source.split(RegExp(r'\r?\n'));
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index].trim();
    if (line.isNotEmpty) yield (index + 1, line);
  }
}

List<String> _nonEmptyLines(String source) =>
    _indexedNonEmptyLines(source).map((entry) => entry.$2).toList();

String _target(McpServer? server) => switch (server) {
  McpServerStdio(:final command) => command,
  McpServerHttp(:final url) => url,
  McpServerSse(:final url) => url,
  null => '',
};

String _args(McpServer? server) => switch (server) {
  McpServerStdio(:final args) => args.join('\n'),
  _ => '',
};

String _properties(McpServer? server) => switch (server) {
  McpServerStdio(:final env) =>
    env.map((value) => '${value.name}=${value.value}').join('\n'),
  McpServerHttp(:final headers) || McpServerSse(:final headers) =>
    headers.map((header) => '${header.name}: ${header.value}').join('\n'),
  null => '',
};

String _transportDescription(AcpMcpTransport transport) => switch (transport) {
  AcpMcpTransport.stdio => 'Supported by every ACP agent.',
  AcpMcpTransport.http => 'Requires the agent HTTP MCP capability.',
  AcpMcpTransport.sse => 'Requires the agent SSE MCP capability.',
};

final _environmentName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
final _headerName = RegExp(r"^[!#-'*+\-.0-9A-Z\^_`a-z\|~]+$");
