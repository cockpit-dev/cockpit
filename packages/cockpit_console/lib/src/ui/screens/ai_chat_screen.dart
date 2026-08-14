import 'dart:convert';
import 'dart:math' as math;

import 'package:acpd/acpd.dart'
    show ContentBlock, PermissionOption, PermissionOptionKind, TextContentBlock;
import 'package:cockpit_console/src/providers/acp_provider.dart';
import 'package:cockpit_console/src/providers/agent_presets.dart';
import 'package:cockpit_console/src/providers/core_providers.dart';
import 'package:cockpit_console/src/providers/data_providers.dart';
import 'package:cockpit_console/src/providers/preferences_store.dart';
import 'package:cockpit_console/src/theme/console_colors.dart';
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
/// The default page shows agent selection. Once connected, the primary surface
/// is deliberately only the conversation and composer; complete ACP controls
/// remain available through one progressively disclosed settings dialog.
/// Generated cockpit.test/v2 documents can be sent to the Documents editor.
final class AiChatScreen extends HookConsumerWidget {
  const AiChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acpState = ref.watch(acpAgentProvider);

    void openConnectionDialog() {
      showDialog<void>(
        context: context,
        builder: (context) => const _AcpConnectionDialog(),
      );
    }

    void openSettingsDialog() {
      showDialog<void>(
        context: context,
        builder: (context) => const _AcpSettingsDialog(),
      );
    }

    return ScreenScaffold(
      title: 'AI Assistant',
      subtitle: _subtitleFor(acpState),
      stackActionsBelowWidth: 0,
      actions: [
        if (acpState is AcpConnected)
          IconButton(
            key: const ValueKey('ai-agent-settings'),
            onPressed: openSettingsDialog,
            icon: const Icon(LucideIcons.settings2, size: 17),
            tooltip: 'Agent settings',
          ),
      ],
      body: acpState is AcpConnected
          ? _ChatView(connection: acpState, onOpenSettings: openSettingsDialog)
          : _DisconnectedChatView(
              connecting: acpState is AcpConnecting,
              errorMessage: switch (acpState) {
                AcpError(:final message) => message,
                _ => null,
              },
              onConnect: openConnectionDialog,
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

/// Keeps first-run state inside the same familiar conversation structure used
/// after connection. Agent selection is disclosed only when requested.
final class _DisconnectedChatView extends StatelessWidget {
  const _DisconnectedChatView({
    required this.connecting,
    required this.errorMessage,
    required this.onConnect,
  });

  final bool connecting;
  final String? errorMessage;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: ConsoleShapes.decoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.1),
                        radius: ConsoleShapes.surfaceRadius,
                      ),
                      child: Icon(
                        LucideIcons.sparkles,
                        size: 21,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      connecting
                          ? 'Connecting to agent'
                          : 'Start a conversation',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      errorMessage ??
                          'Connect an ACP-compatible agent, then ask questions or run development tasks here.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: errorMessage == null
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: connecting ? null : onConnect,
                      icon: connecting
                          ? const SizedBox.square(
                              dimension: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(LucideIcons.plug, size: 16),
                      label: Text(
                        connecting ? 'Connecting...' : 'Connect agent',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Container(height: 1, color: theme.dividerColor),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  readOnly: true,
                  canRequestFocus: false,
                  onTap: connecting ? null : onConnect,
                  decoration: InputDecoration(
                    hintText: connecting
                        ? 'Connecting to agent...'
                        : 'Connect an agent to start chatting',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ConsoleFieldIconButton(
                onPressed: connecting ? null : onConnect,
                icon: connecting
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.plug, size: 16),
                tooltip: connecting ? 'Connecting to agent' : 'Connect agent',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Complete connection setup shown only when the user asks to connect an
/// agent. Keeping it modal preserves a quiet chat surface without removing any
/// ACP capability.
final class _AcpConnectionDialog extends ConsumerWidget {
  const _AcpConnectionDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(acpAgentProvider);
    final dialogHeight = math.min(
      760.0,
      math.max(0.0, MediaQuery.sizeOf(context).height - 32),
    );
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SizedBox(
          height: dialogHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 58,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 8),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.plug, size: 17),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Connect AI agent',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              'Choose an agent and its working directory.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(LucideIcons.x, size: 16),
                        tooltip: 'Close connection setup',
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: Theme.of(context).dividerColor),
              Expanded(
                child: _OnboardingView(
                  connecting: state is AcpConnecting,
                  errorMessage: switch (state) {
                    AcpError(:final message) => message,
                    _ => null,
                  },
                  onConnected: () {
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Progressively disclosed ACP controls. The chat surface stays focused while
/// authentication, session lifecycle, agent modes, MCP, and connection actions
/// remain fully available when the operator needs them.
final class _AcpSettingsDialog extends HookConsumerWidget {
  const _AcpSettingsDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(acpAgentProvider);
    final connection = state is AcpConnected ? state : null;
    final disconnecting = useState(false);

    Future<void> disconnect() async {
      if (disconnecting.value) return;
      disconnecting.value = true;
      await ref.read(acpAgentProvider.notifier).disconnect();
      if (context.mounted) Navigator.of(context).pop();
    }

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.only(left: 16, right: 8),
                child: Row(
                  children: [
                    const Icon(LucideIcons.settings2, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Agent settings',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(LucideIcons.x, size: 16),
                      tooltip: 'Close settings',
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: Theme.of(context).dividerColor),
            Flexible(
              child: connection == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'The agent is no longer connected.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: AcpSessionControls(connection: connection),
                    ),
            ),
            if (connection != null) ...[
              Divider(height: 1, color: Theme.of(context).dividerColor),
              Padding(
                padding: const EdgeInsets.all(12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final clearButton = connection.messages.isEmpty
                        ? null
                        : TextButton.icon(
                            onPressed: connection.isPrompting
                                ? null
                                : ref
                                      .read(acpAgentProvider.notifier)
                                      .clearMessages,
                            icon: const Icon(LucideIcons.eraser, size: 14),
                            label: const Text('Clear chat view'),
                          );
                    final disconnectButton = OutlinedButton.icon(
                      onPressed: disconnecting.value ? null : disconnect,
                      icon: disconnecting.value
                          ? const SizedBox.square(
                              dimension: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(LucideIcons.logOut, size: 14),
                      label: const Text('Disconnect agent'),
                    );

                    if (constraints.maxWidth < 420) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (clearButton != null) ...[
                            clearButton,
                            const SizedBox(height: 8),
                          ],
                          disconnectButton,
                        ],
                      );
                    }

                    return Row(
                      children: [
                        ?clearButton,
                        const Spacer(),
                        disconnectButton,
                      ],
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
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
  const _OnboardingView({
    required this.connecting,
    required this.onConnected,
    this.errorMessage,
  });

  final bool connecting;
  final VoidCallback onConnected;
  final String? errorMessage;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    final selectedAgent = isCustomAgent ? _customAgentPreset : selectedPreset;
    final canConnect =
        sessionCwd.text.trim().isNotEmpty &&
        (isCustomAgent
            ? customExecutable.text.trim().isNotEmpty
            : selectedPreset != null);

    // Load last-used agent and directory from prefs.
    useEffect(() {
      var cancelled = false;
      prefsAsync.maybeWhen(
        data: (prefs) {
          if (preferencesLoaded.value) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (cancelled || !context.mounted || preferencesLoaded.value) {
              return;
            }
            preferencesLoaded.value = true;
            selectedAgentId.value ??= prefs.lastAgentId;
            if (sessionCwdController.text.isEmpty) {
              sessionCwdController.text = prefs.lastSessionCwd ?? '';
            }
            customExecutableController.text = prefs.customAgentExecutable ?? '';
            customArgsController.text = prefs.customAgentArgs.join('\n');
          });
        },
        orElse: () {},
      );
      return () => cancelled = true;
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
      if (context.mounted && ref.read(acpAgentProvider) is AcpConnected) {
        onConnected();
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ConsoleDropdownField<String>(
                      key: ValueKey(selectedAgentId.value),
                      initialValue: selectedAgentId.value,
                      label: 'Agent',
                      hintText: 'Choose an AI agent',
                      prefixIcon: const Icon(LucideIcons.bot, size: 16),
                      supportingText: selectedAgent?.description,
                      items: <AgentPreset>[...agentPresets, _customAgentPreset]
                          .map(
                            (preset) => DropdownMenuItem<String>(
                              value: preset.id,
                              child: Text(preset.name),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: connecting
                          ? null
                          : (value) => selectedAgentId.value = value,
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
          ),
        ),
        Divider(height: 1, color: Theme.of(context).dividerColor),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: connecting || !canConnect ? null : connect,
                  icon: connecting
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.arrowRight, size: 16),
                  label: Text(connecting ? 'Connecting...' : 'Start session'),
                ),
              ),
            ),
          ),
        ),
      ],
    );
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
  const _ChatView({required this.connection, required this.onOpenSettings});

  final AcpConnected connection;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = connection.messages;
    final scrollCtrl = useScrollController();
    final followsLatest = useState(true);
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    void scrollToLatest({bool force = false}) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted || !scrollCtrl.hasClients) return;
        if (!force && !followsLatest.value) return;
        final target = scrollCtrl.position.maxScrollExtent;
        if (disableAnimations) {
          scrollCtrl.jumpTo(target);
        } else {
          scrollCtrl.animateTo(
            target,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }

    useEffect(() {
      void updateTailState() {
        if (!scrollCtrl.hasClients) return;
        final position = scrollCtrl.position;
        final next = position.maxScrollExtent - position.pixels <= 72;
        if (next != followsLatest.value) followsLatest.value = next;
      }

      scrollCtrl.addListener(updateTailState);
      return () => scrollCtrl.removeListener(updateTailState);
    }, [scrollCtrl]);

    useEffect(() {
      scrollToLatest();
      return null;
    }, [messages, followsLatest.value, disableAnimations]);

    Future<bool> sendPrompt(List<ContentBlock> content) async {
      followsLatest.value = true;
      final result = ref
          .read(acpAgentProvider.notifier)
          .sendPromptContent(content);
      scrollToLatest(force: true);
      return result;
    }

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
          child: Stack(
            children: [
              Positioned.fill(
                child: messages.isEmpty
                    ? _ChatEmpty(
                        connection: connection,
                        onOpenSettings: onOpenSettings,
                      )
                    : ListView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        itemCount: messages.length,
                        itemBuilder: (context, index) => _MessageBubble(
                          message: messages[index],
                          toolCalls:
                              connection.activeSession?.toolCalls ?? const {},
                          onSendToEditor: sendToEditor,
                        ),
                      ),
              ),
              if (!followsLatest.value && messages.isNotEmpty)
                Positioned(
                  right: 16,
                  bottom: 12,
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      followsLatest.value = true;
                      scrollToLatest(force: true);
                    },
                    icon: const Icon(LucideIcons.arrowDown, size: 14),
                    label: const Text('Latest'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
            ],
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
        if (connection.lastError case final error?) ...[
          Container(height: 1, color: Theme.of(context).dividerColor),
          _AcpInlineError(
            message: error,
            onDismiss: ref.read(acpAgentProvider.notifier).clearLastError,
          ),
        ],
        Container(height: 1, color: Theme.of(context).dividerColor),
        AcpPromptComposer(
          connection: connection,
          onSend: sendPrompt,
          onCancel: () => ref.read(acpAgentProvider.notifier).cancelTurn(),
        ),
      ],
    );
    return conversation;
  }
}

final class _AcpInlineError extends StatelessWidget {
  const _AcpInlineError({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.error.withValues(alpha: 0.055),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              LucideIcons.circleAlert,
              size: 14,
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(LucideIcons.x, size: 14),
            tooltip: 'Dismiss error',
          ),
        ],
      ),
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
  const _ChatEmpty({required this.connection, required this.onOpenSettings});

  final AcpConnected connection;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, title, description, actionLabel) = switch ((
      connection.authStatus,
      connection.activeSession,
    )) {
      (AcpAuthStatus.required, _) => (
        LucideIcons.lockKeyhole,
        'Sign in to continue',
        'Choose an authentication method in agent settings, then finish the sign-in flow.',
        'Open sign-in',
      ),
      (_, null) => (
        LucideIcons.messageSquarePlus,
        'Create or open a session',
        'Use agent settings to start a new session or resume recent work.',
        'Open session setup',
      ),
      _ => (
        LucideIcons.messageCircle,
        'Start a conversation',
        'Ask about your workspace, request a change, or describe a test scenario.',
        null,
      ),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: context.consoleColors.inkTertiary),
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
            if (actionLabel != null) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onOpenSettings,
                icon: const Icon(LucideIcons.settings2, size: 15),
                label: Text(actionLabel),
              ),
            ],
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
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final bubbleMaxWidth = viewportWidth < 720
        ? math.max(240.0, viewportWidth - 96)
        : math.min(720.0, viewportWidth * 0.72);

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
              constraints: BoxConstraints(maxWidth: bubbleMaxWidth),
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
  bool? _disableAnimations;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (_disableAnimations == disableAnimations) return;
    _disableAnimations = disableAnimations;
    if (disableAnimations) {
      _ctrl
        ..stop()
        ..value = 0;
    } else {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_disableAnimations ?? false) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          3,
          (index) => Padding(
            padding: EdgeInsets.only(right: index < 2 ? 3 : 0),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.62),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      );
    }
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

String _formatAcpRawValue(Object value) {
  if (value is String) return value;
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } on JsonUnsupportedObjectError {
    return value.toString();
  }
}
