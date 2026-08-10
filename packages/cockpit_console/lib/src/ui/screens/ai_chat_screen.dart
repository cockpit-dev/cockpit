import 'dart:convert';

import 'package:acpd/acpd.dart'
    show PermissionOption, PermissionOptionKind, TextContentBlock;
import 'package:cockpit_console/src/providers/acp_provider.dart';
import 'package:cockpit_console/src/providers/agent_presets.dart';
import 'package:cockpit_console/src/providers/core_providers.dart';
import 'package:cockpit_console/src/providers/data_providers.dart';
import 'package:cockpit_console/src/providers/preferences_store.dart';
import 'package:cockpit_console/src/theme/console_control_style.dart';
import 'package:cockpit_console/src/theme/console_shapes.dart';
import 'package:cockpit_console/src/ui/navigation/console_nav.dart';
import 'package:cockpit_console/src/ui/widgets/acp_connection_options.dart';
import 'package:cockpit_console/src/ui/widgets/acp_prompt_composer.dart';
import 'package:cockpit_console/src/ui/widgets/acp_session_controls.dart';
import 'package:cockpit_console/src/ui/widgets/acp_tool_call_view.dart';
import 'package:cockpit_console/src/ui/widgets/console_form_controls.dart';
import 'package:cockpit_console/src/ui/widgets/screen_scaffold.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// AI Assistant screen powered by ACP (Agent Client Protocol).
///
/// Normal user flow:
/// 1. Pick an agent from known presets (or custom command).
/// 2. Select a working directory via the system folder picker.
/// 3. Connect and start chatting with streaming responses.
///
/// The default page shows agent selection + recent sessions. Once connected,
/// it shows the chat conversation. Generated cockpit.test/v2 documents can
/// be sent to the Documents editor.
final class AiChatScreen extends HookConsumerWidget {
  const AiChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acpState = ref.watch(acpAgentProvider);

    return ScreenScaffold(
      title: 'AI Assistant',
      subtitle: _subtitleFor(acpState),
      stackActionsBelowWidth: 420,
      actions: [
        if (acpState is AcpConnected) ...[
          if (acpState.messages.isNotEmpty)
            TextButton.icon(
              onPressed: acpState.isPrompting
                  ? null
                  : () => ref.read(acpAgentProvider.notifier).clearMessages(),
              icon: const Icon(LucideIcons.eraser, size: 13),
              label: const Text('Clear'),
            ),
          TextButton.icon(
            onPressed: () => ref.read(acpAgentProvider.notifier).disconnect(),
            icon: const Icon(LucideIcons.logOut, size: 13),
            label: const Text('Disconnect'),
          ),
        ],
      ],
      body: acpState is AcpConnected
          ? _ChatView(connection: acpState)
          : _OnboardingView(
              connecting: acpState is AcpConnecting,
              errorMessage: switch (acpState) {
                AcpError(:final message) => message,
                _ => null,
              },
            ),
    );
  }

  String _subtitleFor(AcpAgentState state) {
    return switch (state) {
      AcpDisconnected() => 'Connect an AI agent to start',
      AcpConnecting() => 'Connecting...',
      AcpConnected(:final agentInfo) =>
        '${agentInfo.name} ${agentInfo.version}',
      AcpError(:final message) =>
        message.length > 60 ? '${message.substring(0, 60)}...' : message,
    };
  }
}

const _customAgentId = 'custom';
const _customAgentPreset = AgentPreset(
  id: _customAgentId,
  name: 'Custom',
  command: '',
  description: 'Any ACP executable',
  icon: 'terminal',
);

// ── Onboarding: agent selection + directory + recent ────────────────────

final class _OnboardingView extends HookConsumerWidget {
  const _OnboardingView({required this.connecting, this.errorMessage});

  final bool connecting;
  final String? errorMessage;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final prefsAsync = ref.watch(preferencesProvider);
    final selectedAgentId = useState<String?>(null);
    final sessionCwdController = useTextEditingController();
    final customExecutableController = useTextEditingController();
    final customArgsController = useTextEditingController();
    final connectionOptions = useState(const AcpConnectionOptions());
    final sessionCwd = useValueListenable(sessionCwdController);
    final customExecutable = useValueListenable(customExecutableController);
    final preferencesLoaded = useRef(false);
    final isCustomAgent = selectedAgentId.value == _customAgentId;
    final selectedPreset = findAgentPreset(selectedAgentId.value);
    final canConnect =
        sessionCwd.text.trim().isNotEmpty &&
        (isCustomAgent
            ? customExecutable.text.trim().isNotEmpty
            : selectedPreset != null);

    // Load last-used agent and directory from prefs.
    useEffect(() {
      prefsAsync.maybeWhen(
        data: (prefs) {
          if (preferencesLoaded.value) return;
          preferencesLoaded.value = true;
          selectedAgentId.value ??= prefs.lastAgentId;
          if (sessionCwdController.text.isEmpty) {
            sessionCwdController.text = prefs.lastSessionCwd ?? '';
          }
          customExecutableController.text = prefs.customAgentExecutable ?? '';
          customArgsController.text = prefs.customAgentArgs.join('\n');
        },
        orElse: () {},
      );
      return null;
    }, [prefsAsync]);

    Future<void> connect() async {
      final selectedId = selectedAgentId.value;
      final cwd = sessionCwdController.text.trim();
      if (selectedId == null || cwd.isEmpty) return;

      final preset = findAgentPreset(selectedId);
      final String executable;
      final List<String> arguments;
      if (selectedId == _customAgentId) {
        executable = customExecutableController.text.trim();
        if (executable.isEmpty) return;
        arguments = customArgsController.text
            .split('\n')
            .map((argument) => argument.trim())
            .where((argument) => argument.isNotEmpty)
            .toList(growable: false);
      } else {
        if (preset == null) return;
        executable = preset.command;
        arguments = preset.args;
      }

      final prefs = await ref.read(preferencesProvider.future);
      await prefs.setLastAgentId(selectedId);
      await prefs.setLastSessionCwd(cwd);
      if (selectedId == _customAgentId) {
        await prefs.setCustomAgentExecutable(executable);
        await prefs.setCustomAgentArgs(arguments);
      }

      await ref
          .read(acpAgentProvider.notifier)
          .connect(
            AcpConnectionConfig(
              command: executable,
              args: arguments,
              sessionCwd: cwd,
              additionalDirectories:
                  connectionOptions.value.additionalDirectories,
              mcpServers: connectionOptions.value.mcpServers,
            ),
          );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Hero.
              const SizedBox(height: 20),
              Align(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: ConsoleShapes.decoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    radius: ConsoleShapes.dialogRadius,
                  ),
                  child: Icon(
                    LucideIcons.sparkles,
                    size: 26,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Choose an AI agent',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(fontSize: 18),
              ),
              const SizedBox(height: 4),
              Text(
                'Select an agent and a working directory to start a conversation. '
                'Any ACP-compatible agent is supported.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),

              // Agent grid.
              Text(
                'Agent',
                style: theme.textTheme.titleSmall?.copyWith(fontSize: 12),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in agentPresets)
                    _AgentChip(
                      preset: preset,
                      selected: selectedAgentId.value == preset.id,
                      onTap: () => selectedAgentId.value = preset.id,
                    ),
                  _AgentChip(
                    preset: _customAgentPreset,
                    selected: selectedAgentId.value == _customAgentId,
                    onTap: () => selectedAgentId.value = _customAgentId,
                  ),
                ],
              ),
              if (isCustomAgent) ...[
                const SizedBox(height: 12),
                _CustomAgentFields(
                  executableController: customExecutableController,
                  argsController: customArgsController,
                ),
              ],
              const SizedBox(height: 24),

              // Directory picker.
              _DirectoryPicker(
                controller: sessionCwdController,
                enabled: !connecting,
                onPick: () async {
                  final dir = await FilePicker.getDirectoryPath(
                    dialogTitle: 'Select working directory',
                  );
                  if (dir != null) {
                    sessionCwdController.text = dir;
                  }
                },
              ),
              const SizedBox(height: 16),
              AcpConnectionOptionsEditor(
                value: connectionOptions.value,
                enabled: !connecting,
                onChanged: (value) => connectionOptions.value = value,
              ),
              const SizedBox(height: 24),

              // Connect button.
              FilledButton.icon(
                onPressed: connecting || !canConnect ? null : connect,
                icon: connecting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.arrowRight, size: 16),
                label: Text(connecting ? 'Connecting...' : 'Start session'),
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: ConsoleShapes.decoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.error.withValues(alpha: 0.06),
                    borderColor: Theme.of(
                      context,
                    ).colorScheme.error.withValues(alpha: 0.2),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        LucideIcons.alertCircle,
                        size: 14,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          errorMessage!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.error,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

final class _AgentChip extends StatelessWidget {
  const _AgentChip({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final AgentPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = selected
        ? theme.colorScheme.primary.withValues(alpha: 0.1)
        : theme.colorScheme.surfaceContainerLow;
    final border = selected
        ? theme.colorScheme.primary.withValues(alpha: 0.4)
        : theme.dividerColor;
    final fg = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;

    return Semantics(
      button: true,
      selected: selected,
      label: preset.name,
      hint: preset.description,
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: ConsoleShapes.border(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: ConsoleShapes.decoration(color: bg, borderColor: border),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_iconFor(preset.icon), size: 15, color: fg),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preset.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                  Text(
                    preset.description,
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String name) {
    return switch (name) {
      'brain' => LucideIcons.brain,
      'sparkles' => LucideIcons.sparkles,
      'mouse-pointer-click' => LucideIcons.mousePointerClick,
      'bird' => LucideIcons.bird,
      'rocket' => LucideIcons.rocket,
      'gem' => LucideIcons.gem,
      'github' => LucideIcons.gitBranch,
      'terminal' => LucideIcons.terminal,
      'code' => LucideIcons.code,
      'pi' => LucideIcons.pi,
      'braces' => LucideIcons.braces,
      'hand' => LucideIcons.hand,
      'zap' => LucideIcons.zap,
      'moon' => LucideIcons.moon,
      'cpu' => LucideIcons.cpu,
      'wind' => LucideIcons.wind,
      'factory' => LucideIcons.factory,
      'box' => LucideIcons.box,
      _ => LucideIcons.bot,
    };
  }
}

final class _CustomAgentFields extends StatelessWidget {
  const _CustomAgentFields({
    required this.executableController,
    required this.argsController,
  });

  final TextEditingController executableController;
  final TextEditingController argsController;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ConsoleTextField(
          controller: executableController,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          label: 'Executable',
          hint: '/path/to/acp-agent',
          prefixIcon: const Icon(LucideIcons.terminal, size: 16),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
        const SizedBox(height: 12),
        ConsoleTextArea(
          controller: argsController,
          autocorrect: false,
          enableSuggestions: false,
          minLines: 2,
          maxLines: 4,
          label: 'Arguments (one per line)',
          hint: '--flag\nvalue with spaces',
          supportingText: 'Passed directly to the executable without a shell.',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ],
    );
  }
}

final class _DirectoryPicker extends StatelessWidget {
  const _DirectoryPicker({
    required this.controller,
    required this.enabled,
    required this.onPick,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return ConsoleTextField(
      controller: controller,
      enabled: enabled,
      label: 'Working directory',
      autocorrect: false,
      enableSuggestions: false,
      hint: '/absolute/path/to/project',
      prefixIcon: const Icon(LucideIcons.folderOpen, size: 16),
      suffixIcon: IconButton(
        onPressed: enabled ? onPick : null,
        icon: const Icon(LucideIcons.folderSearch, size: 16),
        tooltip: 'Browse directories',
        style: ConsoleControlStyle.fieldIconButtonStyle(),
      ),
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
    );
  }
}

// ── Chat view ────────────────────────────────────────────────────────────

final class _ChatView extends HookConsumerWidget {
  const _ChatView({required this.connection});

  final AcpConnected connection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = connection.messages;
    final scrollCtrl = useScrollController();

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && scrollCtrl.hasClients) {
          scrollCtrl.animateTo(
            scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      });
      return null;
    }, [messages]);

    void sendToEditor(_ExtractedCockpitDocument document) {
      final workspaceId = ref.read(selectedWorkspaceIdProvider);
      if (workspaceId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select a project before editing.')),
        );
        ref.read(navProvider.notifier).go(ConsoleNavDestination.workspaces);
        return;
      }

      ref.read(documentProvider.notifier)
        ..activateWorkspace(workspaceId)
        ..setFormat(document.format)
        ..setContent(document.content);
      ref.read(navProvider.notifier).go(ConsoleNavDestination.documents);
    }

    final pendingPermission = connection.pendingPermission;
    final conversation = Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? _ChatEmpty(connection: connection)
              : ListView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) => _MessageBubble(
                    message: messages[index],
                    toolCalls: connection.activeSession?.toolCalls ?? const {},
                    onSendToEditor: sendToEditor,
                  ),
                ),
        ),
        if (pendingPermission != null) ...[
          Container(height: 1, color: Theme.of(context).dividerColor),
          _PermissionSurface(
            prompt: pendingPermission,
            onRespond: (optionId) => ref
                .read(acpAgentProvider.notifier)
                .respondToPermission(
                  requestId: pendingPermission.requestId,
                  optionId: optionId,
                ),
          ),
        ],
        Container(height: 1, color: Theme.of(context).dividerColor),
        AcpPromptComposer(
          connection: connection,
          onSend: ref.read(acpAgentProvider.notifier).sendPromptContent,
          onCancel: () => ref.read(acpAgentProvider.notifier).cancelTurn(),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 920) {
          return Row(
            children: [
              Container(
                width: 304,
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: AcpSessionControls(connection: connection),
                ),
              ),
              Container(width: 1, color: Theme.of(context).dividerColor),
              Expanded(child: conversation),
            ],
          );
        }
        return Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              child: ExpansionTile(
                initiallyExpanded: connection.activeSession == null,
                leading: const Icon(LucideIcons.slidersHorizontal, size: 16),
                title: Text(
                  connection.activeSession?.title ??
                      (connection.activeSession == null
                          ? 'Agent setup'
                          : 'Session controls'),
                ),
                subtitle: Text(
                  connection.activeSession?.cwd ??
                      _authStatusLabel(connection.authStatus),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * 0.58,
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: AcpSessionControls(connection: connection),
                    ),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: Theme.of(context).dividerColor),
            Expanded(child: conversation),
          ],
        );
      },
    );
  }
}

final class _PermissionSurface extends StatelessWidget {
  const _PermissionSurface({required this.prompt, required this.onRespond});

  final AcpPermissionPrompt prompt;
  final ValueChanged<String?> onRespond;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toolCall = prompt.toolCall;
    final rawInput = toolCall.rawInput == null
        ? null
        : _formatAcpRawValue(toolCall.rawInput!);
    final hasRawInput = rawInput != null;
    final locations = toolCall.locations;

    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: ConsoleShapes.decoration(
              color: theme.colorScheme.primaryContainer,
              radius: ConsoleShapes.smallRadius,
            ),
            child: Icon(
              LucideIcons.shieldQuestion,
              size: 15,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  toolCall.title,
                  style: theme.textTheme.titleSmall?.copyWith(fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  'Permission required to continue',
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                ),
                if (hasRawInput || locations.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 128),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: ConsoleShapes.decoration(
                        color: theme.colorScheme.surfaceContainer,
                        radius: ConsoleShapes.smallRadius,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (hasRawInput) ...[
                              Text(
                                'Input',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 2),
                              SelectableText(
                                rawInput,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  height: 1.4,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ],
                            if (hasRawInput && locations.isNotEmpty)
                              const SizedBox(height: 8),
                            if (locations.isNotEmpty) ...[
                              Text(
                                locations.length == 1
                                    ? 'Location'
                                    : 'Locations',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 2),
                              for (final location in locations)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        LucideIcons.mapPin,
                                        size: 11,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: SelectableText(
                                          '${location.path}${location.line == null ? '' : ':${location.line}'}',
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 11,
                                            height: 1.4,
                                            color: theme.colorScheme.onSurface,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final option in prompt.options)
                      _optionButton(context, option),
                    TextButton.icon(
                      onPressed: () => onRespond(null),
                      icon: const Icon(LucideIcons.x, size: 13),
                      label: const Text('Cancel request'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _optionButton(BuildContext context, PermissionOption option) {
    void onPressed() => onRespond(option.optionId);
    return switch (option.kind) {
      PermissionOptionKind.allowOnce => FilledButton(
        onPressed: onPressed,
        child: Text(option.name),
      ),
      PermissionOptionKind.allowAlways => FilledButton.tonal(
        onPressed: onPressed,
        child: Text(option.name),
      ),
      PermissionOptionKind.rejectOnce => OutlinedButton(
        onPressed: onPressed,
        child: Text(option.name),
      ),
      PermissionOptionKind.rejectAlways => TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
        ),
        child: Text(option.name),
      ),
    };
  }
}

final class _ChatEmpty extends StatelessWidget {
  const _ChatEmpty({required this.connection});

  final AcpConnected connection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, title, description) = switch ((
      connection.authStatus,
      connection.activeSession,
    )) {
      (AcpAuthStatus.required, _) => (
        LucideIcons.lockKeyhole,
        'Sign in to continue',
        'Choose an authentication method in Agent setup, then finish the agent sign-in flow.',
      ),
      (_, null) => (
        LucideIcons.messageSquarePlus,
        'Create or open a session',
        'Use Agent setup to start a new session or resume recent work.',
      ),
      _ => (
        LucideIcons.messageCircle,
        'Start a conversation',
        'Ask about your workspace, request a change, or describe a test scenario.',
      ),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 32,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ExtractedCockpitDocument {
  const _ExtractedCockpitDocument({
    required this.content,
    required this.format,
  });

  final String content;
  final CockpitDocumentFormat format;
}

_ExtractedCockpitDocument? _extractCockpitDocument(String message) {
  final candidates = <String>[
    for (final match in RegExp(
      r'```(?:ya?ml|json)?[ \t]*\r?\n([\s\S]*?)```',
      caseSensitive: false,
    ).allMatches(message))
      match.group(1)!,
    message,
  ];

  for (final candidate in candidates) {
    final content = candidate.trim();
    if (content.isEmpty) continue;
    if (content.startsWith('{')) {
      try {
        final decoded = jsonDecode(content);
        if (decoded is Map &&
            decoded['schemaVersion'] == 'cockpit.test/v2' &&
            (decoded['kind'] == 'case' || decoded['kind'] == 'suite')) {
          return _ExtractedCockpitDocument(
            content: '$content\n',
            format: CockpitDocumentFormat.json,
          );
        }
      } on FormatException {
        // Continue looking for a valid fenced candidate.
      }
      continue;
    }

    final hasSchema = RegExp(
      r'^\s*schemaVersion\s*:\s*["\x27]?cockpit\.test/v2["\x27]?\s*$',
      multiLine: true,
    ).hasMatch(content);
    final hasKind = RegExp(
      r'^\s*kind\s*:\s*["\x27]?(?:case|suite)["\x27]?\s*$',
      multiLine: true,
    ).hasMatch(content);
    if (hasSchema && hasKind) {
      return _ExtractedCockpitDocument(
        content: '$content\n',
        format: CockpitDocumentFormat.yaml,
      );
    }
  }
  return null;
}

final class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.toolCalls,
    required this.onSendToEditor,
  });

  final AcpChatMessage message;
  final Map<String, AcpToolCallState> toolCalls;
  final void Function(_ExtractedCockpitDocument document) onSendToEditor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == AcpMessageRole.user;
    final isError = message.role == AcpMessageRole.error;
    final extractedDocument = _extractCockpitDocument(message.text);
    final messageToolCalls = message.toolCallIds
        .map((id) => toolCalls[id])
        .whereType<AcpToolCallState>()
        .toList(growable: false);

    final bg = isError
        ? theme.colorScheme.error.withValues(alpha: 0.06)
        : isUser
        ? theme.colorScheme.primary.withValues(alpha: 0.08)
        : theme.colorScheme.surfaceContainerLow;
    final fg = isError
        ? theme.colorScheme.error
        : isUser
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            _Avatar(role: message.role),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.6,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: ConsoleShapes.decoration(color: bg),
              child: message.isStreaming && message.text.isEmpty
                  ? _TypingIndicator(color: fg)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (message.thoughts.isNotEmpty) ...[
                          for (final thought in message.thoughts)
                            Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: ConsoleShapes.decoration(
                                color: theme.colorScheme.surfaceContainer,
                                radius: 6,
                              ),
                              child: Text(
                                thought,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          const SizedBox(height: 6),
                        ],
                        if (message.text.isNotEmpty)
                          SelectableText(
                            message.text,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: fg,
                            ),
                          ),
                        if (message.content.any(
                          (block) => block is! TextContentBlock,
                        )) ...[
                          if (message.text.isNotEmpty)
                            const SizedBox(height: 8),
                          AcpMessageContentView(content: message.content),
                        ],
                        if (messageToolCalls.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          for (final toolCall in messageToolCalls)
                            AcpToolCallView(toolCall: toolCall),
                        ],
                        if (!isUser && extractedDocument != null) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () =>
                                  onSendToEditor(extractedDocument),
                              icon: const Icon(
                                LucideIcons.arrowRight,
                                size: 12,
                              ),
                              label: const Text('Send to editor'),
                              style: TextButton.styleFrom(
                                foregroundColor: theme.colorScheme.primary,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            _Avatar(role: message.role),
          ],
        ],
      ),
    );
  }
}

final class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator({required this.color});

  final Color color;

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

final class _TypingIndicatorState extends State<_TypingIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return Padding(
          padding: EdgeInsets.only(right: i < 2 ? 3 : 0),
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              final phase = (_ctrl.value * 3 - i).clamp(0.0, 1.0);
              return Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.3 + phase * 0.7),
                  shape: BoxShape.circle,
                ),
              );
            },
          ),
        );
      }),
    );
  }
}

final class _Avatar extends StatelessWidget {
  const _Avatar({required this.role});

  final AcpMessageRole role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = role == AcpMessageRole.user;
    final isError = role == AcpMessageRole.error;
    final color = isError
        ? theme.colorScheme.error
        : isUser
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Container(
      width: 24,
      height: 24,
      decoration: ConsoleShapes.decoration(
        color: color.withValues(alpha: 0.12),
        radius: ConsoleShapes.smallRadius,
      ),
      child: Icon(
        isError
            ? LucideIcons.alertTriangle
            : isUser
            ? LucideIcons.user
            : LucideIcons.bot,
        size: 13,
        color: color,
      ),
    );
  }
}

String _authStatusLabel(AcpAuthStatus status) => switch (status) {
  AcpAuthStatus.unavailable => 'Ready',
  AcpAuthStatus.available => 'Sign-in available',
  AcpAuthStatus.required => 'Sign-in required',
  AcpAuthStatus.authenticating => 'Signing in…',
  AcpAuthStatus.authenticated => 'Signed in',
  AcpAuthStatus.loggingOut => 'Signing out…',
};

String _formatAcpRawValue(Object value) {
  if (value is String) return value;
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } on JsonUnsupportedObjectError {
    return value.toString();
  }
}
