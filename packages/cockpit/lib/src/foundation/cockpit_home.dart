import 'dart:io';

import 'package:path/path.dart' as p;

import 'cockpit_permissions.dart';

enum CockpitHostPlatform { linux, macos, windows }

final class CockpitHomeResolutionException implements Exception {
  const CockpitHomeResolutionException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'CockpitHomeResolutionException($code): $message';
}

final class CockpitHomeResolver {
  const CockpitHomeResolver({
    required this.platform,
    required this.environment,
    required this.userHome,
  });

  factory CockpitHomeResolver.system() => CockpitHomeResolver(
    platform: Platform.isWindows
        ? CockpitHostPlatform.windows
        : Platform.isMacOS
        ? CockpitHostPlatform.macos
        : CockpitHostPlatform.linux,
    environment: Platform.environment,
    userHome:
        Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'] ?? '',
  );

  final CockpitHostPlatform platform;
  final Map<String, String> environment;
  final String userHome;

  String resolve() {
    final explicit = environment['COCKPIT_HOME'];
    if (explicit != null) {
      return _absoluteNormalized(explicit, variable: 'COCKPIT_HOME');
    }
    return switch (platform) {
      CockpitHostPlatform.linux => _linuxDefault(),
      CockpitHostPlatform.macos => p.join(
        _requiredUserHome(),
        'Library',
        'Application Support',
        'Cockpit',
      ),
      CockpitHostPlatform.windows => p.windows.join(
        _requiredEnvironment('LOCALAPPDATA'),
        'Cockpit',
      ),
    };
  }

  String _linuxDefault() {
    final xdgStateHome = environment['XDG_STATE_HOME'];
    if (xdgStateHome != null && xdgStateHome.isNotEmpty) {
      return p.join(
        _absoluteNormalized(xdgStateHome, variable: 'XDG_STATE_HOME'),
        'cockpit',
      );
    }
    return p.join(_requiredUserHome(), '.local', 'state', 'cockpit');
  }

  String _requiredUserHome() =>
      _absoluteNormalized(userHome, variable: 'userHome');

  String _requiredEnvironment(String name) =>
      _absoluteNormalized(environment[name] ?? '', variable: name);

  String _absoluteNormalized(String value, {required String variable}) {
    final context = platform == CockpitHostPlatform.windows
        ? p.windows
        : p.posix;
    if (value.trim().isEmpty || !context.isAbsolute(value)) {
      throw CockpitHomeResolutionException(
        'invalidHomePath',
        '$variable must contain an absolute path.',
      );
    }
    return context.normalize(value);
  }
}

final class CockpitHomePaths {
  CockpitHomePaths(String home) : home = p.normalize(p.absolute(home));

  final String home;

  String get daemonDiscovery => p.join(home, 'daemon.json');
  String get daemonLock => p.join(home, 'daemon.lock');
  String get daemonEnsureLock => p.join(home, 'daemon.ensure.lock');
  String get daemonLog => p.join(home, 'daemon.log');
  String get authorizationPolicy => p.join(home, 'authorization.json');
  String get registryDirectory => p.join(home, 'registry');
  String get identityRegistry => p.join(registryDirectory, 'identity.json');
  String get rootsRegistry => p.join(registryDirectory, 'roots.json');
  String get workspacesRegistry => p.join(registryDirectory, 'workspaces.json');
  String get referencesRegistry => p.join(registryDirectory, 'references.json');
  String get leasesDirectory => p.join(home, 'leases');
  String get leaseRegistry => p.join(leasesDirectory, 'leases.json');
  String get runsDirectory => p.join(home, 'runs');
  String get artifactsDirectory => p.join(home, 'artifacts');

  Iterable<String> get directories => <String>[
    home,
    registryDirectory,
    leasesDirectory,
    runsDirectory,
    artifactsDirectory,
  ];
}

final class CockpitHome {
  CockpitHome({required this.paths, required this.permissionHardener});

  factory CockpitHome.system() {
    final resolver = CockpitHomeResolver.system();
    return CockpitHome(
      paths: CockpitHomePaths(resolver.resolve()),
      permissionHardener: resolver.platform == CockpitHostPlatform.windows
          ? const CockpitWindowsAclPermissionHardener()
          : const CockpitPosixPermissionHardener(),
    );
  }

  final CockpitHomePaths paths;
  final CockpitPermissionHardener permissionHardener;

  Future<CockpitHomePaths> initialize() async {
    for (final path in paths.directories) {
      final directory = Directory(path);
      await directory.create(recursive: true);
      await permissionHardener.hardenDirectory(directory);
    }
    final canonicalHome = await Directory(paths.home).resolveSymbolicLinks();
    return CockpitHomePaths(canonicalHome);
  }
}
