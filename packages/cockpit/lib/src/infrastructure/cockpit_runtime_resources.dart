import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../foundation/cockpit_version.dart';

const String _runtimeResourceSchema = 'cockpit.runtime-resources/v1';
const String _runtimeResourceManifest = 'manifest.json';
const Map<String, String> _runtimePackageAssets = <String, String>{
  'package:cockpit/src/system_control/resources/android/cockpit-driver.apk':
      'android/cockpit-driver.apk',
  'package:cockpit/src/system_control/resources/android/cockpit-driver-test.apk':
      'android/cockpit-driver-test.apk',
};

typedef CockpitPackageAssetResolver = Future<Uri?> Function(Uri uri);

String cockpitRuntimeResourceDirectoryPath(
  String executablePath, {
  bool? windows,
}) {
  final pathContext = (windows ?? Platform.isWindows)
      ? p.Context(style: p.Style.windows)
      : p.Context(style: p.Style.posix);
  final absolute = pathContext.absolute(executablePath);
  final name = pathContext.basename(absolute);
  final stem = (windows ?? Platform.isWindows)
      ? pathContext.basenameWithoutExtension(name)
      : name;
  return pathContext.join(pathContext.dirname(absolute), '$stem-resources');
}

Future<void> cockpitWriteRuntimeResources({
  required Directory packageRoot,
  required Directory destination,
  required String version,
}) async {
  if (await destination.exists()) {
    throw FileSystemException(
      'Cockpit runtime resource destination already exists.',
      destination.path,
    );
  }
  await destination.create(recursive: true);
  try {
    final hashes = <String, String>{};
    for (final relativePath in _runtimePackageAssets.values) {
      final source = File.fromUri(
        packageRoot.uri.resolve(
          'lib/src/system_control/resources/$relativePath',
        ),
      );
      if (!await source.exists()) {
        throw FileSystemException(
          'Cockpit runtime resource source is missing.',
          source.path,
        );
      }
      final bytes = await source.readAsBytes();
      if (bytes.isEmpty) {
        throw FileSystemException(
          'Cockpit runtime resource source is empty.',
          source.path,
        );
      }
      final output = File.fromUri(destination.uri.resolve(relativePath));
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes, flush: true);
      hashes[relativePath] = sha256.convert(bytes).toString();
    }
    await File.fromUri(
      destination.uri.resolve(_runtimeResourceManifest),
    ).writeAsString(
      jsonEncode(<String, Object?>{
        'schema': _runtimeResourceSchema,
        'version': version,
        'files': hashes,
      }),
      flush: true,
    );
  } on Object {
    if (await destination.exists()) await destination.delete(recursive: true);
    rethrow;
  }
}

Future<bool> cockpitHasValidRuntimeResources({
  required String executablePath,
  required String version,
  bool? windows,
}) async {
  final root = Directory(
    cockpitRuntimeResourceDirectoryPath(executablePath, windows: windows),
  );
  return cockpitHasValidRuntimeResourceDirectory(root, version: version);
}

Future<bool> cockpitHasValidRuntimeResourceDirectory(
  Directory root, {
  required String version,
}) async {
  return await _validatedRuntimeResourceFiles(root, version: version) != null;
}

Future<Uri?> cockpitResolveRuntimePackageAsset(
  Uri uri, {
  String? executablePath,
  CockpitPackageAssetResolver packageResolver = Isolate.resolvePackageUri,
  Map<String, String>? environment,
  bool? windows,
}) async {
  final relativePath = _runtimePackageAssets[uri.toString()];
  if (relativePath != null) {
    final useWindowsPaths = windows ?? Platform.isWindows;
    final root = Directory(
      cockpitRuntimeResourceDirectoryPath(
        executablePath ?? Platform.resolvedExecutable,
        windows: useWindowsPaths,
      ),
    );
    final files = await _validatedRuntimeResourceFiles(
      root,
      version: cockpitVersion,
    );
    final resolved = files?[relativePath];
    if (resolved != null) return resolved.uri;
    final activated = await _activatedPackageResource(
      relativePath,
      environment: environment ?? Platform.environment,
      windows: useWindowsPaths,
    );
    if (activated != null) return activated.uri;
  }
  return packageResolver(uri);
}

Future<File?> _activatedPackageResource(
  String relativePath, {
  required Map<String, String> environment,
  required bool windows,
}) async {
  try {
    final cache = _pubCacheRoot(environment, windows: windows);
    if (cache == null) return null;
    final config = File.fromUri(
      cache.uri.resolve(
        'global_packages/cockpit/.dart_tool/package_config.json',
      ),
    );
    if (!await config.exists()) return null;
    final decoded = jsonDecode(await config.readAsString());
    if (decoded is! Map<Object?, Object?>) return null;
    final rawPackages = decoded['packages'];
    if (rawPackages is! List<Object?>) return null;
    final cockpitPackages = rawPackages
        .whereType<Map<Object?, Object?>>()
        .where((entry) => entry['name'] == 'cockpit');
    if (cockpitPackages.length != 1) return null;
    final rootUri = cockpitPackages.single['rootUri'];
    if (rootUri is! String || rootUri.isEmpty) return null;
    final packageRoot = Directory.fromUri(config.uri.resolve(rootUri));
    if (await _readPackageVersion(packageRoot) != cockpitVersion) return null;
    final resource = File.fromUri(
      packageRoot.uri.resolve('lib/src/system_control/resources/$relativePath'),
    );
    if (!await resource.exists() || await resource.length() == 0) return null;
    return resource;
  } on Object {
    return null;
  }
}

Future<String?> _readPackageVersion(Directory packageRoot) async {
  final pubspec = File.fromUri(packageRoot.uri.resolve('pubspec.yaml'));
  if (!await pubspec.exists()) return null;
  for (final rawLine in await pubspec.readAsLines()) {
    final line = rawLine.trim();
    if (!line.startsWith('version:')) continue;
    final value = line.substring('version:'.length).trim();
    return value.isEmpty ? null : value;
  }
  return null;
}

Directory? _pubCacheRoot(
  Map<String, String> environment, {
  required bool windows,
}) {
  final configured = environment['PUB_CACHE']?.trim();
  if (configured != null && configured.isNotEmpty) {
    return Directory(configured).absolute;
  }
  if (windows) {
    final local = environment['LOCALAPPDATA']?.trim();
    if (local == null || local.isEmpty) return null;
    return Directory.fromUri(Directory(local).uri.resolve('Pub/Cache/'));
  }
  final home = environment['HOME']?.trim();
  if (home == null || home.isEmpty) return null;
  return Directory.fromUri(Directory(home).uri.resolve('.pub-cache/'));
}

Future<Map<String, File>?> _validatedRuntimeResourceFiles(
  Directory root, {
  required String version,
}) async {
  try {
    final manifestFile = File.fromUri(
      root.uri.resolve(_runtimeResourceManifest),
    );
    if (!await manifestFile.exists()) return null;
    final decoded = jsonDecode(await manifestFile.readAsString());
    if (decoded is! Map<Object?, Object?>) return null;
    final manifest = Map<String, Object?>.from(decoded);
    if (manifest['schema'] != _runtimeResourceSchema ||
        manifest['version'] != version) {
      return null;
    }
    final rawFiles = manifest['files'];
    if (rawFiles is! Map<Object?, Object?>) return null;
    final hashes = Map<String, Object?>.from(rawFiles);
    final files = <String, File>{};
    for (final relativePath in _runtimePackageAssets.values) {
      final expected = hashes[relativePath];
      if (expected is! String || expected.length != 64) return null;
      final file = File.fromUri(root.uri.resolve(relativePath));
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty || sha256.convert(bytes).toString() != expected) {
        return null;
      }
      files[relativePath] = file;
    }
    return files;
  } on Object {
    return null;
  }
}
