import 'dart:convert';

import 'package:cockpit_console/src/providers/core_providers.dart';
import 'package:cockpit_console/src/providers/data_providers.dart';
import 'package:cockpit_console/src/theme/console_colors.dart';
import 'package:cockpit_console/src/theme/console_shapes.dart';
import 'package:cockpit_console/src/ui/navigation/console_nav.dart';
import 'package:cockpit_console/src/ui/widgets/console_form_controls.dart';
import 'package:cockpit_console/src/ui/widgets/empty_state.dart';
import 'package:cockpit_console/src/ui/widgets/screen_scaffold.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const _prettyJson = JsonEncoder.withIndent('  ');

/// Resolves how (and whether) the console can invoke an advertised operation,
/// and which scope identity to pass to
/// [ConsoleSupervisorClient.executeOperation]: [rootId] for root-scoped
/// operations, [workspaceId] for workspace-scoped operations, and neither for
/// supervisor-scoped operations. Root-scoped operations require an active
/// project root selected by the operator.
({bool invocable, String? reason, String? rootId, String? workspaceId})
_availabilityFor(
  CockpitOperationDescriptor descriptor, {
  required String? selectedWorkspaceId,
  required String? selectedRootId,
  required bool hasActiveRoots,
}) => switch (descriptor.scope) {
  CockpitOperationScope.workspace =>
    selectedWorkspaceId == null
        ? (
            invocable: false,
            reason: 'Select a project to run this project-scoped action.',
            rootId: null,
            workspaceId: null,
          )
        : (
            invocable: true,
            reason: null,
            rootId: null,
            workspaceId: selectedWorkspaceId,
          ),
  CockpitOperationScope.supervisor => (
    invocable: true,
    reason: null,
    rootId: null,
    workspaceId: null,
  ),
  CockpitOperationScope.root =>
    selectedRootId == null
        ? (
            invocable: false,
            reason: hasActiveRoots
                ? 'Select an allowed folder to run this folder-scoped action.'
                : 'No allowed folder is available. Add one under Projects '
                      'to run folder-scoped actions.',
            rootId: null,
            workspaceId: null,
          )
        : (
            invocable: true,
            reason: null,
            rootId: selectedRootId,
            workspaceId: null,
          ),
};

CockpitOperationDescriptor? _findDescriptor(
  Iterable<CockpitOperationDescriptor> global,
  Iterable<CockpitOperationDescriptor> workspace,
  String? kind,
) {
  if (kind == null) return null;
  for (final descriptor in global) {
    if (descriptor.kind == kind) return descriptor;
  }
  for (final descriptor in workspace) {
    if (descriptor.kind == kind) return descriptor;
  }
  return null;
}

/// Operations screen: inspect and invoke advertised Supervisor operations.
///
/// The left pane lists global (supervisor- and root-scoped) operations and,
/// when a workspace is selected, the workspace-scoped operations advertised for
/// it. The right pane shows the selected operation's contract, accepts a
/// structured object input, an optional idempotency key, and (for root-scoped operations)
/// an exact root selector, then invokes it through the canonical client.
/// Concurrent duplicate submissions are blocked, stale responses are discarded
/// on selection/root/workspace change, and the full structured result is
/// retained for inspection.
final class OperationsScreen extends HookConsumerWidget {
  const OperationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaceId = ref.watch(selectedWorkspaceIdProvider);
    final invState = ref.watch(operationInvocationProvider);
    final globalOps = ref
        .watch(operationsProvider(null))
        .maybeWhen(
          data: (items) => items,
          orElse: () => const <CockpitOperationDescriptor>[],
        );
    final workspaceOps = workspaceId == null
        ? const <CockpitOperationDescriptor>[]
        : ref
              .watch(operationsProvider(workspaceId))
              .maybeWhen(
                data: (items) => items,
                orElse: () => const <CockpitOperationDescriptor>[],
              );
    final rootsState = ref.watch(rootsProvider);
    final activeRoots = rootsState.items
        .where((root) => root.state == CockpitRootState.active)
        .toList(growable: false);
    final splitWidth = useState<double>(300.0);

    useEffect(() {
      var canceled = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (canceled || !context.mounted) return;
        ref
            .read(operationInvocationProvider.notifier)
            .activateWorkspace(workspaceId);
      });
      return () => canceled = true;
    }, [workspaceId]);

    // Refresh roots once on entry so root-scoped operations can be invoked
    // without a manual detour to the Workspaces screen.
    useEffect(() {
      var canceled = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (canceled || !context.mounted) return;
        ref.read(rootsProvider.notifier).refresh();
      });
      return () => canceled = true;
    }, []);

    // If the selected root is removed or retired, drop it so a stale result
    // cannot surface under a missing root.
    useEffect(() {
      var canceled = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (canceled || !context.mounted) return;
        if (invState.selectedRootId != null &&
            !activeRoots.any(
              (root) => root.rootId == invState.selectedRootId,
            )) {
          ref.read(operationInvocationProvider.notifier).selectRoot(null);
        }
      });
      return () => canceled = true;
    }, [activeRoots]);

    final selectedDescriptor = _findDescriptor(
      globalOps,
      workspaceOps,
      invState.selectedKind,
    );

    return ScreenScaffold(
      title: 'Actions',
      subtitle: 'Inspect and run the actions available in Cockpit',
      body: _SplitLayout(
        leftWidth: splitWidth,
        left: _OperationBrowser(
          workspaceId: workspaceId,
          selectedKind: invState.selectedKind,
        ),
        right: selectedDescriptor == null
            ? const EmptyStateView(
                icon: LucideIcons.command,
                title: 'Select an action',
                description:
                    'Choose an available action to review its inputs and run it '
                    'with a LON, JSON, or YAML object.',
              )
            : _OperationDetail(
                descriptor: selectedDescriptor,
                workspaceId: workspaceId,
                activeRoots: activeRoots,
                selectedRootId: invState.selectedRootId,
                state: invState,
              ),
      ),
    );
  }
}

// ── Layout ───────────────────────────────────────────────────────────────

final class _SplitLayout extends StatelessWidget {
  const _SplitLayout({
    required this.leftWidth,
    required this.left,
    required this.right,
  });

  final ValueNotifier<double> leftWidth;
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            children: [
              Expanded(flex: 2, child: left),
              Container(height: 1, color: theme.dividerColor),
              Expanded(flex: 3, child: right),
            ],
          );
        }
        final maximumWidth = constraints.maxWidth * 0.5;
        final width = leftWidth.value.clamp(260.0, maximumWidth);
        return Row(
          children: [
            SizedBox(width: width, child: left),
            GestureDetector(
              onHorizontalDragUpdate: (details) {
                leftWidth.value = (leftWidth.value + details.delta.dx).clamp(
                  260.0,
                  maximumWidth,
                );
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: Container(width: 1, color: theme.dividerColor),
              ),
            ),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

// ── Operation browser (left pane) ────────────────────────────────────────

final class _OperationBrowser extends HookConsumerWidget {
  const _OperationBrowser({
    required this.workspaceId,
    required this.selectedKind,
  });

  final String? workspaceId;
  final String? selectedKind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final globalAsync = ref.watch(operationsProvider(null));
    final workspaceAsync = workspaceId != null
        ? ref.watch(operationsProvider(workspaceId))
        : const AsyncValue<List<CockpitOperationDescriptor>>.loading();
    final query = useState('');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: ConsoleTextField(
            onChanged: (value) => query.value = value,
            hint: 'Filter actions',
            prefixIcon: const Icon(LucideIcons.search, size: 15),
          ),
        ),
        Container(height: 1, color: theme.dividerColor),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _OperationSection(
                label: workspaceId == null ? 'Actions' : 'Global actions',
                async: globalAsync,
                query: query.value,
                selectedKind: selectedKind,
                onSelect: (kind) =>
                    ref.read(operationInvocationProvider.notifier).select(kind),
              ),
              if (workspaceId != null) ...[
                const SizedBox(height: 8),
                _OperationSection(
                  label: 'Project actions',
                  async: workspaceAsync,
                  query: query.value,
                  selectedKind: selectedKind,
                  onSelect: (kind) => ref
                      .read(operationInvocationProvider.notifier)
                      .select(kind),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

final class _OperationSection extends StatelessWidget {
  const _OperationSection({
    required this.label,
    required this.async,
    required this.query,
    required this.selectedKind,
    required this.onSelect,
  });

  final String label;
  final AsyncValue<List<CockpitOperationDescriptor>> async;
  final String query;
  final String? selectedKind;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(fontSize: 12),
              ),
              const SizedBox(width: 8),
              if (async.hasValue) _CountChip(count: async.requireValue.length),
            ],
          ),
        ),
        const SizedBox(height: 6),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              'Failed to load operations: $error',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
            ),
          ),
          data: (items) {
            final filtered = _applyQuery(items, query);
            if (filtered.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Text(
                  query.trim().isEmpty
                      ? 'No operations advertised.'
                      : 'No operations match "${query.trim()}".',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }
            return Column(
              children: [
                for (var i = 0; i < filtered.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: theme.dividerColor),
                  _OperationTile(
                    descriptor: filtered[i],
                    selected: filtered[i].kind == selectedKind,
                    onSelect: () => onSelect(filtered[i].kind),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

List<CockpitOperationDescriptor> _applyQuery(
  List<CockpitOperationDescriptor> items,
  String query,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return items;
  return items
      .where(
        (descriptor) =>
            descriptor.kind.toLowerCase().contains(needle) ||
            descriptor.title.toLowerCase().contains(needle) ||
            descriptor.description.toLowerCase().contains(needle),
      )
      .toList(growable: false);
}

final class _CountChip extends StatelessWidget {
  const _CountChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: ConsoleShapes.decoration(
        color: theme.colorScheme.surfaceContainerHigh,
        radius: 6,
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

final class _OperationTile extends StatelessWidget {
  const _OperationTile({
    required this.descriptor,
    required this.selected,
    required this.onSelect,
  });

  final CockpitOperationDescriptor descriptor;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: descriptor.kind,
      excludeSemantics: true,
      onTap: onSelect,
      child: Material(
        color: selected
            ? theme.colorScheme.surfaceContainerHigh
            : Colors.transparent,
        child: InkWell(
          key: ValueKey(descriptor.kind),
          onTap: onSelect,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  descriptor.mutationClass == CockpitMutationClass.mutating
                      ? LucideIcons.zap
                      : LucideIcons.eye,
                  size: 14,
                  color:
                      descriptor.mutationClass == CockpitMutationClass.mutating
                      ? context.consoleColors.warning
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        descriptor.kind,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: theme.colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        descriptor.title,
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
                _ScopeBadge(scope: descriptor.scope),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _ScopeBadge extends StatelessWidget {
  const _ScopeBadge({required this.scope});

  final CockpitOperationScope scope;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, tint) = switch (scope) {
      CockpitOperationScope.supervisor => ('global', theme.colorScheme.primary),
      CockpitOperationScope.workspace => (
        'workspace',
        context.consoleColors.success,
      ),
      CockpitOperationScope.root => ('root', context.consoleColors.warning),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: ConsoleShapes.decoration(
        color: tint.withValues(alpha: 0.12),
        radius: 6,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: tint,
        ),
      ),
    );
  }
}

// ── Operation detail (right pane) ────────────────────────────────────────

final class _OperationDetail extends HookConsumerWidget {
  const _OperationDetail({
    required this.descriptor,
    required this.workspaceId,
    required this.activeRoots,
    required this.selectedRootId,
    required this.state,
  });

  final CockpitOperationDescriptor descriptor;
  final String? workspaceId;
  final List<CockpitRootResource> activeRoots;
  final String? selectedRootId;
  final OperationInvocationState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(operationInvocationProvider.notifier);
    final availability = _availabilityFor(
      descriptor,
      selectedWorkspaceId: workspaceId,
      selectedRootId: selectedRootId,
      hasActiveRoots: activeRoots.isNotEmpty,
    );
    final inputController = useTextEditingController(text: state.inputText);
    final keyController = useTextEditingController(text: state.idempotencyKey);

    useEffect(() {
      if (inputController.text != state.inputText) {
        inputController.text = state.inputText;
      }
      return null;
    }, [state.inputText]);

    useEffect(() {
      if (keyController.text != state.idempotencyKey) {
        keyController.text = state.idempotencyKey;
      }
      return null;
    }, [state.idempotencyKey]);

    // Expose a generated idempotency key up front for required operations.
    useEffect(() {
      var canceled = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (canceled || !context.mounted) return;
        if (descriptor.idempotency == CockpitIdempotencyBehavior.required &&
            state.idempotencyKey.trim().isEmpty &&
            state.selectedKind == descriptor.kind &&
            !state.submitting) {
          notifier.setIdempotencyKey(
            generateOperationIdempotencyKey(descriptor.kind),
          );
        }
      });
      return () => canceled = true;
    }, [descriptor.kind, descriptor.idempotency, state.selectedKind]);

    final isRootScoped = descriptor.scope == CockpitOperationScope.root;
    final showKey =
        descriptor.idempotency != CockpitIdempotencyBehavior.prohibited;
    final hasResult = state.resultBelongsTo(
      kind: descriptor.kind,
      rootId: availability.rootId,
      workspaceId: availability.workspaceId,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailHeader(descriptor: descriptor),
              const SizedBox(height: 16),
              _ContractPanel(descriptor: descriptor),
              const SizedBox(height: 16),
              _SectionCard(
                icon: LucideIcons.braces,
                title: 'Input',
                subtitle:
                    'A LON, JSON, or YAML object. The idempotency key rides '
                    'the invocation envelope, never this object.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isRootScoped)
                      _RootSelector(
                        roots: activeRoots,
                        selectedRootId: selectedRootId,
                        enabled: !state.submitting,
                        onChanged: notifier.selectRoot,
                      ),
                    if (isRootScoped) const SizedBox(height: 12),
                    _InputEditor(
                      controller: inputController,
                      enabled: !state.submitting && availability.invocable,
                      hint: '{\n  \n}',
                      onChanged: notifier.setInput,
                    ),
                    if (showKey) ...[
                      const SizedBox(height: 12),
                      _IdempotencyField(
                        controller: keyController,
                        behavior: descriptor.idempotency,
                        enabled: !state.submitting && availability.invocable,
                        onChanged: notifier.setIdempotencyKey,
                        onRegenerate: () => notifier.setIdempotencyKey(
                          generateOperationIdempotencyKey(descriptor.kind),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    _InvokeControl(
                      descriptor: descriptor,
                      availability: availability,
                      offerRegisterRoot: isRootScoped && activeRoots.isEmpty,
                      submitting: state.submitting,
                      onInvoke: () => notifier.invoke(
                        descriptor: descriptor,
                        rootId: availability.rootId,
                        workspaceId: availability.workspaceId,
                      ),
                    ),
                  ],
                ),
              ),
              if (state.error != null && hasResult) ...[
                const SizedBox(height: 16),
                _OutcomeBanner(error: state.error!, result: state.result),
              ] else if (state.error != null) ...[
                const SizedBox(height: 16),
                _OutcomeBanner(error: state.error!, result: null),
              ] else if (hasResult) ...[
                const SizedBox(height: 16),
                _ResultPanel(result: state.result!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

final class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.descriptor});

  final CockpitOperationDescriptor descriptor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                descriptor.title,
                style: theme.textTheme.headlineMedium?.copyWith(fontSize: 18),
              ),
              const SizedBox(height: 4),
              Text(
                descriptor.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: ConsoleShapes.decoration(
            color: theme.colorScheme.surfaceContainerHigh,
            radius: ConsoleShapes.smallRadius,
          ),
          child: Text(
            descriptor.kind,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

final class _ContractPanel extends StatelessWidget {
  const _ContractPanel({required this.descriptor});

  final CockpitOperationDescriptor descriptor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: ConsoleShapes.decoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderColor: theme.dividerColor,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MetaRow(label: 'Scope', value: _scopeLabel(descriptor.scope)),
          _MetaRow(
            label: 'Mutation',
            value: _mutationLabel(descriptor.mutationClass),
          ),
          _MetaRow(
            label: 'Idempotency',
            value: _idempotencyLabel(descriptor.idempotency),
          ),
          _MetaRow(
            label: 'Execution',
            value: _executionLabel(descriptor.executionMode),
          ),
          _MetaRow(
            label: 'Timeout',
            value:
                '${_formatTimeoutMs(descriptor.defaultTimeoutMs)} '
                '(max ${_formatTimeoutMs(descriptor.maximumTimeoutMs)})',
          ),
          if (descriptor.safetyEffects.isNotEmpty)
            _MetaRow(
              label: 'Effects',
              value: descriptor.safetyEffects
                  .map((effect) => effect.wireValue)
                  .join(', '),
            ),
          if (descriptor.requiredFeatures.isNotEmpty)
            _MetaRow(
              label: 'Features',
              value: descriptor.requiredFeatures.join(', '),
            ),
          _MetaRow(
            label: 'Input schema',
            value: descriptor.requestSchemaRef,
            mono: true,
          ),
          _MetaRow(
            label: 'Output schema',
            value: descriptor.responseSchemaRef,
            mono: true,
          ),
        ],
      ),
    );
  }
}

final class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value, this.mono = false});

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 12,
                fontFamily: mono ? 'monospace' : null,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: ConsoleShapes.decoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderColor: theme.dividerColor,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              height: 1.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

final class _InputEditor extends StatelessWidget {
  const _InputEditor({
    required this.controller,
    required this.enabled,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 140),
      decoration: ConsoleShapes.decoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderColor: theme.dividerColor,
        radius: ConsoleShapes.smallRadius,
      ),
      child: TextField(
        controller: controller,
        enabled: enabled,
        minLines: 6,
        maxLines: 12,
        onChanged: onChanged,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.5,
          color: theme.colorScheme.onSurface,
        ),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(12),
          hintText: hint,
          hintStyle: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}

final class _IdempotencyField extends StatelessWidget {
  const _IdempotencyField({
    required this.controller,
    required this.behavior,
    required this.enabled,
    required this.onChanged,
    required this.onRegenerate,
  });

  final TextEditingController controller;
  final CockpitIdempotencyBehavior behavior;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final required = behavior == CockpitIdempotencyBehavior.required;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: ConsoleTextField(
                controller: controller,
                enabled: enabled,
                onChanged: onChanged,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: theme.colorScheme.onSurface,
                ),
                label: 'Idempotency key',
                hint: required ? 'Generated on invoke' : 'Optional',
                prefixIcon: const Icon(LucideIcons.keyRound, size: 14),
              ),
            ),
            const SizedBox(width: 8),
            ConsoleFieldIconButton(
              tooltip: 'Generate a new key',
              onPressed: enabled ? onRegenerate : null,
              icon: const Icon(LucideIcons.refreshCw, size: 15),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          required
              ? 'Required for this mutating operation.'
              : 'Optional; omitted when blank.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Exact root selector for root-scoped operations, mirroring the dropdown used
/// to register a workspace. An empty list is surfaced as a precise reason
/// rather than a disabled, empty control.
final class _RootSelector extends StatelessWidget {
  const _RootSelector({
    required this.roots,
    required this.selectedRootId,
    required this.enabled,
    required this.onChanged,
  });

  final List<CockpitRootResource> roots;
  final String? selectedRootId;
  final bool enabled;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (roots.isEmpty) {
      return const Text(
        'No active project roots are registered.',
        style: TextStyle(fontSize: 12),
      );
    }
    final rootId = roots.any((root) => root.rootId == selectedRootId)
        ? selectedRootId
        : null;
    return ConsoleDropdownField<String>(
      key: ValueKey(rootId),
      initialValue: rootId,
      label: 'Project root',
      prefixIcon: const Icon(LucideIcons.folder, size: 16),
      hint: const Text('Select an active root'),
      items: [
        for (final root in roots)
          DropdownMenuItem(
            value: root.rootId,
            child: Text(
              root.canonicalPath,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
      ],
      enabled: enabled,
      onChanged: onChanged,
    );
  }
}

final class _InvokeControl extends ConsumerWidget {
  const _InvokeControl({
    required this.descriptor,
    required this.availability,
    required this.submitting,
    required this.offerRegisterRoot,
    required this.onInvoke,
  });

  final CockpitOperationDescriptor descriptor;
  final ({bool invocable, String? reason, String? rootId, String? workspaceId})
  availability;
  final bool submitting;
  final bool offerRegisterRoot;
  final Future<void> Function() onInvoke;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scopeStyle = TextStyle(
      fontSize: 11,
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (!availability.invocable) {
      // A folder-scoped action with no active root offers a direct detour to
      // Projects where allowed folders are registered, never a simulation.
      return LayoutBuilder(
        builder: (context, constraints) {
          final reason = Row(
            children: [
              Icon(
                LucideIcons.lock,
                size: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  availability.reason ?? 'This action cannot be run here.',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          );
          if (!offerRegisterRoot) return reason;
          final action = TextButton.icon(
            onPressed: () => ref
                .read(navProvider.notifier)
                .go(ConsoleNavDestination.workspaces),
            icon: const Icon(LucideIcons.folderPlus, size: 13),
            label: const Text('Add allowed folder'),
          );
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [reason, const SizedBox(height: 6), action],
            );
          }
          return Row(
            children: [
              Expanded(child: reason),
              const SizedBox(width: 8),
              action,
            ],
          );
        },
      );
    }

    final invokeButton = FilledButton.icon(
      onPressed: submitting ? null : onInvoke,
      icon: submitting
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              descriptor.mutationClass == CockpitMutationClass.mutating
                  ? LucideIcons.zap
                  : LucideIcons.play,
              size: 14,
            ),
      label: Text(
        descriptor.mutationClass == CockpitMutationClass.mutating
            ? 'Invoke (mutating)'
            : 'Invoke',
      ),
    );
    final scopeLabel = Text(
      availability.rootId != null
          ? 'Scoped to the selected root.'
          : availability.workspaceId != null
          ? 'Scoped to the selected workspace.'
          : 'Invoked globally (no root or workspace).',
      style: scopeStyle,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [invokeButton, const SizedBox(height: 8), scopeLabel],
          );
        }
        return Row(
          children: [
            invokeButton,
            const SizedBox(width: 12),
            Flexible(child: scopeLabel),
          ],
        );
      },
    );
  }
}

// ── Outcome rendering ────────────────────────────────────────────────────

final class _OutcomeBanner extends StatelessWidget {
  const _OutcomeBanner({required this.error, required this.result});

  final String error;
  final Map<String, Object?>? result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: ConsoleShapes.decoration(
        color: theme.colorScheme.error.withValues(alpha: 0.06),
        borderColor: theme.colorScheme.error.withValues(alpha: 0.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.xCircle,
                size: 15,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 8),
              Text(
                'Operation did not succeed',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            error,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: theme.colorScheme.onSurface,
            ),
          ),
          if (result != null) ...[
            const SizedBox(height: 12),
            _ResultBody(result: result!, collapsed: true),
          ],
        ],
      ),
    );
  }
}

final class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.result});

  final Map<String, Object?> result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outcome = result['outcome'] as String?;
    final lifecycle = result['lifecycle'] as String?;
    final operationId = result['operationId'] as String?;
    // _ResultPanel is only reached when there is no operation-level error,
    // so the result is either a succeeded operation or an accepted (non-
    // terminal) job. Distinguish the two so a queued/running job is not
    // mistaken for success.
    final succeeded = outcome == 'succeeded';
    final icon = succeeded
        ? LucideIcons.checkCircle2
        : LucideIcons.loaderCircle;
    final color = succeeded
        ? context.consoleColors.success
        : theme.colorScheme.onSurfaceVariant;
    final title = succeeded
        ? 'Result'
        : (lifecycle == null ? 'Submitted' : 'Submitted · $lifecycle');
    return _ResultBody(
      result: result,
      header: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          if (operationId != null) ...[
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                operationId,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (outcome != null) ...[
            const SizedBox(width: 8),
            _OutcomeChip(outcome: outcome),
          ],
        ],
      ),
    );
  }
}

final class _ResultBody extends StatelessWidget {
  const _ResultBody({
    required this.result,
    this.header,
    this.collapsed = false,
  });

  final Map<String, Object?> result;
  final Widget? header;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final encoded = _prettyJson.convert(result);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: ConsoleShapes.decoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderColor: theme.dividerColor,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null) ...[header!, const SizedBox(height: 8)],
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [_CopyButton(text: encoded)],
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            constraints: BoxConstraints(maxHeight: collapsed ? 220 : 420),
            child: SingleChildScrollView(
              child: SelectableText(
                encoded,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.5,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _OutcomeChip extends StatelessWidget {
  const _OutcomeChip({required this.outcome});

  final String outcome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: ConsoleShapes.decoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        radius: 6,
      ),
      child: Text(
        outcome,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

final class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.text});

  final String text;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

final class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: widget.text));
        if (!mounted) return;
        setState(() => _copied = true);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _copied = false);
        });
      },
      icon: Icon(_copied ? LucideIcons.check : LucideIcons.copy, size: 13),
      label: Text(_copied ? 'Copied' : 'Copy'),
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }
}

// ── Label formatting ─────────────────────────────────────────────────────

String _scopeLabel(CockpitOperationScope scope) => switch (scope) {
  CockpitOperationScope.supervisor => 'Supervisor (global)',
  CockpitOperationScope.root => 'Root',
  CockpitOperationScope.workspace => 'Workspace',
};

String _mutationLabel(CockpitMutationClass mutation) => switch (mutation) {
  CockpitMutationClass.readOnly => 'Read-only',
  CockpitMutationClass.mutating => 'Mutating',
};

String _idempotencyLabel(CockpitIdempotencyBehavior behavior) =>
    switch (behavior) {
      CockpitIdempotencyBehavior.required => 'Required',
      CockpitIdempotencyBehavior.optional => 'Optional',
      CockpitIdempotencyBehavior.prohibited => 'Prohibited',
    };

String _executionLabel(CockpitOperationExecutionMode mode) => switch (mode) {
  CockpitOperationExecutionMode.synchronous => 'Synchronous',
  CockpitOperationExecutionMode.job => 'Job',
};

String _formatTimeoutMs(int milliseconds) {
  if (milliseconds <= 0) return '—';
  final seconds = milliseconds ~/ 1000;
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  final remainderSeconds = seconds % 60;
  if (minutes < 60) {
    return remainderSeconds == 0
        ? '${minutes}m'
        : '${minutes}m ${remainderSeconds}s';
  }
  final hours = minutes ~/ 60;
  final remainderMinutes = minutes % 60;
  return remainderMinutes == 0 ? '${hours}h' : '${hours}h ${remainderMinutes}m';
}
