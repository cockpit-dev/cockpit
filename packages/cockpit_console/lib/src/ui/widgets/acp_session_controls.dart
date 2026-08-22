import 'package:acpd/acpd.dart';
import 'package:cockpit_console/i18n/strings.g.dart';
import 'package:cockpit_console/src/providers/acp_provider.dart';
import 'package:cockpit_console/src/theme/console_shapes.dart';
import 'package:cockpit_console/src/ui/widgets/acp_connection_options.dart';
import 'package:cockpit_console/src/ui/widgets/console_form_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Complete ACP connection and session control surface.
final class AcpSessionControls extends HookConsumerWidget {
  const AcpSessionControls({super.key, required this.connection});

  final AcpConnected connection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedAuthMethod = useState<String?>(
      connection.authMethods.firstOrNull?.id,
    );
    useEffect(() {
      if (!connection.authMethods.any(
        (method) => method.id == selectedAuthMethod.value,
      )) {
        selectedAuthMethod.value = connection.authMethods.firstOrNull?.id;
      }
      return null;
    }, [connection.authMethods]);

    final notifier = ref.read(acpAgentProvider.notifier);
    final busy = connection.busy != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AgentSummary(connection: connection),
        if (connection.lastError case final error?) ...[
          const SizedBox(height: 12),
          _ErrorNotice(message: error),
        ],
        if (connection.authMethods.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Section(
            title: context.t.ai.session.authentication,
            icon: LucideIcons.keyRound,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AuthStatus(status: connection.authStatus),
                if (connection.authStatus != AcpAuthStatus.authenticated) ...[
                  const SizedBox(height: 8),
                  ConsoleDropdownField<String>(
                    initialValue: selectedAuthMethod.value,
                    items: [
                      for (final method in connection.authMethods)
                        DropdownMenuItem(
                          value: method.id,
                          child: Text(_authMethodName(method)),
                        ),
                    ],
                    onChanged: busy
                        ? null
                        : (value) => selectedAuthMethod.value = value,
                    supportingText: _authMethodDescription(
                      connection.authMethods,
                      selectedAuthMethod.value,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: busy || selectedAuthMethod.value == null
                        ? null
                        : () =>
                              notifier.authenticate(selectedAuthMethod.value!),
                    icon: const Icon(LucideIcons.logIn, size: 15),
                    label: Text(context.t.ai.session.signIn),
                  ),
                ] else if (connection.canLogout) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: busy ? null : notifier.logout,
                    icon: const Icon(LucideIcons.logOut, size: 15),
                    label: Text(context.t.ai.session.signOut),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        _SessionSection(connection: connection),
        if (connection.activeSession case final session?) ...[
          const SizedBox(height: 16),
          _SessionSettings(connection: connection, session: session),
          const SizedBox(height: 16),
          _SessionContext(session: session),
        ],
      ],
    );
  }
}

final class _AgentSummary extends StatelessWidget {
  const _AgentSummary({required this.connection});

  final AcpConnected connection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final capabilities = _capabilityLabels(context.t, connection.capabilities);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.bot, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                connection.agentInfo.title ?? connection.agentInfo.name,
                style: theme.textTheme.titleSmall,
              ),
            ),
            Text(
              'ACP v${connection.protocolVersion.toJson()}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          '${connection.agentInfo.name} ${connection.agentInfo.version}',
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (capabilities.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [for (final label in capabilities) _Tag(label: label)],
          ),
        ],
      ],
    );
  }
}

final class _SessionSection extends ConsumerWidget {
  const _SessionSection({required this.connection});

  final AcpConnected connection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(acpAgentProvider.notifier);
    final session = connection.activeSession;
    final busy = connection.busy != null || connection.isPrompting;
    final canOpenHistory =
        connection.canResumeSessions || connection.canLoadSessions;

    Future<void> createSession() async {
      final defaults = connection.sessionDefaults;
      if (defaults == null) return;
      final spec = await showAcpSessionEditor(
        context,
        initial: defaults,
        capabilities: connection.capabilities,
      );
      if (spec == null || !context.mounted) return;
      await notifier.createSession(
        cwd: spec.cwd,
        additionalDirectories: spec.additionalDirectories,
        mcpServers: spec.mcpServers,
      );
    }

    return _Section(
      title: context.t.ai.session.section,
      icon: LucideIcons.messagesSquare,
      trailing: connection.canListSessions
          ? IconButton(
              onPressed: busy ? null : notifier.refreshSessions,
              tooltip: context.t.ai.session.refreshRecent,
              icon: const Icon(LucideIcons.refreshCw, size: 14),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (session == null)
            Text(
              connection.authStatus == AcpAuthStatus.required
                  ? context.t.ai.session.signInFirst
                  : context.t.ai.session.noneOpen,
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            _ActiveSessionSummary(session: session),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed:
                    busy || connection.authStatus == AcpAuthStatus.required
                    ? null
                    : createSession,
                icon: const Icon(LucideIcons.plus, size: 15),
                label: Text(context.t.ai.session.newSession),
              ),
              if (session != null && connection.canCloseSessions)
                OutlinedButton.icon(
                  onPressed: busy ? null : notifier.closeSession,
                  icon: const Icon(LucideIcons.archive, size: 15),
                  label: Text(context.t.ai.session.close),
                ),
            ],
          ),
          if (connection.canListSessions) ...[
            const SizedBox(height: 12),
            Text(
              context.t.ai.session.recent,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 6),
            if (connection.recentSessions.isEmpty)
              Text(
                connection.busy == AcpBusyAction.listSessions
                    ? context.t.ai.session.loading
                    : context.t.ai.session.noneSaved,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final recent in connection.recentSessions)
                _RecentSessionRow(
                  session: recent,
                  active: recent.sessionId == session?.sessionId,
                  enabled: !busy,
                  canOpen: canOpenHistory,
                  canDelete: connection.canDeleteSessions,
                  preferResume: connection.canResumeSessions,
                ),
            if (connection.nextSessionCursor != null) ...[
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: busy ? null : notifier.loadMoreSessions,
                icon: const Icon(LucideIcons.chevronsDown, size: 14),
                label: Text(context.t.ai.session.loadMore),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

final class _ActiveSessionSummary extends StatelessWidget {
  const _ActiveSessionSummary({required this.session});

  final AcpSessionState session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: ConsoleShapes.decoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderColor: theme.dividerColor,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            session.title ?? context.t.ai.session.activeSession,
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          _TechnicalValue(icon: LucideIcons.hash, value: session.sessionId),
          const SizedBox(height: 3),
          _TechnicalValue(icon: LucideIcons.folder, value: session.cwd),
          if (session.updatedAt case final updatedAt?) ...[
            const SizedBox(height: 3),
            _TechnicalValue(icon: LucideIcons.clock3, value: updatedAt),
          ],
          if (session.additionalDirectories.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              context.t.ai.session.additionalDirectories(
                n: session.additionalDirectories.length,
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (session.mcpServers.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              context.t.ai.session.mcpServers(
                names: session.mcpServers
                    .map((server) => server.name)
                    .join(', '),
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

final class _RecentSessionRow extends ConsumerWidget {
  const _RecentSessionRow({
    required this.session,
    required this.active,
    required this.enabled,
    required this.canOpen,
    required this.canDelete,
    required this.preferResume,
  });

  final SessionInfo session;
  final bool active;
  final bool enabled;
  final bool canOpen;
  final bool canDelete;
  final bool preferResume;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifier = ref.read(acpAgentProvider.notifier);
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: InkWell(
        onTap: !enabled || active || !canOpen
            ? null
            : () => preferResume
                  ? notifier.resumeSession(session)
                  : notifier.loadSession(session),
        customBorder: ConsoleShapes.border(),
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 7, 4, 7),
          decoration: ConsoleShapes.decoration(
            color: active
                ? theme.colorScheme.primary.withValues(alpha: 0.08)
                : theme.colorScheme.surfaceContainerLow,
            borderColor: active
                ? theme.colorScheme.primary.withValues(alpha: 0.35)
                : theme.dividerColor,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.title ?? _shortSessionId(session.sessionId),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium,
                    ),
                    Text(
                      session.cwd,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (active)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 7),
                  child: _Tag(label: context.t.ai.session.active),
                )
              else if (canDelete)
                PopupMenuButton<String>(
                  enabled: enabled,
                  tooltip: context.t.ai.session.actions,
                  onSelected: (action) async {
                    if (action == 'load') {
                      await notifier.loadSession(session);
                    } else if (action == 'resume') {
                      await notifier.resumeSession(session);
                    } else if (action == 'delete' && context.mounted) {
                      final confirmed = await _confirmDelete(context, session);
                      if (confirmed) {
                        await notifier.deleteSession(session.sessionId);
                      }
                    }
                  },
                  itemBuilder: (context) => [
                    if (canOpen)
                      PopupMenuItem(
                        value: preferResume ? 'resume' : 'load',
                        child: Text(
                          preferResume
                              ? context.t.ai.session.resume
                              : context.t.ai.session.load,
                        ),
                      ),
                    if (canOpen && preferResume)
                      PopupMenuItem(
                        value: 'load',
                        child: Text(context.t.ai.session.loadHistory),
                      ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(context.t.ai.session.delete),
                    ),
                  ],
                  icon: const Icon(LucideIcons.ellipsis, size: 15),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _SessionSettings extends ConsumerWidget {
  const _SessionSettings({required this.connection, required this.session});

  final AcpConnected connection;
  final AcpSessionState session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(acpAgentProvider.notifier);
    final busy = connection.busy != null || connection.isPrompting;
    final modes = session.modes;
    return _Section(
      title: context.t.ai.session.settings,
      icon: LucideIcons.slidersHorizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (modes != null && modes.availableModes.isNotEmpty)
            ConsoleDropdownField<String>(
              label: context.t.ai.session.mode,
              initialValue: modes.currentModeId,
              items: [
                for (final mode in modes.availableModes)
                  DropdownMenuItem(value: mode.id, child: Text(mode.name)),
              ],
              onChanged: busy
                  ? null
                  : (value) {
                      if (value != null && value != modes.currentModeId) {
                        notifier.setMode(value);
                      }
                    },
              supportingText: _currentModeDescription(modes),
            ),
          for (final option in session.configOptions) ...[
            if (modes != null && modes.availableModes.isNotEmpty ||
                option != session.configOptions.first)
              const SizedBox(height: 10),
            _ConfigControl(option: option, enabled: !busy),
          ],
          if ((modes == null || modes.availableModes.isEmpty) &&
              session.configOptions.isEmpty)
            Text(
              context.t.ai.session.noSettings,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

final class _ConfigControl extends ConsumerWidget {
  const _ConfigControl({required this.option, required this.enabled});

  final SessionConfigOption option;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(acpAgentProvider.notifier);
    return switch (option) {
      SessionConfigBooleanOption(:final currentValue) => Material(
        type: MaterialType.transparency,
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(option.name),
          subtitle: option.description == null
              ? null
              : Text(option.description!),
          value: currentValue,
          onChanged: enabled
              ? (value) => notifier.setConfigOption(option.id, value)
              : null,
        ),
      ),
      SessionConfigSelectOptionValue(:final currentValue, :final options) =>
        ConsoleDropdownField<String>(
          label: option.name,
          initialValue: currentValue,
          items: _selectItems(options),
          onChanged: enabled
              ? (value) {
                  if (value != null && value != currentValue) {
                    notifier.setConfigOption(option.id, value);
                  }
                }
              : null,
          supportingText: option.description,
        ),
    };
  }
}

final class _SessionContext extends StatelessWidget {
  const _SessionContext({required this.session});

  final AcpSessionState session;

  @override
  Widget build(BuildContext context) {
    final plan = session.plan;
    final commands = session.availableCommands;
    final usage = session.usage;
    if (plan == null && commands.isEmpty && usage == null) {
      return const SizedBox.shrink();
    }
    return _Section(
      title: context.t.ai.session.currentContext,
      icon: LucideIcons.activity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (usage != null) _UsageView(usage: usage),
          if (usage != null && (plan != null || commands.isNotEmpty))
            const SizedBox(height: 12),
          if (plan != null) _PlanView(plan: plan),
          if (plan != null && commands.isNotEmpty) const SizedBox(height: 12),
          if (commands.isNotEmpty) _CommandsView(commands: commands),
        ],
      ),
    );
  }
}

final class _UsageView extends StatelessWidget {
  const _UsageView({required this.usage});

  final UsageUpdate usage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final used = usage.used;
    final size = usage.size;
    final progress = used != null && size != null && size > 0
        ? (used / size).clamp(0.0, 1.0)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.t.ai.session.usage, style: theme.textTheme.labelMedium),
        const SizedBox(height: 5),
        if (progress != null) ...[
          LinearProgressIndicator(value: progress, minHeight: 4),
          const SizedBox(height: 4),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (used != null)
              Text(
                context.t.ai.session.tokensUsed(n: used),
                style: theme.textTheme.bodySmall,
              ),
            if (size != null)
              Text(
                context.t.ai.session.tokenContext(n: size),
                style: theme.textTheme.bodySmall,
              ),
            if (usage.cost case final cost?)
              Text(
                '${cost.amount.toStringAsFixed(4)} ${cost.currency}',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ],
    );
  }
}

final class _PlanView extends StatelessWidget {
  const _PlanView({required this.plan});

  final Plan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.t.ai.session.plan, style: theme.textTheme.labelMedium),
        const SizedBox(height: 5),
        for (final entry in plan.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _planIcon(entry.status),
                  size: 13,
                  color: _planColor(theme.colorScheme, entry.status),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(entry.content, style: theme.textTheme.bodySmall),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

final class _CommandsView extends StatelessWidget {
  const _CommandsView({required this.commands});

  final List<AvailableCommand> commands;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t.ai.session.availableCommands,
          style: theme.textTheme.labelMedium,
        ),
        const SizedBox(height: 5),
        for (final command in commands)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
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
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

final class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 28,
          child: Row(
            children: [
              Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(child: Text(title, style: theme.textTheme.labelLarge)),
              ?trailing,
            ],
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

final class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: ConsoleShapes.decoration(
        color: theme.colorScheme.error.withValues(alpha: 0.07),
        borderColor: theme.colorScheme.error.withValues(alpha: 0.28),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.circleAlert,
            size: 14,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: SelectableText(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _AuthStatus extends StatelessWidget {
  const _AuthStatus({required this.status});

  final AcpAuthStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (status) {
      AcpAuthStatus.unavailable => (
        context.t.ai.session.authNotRequired,
        LucideIcons.circleCheck,
        Theme.of(context).colorScheme.primary,
      ),
      AcpAuthStatus.available => (
        context.t.ai.session.authAvailable,
        LucideIcons.keyRound,
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      AcpAuthStatus.required => (
        context.t.ai.session.authRequired,
        LucideIcons.lockKeyhole,
        Theme.of(context).colorScheme.error,
      ),
      AcpAuthStatus.authenticating => (
        context.t.ai.session.authWaiting,
        LucideIcons.loaderCircle,
        Theme.of(context).colorScheme.primary,
      ),
      AcpAuthStatus.authenticated => (
        context.t.ai.session.authenticated,
        LucideIcons.shieldCheck,
        Theme.of(context).colorScheme.primary,
      ),
      AcpAuthStatus.loggingOut => (
        context.t.ai.session.signingOut,
        LucideIcons.loaderCircle,
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    };
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}

final class _TechnicalValue extends StatelessWidget {
  const _TechnicalValue({required this.icon, required this.value});

  final IconData icon;
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
            size: 11,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: SelectableText(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              fontSize: 10,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

final class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: ConsoleShapes.decoration(
        color: theme.colorScheme.surfaceContainer,
        radius: ConsoleShapes.smallRadius,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: 10,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

List<String> _capabilityLabels(Translations t, AgentCapabilities capabilities) {
  final labels = <String>[];
  if (capabilities.promptCapabilities?.image == true) {
    labels.add(t.ai.session.capImages);
  }
  if (capabilities.promptCapabilities?.audio == true) {
    labels.add(t.ai.session.capAudio);
  }
  if (capabilities.promptCapabilities?.embeddedContext == true) {
    labels.add(t.ai.session.capContext);
  }
  if (capabilities.loadSession) labels.add(t.ai.session.capLoad);
  if (capabilities.sessionCapabilities?.resume != null) {
    labels.add(t.ai.session.capResume);
  }
  if (capabilities.sessionCapabilities?.list != null) {
    labels.add(t.ai.session.capHistory);
  }
  if (capabilities.mcpCapabilities?.http == true) labels.add('MCP HTTP');
  if (capabilities.mcpCapabilities?.sse == true) labels.add('MCP SSE');
  return labels;
}

String _authMethodName(AuthMethod method) {
  return switch (method) {
    AgentAuthMethod(:final agent) => agent.name,
  };
}

String? _authMethodDescription(List<AuthMethod> methods, String? id) {
  for (final method in methods) {
    if (method.id != id) continue;
    return switch (method) {
      AgentAuthMethod(:final agent) => agent.description,
    };
  }
  return null;
}

String? _currentModeDescription(SessionModeState modes) {
  for (final mode in modes.availableModes) {
    if (mode.id == modes.currentModeId) return mode.description;
  }
  return null;
}

List<DropdownMenuItem<String>> _selectItems(
  SessionConfigSelectOptions options,
) {
  return switch (options) {
    SessionConfigUngroupedOptions(:final options) => [
      for (final option in options)
        DropdownMenuItem(value: option.value, child: Text(option.name)),
    ],
    SessionConfigGroupedOptions(:final groups) => [
      for (final group in groups)
        for (final option in group.options)
          DropdownMenuItem(
            value: option.value,
            child: Text('${group.name} · ${option.name}'),
          ),
    ],
  };
}

IconData _planIcon(PlanEntryStatus status) => switch (status.toJson()) {
  'completed' => LucideIcons.circleCheck,
  'in_progress' => LucideIcons.loaderCircle,
  _ => LucideIcons.circle,
};

Color _planColor(ColorScheme colors, PlanEntryStatus status) {
  return switch (status.toJson()) {
    'completed' => colors.primary,
    'in_progress' => colors.tertiary,
    _ => colors.onSurfaceVariant,
  };
}

String _shortSessionId(String value) {
  if (value.length <= 18) return value;
  return '${value.substring(0, 8)}…${value.substring(value.length - 7)}';
}

Future<bool> _confirmDelete(BuildContext context, SessionInfo session) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.t.ai.session.deleteTitle),
          content: Text(
            context.t.ai.session.deleteDescription(
              name: session.title ?? _shortSessionId(session.sessionId),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.t.ai.session.keep),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              child: Text(context.t.ai.session.delete),
            ),
          ],
        ),
      ) ??
      false;
}
