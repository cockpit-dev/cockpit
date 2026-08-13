import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../infrastructure/cockpit_process_manager.dart';
import 'cockpit_system_control_profile.dart';
import 'cockpit_system_control_adapter.dart';
import 'cockpit_ios_webdriver_agent_client.dart';
import 'cockpit_linux_at_spi_tree.dart';
import 'cockpit_web_cdp_client.dart';
import 'cockpit_system_control_registry.dart';

export 'cockpit_system_control_action.dart';
export 'cockpit_system_control_profile.dart';
export 'cockpit_system_control_registry.dart';

final class CockpitSystemControlDescribeRequest {
  const CockpitSystemControlDescribeRequest({
    required this.platform,
    this.deviceId,
    this.appId,
    this.processId,
    this.metadata = const <String, Object?>{},
  });

  final String platform;
  final String? deviceId;
  final String? appId;
  final int? processId;
  final Map<String, Object?> metadata;
}

final class CockpitSystemControlDescribeResult {
  const CockpitSystemControlDescribeResult({
    required this.profile,
    required this.recommendedNextStep,
    this.metadata = const <String, Object?>{},
  });

  final CockpitSystemControlProfile profile;
  final String recommendedNextStep;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => <String, Object?>{
    ...profile.toJson(),
    if (metadata.isNotEmpty) 'metadata': metadata,
    'recommendedNextStep': recommendedNextStep,
  };
}

typedef CockpitSystemControlDescribeFunction =
    Future<CockpitSystemControlDescribeResult> Function(
      CockpitSystemControlDescribeRequest request,
    );
typedef CockpitAndroidDeviceStateProbe =
    Future<CockpitAndroidDeviceProbeResult> Function(
      String deviceId, {
      required Duration timeout,
    });

final class CockpitAndroidDeviceProbeResult {
  const CockpitAndroidDeviceProbeResult({
    required this.reachable,
    this.state,
    this.failureReason,
  });

  const CockpitAndroidDeviceProbeResult.reachable(String state)
    : this(reachable: true, state: state);

  const CockpitAndroidDeviceProbeResult.blocked({
    required String failureReason,
    String? state,
  }) : this(reachable: false, state: state, failureReason: failureReason);

  final bool reachable;
  final String? state;
  final String? failureReason;
}

Future<CockpitAndroidDeviceProbeResult> cockpitProbeAndroidDeviceState(
  CockpitProcessManager processManager,
  String deviceId, {
  required Duration timeout,
}) async {
  try {
    final result = await processManager
        .run('adb', <String>['-s', deviceId, 'get-state'])
        .timeout(timeout);
    final state = _processOutputText(result.stdout).trim();
    if (result.exitCode == 0 && state == 'device') {
      return CockpitAndroidDeviceProbeResult.reachable(state);
    }
    final stderr = _processOutputText(result.stderr).trim();
    return CockpitAndroidDeviceProbeResult.blocked(
      state: state.isEmpty ? null : state,
      failureReason: stderr.isEmpty ? 'adbDeviceNotReady' : stderr,
    );
  } on TimeoutException {
    return const CockpitAndroidDeviceProbeResult.blocked(
      failureReason: 'adbDeviceProbeTimedOut',
    );
  } on ProcessException catch (error) {
    return CockpitAndroidDeviceProbeResult.blocked(
      failureReason: error.message.isEmpty ? 'adbUnavailable' : error.message,
    );
  } on Object catch (error) {
    return CockpitAndroidDeviceProbeResult.blocked(failureReason: '$error');
  }
}

String _processOutputText(Object? output) {
  if (output == null) {
    return '';
  }
  if (output is String) {
    return output;
  }
  if (output is List<int>) {
    return utf8.decode(output, allowMalformed: true);
  }
  return '$output';
}

final class CockpitSystemControlService {
  CockpitSystemControlService({
    CockpitProcessManager? processManager,
    CockpitSystemControlRegistry registry =
        const CockpitSystemControlRegistry(),
    CockpitIosWdaEndpointProbe iosWdaEndpointProbe = cockpitProbeIosWdaEndpoint,
    CockpitAndroidDeviceStateProbe? androidDeviceStateProbe,
    CockpitLinuxAtSpiProbe linuxAtSpiProbe = cockpitProbeLinuxAtSpi,
    CockpitWebCdpProbe webCdpProbe = cockpitProbeWebCdp,
    bool? linuxHost,
    Map<String, String>? environment,
  }) : _processManager = processManager ?? const LocalCockpitProcessManager(),
       _registry = registry,
       _iosWdaEndpointProbe = iosWdaEndpointProbe,
       _androidDeviceStateProbe = androidDeviceStateProbe,
       _linuxAtSpiProbe = linuxAtSpiProbe,
       _webCdpProbe = webCdpProbe,
       _linuxHost = linuxHost ?? Platform.isLinux,
       _environment = environment ?? Platform.environment;

  final CockpitProcessManager _processManager;
  final CockpitSystemControlRegistry _registry;
  final CockpitIosWdaEndpointProbe _iosWdaEndpointProbe;
  final CockpitAndroidDeviceStateProbe? _androidDeviceStateProbe;
  final CockpitLinuxAtSpiProbe _linuxAtSpiProbe;
  final CockpitWebCdpProbe _webCdpProbe;
  final bool _linuxHost;
  final Map<String, String> _environment;
  CockpitLinuxAtSpiProbeResult? _linuxAtSpiProbeCache;
  DateTime? _linuxAtSpiProbeCachedAt;
  final Map<String, ({CockpitWebCdpProbeResult result, DateTime at})>
  _webCdpProbeCache =
      <String, ({CockpitWebCdpProbeResult result, DateTime at})>{};

  Future<CockpitSystemControlDescribeResult> describe(
    CockpitSystemControlDescribeRequest request,
  ) async {
    final adapter = _registry.resolve(request.platform);
    final metadata = await _resolvedMetadata(request);
    final profile = adapter.describe(
      CockpitSystemControlTargetContext(
        deviceId: request.deviceId,
        appId: request.appId,
        processId: request.processId,
        metadata: metadata,
      ),
    );
    return CockpitSystemControlDescribeResult(
      profile: profile,
      recommendedNextStep: profile.recommendedNextStep,
      metadata: metadata,
    );
  }

  Future<Map<String, Object?>> _resolvedMetadata(
    CockpitSystemControlDescribeRequest request,
  ) async {
    final metadata = <String, Object?>{...request.metadata};
    if (request.platform.trim().toLowerCase() == 'android') {
      return _resolveAndroidMetadata(metadata, request.deviceId);
    }
    if (request.platform.trim().toLowerCase() == 'linux') {
      return _resolveLinuxMetadata(metadata);
    }
    if (request.platform.trim().toLowerCase() == 'web') {
      return _resolveWebMetadata(metadata);
    }
    if (request.platform.trim().toLowerCase() != 'ios') {
      return metadata;
    }
    var wdaUrl = metadata['wdaUrl'];
    if (wdaUrl is! String || wdaUrl.trim().isEmpty) {
      final configured = _environment['FLUTTER_COCKPIT_IOS_WDA_URL']?.trim();
      if (configured == null || configured.isEmpty) {
        return _discoverLocalWdaMetadata(metadata);
      }
      metadata['wdaUrl'] = configured;
      wdaUrl = configured;
    }
    return _resolveExplicitWdaMetadata(metadata, wdaUrl.trim());
  }

  Future<Map<String, Object?>> _resolveLinuxMetadata(
    Map<String, Object?> metadata,
  ) async {
    if (!_linuxHost) {
      metadata['linuxAtSpiAvailable'] = false;
      metadata['linuxAtSpiFailureReason'] = 'linuxHostRequired';
      return metadata;
    }
    final now = DateTime.now();
    final cached = _linuxAtSpiProbeCache;
    final cachedAt = _linuxAtSpiProbeCachedAt;
    final cacheValid =
        cached != null &&
        cachedAt != null &&
        now.difference(cachedAt) <
            (cached.available
                ? const Duration(seconds: 5)
                : const Duration(seconds: 2));
    final result = cacheValid
        ? cached
        : await _linuxAtSpiProbe(timeout: const Duration(milliseconds: 750));
    _linuxAtSpiProbeCache = result;
    _linuxAtSpiProbeCachedAt = now;
    metadata['linuxAtSpiAvailable'] = result.available;
    if (result.failureReason case final reason?) {
      metadata['linuxAtSpiFailureReason'] = reason;
    }
    return metadata;
  }

  Future<Map<String, Object?>> _resolveWebMetadata(
    Map<String, Object?> metadata,
  ) async {
    final rawUrl = metadata['cdpUrl'];
    if (rawUrl is! String || rawUrl.trim().isEmpty) {
      metadata['webCdpAvailable'] = false;
      metadata['webCdpFailureReason'] = 'cdpEndpointNotConfigured';
      return metadata;
    }
    final key = rawUrl.trim();
    final now = DateTime.now();
    final cached = _webCdpProbeCache[key];
    final valid =
        cached != null &&
        now.difference(cached.at) <
            (cached.result.available
                ? const Duration(seconds: 5)
                : const Duration(seconds: 2));
    final result = valid
        ? cached.result
        : await _webCdpProbe(
            cdpUrl: rawUrl.trim(),
            timeout: const Duration(seconds: 1),
          );
    _webCdpProbeCache[key] = (result: result, at: now);
    metadata['webCdpAvailable'] = result.available;
    if (result.webSocketUrl case final value?) {
      metadata['cdpWebSocketUrl'] = value;
    }
    if (result.pageId case final value?) metadata['cdpPageId'] = value;
    if (result.pageUrl case final value?) metadata['cdpPageUrl'] = value;
    if (result.failureReason case final value?) {
      metadata['webCdpFailureReason'] = value;
    }
    return metadata;
  }

  Future<Map<String, Object?>> _resolveAndroidMetadata(
    Map<String, Object?> metadata,
    String? deviceId,
  ) async {
    if (metadata['androidDeviceReachable'] is bool) {
      return metadata;
    }
    final normalizedDeviceId = deviceId?.trim();
    if (normalizedDeviceId == null || normalizedDeviceId.isEmpty) {
      return metadata;
    }
    final probe =
        _androidDeviceStateProbe ??
        (String id, {required Duration timeout}) =>
            cockpitProbeAndroidDeviceState(
              _processManager,
              id,
              timeout: timeout,
            );
    final result = await probe(
      normalizedDeviceId,
      timeout: const Duration(seconds: 2),
    );
    metadata['androidDeviceReachable'] = result.reachable;
    if (result.state != null && result.state!.trim().isNotEmpty) {
      metadata['androidDeviceState'] = result.state!.trim();
    }
    if (!result.reachable) {
      metadata['androidDeviceFailureReason'] =
          result.failureReason ?? 'adbDeviceNotReady';
    }
    return metadata;
  }

  Future<Map<String, Object?>> _discoverLocalWdaMetadata(
    Map<String, Object?> metadata,
  ) async {
    for (final uri in _defaultIosWdaUris) {
      final reachable = await _iosWdaEndpointProbe(
        uri,
        timeout: const Duration(milliseconds: 250),
      );
      if (reachable) {
        metadata['wdaUrl'] = uri.toString();
        metadata['wdaReachable'] = true;
        metadata['wdaDiscovered'] = true;
        return metadata;
      }
    }
    metadata['wdaReachable'] = false;
    metadata['wdaFailureReason'] = 'wdaEndpointNotConfigured';
    return metadata;
  }

  Future<Map<String, Object?>> _resolveExplicitWdaMetadata(
    Map<String, Object?> metadata,
    String wdaUrl,
  ) async {
    if (wdaUrl.isEmpty) {
      return metadata;
    }
    final uri = Uri.tryParse(wdaUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      metadata['wdaReachable'] = false;
      metadata['wdaFailureReason'] = 'invalidWdaUrl';
      return metadata;
    }
    final reachable = await _iosWdaEndpointProbe(
      uri,
      timeout: const Duration(seconds: 2),
    );
    metadata['wdaReachable'] = reachable;
    if (!reachable) {
      metadata['wdaFailureReason'] = 'wdaEndpointUnreachable';
    }
    return metadata;
  }
}

final List<Uri> _defaultIosWdaUris = <Uri>[
  Uri.parse('http://127.0.0.1:8100'),
  Uri.parse('http://localhost:8100'),
];
