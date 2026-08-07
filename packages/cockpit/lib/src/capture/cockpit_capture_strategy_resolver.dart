import 'dart:io';

import '../adapters/cockpit_capture_adapter.dart';
import '../platform/ios/cockpit_ios_device_connection.dart';
import '../platform/web/cockpit_browser_host_app_id.dart';
import '../remote/cockpit_remote_capture_adapter.dart';
import '../remote/cockpit_remote_session_client.dart';
import '../session/cockpit_remote_session_handle.dart';
import 'cockpit_adb_capture_adapter.dart';
import 'cockpit_prioritized_capture_adapter.dart';
import 'cockpit_linux_capture_adapter.dart';
import 'cockpit_macos_capture_adapter.dart';
import 'cockpit_simctl_capture_adapter.dart';
import 'cockpit_wda_capture_adapter.dart';
import 'cockpit_windows_capture_adapter.dart';

typedef CockpitRemoteCaptureAdapterFactory =
    CockpitCaptureAdapter Function(CockpitRemoteSessionClient client);
typedef CockpitAdbCaptureAdapterFactory =
    CockpitCaptureAdapter Function(String deviceId);
typedef CockpitSimctlCaptureAdapterFactory =
    CockpitCaptureAdapter Function(String deviceId);
typedef CockpitWdaCaptureAdapterFactory =
    CockpitCaptureAdapter Function(Uri baseUri);
typedef CockpitMacosCaptureAdapterFactory =
    CockpitCaptureAdapter Function(String appId, {int? processId});
typedef CockpitWindowsCaptureAdapterFactory =
    CockpitCaptureAdapter Function(String appId, {int? processId});
typedef CockpitLinuxCaptureAdapterFactory =
    CockpitCaptureAdapter Function(String appId, {int? processId});
typedef CockpitBrowserHostAppIdResolver = String? Function(String deviceId);
typedef CockpitHostPlatformResolver = String Function();

final class CockpitCaptureStrategyResolver {
  const CockpitCaptureStrategyResolver({
    this.remoteAdapterFactory = _defaultRemoteAdapterFactory,
    this.adbAdapterFactory = _defaultAdbAdapterFactory,
    this.simctlAdapterFactory = _defaultSimctlAdapterFactory,
    this.wdaAdapterFactory = _defaultWdaAdapterFactory,
    this.macosAdapterFactory = _defaultMacosAdapterFactory,
    this.windowsAdapterFactory = _defaultWindowsAdapterFactory,
    this.linuxAdapterFactory = _defaultLinuxAdapterFactory,
    this.browserHostAppIdResolver = cockpitResolveBrowserHostAppId,
    this.hostPlatformResolver = _defaultHostPlatformResolver,
  });

  final CockpitRemoteCaptureAdapterFactory remoteAdapterFactory;
  final CockpitAdbCaptureAdapterFactory adbAdapterFactory;
  final CockpitSimctlCaptureAdapterFactory simctlAdapterFactory;
  final CockpitWdaCaptureAdapterFactory wdaAdapterFactory;
  final CockpitMacosCaptureAdapterFactory macosAdapterFactory;
  final CockpitWindowsCaptureAdapterFactory windowsAdapterFactory;
  final CockpitLinuxCaptureAdapterFactory linuxAdapterFactory;
  final CockpitBrowserHostAppIdResolver browserHostAppIdResolver;
  final CockpitHostPlatformResolver hostPlatformResolver;

  CockpitCaptureAdapter resolve({
    required String platform,
    required CockpitRemoteSessionClient client,
    String? platformAppId,
    int? processId,
    CockpitRemoteSessionHandle? sessionHandle,
    String? deviceId,
    String? androidDeviceId,
    String? iosDeviceId,
    Uri? iosWdaBaseUri,
  }) {
    final remoteAdapter = remoteAdapterFactory(client);
    if (platform == 'android' &&
        androidDeviceId != null &&
        androidDeviceId.isNotEmpty) {
      return CockpitPrioritizedCaptureAdapter(
        remoteAdapter: remoteAdapter,
        hostAcceptanceAdapter: adbAdapterFactory(androidDeviceId),
        client: client,
      );
    }
    if (platform == 'ios' &&
        iosDeviceId != null &&
        iosDeviceId.isNotEmpty &&
        cockpitLooksLikeIosSimulatorDeviceId(iosDeviceId)) {
      return CockpitPrioritizedCaptureAdapter(
        remoteAdapter: remoteAdapter,
        hostAcceptanceAdapter: simctlAdapterFactory(iosDeviceId),
        client: client,
      );
    }
    if (platform == 'ios' && iosWdaBaseUri != null) {
      return CockpitPrioritizedCaptureAdapter(
        remoteAdapter: remoteAdapter,
        hostAcceptanceAdapter: wdaAdapterFactory(iosWdaBaseUri),
        client: client,
      );
    }
    final resolvedAppId = _hostAppIdFor(
      platform: platform,
      platformAppId: platformAppId ?? sessionHandle?.effectivePlatformAppId,
      processId: processId ?? sessionHandle?.processId,
    );
    final resolvedProcessId = processId ?? sessionHandle?.processId;
    if (platform == 'macos' &&
        resolvedAppId != null &&
        resolvedAppId.isNotEmpty) {
      return CockpitPrioritizedCaptureAdapter(
        remoteAdapter: remoteAdapter,
        hostAcceptanceAdapter: macosAdapterFactory(
          resolvedAppId,
          processId: resolvedProcessId,
        ),
        client: client,
        preferHostForAcceptance: false,
      );
    }
    if (platform == 'windows' &&
        resolvedAppId != null &&
        resolvedAppId.isNotEmpty) {
      return CockpitPrioritizedCaptureAdapter(
        remoteAdapter: remoteAdapter,
        hostAcceptanceAdapter: windowsAdapterFactory(
          resolvedAppId,
          processId: resolvedProcessId,
        ),
        client: client,
        preferHostForAcceptance: false,
      );
    }
    if (platform == 'linux' &&
        resolvedAppId != null &&
        resolvedAppId.isNotEmpty) {
      return CockpitPrioritizedCaptureAdapter(
        remoteAdapter: remoteAdapter,
        hostAcceptanceAdapter: linuxAdapterFactory(
          resolvedAppId,
          processId: resolvedProcessId,
        ),
        client: client,
        preferHostForAcceptance: false,
      );
    }
    if (platform == 'web') {
      final browserHostAppId = browserHostAppIdResolver(
        deviceId ?? sessionHandle?.deviceId ?? '',
      );
      if (browserHostAppId != null && browserHostAppId.isNotEmpty) {
        final hostAdapter = _desktopHostCaptureAdapter(
          platform: hostPlatformResolver(),
          appId: browserHostAppId,
        );
        if (hostAdapter != null) {
          return CockpitPrioritizedCaptureAdapter(
            remoteAdapter: remoteAdapter,
            hostAcceptanceAdapter: hostAdapter,
            client: client,
            preferHostForAcceptance: false,
          );
        }
      }
    }
    return remoteAdapter;
  }

  CockpitCaptureAdapter? _desktopHostCaptureAdapter({
    required String platform,
    required String appId,
  }) {
    return switch (platform) {
      'macos' => macosAdapterFactory(appId),
      'windows' => windowsAdapterFactory(appId),
      'linux' => linuxAdapterFactory(appId),
      _ => null,
    };
  }

  static String _defaultHostPlatformResolver() {
    if (Platform.isMacOS) {
      return 'macos';
    }
    if (Platform.isWindows) {
      return 'windows';
    }
    if (Platform.isLinux) {
      return 'linux';
    }
    return Platform.operatingSystem;
  }

  String? _hostAppIdFor({
    required String platform,
    required String? platformAppId,
    required int? processId,
  }) {
    final trimmed = platformAppId?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    if ((platform == 'windows' || platform == 'linux') && processId != null) {
      return 'pid-$processId';
    }
    return null;
  }

  static CockpitCaptureAdapter _defaultRemoteAdapterFactory(
    CockpitRemoteSessionClient client,
  ) {
    return CockpitRemoteCaptureAdapter(client: client);
  }

  static CockpitCaptureAdapter _defaultAdbAdapterFactory(String deviceId) {
    return CockpitAdbCaptureAdapter(deviceId: deviceId);
  }

  static CockpitCaptureAdapter _defaultSimctlAdapterFactory(String deviceId) {
    return CockpitSimctlCaptureAdapter(deviceId: deviceId);
  }

  static CockpitCaptureAdapter _defaultWdaAdapterFactory(Uri baseUri) {
    return CockpitWdaCaptureAdapter(baseUri: baseUri);
  }

  static CockpitCaptureAdapter _defaultMacosAdapterFactory(
    String appId, {
    int? processId,
  }) {
    return CockpitMacosCaptureAdapter(appId: appId, processId: processId);
  }

  static CockpitCaptureAdapter _defaultWindowsAdapterFactory(
    String appId, {
    int? processId,
  }) {
    return CockpitWindowsCaptureAdapter(appId: appId, processId: processId);
  }

  static CockpitCaptureAdapter _defaultLinuxAdapterFactory(
    String appId, {
    int? processId,
  }) {
    return CockpitLinuxCaptureAdapter(appId: appId, processId: processId);
  }
}
