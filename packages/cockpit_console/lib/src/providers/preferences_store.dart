import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:path/path.dart' as p;

/// Persistent console preferences with an in-memory safety mode.
///
/// Hive normally provides durable storage. Flutter hot restart can leave the
/// previous isolate's box lock alive in the host process, so initialization is
/// bounded and falls back to process-local preferences instead of blocking the
/// entire Supervisor client indefinitely.
enum ConsoleLocaleMode {
  system('system'),
  english('en'),
  simplifiedChinese('zh-CN');

  const ConsoleLocaleMode(this.tag);

  final String tag;

  static ConsoleLocaleMode fromTag(String? tag) => values.firstWhere(
    (mode) => mode.tag == tag,
    orElse: () => ConsoleLocaleMode.system,
  );
}

final class PreferencesStore {
  PreferencesStore._(this._box);

  static const _boxName = 'cockpit_console';
  static const defaultOpenTimeout = Duration(seconds: 3);

  final Box<Object?>? _box;
  final Map<String, Object?> _volatileValues = <String, Object?>{};

  static Future<PreferencesStore> initialize({
    String? storagePath,
    Duration openTimeout = defaultOpenTimeout,
  }) async {
    final openFuture = Hive.openBox<Object?>(
      _boxName,
      path: storagePath ?? resolveConsoleStorageDirectory(),
    );
    try {
      return PreferencesStore._(await openFuture.timeout(openTimeout));
    } on Object catch (error) {
      if (error is! TimeoutException &&
          error is! FileSystemException &&
          error is! HiveError) {
        rethrow;
      }
      unawaited(
        openFuture.then<void>(
          (box) => box.close(),
          onError: (Object _, StackTrace _) {},
        ),
      );
      return PreferencesStore._(null);
    }
  }

  /// Resolves the durable per-user directory used by the console on desktop.
  static String resolveConsoleStorageDirectory({
    Map<String, String>? environment,
    String? operatingSystem,
  }) {
    final env = environment ?? Platform.environment;
    final os = operatingSystem ?? Platform.operatingSystem;
    final pathContext = p.Context(
      style: os == 'windows' ? p.Style.windows : p.Style.posix,
    );

    String requireHome() {
      final home = env[os == 'windows' ? 'USERPROFILE' : 'HOME'];
      if (home == null || home.trim().isEmpty) {
        throw StateError(
          'Cannot resolve the Cockpit Console storage directory: '
          '${os == 'windows' ? 'USERPROFILE' : 'HOME'} is not set.',
        );
      }
      return home;
    }

    return switch (os) {
      'macos' => pathContext.join(
        requireHome(),
        'Library',
        'Application Support',
        'Cockpit Console',
      ),
      'windows' => pathContext.join(
        env['APPDATA'] ?? env['LOCALAPPDATA'] ?? requireHome(),
        'Cockpit Console',
      ),
      'linux' => pathContext.join(
        env['XDG_DATA_HOME'] ??
            pathContext.join(requireHome(), '.local', 'share'),
        'cockpit-console',
      ),
      _ => pathContext.join(requireHome(), '.cockpit-console'),
    };
  }

  Object? _get(String key) => _box?.get(key) ?? _volatileValues[key];

  Future<void> _set(String key, Object? value) {
    final box = _box;
    if (box != null) return box.put(key, value);
    _volatileValues[key] = value;
    return Future<void>.value();
  }

  // ── Theme ────────────────────────────────────────────────────────────
  ThemeMode get themeMode {
    final raw = _get(_Keys.themeMode);
    return switch (raw) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) => _set(_Keys.themeMode, mode.name);

  // ── Language ─────────────────────────────────────────────────────────
  ConsoleLocaleMode get localeMode =>
      ConsoleLocaleMode.fromTag(_storedString(_Keys.localeTag));

  Future<void> setLocaleMode(ConsoleLocaleMode mode) =>
      _set(_Keys.localeTag, mode.tag);

  // ── Selected workspace ───────────────────────────────────────────────
  String? get selectedWorkspaceId {
    final raw = _get(_Keys.selectedWorkspaceId);
    return raw is String && raw.isNotEmpty ? raw : null;
  }

  Future<void> setSelectedWorkspaceId(String? id) =>
      _set(_Keys.selectedWorkspaceId, id);

  // ── Sidebar ──────────────────────────────────────────────────────────
  bool get sidebarCollapsed {
    final raw = _get(_Keys.sidebarCollapsed);
    return raw is bool ? raw : false;
  }

  Future<void> setSidebarCollapsed(bool value) =>
      _set(_Keys.sidebarCollapsed, value);

  // ── Recently opened documents ────────────────────────────────────────
  List<String> get recentDocuments {
    final raw = _get(_Keys.recentDocuments);
    if (raw is List) {
      return raw.whereType<String>().toList(growable: false);
    }
    return const [];
  }

  Future<void> addRecentDocument(String path) async {
    final current = recentDocuments;
    final updated = [path, ...current.where((item) => item != path)].take(20);
    await _set(_Keys.recentDocuments, updated.toList());
  }

  // ── Font size scale ──────────────────────────────────────────────────
  double get fontScale {
    final raw = _get(_Keys.fontScale);
    return raw is num ? raw.toDouble().clamp(0.85, 1.3) : 1.0;
  }

  Future<void> setFontScale(double scale) =>
      _set(_Keys.fontScale, scale.clamp(0.85, 1.3));

  // ── ACP: last agent + directory ──────────────────────────────────────
  String? get lastAgentId => _storedString(_Keys.lastAgentId);
  Future<void> setLastAgentId(String? id) => _set(_Keys.lastAgentId, id);

  String? get lastSessionCwd => _storedString(_Keys.lastSessionCwd);
  Future<void> setLastSessionCwd(String? path) =>
      _set(_Keys.lastSessionCwd, path);

  String? get customAgentExecutable =>
      _storedString(_Keys.customAgentExecutable);

  Future<void> setCustomAgentExecutable(String executable) =>
      _set(_Keys.customAgentExecutable, executable);

  List<String> get customAgentArgs {
    final raw = _get(_Keys.customAgentArgs);
    if (raw is List) {
      return raw.whereType<String>().toList(growable: false);
    }
    return const [];
  }

  Future<void> setCustomAgentArgs(List<String> args) =>
      _set(_Keys.customAgentArgs, args.toList(growable: false));

  // ── ACP: chat history ────────────────────────────────────────────────
  List<Map<String, Object?>> get chatHistory {
    final raw = _get(_Keys.chatHistory);
    if (raw is! List) return const [];
    return <Map<String, Object?>>[
      for (final item in raw)
        if (item is Map)
          Map<String, Object?>.unmodifiable(<String, Object?>{
            for (final entry in item.entries)
              if (entry.key is String) entry.key as String: entry.value,
          }),
    ];
  }

  Future<void> addChatMessage(Map<String, Object?> msg) async {
    final current = chatHistory;
    final updated = [...current, msg].toList();
    // Keep last 100 messages.
    if (updated.length > 100) {
      updated.removeRange(0, updated.length - 100);
    }
    await _set(_Keys.chatHistory, updated);
  }

  Future<void> clearChatHistory() => _set(_Keys.chatHistory, const []);

  String? _storedString(String key) {
    final raw = _get(key);
    return raw is String && raw.isNotEmpty ? raw : null;
  }

  Future<void> close() async {
    await _box?.close();
    _volatileValues.clear();
  }
}

final class _Keys {
  const _Keys._();

  static const themeMode = 'themeMode';
  static const localeTag = 'localeTag';
  static const selectedWorkspaceId = 'selectedWorkspaceId';
  static const sidebarCollapsed = 'sidebarCollapsed';
  static const recentDocuments = 'recentDocuments';
  static const fontScale = 'fontScale';
  static const lastAgentId = 'lastAgentId';
  static const lastSessionCwd = 'lastSessionCwd';
  static const customAgentExecutable = 'customAgentExecutable';
  static const customAgentArgs = 'customAgentArgs';
  static const chatHistory = 'chatHistory';
}

/// Provider for the lazily-initialized [PreferencesStore].
///
/// The [PreferencesStore.initialize] call happens in [initializePreferencesProvider]
/// or directly when the shell mounts. Widgets read the store via [preferencesProvider].
final preferencesProvider = FutureProvider<PreferencesStore>((ref) async {
  final store = await PreferencesStore.initialize();
  ref.onDispose(store.close);
  return store;
});

final class ConsoleLocaleNotifier extends Notifier<ConsoleLocaleMode> {
  @override
  ConsoleLocaleMode build() => ConsoleLocaleMode.system;

  void set(ConsoleLocaleMode mode) {
    state = mode;
  }
}

final consoleLocaleProvider =
    NotifierProvider<ConsoleLocaleNotifier, ConsoleLocaleMode>(
      ConsoleLocaleNotifier.new,
    );
