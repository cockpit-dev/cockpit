import 'package:cockpit_console/i18n/strings.g.dart';
import 'package:cockpit_console/src/providers/core_providers.dart';
import 'package:cockpit_console/src/providers/data_providers.dart';
import 'package:cockpit_console/src/providers/session_monitor_provider.dart';
import 'package:cockpit_console/src/theme/console_colors.dart';
import 'package:cockpit_console/src/theme/console_shapes.dart';
import 'package:cockpit_console/src/ui/navigation/console_nav.dart';
import 'package:cockpit_console/src/ui/widgets/console_form_controls.dart';
import 'package:cockpit_console/src/ui/widgets/empty_state.dart';
import 'package:cockpit_console/src/ui/widgets/screen_scaffold.dart';
import 'package:cockpit/cockpit.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Apps and devices screen: discover, add, launch, and inspect live targets.
final class TargetsScreen extends HookConsumerWidget {
  const TargetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaceId = ref.watch(selectedWorkspaceIdProvider);
    final rawTargetsState = ref.watch(targetsProvider);
    final discovery = ref.watch(discoveredTargetsProvider);
    final discovering = useState(false);
    final targetsState = rawTargetsState.workspaceId == workspaceId
        ? rawTargetsState
        : TargetsState(workspaceId: workspaceId, loading: workspaceId != null);

    useEffect(() {
      var canceled = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final nextWorkspaceId = workspaceId;
        if (canceled || !context.mounted || nextWorkspaceId == null) return;
        ref.read(targetsProvider.notifier).refresh(nextWorkspaceId);
      });
      return () => canceled = true;
    }, [workspaceId]);

    if (workspaceId == null) {
      return ScreenScaffold(
        title: context.t.targets.title,
        subtitle: context.t.targets.subtitle,
        body: EmptyStateView(
          icon: LucideIcons.mousePointerClick,
          title: context.t.targets.selectProject,
          description: context.t.targets.selectProjectDescription,
          action: FilledButton.icon(
            onPressed: () => ref
                .read(navProvider.notifier)
                .go(ConsoleNavDestination.workspaces),
            icon: const Icon(LucideIcons.folderOpen, size: 14),
            label: Text(context.t.targets.chooseProject),
          ),
        ),
      );
    }

    Future<void> doDiscover() async {
      discovering.value = true;
      try {
        await ref.read(targetsProvider.notifier).discover();
      } on Object catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.t.targets.discoverFailed(error: e.toString()),
              ),
            ),
          );
        }
      } finally {
        discovering.value = false;
      }
    }

    final targets = targetsState.items;

    return ScreenScaffold(
      title: context.t.targets.title,
      subtitle: context.t.targets.subtitle,
      stackActionsBelowWidth: 420,
      actions: [
        OutlinedButton.icon(
          onPressed: discovering.value ? null : doDiscover,
          icon: discovering.value
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.search, size: 14),
          label: Text(context.t.targets.find),
        ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionLabel(
                  label: context.t.targets.readyToUse,
                  count: targets.length,
                ),
                const SizedBox(height: 8),
                if (targetsState.error != null && targets.isEmpty)
                  _ErrorBox(message: targetsState.error!)
                else if (targetsState.loading && targets.isEmpty)
                  const _LoadingBox()
                else if (targets.isEmpty)
                  _EmptyBox(
                    icon: LucideIcons.smartphone,
                    title: context.t.targets.noneAdded,
                    description: context.t.targets.noneAddedDescription,
                  )
                else
                  _TargetList(targets: targets),
                const SizedBox(height: 32),
                if (discovery != null) ...[
                  _SectionLabel(
                    label: context.t.targets.availableToAdd,
                    count: discovery.targets.length,
                  ),
                  const SizedBox(height: 8),
                  if (discovery.targets.isEmpty)
                    _EmptyBox(
                      icon: LucideIcons.searchX,
                      title: context.t.targets.noneFound,
                      description: context.t.targets.noneFoundDescription,
                    )
                  else
                    _DiscoveryList(
                      targets: discovery.targets,
                      workspaceId: workspaceId,
                      onRegistered: () => ref
                          .read(targetsProvider.notifier)
                          .refresh(workspaceId),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(label, style: theme.textTheme.titleSmall?.copyWith(fontSize: 13)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: ConsoleShapes.decoration(
            color: theme.colorScheme.surfaceContainer,
            radius: 6,
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

final class _LoadingBox extends StatelessWidget {
  const _LoadingBox();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 120,
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}

final class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 120,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: ConsoleShapes.decoration(
        color: theme.colorScheme.error.withValues(alpha: 0.06),
        borderColor: theme.colorScheme.error.withValues(alpha: 0.3),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.alertCircle,
              size: 20,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 8),
            Text(
              context.t.targets.loadFailed,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              message,
              style: theme.textTheme.labelSmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

final class _EmptyBox extends StatelessWidget {
  const _EmptyBox({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 120,
      decoration: ConsoleShapes.decoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderColor: theme.dividerColor,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(title, style: theme.textTheme.labelMedium),
            const SizedBox(height: 2),
            Text(description, style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

final class _TargetList extends StatelessWidget {
  const _TargetList({required this.targets});

  final List<CockpitAutomationTargetResource> targets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: ConsoleShapes.decoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderColor: theme.dividerColor,
      ),
      child: Column(
        children: [
          for (var i = 0; i < targets.length; i++) ...[
            if (i > 0) Divider(height: 1, color: theme.dividerColor),
            _RegisteredTargetTile(item: targets[i]),
          ],
        ],
      ),
    );
  }
}

final class _RegisteredTargetTile extends HookConsumerWidget {
  const _RegisteredTargetTile({required this.item});

  final CockpitAutomationTargetResource item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final workspaceId = ref.watch(selectedWorkspaceIdProvider);

    final active = item.sessionId != null;
    final status = active ? context.t.targets.running : context.t.targets.ready;
    final statusColor = active
        ? context.consoleColors.success
        : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(
            _platformIcon(item.platform),
            size: 16,
            color: theme.colorScheme.onSurface,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              container: true,
              label: context.t.targets.appSemantics(
                name: _targetTitle(context.t, item),
              ),
              value: status,
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _targetTitle(context.t, item),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _targetSummary(context.t, item),
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: ConsoleShapes.decoration(
              color: statusColor.withValues(alpha: 0.1),
              radius: 6,
            ),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (workspaceId != null && active)
            SizedBox(
              width: 30,
              height: 30,
              child: IconButton(
                onPressed: () async {
                  final monitor = ref.read(sessionMonitorProvider.notifier);
                  var selected = monitor.selectTarget(
                    workspaceId: workspaceId,
                    targetId: item.targetId,
                  );
                  if (!selected) {
                    await monitor.refresh();
                    selected = monitor.selectTarget(
                      workspaceId: workspaceId,
                      targetId: item.targetId,
                    );
                  }
                  if (!context.mounted) return;
                  if (!selected) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.t.targets.sessionUnavailable),
                      ),
                    );
                    return;
                  }
                  ref
                      .read(navProvider.notifier)
                      .go(ConsoleNavDestination.sessions);
                },
                icon: const Icon(LucideIcons.radio, size: 13),
                tooltip: context.t.targets.monitorSession,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              ),
            ),
          if (workspaceId != null && !active)
            SizedBox(
              width: 30,
              height: 30,
              child: IconButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      _LaunchTargetDialog(workspaceId: workspaceId, item: item),
                ),
                icon: const Icon(LucideIcons.play, size: 13),
                tooltip: context.t.targets.start,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              ),
            ),
        ],
      ),
    );
  }

  IconData _platformIcon(String platform) {
    return switch (platform) {
      'android' => LucideIcons.smartphone,
      'ios' => LucideIcons.smartphone,
      'macos' => LucideIcons.laptop,
      'linux' => LucideIcons.terminal,
      'windows' => LucideIcons.monitor,
      'web' => LucideIcons.globe,
      _ => LucideIcons.cpu,
    };
  }
}

final class _DiscoveryList extends StatelessWidget {
  const _DiscoveryList({
    required this.targets,
    required this.workspaceId,
    required this.onRegistered,
  });

  final List<CockpitDiscoveredTarget> targets;
  final String workspaceId;
  final VoidCallback onRegistered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: ConsoleShapes.decoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderColor: theme.dividerColor,
      ),
      child: Column(
        children: [
          for (var i = 0; i < targets.length; i++) ...[
            if (i > 0) Divider(height: 1, color: theme.dividerColor),
            _DiscoveredTargetTile(
              target: targets[i],
              workspaceId: workspaceId,
              onRegistered: onRegistered,
            ),
          ],
        ],
      ),
    );
  }
}

final class _DiscoveredTargetTile extends HookConsumerWidget {
  const _DiscoveredTargetTile({
    required this.target,
    required this.workspaceId,
    required this.onRegistered,
  });

  final CockpitDiscoveredTarget target;
  final String workspaceId;
  final VoidCallback onRegistered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(
            _platformIcon(target.platform),
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  target.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${target.platform}'
                  '${target.sdk != null ? ' ${target.sdk}' : ''}'
                  '${target.emulator ? ' (emulator)' : ''}',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 30,
            height: 30,
            child: IconButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _RegisterTargetDialog(
                  workspaceId: workspaceId,
                  target: target,
                  onRegistered: onRegistered,
                ),
              ),
              icon: const Icon(LucideIcons.plus, size: 13),
              tooltip: context.t.targets.addNamed(name: target.name),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            ),
          ),
        ],
      ),
    );
  }

  IconData _platformIcon(String platform) {
    return switch (platform) {
      'android' => LucideIcons.smartphone,
      'ios' => LucideIcons.smartphone,
      'macos' => LucideIcons.laptop,
      'linux' => LucideIcons.terminal,
      'windows' => LucideIcons.monitor,
      'web' => LucideIcons.globe,
      _ => LucideIcons.cpu,
    };
  }
}

String _targetKindLabel(Translations t, CockpitTargetKind kind) =>
    switch (kind) {
      CockpitTargetKind.flutterApp => t.targets.kind.flutterApp,
      CockpitTargetKind.nativeApp => t.targets.kind.nativeApp,
      CockpitTargetKind.desktopApp => t.targets.kind.desktopApp,
      CockpitTargetKind.browserPage => t.targets.kind.browserPage,
      CockpitTargetKind.systemSurface => t.targets.kind.systemSurface,
      CockpitTargetKind.device => t.targets.kind.device,
      CockpitTargetKind.hostWorkspace => t.targets.kind.hostWorkspace,
    };

String _appModeLabel(Translations t, CockpitAppMode mode) => switch (mode) {
  CockpitAppMode.development => t.targets.mode.development,
  CockpitAppMode.automation => t.targets.mode.automation,
};

String _targetSummary(Translations t, CockpitAutomationTargetResource item) {
  final parts = <String>[
    _platformLabel(item.platform),
    _environmentLabel(t, item.environment),
    if (item.flavor != null) item.flavor!,
    if (item.appId != null) item.appId!,
    item.targetId,
  ];
  return parts.join(' · ');
}

String _targetTitle(Translations t, CockpitAutomationTargetResource item) {
  final kind = _targetKindLabel(t, item.targetKind);
  final detail = switch (item.entrypoint) {
    final entrypoint? => _compactPath(entrypoint),
    null => item.appId ?? item.deviceId,
  };
  return '$kind · $detail';
}

String _compactPath(String value) {
  final parts = value.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.length < 2) return value;
  return parts.sublist(parts.length - 2).join('/');
}

String _platformLabel(String platform) => switch (platform) {
  'android' => 'Android',
  'ios' => 'iOS',
  'macos' => 'macOS',
  'linux' => 'Linux',
  'windows' => 'Windows',
  'web' => 'Web',
  _ => platform,
};

String _environmentLabel(
  Translations t,
  CockpitAutomationTargetEnvironment environment,
) => switch (environment) {
  CockpitAutomationTargetEnvironment.development =>
    t.targets.environment.development,
  CockpitAutomationTargetEnvironment.test => t.targets.environment.test,
  CockpitAutomationTargetEnvironment.staging => t.targets.environment.staging,
  CockpitAutomationTargetEnvironment.production =>
    t.targets.environment.production,
  CockpitAutomationTargetEnvironment.unknown => t.targets.environment.unknown,
};

String _testEnvironmentLabel(
  Translations t,
  CockpitTestTargetEnvironment environment,
) => switch (environment) {
  CockpitTestTargetEnvironment.development => t.targets.environment.development,
  CockpitTestTargetEnvironment.test => t.targets.environment.test,
  CockpitTestTargetEnvironment.staging => t.targets.environment.staging,
  CockpitTestTargetEnvironment.production => t.targets.environment.production,
  CockpitTestTargetEnvironment.unknown => t.targets.environment.unknown,
};

List<String> _parseLines(String text) => text
    .split(RegExp(r'\r?\n'))
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .toList(growable: false);

Map<String, String> _parseKeyValueLines(Translations t, String text) {
  final result = <String, String>{};
  for (final line in _parseLines(text)) {
    final equals = line.indexOf('=');
    if (equals <= 0) {
      throw FormatException(t.targets.keyValueSyntaxError(line: line));
    }
    result[line.substring(0, equals).trim()] = line
        .substring(equals + 1)
        .trim();
  }
  return result;
}

CockpitFlutterLaunchConfiguration _buildLaunchConfiguration({
  required Translations t,
  required String dartDefines,
  required String dartDefineFromFiles,
  required String flutterArgs,
  required String environment,
}) {
  final defines = _parseLines(dartDefines);
  final files = _parseLines(dartDefineFromFiles);
  final args = _parseLines(flutterArgs);
  final env = _parseKeyValueLines(t, environment);
  if (defines.isEmpty && files.isEmpty && args.isEmpty && env.isEmpty) {
    return CockpitFlutterLaunchConfiguration.empty;
  }
  return CockpitFlutterLaunchConfiguration(
    dartDefines: defines,
    dartDefineFromFiles: files,
    flutterArgs: args,
    environment: env,
  );
}

Widget _infoRow(BuildContext context, String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: DefaultTextStyle.of(context).style.copyWith(fontSize: 12),
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ],
      ),
    ),
  );
}

Widget _infoNote(BuildContext context, String message) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        LucideIcons.info,
        size: 14,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          message,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ],
  );
}

final class _RegisterTargetDialog extends HookConsumerWidget {
  const _RegisterTargetDialog({
    required this.workspaceId,
    required this.target,
    required this.onRegistered,
  });

  final String workspaceId;
  final CockpitDiscoveredTarget target;
  final VoidCallback onRegistered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(
      sourceDocumentsForWorkspaceProvider(workspaceId),
    );
    final kind = useState(CockpitTargetKind.flutterApp);
    final environment = useState(CockpitTestTargetEnvironment.development);
    final mode = useState(CockpitAppMode.development);
    final entrypointDocId = useState<String?>(null);
    final appIdCtrl = useTextEditingController();
    final appIdEmpty = useState(true);
    final flavorCtrl = useTextEditingController();
    final wdaUrlCtrl = useTextEditingController();
    final submitting = useState(false);
    final formError = useState<String?>(null);

    final requiresAppId = targetKindRequiresAppId(kind.value);

    final docs = docsAsync.maybeWhen(
      data: (documents) => documents,
      orElse: () => const <CockpitDocumentResource>[],
    );

    Future<void> submit() async {
      if (requiresAppId && appIdEmpty.value) {
        formError.value = context.t.targets.appIdRequired(
          kind: _targetKindLabel(context.t, kind.value),
        );
        return;
      }
      formError.value = null;
      submitting.value = true;
      try {
        await ref
            .read(targetsProvider.notifier)
            .register(
              workspaceId: workspaceId,
              platform: target.platform,
              deviceId: target.id,
              targetKind: kind.value,
              environment: environment.value,
              mode: mode.value,
              appId: appIdEmpty.value ? null : appIdCtrl.text.trim(),
              entrypointDocumentId: entrypointDocId.value,
              flavor: flavorCtrl.text,
              wdaUrl: wdaUrlCtrl.text,
              idempotencyKey:
                  'register-${target.platform}-${target.id}-${kind.value.name}-'
                  '${DateTime.now().millisecondsSinceEpoch}',
            );
        if (context.mounted) {
          Navigator.of(context).pop();
          onRegistered();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t.targets.added(name: target.name))),
          );
        }
      } on Object catch (error) {
        formError.value = '$error';
      } finally {
        submitting.value = false;
      }
    }

    return AlertDialog(
      title: Text(context.t.targets.addTitle),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow(context, context.t.targets.device, target.name),
              _infoRow(context, context.t.targets.platform, target.platform),
              _infoRow(context, context.t.targets.deviceId, target.id),
              const SizedBox(height: 12),
              ConsoleDropdownField<CockpitTargetKind>(
                initialValue: kind.value,
                label: context.t.targets.type,
                items: [
                  for (final candidate in CockpitTargetKind.values)
                    DropdownMenuItem(
                      value: candidate,
                      child: Text(_targetKindLabel(context.t, candidate)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) kind.value = value;
                },
              ),
              const SizedBox(height: 12),
              ConsoleDropdownField<String?>(
                initialValue: entrypointDocId.value,
                label: context.t.targets.launchFile,
                hintText: context.t.targets.optional,
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(context.t.targets.none),
                  ),
                  for (final document in docs)
                    DropdownMenuItem<String?>(
                      value: document.documentId,
                      child: Text(
                        document.relativePath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => entrypointDocId.value = value,
              ),
              const SizedBox(height: 12),
              ConsoleTextField(
                controller: appIdCtrl,
                onChanged: (value) => appIdEmpty.value = value.trim().isEmpty,
                label: context.t.targets.appIdentifier,
                hint: requiresAppId
                    ? context.t.targets.required
                    : context.t.targets.optional,
              ),
              const SizedBox(height: 12),
              ConsoleTextField(
                controller: flavorCtrl,
                label: context.t.targets.flavor,
                hint: context.t.targets.optional,
              ),
              const SizedBox(height: 12),
              ConsoleTextField(
                controller: wdaUrlCtrl,
                label: 'WDA URL',
                hint: context.t.targets.optionalIos,
              ),
              const SizedBox(height: 12),
              ConsoleDropdownField<CockpitTestTargetEnvironment>(
                initialValue: environment.value,
                label: context.t.targets.environmentLabel,
                items: [
                  for (final candidate in CockpitTestTargetEnvironment.values)
                    DropdownMenuItem(
                      value: candidate,
                      child: Text(_testEnvironmentLabel(context.t, candidate)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) environment.value = value;
                },
              ),
              const SizedBox(height: 12),
              ConsoleDropdownField<CockpitAppMode>(
                initialValue: mode.value,
                label: context.t.targets.modeLabel,
                items: [
                  for (final candidate in CockpitAppMode.values)
                    DropdownMenuItem(
                      value: candidate,
                      child: Text(_appModeLabel(context.t, candidate)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) mode.value = value;
                },
              ),
              if (formError.value != null) ...[
                const SizedBox(height: 12),
                Text(
                  formError.value!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: submitting.value
              ? null
              : () => Navigator.of(context).pop(),
          child: Text(context.t.common.cancel),
        ),
        FilledButton(
          onPressed: (submitting.value || (requiresAppId && appIdEmpty.value))
              ? null
              : submit,
          child: submitting.value
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(context.t.targets.add),
        ),
      ],
    );
  }
}

final class _LaunchTargetDialog extends HookConsumerWidget {
  const _LaunchTargetDialog({required this.workspaceId, required this.item});

  final String workspaceId;
  final CockpitAutomationTargetResource item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mirrors CockpitWorkerTargetRegistration.usesSystemControl: any non-
    // Flutter kind, or a Flutter kind resolved by app id rather than an
    // entrypoint document, is activated via system control and rejects an
    // explicit launch mode and Flutter configuration.
    final usesSystemControl =
        item.targetKind != CockpitTargetKind.flutterApp ||
        (item.entrypoint == null && item.appId != null);
    final registeredMode = CockpitAppMode.values.firstWhere(
      (mode) => mode.jsonValue == item.mode.name,
      orElse: () => CockpitAppMode.development,
    );
    final mode = useState<CockpitAppMode>(registeredMode);
    final timeoutCtrl = useTextEditingController();
    final dartDefinesCtrl = useTextEditingController();
    final dartDefineFilesCtrl = useTextEditingController();
    final flutterArgsCtrl = useTextEditingController();
    final environmentCtrl = useTextEditingController();
    final submitting = useState(false);
    final formError = useState<String?>(null);

    Future<void> submit() async {
      final timeoutText = timeoutCtrl.text.trim();
      final timeoutMs = int.tryParse(timeoutText);
      if (timeoutText.isNotEmpty && timeoutMs == null) {
        formError.value = context.t.targets.timeoutIntegerError;
        return;
      }
      if (timeoutMs != null && (timeoutMs < 1000 || timeoutMs > 1800000)) {
        formError.value = context.t.targets.timeoutRangeError;
        return;
      }
      CockpitFlutterLaunchConfiguration? launchConfiguration;
      if (!usesSystemControl) {
        try {
          launchConfiguration = _buildLaunchConfiguration(
            t: context.t,
            dartDefines: dartDefinesCtrl.text,
            dartDefineFromFiles: dartDefineFilesCtrl.text,
            flutterArgs: flutterArgsCtrl.text,
            environment: environmentCtrl.text,
          );
        } on FormatException catch (error) {
          formError.value = error.message;
          return;
        } on ArgumentError catch (error) {
          formError.value = error.message;
          return;
        }
      }
      formError.value = null;
      submitting.value = true;
      try {
        await ref
            .read(targetsProvider.notifier)
            .launch(
              workspaceId: workspaceId,
              targetId: item.targetId,
              mode: usesSystemControl ? null : mode.value,
              launchTimeoutMs: timeoutMs,
              launchConfiguration: launchConfiguration,
              idempotencyKey:
                  'launch-${item.targetId}-${DateTime.now().millisecondsSinceEpoch}',
            );
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.t.targets.launched(target: item.targetId)),
            ),
          );
        }
      } on Object catch (error) {
        formError.value = '$error';
      } finally {
        submitting.value = false;
      }
    }

    return AlertDialog(
      title: Text(
        context.t.targets.launchTitle(
          kind: _targetKindLabel(context.t, item.targetKind),
        ),
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow(context, context.t.targets.target, item.targetId),
              _infoRow(context, context.t.targets.platform, item.platform),
              _infoRow(context, context.t.targets.device, item.deviceId),
              const SizedBox(height: 12),
              if (usesSystemControl) ...[
                _infoNote(context, context.t.targets.systemControlNote),
                const SizedBox(height: 12),
              ] else ...[
                ConsoleDropdownField<CockpitAppMode>(
                  initialValue: mode.value,
                  label: context.t.targets.modeLabel,
                  items: [
                    for (final candidate in CockpitAppMode.values)
                      DropdownMenuItem(
                        value: candidate,
                        child: Text(_appModeLabel(context.t, candidate)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) mode.value = value;
                  },
                ),
                const SizedBox(height: 12),
              ],
              ConsoleTextField(
                controller: timeoutCtrl,
                keyboardType: TextInputType.number,
                label: context.t.targets.launchTimeout,
                hint: context.t.targets.launchTimeoutDefault,
              ),
              if (!usesSystemControl) ...[
                const SizedBox(height: 16),
                Text(
                  context.t.targets.launchConfiguration,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                ConsoleTextArea(
                  controller: dartDefinesCtrl,
                  minLines: 3,
                  maxLines: 3,
                  label: context.t.targets.dartDefines,
                  hint: context.t.targets.keyValueLines,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(height: 8),
                ConsoleTextArea(
                  controller: dartDefineFilesCtrl,
                  minLines: 2,
                  maxLines: 2,
                  label: context.t.targets.dartDefineFiles,
                  hint: context.t.targets.fileLines,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(height: 8),
                ConsoleTextArea(
                  controller: flutterArgsCtrl,
                  minLines: 2,
                  maxLines: 2,
                  label: context.t.targets.flutterArgs,
                  hint: context.t.targets.flutterArgsLines,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(height: 8),
                ConsoleTextArea(
                  controller: environmentCtrl,
                  minLines: 2,
                  maxLines: 2,
                  label: context.t.targets.environmentLabel,
                  hint: context.t.targets.keyValueLines,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
              if (formError.value != null) ...[
                const SizedBox(height: 12),
                Text(
                  formError.value!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: submitting.value
              ? null
              : () => Navigator.of(context).pop(),
          child: Text(context.t.common.cancel),
        ),
        FilledButton(
          onPressed: submitting.value ? null : submit,
          child: submitting.value
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(context.t.targets.launch),
        ),
      ],
    );
  }
}
