import 'dart:convert';

import 'package:acpd/acpd.dart';
import 'package:cockpit_console/i18n/strings.g.dart';
import 'package:cockpit_console/src/providers/acp_state.dart';
import 'package:cockpit_console/src/theme/console_shapes.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Expandable, lossless presentation of one ACP tool call.
final class AcpToolCallView extends StatelessWidget {
  const AcpToolCallView({super.key, required this.toolCall});

  final AcpToolCallState toolCall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = toolCall.status?.toJson();
    final hasDetails =
        toolCall.content.isNotEmpty ||
        toolCall.locations.isNotEmpty ||
        toolCall.rawInput != null ||
        toolCall.rawOutput != null;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: ConsoleShapes.decoration(
        color: theme.colorScheme.surfaceContainer,
        borderColor: theme.dividerColor,
      ),
      child: ExpansionTile(
        enabled: hasDetails,
        tilePadding: const EdgeInsets.symmetric(horizontal: 10),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        leading: Icon(
          _toolIcon(toolCall.kind),
          size: 15,
          color: _statusColor(theme.colorScheme, status),
        ),
        title: Text(
          toolCall.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium,
        ),
        subtitle: Wrap(
          spacing: 6,
          runSpacing: 3,
          children: [
            if (toolCall.kind case final kind?) Text(kind.toJson()),
            if (status != null) Text(_statusLabel(context.t, status)),
            Text(toolCall.toolCallId),
          ],
        ),
        children: [
          if (toolCall.locations.isNotEmpty)
            _Locations(locations: toolCall.locations),
          for (final content in toolCall.content) ...[
            if (toolCall.locations.isNotEmpty ||
                content != toolCall.content.first)
              const SizedBox(height: 8),
            _ToolContent(content: content),
          ],
          if (toolCall.rawInput case final input?) ...[
            const SizedBox(height: 8),
            _RawValue(
              label: context.t.ai.tool.rawInput,
              value: _formatRawValue(input),
            ),
          ],
          if (toolCall.rawOutput case final output?) ...[
            const SizedBox(height: 8),
            _RawValue(
              label: context.t.ai.tool.rawOutput,
              value: _formatRawValue(output),
            ),
          ],
        ],
      ),
    );
  }
}

/// Displays non-text ACP message content without printing inline base64 data.
final class AcpMessageContentView extends StatelessWidget {
  const AcpMessageContentView({super.key, required this.content});

  final List<ContentBlock> content;

  @override
  Widget build(BuildContext context) {
    final nonText = content
        .where((block) => block is! TextContentBlock)
        .toList(growable: false);
    if (nonText.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final block in nonText) ...[
          if (block != nonText.first) const SizedBox(height: 6),
          _ContentBlockView(block: block),
        ],
      ],
    );
  }
}

final class _ToolContent extends StatelessWidget {
  const _ToolContent({required this.content});

  final ToolCallContent content;

  @override
  Widget build(BuildContext context) {
    return switch (content) {
      ToolCallContentBlock(:final content) => _ContentBlockView(block: content),
      ToolCallDiff(:final path, :final oldText, :final newText) => _DiffView(
        path: path,
        oldText: oldText,
        newText: newText,
      ),
      ToolCallTerminal(:final terminalId) => _MetadataRow(
        icon: LucideIcons.terminal,
        label: context.t.ai.tool.terminal,
        value: terminalId,
      ),
    };
  }
}

final class _ContentBlockView extends StatelessWidget {
  const _ContentBlockView({required this.block});

  final ContentBlock block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return switch (block) {
      TextContentBlock(:final text) => SelectableText(
        text,
        style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
      ),
      ImageContent(:final data, :final mimeType, :final uri) => _ImageView(
        data: data,
        mimeType: mimeType,
        uri: uri,
      ),
      AudioContent(:final data, :final mimeType) => _MetadataRow(
        icon: LucideIcons.audioLines,
        label: context.t.ai.tool.audio,
        value: '$mimeType · ${_decodedByteLength(data)} bytes',
      ),
      ResourceLink(
        :final name,
        :final title,
        :final uri,
        :final mimeType,
        :final size,
      ) =>
        _ResourceView(
          name: title ?? name,
          uri: uri,
          mimeType: mimeType,
          size: size,
        ),
      EmbeddedResource(:final resource) => _EmbeddedResourceView(
        resource: resource,
      ),
    };
  }
}

final class _ImageView extends StatelessWidget {
  const _ImageView({required this.data, required this.mimeType, this.uri});

  final String data;
  final String mimeType;
  final String? uri;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    try {
      final bytes = base64Decode(data);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipPath.shape(
            shape: ConsoleShapes.border(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => _InvalidContent(
                  message: context.t.ai.tool.invalidImage(mime: mimeType),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            [mimeType, '${bytes.length} bytes', ?uri].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    } on FormatException {
      return _InvalidContent(message: context.t.ai.tool.malformedImage);
    }
  }
}

final class _ResourceView extends StatelessWidget {
  const _ResourceView({
    required this.name,
    required this.uri,
    this.mimeType,
    this.size,
  });

  final String name;
  final String uri;
  final String? mimeType;
  final int? size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: ConsoleShapes.decoration(
        color: theme.colorScheme.surfaceContainerLow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: theme.textTheme.labelMedium),
          const SizedBox(height: 2),
          SelectableText(
            uri,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.primary,
            ),
          ),
          if (mimeType != null || size != null) ...[
            const SizedBox(height: 3),
            Text(
              [mimeType, if (size != null) '$size bytes'].nonNulls.join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

final class _EmbeddedResourceView extends StatelessWidget {
  const _EmbeddedResourceView({required this.resource});

  final ResourceContents resource;

  @override
  Widget build(BuildContext context) {
    return switch (resource) {
      TextResourceContents(:final text, :final uri, :final mimeType) =>
        _RawValue(
          label: [mimeType ?? context.t.ai.tool.textResource, uri].join(' · '),
          value: text,
        ),
      BlobResourceContents(:final blob, :final uri, :final mimeType) =>
        _MetadataRow(
          icon: LucideIcons.fileArchive,
          label: mimeType ?? context.t.ai.tool.binaryResource,
          value: '$uri · ${_decodedByteLength(blob)} bytes',
        ),
    };
  }
}

final class _DiffView extends StatelessWidget {
  const _DiffView({
    required this.path,
    required this.oldText,
    required this.newText,
  });

  final String path;
  final String? oldText;
  final String newText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MetadataRow(
          icon: LucideIcons.fileDiff,
          label: context.t.ai.tool.diff,
          value: path,
        ),
        const SizedBox(height: 6),
        if (oldText case final oldText?) ...[
          Text(context.t.ai.tool.before, style: theme.textTheme.labelSmall),
          const SizedBox(height: 2),
          _CodeBlock(value: oldText, tint: theme.colorScheme.error),
          const SizedBox(height: 6),
        ],
        Text(context.t.ai.tool.after, style: theme.textTheme.labelSmall),
        const SizedBox(height: 2),
        _CodeBlock(value: newText, tint: theme.colorScheme.primary),
      ],
    );
  }
}

final class _Locations extends StatelessWidget {
  const _Locations({required this.locations});

  final List<ToolCallLocation> locations;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final location in locations)
          _MetadataRow(
            icon: LucideIcons.mapPin,
            label: context.t.ai.tool.location,
            value:
                '${location.path}${location.line == null ? '' : ':${location.line}'}',
          ),
      ],
    );
  }
}

final class _RawValue extends StatelessWidget {
  const _RawValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 3),
        _CodeBlock(value: value),
      ],
    );
  }
}

final class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.value, this.tint});

  final String value;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: ConsoleShapes.decoration(
          color:
              tint?.withValues(alpha: 0.055) ??
              theme.colorScheme.surfaceContainerLow,
          borderColor: tint?.withValues(alpha: 0.18),
        ),
        child: SingleChildScrollView(
          child: SelectableText(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}

final class _MetadataRow extends StatelessWidget {
  const _MetadataRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            icon,
            size: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 5),
        Text('$label: ', style: theme.textTheme.labelSmall),
        Expanded(
          child: SelectableText(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

final class _InvalidContent extends StatelessWidget {
  const _InvalidContent({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: ConsoleShapes.decoration(
        color: theme.colorScheme.error.withValues(alpha: 0.06),
        borderColor: theme.colorScheme.error.withValues(alpha: 0.22),
      ),
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
    );
  }
}

IconData _toolIcon(ToolKind? kind) => switch (kind?.toJson()) {
  'read' => LucideIcons.fileSearch,
  'edit' => LucideIcons.filePenLine,
  'delete' => LucideIcons.trash2,
  'move' => LucideIcons.moveRight,
  'search' => LucideIcons.search,
  'execute' => LucideIcons.terminal,
  'think' => LucideIcons.brain,
  'fetch' => LucideIcons.download,
  'switch_mode' => LucideIcons.workflow,
  _ => LucideIcons.wrench,
};

Color _statusColor(ColorScheme colors, String? status) => switch (status) {
  'completed' => colors.primary,
  'failed' => colors.error,
  'in_progress' => colors.tertiary,
  _ => colors.onSurfaceVariant,
};

String _statusLabel(Translations t, String value) => switch (value) {
  'completed' => t.ai.tool.status.completed,
  'failed' => t.ai.tool.status.failed,
  'in_progress' => t.ai.tool.status.inProgress,
  _ =>
    value
        .split('_')
        .map(
          (part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' '),
};

int _decodedByteLength(String value) {
  try {
    return base64Decode(value).length;
  } on FormatException {
    return 0;
  }
}

String _formatRawValue(Object value) {
  if (value is String) return value;
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } on JsonUnsupportedObjectError {
    return value.toString();
  }
}
