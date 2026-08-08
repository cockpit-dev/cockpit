import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/todo_app_service.dart';
import '../../model/todo_priority.dart';
import '../../model/todo_tag.dart';
import '../../model/todo_task.dart';
import '../theme/orbit_todo_theme.dart';
import '../widgets/editorial_section.dart';

final class TaskEditorScreen extends StatefulWidget {
  const TaskEditorScreen({required this.service, this.task, super.key});

  final TodoAppService service;
  final TodoTask? task;

  @override
  State<TaskEditorScreen> createState() => _TaskEditorScreenState();
}

final class _TaskEditorScreenState extends State<TaskEditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late TodoPriority _priority;
  DateTime? _dueAt;
  late final Set<String> _selectedTagIds;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _titleController = TextEditingController(text: task?.title ?? '');
    _notesController = TextEditingController(text: task?.notes ?? '');
    _notesController.addListener(_handleNotesChanged);
    _priority = task?.priority ?? TodoPriority.medium;
    _dueAt = task?.dueAt;
    _selectedTagIds = task?.tagIds.toSet() ?? <String>{};
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (widget.service.availableTags.isEmpty &&
          !widget.service.isLoadingTags) {
        unawaited(widget.service.loadTags());
      }
    });
  }

  @override
  void dispose() {
    _notesController.removeListener(_handleNotesChanged);
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _handleNotesChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _save() async {
    widget.service.editDraft(
      title: _titleController.text,
      notes: _notesController.text,
      priority: _priority,
      dueAt: () => _dueAt,
      selectedTagIds: _selectedTagIds.toList(growable: false),
    );
    final savedTask = await widget.service.submitDraft(
      existingTaskId: widget.task?.id,
    );
    if (savedTask == null || !mounted) {
      return;
    }

    Navigator.of(context).pop(savedTask.id);
  }

  void _selectDuePreset(String preset) {
    final today = DateTime.now();
    setState(() {
      _dueAt = switch (preset) {
        'none' => null,
        'today' => DateTime(today.year, today.month, today.day, 17),
        'tomorrow' => DateTime(today.year, today.month, today.day + 1, 17),
        _ => _dueAt,
      };
    });
  }

  void _clearNotes() {
    _notesController.clear();
  }

  void _goBack() {
    Navigator.of(context).pop();
  }

  void _toggleTag(String tagId) {
    setState(() {
      if (_selectedTagIds.contains(tagId)) {
        _selectedTagIds.remove(tagId);
      } else {
        _selectedTagIds.add(tagId);
      }
    });
  }

  Future<void> _createTag() async {
    final createdTag = await showModalBottomSheet<TodoTag>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _CreateTagSheet(service: widget.service),
    );
    if (createdTag == null || !mounted) {
      return;
    }
    setState(() {
      _selectedTagIds.add(createdTag.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final editorState = widget.service.editorState;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return AnimatedBuilder(
      animation: widget.service,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            leading: Semantics(
              label: 'Back',
              button: true,
              excludeSemantics: true,
              onTap: _goBack,
              child: BackButton(onPressed: _goBack),
            ),
            title: Text(widget.task == null ? 'Create task' : 'Edit task'),
          ),
          body: DecoratedBox(
            decoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
              children: <Widget>[
                EditorialSection(
                  padding: const EdgeInsets.fromLTRB(18, 26, 18, 26),
                  backgroundColor: theme.editorialMutedSurfaceColor,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.task == null ? 'TASK' : 'EDIT',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.task == null
                            ? 'Capture the next item.'
                            : 'Adjust scope, timing, or notes.',
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Keep title, urgency, and due date explicit so the task remains easy to scan in both manual use and AI validation.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                EditorialSection(
                  padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'TASK',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          letterSpacing: 0.95,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text('Task', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 6),
                      Text(
                        'Write the shortest title that still survives search and handoff later.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        key: const ValueKey<String>('task-title-field'),
                        controller: _titleController,
                        decoration: InputDecoration(
                          labelText: 'Task title',
                          errorText:
                              editorState.validationMessage ==
                                  'Task title is required.'
                              ? editorState.validationMessage
                              : null,
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        key: const ValueKey<String>('task-notes-field'),
                        controller: _notesController,
                        minLines: 4,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                          hintText:
                              'Add context, handoff details, or validation notes.',
                        ),
                      ),
                      if (_notesController.text.trim().isNotEmpty) ...<Widget>[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _clearNotes,
                            icon: const Icon(Icons.clear_rounded),
                            label: const Text('Clear notes'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                EditorialSection(
                  padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'SCHEDULING',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          letterSpacing: 0.95,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Priority and due date',
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Use urgency for ordering and a due date only when the task is truly time-bound.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text('Priority', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: TodoPriority.values
                            .map(
                              (priority) => Semantics(
                                identifier:
                                    'task-editor-priority-${priority.name}',
                                child: ChoiceChip(
                                  selected: _priority == priority,
                                  label: Text(priority.name.toUpperCase()),
                                  onSelected: (_) {
                                    setState(() {
                                      _priority = priority;
                                    });
                                  },
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                      const SizedBox(height: 18),
                      Semantics(
                        container: true,
                        identifier: 'task-editor-due-section',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('Due date', style: theme.textTheme.titleSmall),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: <Widget>[
                                Semantics(
                                  identifier: 'task-editor-due-none',
                                  child: ChoiceChip(
                                    selected: _dueAt == null,
                                    label: const Text('No date'),
                                    onSelected: (_) => _selectDuePreset('none'),
                                  ),
                                ),
                                Semantics(
                                  identifier: 'task-editor-due-today',
                                  child: ChoiceChip(
                                    selected:
                                        _dueAt != null &&
                                        _dueAt!
                                                .difference(DateTime.now())
                                                .inDays ==
                                            0,
                                    label: const Text('Today'),
                                    onSelected: (_) =>
                                        _selectDuePreset('today'),
                                  ),
                                ),
                                Semantics(
                                  identifier: 'task-editor-due-tomorrow',
                                  child: ChoiceChip(
                                    selected:
                                        _dueAt != null &&
                                        _dueAt!
                                                .difference(DateTime.now())
                                                .inDays ==
                                            1,
                                    label: const Text('Tomorrow'),
                                    onSelected: (_) =>
                                        _selectDuePreset('tomorrow'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                EditorialSection(
                  padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'TAGS',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          letterSpacing: 0.95,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Tags and ownership',
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Use tags to isolate domains such as backend, design, or release so search and AI validation can narrow the board quickly.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (widget.service.availableTags.isEmpty) ...<Widget>[
                        Text(
                          widget.service.isLoadingTags
                              ? 'Loading tags…'
                              : 'No tags yet. Create the first one for this task.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ] else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: widget.service.availableTags
                              .map(
                                (tag) => FilterChip(
                                  selected: _selectedTagIds.contains(tag.id),
                                  label: Text(tag.name),
                                  onSelected: (_) => _toggleTag(tag.id),
                                ),
                              )
                              .toList(growable: false),
                        ),
                      if (widget.service.tagsErrorMessage != null) ...<Widget>[
                        const SizedBox(height: 12),
                        Text(
                          widget.service.tagsErrorMessage!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _createTag,
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        label: const Text('Create tag'),
                      ),
                    ],
                  ),
                ),
                if (editorState.validationMessage != null &&
                    editorState.validationMessage !=
                        'Task title is required.') ...<Widget>[
                  const SizedBox(height: 24),
                  EditorialSection(
                    leadingAccentColor: colorScheme.error,
                    backgroundColor: colorScheme.errorContainer
                        .withAlphaFraction(0.82),
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                    child: Text(
                      editorState.validationMessage!,
                      style: TextStyle(color: colorScheme.onErrorContainer),
                    ),
                  ),
                ],
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: FilledButton.icon(
                onPressed: editorState.isSaving ? null : _save,
                icon: const Icon(Icons.check_rounded),
                label: Text(widget.task == null ? 'Save task' : 'Save changes'),
              ),
            ),
          ),
        );
      },
    );
  }
}

final class _CreateTagSheet extends StatefulWidget {
  const _CreateTagSheet({required this.service});

  final TodoAppService service;

  @override
  State<_CreateTagSheet> createState() => _CreateTagSheetState();
}

final class _CreateTagSheetState extends State<_CreateTagSheet> {
  late final TextEditingController _controller;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final normalizedName = _controller.text.trim();
    if (normalizedName.isEmpty) {
      setState(() {
        _errorMessage = 'Tag name is required.';
      });
      return;
    }
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      final createdTag = await widget.service.createTag(name: normalizedName);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(createdTag);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSaving = false;
        _errorMessage = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Create tag', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Create one reusable label and immediately attach it to this task.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Tag name',
                hintText: 'Backend',
                errorText: _errorMessage,
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _submit,
                icon: const Icon(Icons.check_rounded),
                label: Text(_isSaving ? 'Creating…' : 'Create tag'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
