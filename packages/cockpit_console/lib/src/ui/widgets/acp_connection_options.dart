import 'package:acpd/acpd.dart';
import 'package:cockpit_console/src/providers/acp_state.dart';
import 'package:cockpit_console/src/theme/console_control_style.dart';
import 'package:cockpit_console/src/theme/console_shapes.dart';
import 'package:cockpit_console/src/ui/widgets/acp_mcp_server_editor.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;

final class AcpConnectionOptions {
  const AcpConnectionOptions({
    this.additionalDirectories = const [],
    this.mcpServers = const [],
  });

  final List<String> additionalDirectories;
  final List<McpServer> mcpServers;

  AcpConnectionOptions copyWith({
    List<String>? additionalDirectories,
    List<McpServer>? mcpServers,
  }) {
    return AcpConnectionOptions(
      additionalDirectories: List.unmodifiable(
        additionalDirectories ?? this.additionalDirectories,
      ),
      mcpServers: List.unmodifiable(mcpServers ?? this.mcpServers),
    );
  }
}

Future<AcpSessionSpec?> showAcpSessionEditor(
  BuildContext context, {
  required AcpSessionSpec initial,
  required AgentCapabilities capabilities,
}) async {
  var cwd = initial.cwd;
  var options = AcpConnectionOptions(
    additionalDirectories: initial.additionalDirectories,
    mcpServers: initial.mcpServers,
  );
  return showDialog<AcpSessionSpec>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Create session'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Working directory',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: ConsoleControlStyle.height,
                  child: InkWell(
                    onTap: () async {
                      final selected = await FilePicker.getDirectoryPath(
                        dialogTitle: 'Select session working directory',
                        initialDirectory: cwd,
                      );
                      if (selected != null) {
                        setState(() => cwd = p.normalize(p.absolute(selected)));
                      }
                    },
                    customBorder: ConsoleShapes.border(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: ConsoleShapes.decoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLow,
                        borderColor: Theme.of(context).dividerColor,
                      ),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.folderOpen, size: 15),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              cwd,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontFamily: 'monospace'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                AcpConnectionOptionsEditor(
                  value: options,
                  capabilities: capabilities,
                  onChanged: (value) => setState(() => options = value),
                ),
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
            onPressed: () => Navigator.pop(
              context,
              AcpSessionSpec(
                cwd: cwd,
                additionalDirectories: options.additionalDirectories,
                mcpServers: options.mcpServers,
              ),
            ),
            child: const Text('Create session'),
          ),
        ],
      ),
    ),
  );
}

final class AcpConnectionOptionsEditor extends StatelessWidget {
  const AcpConnectionOptionsEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.capabilities,
  });

  final AcpConnectionOptions value;
  final ValueChanged<AcpConnectionOptions> onChanged;
  final bool enabled;
  final AgentCapabilities? capabilities;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = value.additionalDirectories.length + value.mcpServers.length;
    return Container(
      decoration: ConsoleShapes.decoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderColor: theme.dividerColor,
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        leading: const Icon(LucideIcons.slidersHorizontal, size: 16),
        title: const Text('Session context'),
        subtitle: Text(
          count == 0
              ? 'Optional directories and MCP servers'
              : '$count configured item${count == 1 ? '' : 's'}',
        ),
        children: [
          _OptionSection(
            title: 'Additional directories',
            description:
                'Grant the agent access to workspace roots beyond the working directory.',
            action: TextButton.icon(
              onPressed:
                  enabled &&
                      (capabilities == null ||
                          capabilities!
                                  .sessionCapabilities
                                  ?.additionalDirectories !=
                              null)
                  ? () => _addDirectory(context)
                  : null,
              icon: const Icon(LucideIcons.folderPlus, size: 14),
              label: const Text('Add directory'),
            ),
            children: [
              for (final directory in value.additionalDirectories)
                _ConfiguredRow(
                  icon: LucideIcons.folder,
                  title: p.basename(directory),
                  subtitle: directory,
                  onDelete: enabled
                      ? () => onChanged(
                          value.copyWith(
                            additionalDirectories: value.additionalDirectories
                                .where((item) => item != directory)
                                .toList(),
                          ),
                        )
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 14),
          _OptionSection(
            title: 'MCP servers',
            description:
                'Attach tools and resources for this Agent connection. Values are not stored.',
            action: TextButton.icon(
              onPressed: enabled ? () => _addMcpServer(context) : null,
              icon: const Icon(LucideIcons.plus, size: 14),
              label: const Text('Add server'),
            ),
            children: [
              for (var index = 0; index < value.mcpServers.length; index++)
                _ConfiguredRow(
                  icon: LucideIcons.server,
                  title: value.mcpServers[index].name,
                  subtitle: acpMcpServerSummary(value.mcpServers[index]),
                  onTap: enabled ? () => _editMcpServer(context, index) : null,
                  onDelete: enabled
                      ? () => onChanged(
                          value.copyWith(
                            mcpServers: [
                              ...value.mcpServers.take(index),
                              ...value.mcpServers.skip(index + 1),
                            ],
                          ),
                        )
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _addDirectory(BuildContext context) async {
    final directory = await FilePicker.getDirectoryPath(
      dialogTitle: 'Add session directory',
    );
    if (directory == null || !context.mounted) return;
    final normalized = p.normalize(p.absolute(directory));
    if (value.additionalDirectories.any((item) => p.equals(item, normalized))) {
      _showOptionsError(context, 'That directory is already included.');
      return;
    }
    onChanged(
      value.copyWith(
        additionalDirectories: [...value.additionalDirectories, normalized],
      ),
    );
  }

  Future<void> _addMcpServer(BuildContext context) async {
    final server = await showAcpMcpServerEditor(
      context,
      capabilities: capabilities?.mcpCapabilities,
    );
    if (server == null || !context.mounted) return;
    if (_hasMcpName(server.name)) {
      _showOptionsError(context, 'MCP server names must be unique.');
      return;
    }
    onChanged(value.copyWith(mcpServers: [...value.mcpServers, server]));
  }

  Future<void> _editMcpServer(BuildContext context, int index) async {
    final server = await showAcpMcpServerEditor(
      context,
      initial: value.mcpServers[index],
      capabilities: capabilities?.mcpCapabilities,
    );
    if (server == null || !context.mounted) return;
    if (_hasMcpName(server.name, except: index)) {
      _showOptionsError(context, 'MCP server names must be unique.');
      return;
    }
    final servers = value.mcpServers.toList()..[index] = server;
    onChanged(value.copyWith(mcpServers: servers));
  }

  bool _hasMcpName(String name, {int? except}) {
    for (var index = 0; index < value.mcpServers.length; index++) {
      if (index != except && value.mcpServers[index].name == name) return true;
    }
    return false;
  }
}

final class _OptionSection extends StatelessWidget {
  const _OptionSection({
    required this.title,
    required this.description,
    required this.action,
    required this.children,
  });

  final String title;
  final String description;
  final Widget action;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: theme.textTheme.labelLarge)),
            action,
          ],
        ),
        Text(
          description,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (children.isNotEmpty) ...[const SizedBox(height: 8), ...children],
      ],
    );
  }
}

final class _ConfiguredRow extends StatelessWidget {
  const _ConfiguredRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.onDelete,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: InkWell(
        onTap: onTap,
        customBorder: ConsoleShapes.border(),
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 6, 3, 6),
          decoration: ConsoleShapes.decoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderColor: theme.dividerColor,
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium,
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDelete,
                tooltip: 'Remove $title',
                visualDensity: VisualDensity.compact,
                iconSize: 14,
                icon: const Icon(LucideIcons.x),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showOptionsError(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
