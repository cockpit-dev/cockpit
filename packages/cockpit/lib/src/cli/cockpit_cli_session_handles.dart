import 'dart:async';

import 'package:path/path.dart' as p;

import '../foundation/cockpit_locked_json_store.dart';
import '../foundation/cockpit_permissions.dart';

const Set<String> cockpitCliSessionLifecycles = <String>{
  'connecting',
  'ready',
  'crashed',
  'stopped',
};

final class CockpitCliSessionHandle {
  const CockpitCliSessionHandle({
    required this.handleId,
    required this.sessionId,
    required this.workspaceId,
    required this.updatedAt,
    this.checkoutIdentity,
    this.checkoutPath,
    this.targetId,
    this.appId,
    this.entrypoint,
    this.platform,
    this.deviceId,
    this.flavor,
    this.lifecycle = 'ready',
    this.recoverable = true,
    this.launchTimeoutMilliseconds = 600000,
  });

  final String handleId;
  final String sessionId;
  final String workspaceId;
  final DateTime updatedAt;
  final String? checkoutIdentity;
  final String? checkoutPath;
  final String? targetId;
  final String? appId;
  final String? entrypoint;
  final String? platform;
  final String? deviceId;
  final String? flavor;
  final String lifecycle;
  final bool recoverable;
  final int launchTimeoutMilliseconds;

  bool get isDevelopment => checkoutIdentity != null;

  CockpitCliSessionHandle copyWith({
    String? sessionId,
    String? workspaceId,
    DateTime? updatedAt,
    String? checkoutIdentity,
    String? checkoutPath,
    String? targetId,
    String? appId,
    String? entrypoint,
    String? platform,
    String? deviceId,
    String? flavor,
    String? lifecycle,
    bool? recoverable,
    int? launchTimeoutMilliseconds,
    bool replaceLaunchIdentity = false,
  }) => CockpitCliSessionHandle(
    handleId: handleId,
    sessionId: sessionId ?? this.sessionId,
    workspaceId: workspaceId ?? this.workspaceId,
    updatedAt: updatedAt ?? this.updatedAt,
    checkoutIdentity: checkoutIdentity ?? this.checkoutIdentity,
    checkoutPath: checkoutPath ?? this.checkoutPath,
    targetId: targetId ?? this.targetId,
    appId: appId ?? this.appId,
    entrypoint: replaceLaunchIdentity
        ? entrypoint
        : entrypoint ?? this.entrypoint,
    platform: replaceLaunchIdentity ? platform : platform ?? this.platform,
    deviceId: replaceLaunchIdentity ? deviceId : deviceId ?? this.deviceId,
    flavor: replaceLaunchIdentity ? flavor : flavor ?? this.flavor,
    lifecycle: lifecycle ?? this.lifecycle,
    recoverable: recoverable ?? this.recoverable,
    launchTimeoutMilliseconds:
        launchTimeoutMilliseconds ?? this.launchTimeoutMilliseconds,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'handleId': handleId,
    'sessionId': sessionId,
    'workspaceId': workspaceId,
    if (checkoutIdentity != null) 'checkoutIdentity': checkoutIdentity,
    if (checkoutPath != null) 'checkoutPath': checkoutPath,
    if (targetId != null) 'targetId': targetId,
    if (appId != null) 'appId': appId,
    if (entrypoint != null) 'entrypoint': entrypoint,
    if (platform != null) 'platform': platform,
    if (deviceId != null) 'deviceId': deviceId,
    if (flavor != null) 'flavor': flavor,
    'lifecycle': lifecycle,
    'recoverable': recoverable,
    'launchTimeoutMilliseconds': launchTimeoutMilliseconds,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}

final class CockpitCliSessionHandleStore {
  CockpitCliSessionHandleStore._(this._store, {DateTime Function()? utcNow})
    : _utcNow = utcNow ?? (() => DateTime.now().toUtc());

  factory CockpitCliSessionHandleStore.file({
    required String path,
    required CockpitPermissionHardener permissionHardener,
    required CockpitDirectorySyncer directorySyncer,
    DateTime Function()? utcNow,
  }) => CockpitCliSessionHandleStore._(
    CockpitLockedJsonStore<_SessionHandleState>(
      path: path,
      codec: const _SessionHandleStateCodec(),
      createInitial: _SessionHandleState.initial,
      permissionHardener: permissionHardener,
      directorySyncer: directorySyncer,
      maximumBytes: 4 * 1024 * 1024,
    ),
    utcNow: utcNow,
  );

  static const int maximumHandles = 4096;

  final CockpitLockedJsonStore<_SessionHandleState> _store;
  final DateTime Function() _utcNow;

  Future<CockpitCliSessionHandle> bind({
    required String workspaceId,
    required String sessionId,
  }) => _store.transact<CockpitCliSessionHandle>((state) {
    _identifier(workspaceId, r'$.workspaceId');
    _identifier(sessionId, r'$.sessionId');
    final existing = state.handles
        .where(
          (item) =>
              item.workspaceId == workspaceId && item.sessionId == sessionId,
        )
        .firstOrNull;
    if (existing != null) {
      final updated = existing.copyWith(updatedAt: _utcNow().toUtc());
      state.handles[state.handles.indexOf(existing)] = updated;
      return CockpitLockedJsonUpdate.write(state, updated);
    }
    final created = _allocate(
      state,
      sessionId: sessionId,
      workspaceId: workspaceId,
    );
    return CockpitLockedJsonUpdate.write(state, created);
  });

  Future<CockpitCliSessionHandle> bindDevelopment({
    required String checkoutIdentity,
    required String checkoutPath,
    required String workspaceId,
    required String sessionId,
    required String targetId,
    required String appId,
    String? entrypoint,
    String? platform,
    String? deviceId,
    String? flavor,
    String lifecycle = 'ready',
    bool? recoverable,
    int? launchTimeoutMilliseconds,
    bool replaceLaunchIdentity = false,
  }) => _store.transact<CockpitCliSessionHandle>((state) {
    _checkoutIdentity(checkoutIdentity, r'$.checkoutIdentity');
    _absolutePath(checkoutPath, r'$.checkoutPath');
    _identifier(workspaceId, r'$.workspaceId');
    _identifier(sessionId, r'$.sessionId');
    _identifier(targetId, r'$.targetId');
    _identifier(appId, r'$.appId');
    if (entrypoint != null) _entrypoint(entrypoint, r'$.entrypoint');
    if (platform != null) _launchValue(platform, r'$.platform');
    if (deviceId != null) _launchValue(deviceId, r'$.deviceId');
    if (flavor != null) _launchValue(flavor, r'$.flavor');
    _lifecycle(lifecycle, r'$.lifecycle');
    _launchTimeout(
      launchTimeoutMilliseconds ?? 600000,
      r'$.launchTimeoutMilliseconds',
    );

    final activeId = state.activeByCheckout[checkoutIdentity];
    final existing = state.handles
        .where(
          (item) =>
              item.handleId == activeId ||
              (item.checkoutIdentity == checkoutIdentity &&
                  item.workspaceId == workspaceId),
        )
        .firstOrNull;
    late final CockpitCliSessionHandle handle;
    if (existing == null) {
      if (entrypoint == null || platform == null || deviceId == null) {
        throw const FormatException(
          'A new development session requires entrypoint, platform, and device.',
        );
      }
      handle = _allocate(
        state,
        sessionId: sessionId,
        workspaceId: workspaceId,
        checkoutIdentity: checkoutIdentity,
        checkoutPath: p.normalize(checkoutPath),
        targetId: targetId,
        appId: appId,
        entrypoint: entrypoint,
        platform: platform,
        deviceId: deviceId,
        flavor: flavor,
        lifecycle: lifecycle,
        recoverable: recoverable ?? true,
        launchTimeoutMilliseconds: launchTimeoutMilliseconds ?? 600000,
      );
    } else {
      if (existing.checkoutIdentity != null &&
          existing.checkoutIdentity != checkoutIdentity) {
        throw const FormatException(
          'Active session belongs to a different checkout identity.',
        );
      }
      if (replaceLaunchIdentity &&
          (entrypoint == null || platform == null || deviceId == null)) {
        throw const FormatException(
          'Replacing launch identity requires entrypoint, platform, and device.',
        );
      }
      handle = existing.copyWith(
        sessionId: sessionId,
        workspaceId: workspaceId,
        checkoutIdentity: checkoutIdentity,
        checkoutPath: p.normalize(checkoutPath),
        targetId: targetId,
        appId: appId,
        entrypoint: entrypoint,
        platform: platform,
        deviceId: deviceId,
        flavor: flavor,
        lifecycle: lifecycle,
        recoverable: recoverable,
        launchTimeoutMilliseconds: launchTimeoutMilliseconds,
        replaceLaunchIdentity: replaceLaunchIdentity,
        updatedAt: _utcNow().toUtc(),
      );
      state.handles[state.handles.indexOf(existing)] = handle;
    }
    state.activeByCheckout[checkoutIdentity] = handle.handleId;
    return CockpitLockedJsonUpdate.write(state, handle);
  });

  Future<CockpitCliSessionHandle?> activeForCheckout(
    String checkoutIdentity,
  ) async {
    _checkoutIdentity(checkoutIdentity, r'$.checkoutIdentity');
    final state = await _store.read();
    final handleId = state.activeByCheckout[checkoutIdentity];
    if (handleId == null) return null;
    return state.handles.where((item) => item.handleId == handleId).firstOrNull;
  }

  Future<CockpitCliSessionHandle> selectForCheckout({
    required String checkoutIdentity,
    required String reference,
  }) => _store.transact<CockpitCliSessionHandle>((state) {
    _checkoutIdentity(checkoutIdentity, r'$.checkoutIdentity');
    final handle = _resolve(state, reference);
    if (handle == null) {
      throw FormatException('Unknown CLI session handle $reference.');
    }
    if (handle.checkoutIdentity != checkoutIdentity) {
      throw const FormatException(
        'Session handle belongs to a different checkout.',
      );
    }
    state.activeByCheckout[checkoutIdentity] = handle.handleId;
    final updated = handle.copyWith(updatedAt: _utcNow().toUtc());
    state.handles[state.handles.indexOf(handle)] = updated;
    return CockpitLockedJsonUpdate.write(state, updated);
  });

  Future<CockpitCliSessionHandle?> find(String reference) async {
    _identifier(reference, r'$.session');
    return _resolve(await _store.read(), reference);
  }

  Future<List<CockpitCliSessionHandle>> list() async {
    final items = [...(await _store.read()).handles]
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return List<CockpitCliSessionHandle>.unmodifiable(items);
  }

  Future<bool> remove(String reference) => _store.transact<bool>((state) {
    final handle = _resolve(state, reference);
    if (handle == null) {
      return CockpitLockedJsonUpdate.readOnly(state, false);
    }
    state.handles.remove(handle);
    state.activeByCheckout.removeWhere((_, value) => value == handle.handleId);
    return CockpitLockedJsonUpdate.write(state, true);
  });

  CockpitCliSessionHandle _allocate(
    _SessionHandleState state, {
    required String sessionId,
    required String workspaceId,
    String? checkoutIdentity,
    String? checkoutPath,
    String? targetId,
    String? appId,
    String? entrypoint,
    String? platform,
    String? deviceId,
    String? flavor,
    String lifecycle = 'ready',
    bool recoverable = true,
    int launchTimeoutMilliseconds = 600000,
  }) {
    if (state.handles.length >= maximumHandles) {
      throw const FormatException(
        'CLI session handle capacity is exhausted; remove stale handles.',
      );
    }
    final used = state.handles.map((item) => item.handleId).toSet();
    var ordinal = state.nextOrdinal;
    var handleId = _handleId(ordinal);
    while (used.contains(handleId)) {
      ordinal += 1;
      handleId = _handleId(ordinal);
    }
    final handle = CockpitCliSessionHandle(
      handleId: handleId,
      sessionId: sessionId,
      workspaceId: workspaceId,
      checkoutIdentity: checkoutIdentity,
      checkoutPath: checkoutPath,
      targetId: targetId,
      appId: appId,
      entrypoint: entrypoint,
      platform: platform,
      deviceId: deviceId,
      flavor: flavor,
      lifecycle: lifecycle,
      recoverable: recoverable,
      launchTimeoutMilliseconds: launchTimeoutMilliseconds,
      updatedAt: _utcNow().toUtc(),
    );
    state
      ..nextOrdinal = ordinal + 1
      ..handles.add(handle);
    return handle;
  }

  CockpitCliSessionHandle? _resolve(
    _SessionHandleState state,
    String reference,
  ) {
    _identifier(reference, r'$.session');
    final isLocalHandle = RegExp(r'^[0-9a-z]+$').hasMatch(reference);
    final matches = state.handles
        .where(
          (item) => isLocalHandle
              ? item.handleId == reference
              : item.sessionId == reference,
        )
        .toList(growable: false);
    if (matches.length > 1) {
      throw const FormatException(
        'Session reference is ambiguous; use its short handle.',
      );
    }
    return matches.firstOrNull;
  }
}

final class _SessionHandleState {
  _SessionHandleState({
    required this.nextOrdinal,
    required this.handles,
    required this.activeByCheckout,
  });

  factory _SessionHandleState.initial() => _SessionHandleState(
    nextOrdinal: 1,
    handles: <CockpitCliSessionHandle>[],
    activeByCheckout: <String, String>{},
  );

  int nextOrdinal;
  final List<CockpitCliSessionHandle> handles;
  final Map<String, String> activeByCheckout;
}

final class _SessionHandleStateCodec
    implements CockpitJsonCodec<_SessionHandleState> {
  const _SessionHandleStateCodec();

  static const schemaVersion = 'cockpit.cli-sessions/v5';

  @override
  _SessionHandleState decode(Object? value) {
    final json = _object(value, r'$');
    if (json['schemaVersion'] != schemaVersion) {
      throw const FormatException('Unsupported CLI session schemaVersion.');
    }
    _keys(json, const <String>{
      'schemaVersion',
      'nextOrdinal',
      'handles',
      'activeByCheckout',
    }, r'$');
    final nextOrdinal = json['nextOrdinal'];
    final rawHandles = json['handles'];
    if (nextOrdinal is! int || nextOrdinal < 1 || rawHandles is! List) {
      throw const FormatException('Invalid CLI session handle state.');
    }
    if (rawHandles.length > CockpitCliSessionHandleStore.maximumHandles) {
      throw const FormatException('CLI session handle state is oversized.');
    }
    final handles = <CockpitCliSessionHandle>[];
    final aliases = <String>{};
    final pairs = <String>{};
    for (var index = 0; index < rawHandles.length; index += 1) {
      final path =
          r'$'
          '.handles[$index]';
      final item = _object(rawHandles[index], path);
      _keys(
        item,
        const <String>{
          'handleId',
          'sessionId',
          'workspaceId',
          'checkoutIdentity',
          'checkoutPath',
          'targetId',
          'appId',
          'entrypoint',
          'platform',
          'deviceId',
          'flavor',
          'lifecycle',
          'recoverable',
          'launchTimeoutMilliseconds',
          'updatedAt',
        },
        path,
        optional: const <String>{
          'checkoutIdentity',
          'checkoutPath',
          'targetId',
          'appId',
          'entrypoint',
          'platform',
          'deviceId',
          'flavor',
        },
      );
      final handleId = _identifier(item['handleId'], '$path.handleId');
      if (!RegExp(r'^[0-9a-z]+$').hasMatch(handleId) ||
          !aliases.add(handleId)) {
        throw FormatException('Invalid or duplicate handle at $path.');
      }
      final sessionId = _identifier(item['sessionId'], '$path.sessionId');
      final workspaceId = _identifier(item['workspaceId'], '$path.workspaceId');
      if (!pairs.add('$workspaceId\u0000$sessionId')) {
        throw FormatException('Duplicate session binding at $path.');
      }
      final checkoutIdentity = item['checkoutIdentity'] == null
          ? null
          : _checkoutIdentity(
              item['checkoutIdentity'],
              '$path.checkoutIdentity',
            );
      final checkoutPath = item['checkoutPath'] == null
          ? null
          : _absolutePath(item['checkoutPath'], '$path.checkoutPath');
      final targetId = item['targetId'] == null
          ? null
          : _identifier(item['targetId'], '$path.targetId');
      final appId = item['appId'] == null
          ? null
          : _identifier(item['appId'], '$path.appId');
      final entrypoint = item['entrypoint'] == null
          ? null
          : _entrypoint(item['entrypoint'], '$path.entrypoint');
      final platform = item['platform'] == null
          ? null
          : _launchValue(item['platform'], '$path.platform');
      final deviceId = item['deviceId'] == null
          ? null
          : _launchValue(item['deviceId'], '$path.deviceId');
      final flavor = item['flavor'] == null
          ? null
          : _launchValue(item['flavor'], '$path.flavor');
      final lifecycle = _lifecycle(item['lifecycle'], '$path.lifecycle');
      final recoverable = item['recoverable'];
      if (recoverable is! bool) {
        throw FormatException('Invalid recoverable state at $path.');
      }
      final launchTimeoutMilliseconds = _launchTimeout(
        item['launchTimeoutMilliseconds'],
        '$path.launchTimeoutMilliseconds',
      );
      final developmentFields = <Object?>[
        checkoutPath,
        targetId,
        appId,
        entrypoint,
        platform,
        deviceId,
      ];
      if (checkoutIdentity == null
          ? developmentFields.any((field) => field != null) || flavor != null
          : developmentFields.any((field) => field == null)) {
        throw FormatException('Incomplete development identity at $path.');
      }
      final updatedAt = DateTime.tryParse('${item['updatedAt']}');
      if (updatedAt == null || !updatedAt.isUtc) {
        throw FormatException('Invalid updatedAt at $path.');
      }
      handles.add(
        CockpitCliSessionHandle(
          handleId: handleId,
          sessionId: sessionId,
          workspaceId: workspaceId,
          checkoutIdentity: checkoutIdentity,
          checkoutPath: checkoutPath,
          targetId: targetId,
          appId: appId,
          entrypoint: entrypoint,
          platform: platform,
          deviceId: deviceId,
          flavor: flavor,
          lifecycle: lifecycle,
          recoverable: recoverable,
          launchTimeoutMilliseconds: launchTimeoutMilliseconds,
          updatedAt: updatedAt,
        ),
      );
    }
    final activeByCheckout = <String, String>{};
    final rawActive = _object(json['activeByCheckout'], r'$.activeByCheckout');
    for (final entry in rawActive.entries) {
      final checkout = _checkoutIdentity(
        entry.key,
        r'$.activeByCheckout.<key>',
      );
      final handle = _identifier(
        entry.value,
        r'$.activeByCheckout.' + checkout,
      );
      final match = handles
          .where(
            (item) =>
                item.handleId == handle && item.checkoutIdentity == checkout,
          )
          .firstOrNull;
      if (match == null) {
        throw const FormatException('Invalid active checkout session binding.');
      }
      activeByCheckout[checkout] = handle;
    }
    return _SessionHandleState(
      nextOrdinal: nextOrdinal,
      handles: handles,
      activeByCheckout: activeByCheckout,
    );
  }

  @override
  Object? encode(_SessionHandleState value) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'nextOrdinal': value.nextOrdinal,
    'handles': value.handles.map((item) => item.toJson()).toList(),
    'activeByCheckout': value.activeByCheckout,
  };
}

String _handleId(int ordinal) {
  if (ordinal < 1 || ordinal > 0x7fffffff) {
    throw const FormatException('CLI session handle sequence is exhausted.');
  }
  return ordinal.toRadixString(36);
}

String _identifier(Object? value, String path) {
  if (value is! String ||
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$').hasMatch(value)) {
    throw FormatException('Invalid identifier at $path.');
  }
  return value;
}

String _checkoutIdentity(Object? value, String path) {
  if (value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    throw FormatException('Invalid checkout identity at $path.');
  }
  return value;
}

String _absolutePath(Object? value, String path) {
  if (value is! String ||
      value.isEmpty ||
      value.length > 32768 ||
      !p.isAbsolute(value) ||
      p.normalize(value) != value) {
    throw FormatException('Invalid absolute path at $path.');
  }
  return value;
}

String _entrypoint(Object? value, String path) {
  if (value is! String ||
      value.isEmpty ||
      value.length > 32768 ||
      p.posix.isAbsolute(value) ||
      p.posix.normalize(value) != value ||
      value == '..' ||
      value.startsWith('../')) {
    throw FormatException('Invalid Flutter entrypoint at $path.');
  }
  return value;
}

String _launchValue(Object? value, String path) {
  if (value is! String ||
      value.isEmpty ||
      value.length > 512 ||
      value.contains('\u0000') ||
      value.contains('\n') ||
      value.contains('\r')) {
    throw FormatException('Invalid Flutter launch value at $path.');
  }
  return value;
}

String _lifecycle(Object? value, String path) {
  if (value is! String || !cockpitCliSessionLifecycles.contains(value)) {
    throw FormatException('Invalid session lifecycle at $path.');
  }
  return value;
}

int _launchTimeout(Object? value, String path) {
  if (value is! int || value < 1000 || value > 1800000) {
    throw FormatException('Invalid launch timeout at $path.');
  }
  return value;
}

Map<String, Object?> _object(Object? value, String path) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw FormatException('Expected object at $path.');
  }
  return Map<String, Object?>.from(value);
}

void _keys(
  Map<String, Object?> value,
  Set<String> expected,
  String path, {
  Set<String> optional = const <String>{},
}) {
  final required = expected.difference(optional);
  if (value.keys.toSet().difference(expected).isNotEmpty ||
      required.difference(value.keys.toSet()).isNotEmpty) {
    throw FormatException('Unexpected fields at $path.');
  }
}
