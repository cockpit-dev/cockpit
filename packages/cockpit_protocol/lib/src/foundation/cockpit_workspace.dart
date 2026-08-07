import 'cockpit_decode_policy.dart';
import 'cockpit_foundation_value_reader.dart';

enum CockpitWorkspaceState { active, draining, retired }

abstract final class CockpitWorkspaceStateMachine {
  static bool canTransition(
    CockpitWorkspaceState from,
    CockpitWorkspaceState to,
  ) {
    if (from == to) {
      return true;
    }
    return switch (from) {
      CockpitWorkspaceState.active =>
        to == CockpitWorkspaceState.draining ||
            to == CockpitWorkspaceState.retired,
      CockpitWorkspaceState.draining =>
        to == CockpitWorkspaceState.active ||
            to == CockpitWorkspaceState.retired,
      CockpitWorkspaceState.retired => false,
    };
  }
}

final class CockpitWorkspaceMarker {
  /// Creates a CockpitWorkspaceMarker.
  CockpitWorkspaceMarker({
    this.schemaVersion = 'cockpit.workspace/v2',
    required this.workspaceId,
    required this.projectId,
    required this.checkoutId,
    required this.createdAt,
  }) {
    if (schemaVersion != 'cockpit.workspace/v2') {
      throw const FormatException('Invalid workspace marker schemaVersion.');
    }
    CockpitFoundationValueReader.id(workspaceId, r'$.workspaceId');
    CockpitFoundationValueReader.id(projectId, r'$.projectId');
    CockpitFoundationValueReader.id(checkoutId, r'$.checkoutId');
    CockpitFoundationValueReader.utcDateTime(createdAt, r'$.createdAt');
  }

  final String schemaVersion;
  final String workspaceId;
  final String projectId;
  final String checkoutId;
  final DateTime createdAt;

  /// Encodes this CockpitWorkspaceMarker as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'workspaceId': workspaceId,
    'projectId': projectId,
    'checkoutId': checkoutId,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  /// Decodes a CockpitWorkspaceMarker from a JSON object.
  factory CockpitWorkspaceMarker.fromJson(Object? value, {String path = r'$'}) {
    final json = CockpitFoundationValueReader.object(value, path);
    const fields = <String>{
      'schemaVersion',
      'workspaceId',
      'projectId',
      'checkoutId',
      'createdAt',
    };
    CockpitFoundationValueReader.keys(json, fields, path, required: fields);
    return CockpitWorkspaceMarker(
      schemaVersion: CockpitFoundationValueReader.string(
        json['schemaVersion'],
        '$path.schemaVersion',
      ),
      workspaceId: CockpitFoundationValueReader.id(
        json['workspaceId'],
        '$path.workspaceId',
      ),
      projectId: CockpitFoundationValueReader.id(
        json['projectId'],
        '$path.projectId',
      ),
      checkoutId: CockpitFoundationValueReader.id(
        json['checkoutId'],
        '$path.checkoutId',
      ),
      createdAt: CockpitFoundationValueReader.dateTime(
        json['createdAt'],
        '$path.createdAt',
      ),
    );
  }
}

final class CockpitWorkspaceResource {
  /// Creates a CockpitWorkspaceResource.
  CockpitWorkspaceResource({
    required this.workspaceId,
    required this.projectId,
    required this.checkoutId,
    required this.rootId,
    required this.canonicalPath,
    required this.filesystemIdentity,
    required this.state,
    required this.registeredAt,
    required this.updatedAt,
  }) {
    for (final entry in <String, String>{
      'workspaceId': workspaceId,
      'projectId': projectId,
      'checkoutId': checkoutId,
      'rootId': rootId,
    }.entries) {
      CockpitFoundationValueReader.id(entry.value, '\$.${entry.key}');
    }
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
    if (updatedAt.isBefore(registeredAt)) {
      throw const FormatException('Workspace updatedAt precedes registeredAt.');
    }
  }

  final String workspaceId;
  final String projectId;
  final String checkoutId;
  final String rootId;
  final String canonicalPath;
  final String filesystemIdentity;
  final CockpitWorkspaceState state;
  final DateTime registeredAt;
  final DateTime updatedAt;

  /// Encodes this CockpitWorkspaceResource as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'workspaceId': workspaceId,
    'projectId': projectId,
    'checkoutId': checkoutId,
    'rootId': rootId,
    'canonicalPath': canonicalPath,
    'filesystemIdentity': filesystemIdentity,
    'state': state.name,
    'registeredAt': registeredAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  /// Decodes a CockpitWorkspaceResource from a JSON object.
  factory CockpitWorkspaceResource.fromJson(
    Object? value, {
    String path = r'$',
    CockpitDecodePolicy decodePolicy = CockpitDecodePolicy.requests,
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    const fields = <String>{
      'workspaceId',
      'projectId',
      'checkoutId',
      'rootId',
      'canonicalPath',
      'filesystemIdentity',
      'state',
      'registeredAt',
      'updatedAt',
    };
    CockpitFoundationValueReader.keys(
      json,
      fields,
      path,
      required: fields,
      policy: decodePolicy,
    );
    return CockpitWorkspaceResource(
      workspaceId: CockpitFoundationValueReader.id(
        json['workspaceId'],
        '$path.workspaceId',
      ),
      projectId: CockpitFoundationValueReader.id(
        json['projectId'],
        '$path.projectId',
      ),
      checkoutId: CockpitFoundationValueReader.id(
        json['checkoutId'],
        '$path.checkoutId',
      ),
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
      state: CockpitEnumValue<CockpitWorkspaceState>.parse(
        json['state'],
        CockpitWorkspaceState.values,
        '$path.state',
        policy: CockpitDecodePolicy.requests,
      ).requireKnown(),
      registeredAt: CockpitFoundationValueReader.dateTime(
        json['registeredAt'],
        '$path.registeredAt',
      ),
      updatedAt: CockpitFoundationValueReader.dateTime(
        json['updatedAt'],
        '$path.updatedAt',
      ),
    );
  }
}

final class CockpitWorkspaceRegistration {
  /// Creates a CockpitWorkspaceRegistration.
  CockpitWorkspaceRegistration({required this.rootId, required this.path}) {
    CockpitFoundationValueReader.id(rootId, r'$.rootId');
    CockpitFoundationValueReader.absolutePath(path, r'$.path');
  }

  final String rootId;
  final String path;

  /// Encodes this CockpitWorkspaceRegistration as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'rootId': rootId,
    'path': path,
  };

  /// Decodes a CockpitWorkspaceRegistration from a JSON object.
  factory CockpitWorkspaceRegistration.fromJson(
    Object? value, {
    String path = r'$',
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    CockpitFoundationValueReader.keys(
      json,
      const <String>{'rootId', 'path'},
      path,
      required: const <String>{'rootId', 'path'},
    );
    return CockpitWorkspaceRegistration(
      rootId: CockpitFoundationValueReader.id(json['rootId'], '$path.rootId'),
      path: CockpitFoundationValueReader.absolutePath(
        json['path'],
        '$path.path',
      ),
    );
  }
}

final class CockpitWorkspaceRebind {
  /// Creates a CockpitWorkspaceRebind.
  CockpitWorkspaceRebind({
    required this.path,
    required this.expectedCheckoutId,
  }) {
    CockpitFoundationValueReader.absolutePath(path, r'$.path');
    CockpitFoundationValueReader.id(
      expectedCheckoutId,
      r'$.expectedCheckoutId',
    );
  }

  final String path;
  final String expectedCheckoutId;

  /// Encodes this CockpitWorkspaceRebind as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'expectedCheckoutId': expectedCheckoutId,
  };

  /// Decodes a CockpitWorkspaceRebind from a JSON object.
  factory CockpitWorkspaceRebind.fromJson(Object? value, {String path = r'$'}) {
    final json = CockpitFoundationValueReader.object(value, path);
    CockpitFoundationValueReader.keys(
      json,
      const <String>{'path', 'expectedCheckoutId'},
      path,
      required: const <String>{'path', 'expectedCheckoutId'},
    );
    return CockpitWorkspaceRebind(
      path: CockpitFoundationValueReader.absolutePath(
        json['path'],
        '$path.path',
      ),
      expectedCheckoutId: CockpitFoundationValueReader.id(
        json['expectedCheckoutId'],
        '$path.expectedCheckoutId',
      ),
    );
  }
}

final class CockpitWorkspaceRemoval {
  /// Creates a CockpitWorkspaceRemoval.
  CockpitWorkspaceRemoval({this.force = false, this.drainTimeoutMs = 30000}) {
    if (drainTimeoutMs < 0 || drainTimeoutMs > 300000) {
      throw const FormatException('Workspace drain timeout is invalid.');
    }
  }

  final bool force;
  final int drainTimeoutMs;

  /// Encodes this CockpitWorkspaceRemoval as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'force': force,
    'drainTimeoutMs': drainTimeoutMs,
  };

  /// Decodes a CockpitWorkspaceRemoval from a JSON object.
  factory CockpitWorkspaceRemoval.fromJson(
    Object? value, {
    String path = r'$',
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    CockpitFoundationValueReader.keys(
      json,
      const <String>{'force', 'drainTimeoutMs'},
      path,
      required: const <String>{'force', 'drainTimeoutMs'},
    );
    return CockpitWorkspaceRemoval(
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
