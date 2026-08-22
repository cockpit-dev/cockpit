import 'dart:io';

import 'package:acpd/acpd.dart';
import 'package:cockpit_console/i18n/strings.g.dart';
import 'package:cockpit_console/src/providers/acp_provider.dart';
import 'package:cockpit_console/src/theme/console_control_style.dart';
import 'package:cockpit_console/src/theme/console_shapes.dart';
import 'package:cockpit_console/src/ui/widgets/acp_prompt_attachment.dart';
import 'package:cockpit_console/src/ui/widgets/console_form_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

final class AcpPromptComposer extends HookWidget {
  const AcpPromptComposer({
    super.key,
    required this.connection,
    required this.onSend,
    required this.onCancel,
  });

  final AcpConnected connection;
  final Future<bool> Function(List<ContentBlock> content) onSend;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController();
    final input = useValueListenable(controller);
    final attachments = useState<List<AcpPromptAttachment>>(const []);
    final dispatching = useState(false);
    final picking = useState(false);
    final enabled =
        connection.activeSession != null &&
        connection.authStatus != AcpAuthStatus.required;
    final canSend =
        enabled &&
        connection.busy == null &&
        !connection.isPrompting &&
        !dispatching.value &&
        (input.text.trim().isNotEmpty || attachments.value.isNotEmpty);

    Future<void> send() async {
      if (!canSend) return;
      final text = controller.text.trim();
      final content = <ContentBlock>[
        if (text.isNotEmpty) TextContentBlock(text: text),
        for (final attachment in attachments.value) attachment.content,
      ];
      dispatching.value = true;
      try {
        if (await onSend(content)) {
          controller.clear();
          attachments.value = const [];
        }
      } finally {
        dispatching.value = false;
      }
    }

    Future<void> addAttachment(_AttachAction action) async {
      if (picking.value || !enabled || connection.isPrompting) return;
      picking.value = true;
      try {
        final attachment = action == _AttachAction.resourceUri
            ? await _showResourceLinkDialog(context)
            : await pickAcpPromptAttachment(action.kind!);
        if (attachment == null || !context.mounted) return;
        if (attachments.value.any(
          (existing) => existing.identity == attachment.identity,
        )) {
          _showComposerError(
            context,
            context.t.ai.composer.duplicateAttachment,
          );
          return;
        }
        final next = [...attachments.value, attachment];
        validateAcpPromptAttachmentBudget(next);
        attachments.value = List.unmodifiable(next);
      } on AcpPromptAttachmentException catch (error) {
        if (context.mounted) _showComposerError(context, error.message);
      } on FileSystemException catch (error) {
        if (context.mounted) {
          _showComposerError(
            context,
            error.message.isEmpty ? '$error' : error.message,
          );
        }
      } finally {
        picking.value = false;
      }
    }

    return _ComposerSurface(
      connection: connection,
      controller: controller,
      attachments: attachments.value,
      enabled: enabled,
      canSend: canSend,
      picking: picking.value,
      onSend: send,
      onCancel: onCancel,
      onAttach: addAttachment,
      onRemoveAttachment: (identity) {
        attachments.value = List.unmodifiable(
          attachments.value.where((item) => item.identity != identity),
        );
      },
    );
  }
}

enum _AttachAction { image, audio, embeddedContext, fileLink, resourceUri }

extension on _AttachAction {
  AcpPromptAttachmentKind? get kind => switch (this) {
    _AttachAction.image => AcpPromptAttachmentKind.image,
    _AttachAction.audio => AcpPromptAttachmentKind.audio,
    _AttachAction.embeddedContext => AcpPromptAttachmentKind.embeddedContext,
    _AttachAction.fileLink => AcpPromptAttachmentKind.fileLink,
    _AttachAction.resourceUri => null,
  };
}

final class _ComposerSurface extends StatelessWidget {
  const _ComposerSurface({
    required this.connection,
    required this.controller,
    required this.attachments,
    required this.enabled,
    required this.canSend,
    required this.picking,
    required this.onSend,
    required this.onCancel,
    required this.onAttach,
    required this.onRemoveAttachment,
  });

  final AcpConnected connection;
  final TextEditingController controller;
  final List<AcpPromptAttachment> attachments;
  final bool enabled;
  final bool canSend;
  final bool picking;
  final Future<void> Function() onSend;
  final VoidCallback onCancel;
  final ValueChanged<_AttachAction> onAttach;
  final ValueChanged<String> onRemoveAttachment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final commands = connection.activeSession?.availableCommands ?? const [];
    void submit() {
      if (canSend) onSend();
    }

    void selectCommand(AvailableCommand command) {
      final current = controller.text.trimLeft();
      final suffix = current.isNotEmpty
          ? ' $current'
          : command.input == null
          ? ''
          : ' ';
      final text = '/${command.name}$suffix';
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (attachments.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final attachment in attachments)
                  _AttachmentChip(
                    attachment: attachment,
                    enabled: !connection.isPrompting,
                    onRemove: () => onRemoveAttachment(attachment.identity),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (commands.isNotEmpty) ...[
                _CommandMenu(
                  commands: commands,
                  enabled: enabled && !connection.isPrompting,
                  onSelected: selectCommand,
                ),
                const SizedBox(width: 8),
              ],
              _AttachmentMenu(
                capabilities: connection.capabilities.promptCapabilities,
                enabled: enabled && !connection.isPrompting && !picking,
                loading: picking,
                onSelected: onAttach,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CallbackShortcuts(
                  bindings: <ShortcutActivator, VoidCallback>{
                    const SingleActivator(
                      LogicalKeyboardKey.enter,
                      includeRepeats: false,
                    ): submit,
                    const SingleActivator(
                      LogicalKeyboardKey.numpadEnter,
                      includeRepeats: false,
                    ): submit,
                  },
                  child: TextField(
                    controller: controller,
                    enabled: enabled && !connection.isPrompting,
                    autofocus: true,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    minLines: 1,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText: enabled
                          ? context.t.ai.composer.messageHint
                          : context.t.ai.composer.sessionRequiredHint,
                      isDense: true,
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              connection.isPrompting
                  ? SizedBox.square(
                      dimension: ConsoleControlStyle.height,
                      child: IconButton.outlined(
                        onPressed: onCancel,
                        icon: const Icon(LucideIcons.square, size: 14),
                        tooltip: context.t.ai.composer.stopResponse,
                      ),
                    )
                  : ConsolePrimaryIconButton(
                      onPressed: canSend ? submit : null,
                      icon: const Icon(LucideIcons.arrowUp, size: 16),
                      tooltip: canSend
                          ? context.t.ai.composer.sendMessage
                          : context.t.ai.composer.addMessage,
                    ),
            ],
          ),
          if (attachments.any((item) => item.inlineBytes > 0)) ...[
            const SizedBox(height: 5),
            Text(
              context.t.ai.composer.inlineLimit(
                size: formatAcpByteSize(
                  attachments.fold<int>(
                    0,
                    (sum, item) => sum + item.inlineBytes,
                  ),
                ),
                limit: formatAcpByteSize(acpMaximumPromptInlineBytes),
              ),
              textAlign: TextAlign.right,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

final class _CommandMenu extends StatelessWidget {
  const _CommandMenu({
    required this.commands,
    required this.enabled,
    required this.onSelected,
  });

  final List<AvailableCommand> commands;
  final bool enabled;
  final ValueChanged<AvailableCommand> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: ConsoleControlStyle.height,
      child: PopupMenuButton<AvailableCommand>(
        enabled: enabled,
        tooltip: context.t.ai.composer.availableCommands,
        onSelected: onSelected,
        itemBuilder: (context) => [
          for (final command in commands)
            PopupMenuItem(
              value: command,
              child: _CommandMenuLabel(command: command),
            ),
        ],
        icon: const Icon(LucideIcons.command, size: 16),
      ),
    );
  }
}

final class _CommandMenuLabel extends StatelessWidget {
  const _CommandMenuLabel({required this.command});

  final AvailableCommand command;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '/${command.name}',
            style: theme.textTheme.labelMedium?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.primary,
            ),
          ),
          Text(command.description, style: theme.textTheme.bodySmall),
          if (command.input case final input?)
            Text(
              input.hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

final class _AttachmentMenu extends StatelessWidget {
  const _AttachmentMenu({
    required this.capabilities,
    required this.enabled,
    required this.loading,
    required this.onSelected,
  });

  final PromptCapabilities? capabilities;
  final bool enabled;
  final bool loading;
  final ValueChanged<_AttachAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: ConsoleControlStyle.height,
      child: PopupMenuButton<_AttachAction>(
        enabled: enabled,
        tooltip: context.t.ai.composer.addContext,
        onSelected: onSelected,
        itemBuilder: (context) => [
          if (capabilities?.image == true)
            PopupMenuItem(
              value: _AttachAction.image,
              child: _AttachmentMenuLabel(
                icon: LucideIcons.imagePlus,
                title: context.t.ai.composer.attachImage,
                subtitle: context.t.ai.composer.attachImageDescription,
              ),
            ),
          if (capabilities?.audio == true)
            PopupMenuItem(
              value: _AttachAction.audio,
              child: _AttachmentMenuLabel(
                icon: LucideIcons.audioLines,
                title: context.t.ai.composer.attachAudio,
                subtitle: context.t.ai.composer.attachAudioDescription,
              ),
            ),
          if (capabilities?.embeddedContext == true)
            PopupMenuItem(
              value: _AttachAction.embeddedContext,
              child: _AttachmentMenuLabel(
                icon: LucideIcons.fileInput,
                title: context.t.ai.composer.embedContext,
                subtitle: context.t.ai.composer.embedContextDescription,
              ),
            ),
          PopupMenuItem(
            value: _AttachAction.fileLink,
            child: _AttachmentMenuLabel(
              icon: LucideIcons.fileSymlink,
              title: context.t.ai.composer.linkFile,
              subtitle: context.t.ai.composer.linkFileDescription,
            ),
          ),
          PopupMenuItem(
            value: _AttachAction.resourceUri,
            child: _AttachmentMenuLabel(
              icon: LucideIcons.link,
              title: context.t.ai.composer.linkResource,
              subtitle: context.t.ai.composer.linkResourceDescription,
            ),
          ),
        ],
        icon: loading
            ? const SizedBox.square(
                dimension: 15,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(LucideIcons.paperclip, size: 16),
      ),
    );
  }
}

final class _AttachmentMenuLabel extends StatelessWidget {
  const _AttachmentMenuLabel({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 9),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ],
    );
  }
}

final class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.attachment,
    required this.enabled,
    required this.onRemove,
  });

  final AcpPromptAttachment attachment;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.fromLTRB(8, 5, 3, 5),
      decoration: ConsoleShapes.decoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderColor: theme.dividerColor,
        radius: ConsoleShapes.smallRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_attachmentIcon(attachment.kind), size: 14),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium,
                ),
                Text(
                  attachment.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: enabled ? onRemove : null,
            tooltip: context.t.ai.composer.removeAttachment(
              name: attachment.name,
            ),
            visualDensity: VisualDensity.compact,
            iconSize: 13,
            icon: const Icon(LucideIcons.x),
          ),
        ],
      ),
    );
  }
}

Future<AcpPromptAttachment?> _showResourceLinkDialog(
  BuildContext context,
) async {
  final nameController = TextEditingController();
  final uriController = TextEditingController();
  final mimeController = TextEditingController();
  final descriptionController = TextEditingController();
  String? error;
  try {
    return await showDialog<AcpPromptAttachment>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(context.t.ai.composer.linkResource),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConsoleTextField(
                    controller: nameController,
                    autofocus: true,
                    label: context.t.ai.composer.name,
                    hint: context.t.ai.composer.nameHint,
                  ),
                  const SizedBox(height: 10),
                  ConsoleTextField(
                    controller: uriController,
                    label: context.t.ai.composer.absoluteUri,
                    hint: 'file:///path/to/spec.yaml',
                    autocorrect: false,
                    enableSuggestions: false,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 10),
                  ConsoleTextField(
                    controller: mimeController,
                    label: context.t.ai.composer.mimeOptional,
                    hint: 'application/yaml',
                    autocorrect: false,
                    enableSuggestions: false,
                  ),
                  const SizedBox(height: 10),
                  ConsoleTextArea(
                    controller: descriptionController,
                    label: context.t.ai.composer.descriptionOptional,
                    minLines: 2,
                    maxLines: 3,
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        error!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
              child: Text(context.t.common.cancel),
            ),
            FilledButton(
              onPressed: () {
                final uri = Uri.tryParse(uriController.text.trim());
                if (nameController.text.trim().isEmpty ||
                    uri == null ||
                    !uri.hasScheme) {
                  setState(() {
                    error = context.t.ai.composer.resourceError;
                  });
                  return;
                }
                Navigator.pop(
                  context,
                  createAcpResourceLink(
                    name: nameController.text,
                    uri: uri,
                    description: descriptionController.text,
                    mimeType: mimeController.text,
                  ),
                );
              },
              child: Text(context.t.ai.composer.addResource),
            ),
          ],
        ),
      ),
    );
  } finally {
    nameController.dispose();
    uriController.dispose();
    mimeController.dispose();
    descriptionController.dispose();
  }
}

IconData _attachmentIcon(AcpPromptAttachmentKind kind) => switch (kind) {
  AcpPromptAttachmentKind.image => LucideIcons.image,
  AcpPromptAttachmentKind.audio => LucideIcons.audioLines,
  AcpPromptAttachmentKind.embeddedContext => LucideIcons.fileInput,
  AcpPromptAttachmentKind.fileLink => LucideIcons.link,
};

void _showComposerError(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
