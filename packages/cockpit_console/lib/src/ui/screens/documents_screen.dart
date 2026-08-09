import 'package:cockpit_console/src/providers/core_providers.dart';
import 'package:cockpit_console/src/providers/data_providers.dart';
import 'package:cockpit_console/src/theme/console_colors.dart';
import 'package:cockpit_console/src/ui/navigation/console_nav.dart';
import 'package:cockpit_console/src/ui/widgets/console_form_controls.dart';
import 'package:cockpit_console/src/ui/widgets/empty_state.dart';
import 'package:cockpit_console/src/ui/widgets/screen_scaffold.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Documents screen: validate and browse case/suite documents.
///
/// Split-pane: document list on left, a LON/JSON/YAML editor with validation
/// on the right. The editor supports save-to-file and validation against the
/// Supervisor's `cockpit.test/v2` schema.
final class DocumentsScreen extends HookConsumerWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaceId = ref.watch(selectedWorkspaceIdProvider);
    final rawDocState = ref.watch(documentProvider);
    final splitWidth = useState<double>(320.0);
    final docState = rawDocState.workspaceId == workspaceId
        ? rawDocState
        : DocumentEditorState(workspaceId: workspaceId);

    useEffect(() {
      var canceled = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final nextWorkspaceId = workspaceId;
        if (canceled || !context.mounted || nextWorkspaceId == null) return;
        ref.read(documentProvider.notifier).activateWorkspace(nextWorkspaceId);
      });
      return () => canceled = true;
    }, [workspaceId]);

    if (workspaceId == null) {
      return ScreenScaffold(
        title: 'Tests',
        subtitle: 'Create and check case or suite files in LON, JSON, or YAML',
        body: EmptyStateView(
          icon: LucideIcons.mousePointerClick,
          title: 'Select a project',
          description:
              'Choose a project from the Projects page to view its test files.',
          action: FilledButton.icon(
            onPressed: () => ref
                .read(navProvider.notifier)
                .go(ConsoleNavDestination.workspaces),
            icon: const Icon(LucideIcons.folderOpen, size: 16),
            label: const Text('Choose project'),
          ),
        ),
      );
    }

    final docsAsync = ref.watch(documentsForWorkspaceProvider(workspaceId));

    return ScreenScaffold(
      title: 'Tests',
      subtitle: 'Create and check case or suite files in LON, JSON, or YAML',
      body: docsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (error, _) => EmptyStateView(
          icon: LucideIcons.alertCircle,
          title: "Couldn't load test files",
          description: '$error',
          action: OutlinedButton.icon(
            onPressed: () =>
                ref.invalidate(documentsForWorkspaceProvider(workspaceId)),
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Retry'),
          ),
        ),
        data: (documents) {
          return _SplitLayout(
            leftWidth: splitWidth,
            left: _DocumentList(
              documents: documents,
              selectedRelativePath: docState.persistedContent.isEmpty
                  ? null
                  : docState.persistedRelativePath,
              onNew: docState.saving
                  ? null
                  : () async {
                      if (docState.dirty &&
                          !await _confirmDiscardDocumentEdits(context)) {
                        return;
                      }
                      ref.read(documentProvider.notifier).newDocument();
                    },
              onSelect: (document) async {
                if (document.relativePath == docState.persistedRelativePath &&
                    docState.persistedContent.isNotEmpty) {
                  return;
                }
                if (docState.dirty &&
                    !await _confirmDiscardDocumentEdits(context)) {
                  return;
                }
                try {
                  await ref
                      .read(documentProvider.notifier)
                      .selectDocument(
                        workspaceId: workspaceId,
                        document: document,
                      );
                } on Object catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Failed to read ${document.relativePath}: $e',
                        ),
                      ),
                    );
                  }
                }
              },
            ),
            right: _Editor(workspaceId: workspaceId, docState: docState),
          );
        },
      ),
    );
  }
}

Future<bool> _confirmDiscardDocumentEdits(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Discard unsaved changes?'),
          content: const Text(
            'The editor contains changes that have not been saved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Discard changes'),
            ),
          ],
        ),
      ) ??
      false;
}

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
        final width = leftWidth.value.clamp(240.0, maximumWidth);
        return Row(
          children: [
            SizedBox(width: width, child: left),
            GestureDetector(
              onHorizontalDragUpdate: (details) {
                leftWidth.value = (leftWidth.value + details.delta.dx).clamp(
                  240.0,
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

final class _DocumentList extends StatelessWidget {
  const _DocumentList({
    required this.documents,
    required this.selectedRelativePath,
    required this.onNew,
    required this.onSelect,
  });

  final List<CockpitDocumentResource> documents;
  final String? selectedRelativePath;
  final VoidCallback? onNew;
  final ValueChanged<CockpitDocumentResource> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text('Test files', style: theme.textTheme.titleSmall),
              ),
              TextButton.icon(
                onPressed: onNew,
                icon: const Icon(LucideIcons.filePlus2, size: 14),
                label: const Text('New test'),
              ),
            ],
          ),
        ),
        Container(height: 1, color: theme.dividerColor),
        Expanded(
          child: documents.isEmpty
              ? const EmptyStateView(
                  icon: LucideIcons.fileX,
                  title: 'No test files yet',
                  description:
                      'Create a test, save it, then check it before running.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: documents.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: theme.dividerColor),
                  itemBuilder: (context, index) {
                    final doc = documents[index];
                    return _DocumentTile(
                      document: doc,
                      selected: doc.relativePath == selectedRelativePath,
                      onTap: onSelect,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

final class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.document,
    required this.selected,
    required this.onTap,
  });

  final CockpitDocumentResource document;
  final bool selected;
  final ValueChanged<CockpitDocumentResource> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caseCount = document.cases.length;

    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        selected: selected,
        selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.07),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Icon(
          document.kind == CockpitIndexedDocumentKind.suite
              ? LucideIcons.layers
              : LucideIcons.fileText,
          size: 15,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(
          document.relativePath,
          style: TextStyle(
            fontSize: 12,
            fontFamily: 'monospace',
            color: theme.colorScheme.onSurface,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          document.kind == CockpitIndexedDocumentKind.suite
              ? 'Test suite${caseCount > 0 ? " · $caseCount cases" : ""}'
              : 'Test case',
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        onTap: () => onTap(document),
      ),
    );
  }
}

final class _Editor extends HookConsumerWidget {
  const _Editor({required this.workspaceId, required this.docState});

  final String workspaceId;
  final DocumentEditorState docState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final contentController = useTextEditingController(text: docState.content);
    final pathController = useTextEditingController(
      text: docState.relativePath,
    );

    useEffect(() {
      if (contentController.text != docState.content) {
        contentController.text = docState.content;
      }
      return null;
    }, [docState.content]);
    useEffect(() {
      if (pathController.text != docState.relativePath) {
        pathController.text = docState.relativePath;
      }
      return null;
    }, [docState.relativePath]);

    Future<void> save() async {
      final result = await ref
          .read(documentProvider.notifier)
          .saveAndIndex(workspaceId: workspaceId);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.message)));
      }
    }

    final hasContent = docState.content.trim().isNotEmpty;
    final canSave = !docState.saving && docState.dirty && hasContent;
    final canValidate = !docState.validating && !docState.saving && hasContent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: ConsoleTextField(
                      controller: pathController,
                      enabled: !docState.saving,
                      label: 'Test file path',
                      hint: 'Relative to project, e.g. cockpit/e2e/case.yaml',
                      prefixIcon: const Icon(LucideIcons.fileText, size: 15),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                      onChanged: (path) => ref
                          .read(documentProvider.notifier)
                          .setRelativePath(path),
                    ),
                  ),
                  const SizedBox(width: 12),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 120),
                    child: docState.saving
                        ? const _EditorStateLabel(
                            key: ValueKey('saving'),
                            label: 'Saving',
                            icon: LucideIcons.loaderCircle,
                          )
                        : docState.dirty
                        ? const _EditorStateLabel(
                            key: ValueKey('dirty'),
                            label: 'Unsaved',
                            icon: LucideIcons.circle,
                          )
                        : const _EditorStateLabel(
                            key: ValueKey('saved'),
                            label: 'Saved',
                            icon: LucideIcons.check,
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 100,
                    child: ConsoleDropdownField<CockpitDocumentFormat>(
                      key: ValueKey(docState.format),
                      initialValue: docState.format,
                      label: 'Format',
                      items: [
                        for (final format in CockpitDocumentFormat.values)
                          DropdownMenuItem(
                            value: format,
                            child: Text(format.name.toUpperCase()),
                          ),
                      ],
                      onChanged: docState.saving
                          ? null
                          : (format) {
                              if (format != null) {
                                ref
                                    .read(documentProvider.notifier)
                                    .setFormat(format);
                              }
                            },
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: canSave ? save : null,
                    icon: docState.saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.save, size: 14),
                    label: const Text('Save test'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: canValidate
                        ? () => ref
                              .read(documentProvider.notifier)
                              .validate(workspaceId)
                        : null,
                    icon: docState.validating
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.check, size: 14),
                    label: const Text('Check test'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (docState.validation != null)
          _ValidationBar(validation: docState.validation!),
        Expanded(
          child: Container(
            color: theme.colorScheme.surfaceContainerLowest,
            child: TextField(
              controller: contentController,
              enabled: !docState.saving,
              expands: true,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              onChanged: (text) =>
                  ref.read(documentProvider.notifier).setContent(text),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.6,
                color: theme.colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(16),
                hintText: switch (docState.format) {
                  CockpitDocumentFormat.lon =>
                    '{schemaVersion:"cockpit.test/v2" kind:case '
                        'id:myCase steps:[]}',
                  CockpitDocumentFormat.json =>
                    '{\n  "schemaVersion": "cockpit.test/v2",\n'
                        '  "kind": "case"\n}',
                  CockpitDocumentFormat.yaml =>
                    'schemaVersion: cockpit.test/v2\nkind: case\n'
                        'id: myCase\nsteps: []',
                },
                hintStyle: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.4,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

final class _EditorStateLabel extends StatelessWidget {
  const _EditorStateLabel({super.key, required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }
}

final class _ValidationBar extends StatelessWidget {
  const _ValidationBar({required this.validation});

  final DocumentValidation validation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = validation.valid
        ? context.consoleColors.success
        : theme.colorScheme.error;
    final icon = validation.valid
        ? LucideIcons.checkCircle2
        : LucideIcons.xCircle;

    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        border: Border(bottom: BorderSide(color: color.withValues(alpha: 0.2))),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 8),
                Text(
                  validation.valid ? 'Valid document' : 'Validation failed',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                if (validation.errors.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${validation.errors.length} error${validation.errors.length > 1 ? "s" : ""}',
                    style: TextStyle(fontSize: 11, color: color),
                  ),
                ],
                if (validation.warnings.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${validation.warnings.length} warning${validation.warnings.length > 1 ? "s" : ""}',
                    style: TextStyle(fontSize: 11, color: color),
                  ),
                ],
              ],
            ),
            if (validation.errors.isNotEmpty) ...[
              const SizedBox(height: 6),
              for (final error in validation.errors.take(5))
                Padding(
                  padding: const EdgeInsets.only(left: 22, bottom: 2),
                  child: Text(
                    error,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.error,
                      height: 1.4,
                    ),
                  ),
                ),
            ],
            if (validation.warnings.isNotEmpty) ...[
              const SizedBox(height: 4),
              for (final warning in validation.warnings.take(3))
                Padding(
                  padding: const EdgeInsets.only(left: 22, bottom: 2),
                  child: Text(
                    warning,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
