import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/application/cockpit_application_service_exception.dart';
import 'package:cockpit/src/application/cockpit_pub_dev_search_service.dart';
import 'package:cockpit/src/infrastructure/cockpit_http_client.dart';
import 'package:cockpit/src/infrastructure/cockpit_process_manager.dart';
import 'package:test/test.dart';

void main() {
  test('returns bounded pub.dev package summaries', () async {
    final service = CockpitPubDevSearchService(
      httpClient: _FakeHttpClient(
        responses: <String, String>{
          'https://pub.dev/api/search?q=state+management':
              '{"packages":[{"package":"riverpod"}]}',
          'https://pub.dev/api/packages/riverpod':
              '{"name":"riverpod","publisher":"example.dev","latest":{"version":"2.0.0","pubspec":{"description":"Reactive caching framework.","homepage":"https://riverpod.dev","repository":"https://github.com/rrousselGit/riverpod"}},"topics":["state-management","reactive"],"license":"MIT"}',
          'https://pub.dev/api/packages/riverpod/score':
              '{"grantedPoints":140,"maxPoints":160,"likeCount":120,"popularityScore":0.98}',
        },
      ),
    );

    final result = await service.search(
      const CockpitPubDevSearchRequest(
        query: 'state management',
        maxResults: 1,
      ),
    );

    expect(result.results, hasLength(1));
    expect(result.results.single.packageName, 'riverpod');
    expect(result.results.single.latestVersion, '2.0.0');
    expect(result.results.single.publisher, 'example.dev');
    expect(result.results.single.grantedPoints, 140);
    expect(result.results.single.popularityScore, closeTo(0.98, 0.0001));
    expect(result.results.single.homepageUrl, 'https://riverpod.dev');
    expect(
      result.results.single.repositoryUrl,
      'https://github.com/rrousselGit/riverpod',
    );
    expect(result.results.single.topics, <String>[
      'state-management',
      'reactive',
    ]);
    expect(result.results.single.license, 'MIT');
    expect(result.warnings, isEmpty);
    expect(result.suggestion, isNull);
  });

  test(
    'returns suggestions and warnings for empty and partial results',
    () async {
      final service = CockpitPubDevSearchService(
        httpClient: _FakeHttpClient(
          responses: <String, String>{
            'https://pub.dev/api/search?q=obscure+thing':
                '{"packages":[{"package":"mystery_pkg"}]}',
            'https://pub.dev/api/packages/mystery_pkg':
                '{"name":"mystery_pkg","latest":{"version":"0.1.0","pubspec":{"description":"Unknown helper."}}}',
          },
          failingUris: <String>{
            'https://pub.dev/api/packages/mystery_pkg/score',
          },
        ),
      );

      final result = await service.search(
        const CockpitPubDevSearchRequest(query: 'obscure thing'),
      );

      expect(result.results.single.packageName, 'mystery_pkg');
      expect(result.results.single.latestVersion, '0.1.0');
      expect(result.warnings, isNotEmpty);
      expect(result.suggestion, contains('Try'));
    },
  );

  test('times out instead of hanging on pub.dev search', () async {
    final service = CockpitPubDevSearchService(
      httpClient: _HangingHttpClient(),
    );

    expect(
      () => service.search(
        const CockpitPubDevSearchRequest(
          query: 'riverpod',
          timeout: Duration(milliseconds: 20),
        ),
      ),
      throwsA(isA<Exception>()),
    );
  });

  test(
    'uses the external fetch fallback when the default client fails',
    () async {
      final service = CockpitPubDevSearchService(
        httpClient: _AlwaysFailingHttpClient(),
        processManager: _FakeFetchProcessManager(
          body: '{"packages":[{"package":"collection"}]}',
        ),
        enableProcessFallback: true,
      );

      final result = await service.search(
        const CockpitPubDevSearchRequest(query: 'collection', maxResults: 1),
      );

      expect(result.results.single.packageName, 'collection');
    },
  );

  test('external fetch fallback kills timed-out helper processes', () async {
    final processManager = _HangingFetchProcessManager();
    final service = CockpitPubDevSearchService(
      httpClient: _AlwaysFailingHttpClient(),
      processManager: processManager,
      enableProcessFallback: true,
    );

    await expectLater(
      service.search(
        const CockpitPubDevSearchRequest(
          query: 'collection',
          timeout: Duration(milliseconds: 20),
        ),
      ),
      throwsA(
        isA<CockpitApplicationServiceException>().having(
          (error) => error.code,
          'code',
          'pubDevSearchFailed',
        ),
      ),
    );
    expect(
      processManager.processes.any(
        (process) => process.killSignals.contains(ProcessSignal.sigkill),
      ),
      isTrue,
    );
  });
}

final class _FakeHttpClient implements CockpitHttpClient {
  const _FakeHttpClient({
    required this.responses,
    this.failingUris = const <String>{},
  });

  final Map<String, String> responses;
  final Set<String> failingUris;

  @override
  Future<void> close() async {}

  @override
  Future<String> read(Uri uri) async {
    if (failingUris.contains(uri.toString())) {
      throw StateError('network failed');
    }
    return responses[uri.toString()]!;
  }

  @override
  Future<List<int>> readBytes(Uri uri) async => throw UnimplementedError();
}

final class _HangingHttpClient implements CockpitHttpClient {
  @override
  Future<void> close() async {}

  @override
  Future<String> read(Uri uri) => Completer<String>().future;

  @override
  Future<List<int>> readBytes(Uri uri) => Completer<List<int>>().future;
}

final class _AlwaysFailingHttpClient implements CockpitHttpClient {
  @override
  Future<void> close() async {}

  @override
  Future<String> read(Uri uri) async {
    throw const HandshakeException('terminated during handshake');
  }

  @override
  Future<List<int>> readBytes(Uri uri) async {
    throw const HandshakeException('terminated during handshake');
  }
}

final class _FakeFetchProcessManager implements CockpitProcessManager {
  const _FakeFetchProcessManager({required this.body});

  final String body;

  ProcessResult _resultFor(List<String> arguments) {
    if (arguments.length < 3 ||
        !arguments.first.startsWith('-') ||
        !arguments[2].contains('pub.dev')) {
      return ProcessResult(1, 1, '', 'bad fetch command');
    }
    if (arguments[2].contains('/score')) {
      return ProcessResult(
        1,
        0,
        '{"grantedPoints":140,"maxPoints":160,"likeCount":120,"popularityScore":0.98}',
        '',
      );
    }
    if (arguments[2].contains('/packages/collection')) {
      return ProcessResult(
        1,
        0,
        '{"name":"collection","latest":{"version":"1.19.0","pubspec":{"description":"Collections utilities."}}}',
        '',
      );
    }
    return ProcessResult(1, 0, body, '');
  }

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) async {
    return _resultFor(arguments);
  }

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) async {
    final result = _resultFor(arguments);
    return _CompletedFetchProcess(
      stdout: '${result.stdout}',
      stderr: '${result.stderr}',
      exitCode: result.exitCode,
    );
  }
}

final class _CompletedFetchProcess implements Process {
  _CompletedFetchProcess({
    required String stdout,
    required String stderr,
    required int exitCode,
  }) : _stdout = Stream<List<int>>.value(utf8.encode(stdout)),
       _stderr = Stream<List<int>>.value(utf8.encode(stderr)),
       _exitCode = Future<int>.value(exitCode);

  final Stream<List<int>> _stdout;
  final Stream<List<int>> _stderr;
  final Future<int> _exitCode;

  @override
  Future<int> get exitCode => _exitCode;

  @override
  int get pid => 1;

  @override
  IOSink get stdin => throw UnsupportedError('stdin is not used in tests');

  @override
  Stream<List<int>> get stderr => _stderr;

  @override
  Stream<List<int>> get stdout => _stdout;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}

final class _HangingFetchProcessManager implements CockpitProcessManager {
  final List<_HangingProcess> processes = <_HangingProcess>[];

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) {
    return Completer<ProcessResult>().future;
  }

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) async {
    final process = _HangingProcess();
    processes.add(process);
    return process;
  }
}

final class _HangingProcess implements Process {
  final StreamController<List<int>> _stdoutController =
      StreamController<List<int>>();
  final StreamController<List<int>> _stderrController =
      StreamController<List<int>>();
  final StreamController<List<int>> _stdinController =
      StreamController<List<int>>();
  final List<ProcessSignal> killSignals = <ProcessSignal>[];

  @override
  Future<int> get exitCode => Completer<int>().future;

  @override
  int get pid => 1;

  @override
  IOSink get stdin => IOSink(_stdinController.sink);

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killSignals.add(signal);
    if (!_stdoutController.isClosed) {
      unawaited(_stdoutController.close());
    }
    if (!_stderrController.isClosed) {
      unawaited(_stderrController.close());
    }
    if (!_stdinController.isClosed) {
      unawaited(_stdinController.close());
    }
    return true;
  }
}
