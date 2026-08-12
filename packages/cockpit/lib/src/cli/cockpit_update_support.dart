import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../infrastructure/cockpit_process_manager.dart';

const Duration _latestVersionLookupLimit = Duration(seconds: 3);

Future<String> cockpitLookupLatestVersion(
  Duration timeout, {
  http.Client? client,
}) async {
  final effectiveTimeout = timeout < _latestVersionLookupLimit
      ? timeout
      : _latestVersionLookupLimit;
  if (effectiveTimeout <= Duration.zero) {
    throw TimeoutException('Cockpit version lookup exceeded its timeout.');
  }
  final effectiveClient = client ?? http.Client();
  try {
    final response = await effectiveClient
        .get(
          Uri.https('pub.dev', '/api/packages/cockpit', <String, String>{
            '_': DateTime.now().toUtc().microsecondsSinceEpoch.toString(),
          }),
          headers: const <String, String>{
            'accept': 'application/json',
            'cache-control': 'no-cache',
            'pragma': 'no-cache',
          },
        )
        .timeout(effectiveTimeout);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Pub returned status ${response.statusCode}.',
        uri: response.request?.url,
      );
    }
    final body = jsonDecode(response.body) as Map<Object?, Object?>;
    final latest = body['latest'] as Map<Object?, Object?>?;
    final version = latest?['version'];
    if (version is! String || version.trim().isEmpty) {
      throw const FormatException('Pub returned an invalid latest version.');
    }
    return version.trim();
  } finally {
    if (client == null) effectiveClient.close();
  }
}

Future<bool> cockpitHasCanonicalHostedInstall({
  required Map<String, String> environment,
  required bool windows,
  required String resolvedExecutable,
  required String version,
}) async {
  try {
    final pubCache = cockpitPubCacheRoot(environment, windows: windows);
    if (pubCache == null) return false;
    final cache = Directory(pubCache);
    final executable = File.fromUri(
      cache.uri.resolve(windows ? 'bin/cockpit.exe' : 'bin/cockpit'),
    );
    if (!cockpitPathsMatch(
          resolvedExecutable,
          executable.path,
          windows: windows,
        ) ||
        !await executable.exists()) {
      return false;
    }

    final config = File.fromUri(
      cache.uri.resolve(
        'global_packages/cockpit/.dart_tool/package_config.json',
      ),
    );
    if (!await config.exists()) return false;
    final decoded = jsonDecode(await config.readAsString());
    final packages = (decoded as Map<Object?, Object?>)['packages'];
    if (packages is! List<Object?>) return false;
    final entries = packages.whereType<Map<Object?, Object?>>().where(
      (entry) => entry['name'] == 'cockpit',
    );
    if (entries.length != 1) return false;
    final rootValue = entries.single['rootUri'];
    if (rootValue is! String || rootValue.isEmpty) return false;
    final packageRoot = Directory.fromUri(config.uri.resolve(rootValue));
    final hostedRoot = Directory.fromUri(cache.uri.resolve('hosted/'));
    final resolvedPackageRoot = await packageRoot.resolveSymbolicLinks();
    final resolvedHostedRoot = await hostedRoot.resolveSymbolicLinks();
    if (!cockpitPathIsWithin(resolvedPackageRoot, resolvedHostedRoot)) {
      return false;
    }

    final pubspec = File.fromUri(packageRoot.uri.resolve('pubspec.yaml'));
    final entrypoint = File.fromUri(
      packageRoot.uri.resolve('bin/cockpit.dart'),
    );
    if (!await pubspec.exists() || !await entrypoint.exists()) return false;
    final manifest = loadYaml(await pubspec.readAsString());
    if (manifest is! YamlMap) return false;
    return manifest['name'] == 'cockpit' && manifest['version'] == version;
  } on Object {
    return false;
  }
}

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

bool cockpitPathsMatch(String left, String right, {required bool windows}) {
  final a = _resolvedPath(left);
  final b = _resolvedPath(right);
  return windows ? a.toLowerCase() == b.toLowerCase() : a == b;
}

String _resolvedPath(String path) {
  try {
    return File(path).resolveSymbolicLinksSync();
  } on FileSystemException {
    return p.normalize(p.absolute(path));
  }
}
