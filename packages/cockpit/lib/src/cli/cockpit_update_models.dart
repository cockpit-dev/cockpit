import 'dart:io';

typedef CockpitUpdateProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments,
      Duration timeout,
    );

typedef CockpitLatestVersionLookup = Future<String> Function(Duration timeout);

typedef CockpitHostedInstallProbe = Future<bool> Function(String version);

final class CockpitUpdateException implements Exception {
  const CockpitUpdateException(
    this.code,
    this.message, {
    this.retryable = true,
  });

  final String code;
  final String message;
  final bool retryable;

  @override
  String toString() => 'CockpitUpdateException($code): $message';
}

final class CockpitUpdateResult {
  const CockpitUpdateResult({
    required this.previousVersion,
    required this.version,
  });

  final String previousVersion;
  final String version;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'updated': previousVersion != version,
    if (previousVersion != version) 'previous': previousVersion,
    'supervisor': 'ready',
  };
}
