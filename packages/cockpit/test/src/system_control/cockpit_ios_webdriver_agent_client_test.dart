import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/system_control/cockpit_ios_webdriver_agent_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final baseUri = Uri.parse('http://127.0.0.1:8100');

  MockClient clientWithSession(
    Future<http.Response> Function(http.Request request) onSessionRequest,
  ) {
    return MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/status') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'sessionId': 'session-1',
            'value': <String, Object?>{'ready': true},
          }),
          200,
        );
      }
      return onSessionRequest(request);
    });
  }

  test('pressHome posts to the root homescreen endpoint', () async {
    final requests = <http.Request>[];
    final client = clientWithSession((request) async {
      requests.add(request);
      return http.Response(jsonEncode(<String, Object?>{'value': null}), 200);
    });

    final result = await CockpitIosWebDriverAgentClient(httpClient: client).run(
      CockpitIosWdaCommand(
        baseUri: baseUri,
        action: CockpitIosWdaAction.pressHome,
      ),
      timeout: const Duration(seconds: 2),
    );

    expect(result, 'pressHome');
    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/wda/homescreen');
  });

  test('tap posts W3C touch actions to the session', () async {
    final requests = <http.Request>[];
    final client = clientWithSession((request) async {
      requests.add(request);
      return http.Response(jsonEncode(<String, Object?>{'value': null}), 200);
    });

    await CockpitIosWebDriverAgentClient(httpClient: client).run(
      CockpitIosWdaCommand(
        baseUri: baseUri,
        action: CockpitIosWdaAction.tap,
        parameters: const <String, Object?>{'x': 120, 'y': 240},
      ),
      timeout: const Duration(seconds: 2),
    );

    expect(requests.single.url.path, '/session/session-1/actions');
    final payload = jsonDecode(requests.single.body) as Map<String, Object?>;
    final actions = payload['actions']! as List<Object?>;
    final pointer = actions.single! as Map<String, Object?>;
    expect(pointer['type'], 'pointer');
    expect(
      (pointer['parameters']! as Map<Object?, Object?>)['pointerType'],
      'touch',
    );
    final steps = (pointer['actions']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    expect(steps.first['x'], 120);
    expect(steps.first['y'], 240);
  });

  test('creates a session when status has no session id', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'GET' && request.url.path == '/status') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'value': <String, Object?>{'ready': true},
          }),
          200,
        );
      }
      if (request.method == 'POST' && request.url.path == '/session') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'value': <String, Object?>{'sessionId': 'created-session'},
          }),
          200,
        );
      }
      return http.Response(jsonEncode(<String, Object?>{'value': null}), 200);
    });

    await CockpitIosWebDriverAgentClient(httpClient: client).run(
      CockpitIosWdaCommand(
        baseUri: baseUri,
        action: CockpitIosWdaAction.dismissKeyboard,
      ),
      timeout: const Duration(seconds: 2),
    );

    expect(
      requests.map((request) => request.url.path),
      containsAll(<String>[
        '/status',
        '/session',
        '/session/created-session/wda/keyboard/dismiss',
      ]),
    );
  });

  test('dismissSystemDialog dismiss posts alert dismiss', () async {
    final requests = <http.Request>[];
    final client = clientWithSession((request) async {
      requests.add(request);
      return http.Response(jsonEncode(<String, Object?>{'value': null}), 200);
    });

    await CockpitIosWebDriverAgentClient(httpClient: client).run(
      CockpitIosWdaCommand(
        baseUri: baseUri,
        action: CockpitIosWdaAction.dismissSystemDialog,
        parameters: const <String, Object?>{'decision': 'dismiss'},
      ),
      timeout: const Duration(seconds: 2),
    );

    expect(requests.single.url.path, '/session/session-1/alert/dismiss');
  });

  test('failures surface the W3C error and message fields', () async {
    final client = clientWithSession((request) async {
      return http.Response(
        jsonEncode(<String, Object?>{
          'value': <String, Object?>{
            'error': 'no such alert',
            'message':
                'An attempt was made to operate on a modal dialog '
                'when one was not open',
          },
        }),
        404,
      );
    });

    await expectLater(
      CockpitIosWebDriverAgentClient(httpClient: client).run(
        CockpitIosWdaCommand(
          baseUri: baseUri,
          action: CockpitIosWdaAction.dismissSystemDialog,
        ),
        timeout: const Duration(seconds: 2),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          allOf(contains('no such alert'), contains('modal dialog')),
        ),
      ),
    );
  });

  test(
    'resolveBlockers relaunches the app through the injected runner',
    () async {
      final commands = <List<String>>[];
      final client = clientWithSession((request) async {
        return http.Response(jsonEncode(<String, Object?>{'value': null}), 200);
      });

      final result =
          await CockpitIosWebDriverAgentClient(
            httpClient: client,
            processRunner: (executable, arguments) async {
              commands.add(<String>[executable, ...arguments]);
              return ProcessResult(0, 0, '', '');
            },
          ).run(
            CockpitIosWdaCommand(
              baseUri: baseUri,
              action: CockpitIosWdaAction.resolveBlockers,
              parameters: const <String, Object?>{
                'appId': 'dev.cockpit.example',
                'deviceId': '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
              },
            ),
            timeout: const Duration(seconds: 2),
          );

      expect(result, contains('resolveBlockers'));
      expect(commands.single, <String>[
        'xcrun',
        'simctl',
        'launch',
        '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
        'dev.cockpit.example',
      ]);
    },
  );
}
