import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:kache/kache.dart';
import 'package:kache_hive_ce/kache_hive_ce.dart';

import 'preferences_store.dart';

/// A persisted [KacheClient] with a bounded in-memory safety mode.
///
/// Hive CE normally retains list responses across launches. If a Flutter hot
/// restart leaves the previous isolate's box lock alive, startup falls back to
/// [MemoryKachePersistence] instead of hanging every data provider.
final class ConsoleCache {
  ConsoleCache._(this._client, this._hiveStore, this._memoryStore);

  static const defaultOpenTimeout = Duration(seconds: 3);

  final KacheClient _client;
  final HiveCeKacheStore? _hiveStore;
  final MemoryKachePersistence? _memoryStore;

  static final _jsonCodec = HiveCeCodec<Map<String, Object?>>(
    encode: (value) {
      return Uint8List.fromList(utf8.encode(jsonEncode(value)));
    },
    decode: (bytes) {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, Object?>) return decoded;
      if (decoded is Map) return decoded.cast<String, Object?>();
      return <String, Object?>{};
    },
  );

  static Future<ConsoleCache> initialize({
    Duration openTimeout = defaultOpenTimeout,
  }) async {
    final openFuture = HiveCeKacheStore.open(
      boxName: 'cockpit_console_cache',
      path: PreferencesStore.resolveConsoleStorageDirectory(),
    );
    try {
      final store = await openFuture.timeout(openTimeout);
      final client = KacheClient(
        persistence: store,
        persistenceOwnership: KachePersistenceOwnership.borrowed,
      );
      return ConsoleCache._(client, store, null);
    } on Object catch (error) {
      if (error is! TimeoutException &&
          error is! FileSystemException &&
          error is! HiveError) {
        rethrow;
      }
      unawaited(
        openFuture.then<void>(
          (store) => store.close(),
          onError: (Object _, StackTrace _) {},
        ),
      );
      final store = MemoryKachePersistence();
      final client = KacheClient(
        persistence: store,
        persistenceOwnership: KachePersistenceOwnership.borrowed,
      );
      return ConsoleCache._(client, null, store);
    }
  }

  /// Watches a persisted query that fetches and caches a JSON map.
  KacheResource<Map<String, Object?>> watchJson({
    required String namespace,
    String key = 'default',
    required Future<Map<String, Object?>> Function() fetch,
    Duration staleAfter = const Duration(minutes: 5),
  }) {
    final binding = switch ((_hiveStore, _memoryStore)) {
      (final hive?, _) => hive.bind<Map<String, Object?>>(
        codecId: namespace,
        schema: 1,
        codec: _jsonCodec,
      ),
      (_, final memory?) => memory.bind<Map<String, Object?>>(
        fingerprint: '$namespace|schema=1|json-map',
      ),
      _ => throw StateError('Console cache has no persistence backend.'),
    };
    final query = KacheQuery.persisted(
      key: KacheKey(namespace, [key]),
      fetch: (_) => fetch(),
      binding: binding,
      policy: KachePolicy.staleWhileRevalidate(staleAfter: staleAfter),
    );
    return _client.watch(query);
  }

  /// Watches a memory-only query for ephemeral cached values.
  KacheResource<T> watchMemory<T>({
    required String namespace,
    required String key,
    required Future<T> Function() fetch,
    Duration staleAfter = const Duration(seconds: 30),
  }) {
    final query = KacheQuery.memory(
      key: KacheKey(namespace, [key]),
      fetch: (_) => fetch(),
      policy: KachePolicy.staleWhileRevalidate(staleAfter: staleAfter),
    );
    return _client.watch(query);
  }

  /// Clears all cached entries and optionally refetches active handles.
  Future<void> clearAll({bool refetch = false}) {
    return _client.clear(refetch: refetch);
  }

  /// Forces refresh on every active handle.
  Future<void> refreshActive() => _client.refreshActive();

  Future<void> close() async {
    await _client.close();
    await _hiveStore?.close();
    await _memoryStore?.close();
  }
}

final consoleCacheProvider = FutureProvider<ConsoleCache>((ref) async {
  final cache = await ConsoleCache.initialize();
  ref.onDispose(cache.close);
  return cache;
});
