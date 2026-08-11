import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../foundation/cockpit_ids.dart';
import 'cockpit_application_service_exception.dart';

typedef CockpitInteractiveNow = DateTime Function();

final class CockpitInteractiveStoredSnapshot {
  const CockpitInteractiveStoredSnapshot({
    required this.ref,
    required this.sessionKey,
    required this.snapshot,
    required this.createdAt,
  });

  final String ref;
  final String sessionKey;
  final CockpitSnapshot snapshot;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'ref': ref,
    'sessionKey': sessionKey,
    'snapshot': snapshot.toJson(),
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}

final class CockpitInteractiveSnapshotStore {
  CockpitInteractiveSnapshotStore({
    this.ttl = const Duration(minutes: 10),
    this.maxEntries = 32,
    CockpitInteractiveNow? now,
    CockpitTokenGenerator? tokenGenerator,
  }) : _now = now ?? DateTime.now,
       _tokenGenerator = tokenGenerator ?? CockpitSecureTokenGenerator();

  final Duration ttl;
  final int maxEntries;
  final CockpitInteractiveNow _now;
  final CockpitTokenGenerator _tokenGenerator;
  final Map<String, CockpitInteractiveStoredSnapshot> _entries =
      <String, CockpitInteractiveStoredSnapshot>{};

  String put({required String sessionKey, required CockpitSnapshot snapshot}) {
    _purgeExpired();
    final timestamp = _now().toUtc();
    final ref = _tokenGenerator.nextResourceId('s');
    _entries[ref] = CockpitInteractiveStoredSnapshot(
      ref: ref,
      sessionKey: sessionKey,
      snapshot: snapshot,
      createdAt: timestamp,
    );
    _evictOverflow();
    return ref;
  }

  CockpitInteractiveStoredSnapshot read(String ref, {String? sessionKey}) {
    final entry = _entries[ref];
    if (entry == null) {
      throw CockpitApplicationServiceException(
        code: 'interactiveSnapshotRefNotFound',
        message: 'Snapshot ref does not exist.',
        details: <String, Object?>{'snapshotRef': ref},
      );
    }
    if (_isExpired(entry)) {
      _entries.remove(ref);
      throw CockpitApplicationServiceException(
        code: 'interactiveSnapshotRefExpired',
        message: 'Snapshot ref has expired.',
        details: <String, Object?>{'snapshotRef': ref},
      );
    }
    if (sessionKey != null && entry.sessionKey != sessionKey) {
      throw CockpitApplicationServiceException(
        code: 'interactiveSnapshotRefSessionMismatch',
        message: 'Snapshot ref does not belong to the requested session.',
        details: <String, Object?>{
          'snapshotRef': ref,
          'sessionKey': sessionKey,
        },
      );
    }
    return entry;
  }

  void _purgeExpired() {
    final expired = <String>[];
    for (final entry in _entries.entries) {
      if (_isExpired(entry.value)) {
        expired.add(entry.key);
      }
    }
    for (final ref in expired) {
      _entries.remove(ref);
    }
  }

  bool _isExpired(CockpitInteractiveStoredSnapshot entry) {
    return _now().toUtc().difference(entry.createdAt) > ttl;
  }

  void _evictOverflow() {
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }
}
