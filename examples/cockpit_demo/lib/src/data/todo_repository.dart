import 'dart:convert';

import 'package:drift/drift.dart';

import '../model/todo_filter.dart';
import '../model/todo_priority.dart';
import '../model/todo_settings.dart';
import '../model/todo_sync_conflict.dart';
import '../model/todo_tag.dart';
import '../model/todo_task.dart';
import '../model/todo_task_sync_status.dart';
import 'cockpit_demo_database.dart';

abstract interface class TodoRepositoryClient {
  Future<TodoTag> createTag({required String name, String? colorHex});

  Future<List<TodoTag>> fetchTags();

  Future<TodoTask> createTask({
    required String title,
    String notes,
    TodoPriority priority,
    DateTime? dueAt,
    List<String> tagIds,
  });

  Future<TodoTask> updateTask({
    required String taskId,
    required String title,
    String notes,
    TodoPriority priority,
    DateTime? dueAt,
    List<String> tagIds,
  });

  Future<TodoTask> setTaskCompleted({
    required String taskId,
    required bool isCompleted,
  });

  Future<void> setTasksCompleted({
    required List<String> taskIds,
    required bool isCompleted,
  });

  Future<TodoTask> deleteTask(String taskId);

  Future<List<TodoTask>> deleteTasks(List<String> taskIds);

  Future<TodoTask> restoreTask(String taskId);

  Future<void> restoreTasks(List<String> taskIds);

  Future<List<TodoTask>> updateTasksPriority({
    required List<String> taskIds,
    required TodoPriority priority,
  });

  Future<List<TodoTask>> updateTasksDueDate({
    required List<String> taskIds,
    required DateTime? dueAt,
  });

  Future<List<TodoTask>> updateTasksTags({
    required List<String> taskIds,
    required List<String> tagIds,
  });

  Future<List<TodoTask>> duplicateTasks({
    required List<String> taskIds,
    required String titlePrefix,
    required bool carryNotes,
    required bool carryDueDate,
    required bool carryTags,
  });

  Future<TodoTask> createFollowUpTask({
    required String sourceTaskId,
    required String title,
    required bool carryNotes,
    required bool carryTags,
    DateTime? dueAt,
  });

  Future<TodoTask> applySyncResolution({
    required String taskId,
    required TodoTaskSyncStatus syncStatus,
    required int localRevision,
    required int remoteRevision,
    TodoSyncConflict? conflict,
    List<String> pendingChanges,
    String? lastSyncFailure,
    DateTime? lastSyncedAt,
  });

  Future<void> reorderTasks(List<String> orderedTaskIds);

  Future<TodoTask?> getTask(String taskId);

  Future<List<TodoTask>> fetchTasks(TodoFilter filter);

  Future<TodoSettings> readSettings();

  Future<void> saveSettings(TodoSettings settings);
}

final class TodoRepository implements TodoRepositoryClient {
  TodoRepository(this._database);

  final CockpitDemoDatabase _database;
  int _lastIdMicros = 0;

  /// Windows clocks can return identical timestamps for consecutive reads,
  /// so entity ids advance monotonically past the last issued value.
  String _nextEntityId(String prefix) {
    var micros = DateTime.now().toUtc().microsecondsSinceEpoch;
    if (micros <= _lastIdMicros) {
      micros = _lastIdMicros + 1;
    }
    _lastIdMicros = micros;
    return '$prefix-$micros';
  }

  @override
  Future<TodoTag> createTag({required String name, String? colorHex}) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Tag name must not be empty.');
    }

    final existing = await (_database.select(
      _database.tags,
    )..where((table) => table.name.equals(normalizedName))).getSingleOrNull();
    if (existing != null) {
      return _mapTag(existing);
    }

    final createdAt = DateTime.now().toUtc();
    final tagId = _nextEntityId('tag');
    await _database
        .into(_database.tags)
        .insert(
          TagsCompanion.insert(
            id: tagId,
            name: normalizedName,
            colorHex: Value(colorHex),
            createdAtEpochMs: createdAt.millisecondsSinceEpoch,
          ),
        );

    return (await _fetchTagsByIds(<String>{tagId})).single;
  }

  @override
  Future<List<TodoTag>> fetchTags() async {
    final rows = await (_database.select(
      _database.tags,
    )..orderBy([(table) => OrderingTerm.asc(table.name)])).get();
    return rows.map(_mapTag).toList(growable: false);
  }

  @override
  Future<TodoTask> createTask({
    required String title,
    String notes = '',
    TodoPriority priority = TodoPriority.medium,
    DateTime? dueAt,
    List<String> tagIds = const <String>[],
  }) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw ArgumentError.value(
        title,
        'title',
        'Task title must not be empty.',
      );
    }

    final now = DateTime.now().toUtc();
    final displayOrder = await _nextDisplayOrder();
    final taskId = _nextEntityId('task');
    await _database
        .into(_database.tasks)
        .insert(
          TasksCompanion.insert(
            id: taskId,
            title: normalizedTitle,
            notes: Value(notes.trim()),
            priority: Value(priority.storageValue),
            dueAtEpochMs: Value(dueAt?.toUtc().millisecondsSinceEpoch),
            displayOrder: displayOrder,
            tagIdsJson: Value(_encodeTagIds(tagIds)),
            createdAtEpochMs: now.millisecondsSinceEpoch,
            updatedAtEpochMs: now.millisecondsSinceEpoch,
          ),
        );

    return (await getTask(taskId))!;
  }

  @override
  Future<TodoTask> updateTask({
    required String taskId,
    required String title,
    String notes = '',
    TodoPriority priority = TodoPriority.medium,
    DateTime? dueAt,
    List<String> tagIds = const <String>[],
  }) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw ArgumentError.value(
        title,
        'title',
        'Task title must not be empty.',
      );
    }

    final now = DateTime.now().toUtc();
    await (_database.update(
      _database.tasks,
    )..where((table) => table.id.equals(taskId))).write(
      TasksCompanion(
        title: Value(normalizedTitle),
        notes: Value(notes.trim()),
        priority: Value(priority.storageValue),
        dueAtEpochMs: Value(dueAt?.toUtc().millisecondsSinceEpoch),
        tagIdsJson: Value(_encodeTagIds(tagIds)),
        updatedAtEpochMs: Value(now.millisecondsSinceEpoch),
      ),
    );

    return (await getTask(taskId))!;
  }

  @override
  Future<TodoTask> setTaskCompleted({
    required String taskId,
    required bool isCompleted,
  }) async {
    await setTasksCompleted(
      taskIds: <String>[taskId],
      isCompleted: isCompleted,
    );
    return (await getTask(taskId))!;
  }

  @override
  Future<void> setTasksCompleted({
    required List<String> taskIds,
    required bool isCompleted,
  }) async {
    final normalizedIds = taskIds.toSet().toList(growable: false);
    if (normalizedIds.isEmpty) {
      return;
    }
    final now = DateTime.now().toUtc();
    await (_database.update(
      _database.tasks,
    )..where((table) => table.id.isIn(normalizedIds))).write(
      TasksCompanion(
        isCompleted: Value(isCompleted),
        completedAtEpochMs: Value(
          isCompleted ? now.millisecondsSinceEpoch : null,
        ),
        updatedAtEpochMs: Value(now.millisecondsSinceEpoch),
      ),
    );
  }

  @override
  Future<TodoTask> deleteTask(String taskId) async {
    return (await deleteTasks(<String>[taskId])).single;
  }

  @override
  Future<List<TodoTask>> deleteTasks(List<String> taskIds) async {
    final normalizedIds = taskIds.toSet().toList(growable: false);
    if (normalizedIds.isEmpty) {
      return const <TodoTask>[];
    }
    final now = DateTime.now().toUtc();
    await (_database.update(
      _database.tasks,
    )..where((table) => table.id.isIn(normalizedIds))).write(
      TasksCompanion(
        deletedAtEpochMs: Value(now.millisecondsSinceEpoch),
        updatedAtEpochMs: Value(now.millisecondsSinceEpoch),
      ),
    );
    return _fetchTasksByIds(normalizedIds);
  }

  @override
  Future<TodoTask> restoreTask(String taskId) async {
    await restoreTasks(<String>[taskId]);
    return (await getTask(taskId))!;
  }

  @override
  Future<void> restoreTasks(List<String> taskIds) async {
    final normalizedIds = taskIds.toSet().toList(growable: false);
    if (normalizedIds.isEmpty) {
      return;
    }
    final now = DateTime.now().toUtc();
    await (_database.update(
      _database.tasks,
    )..where((table) => table.id.isIn(normalizedIds))).write(
      TasksCompanion(
        deletedAtEpochMs: const Value(null),
        updatedAtEpochMs: Value(now.millisecondsSinceEpoch),
      ),
    );
  }

  @override
  Future<List<TodoTask>> updateTasksPriority({
    required List<String> taskIds,
    required TodoPriority priority,
  }) async {
    final normalizedIds = taskIds.toSet().toList(growable: false);
    if (normalizedIds.isEmpty) {
      return const <TodoTask>[];
    }
    final now = DateTime.now().toUtc();
    await (_database.update(
      _database.tasks,
    )..where((table) => table.id.isIn(normalizedIds))).write(
      TasksCompanion(
        priority: Value(priority.storageValue),
        updatedAtEpochMs: Value(now.millisecondsSinceEpoch),
      ),
    );
    return _fetchTasksByIds(normalizedIds);
  }

  @override
  Future<List<TodoTask>> updateTasksDueDate({
    required List<String> taskIds,
    required DateTime? dueAt,
  }) async {
    final normalizedIds = taskIds.toSet().toList(growable: false);
    if (normalizedIds.isEmpty) {
      return const <TodoTask>[];
    }
    final now = DateTime.now().toUtc();
    await (_database.update(
      _database.tasks,
    )..where((table) => table.id.isIn(normalizedIds))).write(
      TasksCompanion(
        dueAtEpochMs: Value(dueAt?.toUtc().millisecondsSinceEpoch),
        updatedAtEpochMs: Value(now.millisecondsSinceEpoch),
      ),
    );
    return _fetchTasksByIds(normalizedIds);
  }

  @override
  Future<List<TodoTask>> updateTasksTags({
    required List<String> taskIds,
    required List<String> tagIds,
  }) async {
    final normalizedIds = taskIds.toSet().toList(growable: false);
    if (normalizedIds.isEmpty) {
      return const <TodoTask>[];
    }
    final now = DateTime.now().toUtc();
    await (_database.update(
      _database.tasks,
    )..where((table) => table.id.isIn(normalizedIds))).write(
      TasksCompanion(
        tagIdsJson: Value(_encodeTagIds(tagIds)),
        updatedAtEpochMs: Value(now.millisecondsSinceEpoch),
      ),
    );
    return _fetchTasksByIds(normalizedIds);
  }

  @override
  Future<List<TodoTask>> duplicateTasks({
    required List<String> taskIds,
    required String titlePrefix,
    required bool carryNotes,
    required bool carryDueDate,
    required bool carryTags,
  }) async {
    final normalizedIds = taskIds.toSet().toList(growable: false);
    if (normalizedIds.isEmpty) {
      return const <TodoTask>[];
    }

    final normalizedPrefix = titlePrefix.trim();
    if (normalizedPrefix.isEmpty) {
      throw ArgumentError.value(
        titlePrefix,
        'titlePrefix',
        'Duplicate title prefix must not be empty.',
      );
    }

    final sourceTasks = await _fetchTasksByIds(normalizedIds);
    final sourceTasksById = <String, TodoTask>{
      for (final task in sourceTasks) task.id: task,
    };
    for (final taskId in normalizedIds) {
      if (!sourceTasksById.containsKey(taskId)) {
        throw StateError('Task $taskId no longer exists.');
      }
    }

    final duplicatedTasks = <TodoTask>[];
    await _database.transaction(() async {
      for (final taskId in normalizedIds) {
        final sourceTask = sourceTasksById[taskId]!;
        duplicatedTasks.add(
          await createTask(
            title: '$normalizedPrefix: ${sourceTask.title}',
            notes: carryNotes ? sourceTask.notes : '',
            priority: sourceTask.priority,
            dueAt: carryDueDate ? sourceTask.dueAt : null,
            tagIds: carryTags ? sourceTask.tagIds : const <String>[],
          ),
        );
      }
    });
    return List<TodoTask>.unmodifiable(duplicatedTasks);
  }

  @override
  Future<TodoTask> createFollowUpTask({
    required String sourceTaskId,
    required String title,
    required bool carryNotes,
    required bool carryTags,
    DateTime? dueAt,
  }) async {
    final sourceTask = await getTask(sourceTaskId);
    if (sourceTask == null) {
      throw StateError('Task $sourceTaskId no longer exists.');
    }
    return createTask(
      title: title,
      notes: carryNotes ? sourceTask.notes : '',
      priority: sourceTask.priority,
      dueAt: dueAt,
      tagIds: carryTags
          ? sourceTask.tags.map((tag) => tag.id).toList(growable: false)
          : const <String>[],
    );
  }

  @override
  Future<TodoTask> applySyncResolution({
    required String taskId,
    required TodoTaskSyncStatus syncStatus,
    required int localRevision,
    required int remoteRevision,
    TodoSyncConflict? conflict,
    List<String> pendingChanges = const <String>[],
    String? lastSyncFailure,
    DateTime? lastSyncedAt,
  }) async {
    final now = DateTime.now().toUtc();
    await _database.customStatement(
      'INSERT INTO task_sync_state ('
      'task_id, sync_status, local_revision, remote_revision, '
      'pending_change_json, sync_conflict_json, last_sync_failure, '
      'last_synced_at_epoch_ms'
      ') VALUES ('
      '${_sqlString(taskId)}, '
      '${_sqlString(syncStatus.name)}, '
      '$localRevision, '
      '$remoteRevision, '
      '${_sqlString(_encodeStringList(pendingChanges))}, '
      '${_sqlStringOrNull(_encodeSyncConflict(conflict))}, '
      '${_sqlStringOrNull(lastSyncFailure)}, '
      '${_sqlIntOrNull(lastSyncedAt?.toUtc().millisecondsSinceEpoch)}'
      ') ON CONFLICT(task_id) DO UPDATE SET '
      'sync_status = excluded.sync_status, '
      'local_revision = excluded.local_revision, '
      'remote_revision = excluded.remote_revision, '
      'pending_change_json = excluded.pending_change_json, '
      'sync_conflict_json = excluded.sync_conflict_json, '
      'last_sync_failure = excluded.last_sync_failure, '
      'last_synced_at_epoch_ms = excluded.last_synced_at_epoch_ms',
    );
    await (_database.update(
      _database.tasks,
    )..where((table) => table.id.equals(taskId))).write(
      TasksCompanion(updatedAtEpochMs: Value(now.millisecondsSinceEpoch)),
    );
    return (await getTask(taskId))!;
  }

  @override
  Future<void> reorderTasks(List<String> orderedTaskIds) async {
    if (orderedTaskIds.isEmpty) {
      return;
    }

    final normalizedIds = orderedTaskIds.toSet().toList(growable: false);
    await _database.transaction(() async {
      for (var index = 0; index < normalizedIds.length; index += 1) {
        await (_database.update(
          _database.tasks,
        )..where((table) => table.id.equals(normalizedIds[index]))).write(
          TasksCompanion(
            displayOrder: Value(index),
            updatedAtEpochMs: Value(
              DateTime.now().toUtc().millisecondsSinceEpoch,
            ),
          ),
        );
      }
    });
  }

  @override
  Future<TodoTask?> getTask(String taskId) async {
    final row = await (_database.select(
      _database.tasks,
    )..where((table) => table.id.equals(taskId))).getSingleOrNull();
    if (row == null) {
      return null;
    }
    return _hydrateTasks(<Task>[row]).then((tasks) => tasks.single);
  }

  @override
  Future<List<TodoTask>> fetchTasks(TodoFilter filter) async {
    final query = _database.select(_database.tasks);
    if (!filter.includeDeleted) {
      query.where((table) => table.deletedAtEpochMs.isNull());
    }

    switch (filter.completionFilter) {
      case TodoCompletionFilter.active:
        query.where((table) => table.isCompleted.equals(false));
      case TodoCompletionFilter.completed:
        query.where((table) => table.isCompleted.equals(true));
      case TodoCompletionFilter.all:
        break;
    }

    if (filter.priorities.isNotEmpty) {
      query.where(
        (table) => table.priority.isIn(
          filter.priorities
              .map((priority) => priority.storageValue)
              .toList(growable: false),
        ),
      );
    }

    final normalizedQuery = filter.query.trim().toLowerCase();
    if (normalizedQuery.isNotEmpty) {
      final pattern = '%$normalizedQuery%';
      query.where(
        (table) =>
            table.title.lower().like(pattern) |
            table.notes.lower().like(pattern),
      );
    }

    if (filter.onlyDueToday) {
      final today = DateTime.now();
      final dayStart = DateTime(today.year, today.month, today.day);
      final nextDay = dayStart.add(const Duration(days: 1));
      query.where(
        (table) =>
            table.dueAtEpochMs.isBiggerOrEqualValue(
              dayStart.toUtc().millisecondsSinceEpoch,
            ) &
            table.dueAtEpochMs.isSmallerThanValue(
              nextDay.toUtc().millisecondsSinceEpoch,
            ),
      );
    }

    query.orderBy(<OrderingTerm Function($TasksTable)>[
      ($TasksTable table) => OrderingTerm.asc(table.displayOrder),
      ($TasksTable table) => OrderingTerm.desc(table.updatedAtEpochMs),
    ]);

    final rows = await query.get();
    final tasks = await _hydrateTasks(rows);
    if (filter.tagIds.isEmpty && filter.syncStatuses.isEmpty) {
      return tasks;
    }

    return tasks
        .where((task) {
          final matchesTags =
              filter.tagIds.isEmpty ||
              task.tagIds.any((tagId) => filter.tagIds.contains(tagId));
          final matchesSyncStatus =
              filter.syncStatuses.isEmpty ||
              filter.syncStatuses.contains(task.syncStatus);
          return matchesTags && matchesSyncStatus;
        })
        .toList(growable: false);
  }

  @override
  Future<TodoSettings> readSettings() async {
    final existing = await (_database.select(
      _database.appSettings,
    )..where((table) => table.id.equals(1))).getSingleOrNull();
    if (existing != null) {
      return _mapSettings(existing);
    }

    await saveSettings(TodoSettings.defaults);
    return TodoSettings.defaults;
  }

  @override
  Future<void> saveSettings(TodoSettings settings) async {
    final now = DateTime.now().toUtc();
    await _database
        .into(_database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            id: const Value<int>(1),
            themePreference: settings.themePreference.name,
            sortMode: settings.sortMode.name,
            showCompletedInInbox: settings.showCompletedInInbox,
            compactMode: settings.compactMode,
            updatedAtEpochMs: now.millisecondsSinceEpoch,
          ),
        );
  }

  Future<int> _nextDisplayOrder() async {
    final expression = _database.tasks.displayOrder.max();
    final result = await (_database.selectOnly(
      _database.tasks,
    )..addColumns(<Expression<Object>>[expression])).getSingle();
    final maxValue = result.read(expression);
    return (maxValue ?? -1) + 1;
  }

  Future<List<TodoTask>> _hydrateTasks(List<Task> rows) async {
    final tagIds = rows.expand((row) => _decodeTagIds(row.tagIdsJson)).toSet();
    final tagsById = await _fetchTagsByIds(tagIds);
    final tagMap = <String, TodoTag>{for (final tag in tagsById) tag.id: tag};
    final syncMap = await _fetchSyncSnapshots(
      rows.map((row) => row.id).toSet(),
    );

    return rows
        .map(
          (row) => _mapTask(
            row,
            tagMap,
            syncMap[row.id] ?? const _TaskSyncSnapshot(),
          ),
        )
        .toList(growable: false);
  }

  Future<List<TodoTag>> _fetchTagsByIds(Set<String> tagIds) async {
    if (tagIds.isEmpty) {
      return const <TodoTag>[];
    }

    final rows = await (_database.select(
      _database.tags,
    )..where((table) => table.id.isIn(tagIds))).get();
    return rows.map(_mapTag).toList(growable: false);
  }

  Future<List<TodoTask>> _fetchTasksByIds(List<String> taskIds) async {
    if (taskIds.isEmpty) {
      return const <TodoTask>[];
    }
    final rows = await (_database.select(
      _database.tasks,
    )..where((table) => table.id.isIn(taskIds))).get();
    final mapped = await _hydrateTasks(rows);
    final byId = <String, TodoTask>{for (final task in mapped) task.id: task};
    return taskIds
        .map((taskId) => byId[taskId])
        .whereType<TodoTask>()
        .toList(growable: false);
  }

  Future<Map<String, _TaskSyncSnapshot>> _fetchSyncSnapshots(
    Set<String> taskIds,
  ) async {
    if (taskIds.isEmpty) {
      return const <String, _TaskSyncSnapshot>{};
    }
    final rows = await _database
        .customSelect(
          'SELECT '
          'task_id AS taskId, '
          'sync_status AS syncStatus, '
          'local_revision AS localRevision, '
          'remote_revision AS remoteRevision, '
          'pending_change_json AS pendingChangeJson, '
          'sync_conflict_json AS syncConflictJson, '
          'last_sync_failure AS lastSyncFailure, '
          'last_synced_at_epoch_ms AS lastSyncedAtEpochMs '
          'FROM task_sync_state '
          'WHERE task_id IN (${taskIds.map(_sqlString).join(', ')})',
        )
        .get();
    return <String, _TaskSyncSnapshot>{
      for (final row in rows)
        row.read<String>('taskId'): _TaskSyncSnapshot(
          syncStatus: TodoTaskSyncStatus.values.byName(
            row.readNullable<String>('syncStatus') ??
                TodoTaskSyncStatus.idle.name,
          ),
          localRevision: row.readNullable<int>('localRevision') ?? 0,
          remoteRevision: row.readNullable<int>('remoteRevision') ?? 0,
          pendingChanges: _decodeStringList(
            row.readNullable<String>('pendingChangeJson') ?? '[]',
          ),
          syncConflict: _decodeSyncConflict(
            row.readNullable<String>('syncConflictJson'),
          ),
          lastSyncFailure: row.readNullable<String>('lastSyncFailure'),
          lastSyncedAt: _fromEpochMs(
            row.readNullable<int>('lastSyncedAtEpochMs'),
          ),
        ),
    };
  }

  TodoTask _mapTask(
    Task row,
    Map<String, TodoTag> tagMap,
    _TaskSyncSnapshot syncSnapshot,
  ) {
    final tags = _decodeTagIds(row.tagIdsJson)
        .map((tagId) => tagMap[tagId])
        .whereType<TodoTag>()
        .toList(growable: false);
    return TodoTask(
      id: row.id,
      title: row.title,
      notes: row.notes,
      priority: TodoPriority.fromStorage(row.priority),
      dueAt: _fromEpochMs(row.dueAtEpochMs),
      isCompleted: row.isCompleted,
      completedAt: _fromEpochMs(row.completedAtEpochMs),
      deletedAt: _fromEpochMs(row.deletedAtEpochMs),
      displayOrder: row.displayOrder,
      createdAt: _fromEpochMs(row.createdAtEpochMs)!,
      updatedAt: _fromEpochMs(row.updatedAtEpochMs)!,
      syncStatus: syncSnapshot.syncStatus,
      localRevision: syncSnapshot.localRevision,
      remoteRevision: syncSnapshot.remoteRevision,
      lastSyncedAt: syncSnapshot.lastSyncedAt,
      lastSyncFailure: syncSnapshot.lastSyncFailure,
      pendingChanges: syncSnapshot.pendingChanges,
      syncConflict: syncSnapshot.syncConflict,
      tags: tags,
    );
  }

  TodoTag _mapTag(Tag row) {
    return TodoTag(
      id: row.id,
      name: row.name,
      colorHex: row.colorHex,
      createdAt: _fromEpochMs(row.createdAtEpochMs)!,
    );
  }

  TodoSettings _mapSettings(AppSetting row) {
    return TodoSettings(
      themePreference: TodoThemePreference.values.byName(row.themePreference),
      sortMode: TodoSortMode.values.byName(row.sortMode),
      showCompletedInInbox: row.showCompletedInInbox,
      compactMode: row.compactMode,
    );
  }

  DateTime? _fromEpochMs(int? epochMs) {
    if (epochMs == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true);
  }

  String _encodeTagIds(List<String> tagIds) {
    return _encodeStringList(tagIds);
  }

  List<String> _decodeTagIds(String jsonValue) {
    return _decodeStringList(jsonValue);
  }

  String _encodeStringList(List<String> values) {
    return jsonEncode(values.toSet().toList(growable: false));
  }

  List<String> _decodeStringList(String jsonValue) {
    final decoded = jsonDecode(jsonValue);
    if (decoded is! List<Object?>) {
      return const <String>[];
    }
    return decoded
        .whereType<String>()
        .map((tagId) => tagId.trim())
        .where((tagId) => tagId.isNotEmpty)
        .toList(growable: false);
  }

  String? _encodeSyncConflict(TodoSyncConflict? conflict) {
    if (conflict == null) {
      return null;
    }
    return jsonEncode(conflict.toJson());
  }

  TodoSyncConflict? _decodeSyncConflict(String? jsonValue) {
    if (jsonValue == null || jsonValue.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(jsonValue);
    if (decoded is! Map<Object?, Object?>) {
      return null;
    }
    return TodoSyncConflict.fromJson(
      decoded.map((key, value) => MapEntry('$key', value)),
    );
  }

  String _sqlString(String value) {
    final escaped = value.replaceAll('\'', '\'\'');
    return '\'$escaped\'';
  }

  String _sqlStringOrNull(String? value) {
    if (value == null) {
      return 'NULL';
    }
    return _sqlString(value);
  }

  String _sqlIntOrNull(int? value) {
    return value == null ? 'NULL' : '$value';
  }
}

final class _TaskSyncSnapshot {
  const _TaskSyncSnapshot({
    this.syncStatus = TodoTaskSyncStatus.idle,
    this.localRevision = 0,
    this.remoteRevision = 0,
    this.pendingChanges = const <String>[],
    this.syncConflict,
    this.lastSyncFailure,
    this.lastSyncedAt,
  });

  final TodoTaskSyncStatus syncStatus;
  final int localRevision;
  final int remoteRevision;
  final List<String> pendingChanges;
  final TodoSyncConflict? syncConflict;
  final String? lastSyncFailure;
  final DateTime? lastSyncedAt;
}
