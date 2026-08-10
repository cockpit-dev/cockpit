import 'cockpit_flutter_launch_configuration.dart';

final class CockpitRemoteSessionLaunchOptions {
  const CockpitRemoteSessionLaunchOptions({
    required this.projectDir,
    required this.target,
    required this.platform,
    required this.deviceId,
    required this.sessionPort,
    this.flavor,
    this.launchTimeout = const Duration(seconds: 120),
    this.flutterVersion,
    this.flutterExecutable,
    this.launchId,
    this.launchConfiguration = CockpitFlutterLaunchConfiguration.empty,
    this.appEnvironment,
  });

  final String projectDir;
  final String target;
  final String platform;
  final String deviceId;
  final int sessionPort;
  final String? flavor;
  final Duration launchTimeout;
  final String? flutterVersion;
  final String? flutterExecutable;
  final String? launchId;
  final CockpitFlutterLaunchConfiguration launchConfiguration;

  /// Environment applied only to the detached desktop app process.
  final Map<String, String>? appEnvironment;
}
