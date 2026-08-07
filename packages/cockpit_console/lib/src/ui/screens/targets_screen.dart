import 'package:cockpit_console/src/providers/core_providers.dart';
import 'package:cockpit_console/src/providers/data_providers.dart';
import 'package:cockpit_console/src/theme/console_colors.dart';
import 'package:cockpit_console/src/theme/console_shapes.dart';
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
      return const ScreenScaffold(
        title: 'Apps & devices',
        subtitle: 'Find and connect the apps and devices used by this project',
        body: EmptyStateView(
          icon: LucideIcons.mousePointerClick,
          title: 'Select a project',
          description:
              'Choose a project from the Projects page to view its apps and devices.',
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
            SnackBar(content: Text("Couldn't find apps & devices: $e")),
          );
        }
      } finally {
        discovering.value = false;
      }
    }

    final targets = targetsState.items;

    return ScreenScaffold(
      title: 'Apps & devices',
      subtitle: 'Find and connect the apps and devices used by this project',
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
          label: const Text('Find apps & devices'),
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
                _SectionLabel(label: 'Ready to use', count: targets.length),
                const SizedBox(height: 8),
                if (targetsState.error != null && targets.isEmpty)
                  _ErrorBox(message: targetsState.error!)
                else if (targetsState.loading && targets.isEmpty)
                  const _LoadingBox()
                else if (targets.isEmpty)
                  const _EmptyBox(
                    icon: LucideIcons.smartphone,
                    title: 'No apps or devices added',
                    description:
                        'Find available apps and devices, then add the one you need.',
                  )
                else
                  _TargetList(targets: targets),
                const SizedBox(height: 32),
                if (discovery != null) ...[
                  _SectionLabel(
                    label: 'Available to add',
                    count: discovery.targets.length,
                  ),
                  const SizedBox(height: 8),
                  if (discovery.targets.isEmpty)
                    const _EmptyBox(
                      icon: LucideIcons.searchX,
                      title: 'No apps or devices found',
                      description:
                          'Connect or start a device, then try finding again.',
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
              "Couldn't load apps & devices",
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
    final status = active ? 'Running' : 'Ready';
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _targetTitle(item),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  _targetSummary(item),
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
                tooltip: 'Start app or device',
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
              tooltip: 'Add ${target.name}',
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

String _targetKindLabel(CockpitTargetKind kind) => switch (kind) {
  CockpitTargetKind.flutterApp => 'Flutter app',
  CockpitTargetKind.nativeApp => 'Native app',
  CockpitTargetKind.desktopApp => 'Desktop app',
  CockpitTargetKind.browserPage => 'Browser page',
  CockpitTargetKind.systemSurface => 'System surface',
  CockpitTargetKind.device => 'Device',
  CockpitTargetKind.hostWorkspace => 'Host workspace',
};

String _appModeLabel(CockpitAppMode mode) => switch (mode) {
  CockpitAppMode.development => 'Development',
  CockpitAppMode.automation => 'Automation',
};

String _targetSummary(CockpitAutomationTargetResource item) {
  final parts = <String>[
    _platformLabel(item.platform),
    _environmentLabel(item.environment),
    if (item.flavor != null) item.flavor!,
    if (item.appId != null) item.appId!,
    item.targetId,
  ];
  return parts.join(' · ');
}

String _targetTitle(CockpitAutomationTargetResource item) {
  final kind = _targetKindLabel(item.targetKind);
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

String _environmentLabel(CockpitAutomationTargetEnvironment environment) =>
    switch (environment) {
      CockpitAutomationTargetEnvironment.development => 'Development',
      CockpitAutomationTargetEnvironment.test => 'Test',
      CockpitAutomationTargetEnvironment.staging => 'Staging',
      CockpitAutomationTargetEnvironment.production => 'Production',
      CockpitAutomationTargetEnvironment.unknown => 'Unknown',
    };

List<String> _parseLines(String text) => text
    .split(RegExp(r'\r?\n'))
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .toList(growable: false);

Map<String, String> _parseKeyValueLines(String text) {
  final result = <String, String>{};
  for (final line in _parseLines(text)) {
    final equals = line.indexOf('=');
    if (equals <= 0) {
      throw FormatException('Entries must use KEY=VALUE syntax: "$line".');
    }
    result[line.substring(0, equals).trim()] = line
        .substring(equals + 1)
        .trim();
  }
  return result;
}

CockpitFlutterLaunchConfiguration _buildLaunchConfiguration({
  required String dartDefines,
  required String dartDefineFromFiles,
  required String flutterArgs,
  required String environment,
}) {
  final defines = _parseLines(dartDefines);
  final files = _parseLines(dartDefineFromFiles);
  final args = _parseLines(flutterArgs);
  final env = _parseKeyValueLines(environment);
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
        formError.value =
            '${_targetKindLabel(kind.value)} targets require '
            'an app ID.';
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Added ${target.name}')));
        }
      } on Object catch (error) {
        formError.value = '$error';
      } finally {
        submitting.value = false;
      }
    }

    return AlertDialog(
      title: const Text('Add app or device'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow(context, 'Device', target.name),
              _infoRow(context, 'Platform', target.platform),
              _infoRow(context, 'Device ID', target.id),
              const SizedBox(height: 12),
              ConsoleDropdownField<CockpitTargetKind>(
                initialValue: kind.value,
                label: 'Type',
                items: [
                  for (final candidate in CockpitTargetKind.values)
                    DropdownMenuItem(
                      value: candidate,
                      child: Text(_targetKindLabel(candidate)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) kind.value = value;
                },
              ),
              const SizedBox(height: 12),
              ConsoleDropdownField<String?>(
                initialValue: entrypointDocId.value,
                label: 'Launch file',
                hintText: 'Optional',
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('None'),
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
                label: 'App identifier',
                hint: requiresAppId ? 'Required' : 'Optional',
              ),
              const SizedBox(height: 12),
              ConsoleTextField(
                controller: flavorCtrl,
                label: 'Flavor',
                hint: 'Optional',
              ),
              const SizedBox(height: 12),
              ConsoleTextField(
                controller: wdaUrlCtrl,
                label: 'WDA URL',
                hint: 'Optional (iOS)',
              ),
              const SizedBox(height: 12),
              ConsoleDropdownField<CockpitTestTargetEnvironment>(
                initialValue: environment.value,
                label: 'Environment',
                items: [
                  for (final candidate in CockpitTestTargetEnvironment.values)
                    DropdownMenuItem(
                      value: candidate,
                      child: Text(candidate.name),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) environment.value = value;
                },
              ),
              const SizedBox(height: 12),
              ConsoleDropdownField<CockpitAppMode>(
                initialValue: mode.value,
                label: 'Mode',
                items: [
                  for (final candidate in CockpitAppMode.values)
                    DropdownMenuItem(
                      value: candidate,
                      child: Text(_appModeLabel(candidate)),
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
          child: const Text('Cancel'),
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
              : const Text('Add'),
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
        formError.value =
            'Launch timeout must be an integer number of milliseconds.';
        return;
      }
      if (timeoutMs != null && (timeoutMs < 1000 || timeoutMs > 1800000)) {
        formError.value =
            'Launch timeout must be between 1,000 and 1,800,000 ms.';
        return;
      }
      CockpitFlutterLaunchConfiguration? launchConfiguration;
      if (!usesSystemControl) {
        try {
          launchConfiguration = _buildLaunchConfiguration(
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Launched ${item.targetId}')));
        }
      } on Object catch (error) {
        formError.value = '$error';
      } finally {
        submitting.value = false;
      }
    }

    return AlertDialog(
      title: Text('Launch ${_targetKindLabel(item.targetKind)}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow(context, 'Target', item.targetId),
              _infoRow(context, 'Platform', item.platform),
              _infoRow(context, 'Device', item.deviceId),
              const SizedBox(height: 12),
              if (usesSystemControl) ...[
                _infoNote(
                  context,
                  'This target is activated via system control. A launch mode '
                  'and Flutter configuration are not accepted.',
                ),
                const SizedBox(height: 12),
              ] else ...[
                ConsoleDropdownField<CockpitAppMode>(
                  initialValue: mode.value,
                  label: 'Mode',
                  items: [
                    for (final candidate in CockpitAppMode.values)
                      DropdownMenuItem(
                        value: candidate,
                        child: Text(_appModeLabel(candidate)),
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
                label: 'Launch timeout (ms)',
                hint: 'Default (600,000)',
              ),
              if (!usesSystemControl) ...[
                const SizedBox(height: 16),
                Text(
                  'Launch configuration',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                ConsoleTextArea(
                  controller: dartDefinesCtrl,
                  minLines: 3,
                  maxLines: 3,
                  label: 'Dart defines',
                  hint: 'KEY=VALUE, one per line',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(height: 8),
                ConsoleTextArea(
                  controller: dartDefineFilesCtrl,
                  minLines: 2,
                  maxLines: 2,
                  label: 'Dart define files',
                  hint: 'config/*.json, one per line',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(height: 8),
                ConsoleTextArea(
                  controller: flutterArgsCtrl,
                  minLines: 2,
                  maxLines: 2,
                  label: 'Flutter args',
                  hint: '--verbose, one per line',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(height: 8),
                ConsoleTextArea(
                  controller: environmentCtrl,
                  minLines: 2,
                  maxLines: 2,
                  label: 'Environment',
                  hint: 'KEY=VALUE, one per line',
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
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: submitting.value ? null : submit,
          child: submitting.value
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Launch'),
        ),
      ],
    );
  }
}
