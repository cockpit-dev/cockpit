import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/foundation/cockpit_version.dart';
import 'package:cockpit/src/infrastructure/cockpit_runtime_resources.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('cockpit-resources-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('writes and validates resources beside an AOT executable', () async {
    final package = await _writePackage(root, cockpitVersion);
    final executable = File('${root.path}/bin/cockpit');
    await executable.create(recursive: true);
    final resources = Directory(
      cockpitRuntimeResourceDirectoryPath(executable.path),
    );

    await cockpitWriteRuntimeResources(
      packageRoot: package,
      destination: resources,
      version: cockpitVersion,
    );

    expect(
      await cockpitHasValidRuntimeResources(
        executablePath: executable.path,
        version: cockpitVersion,
      ),
      isTrue,
    );
    final resolved = await cockpitResolveRuntimePackageAsset(
      Uri.parse(
        'package:cockpit/src/system_control/resources/android/cockpit-driver.apk',
      ),
      executablePath: executable.path,
      environment: const <String, String>{},
      packageResolver: (_) async => null,
    );
    expect(await File.fromUri(resolved!).readAsBytes(), <int>[1, 2, 3]);
  });

  test(
    'uses the exact activated package during an old updater handoff',
    () async {
      final package = await _writePackage(root, cockpitVersion);
      final config = File(
        '${root.path}/global_packages/cockpit/.dart_tool/package_config.json',
      );
      await config.create(recursive: true);
      await config.writeAsString(
        jsonEncode(<String, Object?>{
          'configVersion': 2,
          'packages': <Object?>[
            <String, Object?>{
              'name': 'cockpit',
              'rootUri': package.uri.toString(),
              'packageUri': 'lib/',
              'languageVersion': '3.8',
            },
          ],
        }),
      );

      final resolved = await cockpitResolveRuntimePackageAsset(
        Uri.parse(
          'package:cockpit/src/system_control/resources/android/cockpit-driver-test.apk',
        ),
        executablePath: '${root.path}/bin/cockpit',
        environment: <String, String>{'PUB_CACHE': root.path},
        packageResolver: (_) async => null,
      );

      expect(await File.fromUri(resolved!).readAsBytes(), <int>[4, 5, 6]);
    },
  );

  test('rejects activated resources from a different version', () async {
    final package = await _writePackage(root, '0.0.1');
    final config = File(
      '${root.path}/global_packages/cockpit/.dart_tool/package_config.json',
    );
    await config.create(recursive: true);
    await config.writeAsString(
      jsonEncode(<String, Object?>{
        'configVersion': 2,
        'packages': <Object?>[
          <String, Object?>{
            'name': 'cockpit',
            'rootUri': package.uri.toString(),
          },
        ],
      }),
    );

    expect(
      await cockpitResolveRuntimePackageAsset(
        Uri.parse(
          'package:cockpit/src/system_control/resources/android/cockpit-driver.apk',
        ),
        executablePath: '${root.path}/bin/cockpit',
        environment: <String, String>{'PUB_CACHE': root.path},
        packageResolver: (_) async => null,
      ),
      isNull,
    );
  });

  test('derives a Windows sidecar with Windows path rules', () {
    expect(
      cockpitRuntimeResourceDirectoryPath(
        r'C:\tools\cockpit.exe',
        windows: true,
      ),
      r'C:\tools\cockpit-resources',
    );
  });
}

Future<Directory> _writePackage(Directory root, String version) async {
  final package = Directory('${root.path}/package-$version');
  final android = Directory(
    '${package.path}/lib/src/system_control/resources/android',
  );
  await android.create(recursive: true);
  await File(
    '${package.path}/pubspec.yaml',
  ).writeAsString('name: cockpit\nversion: $version\n', flush: true);
  await File(
    '${android.path}/cockpit-driver.apk',
  ).writeAsBytes(<int>[1, 2, 3], flush: true);
  await File(
    '${android.path}/cockpit-driver-test.apk',
  ).writeAsBytes(<int>[4, 5, 6], flush: true);
  return package;
}
