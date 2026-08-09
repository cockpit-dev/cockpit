import 'dart:io';

import '../infrastructure/cockpit_process_manager.dart';

Future<ProcessResult> cockpitRunUpdateProcess(
  String executable,
  List<String> arguments,
  Duration timeout,
) => cockpitRunManagedProcessWithTimeout(
  const LocalCockpitProcessManager(),
  executable,
  arguments,
  timeout: timeout,
);

String? cockpitUpdateDiagnostic(ProcessResult result) {
  for (final raw in <String>['${result.stderr}', '${result.stdout}']) {
    final lines = raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isNotEmpty) return cockpitBoundUpdateText(lines.last);
  }
  return null;
}

String cockpitBoundUpdateText(String value) =>
    value.length <= 800 ? value : '${value.substring(0, 797)}...';

Future<void> cockpitRemoveLegacySourcePayload({
  required Map<String, String> environment,
  required bool windows,
  required String resolvedExecutable,
}) async {
  final root = _pubCacheRoot(environment, windows: windows);
  if (root == null) return;
  final legacy = Directory(
    Directory(root).uri.resolve('cockpit-aot/').toFilePath(),
  );
  if (!await legacy.exists()) return;
  if (windows && _isWithin(resolvedExecutable, legacy.path)) return;
  await legacy.delete(recursive: true);
}

String? _pubCacheRoot(
  Map<String, String> environment, {
  required bool windows,
}) {
  final configured = environment['PUB_CACHE']?.trim();
  if (configured != null && configured.isNotEmpty) {
    return Directory(configured).absolute.path;
  }
  if (windows) {
    final local = environment['LOCALAPPDATA']?.trim();
    return local == null || local.isEmpty
        ? null
        : Directory(local).uri.resolve('Pub/Cache/').toFilePath();
  }
  final home = environment['HOME']?.trim();
  return home == null || home.isEmpty
      ? null
      : Directory(home).uri.resolve('.pub-cache/').toFilePath();
}

bool _isWithin(String path, String directory) {
  final normalizedPath = File(path).absolute.path;
  final normalizedDirectory = Directory(directory).absolute.path;
  return normalizedPath == normalizedDirectory ||
      normalizedPath.startsWith(
        '$normalizedDirectory${Platform.pathSeparator}',
      );
}
