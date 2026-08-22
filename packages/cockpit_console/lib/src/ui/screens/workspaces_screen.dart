import 'dart:async';

import 'package:cockpit_console/i18n/strings.g.dart';
import 'package:cockpit_console/src/providers/core_providers.dart';
import 'package:cockpit_console/src/providers/data_providers.dart';
import 'package:cockpit_console/src/theme/console_colors.dart';
import 'package:cockpit_console/src/theme/console_shapes.dart';
import 'package:cockpit_console/src/ui/widgets/console_form_controls.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit_console/src/ui/widgets/empty_state.dart';
import 'package:cockpit_console/src/ui/widgets/screen_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;

/// Projects screen: manage allowed folders and registered project directories.
///
/// Shows two sections: roots (top-level project directories registered with
/// Supervisor) and workspaces (individual checkouts within roots). Supports
/// registering and removing both via dialogs.
final class WorkspacesScreen extends HookConsumerWidget {
  const WorkspacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roots = ref.watch(rootsProvider);
    final workspaces = ref.watch(workspacesProvider);
    final showRemoved = useState(false);
    final activeRoots = roots.items
        .where((item) => item.state != CockpitRootState.retired)
        .toList(growable: false);
    final removedRoots = roots.items
        .where((item) => item.state == CockpitRootState.retired)
        .toList(growable: false);
    final activeWorkspaces = workspaces.items
        .where((item) => item.state != CockpitWorkspaceState.retired)
        .toList(growable: false);
    final removedWorkspaces = workspaces.items
        .where((item) => item.state == CockpitWorkspaceState.retired)
        .toList(growable: false);
    final removedCount = removedRoots.length + removedWorkspaces.length;

    // The provider owns connection single-flight and surfaces failures. Loading
    // unconditionally avoids a mount-before-connect race that otherwise leaves
    // this screen empty until a manual refresh.
    useEffect(() {
      var canceled = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (canceled || !context.mounted) return;
        unawaited(
          Future.wait([
            ref.read(rootsProvider.notifier).refresh(),
            ref.read(workspacesProvider.notifier).refresh(),
          ]),
        );
      });
      return () => canceled = true;
    }, []);

    return ScreenScaffold(
      title: context.t.projects.title,
      subtitle: context.t.projects.subtitle,
      stackActionsBelowWidth: 420,
      actions: [
        IconButton(
          icon: const Icon(LucideIcons.refreshCw, size: 16),
          tooltip: context.t.common.refresh,
          onPressed: () {
            ref.read(rootsProvider.notifier).refresh();
            ref.read(workspacesProvider.notifier).refresh();
          },
        ),
        const SizedBox(width: 4),
        FilledButton.icon(
          onPressed: () => _showRegisterWorkspaceDialog(context, ref),
          icon: const Icon(LucideIcons.plus, size: 14),
          label: Text(context.t.projects.addProject),
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
                _SectionHeader(
                  title: context.t.projects.allowedFolders,
                  count: activeRoots.length,
                  actionLabel: context.t.projects.addFolder,
                  onAdd: () => _showRegisterRootDialog(context, ref),
                ),
                const SizedBox(height: 8),
                _RootsList(state: roots, items: activeRoots),
                const SizedBox(height: 32),
                _SectionHeader(
                  title: context.t.projects.title,
                  count: activeWorkspaces.length,
                ),
                const SizedBox(height: 8),
                _WorkspacesList(state: workspaces, items: activeWorkspaces),
                if (removedCount > 0) ...[
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () => showRemoved.value = !showRemoved.value,
                    icon: Icon(
                      showRemoved.value
                          ? LucideIcons.chevronUp
                          : LucideIcons.history,
                      size: 14,
                    ),
                    label: Text(
                      showRemoved.value
                          ? context.t.projects.hideRemovedHistory
                          : context.t.projects.showRemovedHistory(
                              count: removedCount,
                            ),
                    ),
                  ),
                ],
                if (showRemoved.value) ...[
                  if (removedRoots.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _SectionHeader(
                      title: context.t.projects.removedFolders,
                      count: removedRoots.length,
                    ),
                    const SizedBox(height: 8),
                    _RootsList(state: roots, items: removedRoots),
                  ],
                  if (removedWorkspaces.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _SectionHeader(
                      title: context.t.projects.removedProjects,
                      count: removedWorkspaces.length,
                    ),
                    const SizedBox(height: 8),
                    _WorkspacesList(
                      state: workspaces,
                      items: removedWorkspaces,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showRegisterRootDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (_) => const _RegisterRootDialog(),
    );
  }

  void _showRegisterWorkspaceDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (_) => const _RegisterWorkspaceDialog(),
    );
  }
}

final class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    this.actionLabel,
    this.onAdd,
  });

  final String title;
  final int count;
  final String? actionLabel;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(title, style: theme.textTheme.titleSmall?.copyWith(fontSize: 13)),
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
        if (onAdd != null && actionLabel != null) ...[
          const Spacer(),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(LucideIcons.plus, size: 13),
            label: Text(actionLabel!),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.primary,
            ),
          ),
        ],
      ],
    );
  }
}

final class _RootsList extends StatelessWidget {
  const _RootsList({required this.state, required this.items});

  final RootsState state;
  final List<CockpitRootResource> items;

  @override
  Widget build(BuildContext context) {
    if (state.loading && state.items.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (items.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.error != null) _ErrorBanner(error: state.error!),
          SizedBox(
            height: 200,
            child: EmptyStateView(
              icon: LucideIcons.folderPlus,
              title: context.t.projects.noAllowedFolders,
              description: context.t.projects.noAllowedFoldersDescription,
            ),
          ),
        ],
      );
    }

    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.error != null) _ErrorBanner(error: state.error!),
        Container(
          decoration: ConsoleShapes.decoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderColor: theme.dividerColor,
          ),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) Divider(height: 1, color: theme.dividerColor),
                _RootTile(item: items[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

final class _RootTile extends HookConsumerWidget {
  const _RootTile({required this.item});

  final CockpitRootResource item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final removing = useState(false);
    final removed = item.state == CockpitRootState.retired;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(
            LucideIcons.folder,
            size: 15,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.canonicalPath,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StateBadge(stateName: item.state.name),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  item.rootId,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: context.consoleColors.inkTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!removed)
            SizedBox(
              width: 30,
              height: 30,
              child: removing.value
                  ? const Padding(
                      padding: EdgeInsets.all(4),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      onPressed: () => _confirmRemove(context, ref, removing),
                      icon: const Icon(LucideIcons.trash2, size: 13),
                      tooltip: context.t.projects.removeFolderTooltip,
                      color: theme.colorScheme.error,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                    ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    ValueNotifier<bool> removing,
  ) async {
    final force = await _confirmRemoval(
      context: context,
      title: context.t.projects.removeFolderTitle,
      message: context.t.projects.removeFolderDescription(
        path: item.canonicalPath,
      ),
    );
    if (force == null || !context.mounted) return;
    removing.value = true;
    final ok = await ref
        .read(rootsProvider.notifier)
        .remove(rootId: item.rootId, force: force);
    removing.value = false;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? context.t.projects.folderRemoved
              : context.t.projects.folderRemoveFailed,
        ),
      ),
    );
  }
}

final class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.stateName});

  final String stateName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (stateName) {
      'active' => context.consoleColors.success,
      'draining' => context.consoleColors.warning,
      'retired' => theme.colorScheme.onSurfaceVariant,
      _ => theme.colorScheme.onSurfaceVariant,
    };
    final label = switch (stateName) {
      'active' => context.t.projects.stateReady,
      'draining' => context.t.projects.stateRemoving,
      'retired' => context.t.projects.stateRemoved,
      _ => stateName,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: ConsoleShapes.decoration(
        color: color.withValues(alpha: 0.12),
        radius: 6,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// Returns true to remove immediately, false to finish active work, or null.
Future<bool?> _confirmRemoval({
  required BuildContext context,
  required String title,
  required String message,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Text(message),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(null),
          child: Text(context.t.common.cancel),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(context.t.projects.finishWorkRemove),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(context.t.projects.removeNow),
        ),
      ],
    ),
  );
}

final class _WorkspacesList extends StatelessWidget {
  const _WorkspacesList({required this.state, required this.items});

  final WorkspacesState state;
  final List<CockpitWorkspaceResource> items;

  @override
  Widget build(BuildContext context) {
    if (state.loading && state.items.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (items.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.error != null) _ErrorBanner(error: state.error!),
          SizedBox(
            height: 200,
            child: EmptyStateView(
              icon: LucideIcons.gitBranch,
              title: context.t.projects.noProjects,
              description: context.t.projects.noProjectsDescription,
            ),
          ),
        ],
      );
    }

    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.error != null) _ErrorBanner(error: state.error!),
        Container(
          decoration: ConsoleShapes.decoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderColor: theme.dividerColor,
          ),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) Divider(height: 1, color: theme.dividerColor),
                _WorkspaceTile(item: items[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

final class _WorkspaceTile extends HookConsumerWidget {
  const _WorkspaceTile({required this.item});

  final CockpitWorkspaceResource item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selectedId = ref.watch(selectedWorkspaceIdProvider);
    final isSelected = selectedId == item.workspaceId;
    final removing = useState(false);
    final removed = item.state == CockpitWorkspaceState.retired;
    final projectName = p.basename(item.canonicalPath);

    return Semantics(
      container: true,
      button: !removed,
      enabled: !removed,
      selected: isSelected,
      label: removed
          ? context.t.projects.removedProjectSemantics(name: projectName)
          : context.t.projects.selectProjectSemantics(name: projectName),
      child: InkWell(
        onTap: removed
            ? null
            : () => ref
                  .read(selectedWorkspaceIdProvider.notifier)
                  .select(item.workspaceId),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.06)
              : null,
          child: Row(
            children: [
              Icon(
                LucideIcons.gitBranch,
                size: 15,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.canonicalPath,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'monospace',
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StateBadge(stateName: item.state.name),
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      context.t.projects.workspaceIdentity(
                        workspace: item.workspaceId,
                        root: item.rootId,
                      ),
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
              const SizedBox(width: 8),
              if (!removed) ...[
                SizedBox(
                  width: 30,
                  height: 30,
                  child: IconButton(
                    onPressed: removing.value
                        ? null
                        : () => showDialog<void>(
                            context: context,
                            builder: (_) =>
                                _RebindWorkspaceDialog(workspace: item),
                          ),
                    icon: const Icon(LucideIcons.gitCompare, size: 13),
                    tooltip: context.t.projects.updateLocationTooltip,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              if (isSelected && !removed)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: ConsoleShapes.decoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    radius: 6,
                  ),
                  child: Text(
                    context.t.projects.current,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              if (removing.value && !removed)
                const Padding(
                  padding: EdgeInsets.all(4),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (!removed)
                SizedBox(
                  width: 30,
                  height: 30,
                  child: IconButton(
                    onPressed: () => _confirmRemove(context, ref, removing),
                    icon: const Icon(LucideIcons.trash2, size: 13),
                    tooltip: context.t.projects.removeProjectTooltip,
                    color: theme.colorScheme.error,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    ValueNotifier<bool> removing,
  ) async {
    final force = await _confirmRemoval(
      context: context,
      title: context.t.projects.removeProjectTitle,
      message: context.t.projects.removeProjectDescription(
        path: item.canonicalPath,
      ),
    );
    if (force == null || !context.mounted) return;
    removing.value = true;
    final ok = await ref
        .read(workspacesProvider.notifier)
        .remove(workspaceId: item.workspaceId, force: force);
    removing.value = false;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? context.t.projects.projectRemoved
              : context.t.projects.projectRemoveFailed,
        ),
      ),
    );
  }
}

final class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: ConsoleShapes.decoration(
        color: theme.colorScheme.error.withValues(alpha: 0.08),
        borderColor: theme.colorScheme.error.withValues(alpha: 0.3),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.alertCircle,
            size: 14,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.error,
                height: 1.4,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dialogs ──────────────────────────────────────────────────────────────

final class _RegisterRootDialog extends HookConsumerWidget {
  const _RegisterRootDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pathCtrl = useTextEditingController();
    final labelCtrl = useTextEditingController();
    final submitting = useState(false);
    final error = useState<String?>(null);

    Future<void> submit() async {
      final path = pathCtrl.text.trim();
      if (path.isEmpty || !p.isAbsolute(path)) {
        error.value = context.t.projects.absoluteFolderError;
        return;
      }
      submitting.value = true;
      error.value = null;
      final label = labelCtrl.text.trim();
      final ok = await ref
          .read(rootsProvider.notifier)
          .register(
            path: p.normalize(path),
            label: label.isEmpty ? null : label,
          );
      if (!context.mounted) return;
      if (ok) {
        Navigator.of(context).pop();
        return;
      }
      submitting.value = false;
      error.value =
          ref.read(rootsProvider).error ?? context.t.projects.addFolderFailed;
    }

    return AlertDialog(
      title: Text(context.t.projects.addFolderTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.t.projects.addFolderDescription,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            ConsoleTextField(
              controller: pathCtrl,
              enabled: !submitting.value,
              autofocus: true,
              label: context.t.projects.folderPath,
              hint: context.t.projects.folderPathHint,
              prefixIcon: const Icon(LucideIcons.folder, size: 16),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
            const SizedBox(height: 12),
            ConsoleTextField(
              controller: labelCtrl,
              enabled: !submitting.value,
              label: context.t.projects.optionalName,
              hint: context.t.projects.projectNameHint,
              onSubmitted: (_) => submitting.value ? null : submit(),
            ),
            if (error.value != null) ...[
              const SizedBox(height: 12),
              _DialogError(message: error.value!),
            ],
          ],
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
              : Text(context.t.projects.addFolder),
        ),
      ],
    );
  }
}

final class _RegisterWorkspaceDialog extends HookConsumerWidget {
  const _RegisterWorkspaceDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pathCtrl = useTextEditingController();
    final selectedRootId = useState<String?>(null);
    final submitting = useState(false);
    final error = useState<String?>(null);
    final activeRoots = ref
        .watch(rootsProvider)
        .items
        .where((root) => root.state == CockpitRootState.active)
        .toList(growable: false);
    final rootId =
        activeRoots.any((root) => root.rootId == selectedRootId.value)
        ? selectedRootId.value
        : activeRoots.isEmpty
        ? null
        : activeRoots.first.rootId;

    Future<void> submit() async {
      final path = pathCtrl.text.trim();
      if (rootId == null) {
        error.value = context.t.projects.allowedFolderRequired;
        return;
      }
      if (path.isEmpty || !p.isAbsolute(path)) {
        error.value = context.t.projects.absoluteProjectError;
        return;
      }
      submitting.value = true;
      error.value = null;
      final ok = await ref
          .read(workspacesProvider.notifier)
          .register(rootId: rootId, path: p.normalize(path));
      if (!context.mounted) return;
      if (ok) {
        Navigator.of(context).pop();
        return;
      }
      submitting.value = false;
      error.value =
          ref.read(workspacesProvider).error ??
          context.t.projects.addProjectFailed;
    }

    return AlertDialog(
      title: Text(context.t.projects.addProject),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConsoleDropdownField<String>(
              key: ValueKey(rootId),
              initialValue: rootId,
              label: context.t.projects.allowedFolder,
              prefixIcon: const Icon(LucideIcons.folder, size: 16),
              items: [
                for (final root in activeRoots)
                  DropdownMenuItem(
                    value: root.rootId,
                    child: Text(
                      root.canonicalPath,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
              onChanged: submitting.value
                  ? null
                  : (value) => selectedRootId.value = value,
            ),
            const SizedBox(height: 12),
            ConsoleTextField(
              controller: pathCtrl,
              enabled: !submitting.value,
              autofocus: true,
              label: context.t.projects.projectDirectory,
              hint: context.t.projects.folderPathHint,
              prefixIcon: const Icon(LucideIcons.gitBranch, size: 16),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              onSubmitted: (_) {
                if (!submitting.value) submit();
              },
            ),
            if (activeRoots.isEmpty) ...[
              const SizedBox(height: 12),
              _DialogError(
                message: context.t.projects.noAllowedFoldersAvailable,
              ),
            ] else if (error.value != null) ...[
              const SizedBox(height: 12),
              _DialogError(message: error.value!),
            ],
          ],
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
          onPressed: submitting.value || activeRoots.isEmpty ? null : submit,
          child: submitting.value
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(context.t.projects.addProject),
        ),
      ],
    );
  }
}

final class _RebindWorkspaceDialog extends HookConsumerWidget {
  const _RebindWorkspaceDialog({required this.workspace});

  final CockpitWorkspaceResource workspace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pathCtrl = useTextEditingController();
    final submitting = useState(false);
    final error = useState<String?>(null);

    Future<void> submit() async {
      final path = pathCtrl.text.trim();
      if (path.isEmpty || !p.isAbsolute(path)) {
        error.value = context.t.projects.newAbsoluteProjectError;
        return;
      }
      submitting.value = true;
      error.value = null;
      final ok = await ref
          .read(workspacesProvider.notifier)
          .rebind(
            workspaceId: workspace.workspaceId,
            path: p.normalize(path),
            expectedCheckoutId: workspace.checkoutId,
          );
      if (!context.mounted) return;
      if (ok) {
        Navigator.of(context).pop();
        return;
      }
      submitting.value = false;
      error.value =
          ref.read(workspacesProvider).error ??
          context.t.projects.updateLocationFailed;
    }

    return AlertDialog(
      title: Text(context.t.projects.updateLocationTitle),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.t.projects.currentDirectory,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            SelectableText(
              workspace.canonicalPath,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 16),
            ConsoleTextField(
              controller: pathCtrl,
              enabled: !submitting.value,
              autofocus: true,
              label: context.t.projects.newProjectDirectory,
              prefixIcon: const Icon(LucideIcons.gitBranch, size: 16),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
            if (error.value != null) ...[
              const SizedBox(height: 12),
              _DialogError(message: error.value!),
            ],
          ],
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
              : Text(context.t.projects.updateLocation),
        ),
      ],
    );
  }
}

final class _DialogError extends StatelessWidget {
  const _DialogError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: ConsoleShapes.decoration(
        color: color.withValues(alpha: 0.08),
        radius: ConsoleShapes.smallRadius,
      ),
      child: Text(message, style: TextStyle(fontSize: 12, color: color)),
    );
  }
}
