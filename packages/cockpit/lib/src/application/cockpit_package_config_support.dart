import 'dart:convert';

import 'package:path/path.dart' as p;

import '../infrastructure/cockpit_file_system.dart';
import 'cockpit_application_service_exception.dart';

final class CockpitResolvedPackageConfigEntry {
  const CockpitResolvedPackageConfigEntry({
    required this.packageName,
    required this.rootPath,
    required this.packagePath,
  });

  final String packageName;
  final String rootPath;
  final String packagePath;

  String packageRootUriForRelativePath(String relativePath) {
    final normalizedRelative = cockpitNormalizePackageRelativePath(
      relativePath,
    );
    if (normalizedRelative.isEmpty) {
      return 'package-root:$packageName';
    }
    return 'package-root:$packageName/$normalizedRelative';
  }

  String? packageUriForRelativePath(String relativePath) {
    final normalizedRelative = cockpitNormalizePackageRelativePath(
      relativePath,
    );
    if (normalizedRelative == 'lib') {
      return 'package:$packageName';
    }
    if (!normalizedRelative.startsWith('lib/')) {
      return null;
    }
    final packageRelative = normalizedRelative.substring(4);
    if (packageRelative.isEmpty) {
      return 'package:$packageName';
    }
    return 'package:$packageName/$packageRelative';
  }

  factory CockpitResolvedPackageConfigEntry.fromJson(
    Map<Object?, Object?> json, {
    required String configDirectoryPath,
  }) {
    final packageName = json['name'] as String?;
    if (packageName == null || packageName.isEmpty) {
      throw const CockpitApplicationServiceException(
        code: 'packageConfigInvalid',
        message: 'package_config.json contains a package without a valid name.',
      );
    }
    final rootUri = json['rootUri'] as String?;
    if (rootUri == null || rootUri.isEmpty) {
      throw CockpitApplicationServiceException(
        code: 'packageConfigInvalid',
        message:
            'package_config.json contains a package without a valid rootUri.',
        details: <String, Object?>{'packageName': packageName},
      );
    }
    final rootPath = _pathFromPackageConfigUri(
      rootUri,
      configDirectoryPath: configDirectoryPath,
    );
    final packageUri = json['packageUri'] as String? ?? 'lib/';
    return CockpitResolvedPackageConfigEntry(
      packageName: packageName,
      rootPath: rootPath,
      packagePath: p.normalize(p.join(rootPath, packageUri)),
    );
  }
}

Map<String, CockpitResolvedPackageConfigEntry> cockpitReadPackageConfig({
  required CockpitFileSystem fileSystem,
  required String workspaceRoot,
}) {
  final pathContext = fileSystem.pathContext;
  var directory = pathContext.normalize(workspaceRoot);
  String? configPath;
  while (true) {
    final candidate = fileSystem.file(
      pathContext.join(directory, '.dart_tool', 'package_config.json'),
    );
    if (candidate.existsSync()) {
      configPath = candidate.path;
      break;
    }
    final parent = pathContext.dirname(directory);
    if (parent == directory) break;
    directory = parent;
  }
  if (configPath == null) {
    throw CockpitApplicationServiceException(
      code: 'packageConfigNotFound',
      message:
          'package_config.json was not found. Run pub get before reading dependency packages.',
      details: <String, Object?>{'workspaceRoot': workspaceRoot},
    );
  }
  final configFile = fileSystem.file(configPath);
  final decoded =
      jsonDecode(configFile.readAsStringSync()) as Map<Object?, Object?>;
  final packages = ((decoded['packages'] as List?) ?? const <Object?>[])
      .cast<Map<Object?, Object?>>();
  return <String, CockpitResolvedPackageConfigEntry>{
    for (final package in packages)
      (package['name'] as String): CockpitResolvedPackageConfigEntry.fromJson(
        package,
        configDirectoryPath: configFile.parent.path,
      ),
  };
}

String cockpitNormalizePackageRelativePath(String path) {
  final normalized = p.posix.normalize(path.replaceAll('\\', '/'));
  if (normalized == '.') {
    return '';
  }
  return normalized.startsWith('./') ? normalized.substring(2) : normalized;
}

String _pathFromPackageConfigUri(
  String uri, {
  required String configDirectoryPath,
}) {
  final parsed = Uri.parse(uri);
  if (parsed.scheme.isEmpty) {
    return Uri.directory(configDirectoryPath).resolveUri(parsed).toFilePath();
  }
  return parsed.toFilePath();
}
