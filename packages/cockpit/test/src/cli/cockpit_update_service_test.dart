import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/cli/cockpit_update_service.dart';
import 'package:cockpit/src/cli/cockpit_update_support.dart';
import 'package:cockpit/src/infrastructure/cockpit_runtime_resources.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'update check returns only a useful next step for a newer release',
    () async {
      final service = CockpitUpdateService(
        latestVersionLookup: (_) async => '4.0.19',
      );

      final result = await service.check(currentVersion: '4.0.18');

      expect(result.toJson(), <String, Object?>{
        'version': '4.0.18',
        'latest': '4.0.19',
        'next': 'cockpit update',
      });
    },
  );

  test(
    'update check stays compact when the current release is latest',
    () async {
      final service = CockpitUpdateService(
        latestVersionLookup: (_) async => '4.0.18',
      );

      final result = await service.check(currentVersion: '4.0.18');

      expect(result.toJson(), <String, Object?>{'version': '4.0.18'});
    },
  );

  test('update check reports lookup failures instead of hiding them', () async {
    final service = CockpitUpdateService(
      latestVersionLookup: (_) => throw const SocketException('offline'),
    );

    await expectLater(
      service.check(currentVersion: '4.0.18'),
      throwsA(
        isA<CockpitUpdateException>().having(
          (error) => error.code,
          'code',
          'updateCheckFailed',
        ),
      ),
    );
  });

  test('latest-version lookup bypasses cached Pub metadata', () async {
    late http.Request request;
    final client = MockClient((candidate) async {
      request = candidate;
      return http.Response(
        jsonEncode(<String, Object?>{
          'latest': <String, Object?>{'version': '4.0.4'},
        }),
        HttpStatus.ok,
        request: candidate,
      );
    });

    final version = await cockpitLookupLatestVersion(
      const Duration(seconds: 1),
      client: client,
    );

    expect(version, '4.0.4');
    expect(request.headers['accept-encoding'], 'identity');
    expect(request.headers['cache-control'], 'no-cache');
    expect(request.headers['pragma'], 'no-cache');
    expect(request.url.queryParameters['_'], isNotEmpty);
  });

  test('reads the stale dependency reported by Dart Pub', () {
    final result = ProcessResult(
      1,
      1,
      '',
      'Because cockpit >=4.0.5 depends on cockpit_protocol ^4.0.5 which '
          "doesn't match any versions, cockpit >=4.0.5 is forbidden.\n",
    );

    expect(cockpitStaleHostedDependency(result), (
      package: 'cockpit_protocol',
      constraint: '^4.0.5',
    ));
  });

  test('reads a stale root package reported by Dart Pub', () {
    final result = ProcessResult(
      1,
      1,
      '',
      'Because pub global activate depends on cockpit 4.0.5 which '
          "doesn't match any versions, version solving failed.\n",
    );

    expect(cockpitStaleHostedDependency(result), (
      package: 'cockpit',
      constraint: '4.0.5',
    ));
  });

  test('recognizes a newly published version missing from Dart Pub', () {
    final unavailable = ProcessResult(
      1,
      1,
      '',
      'Package cockpit has no versions that match 4.0.9.\n',
    );
    final unrelated = ProcessResult(
      2,
      1,
      '',
      'Package cockpit has no versions that match 4.0.8.\n',
    );

    expect(
      cockpitHostedVersionUnavailable(
        unavailable,
        package: 'cockpit',
        version: '4.0.9',
      ),
      isTrue,
    );
    expect(
      cockpitHostedVersionUnavailable(
        unrelated,
        package: 'cockpit',
        version: '4.0.9',
      ),
      isFalse,
    );
  });

  test('normalizes update cleanup paths before boundary checks', () {
    final root = '${Directory.systemTemp.path}/cockpit-update-boundary';
    expect(cockpitPathIsWithin('$root/child', root), isTrue);
    expect(cockpitPathIsWithin('$root/../outside', root), isFalse);
  });

  test('matches executable paths through filesystem aliases', () async {
    if (Platform.isWindows) return;
    final root = await Directory.systemTemp.createTemp('cockpit-path-alias-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final executable = File('${root.path}/cockpit');
    await executable.writeAsString('aot');
    final alias = Link('${root.path}/cockpit-alias');
    await alias.create(executable.path);

    expect(
      cockpitPathsMatch(executable.path, alias.path, windows: false),
      isTrue,
    );
  });

  test('skips reinstall for a current canonical hosted AOT install', () async {
    final pubCache = await Directory.systemTemp.createTemp(
      'cockpit-update-current-',
    );
    addTearDown(() async {
      if (await pubCache.exists()) await pubCache.delete(recursive: true);
    });
    final executable = await _writeCanonicalInstall(
      pubCache,
      version: '3.0.7',
      contents: 'current aot',
    );
    final legacy = Directory('${pubCache.path}/cockpit-aot');
    await legacy.create();
    final calls = <List<String>>[];
    var lookups = 0;
    final service = CockpitUpdateService(
      environment: <String, String>{'PUB_CACHE': pubCache.path},
      resolvedExecutable: executable.path,
      windows: false,
      latestVersionLookup: (timeout) async {
        lookups += 1;
        expect(timeout, greaterThan(Duration.zero));
        return '3.0.7';
      },
      processRunner: (executable, arguments, timeout) async {
        calls.add(<String>[executable, ...arguments]);
        return ProcessResult(1, 0, '', '');
      },
    );

    final result = await service.update(
      currentVersion: '3.0.7',
      timeout: const Duration(minutes: 1),
    );

    expect(result.toJson(), <String, Object?>{
      'version': '3.0.7',
      'updated': false,
      'supervisor': 'ready',
      'next': 'cockpit skill',
    });
    expect(lookups, 1);
    expect(calls, hasLength(1));
    expect(
      calls.single,
      containsAllInOrder(<String>[
        executable.path,
        'server',
        '--format',
        'none',
        '--timeout',
      ]),
    );
    expect(await executable.readAsString(), 'current aot');
    expect(await legacy.exists(), isFalse);
    expect(await _updateWorkspaces(pubCache), isEmpty);
  });

  test('installs a newer hosted release after the fast check', () async {
    final pubCache = await Directory.systemTemp.createTemp(
      'cockpit-update-newer-',
    );
    addTearDown(() async {
      if (await pubCache.exists()) await pubCache.delete(recursive: true);
    });
    final executable = await _writeCanonicalInstall(
      pubCache,
      version: '3.0.7',
      contents: 'current aot',
    );
    final calls = <List<String>>[];
    final service = CockpitUpdateService(
      environment: <String, String>{'PUB_CACHE': pubCache.path},
      resolvedExecutable: executable.path,
      windows: false,
      latestVersionLookup: (_) async => '3.0.8',
      processRunner: (command, arguments, timeout) async {
        calls.add(<String>[command, ...arguments]);
        if (arguments.contains('activate')) {
          await _writeActivatedPackage(pubCache, version: '3.0.8');
        }
        if (arguments.contains('compile')) {
          final output = arguments[arguments.indexOf('-o') + 1];
          await File(output).writeAsString('new aot');
        }
        if (arguments.last == '--version') {
          return ProcessResult(calls.length, 0, 'cockpit 3.0.8\n', '');
        }
        return ProcessResult(calls.length, 0, '', '');
      },
    );

    final result = await service.update(
      currentVersion: '3.0.7',
      timeout: const Duration(minutes: 1),
    );

    expect(result.version, '3.0.8');
    expect(calls, hasLength(6));
    expect(
      calls.first,
      containsAllInOrder(<String>['pub', 'global', 'activate']),
    );
    final installed = await _activeRuntime(pubCache, version: '3.0.8');
    expect(await installed.executable.readAsString(), 'new aot');
    expect(
      await installed.paths.launcher.readAsString(),
      cockpitRuntimeLauncherContents(
        executablePath: installed.executable.path,
        version: '3.0.8',
        windows: false,
      ),
    );
  });

  test(
    'refreshes a stale dependency index before retrying activation',
    () async {
      final pubCache = await Directory.systemTemp.createTemp(
        'cockpit-update-stale-dependency-',
      );
      addTearDown(() async {
        if (await pubCache.exists()) await pubCache.delete(recursive: true);
      });
      final executable = await _writeCanonicalInstall(
        pubCache,
        version: '4.0.4',
        contents: 'current aot',
      );
      final calls = <List<String>>[];
      var activationAttempts = 0;
      final service = CockpitUpdateService(
        environment: <String, String>{'PUB_CACHE': pubCache.path},
        resolvedExecutable: executable.path,
        windows: false,
        latestVersionLookup: (_) async => '4.0.5',
        processRunner: (command, arguments, timeout) async {
          calls.add(<String>[command, ...arguments]);
          if (arguments.contains('activate')) {
            activationAttempts += 1;
            if (activationAttempts == 1) {
              return ProcessResult(
                calls.length,
                1,
                '',
                'Because cockpit >=4.0.5 depends on cockpit_protocol ^4.0.5 '
                    "which doesn't match any versions, cockpit is forbidden.\n",
              );
            }
            await _writeActivatedPackage(pubCache, version: '4.0.5');
          }
          if (arguments.contains('compile')) {
            final output = arguments[arguments.indexOf('-o') + 1];
            await File(output).writeAsString('new aot');
          }
          if (arguments.last == '--version') {
            return ProcessResult(calls.length, 0, 'cockpit 4.0.5\n', '');
          }
          return ProcessResult(calls.length, 0, '', '');
        },
      );

      final result = await service.update(
        currentVersion: '4.0.4',
        timeout: const Duration(minutes: 1),
      );

      expect(result.version, '4.0.5');
      expect(activationAttempts, 2);
      expect(calls[0], containsAllInOrder(<String>['cockpit', '4.0.5']));
      expect(calls[1], <String>[
        'dart',
        'pub',
        'cache',
        'add',
        'cockpit_protocol',
        '--version',
        '^4.0.5',
      ]);
    },
  );

  test('waits for a newly published root package within the timeout', () async {
    final pubCache = await Directory.systemTemp.createTemp(
      'cockpit-update-publishing-',
    );
    addTearDown(() async {
      if (await pubCache.exists()) await pubCache.delete(recursive: true);
    });
    final executable = await _writeCanonicalInstall(
      pubCache,
      version: '4.0.8',
      contents: 'current aot',
    );
    final calls = <List<String>>[];
    final waits = <Duration>[];
    final progress = <String>[];
    var activationAttempts = 0;
    var refreshAttempts = 0;
    final service = CockpitUpdateService(
      environment: <String, String>{'PUB_CACHE': pubCache.path},
      resolvedExecutable: executable.path,
      windows: false,
      latestVersionLookup: (_) async => '4.0.9',
      delay: (duration) async => waits.add(duration),
      processRunner: (command, arguments, timeout) async {
        calls.add(<String>[command, ...arguments]);
        if (arguments.contains('activate')) {
          activationAttempts += 1;
          if (activationAttempts == 1) {
            return ProcessResult(
              calls.length,
              1,
              '',
              'Because pub global activate depends on cockpit 4.0.9 which '
                  "doesn't match any versions, version solving failed.\n",
            );
          }
          await _writeActivatedPackage(pubCache, version: '4.0.9');
        }
        if (arguments.contains('cache')) {
          refreshAttempts += 1;
          if (refreshAttempts < 3) {
            return ProcessResult(
              calls.length,
              1,
              '',
              'Package cockpit has no versions that match 4.0.9.\n',
            );
          }
        }
        if (arguments.contains('compile')) {
          final output = arguments[arguments.indexOf('-o') + 1];
          await File(output).writeAsString('new aot');
        }
        if (arguments.last == '--version') {
          return ProcessResult(calls.length, 0, 'cockpit 4.0.9\n', '');
        }
        return ProcessResult(calls.length, 0, '', '');
      },
    );

    final result = await service.update(
      currentVersion: '4.0.8',
      timeout: const Duration(minutes: 1),
      onProgress: progress.add,
    );

    expect(result.version, '4.0.9');
    expect(activationAttempts, 2);
    expect(refreshAttempts, 3);
    expect(waits, const <Duration>[Duration(seconds: 1), Duration(seconds: 2)]);
    expect(
      progress.where((message) => message.contains('still indexing')),
      hasLength(2),
    );
  });

  test(
    'reinstalls a source activation even when its version is current',
    () async {
      final pubCache = await Directory.systemTemp.createTemp(
        'cockpit-update-source-',
      );
      addTearDown(() async {
        if (await pubCache.exists()) await pubCache.delete(recursive: true);
      });
      await _writeActivatedPackage(pubCache, version: '3.0.7', hosted: false);
      final executable = File('${pubCache.path}/bin/cockpit');
      await executable.create(recursive: true);
      await executable.writeAsString('source aot');
      final calls = <List<String>>[];
      var lookups = 0;
      final service = CockpitUpdateService(
        environment: <String, String>{'PUB_CACHE': pubCache.path},
        resolvedExecutable: executable.path,
        windows: false,
        latestVersionLookup: (_) async {
          lookups += 1;
          return '3.0.7';
        },
        processRunner: (command, arguments, timeout) async {
          calls.add(<String>[command, ...arguments]);
          if (arguments.contains('activate')) {
            await _writeActivatedPackage(pubCache, version: '3.0.7');
          }
          if (arguments.contains('compile')) {
            final output = arguments[arguments.indexOf('-o') + 1];
            await File(output).writeAsString('hosted aot');
          }
          if (arguments.last == '--version') {
            return ProcessResult(calls.length, 0, 'cockpit 3.0.7\n', '');
          }
          return ProcessResult(calls.length, 0, '', '');
        },
      );

      await service.update(
        currentVersion: '3.0.7',
        timeout: const Duration(minutes: 1),
      );

      expect(lookups, 0);
      expect(calls, hasLength(6));
      expect(
        calls.first,
        containsAllInOrder(<String>['pub', 'global', 'activate']),
      );
      final installed = await _activeRuntime(pubCache, version: '3.0.7');
      expect(await installed.executable.readAsString(), 'hosted aot');
    },
  );

  test('falls back to the full update when the latest lookup fails', () async {
    final pubCache = await Directory.systemTemp.createTemp(
      'cockpit-update-lookup-failure-',
    );
    addTearDown(() async {
      if (await pubCache.exists()) await pubCache.delete(recursive: true);
    });
    final executable = await _writeCanonicalInstall(
      pubCache,
      version: '3.0.7',
      contents: 'current aot',
    );
    final calls = <List<String>>[];
    final service = CockpitUpdateService(
      environment: <String, String>{'PUB_CACHE': pubCache.path},
      resolvedExecutable: executable.path,
      windows: false,
      latestVersionLookup: (_) async => throw const SocketException('offline'),
      processRunner: (command, arguments, timeout) async {
        calls.add(<String>[command, ...arguments]);
        if (arguments.contains('compile')) {
          final output = arguments[arguments.indexOf('-o') + 1];
          await File(output).writeAsString('rebuilt aot');
        }
        if (arguments.last == '--version') {
          return ProcessResult(calls.length, 0, 'cockpit 3.0.7\n', '');
        }
        return ProcessResult(calls.length, 0, '', '');
      },
    );

    await service.update(
      currentVersion: '3.0.7',
      timeout: const Duration(minutes: 1),
    );

    expect(calls, hasLength(6));
    expect(
      calls.first,
      containsAllInOrder(<String>['pub', 'global', 'activate']),
    );
    final installed = await _activeRuntime(pubCache, version: '3.0.7');
    expect(await installed.executable.readAsString(), 'rebuilt aot');
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
      'next': 'cockpit skill',
    });
    expect(calls, hasLength(6));
    expect(calls[0], <String>[
      Platform.isWindows ? 'dart.exe' : 'dart',
      'pub',
      'global',
      'activate',
      'cockpit',
    ]);
    expect(
      calls[1],
      containsAllInOrder(<String>['cockpit:cockpit', '--version']),
    );
    expect(calls[2], containsAllInOrder(<String>['compile', 'exe']));
    expect(calls[3], contains('--version'));
    expect(calls[4], contains('--version'));
    final installed = await _activeRuntime(pubCache, version: '3.0.7');
    expect(
      calls[5],
      containsAllInOrder(<String>[
        installed.executable.path,
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
    final installed = await _activeRuntime(pubCache, version: '3.0.7');
    expect(await installed.executable.readAsString(), 'optimized aot');
    expect(await native.readAsString(), startsWith('#!/usr/bin/env sh'));
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
    final installed = await _activeRuntime(
      pubCache,
      version: '3.0.7',
      windows: true,
      allowLegacyNative: true,
    );
    expect(await installed.executable.readAsString(), 'optimized windows aot');
    expect(await native.exists(), isFalse);
    expect(
      await launcher.readAsString(),
      cockpitRuntimeLauncherContents(
        executablePath: installed.executable.path,
        version: '3.0.7',
        windows: true,
      ),
    );
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

  test('blocks a stale Pub cache from downgrading Cockpit', () async {
    final pubCache = await Directory.systemTemp.createTemp(
      'cockpit-update-downgrade-',
    );
    addTearDown(() async {
      if (await pubCache.exists()) await pubCache.delete(recursive: true);
    });
    final executable = await _writeCanonicalInstall(
      pubCache,
      version: '3.0.7',
      contents: 'current aot',
    );
    final launcher = File('${pubCache.path}/bin/cockpit');
    final originalLauncher = await launcher.readAsString();
    final calls = <List<String>>[];
    final service = CockpitUpdateService(
      environment: <String, String>{'PUB_CACHE': pubCache.path},
      resolvedExecutable: executable.path,
      windows: false,
      latestVersionLookup: (_) async => '3.0.8',
      processRunner: (command, arguments, timeout) async {
        calls.add(<String>[command, ...arguments]);
        if (arguments.contains('activate')) {
          await launcher.writeAsString('downgraded Pub launcher');
        }
        return ProcessResult(
          calls.length,
          0,
          calls.length == 2 ? 'cockpit 3.0.6\n' : '',
          '',
        );
      },
    );

    await expectLater(
      service.update(
        currentVersion: '3.0.7',
        timeout: const Duration(minutes: 1),
      ),
      throwsA(
        isA<CockpitUpdateException>()
            .having((error) => error.code, 'code', 'updateDowngradeBlocked')
            .having(
              (error) => error.message,
              'message',
              contains('older than the running 3.0.7 release'),
            ),
      ),
    );
    expect(calls, hasLength(2));
    expect(calls.first, <String>[
      'dart',
      'pub',
      'global',
      'activate',
      'cockpit',
      '3.0.8',
    ]);
    expect(await launcher.readAsString(), originalLauncher);
  });
}

Future<Directory> _writeActivatedPackage(
  Directory pubCache, {
  required String version,
  bool hosted = true,
}) async {
  final package = Directory(
    hosted
        ? '${pubCache.path}/hosted/pub.dev/cockpit-$version'
        : '${pubCache.path}/source/cockpit',
  );
  final entrypoint = File('${package.path}/bin/cockpit.dart');
  await entrypoint.create(recursive: true);
  await entrypoint.writeAsString('void main() {}\n');
  await File(
    '${package.path}/pubspec.yaml',
  ).writeAsString('name: cockpit\nversion: $version\n');
  final androidResources = Directory(
    '${package.path}/lib/src/system_control/resources/android',
  );
  await androidResources.create(recursive: true);
  await File(
    '${androidResources.path}/cockpit-driver.apk',
  ).writeAsBytes(<int>[1, 2, 3], flush: true);
  await File(
    '${androidResources.path}/cockpit-driver-test.apk',
  ).writeAsBytes(<int>[4, 5, 6], flush: true);
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
  return package;
}

Future<File> _writeCanonicalInstall(
  Directory pubCache, {
  required String version,
  required String contents,
  bool windows = false,
}) async {
  final package = await _writeActivatedPackage(pubCache, version: version);
  final paths = CockpitInstalledRuntimePaths(
    pubCacheRoot: pubCache.path,
    windows: windows,
  );
  final release = Directory.fromUri(paths.releases.uri.resolve('current/'));
  final executable = File.fromUri(release.uri.resolve(paths.executableName));
  await executable.create(recursive: true);
  await executable.writeAsString(contents);
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
  return executable;
}

Future<CockpitInstalledRuntime> _activeRuntime(
  Directory pubCache, {
  required String version,
  bool windows = false,
  bool allowLegacyNative = false,
}) async {
  final paths = CockpitInstalledRuntimePaths(
    pubCacheRoot: pubCache.path,
    windows: windows,
  );
  await for (final entity in paths.releases.list(followLinks: false)) {
    if (entity is! Directory) continue;
    final executable = File.fromUri(entity.uri.resolve(paths.executableName));
    final installed = await cockpitReadCanonicalInstalledRuntime(
      environment: <String, String>{'PUB_CACHE': pubCache.path},
      windows: windows,
      resolvedExecutable: executable.path,
      version: version,
      allowLegacyNative: allowLegacyNative,
    );
    if (installed != null) return installed;
  }
  throw StateError('Canonical Cockpit runtime was not installed.');
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
