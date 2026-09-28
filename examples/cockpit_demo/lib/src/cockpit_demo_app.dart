import 'dart:async';

import 'package:flutter/material.dart';

import 'app/todo_app_service.dart';
import 'data/cockpit_demo_database.dart';
import 'data/todo_repository.dart';
import 'model/todo_settings.dart';
import 'model/todo_filter.dart';
import 'model/todo_task.dart';
import 'model/todo_task_sync_status.dart';
import 'network/todo_sync_gateway.dart';
import 'ui/screens/command_lab_screen.dart';
import 'ui/screens/completed_screen.dart';
import 'ui/screens/inbox_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/sync_conflict_screen.dart';
import 'ui/screens/task_detail_screen.dart';
import 'ui/screens/task_editor_screen.dart';
import 'ui/screens/today_screen.dart';
import 'ui/theme/orbit_todo_theme.dart';

final class CockpitDemoApp extends StatefulWidget {
  const CockpitDemoApp({
    this.initialRouteName = '/inbox',
    this.navigatorObservers = const <NavigatorObserver>[],
    this.database,
    this.syncGateway,
    this.onServiceReady,
    super.key,
  });
  final String initialRouteName;
  final List<NavigatorObserver> navigatorObservers;
  final CockpitDemoDatabase? database;
  final TodoSyncGatewayClient? syncGateway;

  /// Reports the live [TodoAppService] once it is constructed, so hosts such
  /// as the development shell can surface app state through Cockpit's
  /// `describeApp` command.
  final void Function(TodoAppService service)? onServiceReady;

  @override
  State<CockpitDemoApp> createState() => _CockpitDemoAppState();
}

final class _CockpitDemoAppState extends State<CockpitDemoApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final CockpitDemoDatabase _database =
      widget.database ?? CockpitDemoDatabase.local();
  late final TodoRepository _repository = TodoRepository(_database);
  late final TodoSyncGatewayClient _syncGateway =
      widget.syncGateway ??
      TodoLoopbackSyncGateway(
        payloadBuilder: _buildSyncProbePayload,
        shouldSimulateFailure: () => _service.syncState.simulateFailure,
      );
  late final TodoAppService _service = TodoAppService(
    repository: _repository,
    syncGateway: _syncGateway,
  );

  @override
  void initState() {
    super.initState();
    widget.onServiceReady?.call(_service);
    unawaited(_service.loadSettings());
    unawaited(_service.loadTags());
  }

  @override
  void dispose() {
    _service.dispose();
    unawaited(_syncGateway.close());
    if (widget.database == null) {
      unawaited(_database.close());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _service,
      builder: (context, _) {
        return MaterialApp(
          title: 'Super Cockpit',
          navigatorKey: _navigatorKey,
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          themeMode: _themeModeFor(_service.settingsState.settings),
          navigatorObservers: widget.navigatorObservers,
          onGenerateInitialRoutes: (initialRoute) {
            return <Route<dynamic>>[
              _buildRoute(RouteSettings(name: widget.initialRouteName)),
            ];
          },
          onGenerateRoute: _buildRoute,
        );
      },
    );
  }

  Route<dynamic> _buildRoute(RouteSettings settings) {
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (context) {
        switch (settings.name) {
          case '/today':
            return TodayScreen(
              service: _service,
              onOpenEditor: _openEditor,
              onOpenTask: _openTask,
              onOpenSettings: _openSettings,
              onNavigateToIndex: _navigateFromIndex,
            );
          case '/completed':
            return CompletedScreen(
              service: _service,
              onOpenEditor: _openEditor,
              onOpenTask: _openTask,
              onOpenSettings: _openSettings,
              onNavigateToIndex: _navigateFromIndex,
            );
          case '/editor':
            final task = settings.arguments as TodoTask?;
            return TaskEditorScreen(service: _service, task: task);
          case '/detail':
            final task = settings.arguments;
            if (task is! TodoTask) {
              return _fallbackScreen();
            }
            return TaskDetailScreen(
              service: _service,
              repository: _repository,
              task: task,
              onEdit: _editTask,
            );
          case '/settings':
            return SettingsScreen(service: _service);
          case '/command-lab':
            return const CommandLabScreen();
          case '/sync-conflict':
            final task = settings.arguments;
            if (task is! TodoTask) {
              return _fallbackScreen();
            }
            return SyncConflictScreen(
              service: _service,
              repository: _repository,
              task: task,
            );
          case '/inbox':
          default:
            return InboxScreen(
              service: _service,
              onOpenEditor: _openEditor,
              onOpenTask: _openTask,
              onOpenSettings: _openSettings,
              onNavigateToIndex: _navigateFromIndex,
            );
        }
      },
    );
  }

  Future<String?> _openEditor() async {
    final result = await _navigatorState.pushNamed('/editor');
    if (result is String && result.isNotEmpty) {
      return result;
    }
    return null;
  }

  Future<TodoTask?> _editTask(TodoTask task) async {
    await _navigatorState.pushNamed('/editor', arguments: task);
    return _repository.getTask(task.id);
  }

  Future<void> _openTask(TodoTask task) {
    return _navigatorState.pushNamed('/detail', arguments: task);
  }

  Future<void> _openSettings() {
    return _navigatorState.pushNamed('/settings');
  }

  void _navigateFromIndex(int index) {
    final routeName = switch (index) {
      1 => '/today',
      2 => '/completed',
      _ => '/inbox',
    };
    _navigatorState.pushReplacementNamed(routeName);
  }

  NavigatorState get _navigatorState {
    final state = _navigatorKey.currentState;
    if (state == null) {
      throw StateError('CockpitDemoApp navigator is not mounted.');
    }
    return state;
  }

  Future<Map<String, Object?>> _buildSyncProbePayload() async {
    final tasks = await _repository.fetchTasks(
      const TodoFilter(completionFilter: TodoCompletionFilter.all),
    );
    final settings = await _repository.readSettings();
    final today = DateTime.now();
    final activeCount = tasks.where((task) => !task.isCompleted).length;
    final completedCount = tasks.where((task) => task.isCompleted).length;
    final pendingCount = tasks
        .where((task) => task.syncStatus == TodoTaskSyncStatus.pending)
        .length;
    final failedCount = tasks
        .where((task) => task.syncStatus == TodoTaskSyncStatus.failed)
        .length;
    final conflictCount = tasks
        .where((task) => task.syncStatus == TodoTaskSyncStatus.conflicted)
        .length;
    final dueTodayCount = tasks.where((task) {
      final dueAt = task.dueAt;
      return dueAt != null &&
          dueAt.year == today.year &&
          dueAt.month == today.month &&
          dueAt.day == today.day;
    }).length;

    return <String, Object?>{
      'status': 'ready',
      'mode': 'local-first',
      'summary':
          'Local relay healthy · pending $pendingCount · conflicts $conflictCount · active $activeCount',
      'activeTaskCount': activeCount,
      'completedTaskCount': completedCount,
      'pendingTaskCount': pendingCount,
      'failedTaskCount': failedCount,
      'conflictTaskCount': conflictCount,
      'syncStatus': _service.syncState.status.name,
      'dueTodayCount': dueTodayCount,
      'sortMode': settings.sortMode.name,
      'compactMode': settings.compactMode,
      'checkedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Widget _fallbackScreen() {
    return const Scaffold(
      body: Center(child: Text('Unable to load the requested task.')),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    return OrbitTodoTheme.build(brightness);
  }

  ThemeMode _themeModeFor(TodoSettings settings) {
    return switch (settings.themePreference) {
      TodoThemePreference.system => ThemeMode.system,
      TodoThemePreference.light => ThemeMode.light,
      TodoThemePreference.dark => ThemeMode.dark,
    };
  }
}
