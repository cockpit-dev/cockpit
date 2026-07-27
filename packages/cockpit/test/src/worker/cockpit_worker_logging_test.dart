import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/worker/cockpit_worker_logger.dart';
import 'package:cockpit/src/worker/cockpit_worker_secret_resolver.dart';
import 'package:cockpit/src/test/cockpit_test_secret_resolver.dart';
import 'package:test/test.dart';

void main() {
  test(
    'bounds unterminated and malformed stderr at the byte boundary',
    () async {
      final input = StreamController<List<int>>();
      final lines = input.stream
          .transform(const CockpitBoundedUtf8LineFramer(maximumBytes: 256))
          .toList();
      input.add(<int>[...List<int>.filled(400, 0x61), 0x0a]);
      input.add(<int>[0xff, 0xfe, 0x0a]);
      await input.close();

      final framed = await lines;
      expect(framed, hasLength(2));
      expect(utf8.encode(framed.first.text), hasLength(256));
      expect(framed.first.truncated, isTrue);
      expect(framed.last.text, contains('\uFFFD'));
      expect(framed.last.truncated, isFalse);
    },
  );

  test('resolved environment secrets are allowlisted and redacted', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'cockpit-worker-log-',
    );
    final logFile = File('${temporary.path}/worker.log');
    final sink = logFile.openWrite();
    final redactor = CockpitWorkerLogRedactor();
    final logger = CockpitWorkerLogger(
      stderrSink: sink,
      redactor: redactor,
      utcNow: () => DateTime.utc(2026, 7, 22),
    );
    final resolver = CockpitAllowedWorkerSecretResolver(
      providers: <CockpitWorkerSecretProvider>[
        CockpitEnvironmentSecretProvider(
          allowedNames: const <String>['API_TOKEN'],
          environment: const <String, String>{
            'API_TOKEN': 'plaintext-secret-value',
            'OTHER_TOKEN': 'must-not-resolve',
          },
        ),
      ],
      allowedProviderIds: const <String>['env'],
      redactor: redactor,
    );
    addTearDown(() async {
      await sink.close();
      await temporary.delete(recursive: true);
    });

    expect(await resolver.resolve('env:API_TOKEN'), 'plaintext-secret-value');
    logger.log(
      'error',
      'dispatch failed for plaintext-secret-value',
      fields: const <String, Object?>{
        'authorization': 'Bearer plaintext-secret-value',
      },
    );
    await sink.flush();
    final contents = await logFile.readAsString();
    expect(contents, isNot(contains('plaintext-secret-value')));
    expect(contents, contains(CockpitWorkerLogRedactor.redacted));
    await expectLater(
      resolver.resolve('env:OTHER_TOKEN'),
      throwsA(isA<CockpitTestSecretResolutionException>()),
    );
  });

  test('structured secret references survive document redaction', () {
    final redactor = CockpitWorkerLogRedactor();

    expect(
      redactor.redact(const <String, Object?>{
        'password': <String, Object?>{
          'source': 'secret',
          'type': 'string',
          'reference': 'env:COCKPIT_TEST_PASSWORD',
        },
        'token': 'plaintext-value',
      }),
      <String, Object?>{
        'password': <String, Object?>{
          'source': 'secret',
          'type': 'string',
          'reference': 'env:COCKPIT_TEST_PASSWORD',
        },
        'token': CockpitWorkerLogRedactor.redacted,
      },
    );
  });

  test('yolo environment provider resolves any valid explicit name', () async {
    final provider = CockpitEnvironmentSecretProvider(
      allowedNames: const <String>[],
      allowAllNames: true,
      environment: const <String, String>{'DYNAMIC_SECRET': 'value'},
    );

    expect(await provider.resolve('DYNAMIC_SECRET'), 'value');
    await expectLater(
      provider.resolve('../invalid'),
      throwsA(isA<CockpitTestSecretResolutionException>()),
    );
  });
}
