import 'package:cockpit_protocol/cockpit_protocol.dart';

import '../adapters/cockpit_recording_adapter.dart';
import '../platform/ios/cockpit_ios_device_connection.dart';
import '../remote/cockpit_remote_recording_adapter.dart';
import '../remote/cockpit_remote_session_client.dart';
import '../session/cockpit_remote_session_handle.dart';
import 'cockpit_adb_recording_adapter.dart';
import 'cockpit_host_recording_adapter.dart';
import 'cockpit_linux_recording_adapter.dart';
import 'cockpit_macos_recording_adapter.dart';
import 'cockpit_recording_strategy_resolution.dart';
import 'cockpit_simctl_recording_adapter.dart';
import 'cockpit_windows_recording_adapter.dart';

typedef CockpitRemoteRecordingAdapterFactory =
    CockpitRecordingAdapter Function(CockpitRemoteSessionClient client);
typedef CockpitAdbRecordingAdapterFactory =
    CockpitRecordingAdapter Function(String deviceId);
typedef CockpitSimctlRecordingAdapterFactory =
    CockpitRecordingAdapter Function(String deviceId);
typedef CockpitMacosRecordingAdapterFactory =
    CockpitRecordingAdapter Function(String appId, {int? processId});
typedef CockpitWindowsRecordingAdapterFactory =
    CockpitRecordingAdapter Function(String appId, {int? processId});
typedef CockpitLinuxRecordingAdapterFactory =
    CockpitRecordingAdapter Function(String appId, {int? processId});

final class CockpitRecordingStrategyResolver {
  const CockpitRecordingStrategyResolver({
    this.remoteAdapterFactory = _defaultRemoteAdapterFactory,
    this.adbAdapterFactory = _defaultAdbAdapterFactory,
    this.simctlAdapterFactory = _defaultSimctlAdapterFactory,
    this.macosAdapterFactory = _defaultMacosAdapterFactory,
    this.windowsAdapterFactory = _defaultWindowsAdapterFactory,
    this.linuxAdapterFactory = _defaultLinuxAdapterFactory,
  });

  final CockpitRemoteRecordingAdapterFactory remoteAdapterFactory;
  final CockpitAdbRecordingAdapterFactory adbAdapterFactory;
  final CockpitSimctlRecordingAdapterFactory simctlAdapterFactory;
  final CockpitMacosRecordingAdapterFactory macosAdapterFactory;
  final CockpitWindowsRecordingAdapterFactory windowsAdapterFactory;
  final CockpitLinuxRecordingAdapterFactory linuxAdapterFactory;

  CockpitRecordingAdapter? resolve({
    required String platform,
    required CockpitRecordingRequest? recording,
    required CockpitRemoteSessionClient client,
    CockpitRemoteSessionHandle? sessionHandle,
    String? androidDeviceId,
    String? iosDeviceId,
    String? platformAppId,
    int? processId,
    bool preferActiveHostSession = false,
  }) {
    return resolveDetailed(
      platform: platform,
      recording: recording,
      client: client,
      sessionHandle: sessionHandle,
      androidDeviceId: androidDeviceId,
      iosDeviceId: iosDeviceId,
      platformAppId: platformAppId,
      processId: processId,
      preferActiveHostSession: preferActiveHostSession,
    )?.adapter;
  }

  CockpitRecordingStrategyResolution? resolveDetailed({
    required String platform,
    required CockpitRecordingRequest? recording,
    required CockpitRemoteSessionClient client,
    CockpitRemoteSessionHandle? sessionHandle,
    String? androidDeviceId,
    String? iosDeviceId,
    String? platformAppId,
    int? processId,
    bool preferActiveHostSession = false,
  }) {
    if (recording == null) {
      return null;
    }

    final normalizedPlatform = platform.trim().toLowerCase();
    final candidates = _orderedCandidates(
      platform: normalizedPlatform,
      mode: recording.mode,
      client: client,
      sessionHandle: sessionHandle,
      androidDeviceId: androidDeviceId,
      iosDeviceId: iosDeviceId,
      platformAppId: platformAppId,
      processId: processId,
      preferActiveHostSession: preferActiveHostSession,
    );
    return _resolveFromCandidates(
      platform: normalizedPlatform,
      recording: recording,
      candidates: candidates,
      preferActiveHostSession: preferActiveHostSession,
    );
  }

  Future<CockpitRecordingStrategyResolution?> resolveDetailedForStop({
    required String platform,
    required CockpitRecordingRequest? recording,
    required CockpitRemoteSessionClient client,
    CockpitRemoteSessionHandle? sessionHandle,
    String? androidDeviceId,
    String? iosDeviceId,
    String? platformAppId,
    int? processId,
  }) async {
    if (recording == null) {
      return null;
    }

    final normalizedPlatform = platform.trim().toLowerCase();
    final candidates = _orderedStopCandidates(
      platform: normalizedPlatform,
      client: client,
      sessionHandle: sessionHandle,
      androidDeviceId: androidDeviceId,
      iosDeviceId: iosDeviceId,
      platformAppId: platformAppId,
      processId: processId,
    );
    final activeSessionCandidate = await _preferredLiveActiveSessionCandidate(
      candidates,
    );
    if (activeSessionCandidate != null) {
      final desiredLayer =
          recording.layer ??
          _preferredLayerForMode(normalizedPlatform, recording.mode);
      final effectiveLayer = activeSessionCandidate.layer;
      final fallbackUsed =
          desiredLayer != null && effectiveLayer != desiredLayer;
      return _buildResolution(
        candidate: activeSessionCandidate,
        request: recording,
        effectiveLayer: effectiveLayer,
        fallbackUsed: fallbackUsed,
        fallbackReason: fallbackUsed
            ? 'An active host recording session is already running. '
                  'Reusing ${effectiveLayer.jsonValue} to stop the active host recording.'
            : null,
      );
    }

    final remoteCandidate = _firstRemoteCandidate(candidates);
    if (remoteCandidate != null) {
      return _buildResolution(
        candidate: remoteCandidate,
        request: recording,
        effectiveLayer: remoteCandidate.layer,
      );
    }

    return _resolveFromCandidates(
      platform: normalizedPlatform,
      recording: recording,
      candidates: candidates,
      preferActiveHostSession: true,
    );
  }

  CockpitRecordingStrategyResolution _resolveFromCandidates({
    required String platform,
    required CockpitRecordingRequest recording,
    required List<_RecordingCandidate> candidates,
    required bool preferActiveHostSession,
  }) {
    final desiredLayer =
        recording.layer ?? _preferredLayerForMode(platform, recording.mode);

    final preferredActiveSessionCandidate = _preferredActiveSessionCandidate(
      candidates,
      preferActiveHostSession,
    );
    if (preferredActiveSessionCandidate != null) {
      final effectiveLayer = preferredActiveSessionCandidate.layer;
      final fallbackUsed =
          desiredLayer != null && effectiveLayer != desiredLayer;
      return _buildResolution(
        candidate: preferredActiveSessionCandidate,
        request: recording,
        effectiveLayer: effectiveLayer,
        fallbackUsed: fallbackUsed,
        fallbackReason: fallbackUsed
            ? 'An active host recording session is already running. '
                  'Reusing ${effectiveLayer.jsonValue} to stop the active host recording.'
            : null,
      );
    }

    if (desiredLayer != null) {
      for (final candidate in candidates) {
        if (candidate.layer == desiredLayer) {
          return _buildResolution(
            candidate: candidate,
            request: recording,
            effectiveLayer: desiredLayer,
            runtimeFallbackCandidates: _runtimeFallbackCandidatesFor(
              request: recording,
              candidates: candidates,
              selectedCandidate: candidate,
            ),
          );
        }
      }

      if (!recording.allowsFallback) {
        return CockpitRecordingStrategyResolution(
          implementation: 'unavailable',
          requestedMode: recording.mode,
          requestedLayer: recording.layer,
          fallbackUsed: false,
          unsupportedReason:
              'Recording layer ${desiredLayer.jsonValue} is unavailable on $platform.',
        );
      }
    } else if (!recording.allowsFallback) {
      return CockpitRecordingStrategyResolution(
        implementation: 'unavailable',
        requestedMode: recording.mode,
        requestedLayer: recording.layer,
        fallbackUsed: false,
        unsupportedReason:
            'Recording mode ${recording.mode.jsonValue} is unavailable on $platform.',
      );
    }

    if (candidates.isEmpty) {
      return CockpitRecordingStrategyResolution(
        implementation: 'unavailable',
        requestedMode: recording.mode,
        requestedLayer: recording.layer,
        fallbackUsed: false,
        unsupportedReason: 'No recording strategy is available for $platform.',
      );
    }

    final fallbackCandidate = desiredLayer == null
        ? candidates.first
        : _closestLayerCandidate(candidates, desiredLayer);
    return _buildResolution(
      candidate: fallbackCandidate,
      request: recording,
      effectiveLayer: fallbackCandidate.layer,
      fallbackUsed: true,
      fallbackReason: desiredLayer == null
          ? 'Recording mode ${recording.mode.jsonValue} is unavailable on $platform. Falling back to ${fallbackCandidate.layer.jsonValue}.'
          : 'Recording layer ${desiredLayer.jsonValue} is unavailable on $platform. Falling back to ${fallbackCandidate.layer.jsonValue}.',
      runtimeFallbackCandidates: _runtimeFallbackCandidatesFor(
        request: recording,
        candidates: candidates,
        selectedCandidate: fallbackCandidate,
      ),
    );
  }

  _RecordingCandidate? _preferredActiveSessionCandidate(
    List<_RecordingCandidate> candidates,
    bool preferActiveHostSession,
  ) {
    if (!preferActiveHostSession || candidates.isEmpty) {
      return null;
    }
    final candidate = candidates.first;
    final sessionKey = candidate.sessionKey;
    if (sessionKey == null ||
        !cockpitHasActiveHostRecordingSession(sessionKey)) {
      return null;
    }
    return candidate;
  }

  _RecordingCandidate? _firstRemoteCandidate(
    List<_RecordingCandidate> candidates,
  ) {
    for (final candidate in candidates) {
      if (candidate.implementation == 'remote') {
        return candidate;
      }
    }
    return null;
  }

  Future<_RecordingCandidate?> _preferredLiveActiveSessionCandidate(
    List<_RecordingCandidate> candidates,
  ) async {
    for (final candidate in candidates) {
      final checker = candidate.liveSessionChecker;
      if (checker == null) {
        continue;
      }
      if (await checker()) {
        return candidate;
      }
    }
    return null;
  }

  CockpitRecordingStrategyResolution _buildResolution({
    required _RecordingCandidate candidate,
    required CockpitRecordingRequest request,
    required CockpitRecordingLayer effectiveLayer,
    bool fallbackUsed = false,
    String? fallbackReason,
    List<_RecordingCandidate> runtimeFallbackCandidates =
        const <_RecordingCandidate>[],
  }) {
    return CockpitRecordingStrategyResolution(
      implementation: candidate.implementation,
      adapter: _PolicyAwareRecordingAdapter(
        delegate: candidate.factory(),
        delegateImplementation: candidate.implementation,
        runtimeFallbackCandidates: runtimeFallbackCandidates,
        requestedMode: request.mode,
        requestedLayer: request.layer,
        effectiveLayer: effectiveLayer,
        fallbackUsed: fallbackUsed,
        fallbackReason: fallbackReason,
      ),
      requestedMode: request.mode,
      requestedLayer: request.layer,
      effectiveLayer: effectiveLayer,
      fallbackUsed: fallbackUsed,
      fallbackReason: fallbackReason,
    );
  }

  List<_RecordingCandidate> _orderedCandidates({
    required String platform,
    required CockpitRecordingMode mode,
    required CockpitRemoteSessionClient client,
    required CockpitRemoteSessionHandle? sessionHandle,
    required String? androidDeviceId,
    required String? iosDeviceId,
    required String? platformAppId,
    required int? processId,
    required bool preferActiveHostSession,
  }) {
    final remote = _RecordingCandidate(
      implementation: 'remote',
      layer: _remoteLayerForPlatform(platform),
      factory: () => remoteAdapterFactory(client),
    );
    switch (platform) {
      case 'android':
        return _mobileCandidates(
          mode: mode,
          remote: remote,
          host: (androidDeviceId == null || androidDeviceId.isEmpty)
              ? null
              : _RecordingCandidate(
                  implementation: 'adb',
                  layer: CockpitRecordingLayer.system,
                  factory: () => adbAdapterFactory(androidDeviceId),
                  sessionKey: 'adb:$androidDeviceId',
                ),
          activeHostSession:
              androidDeviceId != null &&
              androidDeviceId.isNotEmpty &&
              cockpitHasActiveAdbRecordingSession(androidDeviceId),
          preferActiveHostSession: preferActiveHostSession,
        );
      case 'ios':
        final simulatorDeviceId =
            (iosDeviceId == null ||
                iosDeviceId.isEmpty ||
                !cockpitLooksLikeIosSimulatorDeviceId(iosDeviceId))
            ? null
            : iosDeviceId;
        return _mobileCandidates(
          mode: mode,
          remote: remote,
          host: (simulatorDeviceId == null || simulatorDeviceId.isEmpty)
              ? null
              : _RecordingCandidate(
                  implementation: 'simctl',
                  layer: CockpitRecordingLayer.system,
                  factory: () => simctlAdapterFactory(simulatorDeviceId),
                ),
          activeHostSession:
              simulatorDeviceId != null &&
              simulatorDeviceId.isNotEmpty &&
              cockpitHasActiveSimctlRecordingSession(simulatorDeviceId),
          preferActiveHostSession: preferActiveHostSession,
        );
      case 'macos':
        return _desktopCandidates(
          mode: mode,
          remote: remote,
          host: _desktopHostCandidate(
            platform: platform,
            appId: platformAppId ?? sessionHandle?.effectivePlatformAppId,
          ),
          preferActiveHostSession: preferActiveHostSession,
        );
      case 'windows':
        return _desktopCandidates(
          mode: mode,
          remote: remote,
          host: _desktopHostCandidate(
            platform: platform,
            appId: platformAppId ?? sessionHandle?.effectivePlatformAppId,
            processId: processId ?? sessionHandle?.processId,
          ),
          preferActiveHostSession: preferActiveHostSession,
        );
      case 'linux':
        return _desktopCandidates(
          mode: mode,
          remote: remote,
          host: _desktopHostCandidate(
            platform: platform,
            appId: platformAppId ?? sessionHandle?.effectivePlatformAppId,
            processId: processId ?? sessionHandle?.processId,
          ),
          preferActiveHostSession: preferActiveHostSession,
        );
      case 'web':
        return <_RecordingCandidate>[remote];
      default:
        return <_RecordingCandidate>[remote];
    }
  }

  List<_RecordingCandidate> _orderedStopCandidates({
    required String platform,
    required CockpitRemoteSessionClient client,
    required CockpitRemoteSessionHandle? sessionHandle,
    required String? androidDeviceId,
    required String? iosDeviceId,
    required String? platformAppId,
    required int? processId,
  }) {
    final remote = _RecordingCandidate(
      implementation: 'remote',
      layer: _remoteLayerForPlatform(platform),
      factory: () => remoteAdapterFactory(client),
    );
    switch (platform) {
      case 'android':
        final host = (androidDeviceId == null || androidDeviceId.isEmpty)
            ? null
            : _RecordingCandidate(
                implementation: 'adb',
                layer: CockpitRecordingLayer.system,
                factory: () => adbAdapterFactory(androidDeviceId),
                sessionKey: 'adb:$androidDeviceId',
                liveSessionChecker: () =>
                    cockpitHasLiveAdbRecordingSession(androidDeviceId),
              );
        return <_RecordingCandidate>[remote, ?host];
      case 'ios':
        final simulatorDeviceId =
            (iosDeviceId == null ||
                iosDeviceId.isEmpty ||
                !cockpitLooksLikeIosSimulatorDeviceId(iosDeviceId))
            ? null
            : iosDeviceId;
        final host = (simulatorDeviceId == null || simulatorDeviceId.isEmpty)
            ? null
            : _RecordingCandidate(
                implementation: 'simctl',
                layer: CockpitRecordingLayer.system,
                factory: () => simctlAdapterFactory(simulatorDeviceId),
                sessionKey: 'simctl:$simulatorDeviceId',
                liveSessionChecker: () =>
                    cockpitHasLiveSimctlRecordingSession(simulatorDeviceId),
              );
        return <_RecordingCandidate>[remote, ?host];
      case 'macos':
        final host = _desktopHostCandidate(
          platform: platform,
          appId: platformAppId ?? sessionHandle?.effectivePlatformAppId,
        );
        return <_RecordingCandidate>[remote, ?host];
      case 'windows':
        final host = _desktopHostCandidate(
          platform: platform,
          appId: platformAppId ?? sessionHandle?.effectivePlatformAppId,
          processId: processId ?? sessionHandle?.processId,
        );
        return <_RecordingCandidate>[remote, ?host];
      case 'linux':
        final host = _desktopHostCandidate(
          platform: platform,
          appId: platformAppId ?? sessionHandle?.effectivePlatformAppId,
          processId: processId ?? sessionHandle?.processId,
        );
        return <_RecordingCandidate>[remote, ?host];
      default:
        return <_RecordingCandidate>[remote];
    }
  }

  _RecordingCandidate? _desktopHostCandidate({
    required String platform,
    required String? appId,
    int? processId,
  }) {
    final resolvedAppId = _desktopHostAppId(
      platform: platform,
      appId: appId,
      processId: processId,
    );
    if (resolvedAppId == null || resolvedAppId.isEmpty) {
      return null;
    }
    final hostCandidate = switch (platform) {
      'macos' => _RecordingCandidate(
        implementation: 'macosHost',
        layer: CockpitRecordingLayer.hostScreen,
        factory: () => macosAdapterFactory(resolvedAppId, processId: processId),
        sessionKey: 'macos:${processId ?? resolvedAppId}',
        liveSessionChecker: () => cockpitHasLiveHostRecordingSession(
          'macos:${processId ?? resolvedAppId}',
        ),
      ),
      'windows' => _RecordingCandidate(
        implementation: 'windowsHost',
        layer: CockpitRecordingLayer.hostScreen,
        factory: () =>
            windowsAdapterFactory(resolvedAppId, processId: processId),
        sessionKey: _desktopHostSessionKey(
          platform: platform,
          appId: resolvedAppId,
          processId: processId,
        ),
        liveSessionChecker: () => cockpitHasLiveHostRecordingSession(
          _desktopHostSessionKey(
            platform: platform,
            appId: resolvedAppId,
            processId: processId,
          ),
        ),
      ),
      'linux' => _RecordingCandidate(
        implementation: 'linuxHost',
        layer: CockpitRecordingLayer.hostScreen,
        factory: () => linuxAdapterFactory(resolvedAppId, processId: processId),
        sessionKey: _desktopHostSessionKey(
          platform: platform,
          appId: resolvedAppId,
          processId: processId,
        ),
        liveSessionChecker: () => cockpitHasLiveHostRecordingSession(
          _desktopHostSessionKey(
            platform: platform,
            appId: resolvedAppId,
            processId: processId,
          ),
        ),
      ),
      _ => null,
    };
    return hostCandidate;
  }

  String? _desktopHostAppId({
    required String platform,
    required String? appId,
    required int? processId,
  }) {
    final trimmed = appId?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    if ((platform == 'windows' || platform == 'linux') && processId != null) {
      return 'pid-$processId';
    }
    return null;
  }

  String _desktopHostSessionKey({
    required String platform,
    required String appId,
    int? processId,
  }) {
    if ((platform == 'windows' || platform == 'linux') && processId != null) {
      return '$platform:$processId';
    }
    return '$platform:$appId';
  }

  List<_RecordingCandidate> _mobileCandidates({
    required CockpitRecordingMode mode,
    required _RecordingCandidate remote,
    required _RecordingCandidate? host,
    required bool activeHostSession,
    required bool preferActiveHostSession,
  }) {
    final ordered = <_RecordingCandidate>[];
    if (activeHostSession && host != null) {
      ordered.add(host);
      ordered.add(remote);
      return ordered;
    }
    if (preferActiveHostSession) {
      ordered.add(remote);
      if (host != null) {
        ordered.add(host);
      }
      return ordered;
    }
    final hostFirst =
        mode == CockpitRecordingMode.auto || mode == CockpitRecordingMode.full;
    if (hostFirst && host != null) {
      ordered.add(host);
    }
    ordered.add(remote);
    if (!hostFirst && host != null) {
      ordered.add(host);
    }
    return ordered;
  }

  List<_RecordingCandidate> _desktopCandidates({
    required CockpitRecordingMode mode,
    required _RecordingCandidate remote,
    required _RecordingCandidate? host,
    required bool preferActiveHostSession,
  }) {
    final ordered = <_RecordingCandidate>[];
    final activeHost =
        preferActiveHostSession &&
        host != null &&
        host.sessionKey != null &&
        cockpitHasActiveHostRecordingSession(host.sessionKey!);
    if (activeHost) {
      ordered.add(host);
      ordered.add(remote);
      return ordered;
    }
    if (preferActiveHostSession) {
      ordered.add(remote);
      if (host != null) {
        ordered.add(host);
      }
      return ordered;
    }
    final hostFirst =
        mode == CockpitRecordingMode.auto || mode == CockpitRecordingMode.full;
    if (hostFirst && host != null) {
      ordered.add(host);
    }
    ordered.add(remote);
    if (!hostFirst && host != null) {
      ordered.add(host);
    }
    return ordered;
  }

  CockpitRecordingLayer? _preferredLayerForMode(
    String platform,
    CockpitRecordingMode mode,
  ) {
    return switch (mode) {
      CockpitRecordingMode.auto => switch (platform) {
        'macos' || 'windows' || 'linux' => CockpitRecordingLayer.hostScreen,
        _ => _remoteLayerForPlatform(platform),
      },
      CockpitRecordingMode.cheap => _remoteLayerForPlatform(platform),
      CockpitRecordingMode.native => switch (platform) {
        'web' => null,
        _ => _remoteLayerForPlatform(platform),
      },
      CockpitRecordingMode.full => switch (platform) {
        'macos' || 'windows' || 'linux' => CockpitRecordingLayer.hostScreen,
        _ => _remoteLayerForPlatform(platform),
      },
    };
  }

  CockpitRecordingLayer _remoteLayerForPlatform(String platform) {
    return switch (platform) {
      'android' || 'ios' => CockpitRecordingLayer.system,
      'web' => CockpitRecordingLayer.hostScreen,
      _ => CockpitRecordingLayer.appWindow,
    };
  }

  _RecordingCandidate _closestLayerCandidate(
    List<_RecordingCandidate> candidates,
    CockpitRecordingLayer desiredLayer,
  ) {
    var best = candidates.first;
    var bestScore = _fallbackDistance(best.layer, desiredLayer);
    for (final candidate in candidates.skip(1)) {
      final score = _fallbackDistance(candidate.layer, desiredLayer);
      if (score < bestScore ||
          (score == bestScore &&
              candidate.layer.coverageRank > best.layer.coverageRank)) {
        best = candidate;
        bestScore = score;
      }
    }
    return best;
  }

  List<_RecordingCandidate> _runtimeFallbackCandidatesFor({
    required CockpitRecordingRequest request,
    required List<_RecordingCandidate> candidates,
    required _RecordingCandidate selectedCandidate,
  }) {
    if (!request.allowsFallback) {
      return const <_RecordingCandidate>[];
    }
    return candidates
        .where((candidate) => !identical(candidate, selectedCandidate))
        .toList(growable: false);
  }

  int _fallbackDistance(
    CockpitRecordingLayer candidate,
    CockpitRecordingLayer desired,
  ) {
    return (candidate.coverageRank - desired.coverageRank).abs();
  }

  static CockpitRecordingAdapter _defaultRemoteAdapterFactory(
    CockpitRemoteSessionClient client,
  ) {
    return CockpitRemoteRecordingAdapter(client: client);
  }

  static CockpitRecordingAdapter _defaultAdbAdapterFactory(String deviceId) {
    return CockpitAdbRecordingAdapter(deviceId: deviceId);
  }

  static CockpitRecordingAdapter _defaultSimctlAdapterFactory(String deviceId) {
    return CockpitSimctlRecordingAdapter(deviceId: deviceId);
  }

  static CockpitRecordingAdapter _defaultMacosAdapterFactory(
    String appId, {
    int? processId,
  }) {
    return CockpitMacosRecordingAdapter(appId: appId, processId: processId);
  }

  static CockpitRecordingAdapter _defaultWindowsAdapterFactory(
    String appId, {
    int? processId,
  }) {
    return CockpitWindowsRecordingAdapter(appId: appId, processId: processId);
  }

  static CockpitRecordingAdapter _defaultLinuxAdapterFactory(
    String appId, {
    int? processId,
  }) {
    return CockpitLinuxRecordingAdapter(appId: appId, processId: processId);
  }
}

final class _RecordingCandidate {
  const _RecordingCandidate({
    required this.implementation,
    required this.layer,
    required this.factory,
    this.sessionKey,
    this.liveSessionChecker,
  });

  final String implementation;
  final CockpitRecordingLayer layer;
  final CockpitRecordingAdapter Function() factory;
  final String? sessionKey;
  final Future<bool> Function()? liveSessionChecker;
}

final class _PolicyAwareRecordingAdapter
    implements CockpitRecordingAdapter, CockpitRecordingProvenanceProvider {
  _PolicyAwareRecordingAdapter({
    required CockpitRecordingAdapter delegate,
    required String delegateImplementation,
    required List<_RecordingCandidate> runtimeFallbackCandidates,
    required CockpitRecordingMode requestedMode,
    required CockpitRecordingLayer? requestedLayer,
    required CockpitRecordingLayer effectiveLayer,
    required bool fallbackUsed,
    required String? fallbackReason,
  }) : _delegate = delegate,
       _delegateImplementation = delegateImplementation,
       _runtimeFallbackCandidates = runtimeFallbackCandidates,
       _requestedMode = requestedMode,
       _requestedLayer = requestedLayer,
       _effectiveLayer = effectiveLayer,
       _fallbackUsed = fallbackUsed,
       _fallbackReason = fallbackReason;

  final CockpitRecordingAdapter _delegate;
  final String _delegateImplementation;
  final List<_RecordingCandidate> _runtimeFallbackCandidates;
  final CockpitRecordingMode _requestedMode;
  final CockpitRecordingLayer? _requestedLayer;
  final CockpitRecordingLayer _effectiveLayer;
  final bool _fallbackUsed;
  final String? _fallbackReason;
  CockpitRecordingAdapter? _activeDelegate;
  CockpitRecordingLayer? _activeEffectiveLayer;
  bool _runtimeFallbackUsed = false;
  String? _runtimeFallbackReason;
  CockpitRecordingProvenance? _activeProvenance;

  @override
  CockpitRecordingProvenance? get recordingProvenance {
    if (_activeDelegate != null) {
      return _activeProvenance;
    }
    return _provenanceFor(
      adapter: _delegate,
      implementation: _delegateImplementation,
    );
  }

  @override
  Future<CockpitRecordingSession> startRecording(
    CockpitRecordingRequest request,
  ) async {
    try {
      final session = await _delegate.startRecording(request);
      _activeDelegate = _delegate;
      _activeEffectiveLayer = _effectiveLayer;
      _activeProvenance = _provenanceFor(
        adapter: _delegate,
        implementation: _delegateImplementation,
      );
      return session;
    } on Object catch (primaryError, primaryStackTrace) {
      if (_runtimeFallbackCandidates.isEmpty) {
        rethrow;
      }
      final fallbackFailures = <_RuntimeRecordingFallbackFailure>[];
      for (final candidate in _runtimeFallbackCandidates) {
        final fallbackDelegate = candidate.factory();
        try {
          final session = await fallbackDelegate.startRecording(request);
          _activeDelegate = fallbackDelegate;
          _activeEffectiveLayer = candidate.layer;
          _activeProvenance = _provenanceFor(
            adapter: fallbackDelegate,
            implementation: candidate.implementation,
          );
          _runtimeFallbackUsed = true;
          _runtimeFallbackReason =
              'Recording layer ${_effectiveLayer.jsonValue} failed to start: '
              '$primaryError. Falling back to ${candidate.layer.jsonValue}.';
          return session;
        } on Object catch (fallbackError) {
          fallbackFailures.add(
            _RuntimeRecordingFallbackFailure(
              layer: candidate.layer,
              implementation: candidate.implementation,
              error: fallbackError,
            ),
          );
        }
      }
      if (fallbackFailures.isNotEmpty) {
        Error.throwWithStackTrace(
          StateError(
            _runtimeFallbackFailureMessage(
              primaryError: primaryError,
              primaryLayer: _effectiveLayer,
              fallbackFailures: fallbackFailures,
            ),
          ),
          primaryStackTrace,
        );
      }
      Error.throwWithStackTrace(primaryError, primaryStackTrace);
    }
  }

  @override
  Future<CockpitRecordingResult> stopRecording() async {
    final activeDelegate = _activeDelegate ?? _delegate;
    final activeEffectiveLayer = _activeEffectiveLayer ?? _effectiveLayer;
    final result = await activeDelegate.stopRecording();
    return result.copyWith(
      requestedMode: result.requestedMode ?? _requestedMode,
      requestedLayer: result.requestedLayer ?? _requestedLayer,
      effectiveLayer: result.effectiveLayer ?? activeEffectiveLayer,
      fallbackUsed:
          result.fallbackUsed || _fallbackUsed || _runtimeFallbackUsed,
      fallbackReason:
          result.fallbackReason ?? _runtimeFallbackReason ?? _fallbackReason,
    );
  }

  CockpitRecordingProvenance? _provenanceFor({
    required CockpitRecordingAdapter adapter,
    required String implementation,
  }) {
    if (adapter is CockpitRecordingProvenanceProvider) {
      final provenance =
          (adapter as CockpitRecordingProvenanceProvider).recordingProvenance;
      if (provenance != null) {
        return provenance;
      }
    }
    if (adapter is CockpitHostRecordingAdapter) {
      return CockpitRecordingProvenance(
        implementation: implementation,
        sourcePlane: CockpitRecordingSourcePlane.host,
      );
    }
    return null;
  }
}

final class _RuntimeRecordingFallbackFailure {
  const _RuntimeRecordingFallbackFailure({
    required this.layer,
    required this.implementation,
    required this.error,
  });

  final CockpitRecordingLayer layer;
  final String implementation;
  final Object error;
}

String _runtimeFallbackFailureMessage({
  required Object primaryError,
  required CockpitRecordingLayer primaryLayer,
  required List<_RuntimeRecordingFallbackFailure> fallbackFailures,
}) {
  final buffer = StringBuffer(
    'Recording ${primaryLayer.jsonValue} failed to start: $primaryError.',
  );
  buffer.write(' Runtime fallbacks were attempted but none could start.');
  for (final failure in fallbackFailures) {
    buffer.write(
      ' ${failure.layer.jsonValue} fallback failed'
      ' (${failure.implementation}): ${failure.error}.',
    );
  }
  return buffer.toString();
}
