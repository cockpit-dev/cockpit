import 'dart:io';

import 'package:cockpit/src/infrastructure/cockpit_installed_runtime.dart';
import 'package:cockpit/src/infrastructure/cockpit_installed_runtime_cleanup.dart';
import 'package:cockpit/src/infrastructure/cockpit_runtime_resources.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Directory pubCache;
  late Directory package;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('cockpit-runtime-install-');
    pubCache = Directory('${root.path}/pub-cache');
    package = Directory('${root.path}/package');
    await _writePackageResources(package);
  });

  tearDown(() async {
    cockpitResetCurrentExecutable();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('installs AOT outside Pub bin and keeps a text launcher', () async {
    const version = '1.2.3';
    final staged = await _stageRuntime(
      root,
      package,
      version: version,
      contents: 'aot payload',
    );

    final installed = await cockpitInstallRuntimeRelease(
      environment: <String, String>{'PUB_CACHE': pubCache.path},
      windows: Platform.isWindows,
      stagedExecutable: staged.executable,
      stagedResources: staged.resources,
      version: version,
      verify: (executable) async {
        expect(await executable.readAsString(), 'aot payload');
      },
    );

    expect(
      cockpitPathIsWithin(
        installed.executable.path,
        installed.paths.releases.path,
      ),
      isTrue,
    );
    expect(
      await installed.paths.launcher.readAsString(),
      cockpitRuntimeLauncherContents(
        executablePath: installed.executable.path,
        version: version,
        windows: Platform.isWindows,
      ),
    );
    expect(
      await cockpitReadCanonicalInstalledRuntime(
        environment: <String, String>{'PUB_CACHE': pubCache.path},
        windows: Platform.isWindows,
        resolvedExecutable: installed.executable.path,
        version: version,
      ),
      isNotNull,
    );
  });

  test('keeps the active launcher when runtime verification fails', () async {
    final paths = CockpitInstalledRuntimePaths(
      pubCacheRoot: pubCache.path,
      windows: Platform.isWindows,
    );
    await paths.launcher.create(recursive: true);
    await paths.launcher.writeAsString('existing launcher');
    final staged = await _stageRuntime(
      root,
      package,
      version: '1.2.3',
      contents: 'invalid payload',
      name: 'failed',
    );

    await expectLater(
      cockpitInstallRuntimeRelease(
        environment: <String, String>{'PUB_CACHE': pubCache.path},
        windows: Platform.isWindows,
        stagedExecutable: staged.executable,
        stagedResources: staged.resources,
        version: '1.2.3',
        verify: (_) => throw const FormatException('invalid runtime'),
      ),
      throwsFormatException,
    );

    expect(await paths.launcher.readAsString(), 'existing launcher');
    expect(await paths.releases.list().toList(), isEmpty);
  });

  test('migrates a legacy Unix Pub-bin AOT without manual cleanup', () async {
    if (Platform.isWindows) return;
    const version = '1.2.3';
    final paths = CockpitInstalledRuntimePaths(
      pubCacheRoot: pubCache.path,
      windows: false,
    );
    await paths.legacyNative.create(recursive: true);
    await paths.legacyNative.writeAsString('legacy aot');
    final legacyResources = Directory(
      cockpitRuntimeResourceDirectoryPath(
        paths.legacyNative.path,
        windows: false,
      ),
    );
    await cockpitWriteRuntimeResources(
      packageRoot: package,
      destination: legacyResources,
      version: version,
    );

    final activePath = await cockpitPrepareInstalledRuntime(
      environment: <String, String>{'PUB_CACHE': pubCache.path},
      windows: false,
      resolvedExecutable: paths.legacyNative.path,
      version: version,
      verify: (executable) async {
        expect(await executable.readAsString(), 'legacy aot');
      },
    );

    expect(activePath, isNotNull);
    expect(await paths.legacyNative.readAsString(), startsWith('#!/usr/bin'));
    expect(await legacyResources.exists(), isFalse);
    expect(cockpitCurrentExecutable(), activePath);
    expect(
      await cockpitReadCanonicalInstalledRuntime(
        environment: <String, String>{'PUB_CACHE': pubCache.path},
        windows: false,
        resolvedExecutable: activePath!,
        version: version,
      ),
      isNotNull,
    );
  });

  test(
    'reuses the active Windows runtime while legacy EXE cleanup runs',
    () async {
      const version = '1.2.3';
      final active = await _writeCanonicalRuntime(
        pubCache,
        package,
        version: version,
        windows: true,
      );
      await active.paths.legacyNative.create(recursive: true);
      await active.paths.legacyNative.writeAsString('legacy exe');
      final legacyResources = Directory(
        cockpitRuntimeResourceDirectoryPath(
          active.paths.legacyNative.path,
          windows: true,
        ),
      );
      await cockpitWriteRuntimeResources(
        packageRoot: package,
        destination: legacyResources,
        version: version,
      );

      final activePath = await cockpitPrepareInstalledRuntime(
        environment: <String, String>{'PUB_CACHE': pubCache.path},
        windows: true,
        resolvedExecutable: active.paths.legacyNative.path,
        version: version,
        verify: (_) => throw StateError('must reuse the active runtime'),
      );

      expect(activePath, active.executable.path);
      expect(await active.paths.legacyNative.exists(), isFalse);
      expect(await legacyResources.exists(), isFalse);
    },
  );
}

Future<({File executable, Directory resources})> _stageRuntime(
  Directory root,
  Directory package, {
  required String version,
  required String contents,
  String name = 'staged',
}) async {
  final directory = await Directory('${root.path}/$name').create();
  final executable = File(
    '${directory.path}/${Platform.isWindows ? 'cockpit.exe' : 'cockpit'}',
  );
  await executable.writeAsString(contents);
  final resources = Directory('${directory.path}/resources');
  await cockpitWriteRuntimeResources(
    packageRoot: package,
    destination: resources,
    version: version,
  );
  return (executable: executable, resources: resources);
}

Future<void> _writePackageResources(Directory package) async {
  final android = Directory(
    '${package.path}/lib/src/system_control/resources/android',
  );
  await android.create(recursive: true);
  await File('${android.path}/cockpit-driver.apk').writeAsBytes(<int>[1, 2]);
  await File(
    '${android.path}/cockpit-driver-test.apk',
  ).writeAsBytes(<int>[3, 4]);
}

Future<CockpitInstalledRuntime> _writeCanonicalRuntime(
  Directory pubCache,
  Directory package, {
  required String version,
  required bool windows,
}) async {
  final paths = CockpitInstalledRuntimePaths(
    pubCacheRoot: pubCache.path,
    windows: windows,
  );
  final release = Directory.fromUri(paths.releases.uri.resolve('current/'));
  final executable = File.fromUri(release.uri.resolve(paths.executableName));
  await executable.create(recursive: true);
  await executable.writeAsString('active runtime');
  final resources = Directory(
    cockpitRuntimeResourceDirectoryPath(executable.path, windows: windows),
  );
  await cockpitWriteRuntimeResources(
    packageRoot: package,
    destination: resources,
    version: version,
  );
  await paths.launcher.create(recursive: true);
  await paths.launcher.writeAsString(
    cockpitRuntimeLauncherContents(
      executablePath: executable.path,
      version: version,
      windows: windows,
    ),
  );
  return CockpitInstalledRuntime(
    paths: paths,
    release: release,
    executable: executable,
    resources: resources,
  );
}
