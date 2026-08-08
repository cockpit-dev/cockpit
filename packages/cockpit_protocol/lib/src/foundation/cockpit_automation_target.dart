import '../runtime/cockpit_target_kind.dart';
import 'cockpit_decode_policy.dart';
import 'cockpit_foundation_value_reader.dart';

enum CockpitAutomationTargetMode { development, automation }

enum CockpitAutomationTargetEnvironment {
  development,
  test,
  staging,
  production,
  unknown,
}

final class CockpitAutomationTargetResource {
  /// Creates a CockpitAutomationTargetResource.
  CockpitAutomationTargetResource({
    required this.targetId,
    required this.workspaceId,
    required this.platform,
    required this.deviceId,
    required this.targetKind,
    required this.mode,
    required this.environment,
    this.entrypoint,
    this.entrypointSha256,
    this.flavor,
    this.appId,
    this.sessionId,
  }) {
    CockpitFoundationValueReader.id(targetId, r'$.targetId');
    CockpitFoundationValueReader.id(workspaceId, r'$.workspaceId');
    CockpitFoundationValueReader.string(platform, r'$.platform', maximum: 32);
    CockpitFoundationValueReader.string(deviceId, r'$.deviceId', maximum: 256);
    if (entrypoint != null) {
      CockpitFoundationValueReader.relativePath(entrypoint, r'$.entrypoint');
    }
    if (entrypointSha256 != null) {
      if (entrypoint == null) {
        throw const FormatException(
          'Target entrypointSha256 requires an entrypoint.',
        );
      }
      CockpitFoundationValueReader.sha256(
        entrypointSha256,
        r'$.entrypointSha256',
      );
    }
    if (flavor != null) {
      CockpitFoundationValueReader.string(flavor, r'$.flavor', maximum: 128);
    }
    if (appId case final appId?) {
      CockpitFoundationValueReader.string(appId, r'$.appId', maximum: 512);
      if (appId.trim().isEmpty) {
        throw const FormatException('Target appId must not be blank.');
      }
    } else if (_targetKindRequiresAppId(targetKind)) {
      throw const FormatException('Target kind requires an appId.');
    }
    if (sessionId != null) {
      CockpitFoundationValueReader.id(sessionId, r'$.sessionId');
    }
  }

  final String targetId;
  final String workspaceId;
  final String platform;
  final String deviceId;
  final CockpitTargetKind targetKind;
  final CockpitAutomationTargetMode mode;
  final CockpitAutomationTargetEnvironment environment;
  final String? entrypoint;
  final String? entrypointSha256;
  final String? flavor;
  final String? appId;
  final String? sessionId;

  /// Encodes this CockpitAutomationTargetResource as a JSON object.
  Map<String, Object?> toJson() => <String, Object?>{
    'targetId': targetId,
    'workspaceId': workspaceId,
    'platform': platform,
    'deviceId': deviceId,
    'targetKind': targetKind.name,
    'mode': mode.name,
    'environment': environment.name,
    if (entrypoint != null) 'entrypoint': entrypoint,
    if (entrypointSha256 != null) 'entrypointSha256': entrypointSha256,
    if (flavor != null) 'flavor': flavor,
    if (appId != null) 'appId': appId,
    if (sessionId != null) 'sessionId': sessionId,
  };

  /// Decodes a CockpitAutomationTargetResource from a JSON object.
  factory CockpitAutomationTargetResource.fromJson(
    Object? value, {
    String path = r'$',
    CockpitDecodePolicy decodePolicy = CockpitDecodePolicy.requests,
  }) {
    final json = CockpitFoundationValueReader.object(value, path);
    const fields = <String>{
      'targetId',
      'workspaceId',
      'platform',
      'deviceId',
      'targetKind',
      'mode',
      'environment',
      'entrypoint',
      'entrypointSha256',
      'flavor',
      'appId',
      'sessionId',
    };
    CockpitFoundationValueReader.keys(
      json,
      fields,
      path,
      required: const <String>{
        'targetId',
        'workspaceId',
        'platform',
        'deviceId',
        'targetKind',
        'mode',
        'environment',
      },
      policy: decodePolicy,
    );
    return CockpitAutomationTargetResource(
      targetId: CockpitFoundationValueReader.id(
        json['targetId'],
        '$path.targetId',
      ),
      workspaceId: CockpitFoundationValueReader.id(
        json['workspaceId'],
        '$path.workspaceId',
      ),
      platform: CockpitFoundationValueReader.string(
        json['platform'],
        '$path.platform',
        maximum: 32,
      ),
      deviceId: CockpitFoundationValueReader.string(
        json['deviceId'],
        '$path.deviceId',
        maximum: 256,
      ),
      targetKind: _enumValue(
        json['targetKind'],
        CockpitTargetKind.values,
        '$path.targetKind',
      ),
      mode: _enumValue(
        json['mode'],
        CockpitAutomationTargetMode.values,
        '$path.mode',
      ),
      environment: _enumValue(
        json['environment'],
        CockpitAutomationTargetEnvironment.values,
        '$path.environment',
      ),
      entrypoint: json['entrypoint'] == null
          ? null
          : CockpitFoundationValueReader.relativePath(
              json['entrypoint'],
              '$path.entrypoint',
            ),
      entrypointSha256: json['entrypointSha256'] == null
          ? null
          : CockpitFoundationValueReader.sha256(
              json['entrypointSha256'],
              '$path.entrypointSha256',
            ),
      flavor: CockpitFoundationValueReader.optionalString(
        json['flavor'],
        '$path.flavor',
        maximum: 128,
      ),
      appId: CockpitFoundationValueReader.optionalString(
        json['appId'],
        '$path.appId',
        maximum: 512,
      ),
      sessionId: json['sessionId'] == null
          ? null
          : CockpitFoundationValueReader.id(
              json['sessionId'],
              '$path.sessionId',
            ),
    );
  }
}

bool _targetKindRequiresAppId(CockpitTargetKind kind) => switch (kind) {
  CockpitTargetKind.nativeApp ||
  CockpitTargetKind.desktopApp ||
  CockpitTargetKind.browserPage => true,
  CockpitTargetKind.flutterApp ||
  CockpitTargetKind.systemSurface ||
  CockpitTargetKind.device ||
  CockpitTargetKind.hostWorkspace => false,
};

T _enumValue<T extends Enum>(Object? value, List<T> values, String path) =>
    CockpitEnumValue<T>.parse(
      value,
      values,
      path,
      policy: CockpitDecodePolicy.requests,
    ).requireKnown();
