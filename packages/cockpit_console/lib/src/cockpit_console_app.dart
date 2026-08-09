import 'dart:async';

import 'package:cockpit_console/src/providers/core_providers.dart';
import 'package:cockpit_console/src/providers/data_providers.dart';
import 'package:cockpit_console/src/providers/preferences_store.dart';
import 'package:cockpit_console/src/theme/console_theme.dart';
import 'package:cockpit_console/src/ui/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Root widget for the Cockpit Console desktop application.
///
/// Wraps the [ProviderScope] consumer tree and applies the theme from the
/// persisted [PreferencesStore]. Connects to the Supervisor daemon on first
/// build. Accepts optional [navigatorObservers] for the development shell.
final class CockpitConsoleApp extends ConsumerStatefulWidget {
  const CockpitConsoleApp({
    this.navigatorObservers = const <NavigatorObserver>[],
    super.key,
  });

  /// Navigator observers injected by the development shell (flutter_cockpit).
  final List<NavigatorObserver> navigatorObservers;

  @override
  ConsumerState<CockpitConsoleApp> createState() => _CockpitConsoleAppState();
}

final class _CockpitConsoleAppState extends ConsumerState<CockpitConsoleApp> {
  bool _initialized = false;
  bool _startupComplete = false;

  @override
  Widget build(BuildContext context) {
    // Persistence is optional and may be unavailable when another console
    // process owns the Hive boxes. Never let it gate Supervisor connectivity.
    if (!_initialized) {
      _initialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_initialize());
      });
    }

    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: 'Cockpit Console',
      debugShowCheckedModeBanner: false,
      theme: ConsoleTheme.build(Brightness.light),
      darkTheme: ConsoleTheme.build(Brightness.dark),
      themeMode: themeMode,
      navigatorObservers: widget.navigatorObservers,
      home: _startupComplete ? const AppShell() : const _ConsoleStartupView(),
    );
  }

  Future<void> _initialize() async {
    await Future.wait<void>([
      _initializePreferences(),
      _initializeSupervisor(),
    ]);
    if (!mounted) return;
    final workspaceState = ref.read(workspacesProvider);
    if (ref.read(supervisorProvider) is SupervisorConnected &&
        workspaceState.error == null) {
      ref.read(workspacesProvider.notifier).reconcileSelection();
    }
  }

  Future<void> _initializePreferences() async {
    PreferencesStore? loadedPreferences;
    try {
      final preferences = await ref.read(preferencesProvider.future);
      loadedPreferences = preferences;
      if (!mounted) return;
      ref.read(themeProvider.notifier).set(preferences.themeMode);
      ref
          .read(selectedWorkspaceIdProvider.notifier)
          .select(preferences.selectedWorkspaceId);
    } on Object {
      // Preferences are optional; the in-memory defaults remain usable.
    }
    if (!mounted) return;

    final preferences = loadedPreferences;
    if (preferences != null) {
      ref.listenManual<ThemeMode>(themeProvider, (previous, next) async {
        try {
          await preferences.setThemeMode(next);
        } on Object {
          // A persistence failure must not break the active console session.
        }
      });
      ref.listenManual<String?>(selectedWorkspaceIdProvider, (
        previous,
        next,
      ) async {
        try {
          await preferences.setSelectedWorkspaceId(next);
        } on Object {
          // A persistence failure must not break the active console session.
        }
      });
    }
  }

  Future<void> _initializeSupervisor() async {
    try {
      await ref.read(daemonProvider.notifier).refresh();
      if (!mounted || !ref.read(daemonProvider).healthy) return;
      await ref.read(supervisorProvider.notifier).connect();
    } finally {
      if (mounted) {
        setState(() => _startupComplete = true);
      }
    }
    if (!mounted) return;
    if (ref.read(supervisorProvider) is SupervisorConnected) {
      await ref.read(workspacesProvider.notifier).refresh();
    }
  }
}

final class _ConsoleStartupView extends StatelessWidget {
  const _ConsoleStartupView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox.square(
                  dimension: 28,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(height: 20),
                Text(
                  'Connecting to Cockpit',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Checking daemon health and Supervisor capabilities.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
