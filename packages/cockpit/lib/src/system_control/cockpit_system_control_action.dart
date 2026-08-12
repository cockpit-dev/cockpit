import 'cockpit_system_control_profile.dart';

final class CockpitSystemControlActionRequest {
  const CockpitSystemControlActionRequest({
    required this.platform,
    required this.action,
    this.deviceId,
    this.appId,
    this.processId,
    this.metadata = const <String, Object?>{},
    this.parameters = const <String, Object?>{},
    this.timeout = const Duration(seconds: 15),
  });

  final String platform;
  final String? deviceId;
  final String? appId;
  final int? processId;
  final Map<String, Object?> metadata;
  final CockpitSystemControlAction action;
  final Map<String, Object?> parameters;
  final Duration timeout;
}

final class CockpitSystemControlActionResult {
  const CockpitSystemControlActionResult({
    required this.platform,
    required this.deviceId,
    required this.action,
    required this.availability,
    required this.success,
    required this.recommendedNextStep,
    this.appId,
    this.processId,
    this.command = const <String>[],
    this.exitCode,
    this.stdout,
    this.stderr,
    this.errorCode,
    this.errorMessage,
    this.errorDetails = const <String, Object?>{},
    this.changed,
    this.strategy,
    this.requires = const <String>[],
    this.limitations = const <String>[],
    this.artifact,
    this.sourceFilePath,
    this.recordingSession,
    this.recordingResult,
  });

  final String platform;
  final String? deviceId;
  final String? appId;
  final int? processId;
  final CockpitSystemControlAction action;
  final CockpitSystemControlAvailability availability;
  final bool success;
  final List<String> command;
  final int? exitCode;
  final String? stdout;
  final String? stderr;
  final String? errorCode;
  final String? errorMessage;
  final Map<String, Object?> errorDetails;
  final bool? changed;
  final String recommendedNextStep;
  final String? strategy;
  final List<String> requires;
  final List<String> limitations;
  final Map<String, Object?>? artifact;
  final String? sourceFilePath;
  final Map<String, Object?>? recordingSession;
  final Map<String, Object?>? recordingResult;

  Map<String, Object?> toJson() => <String, Object?>{
    'platform': platform,
    if (deviceId != null) 'deviceId': deviceId,
    if (appId != null) 'appId': appId,
    if (processId != null) 'processId': processId,
    'action': action.name,
    'availability': availability.name,
    'success': success,
    'recommendedNextStep': recommendedNextStep,
    if (command.isNotEmpty) 'command': command,
    if (exitCode != null) 'exitCode': exitCode,
    if (stdout != null && stdout!.isNotEmpty) 'stdout': stdout,
    if (stderr != null && stderr!.isNotEmpty) 'stderr': stderr,
    if (errorCode != null) 'errorCode': errorCode,
    if (errorMessage != null) 'errorMessage': errorMessage,
    if (errorDetails.isNotEmpty) 'errorDetails': errorDetails,
    if (changed != null) 'changed': changed,
    if (strategy != null) 'strategy': strategy,
    if (requires.isNotEmpty) 'requires': requires,
    if (limitations.isNotEmpty) 'limitations': limitations,
    if (artifact != null) 'artifact': artifact,
    if (sourceFilePath != null) 'sourceFilePath': sourceFilePath,
    if (recordingSession != null) 'recordingSession': recordingSession,
    if (recordingResult != null) 'recordingResult': recordingResult,
  };
}

final class CockpitResolvedSystemControlCommand {
  const CockpitResolvedSystemControlCommand(this.executable, this.arguments)
    : errorCode = null,
      errorMessage = null;

  const CockpitResolvedSystemControlCommand.error({
    required String code,
    required String message,
  }) : executable = null,
       arguments = const <String>[],
       errorCode = code,
       errorMessage = message;

  final String? executable;
  final List<String> arguments;
  final String? errorCode;
  final String? errorMessage;

  bool get hasError => errorCode != null;
}
