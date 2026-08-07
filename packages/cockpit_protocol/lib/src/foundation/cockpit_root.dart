import 'cockpit_decode_policy.dart';
import 'cockpit_foundation_value_reader.dart';

enum CockpitRootState { active, draining, retired }

abstract final class CockpitRootStateMachine {
  static bool canTransition(CockpitRootState from, CockpitRootState to) {
    if (from == to) {
      return true;
    }
    return switch (from) {
      CockpitRootState.active =>
        to == CockpitRootState.draining || to == CockpitRootState.retired,
      CockpitRootState.draining =>
        to == CockpitRootState.active || to == CockpitRootState.retired,
      CockpitRootState.retired => false,
    };
  }

  static void validate(CockpitRootState from, CockpitRootState to) {
    if (!canTransition(from, to)) {
      throw FormatException(
        'Invalid root transition ${from.name} -> ${to.name}.',
      );
    }
  }
}

final class CockpitRootResource {
  /// Creates a CockpitRootResource.
  CockpitRootResource({
    required this.rootId,
    required this.canonicalPath,
    required this.filesystemIdentity,
    required this.state,
    required this.registeredAt,
    required this.updatedAt,
    this.retiredAt,
  }) {
    CockpitFoundationValueReader.id(rootId, r'$.rootId');
    CockpitFoundationValueReader.absolutePath(
      canonicalPath,
      r'$.canonicalPath',
    );
    CockpitFoundationValueReader.string(
      filesystemIdentity,
      r'$.filesystemIdentity',
      maximum: 512,
    );
    CockpitFoundationValueReader.utcDateTime(registeredAt, r'$.registeredAt');
    CockpitFoundationValueReader.utcDateTime(updatedAt, r'$.updatedAt');
    if (retiredAt != null) {
      CockpitFoundationValueReader.utcDateTime(retiredAt!, r'$.retiredAt');
    }
    if (updatedAt.isBefore(registeredAt)) {
      throw const FormatException('Root updatedAt precedes registeredAt.');
    }
    if ((state == CockpitRootState.retired) != (retiredAt != null) ||
        (retiredAt != null && retiredAt!.isBefore(updatedAt))) {
      throw const FormatException('Root retirement state is inconsistent.');
    }
  }

  final String rootId;
  final String canonicalPath;
  final String filesystemIdentity;
  final CockpitRootState state;
  final DateTime registeredAt;
  final DateTime updatedAt;
  final DateTime? retiredAt;

  /// Encodes this CockpitRootResource as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'rootId': rootId,
    'canonicalPath': canonicalPath,
    'filesystemIdentity': filesystemIdentity,
    'state': state.name,
    'registeredAt': registeredAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    if (retiredAt != null) 'retiredAt': retiredAt!.toUtc().toIso8601String(),
  };

  /// Decodes a CockpitRootResource from a JSON object.
  factory CockpitRootResource.fromJson(
    Object? value, {
    String path = r'$',
    CockpitDecodePolicy decodePolicy = CockpitDecodePolicy.requests,
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    CockpitFoundationValueReader.keys(
      json,
      const <String>{
        'rootId',
        'canonicalPath',
        'filesystemIdentity',
        'state',
        'registeredAt',
        'updatedAt',
        'retiredAt',
      },
      path,
      required: const <String>{
        'rootId',
        'canonicalPath',
        'filesystemIdentity',
        'state',
        'registeredAt',
        'updatedAt',
      },
      policy: decodePolicy,
    );
    return CockpitRootResource(
      rootId: CockpitFoundationValueReader.id(json['rootId'], '$path.rootId'),
      canonicalPath: CockpitFoundationValueReader.absolutePath(
        json['canonicalPath'],
        '$path.canonicalPath',
      ),
      filesystemIdentity: CockpitFoundationValueReader.string(
        json['filesystemIdentity'],
        '$path.filesystemIdentity',
        maximum: 512,
      ),
      state: _rootState(json['state'], '$path.state'),
      registeredAt: CockpitFoundationValueReader.dateTime(
        json['registeredAt'],
        '$path.registeredAt',
      ),
      updatedAt: CockpitFoundationValueReader.dateTime(
        json['updatedAt'],
        '$path.updatedAt',
      ),
      retiredAt: json['retiredAt'] == null
          ? null
          : CockpitFoundationValueReader.dateTime(
              json['retiredAt'],
              '$path.retiredAt',
            ),
    );
  }
}

final class CockpitRootRegistration {
  /// Creates a CockpitRootRegistration.
  CockpitRootRegistration({required this.path, this.label}) {
    CockpitFoundationValueReader.absolutePath(path, r'$.path');
    if (label != null) {
      CockpitFoundationValueReader.string(label, r'$.label', maximum: 128);
    }
  }

  final String path;
  final String? label;

  /// Encodes this CockpitRootRegistration as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    if (label != null) 'label': label,
  };

  /// Decodes a CockpitRootRegistration from a JSON object.
  factory CockpitRootRegistration.fromJson(
    Object? value, {
    String path = r'$',
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    CockpitFoundationValueReader.keys(
      json,
      const <String>{'path', 'label'},
      path,
      required: const <String>{'path'},
    );
    return CockpitRootRegistration(
      path: CockpitFoundationValueReader.absolutePath(
        json['path'],
        '$path.path',
      ),
      label: CockpitFoundationValueReader.optionalString(
        json['label'],
        '$path.label',
        maximum: 128,
      ),
    );
  }
}

final class CockpitRootRemoval {
  /// Creates a CockpitRootRemoval.
  CockpitRootRemoval({this.force = false, this.drainTimeoutMs = 30000}) {
    if (drainTimeoutMs < 0 || drainTimeoutMs > 300000) {
      throw const FormatException('Root drain timeout is invalid.');
    }
  }

  final bool force;
  final int drainTimeoutMs;

  /// Encodes this CockpitRootRemoval as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'force': force,
    'drainTimeoutMs': drainTimeoutMs,
  };

  /// Decodes a CockpitRootRemoval from a JSON object.
  factory CockpitRootRemoval.fromJson(Object? value, {String path = r'$'}) {
    final json = CockpitFoundationValueReader.object(value, path);
    CockpitFoundationValueReader.keys(
      json,
      const <String>{'force', 'drainTimeoutMs'},
      path,
      required: const <String>{'force', 'drainTimeoutMs'},
    );
    return CockpitRootRemoval(
      force: CockpitFoundationValueReader.boolean(json['force'], '$path.force'),
      drainTimeoutMs: CockpitFoundationValueReader.integer(
        json['drainTimeoutMs'],
        '$path.drainTimeoutMs',
        min: 0,
        max: 300000,
      ),
    );
  }
}

CockpitRootState _rootState(Object? value, String path) {
  return CockpitEnumValue<CockpitRootState>.parse(
    value,
    CockpitRootState.values,
    path,
    policy: CockpitDecodePolicy.requests,
  ).requireKnown();
}
