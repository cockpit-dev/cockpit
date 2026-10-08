import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/application/cockpit_application_service_exception.dart';
import 'package:cockpit/src/application/cockpit_app_handle.dart';
import 'package:cockpit/src/application/cockpit_interaction_recorder_app_service.dart';
import 'package:cockpit/src/session/cockpit_remote_session_handle.dart';
import 'package:test/test.dart';

/// Wire-level coverage for the worker-facing recorder app service: every
/// method dials one loopback fake app through a [CockpitAppHandle] and must
/// return the endpoint's raw JSON, while app error envelopes surface with the
/// app's error code.
void main() {
  test('recorder app service returns each endpoint payload', () async {
    final app = await _FakeRecorderApp.start();
    addTearDown(app.close);
    final service = CockpitInteractionRecorderAppService();
    final handle = _handle(app.endpoint);

    final started = await service.start(handle, name: 'checkout flow');
    expect(started['sessionId'], 'r1');
    expect(started['phase'], 'recording');
    expect(app.startBodies.single, <String, Object?>{'name': 'checkout flow'});
    expect(app.authTokens, const <String>['app-token-1']);

    expect((await service.pause(handle))['phase'], 'paused');
    expect((await service.resume(handle))['phase'], 'recording');

    final stopped = await service.stop(handle);
    expect((stopped['session']! as Map<String, Object?>)['phase'], 'stopped');
    expect(stopped['steps'], hasLength(_FakeRecorderApp.stepCount));

    expect((await service.session(handle))['sessionId'], 'r1');
    app.idle = true;
    expect(await service.session(handle), const <String, Object?>{
      'phase': 'idle',
    });

    final page = await service.steps(handle, after: 1);
    expect(page['total'], _FakeRecorderApp.stepCount);
    expect(
      (page['steps']! as List<Object?>).map(
        (step) => (step as Map<String, Object?>)['stepId'],
      ),
      const <String>['s2'],
    );

    final exported = await service.export(handle);
    expect(exported['caseYaml'], _FakeRecorderApp.caseYaml);
    expect(
      (exported['caseDocument']! as Map<String, Object?>)['id'],
      'recorded-r1',
    );
  });

  test('recorder app service preserves app error envelopes', () async {
    final app = await _FakeRecorderApp.start()
      ..failPause = true;
    addTearDown(app.close);
    final service = CockpitInteractionRecorderAppService();

    await expectLater(
      service.pause(_handle(app.endpoint)),
      throwsA(
        isA<CockpitApplicationServiceException>()
            .having((error) => error.code, 'code', 'serverError')
            .having(
              (error) => error.message,
              'message',
              contains('Cannot pause while idle.'),
            ),
      ),
    );
  });
}

CockpitAppHandle _handle(Uri endpoint) => CockpitAppHandle.fromRemoteSession(
  CockpitRemoteSessionHandle(
    platform: 'android',
    deviceId: 'emulator-5554',
    projectDir: '/workspace/demo',
    target: 'android',
    appId: 'app-1',
    platformAppIdKnown: false,
    host: endpoint.host,
    hostPort: endpoint.port,
    devicePort: endpoint.port,
    baseUrl: endpoint.toString(),
    authToken: 'app-token-1',
    launchedAt: DateTime.utc(2026, 10, 7, 9),
  ),
);

final class _FakeRecorderApp {
  _FakeRecorderApp._(this._server);

  static const int stepCount = 2;
  static const String caseYaml =
      'schemaVersion: cockpit.test/v2\nid: recorded-r1\n';

  final HttpServer _server;
  final List<Map<String, Object?>> startBodies = <Map<String, Object?>>[];
  final List<String> authTokens = <String>[];

  bool idle = false;
  bool failPause = false;

  Uri get endpoint => Uri.parse('http://127.0.0.1:${_server.port}');

  static Future<_FakeRecorderApp> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final app = _FakeRecorderApp._(server);
    server.listen(app._handle);
    return app;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final token = request.headers.value('x-cockpit-token');
    if (token != null) {
      authTokens.add(token);
    }
    request.response.headers.contentType = ContentType.json;
    switch ((request.method, request.uri.path)) {
      case ('POST', '/recorder/start'):
        final body = jsonDecode(await utf8.decoder.bind(request).join());
        startBodies.add(
          Map<String, Object?>.from(body as Map<Object?, Object?>),
        );
        request.response.write(jsonEncode(_session('recording')));
      case ('POST', '/recorder/pause'):
        if (failPause || idle) {
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.write(
            jsonEncode(const <String, Object?>{
              'error': 'serverError',
              'message': 'Bad state: Cannot pause while idle.',
            }),
          );
        } else {
          request.response.write(
            jsonEncode(<String, Object?>{
              ..._session('paused'),
              'pausedAt': '2026-10-07T09:01:00.000Z',
            }),
          );
        }
      case ('POST', '/recorder/resume'):
        request.response.write(jsonEncode(_session('recording')));
      case ('POST', '/recorder/stop'):
        request.response.write(
          jsonEncode(<String, Object?>{
            'session': _session('stopped'),
            'steps': _steps,
          }),
        );
      case ('GET', '/recorder/session'):
        request.response.write(
          jsonEncode(
            idle
                ? const <String, Object?>{'phase': 'idle'}
                : _session('recording'),
          ),
        );
      case ('GET', '/recorder/steps'):
        final after = int.parse(request.uri.queryParameters['after'] ?? '0');
        request.response.write(
          jsonEncode(<String, Object?>{
            'steps': _steps.skip(after).toList(),
            'total': stepCount,
          }),
        );
      case ('GET', '/recorder/export'):
        request.response.write(
          jsonEncode(<String, Object?>{
            'session': _session('recording'),
            'steps': _steps,
            'caseDocument': <String, Object?>{
              'id': 'recorded-r1',
              'schemaVersion': 'cockpit.test/v2',
            },
            'caseYaml': caseYaml,
          }),
        );
      default:
        request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  }

  static Map<String, Object?> _session(String phase) => <String, Object?>{
    'sessionId': 'r1',
    'phase': phase,
    'startedAt': '2026-10-07T09:00:00.000Z',
    'stepCount': stepCount,
    'unresolvedCount': 0,
  };

  static const List<Map<String, Object?>> _steps = <Map<String, Object?>>[
    <String, Object?>{
      'stepId': 's1',
      'kind': 'tap',
      'locatorCandidates': <Object?>[
        <String, Object?>{'kind': 'key', 'selector': '@save', 'score': 4},
      ],
      'phase': 'recording',
      'recordedAt': '2026-10-07T09:00:00.000Z',
    },
    <String, Object?>{
      'stepId': 's2',
      'kind': 'tap',
      'locatorCandidates': <Object?>[
        <String, Object?>{'kind': 'key', 'selector': '@submit', 'score': 4},
      ],
      'phase': 'recording',
      'recordedAt': '2026-10-07T09:00:30.000Z',
    },
  ];
}
