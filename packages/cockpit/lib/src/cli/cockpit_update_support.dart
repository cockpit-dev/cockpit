import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

import '../infrastructure/cockpit_installed_runtime.dart';
import '../infrastructure/cockpit_process_manager.dart';

export '../infrastructure/cockpit_installed_runtime.dart';

const Duration _latestVersionLookupLimit = Duration(seconds: 30);

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
            'accept-encoding': 'identity',
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
    final runtime = await cockpitReadCanonicalInstalledRuntime(
      environment: environment,
      windows: windows,
      resolvedExecutable: resolvedExecutable,
      version: version,
    );
    if (runtime == null) return false;

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

({String package, String constraint})? cockpitStaleHostedDependency(
  ProcessResult result,
) {
  final output = '${result.stderr}\n${result.stdout}';
  final match = RegExp(
    r"depends on\s+([A-Za-z0-9_]+)\s+(.+?)\s+which doesn't match any versions",
  ).firstMatch(output);
  if (match == null) return null;
  final package = match.group(1)!.trim();
  final constraint = match.group(2)!.trim();
  if (package.isEmpty || constraint.isEmpty) return null;
  return (package: package, constraint: constraint);
}

bool cockpitHostedVersionUnavailable(
  ProcessResult result, {
  required String package,
  required String version,
}) {
  final output = '${result.stderr}\n${result.stdout}';
  return RegExp(
    'Package\\s+${RegExp.escape(package)}\\s+has no versions that match\\s+'
    '${RegExp.escape(version)}(?:\\s|\\.|\$)',
    caseSensitive: false,
  ).hasMatch(output);
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
