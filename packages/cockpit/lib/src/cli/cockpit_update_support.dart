import 'dart:io';

import 'package:path/path.dart' as p;

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
  final root = cockpitPubCacheRoot(environment, windows: windows);
  if (root == null) return;
  final legacy = Directory(
    Directory(root).uri.resolve('cockpit-aot/').toFilePath(),
  );
  if (!await legacy.exists()) return;
  if (windows && cockpitPathIsWithin(resolvedExecutable, legacy.path)) return;
  await legacy.delete(recursive: true);
}

String cockpitReadInstalledVersion(String output) {
  final match = RegExp(
    r'^cockpit\s+(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)$',
  ).firstMatch(output.trim());
  if (match == null) {
    throw const FormatException(
      'The installed Cockpit executable returned an invalid version.',
    );
  }
  return match.group(1)!;
}

String? cockpitPubCacheRoot(
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

bool cockpitPathIsWithin(String path, String directory) {
  final normalizedPath = p.normalize(p.absolute(path));
  final normalizedDirectory = p.normalize(p.absolute(directory));
  return normalizedPath == normalizedDirectory ||
      p.isWithin(normalizedDirectory, normalizedPath);
}
