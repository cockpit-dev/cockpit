import 'dart:io';

import 'package:cockpit/src/cli/cockpit_update_service.dart';
import 'package:test/test.dart';

void main() {
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
    final calls = <List<String>>[];
    final service = CockpitUpdateService(
      environment: <String, String>{'PUB_CACHE': pubCache.path},
      resolvedExecutable: '${pubCache.path}/bin/cockpit',
      processRunner: (executable, arguments, timeout) async {
        calls.add(<String>[executable, ...arguments]);
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
    expect(calls, hasLength(3));
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
    expect(
      calls[2],
      containsAllInOrder(<String>[
        'cockpit:cockpit',
        'server',
        '--format',
        'none',
        '--timeout',
      ]),
    );
    expect(await legacy.exists(), isFalse);
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
