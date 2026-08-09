import 'dart:io';

import 'package:cockpit/src/cli/cockpit_update_service.dart';
import 'package:cockpit/src/cli/cockpit_update_support.dart';
import 'package:test/test.dart';

void main() {
  test('normalizes update cleanup paths before boundary checks', () {
    final root = '${Directory.systemTemp.path}/cockpit-update-boundary';
    expect(cockpitPathIsWithin('$root/child', root), isTrue);
    expect(cockpitPathIsWithin('$root/../outside', root), isFalse);
  });

  test('updates, verifies, reconciles, and removes retired payload', () async {
    final pubCache = await Directory.systemTemp.createTemp(
      'cockpit-update-service-',
    );
    addTearDown(() async {
      if (await pubCache.exists()) await pubCache.delete(recursive: true);
    });
    final legacy = Directory('${pubCache.path}/cockpit-aot');
    await legacy.create(recursive: true);
    await File('${legacy.path}/cockpit').writeAsString('retired');
    await _writeActivatedPackage(pubCache, version: '3.0.7');
    final calls = <List<String>>[];
    final service = CockpitUpdateService(
      environment: <String, String>{'PUB_CACHE': pubCache.path},
      resolvedExecutable: '${pubCache.path}/bin/cockpit',
      processRunner: (executable, arguments, timeout) async {
        calls.add(<String>[executable, ...arguments]);
        if (arguments.contains('compile')) {
          final output = arguments[arguments.indexOf('-o') + 1];
          await File(output).writeAsString('compiled');
          return ProcessResult(calls.length, 0, 'Generated: $output\n', '');
        }
        if (arguments.last == '--version') {
          return ProcessResult(2, 0, 'cockpit 3.0.7\n', '');
        }
        return ProcessResult(1, 0, '', '');
      },
    );

    final result = await service.update(
      currentVersion: '3.0.6',
      timeout: const Duration(minutes: 1),
    );

    expect(result.toJson(), <String, Object?>{
      'version': '3.0.7',
      'updated': true,
      'previous': '3.0.6',
      'supervisor': 'ready',
    });
    expect(calls, hasLength(6));
    expect(calls[0], <String>[
      Platform.isWindows ? 'dart.exe' : 'dart',
      'pub',
      'global',
      'activate',
      'cockpit',
      'any',
    ]);
    expect(
      calls[1],
      containsAllInOrder(<String>['cockpit:cockpit', '--version']),
    );
    expect(calls[2], containsAllInOrder(<String>['compile', 'exe']));
    expect(calls[3], contains('--version'));
    expect(calls[4], contains('--version'));
    expect(
      calls[5],
      containsAllInOrder(<String>[
        '${pubCache.path}/bin/cockpit',
        'server',
        '--format',
        'none',
        '--timeout',
      ]),
    );
    expect(await legacy.exists(), isFalse);
    expect(await File('${pubCache.path}/bin/cockpit').exists(), isTrue);
  });

  test('failed activation stops before verification or cleanup', () async {
    final pubCache = await Directory.systemTemp.createTemp(
      'cockpit-update-failure-',
    );
    addTearDown(() async {
      if (await pubCache.exists()) await pubCache.delete(recursive: true);
    });
    final legacy = Directory('${pubCache.path}/cockpit-aot');
    await legacy.create(recursive: true);
    var calls = 0;
    final service = CockpitUpdateService(
      environment: <String, String>{'PUB_CACHE': pubCache.path},
      processRunner: (executable, arguments, timeout) async {
        calls += 1;
        return ProcessResult(1, 1, '', 'network unavailable\n');
      },
    );

    await expectLater(
      service.update(timeout: const Duration(minutes: 1)),
      throwsA(
        isA<CockpitUpdateException>()
            .having((error) => error.code, 'code', 'updateInstallFailed')
            .having(
              (error) => error.message,
              'message',
              contains('network unavailable'),
            ),
      ),
    );
    expect(calls, 1);
    expect(await legacy.exists(), isTrue);
  });

  test('hands a native Pub bin executable to Pub and reinstalls AOT', () async {
    final pubCache = await Directory.systemTemp.createTemp(
      'cockpit-update-native-takeover-',
    );
    addTearDown(() async {
      if (await pubCache.exists()) await pubCache.delete(recursive: true);
    });
    await _writeActivatedPackage(pubCache, version: '3.0.7');
    final native = File('${pubCache.path}/bin/cockpit');
    await native.create(recursive: true);
    await native.writeAsBytes(<int>[0xcf, 0xfa, 0xed, 0xfe]);
    var sawFallback = false;
    final service = CockpitUpdateService(
      environment: <String, String>{'PUB_CACHE': pubCache.path},
      resolvedExecutable: native.path,
      windows: false,
      processRunner: (executable, arguments, timeout) async {
        if (arguments.contains('activate')) {
          final fallback = await native.readAsString();
          sawFallback =
              fallback.contains('# Package: cockpit') &&
              fallback.contains('cockpit-previous');
          await native.writeAsString('hosted launcher');
        } else if (arguments.contains('compile')) {
          final output = arguments[arguments.indexOf('-o') + 1];
          await File(output).writeAsString('optimized aot');
        }
        if (arguments.last == '--version') {
          return ProcessResult(1, 0, 'cockpit 3.0.7\n', '');
        }
        return ProcessResult(1, 0, '', '');
      },
    );

    await service.update(
      currentVersion: '3.0.6',
      timeout: const Duration(minutes: 1),
    );

    expect(sawFallback, isTrue);
    expect(await native.readAsString(), 'optimized aot');
    expect(await _updateWorkspaces(pubCache), isEmpty);
  });

  test('restores the native executable when Pub activation fails', () async {
    final pubCache = await Directory.systemTemp.createTemp(
      'cockpit-update-native-restore-',
    );
    addTearDown(() async {
      if (await pubCache.exists()) await pubCache.delete(recursive: true);
    });
    final native = File('${pubCache.path}/bin/cockpit');
    await native.create(recursive: true);
    final original = <int>[0xcf, 0xfa, 0xed, 0xfe, 0, 1, 2, 3];
    await native.writeAsBytes(original);
    final service = CockpitUpdateService(
      environment: <String, String>{'PUB_CACHE': pubCache.path},
      resolvedExecutable: native.path,
      windows: false,
      processRunner: (executable, arguments, timeout) async {
        expect(await native.readAsString(), contains('# Package: cockpit'));
        return ProcessResult(1, 1, '', 'network unavailable\n');
      },
    );

    await expectLater(
      service.update(timeout: const Duration(minutes: 1)),
      throwsA(
        isA<CockpitUpdateException>().having(
          (error) => error.code,
          'code',
          'updateInstallFailed',
        ),
      ),
    );

    expect(await native.readAsBytes(), original);
    expect(await _updateWorkspaces(pubCache), isEmpty);
  });

  test('uses a recoverable batch handoff for a Windows AOT install', () async {
    final pubCache = await Directory.systemTemp.createTemp(
      'cockpit-update-windows-takeover-',
    );
    addTearDown(() async {
      if (await pubCache.exists()) await pubCache.delete(recursive: true);
    });
    await _writeActivatedPackage(pubCache, version: '3.0.7');
    final native = File('${pubCache.path}/bin/cockpit.exe');
    final launcher = File('${pubCache.path}/bin/cockpit.bat');
    await native.create(recursive: true);
    await native.writeAsBytes(<int>[0x4d, 0x5a, 0, 0]);
    await launcher.writeAsString('previous hosted batch');
    var sawFallback = false;
    final service = CockpitUpdateService(
      environment: <String, String>{'PUB_CACHE': pubCache.path},
      resolvedExecutable: native.path,
      windows: true,
      processRunner: (executable, arguments, timeout) async {
        if (arguments.contains('activate')) {
          final fallback = await launcher.readAsString();
          sawFallback =
              fallback.contains('rem Package: cockpit') &&
              fallback.contains('cockpit-previous.exe');
          await launcher.writeAsString('hosted 3.0.7 batch');
        } else if (arguments.contains('compile')) {
          final output = arguments[arguments.indexOf('-o') + 1];
          await File(output).writeAsString('optimized windows aot');
        }
        if (arguments.last == '--version') {
          return ProcessResult(1, 0, 'cockpit 3.0.7\n', '');
        }
        return ProcessResult(1, 0, '', '');
      },
    );

    await service.update(
      currentVersion: '3.0.6',
      timeout: const Duration(minutes: 1),
    );

    expect(sawFallback, isTrue);
    expect(await native.readAsString(), 'optimized windows aot');
    expect(await launcher.readAsString(), 'hosted 3.0.7 batch');
    expect(await _updateWorkspaces(pubCache), isEmpty);
  });

  test('rejects an untrusted installed version response', () async {
    var calls = 0;
    final service = CockpitUpdateService(
      environment: const <String, String>{},
      processRunner: (executable, arguments, timeout) async {
        calls += 1;
        return ProcessResult(
          calls,
          0,
          calls == 2 ? 'unexpected output\n' : '',
          '',
        );
      },
    );

    await expectLater(
      service.update(timeout: const Duration(minutes: 1)),
      throwsA(
        isA<CockpitUpdateException>()
            .having((error) => error.code, 'code', 'updateVerificationFailed')
            .having((error) => error.retryable, 'retryable', isFalse),
      ),
    );
    expect(calls, 2);
  });
}

Future<void> _writeActivatedPackage(
  Directory pubCache, {
  required String version,
}) async {
  final package = Directory('${pubCache.path}/hosted/cockpit-$version');
  final entrypoint = File('${package.path}/bin/cockpit.dart');
  await entrypoint.create(recursive: true);
  await entrypoint.writeAsString('void main() {}\n');
  final config = File(
    '${pubCache.path}/global_packages/cockpit/.dart_tool/package_config.json',
  );
  await config.create(recursive: true);
  final rootUri = package.uri.toString().replaceFirst(RegExp(r'/$'), '');
  await config.writeAsString('''
{
  "configVersion": 2,
  "packages": [
    {
      "name": "cockpit",
      "rootUri": "$rootUri",
      "packageUri": "lib/",
      "languageVersion": "3.8"
    }
  ]
}
''');
}

Future<List<FileSystemEntity>> _updateWorkspaces(Directory pubCache) async {
  final temp = Directory('${pubCache.path}/_temp');
  if (!await temp.exists()) return const <FileSystemEntity>[];
  return temp
      .list()
      .where(
        (entity) => entity.uri.pathSegments.any(
          (segment) => segment.startsWith('cockpit-update-'),
        ),
      )
      .toList();
}
