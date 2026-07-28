import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/todo_app_service.dart';
import '../../app/todo_list_state.dart';
import '../../model/todo_filter.dart';
import '../../model/todo_priority.dart';
import '../../model/todo_settings.dart';
import '../../model/todo_tag.dart';
import '../../model/todo_task.dart';
import '../../model/todo_task_sync_status.dart';
import '../theme/orbit_todo_theme.dart';
import '../widgets/collection_overview_card.dart';
import '../widgets/editorial_section.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/planning_surface_card.dart';
import '../widgets/task_filter_bar.dart';
import '../widgets/task_list_item.dart';

final class TodoCollectionScreen extends StatefulWidget {
  const TodoCollectionScreen({
    required this.routeName,
    required this.title,
    required this.baseFilter,
    required this.navigationIndex,
    required this.service,
    required this.onOpenEditor,
    required this.onOpenTask,
    required this.onOpenSettings,
    required this.onNavigateToIndex,
    super.key,
  });

  final String routeName;
  final String title;
  final TodoFilter baseFilter;
  final int navigationIndex;
  final TodoAppService service;
  final Future<String?> Function() onOpenEditor;
  final Future<void> Function(TodoTask task) onOpenTask;
  final Future<void> Function() onOpenSettings;
  final void Function(int index) onNavigateToIndex;

  @override
  State<TodoCollectionScreen> createState() => _TodoCollectionScreenState();
}

final class _TodoCollectionScreenState extends State<TodoCollectionScreen> {
  late final TextEditingController _searchController;
  late final ScrollController _scrollController;
  bool _highPriorityOnly = false;
  bool _conflictsOnly = false;
  late final Set<String> _selectedTagIds;
  final Set<String> _selectedTaskIds = <String>{};
  double _planningZoom = 1.0;
  double _planningZoomAtStart = 1.0;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.baseFilter.query);
    _scrollController = ScrollController();
    _highPriorityOnly = widget.baseFilter.priorities.contains(
      TodoPriority.high,
    );
    _conflictsOnly = widget.baseFilter.syncStatuses.contains(
      TodoTaskSyncStatus.conflicted,
    );
    _selectedTagIds = widget.baseFilter.tagIds.toSet();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (widget.service.availableTags.isEmpty &&
          !widget.service.isLoadingTags) {
        widget.service.loadTags();
      }
      widget.service.loadTasks(_effectiveFilter());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  TodoFilter _effectiveFilter() {
    final completionFilter =
        widget.routeName == '/inbox' &&
            widget.service.settingsState.settings.showCompletedInInbox
        ? TodoCompletionFilter.all
        : widget.baseFilter.completionFilter;
    return TodoFilter(
      query: _searchController.text,
      completionFilter: completionFilter,
      priorities: _highPriorityOnly
          ? const <TodoPriority>{TodoPriority.high}
          : widget.baseFilter.priorities,
      tagIds: _selectedTagIds,
      syncStatuses: _conflictsOnly
          ? const <TodoTaskSyncStatus>{TodoTaskSyncStatus.conflicted}
          : widget.baseFilter.syncStatuses,
      includeDeleted: widget.baseFilter.includeDeleted,
      onlyDueToday: widget.baseFilter.onlyDueToday,
    );
  }

  bool get _selectionMode => widget.service.listState.tasks.any(
    (task) => _selectedTaskIds.contains(task.id),
  );

  bool _canManualReorder(TodoSettings settings) {
    return widget.routeName == '/inbox' &&
        settings.sortMode == TodoSortMode.manual &&
        _searchController.text.trim().isEmpty &&
        !_highPriorityOnly &&
        !_conflictsOnly &&
        _selectedTagIds.isEmpty;
  }

  Future<void> _refreshCurrentFilter() {
    return widget.service.updateFilter(_effectiveFilter());
  }

  void _toggleTagFilter(String tagId) {
    setState(() {
      if (_selectedTagIds.contains(tagId)) {
        _selectedTagIds.remove(tagId);
      } else {
        _selectedTagIds.add(tagId);
      }
    });
    _refreshCurrentFilter();
  }

  void _clearTagFilters() {
    if (_selectedTagIds.isEmpty) {
      return;
    }
    setState(_selectedTagIds.clear);
    _refreshCurrentFilter();
  }

  Future<void> _openEditor() async {
    final savedTaskId = await widget.onOpenEditor();
    if (mounted) {
      await widget.service.loadTasks(_effectiveFilter(), savedTaskId);
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _handleTaskTap(TodoTask task) async {
    if (_selectionMode) {
      setState(() {
        if (_selectedTaskIds.contains(task.id)) {
          _selectedTaskIds.remove(task.id);
        } else {
          _selectedTaskIds.add(task.id);
        }
      });
      return;
    }

    await widget.onOpenTask(task);
    if (mounted) {
      await widget.service.loadTasks(_effectiveFilter());
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _openSettings() async {
    await widget.onOpenSettings();
    if (!mounted) {
      return;
    }
    await widget.service.loadTasks(_effectiveFilter());
    if (mounted) {
      setState(() {});
    }
  }

  void _handleTaskLongPress(TodoTask task) {
    setState(() {
      _selectedTaskIds.add(task.id);
    });
  }

  Future<void> _quickCompleteTask(TodoTask task) {
    return widget.service.setTaskCompleted(
      taskId: task.id,
      isCompleted: !task.isCompleted,
    );
  }

  List<TodoTask> _selectedTasks(List<TodoTask> tasks) {
    return tasks
        .where((task) => _selectedTaskIds.contains(task.id))
        .toList(growable: false);
  }

  bool _allFilteredTasksSelected(List<TodoTask> tasks) {
    return tasks.isNotEmpty &&
        tasks.every((task) => _selectedTaskIds.contains(task.id));
  }

  void _selectAllFilteredTasks(List<TodoTask> tasks) {
    setState(() {
      _selectedTaskIds.addAll(tasks.map((task) => task.id));
    });
  }

  Widget _selectionActionButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[Icon(icon), const SizedBox(width: 8), Text(label)],
      ),
    );
  }

  Future<void> _deleteSelectedTasks(List<TodoTask> tasks) async {
    final selectedTasks = _selectedTasks(tasks);
    if (selectedTasks.isEmpty) {
      return;
    }
    final confirmed = await _showDeleteSelectionDialog(selectedTasks);
    if (confirmed != true) {
      return;
    }

    final deleted = await widget.service.deleteTasks(
      selectedTasks.map((task) => task.id).toList(growable: false),
    );
    if (deleted && mounted) {
      setState(_selectedTaskIds.clear);
    }
  }

  Future<void> _completeSelectedTasks(List<TodoTask> tasks) async {
    final selectedTasks = _selectedTasks(tasks);
    if (selectedTasks.isEmpty) {
      return;
    }
    final shouldComplete = selectedTasks.any((task) => !task.isCompleted);
    final updated = await widget.service.setTasksCompleted(
      taskIds: selectedTasks.map((task) => task.id).toList(growable: false),
      isCompleted: shouldComplete,
    );
    if (updated && mounted) {
      setState(_selectedTaskIds.clear);
    }
  }

  Future<void> _changeSelectedPriority(List<TodoTask> tasks) async {
    final selectedTasks = _selectedTasks(tasks);
    if (selectedTasks.isEmpty) {
      return;
    }
    final nextPriority = await showModalBottomSheet<TodoPriority>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.72,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Update priority',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Apply one priority to ${selectedTasks.length} selected tasks.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...TodoPriority.values.map(
                      (priority) => Material(
                        color: Colors.transparent,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_prioritySheetTitle(priority)),
                          subtitle: Text(_prioritySheetSubtitle(priority)),
                          trailing: Icon(
                            Icons.flag_rounded,
                            color: _priorityColor(colorScheme, priority),
                          ),
                          onTap: () => Navigator.of(context).pop(priority),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (nextPriority == null) {
      return;
    }

    final updated = await widget.service.updateTasksPriority(
      taskIds: selectedTasks.map((task) => task.id).toList(growable: false),
      priority: nextPriority,
    );
    if (updated && mounted) {
      setState(_selectedTaskIds.clear);
    }
  }

  Future<void> _changeSelectedDueDate(List<TodoTask> tasks) async {
    final selectedTasks = _selectedTasks(tasks);
    if (selectedTasks.isEmpty) {
      return;
    }
    final dueAt = await showModalBottomSheet<DateTime?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final today = DateTime.now();
        final presets = <({String label, String detail, DateTime? dueAt})>[
          (
            label: 'No date',
            detail: 'Clear the schedule and return the tasks to open planning.',
            dueAt: null,
          ),
          (
            label: 'Today',
            detail: 'Anchor the selected tasks to today at 17:00.',
            dueAt: DateTime(today.year, today.month, today.day, 17),
          ),
          (
            label: 'Tomorrow',
            detail: 'Move the selected tasks into tomorrow’s review lane.',
            dueAt: DateTime(today.year, today.month, today.day + 1, 17),
          ),
          (
            label: 'Next week',
            detail:
                'Push the selection one week forward without changing scope.',
            dueAt: DateTime(today.year, today.month, today.day + 7, 17),
          ),
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Update due date', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Apply one due date preset to ${selectedTasks.length} selected tasks.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                ...presets.map(
                  (preset) => Material(
                    color: Colors.transparent,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(preset.label),
                      subtitle: Text(preset.detail),
                      trailing: Icon(
                        preset.dueAt == null
                            ? Icons.event_busy_rounded
                            : Icons.event_available_rounded,
                        color: colorScheme.primary,
                      ),
                      onTap: () => Navigator.of(context).pop(preset.dueAt),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    final updated = await widget.service.updateTasksDueDate(
      taskIds: selectedTasks.map((task) => task.id).toList(growable: false),
      dueAt: dueAt,
    );
    if (updated && mounted) {
      setState(_selectedTaskIds.clear);
    }
  }

  Future<void> _changeSelectedTags(List<TodoTask> tasks) async {
    final selectedTasks = _selectedTasks(tasks);
    if (selectedTasks.isEmpty) {
      return;
    }
    final nextTagIds = await showModalBottomSheet<List<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _BatchTagSheet(
        selectedTaskCount: selectedTasks.length,
        availableTags: widget.service.availableTags,
        initialSelectedTagIds: selectedTasks
            .expand((task) => task.tagIds)
            .toSet()
            .toList(growable: false),
        onCreateTag: (name) => widget.service.createTag(name: name),
      ),
    );
    if (nextTagIds == null) {
      return;
    }

    final updated = await widget.service.updateTasksTags(
      taskIds: selectedTasks.map((task) => task.id).toList(growable: false),
      tagIds: nextTagIds,
    );
    if (updated && mounted) {
      setState(_selectedTaskIds.clear);
    }
  }

  Future<void> _duplicateSelectedTasks(List<TodoTask> tasks) async {
    final selectedTasks = _selectedTasks(tasks);
    if (selectedTasks.isEmpty) {
      return;
    }
    final result = await showModalBottomSheet<_DuplicateSelectionResult>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) =>
          _DuplicateSelectionSheet(selectedTaskCount: selectedTasks.length),
    );
    if (result == null) {
      return;
    }

    final duplicated = await widget.service.duplicateTasks(
      taskIds: selectedTasks.map((task) => task.id).toList(growable: false),
      titlePrefix: result.titlePrefix,
      carryNotes: result.carryNotes,
      carryDueDate: result.carryDueDate,
      carryTags: result.carryTags,
    );
    if (duplicated.isNotEmpty && mounted) {
      setState(_selectedTaskIds.clear);
    }
  }

  void _clearSelection() {
    setState(_selectedTaskIds.clear);
  }

  Future<bool?> _showDeleteSelectionDialog(List<TodoTask> selectedTasks) {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final previewTasks = selectedTasks.take(3).toList(growable: false);
        return AlertDialog(
          title: Text('Delete ${selectedTasks.length} tasks?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'This removes the selected tasks from the visible board and keeps one grouped undo step.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                ...previewTasks.map(
                  (task) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('• ${task.title}'),
                  ),
                ),
                if (selectedTasks.length > previewTasks.length)
                  Text(
                    '+${selectedTasks.length - previewTasks.length} more tasks',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete tasks'),
            ),
          ],
        );
      },
    );
  }

  String _prioritySheetTitle(TodoPriority priority) {
    return switch (priority) {
      TodoPriority.low => 'Low priority',
      TodoPriority.medium => 'Medium priority',
      TodoPriority.high => 'High priority',
      TodoPriority.urgent => 'Urgent priority',
    };
  }

  String _prioritySheetSubtitle(TodoPriority priority) {
    return switch (priority) {
      TodoPriority.low => 'Keep it visible without interrupting the queue.',
      TodoPriority.medium => 'Default working level for normal delivery tasks.',
      TodoPriority.high => 'Move the selection into the active review lane.',
      TodoPriority.urgent => 'Escalate the selection to the top decision tier.',
    };
  }

  Color _priorityColor(ColorScheme colorScheme, TodoPriority priority) {
    return switch (priority) {
      TodoPriority.low => colorScheme.secondary,
      TodoPriority.medium => colorScheme.tertiary,
      TodoPriority.high => colorScheme.primary,
      TodoPriority.urgent => colorScheme.error,
    };
  }

  void _handlePlanningScaleStart(ScaleStartDetails details) {
    _planningZoomAtStart = _planningZoom;
  }

  void _handlePlanningScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      _planningZoom = (_planningZoomAtStart * details.scale).clamp(0.9, 1.75);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.service,
      builder: (context, _) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final listState = widget.service.listState;
        final settingsState = widget.service.settingsState;
        final tasks = listState.tasks;
        final selectedTasks = _selectedTasks(tasks);
        final selectionCount = selectedTasks.length;
        final allVisibleSelected = _allFilteredTasksSelected(tasks);
        final shouldCompleteSelection = selectedTasks.any(
          (task) => !task.isCompleted,
        );
        final focusedTask = _taskById(tasks, listState.focusedTaskId);
        final showEmptyState =
            !listState.isLoading &&
            listState.errorMessage == null &&
            tasks.isEmpty;
        final activeCount = tasks.where((task) => !task.isCompleted).length;
        final dueTodayCount = tasks.where(_isDueToday).length;
        final priorityCount = tasks
            .where(
              (task) =>
                  !task.isCompleted &&
                  (task.priority == TodoPriority.high ||
                      task.priority == TodoPriority.urgent),
            )
            .length;
        final queueBrief = _queueBrief(
          activeCount: activeCount,
          dueTodayCount: dueTodayCount,
          priorityCount: priorityCount,
          conflictTaskCount: widget.service.syncState.conflictTaskCount,
        );
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 74,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  'SUPER COCKPIT',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.35,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            actions: <Widget>[
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 4),
                child: TextButton.icon(
                  key: const ValueKey<String>('open-task-editor-action'),
                  onPressed: _openEditor,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New task'),
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.onSurface,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    textStyle: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.15,
                    ),
                    shape: const RoundedRectangleBorder(),
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey<String>('open-settings-action'),
                tooltip: 'Settings',
                onPressed: _openSettings,
                icon: const Icon(Icons.tune_rounded),
              ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                border: Border(
                  top: BorderSide(
                    color: colorScheme.outlineVariant.withAlphaFraction(0.82),
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: _NavigationButton(
                        icon: Icons.inbox_rounded,
                        label: 'Inbox',
                        selected: widget.navigationIndex == 0,
                        onPressed: () => widget.onNavigateToIndex(0),
                      ),
                    ),
                    Expanded(
                      child: _NavigationButton(
                        icon: Icons.calendar_today_rounded,
                        label: 'Today',
                        selected: widget.navigationIndex == 1,
                        onPressed: () => widget.onNavigateToIndex(1),
                      ),
                    ),
                    Expanded(
                      child: _NavigationButton(
                        icon: Icons.task_alt_rounded,
                        label: 'Completed',
                        selected: widget.navigationIndex == 2,
                        onPressed: () => widget.onNavigateToIndex(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          body: DecoratedBox(
            decoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
            child: Column(
              children: <Widget>[
                if (listState.canUndoDelete)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: EditorialSection(
                      backgroundColor: colorScheme.secondaryContainer
                          .withAlphaFraction(0.82),
                      leadingAccentColor: colorScheme.secondary,
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.undo_rounded,
                            color: colorScheme.onSecondaryContainer,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _undoDeleteBannerMessage(listState),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: widget.service.undoDelete,
                            child: const Text('Undo'),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_selectionMode)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    child: EditorialSection(
                      backgroundColor: colorScheme.secondaryContainer
                          .withAlphaFraction(0.86),
                      leadingAccentColor: colorScheme.primary,
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Icon(
                                Icons.select_all_rounded,
                                color: colorScheme.onSecondaryContainer,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '$selectionCount selected',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: colorScheme.onSecondaryContainer,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Clear selection',
                                onPressed: _clearSelection,
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: <Widget>[
                              _selectionActionButton(
                                onPressed: allVisibleSelected
                                    ? null
                                    : () => _selectAllFilteredTasks(tasks),
                                icon: Icons.done_all_rounded,
                                label: 'All results',
                              ),
                              _selectionActionButton(
                                onPressed: () => _duplicateSelectedTasks(tasks),
                                icon: Icons.copy_all_rounded,
                                label: 'Duplicate',
                              ),
                              _selectionActionButton(
                                onPressed: () => _changeSelectedPriority(tasks),
                                icon: Icons.flag_rounded,
                                label: 'Priority',
                              ),
                              _selectionActionButton(
                                onPressed: () => _changeSelectedDueDate(tasks),
                                icon: Icons.event_available_rounded,
                                label: 'Schedule',
                              ),
                              _selectionActionButton(
                                onPressed: () => _changeSelectedTags(tasks),
                                icon: Icons.sell_rounded,
                                label: 'Tags',
                              ),
                              _selectionActionButton(
                                onPressed: () => _completeSelectedTasks(tasks),
                                icon: shouldCompleteSelection
                                    ? Icons.task_alt_rounded
                                    : Icons.undo_rounded,
                                label: shouldCompleteSelection
                                    ? 'Complete'
                                    : 'Reopen',
                              ),
                              FilledButton.tonalIcon(
                                onPressed: () => _deleteSelectedTasks(tasks),
                                icon: const Icon(Icons.delete_sweep_rounded),
                                label: const Text('Delete'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () =>
                        widget.service.loadTasks(_effectiveFilter()),
                    child: ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
                      children: <Widget>[
                        if (focusedTask != null) ...<Widget>[
                          EditorialSection(
                            backgroundColor: colorScheme.primaryContainer
                                .withAlphaFraction(0.84),
                            leadingAccentColor: colorScheme.primary,
                            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: <Widget>[
                                Expanded(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        'LATEST UPDATE',
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                              color: colorScheme
                                                  .onPrimaryContainer
                                                  .withAlphaFraction(0.72),
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.9,
                                              height: 1,
                                            ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        focusedTask.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                              color: colorScheme
                                                  .onPrimaryContainer,
                                              fontWeight: FontWeight.w700,
                                              height: 1.08,
                                            ),
                                      ),
                                      if (focusedTask
                                          .notes
                                          .isNotEmpty) ...<Widget>[
                                        const SizedBox(height: 4),
                                        Text(
                                          focusedTask.notes,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: colorScheme
                                                    .onPrimaryContainer
                                                    .withAlphaFraction(0.74),
                                                height: 1.2,
                                              ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      left: BorderSide(
                                        color: colorScheme.onPrimaryContainer
                                            .withAlphaFraction(0.1),
                                      ),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 10),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        Semantics(
                                          label:
                                              'Open task ${focusedTask.title}',
                                          button: true,
                                          child: TextButton(
                                            key: const ValueKey<String>(
                                              'latest-task-open-action',
                                            ),
                                            onPressed: () {
                                              widget.onOpenTask(focusedTask);
                                            },
                                            style: TextButton.styleFrom(
                                              foregroundColor: colorScheme
                                                  .onPrimaryContainer,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 6,
                                                  ),
                                              minimumSize: Size.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              textStyle: theme
                                                  .textTheme
                                                  .labelMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                    letterSpacing: 0.12,
                                                  ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: <Widget>[
                                                const Text('Open'),
                                                const SizedBox(width: 4),
                                                Icon(
                                                  Icons.arrow_outward_rounded,
                                                  size: 15,
                                                  color: colorScheme
                                                      .onPrimaryContainer,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        IconButton(
                                          tooltip: 'Dismiss latest update',
                                          onPressed:
                                              widget.service.dismissFocusedTask,
                                          visualDensity: VisualDensity.compact,
                                          splashRadius: 16,
                                          constraints:
                                              const BoxConstraints.tightFor(
                                                width: 32,
                                                height: 32,
                                              ),
                                          padding: EdgeInsets.zero,
                                          icon: Icon(
                                            Icons.close_rounded,
                                            size: 17,
                                            color: colorScheme
                                                .onPrimaryContainer
                                                .withAlphaFraction(0.68),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                        ],
                        if (listState.errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 18),
                            child: EditorialSection(
                              backgroundColor: colorScheme.errorContainer
                                  .withAlphaFraction(0.88),
                              leadingAccentColor: colorScheme.error,
                              padding: const EdgeInsets.fromLTRB(
                                18,
                                16,
                                18,
                                16,
                              ),
                              child: Row(
                                children: <Widget>[
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    color: colorScheme.onErrorContainer,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      listState.errorMessage!,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: colorScheme.onErrorContainer,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (listState.isLoading)
                          const Padding(
                            padding: EdgeInsets.only(top: 32),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (tasks.isEmpty) ...<Widget>[
                          CollectionOverviewCard(
                            eyebrow: _eyebrowForRoute(),
                            headline: _headlineForRoute(),
                            message: _messageForRoute(),
                            statusBanner: showEmptyState
                                ? 'Fresh canvas'
                                : null,
                            dense: showEmptyState,
                            trailing: _OverviewActionRail(
                              modeTitle: settingsState.settings.compactMode
                                  ? 'Compact'
                                  : 'Comfort',
                              modeSubtitle:
                                  'Sorted ${settingsState.settings.sortMode.name}',
                              onCreateTask: _openEditor,
                            ),
                            metrics: <CollectionMetricData>[
                              CollectionMetricData(
                                label: 'Open',
                                value: '$activeCount',
                                caption: 'Active work in the current view.',
                                icon: Icons.stacked_line_chart_rounded,
                              ),
                              CollectionMetricData(
                                label: 'Today',
                                value: '$dueTodayCount',
                                caption: 'Tasks due before the day closes.',
                                icon: Icons.watch_later_rounded,
                              ),
                              CollectionMetricData(
                                label: 'Priority',
                                value: '$priorityCount',
                                caption: 'High and urgent tasks in the queue.',
                                icon: Icons.priority_high_rounded,
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                        ],
                        if (!listState.isLoading && tasks.isEmpty)
                          EmptyStateView(
                            title: 'No tasks yet',
                            message:
                                'Add the first task to establish the queue, then use search, filters, and detail editing as the list grows.',
                            actionLabel: 'Create task',
                            onAction: _openEditor,
                          )
                        else if (!listState.isLoading) ...<Widget>[
                          _QueueBriefStrip(summary: queueBrief),
                          const SizedBox(height: 18),
                          TaskFilterBar(
                            searchController: _searchController,
                            highPriorityOnly: _highPriorityOnly,
                            conflictsOnly: _conflictsOnly,
                            availableTags: widget.service.availableTags,
                            selectedTagIds: _selectedTagIds,
                            onSearchChanged: (_) {
                              widget.service.updateFilter(_effectiveFilter());
                            },
                            onHighPriorityChanged: (selected) {
                              setState(() {
                                _highPriorityOnly = selected;
                              });
                              widget.service.updateFilter(_effectiveFilter());
                            },
                            onConflictsOnlyChanged: (selected) {
                              setState(() {
                                _conflictsOnly = selected;
                              });
                              widget.service.updateFilter(_effectiveFilter());
                            },
                            onTagToggle: _toggleTagFilter,
                            onClearTagSelection: _clearTagFilters,
                          ),
                          const SizedBox(height: 18),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: <Widget>[
                                Text(
                                  'Task list',
                                  style: theme.textTheme.titleLarge,
                                ),
                                const Spacer(),
                                Text(
                                  '${tasks.length} visible',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildTaskList(
                            tasks: tasks,
                            settings: settingsState.settings,
                          ),
                          const SizedBox(height: 18),
                          CollectionOverviewCard(
                            eyebrow: _eyebrowForRoute(),
                            headline: _headlineForRoute(),
                            message: _messageForRoute(),
                            trailing: _OverviewActionRail(
                              modeTitle: settingsState.settings.compactMode
                                  ? 'Compact'
                                  : 'Comfort',
                              modeSubtitle:
                                  'Sorted ${settingsState.settings.sortMode.name}',
                              onCreateTask: _openEditor,
                            ),
                            metrics: <CollectionMetricData>[
                              CollectionMetricData(
                                label: 'Open',
                                value: '$activeCount',
                                caption: 'Active work in the current view.',
                                icon: Icons.stacked_line_chart_rounded,
                              ),
                              CollectionMetricData(
                                label: 'Today',
                                value: '$dueTodayCount',
                                caption: 'Tasks due before the day closes.',
                                icon: Icons.watch_later_rounded,
                              ),
                              CollectionMetricData(
                                label: 'Priority',
                                value: '$priorityCount',
                                caption: 'High and urgent tasks in the queue.',
                                icon: Icons.priority_high_rounded,
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          PlanningSurfaceCard(
                            tasks: tasks,
                            zoomLevel: _planningZoom,
                            onScaleStart: _handlePlanningScaleStart,
                            onScaleUpdate: _handlePlanningScaleUpdate,
                            onResetZoom: () {
                              setState(() {
                                _planningZoom = 1.0;
                              });
                            },
                          ),
                          if (_canManualReorder(
                            settingsState.settings,
                          )) ...<Widget>[
                            const SizedBox(height: 18),
                            _buildManualQueuePanel(
                              tasks: tasks,
                              compactMode: settingsState.settings.compactMode,
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isDueToday(TodoTask task) {
    final dueAt = task.dueAt;
    if (dueAt == null) {
      return false;
    }
    final now = DateTime.now();
    return dueAt.year == now.year &&
        dueAt.month == now.month &&
        dueAt.day == now.day;
  }

  String _eyebrowForRoute() {
    return switch (widget.routeName) {
      '/today' => 'Today',
      '/completed' => 'Completed',
      _ => 'Inbox',
    };
  }

  String _headlineForRoute() {
    return switch (widget.routeName) {
      '/today' => 'Today queue',
      '/completed' => 'Finished work',
      _ => 'Work queue',
    };
  }

  String _messageForRoute() {
    return switch (widget.routeName) {
      '/today' =>
        'Only the commitments due today stay in view, with search and priority filters ready for triage.',
      '/completed' =>
        'Closed tasks remain searchable, reversible, and ready for final review or archive cleanup.',
      _ =>
        'The main queue keeps due dates, urgency, and notes visible without burying the working surface in chrome.',
    };
  }

  String _undoDeleteBannerMessage(TodoListState listState) {
    final pendingTask = listState.pendingUndoTask;
    if (pendingTask != null) {
      return 'Removed "${pendingTask.title}" from the board.';
    }
    return 'Removed ${listState.pendingUndoCount} tasks from the board.';
  }

  String _queueBrief({
    required int activeCount,
    required int dueTodayCount,
    required int priorityCount,
    required int conflictTaskCount,
  }) {
    return 'Queue brief: $activeCount active / $dueTodayCount due today / '
        '$priorityCount priority / $conflictTaskCount conflicts';
  }

  Widget _buildTaskList({
    required List<TodoTask> tasks,
    required TodoSettings settings,
  }) {
    if (_canManualReorder(settings)) {
      return Column(
        children: tasks
            .map(
              (task) => _buildTaskRow(
                task: task,
                compactMode: settings.compactMode,
                isHighlighted:
                    task.id == widget.service.listState.focusedTaskId,
              ),
            )
            .toList(growable: false),
      );
    }

    return Column(
      children: tasks
          .map(
            (task) => _buildTaskRow(
              task: task,
              compactMode: settings.compactMode,
              isHighlighted: task.id == widget.service.listState.focusedTaskId,
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _buildTaskRow({
    required TodoTask task,
    required bool compactMode,
    required bool isHighlighted,
  }) {
    return _SwipeToDeleteTaskRow(
      taskId: task.id,
      onDismissed: () {
        widget.service.deleteTask(task.id);
      },
      child: TaskListItem(
        task: task,
        compactMode: compactMode,
        selectionMode: _selectionMode,
        isSelected: _selectedTaskIds.contains(task.id),
        isHighlighted: isHighlighted,
        onTap: () => _handleTaskTap(task),
        onLongPress: () => _handleTaskLongPress(task),
        onDoubleTap: () => _quickCompleteTask(task),
        onToggleCompleted: (value) {
          widget.service.setTaskCompleted(taskId: task.id, isCompleted: value);
        },
      ),
    );
  }

  Future<void> _moveTaskToIndex({
    required List<TodoTask> tasks,
    required String draggedTaskId,
    required int targetIndex,
  }) async {
    final oldIndex = tasks.indexWhere((task) => task.id == draggedTaskId);
    if (oldIndex == -1 ||
        targetIndex < 0 ||
        targetIndex >= tasks.length ||
        oldIndex == targetIndex) {
      return;
    }
    final newIndex = targetIndex > oldIndex ? targetIndex + 1 : targetIndex;
    await widget.service.reorderTasks(oldIndex: oldIndex, newIndex: newIndex);
  }

  TodoTask? _taskById(List<TodoTask> tasks, String? taskId) {
    if (taskId == null) {
      return null;
    }
    for (final task in tasks) {
      if (task.id == taskId) {
        return task;
      }
    }
    return null;
  }

  Widget _buildManualQueuePanel({
    required List<TodoTask> tasks,
    required bool compactMode,
  }) {
    return _ManualQueuePanel(
      tasks: tasks,
      compactMode: compactMode,
      onMoveToIndex: (draggedTaskId, targetIndex) => _moveTaskToIndex(
        tasks: tasks,
        draggedTaskId: draggedTaskId,
        targetIndex: targetIndex,
      ),
    );
  }
}

final class _QueueBriefStrip extends StatelessWidget {
  const _QueueBriefStrip({required this.summary});

  final String summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Semantics(
      container: true,
      label: 'Queue brief summary',
      child: EditorialSection(
        backgroundColor: colorScheme.primaryContainer.withAlphaFraction(0.52),
        leadingAccentColor: colorScheme.primary,
        padding: const EdgeInsets.fromLTRB(18, 13, 18, 13),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.auto_awesome_rounded,
              size: 20,
              color: colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                summary,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _SwipeToDeleteTaskRow extends StatefulWidget {
  const _SwipeToDeleteTaskRow({
    required this.taskId,
    required this.onDismissed,
    required this.child,
  });

  final String taskId;
  final VoidCallback onDismissed;
  final Widget child;

  @override
  State<_SwipeToDeleteTaskRow> createState() => _SwipeToDeleteTaskRowState();
}

final class _SwipeToDeleteTaskRowState extends State<_SwipeToDeleteTaskRow> {
  static const Duration _settleDuration = Duration(milliseconds: 170);
  static const double _dismissVelocity = 760;
  static const double _dismissThresholdFactor = 0.34;
  double _dragOffset = 0;
  bool _isDragging = false;
  bool _dismissScheduled = false;

  @override
  void didUpdateWidget(covariant _SwipeToDeleteTaskRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.taskId != widget.taskId) {
      _dragOffset = 0;
      _isDragging = false;
      _dismissScheduled = false;
    }
  }

  void _scheduleDismiss() {
    if (_dismissScheduled) {
      return;
    }
    _dismissScheduled = true;
    Future<void>.delayed(_settleDuration, () {
      if (mounted && _dismissScheduled) {
        widget.onDismissed();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth <= 0 ? 1.0 : constraints.maxWidth;
        final dismissThreshold = width * _dismissThresholdFactor;
        final fraction = _dragOffset / width;
        final showingBackground = _dragOffset.abs() > 1;
        return Stack(
          children: <Widget>[
            if (showingBackground)
              Positioned.fill(
                child: _DismissBackground(
                  alignment: _dragOffset >= 0
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  icon: Icons.delete_sweep_rounded,
                  label: 'Delete',
                ),
              ),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: (_) {
                _dismissScheduled = false;
                setState(() {
                  _isDragging = true;
                });
              },
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _dragOffset = (_dragOffset + details.delta.dx).clamp(
                    -width,
                    width,
                  );
                });
              },
              onHorizontalDragEnd: (details) {
                final shouldDismiss =
                    _dragOffset.abs() >= dismissThreshold ||
                    details.primaryVelocity!.abs() >= _dismissVelocity;
                setState(() {
                  _isDragging = false;
                  _dragOffset = shouldDismiss
                      ? (_dragOffset.isNegative ? -width : width)
                      : 0;
                });
                if (shouldDismiss) {
                  _scheduleDismiss();
                }
              },
              child: AnimatedSlide(
                duration: _isDragging ? Duration.zero : _settleDuration,
                curve: Curves.easeOutCubic,
                offset: Offset(fraction, 0),
                child: widget.child,
              ),
            ),
          ],
        );
      },
    );
  }
}

final class _OverviewActionRail extends StatelessWidget {
  const _OverviewActionRail({
    required this.modeTitle,
    required this.modeSubtitle,
    required this.onCreateTask,
  });

  final String modeTitle;
  final String modeSubtitle;
  final Future<void> Function() onCreateTask;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        OverviewBadge(title: modeTitle, subtitle: modeSubtitle),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onCreateTask,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Create task'),
        ),
      ],
    );
  }
}

final class _ManualQueuePanel extends StatefulWidget {
  const _ManualQueuePanel({
    required this.tasks,
    required this.compactMode,
    required this.onMoveToIndex,
  });

  final List<TodoTask> tasks;
  final bool compactMode;
  final Future<void> Function(String draggedTaskId, int targetIndex)
  onMoveToIndex;

  @override
  State<_ManualQueuePanel> createState() => _ManualQueuePanelState();
}

final class _ManualQueuePanelState extends State<_ManualQueuePanel> {
  String? _draggedTaskId;
  double _dragDeltaY = 0;

  void _clearDragState() {
    if (mounted) {
      setState(() {
        _draggedTaskId = null;
        _dragDeltaY = 0;
      });
    }
  }

  void _handleDragStart(String taskId) {
    setState(() {
      _draggedTaskId = taskId;
      _dragDeltaY = 0;
    });
  }

  void _handleDragUpdate(TodoTask task, DragUpdateDetails details) {
    if (_draggedTaskId != task.id) {
      return;
    }
    final stepExtent = widget.compactMode ? 104.0 : 116.0;
    _dragDeltaY += details.delta.dy;
    if (_dragDeltaY.abs() < stepExtent * 0.72) {
      setState(() {});
      return;
    }

    final currentIndex = widget.tasks.indexWhere(
      (candidate) => candidate.id == task.id,
    );
    if (currentIndex == -1) {
      _clearDragState();
      return;
    }

    final direction = _dragDeltaY.isNegative ? -1 : 1;
    final targetIndex = (currentIndex + direction).clamp(
      0,
      widget.tasks.length - 1,
    );
    _dragDeltaY = 0;
    if (targetIndex != currentIndex) {
      unawaited(widget.onMoveToIndex(task.id, targetIndex));
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return EditorialSection(
      backgroundColor: theme.editorialMutedSurfaceColor,
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Manual queue', style: theme.textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Drag tasks to set the next execution order.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: (widget.tasks.length * (widget.compactMode ? 92.0 : 104.0))
                .clamp(196.0, 372.0),
            child: ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: widget.tasks.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final task = widget.tasks[index];
                return Opacity(
                  opacity: _draggedTaskId == task.id ? 0.62 : 1,
                  child: _ManualQueueCard(
                    index: index,
                    task: task,
                    compactMode: widget.compactMode,
                    highlightDropTarget: _draggedTaskId == task.id,
                    dragHandle: _ManualQueueHandle(
                      label: 'Reorder task ${task.title}',
                      faded: _draggedTaskId == task.id,
                      onVerticalDragStart: (_) => _handleDragStart(task.id),
                      onVerticalDragUpdate: (details) =>
                          _handleDragUpdate(task, details),
                      onVerticalDragEnd: (_) => _clearDragState(),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

final class _BatchTagSheet extends StatefulWidget {
  const _BatchTagSheet({
    required this.selectedTaskCount,
    required this.availableTags,
    required this.initialSelectedTagIds,
    required this.onCreateTag,
  });

  final int selectedTaskCount;
  final List<TodoTag> availableTags;
  final List<String> initialSelectedTagIds;
  final Future<TodoTag> Function(String name) onCreateTag;

  @override
  State<_BatchTagSheet> createState() => _BatchTagSheetState();
}

final class _BatchTagSheetState extends State<_BatchTagSheet> {
  late final TextEditingController _newTagController;
  late List<TodoTag> _availableTags;
  late Set<String> _selectedTagIds;
  bool _isCreatingTag = false;
  String? _tagErrorMessage;

  @override
  void initState() {
    super.initState();
    _newTagController = TextEditingController();
    _availableTags = _sortTags(widget.availableTags);
    _selectedTagIds = widget.initialSelectedTagIds.toSet();
  }

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  List<TodoTag> _sortTags(List<TodoTag> tags) {
    final sorted = tags.toList(growable: false);
    sorted.sort((left, right) => left.name.compareTo(right.name));
    return sorted;
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
    final normalizedName = _newTagController.text.trim();
    if (normalizedName.isEmpty) {
      setState(() {
        _tagErrorMessage = 'Tag name is required.';
      });
      return;
    }

    setState(() {
      _isCreatingTag = true;
      _tagErrorMessage = null;
    });

    try {
      final createdTag = await widget.onCreateTag(normalizedName);
      if (!mounted) {
        return;
      }
      setState(() {
        _availableTags = _sortTags(<TodoTag>[..._availableTags, createdTag]);
        _selectedTagIds.add(createdTag.id);
        _newTagController.clear();
        _isCreatingTag = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isCreatingTag = false;
        _tagErrorMessage = error.toString();
      });
    }
  }

  List<String> _orderedSelectedTagIds() {
    return _availableTags
        .where((tag) => _selectedTagIds.contains(tag.id))
        .map((tag) => tag.id)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Update tags', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      Text(
                        'Choose the shared tag set that ${widget.selectedTaskCount} selected tasks should carry.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _newTagController,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _createTag(),
                        decoration: InputDecoration(
                          labelText: 'New tag',
                          errorText: _tagErrorMessage,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _isCreatingTag ? null : _createTag,
                          icon: _isCreatingTag
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colorScheme.primary,
                                  ),
                                )
                              : const Icon(Icons.add_rounded),
                          label: Text(
                            _isCreatingTag ? 'Creating…' : 'Create tag',
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_availableTags.isEmpty)
                        Text(
                          'Create the first tag to apply a shared context to the selection.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _availableTags
                              .map(
                                (tag) => FilterChip(
                                  selected: _selectedTagIds.contains(tag.id),
                                  label: Text(tag.name),
                                  onSelected: (_) => _toggleTag(tag.id),
                                ),
                              )
                              .toList(growable: false),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: <Widget>[
                  TextButton(
                    onPressed: _selectedTagIds.isEmpty
                        ? null
                        : () {
                            setState(_selectedTagIds.clear);
                          },
                    child: const Text('Clear all tags'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _isCreatingTag
                        ? null
                        : () => Navigator.of(
                            context,
                          ).pop(_orderedSelectedTagIds()),
                    icon: const Icon(Icons.sell_rounded),
                    label: const Text('Apply tags'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _DuplicateSelectionResult {
  const _DuplicateSelectionResult({
    required this.titlePrefix,
    required this.carryNotes,
    required this.carryDueDate,
    required this.carryTags,
  });

  final String titlePrefix;
  final bool carryNotes;
  final bool carryDueDate;
  final bool carryTags;
}

final class _DuplicateSelectionSheet extends StatefulWidget {
  const _DuplicateSelectionSheet({required this.selectedTaskCount});

  final int selectedTaskCount;

  @override
  State<_DuplicateSelectionSheet> createState() =>
      _DuplicateSelectionSheetState();
}

final class _DuplicateSelectionSheetState
    extends State<_DuplicateSelectionSheet> {
  late final TextEditingController _prefixController;
  bool _carryNotes = true;
  bool _carryDueDate = true;
  bool _carryTags = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _prefixController = TextEditingController(text: 'Copy');
  }

  @override
  void dispose() {
    _prefixController.dispose();
    super.dispose();
  }

  void _submit() {
    final normalizedPrefix = _prefixController.text.trim();
    if (normalizedPrefix.isEmpty) {
      setState(() {
        _errorMessage = 'Title prefix is required.';
      });
      return;
    }

    Navigator.of(context).pop(
      _DuplicateSelectionResult(
        titlePrefix: normalizedPrefix,
        carryNotes: _carryNotes,
        carryDueDate: _carryDueDate,
        carryTags: _carryTags,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Duplicate tasks',
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Create ${widget.selectedTaskCount} new tasks with a shared prefix so the copied work stays easy to locate and verify.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _prefixController,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Title prefix',
                          errorText: _errorMessage,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Material(
                        color: Colors.transparent,
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Carry notes'),
                          subtitle: const Text(
                            'Keep implementation context and handoff detail.',
                          ),
                          value: _carryNotes,
                          onChanged: (value) {
                            setState(() {
                              _carryNotes = value;
                            });
                          },
                        ),
                      ),
                      Material(
                        color: Colors.transparent,
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Carry due date'),
                          subtitle: const Text(
                            'Preserve schedule pressure from the source tasks.',
                          ),
                          value: _carryDueDate,
                          onChanged: (value) {
                            setState(() {
                              _carryDueDate = value;
                            });
                          },
                        ),
                      ),
                      Material(
                        color: Colors.transparent,
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Carry tags'),
                          subtitle: const Text(
                            'Keep shared ownership markers such as backend or design.',
                          ),
                          value: _carryTags,
                          onChanged: (value) {
                            setState(() {
                              _carryTags = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.copy_all_rounded),
                  label: const Text('Create duplicates'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _ManualQueueCard extends StatelessWidget {
  const _ManualQueueCard({
    required this.index,
    required this.task,
    required this.compactMode,
    required this.highlightDropTarget,
    required this.dragHandle,
  });

  final int index;
  final TodoTask task;
  final bool compactMode;
  final bool highlightDropTarget;
  final Widget dragHandle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return EditorialSection(
      backgroundColor: highlightDropTarget
          ? theme.colorScheme.primaryContainer.withAlphaFraction(0.7)
          : theme.editorialSurfaceColor,
      leadingAccentColor: theme.colorScheme.primary.withAlphaFraction(
        highlightDropTarget ? 0.92 : 0.55,
      ),
      padding: EdgeInsets.fromLTRB(
        18,
        compactMode ? 10 : 12,
        18,
        compactMode ? 10 : 12,
      ),
      child: Row(
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withAlphaFraction(0.82),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(
                '#${index + 1}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  task.title,
                  maxLines: compactMode ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  task.priority.name.toUpperCase(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.7,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          dragHandle,
        ],
      ),
    );
  }
}

final class _ManualQueueHandle extends StatelessWidget {
  const _ManualQueueHandle({
    required this.label,
    this.faded = false,
    this.onVerticalDragStart,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
  });

  final String label;
  final bool faded;
  final GestureDragStartCallback? onVerticalDragStart;
  final GestureDragUpdateCallback? onVerticalDragUpdate;
  final GestureDragEndCallback? onVerticalDragEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: onVerticalDragStart,
        onVerticalDragUpdate: onVerticalDragUpdate,
        onVerticalDragEnd: onVerticalDragEnd,
        child: Opacity(
          opacity: faded ? 0.34 : 1,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: theme.editorialChromeColor,
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withAlphaFraction(0.82),
              ),
            ),
            child: Icon(
              Icons.drag_indicator_rounded,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

final class _DismissBackground extends StatelessWidget {
  const _DismissBackground({
    required this.alignment,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      alignment: alignment,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        border: Border.all(color: colorScheme.error.withAlphaFraction(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colorScheme.onErrorContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

final class _NavigationButton extends StatelessWidget {
  const _NavigationButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: selected
            ? colorScheme.onSurface
            : colorScheme.onSurfaceVariant,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        shape: const RoundedRectangleBorder(),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18),
          const SizedBox(height: 6),
          Text(label),
          const SizedBox(height: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            width: selected ? 26 : 12,
            height: 2,
            color: selected ? colorScheme.primary : Colors.transparent,
          ),
        ],
      ),
    );
  }
}
