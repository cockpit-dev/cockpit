import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../infrastructure/cockpit_process_manager.dart';
import 'cockpit_system_control_action.dart';
import 'cockpit_system_control_adapter.dart';

const String cockpitIosWdaCommandExecutable =
    '__flutter_cockpit_ios_webdriver_agent';
const String cockpitIosUiStabilitySnapshotMetadataKey =
    'cockpit.ios.uiStabilitySnapshot';

typedef CockpitIosWdaHttpClientFactory = http.Client Function();
typedef CockpitIosWdaEndpointProbe =
    Future<bool> Function(Uri baseUri, {required Duration timeout});
typedef CockpitIosWdaProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

Future<bool> cockpitProbeIosWdaEndpoint(
  Uri baseUri, {
  required Duration timeout,
}) async {
  try {
    await CockpitIosWebDriverAgentClient().ping(baseUri, timeout: timeout);
    return true;
  } on Object {
    return false;
  }
}

final class CockpitIosWebDriverAgentClient {
  CockpitIosWebDriverAgentClient({
    http.Client? httpClient,
    CockpitIosWdaHttpClientFactory? httpClientFactory,
    CockpitIosWdaProcessRunner? processRunner,
  }) : _httpClient = httpClient,
       _httpClientFactory = httpClientFactory ?? http.Client.new,
       _processRunner = processRunner ?? cockpitRunIsolatedProcess;

  final http.Client? _httpClient;
  final CockpitIosWdaHttpClientFactory _httpClientFactory;
  final CockpitIosWdaProcessRunner _processRunner;

  Future<void> ping(Uri baseUri, {required Duration timeout}) {
    return _withClient((client) async {
      final response = await client
          .get(_resolve(baseUri, '/status'))
          .timeout(timeout);
      _ensureSuccess(response, 'read WebDriverAgent status');
      _decodeObject(response.body);
    });
  }

  Future<List<int>> captureScreenshot(
    Uri baseUri, {
    required Duration timeout,
  }) async {
    final session = await resolveSession(baseUri, timeout: timeout);
    return _withClient((client) async {
      final response = await _getSession(
        client,
        session,
        'screenshot',
        timeout: timeout,
      );
      final value = _decodeObject(response.body)['value'];
      if (value is! String || value.trim().isEmpty) {
        throw StateError(
          'WebDriverAgent screenshot response did not include PNG data.',
        );
      }
      return base64Decode(value);
    });
  }

  Future<CockpitIosWdaSession> resolveSession(
    Uri baseUri, {
    required Duration timeout,
  }) async {
    return _withClient((client) async {
      final response = await client
          .get(_resolve(baseUri, '/status'))
          .timeout(timeout);
      _ensureSuccess(response, 'read WebDriverAgent status');
      final decoded = _decodeObject(response.body);
      final resolvedSessionId =
          _readNestedString(decoded, const <String>['sessionId']) ??
          _readNestedString(decoded, const <String>['value', 'sessionId']);
      if (resolvedSessionId == null || resolvedSessionId.trim().isEmpty) {
        return _createSession(client, baseUri, timeout: timeout);
      }
      return CockpitIosWdaSession(
        baseUri: baseUri,
        sessionId: resolvedSessionId.trim(),
      );
    });
  }

  Future<CockpitIosWdaSession> _createSession(
    http.Client client,
    Uri baseUri, {
    required Duration timeout,
  }) async {
    final response = await client
        .post(
          _resolve(baseUri, '/session'),
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
          body: jsonEncode(<String, Object?>{
            'capabilities': <String, Object?>{
              'alwaysMatch': <String, Object?>{},
            },
            'desiredCapabilities': <String, Object?>{},
          }),
        )
        .timeout(timeout);
    _ensureSuccess(response, 'create WebDriverAgent session');
    final decoded = _decodeObject(response.body);
    final resolvedSessionId =
        _readNestedString(decoded, const <String>['sessionId']) ??
        _readNestedString(decoded, const <String>['value', 'sessionId']);
    if (resolvedSessionId == null || resolvedSessionId.trim().isEmpty) {
      throw StateError(
        'WebDriverAgent session creation did not return a session id.',
      );
    }
    return CockpitIosWdaSession(
      baseUri: baseUri,
      sessionId: resolvedSessionId.trim(),
    );
  }

  static CockpitIosWdaCommand commandFromArguments(List<String> arguments) {
    if (arguments.length != 1) {
      throw ArgumentError.value(
        arguments,
        'arguments',
        'WebDriverAgent internal command requires one JSON argument.',
      );
    }
    final decoded = jsonDecode(arguments.single);
    if (decoded is! Map<Object?, Object?>) {
      throw ArgumentError.value(
        arguments.single,
        'arguments',
        'WebDriverAgent internal command JSON must be an object.',
      );
    }
    final json = decoded.cast<String, Object?>();
    return CockpitIosWdaCommand(
      baseUri: Uri.parse(json['baseUrl']! as String),
      action: CockpitIosWdaAction.values.byName(json['action']! as String),
      stabilitySnapshot: json['stabilitySnapshot'] == true,
      parameters:
          (json['parameters'] as Map<Object?, Object?>?)
              ?.cast<String, Object?>() ??
          const <String, Object?>{},
    );
  }

  static List<String> commandToArguments(CockpitIosWdaCommand command) {
    return <String>[
      jsonEncode(<String, Object?>{
        'baseUrl': command.baseUri.toString(),
        'action': command.action.name,
        if (command.stabilitySnapshot) 'stabilitySnapshot': true,
        if (command.parameters.isNotEmpty) 'parameters': command.parameters,
      }),
    ];
  }

  static CockpitResolvedSystemControlCommand resolvedCommand(
    CockpitIosWdaCommand command,
  ) {
    return CockpitResolvedSystemControlCommand(
      cockpitIosWdaCommandExecutable,
      commandToArguments(command),
    );
  }

  Future<String> run(
    CockpitIosWdaCommand command, {
    required Duration timeout,
  }) async {
    final session = await resolveSession(command.baseUri, timeout: timeout);
    return _withClient((client) async {
      switch (command.action) {
        case CockpitIosWdaAction.tap:
          final x = _requiredInt(command.parameters, 'x');
          final y = _requiredInt(command.parameters, 'y');
          await _postSession(client, session, 'wda/tap', <String, Object?>{
            'x': x,
            'y': y,
          }, timeout: timeout);
          return 'tap x=$x y=$y';
        case CockpitIosWdaAction.longPress:
          final x = _requiredInt(command.parameters, 'x');
          final y = _requiredInt(command.parameters, 'y');
          final durationMs =
              _optionalPositiveInt(command.parameters, 'durationMs') ?? 800;
          await _postSession(client, session, 'actions', <String, Object?>{
            'actions': <Object?>[
              <String, Object?>{
                'type': 'pointer',
                'id': 'cockpit-finger',
                'parameters': <String, Object?>{'pointerType': 'touch'},
                'actions': <Object?>[
                  <String, Object?>{
                    'type': 'pointerMove',
                    'duration': 0,
                    'origin': 'viewport',
                    'x': x,
                    'y': y,
                  },
                  <String, Object?>{'type': 'pointerDown', 'button': 0},
                  <String, Object?>{'type': 'pause', 'duration': durationMs},
                  <String, Object?>{'type': 'pointerUp', 'button': 0},
                ],
              },
            ],
          }, timeout: timeout);
          return 'longPress x=$x y=$y durationMs=$durationMs';
        case CockpitIosWdaAction.drag:
          final startX = _requiredInt(command.parameters, 'startX');
          final startY = _requiredInt(command.parameters, 'startY');
          final endX = _requiredInt(command.parameters, 'endX');
          final endY = _requiredInt(command.parameters, 'endY');
          final durationMs =
              _optionalPositiveInt(command.parameters, 'durationMs') ?? 300;
          await _postSession(client, session, 'actions', <String, Object?>{
            'actions': <Object?>[
              <String, Object?>{
                'type': 'pointer',
                'id': 'cockpit-finger',
                'parameters': <String, Object?>{'pointerType': 'touch'},
                'actions': <Object?>[
                  <String, Object?>{
                    'type': 'pointerMove',
                    'duration': 0,
                    'origin': 'viewport',
                    'x': startX,
                    'y': startY,
                  },
                  <String, Object?>{'type': 'pointerDown', 'button': 0},
                  <String, Object?>{
                    'type': 'pointerMove',
                    'duration': durationMs,
                    'origin': 'viewport',
                    'x': endX,
                    'y': endY,
                  },
                  <String, Object?>{'type': 'pointerUp', 'button': 0},
                ],
              },
            ],
          }, timeout: timeout);
          return 'drag start=($startX,$startY) end=($endX,$endY) durationMs=$durationMs';
        case CockpitIosWdaAction.typeText:
          final text = _requiredString(command.parameters, 'text');
          await _postSession(client, session, 'actions', <String, Object?>{
            'actions': <Object?>[
              <String, Object?>{
                'type': 'key',
                'id': 'cockpit-keyboard',
                'actions': _keyboardActions(text),
              },
            ],
          }, timeout: timeout);
          return 'typeText length=${text.length}';
        case CockpitIosWdaAction.pressKey:
          final key = _requiredString(command.parameters, 'key');
          final mapped = _mapKey(key);
          final repeat =
              _optionalPositiveInt(command.parameters, 'repeat') ?? 1;
          if (repeat > 500) {
            throw StateError('WebDriverAgent pressKey repeat exceeds 500.');
          }
          await _postSession(client, session, 'actions', <String, Object?>{
            'actions': <Object?>[
              <String, Object?>{
                'type': 'key',
                'id': 'cockpit-keyboard',
                'actions': <Object?>[
                  for (var index = 0; index < repeat; index += 1) ...<Object?>[
                    <String, Object?>{'type': 'keyDown', 'value': mapped},
                    <String, Object?>{'type': 'keyUp', 'value': mapped},
                  ],
                ],
              },
            ],
          }, timeout: timeout);
          return 'pressKey key=$key repeat=$repeat';
        case CockpitIosWdaAction.dismissSystemDialog:
          final mode =
              _optionalString(command.parameters, 'mode') ??
              _optionalString(command.parameters, 'decision') ??
              'accept';
          final endpoint = switch (mode) {
            'dismiss' || 'cancel' || 'deny' => 'alert/dismiss',
            _ => 'alert/accept',
          };
          await _postSession(
            client,
            session,
            endpoint,
            const <String, Object?>{},
            timeout: timeout,
          );
          return 'dismissSystemDialog mode=$mode';
        case CockpitIosWdaAction.dismissKeyboard:
          await _postSession(
            client,
            session,
            'wda/keyboard/dismiss',
            const <String, Object?>{},
            timeout: timeout,
          );
          return 'dismissKeyboard';
        case CockpitIosWdaAction.pressButton:
          final name = _requiredString(command.parameters, 'name');
          final durationMs = _optionalPositiveInt(
            command.parameters,
            'durationMs',
          );
          await _postSession(
            client,
            session,
            'wda/pressButton',
            <String, Object?>{
              'name': _mapButtonName(name),
              if (durationMs != null) 'duration': durationMs / 1000.0,
            },
            timeout: timeout,
          );
          return 'pressButton name=$name';
        case CockpitIosWdaAction.pressHome:
          // WebDriverAgent registers /wda/homescreen as a root (session-less)
          // endpoint; the session-scoped variant 404s on modern WDA builds.
          await _postRoot(
            client,
            session.baseUri,
            'wda/homescreen',
            const <String, Object?>{},
            timeout: timeout,
          );
          return 'pressHome';
        case CockpitIosWdaAction.activateApp:
          final bundleId = _requiredString(command.parameters, 'bundleId');
          await _postSession(
            client,
            session,
            'wda/apps/activate',
            <String, Object?>{'bundleId': bundleId},
            timeout: timeout,
          );
          return 'activateApp bundleId=$bundleId';
        case CockpitIosWdaAction.terminateApp:
          final bundleId = _requiredString(command.parameters, 'bundleId');
          await _postSession(
            client,
            session,
            'wda/apps/terminate',
            <String, Object?>{'bundleId': bundleId},
            timeout: timeout,
          );
          return 'terminateApp bundleId=$bundleId';
        case CockpitIosWdaAction.setOrientation:
          final orientation = _requiredString(
            command.parameters,
            'orientation',
          );
          await _postSession(client, session, 'orientation', <String, Object?>{
            'orientation': _mapOrientation(orientation),
          }, timeout: timeout);
          return 'setOrientation orientation=$orientation';
        case CockpitIosWdaAction.readUiTree:
          final response = await _getSession(
            client,
            session,
            'source',
            queryParameters: command.stabilitySnapshot
                ? const <String, String>{
                    'excluded_attributes': 'visible,accessible',
                  }
                : const <String, String>{},
            timeout: timeout,
          );
          final decoded = _decodeObject(response.body);
          final value = decoded['value'];
          return value is String ? value : jsonEncode(value);
        case CockpitIosWdaAction.readDeviceInfo:
          final response = await _getSession(
            client,
            session,
            'wda/device/info',
            timeout: timeout,
          );
          return response.body;
        case CockpitIosWdaAction.readFocusState:
          final keyboardResponse = await _getSessionOrNull(
            client,
            session,
            'wda/keyboard/isShown',
            timeout: timeout,
          );
          final sourceResponse = await _getSessionOrNull(
            client,
            session,
            'source',
            timeout: timeout,
          );
          return jsonEncode(<String, Object?>{
            'keyboardVisible': _readWdaBooleanValue(keyboardResponse?.body),
            if (sourceResponse != null)
              'sourcePreview': _trimForDiagnostics(sourceResponse.body),
          });
        case CockpitIosWdaAction.expandNotifications:
          final size = await _readWindowSize(client, session, timeout: timeout);
          await _dragPoint(
            client,
            session,
            start: _WdaPoint((size.width * 0.5).round(), 2),
            end: _WdaPoint(
              (size.width * 0.5).round(),
              (size.height * 0.62).round(),
            ),
            durationMs: 450,
            id: 'cockpit-notification-center-drag',
            timeout: timeout,
          );
          return 'expandNotifications width=${size.width} height=${size.height}';
        case CockpitIosWdaAction.expandQuickSettings:
          final size = await _readWindowSize(client, session, timeout: timeout);
          await _dragPoint(
            client,
            session,
            start: _WdaPoint((size.width * 0.92).round(), 2),
            end: _WdaPoint(
              (size.width * 0.92).round(),
              (size.height * 0.62).round(),
            ),
            durationMs: 450,
            id: 'cockpit-control-center-drag',
            timeout: timeout,
          );
          return 'expandQuickSettings width=${size.width} height=${size.height}';
        case CockpitIosWdaAction.collapseSystemUi:
          final size = await _readWindowSize(client, session, timeout: timeout);
          await _dragPoint(
            client,
            session,
            start: _WdaPoint(
              (size.width * 0.5).round(),
              (size.height * 0.90).round(),
            ),
            end: _WdaPoint(
              (size.width * 0.5).round(),
              (size.height * 0.18).round(),
            ),
            durationMs: 350,
            id: 'cockpit-system-ui-collapse-drag',
            timeout: timeout,
          );
          return 'collapseSystemUi width=${size.width} height=${size.height}';
        case CockpitIosWdaAction.tapNotification:
          final matchText = _notificationMatchText(command.parameters);
          await _openNotificationCenter(client, session, timeout: timeout);
          final sourceResponse = await _getSession(
            client,
            session,
            'source',
            timeout: timeout,
          );
          final source = _extractWdaSourceValue(sourceResponse.body);
          final point = _findXmlNodeCenterForText(source, matchText);
          if (point == null) {
            throw StateError(
              'WebDriverAgent source did not contain notification text "$matchText".',
            );
          }
          await _tapPoint(client, session, point, timeout: timeout);
          return 'tapNotification text=$matchText x=${point.x} y=${point.y}';
        case CockpitIosWdaAction.resolveBlockers:
          final decision =
              _optionalString(command.parameters, 'decision') ?? 'dismiss';
          final dismissKeyboard =
              _optionalBool(command.parameters, 'dismissKeyboard') ?? false;
          await _dismissAlertIfPresent(
            client,
            session,
            decision: decision,
            timeout: timeout,
          );
          if (dismissKeyboard) {
            await _postSessionOrNull(
              client,
              session,
              'wda/keyboard/dismiss',
              const <String, Object?>{},
              timeout: timeout,
            );
          }
          final appId = _requiredString(command.parameters, 'appId');
          final deviceId =
              _optionalString(command.parameters, 'deviceId') ?? 'booted';
          if (_looksLikeIosSimulatorDeviceId(deviceId)) {
            final launchOutput = await _processRunner('xcrun', <String>[
              'simctl',
              'launch',
              deviceId,
              appId,
            ]).timeout(timeout);
            if (launchOutput.exitCode != 0) {
              throw StateError(
                'Failed to relaunch iOS simulator app $appId: ${launchOutput.stderr}',
              );
            }
          } else {
            await _postSession(
              client,
              session,
              'wda/apps/activate',
              <String, Object?>{'bundleId': appId},
              timeout: timeout,
            );
          }
          return 'resolveBlockers appId=$appId decision=$decision';
      }
    });
  }

  Future<T> _withClient<T>(Future<T> Function(http.Client client) callback) {
    final ownedClient = _httpClient == null ? _httpClientFactory() : null;
    final client = _httpClient ?? ownedClient!;
    return callback(client).whenComplete(() => ownedClient?.close());
  }

  Future<http.Response> _postSession(
    http.Client client,
    CockpitIosWdaSession session,
    String path,
    Map<String, Object?> payload, {
    required Duration timeout,
  }) async {
    final response = await client
        .post(
          _resolve(
            session.baseUri,
            '/session/${Uri.encodeComponent(session.sessionId)}/$path',
          ),
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
          body: jsonEncode(payload),
        )
        .timeout(timeout);
    _ensureSuccess(response, 'run WebDriverAgent $path');
    return response;
  }

  Future<http.Response> _postRoot(
    http.Client client,
    Uri baseUri,
    String path,
    Map<String, Object?> payload, {
    required Duration timeout,
  }) async {
    final response = await client
        .post(
          _resolve(baseUri, '/$path'),
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
          body: jsonEncode(payload),
        )
        .timeout(timeout);
    _ensureSuccess(response, 'run WebDriverAgent $path');
    return response;
  }

  Future<http.Response> _getSession(
    http.Client client,
    CockpitIosWdaSession session,
    String path, {
    Map<String, String> queryParameters = const <String, String>{},
    required Duration timeout,
  }) async {
    final response = await client
        .get(
          _resolve(
            session.baseUri,
            '/session/${Uri.encodeComponent(session.sessionId)}/$path',
            queryParameters: queryParameters,
          ),
        )
        .timeout(timeout);
    _ensureSuccess(response, 'run WebDriverAgent $path');
    return response;
  }

  Future<http.Response?> _getSessionOrNull(
    http.Client client,
    CockpitIosWdaSession session,
    String path, {
    required Duration timeout,
  }) async {
    try {
      return await _getSession(client, session, path, timeout: timeout);
    } on Object {
      return null;
    }
  }

  Future<http.Response?> _postSessionOrNull(
    http.Client client,
    CockpitIosWdaSession session,
    String path,
    Map<String, Object?> payload, {
    required Duration timeout,
  }) async {
    try {
      return await _postSession(
        client,
        session,
        path,
        payload,
        timeout: timeout,
      );
    } on Object {
      return null;
    }
  }

  Uri _resolve(
    Uri baseUri,
    String path, {
    Map<String, String> queryParameters = const <String, String>{},
  }) {
    final basePath = baseUri.path.endsWith('/')
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    return baseUri.replace(
      path: '$basePath$path',
      queryParameters: queryParameters,
      fragment: '',
    );
  }

  Map<String, Object?> _decodeObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<Object?, Object?>) {
      return decoded.cast<String, Object?>();
    }
    throw StateError('WebDriverAgent response was not a JSON object.');
  }

  void _ensureSuccess(http.Response response, String operation) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    throw StateError(
      'Failed to $operation: HTTP ${response.statusCode} '
      '${_describeWdaError(response.body)}',
    );
  }

  String _describeWdaError(String body) {
    try {
      final decoded = _decodeObject(body);
      final value = decoded['value'];
      if (value is Map<Object?, Object?>) {
        final error = value['error'];
        final message = value['message'];
        final parts = <String>[
          if (error is String && error.trim().isNotEmpty) error.trim(),
          if (message is String && message.trim().isNotEmpty) message.trim(),
        ];
        if (parts.isNotEmpty) {
          return parts.join(': ');
        }
      }
    } on Object {
      // Fall through to the raw body preview.
    }
    return _trimForDiagnostics(body);
  }

  String? _readNestedString(Map<String, Object?> json, List<String> path) {
    Object? current = json;
    for (final segment in path) {
      if (current is! Map<Object?, Object?>) {
        return null;
      }
      current = current[segment];
    }
    return current is String ? current : null;
  }

  int _requiredInt(Map<String, Object?> parameters, String key) {
    final value = cockpitReadSystemControlIntParameter(parameters, key);
    if (!value.isValid) {
      throw StateError('WebDriverAgent command requires integer $key.');
    }
    return value.value!;
  }

  int? _optionalPositiveInt(Map<String, Object?> parameters, String key) {
    final value = cockpitReadSystemControlIntParameter(
      parameters,
      key,
      minimum: 1,
    );
    if (value.isInvalid) {
      throw StateError(
        'WebDriverAgent command requires positive integer $key.',
      );
    }
    return value.value;
  }

  String _requiredString(Map<String, Object?> parameters, String key) {
    final value = cockpitReadSystemControlStringParameter(parameters, key);
    if (!value.isValid) {
      throw StateError('WebDriverAgent command requires string $key.');
    }
    return value.value!;
  }

  String? _optionalString(Map<String, Object?> parameters, String key) {
    final value = cockpitReadSystemControlStringParameter(parameters, key);
    if (value.isInvalid) {
      throw StateError('WebDriverAgent command requires string $key.');
    }
    return value.value;
  }

  bool? _optionalBool(Map<String, Object?> parameters, String key) {
    final value = cockpitReadSystemControlBoolParameter(parameters, key);
    if (value.isInvalid) {
      throw StateError('WebDriverAgent command requires boolean $key.');
    }
    return value.value;
  }

  String _notificationMatchText(Map<String, Object?> parameters) {
    final text = _optionalString(parameters, 'text');
    final title = _optionalString(parameters, 'title');
    final body = _optionalString(parameters, 'body');
    final tag = _optionalString(parameters, 'tag');
    final value = text ?? title ?? body ?? tag;
    if (value == null || value.trim().isEmpty) {
      throw StateError(
        'WebDriverAgent tapNotification requires text, title, body, or tag.',
      );
    }
    return value;
  }

  // Notification Center, Control Center, and collapse gestures use
  // window-size ratios because WDA has no dedicated endpoints for them;
  // unusual simulator geometries may need coordinate fallbacks.
  Future<void> _openNotificationCenter(
    http.Client client,
    CockpitIosWdaSession session, {
    required Duration timeout,
  }) async {
    final size = await _readWindowSize(client, session, timeout: timeout);
    await _dragPoint(
      client,
      session,
      start: _WdaPoint((size.width * 0.5).round(), 2),
      end: _WdaPoint((size.width * 0.5).round(), (size.height * 0.62).round()),
      durationMs: 450,
      id: 'cockpit-notification-drag',
      timeout: timeout,
    );
  }

  Future<void> _dragPoint(
    http.Client client,
    CockpitIosWdaSession session, {
    required _WdaPoint start,
    required _WdaPoint end,
    required int durationMs,
    required String id,
    required Duration timeout,
  }) async {
    await _postSession(client, session, 'actions', <String, Object?>{
      'actions': <Object?>[
        <String, Object?>{
          'type': 'pointer',
          'id': id,
          'parameters': <String, Object?>{'pointerType': 'touch'},
          'actions': <Object?>[
            <String, Object?>{
              'type': 'pointerMove',
              'duration': 0,
              'origin': 'viewport',
              'x': start.x,
              'y': start.y,
            },
            <String, Object?>{'type': 'pointerDown', 'button': 0},
            <String, Object?>{
              'type': 'pointerMove',
              'duration': durationMs,
              'origin': 'viewport',
              'x': end.x,
              'y': end.y,
            },
            <String, Object?>{'type': 'pointerUp', 'button': 0},
          ],
        },
      ],
    }, timeout: timeout);
  }

  Future<void> _tapPoint(
    http.Client client,
    CockpitIosWdaSession session,
    _WdaPoint point, {
    required Duration timeout,
  }) async {
    await _postSession(client, session, 'wda/tap', <String, Object?>{
      'x': point.x,
      'y': point.y,
    }, timeout: timeout);
  }

  Future<void> _dismissAlertIfPresent(
    http.Client client,
    CockpitIosWdaSession session, {
    required String decision,
    required Duration timeout,
  }) async {
    final endpoint = switch (decision) {
      'dismiss' || 'cancel' || 'deny' => 'alert/dismiss',
      _ => 'alert/accept',
    };
    await _postSessionOrNull(
      client,
      session,
      endpoint,
      const <String, Object?>{},
      timeout: timeout,
    );
  }

  bool? _readWdaBooleanValue(String? body) {
    if (body == null || body.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = _decodeObject(body);
      final value = decoded['value'];
      return value is bool ? value : null;
    } on Object {
      return null;
    }
  }

  String _extractWdaSourceValue(String body) {
    final decoded = _decodeObject(body);
    final value = decoded['value'];
    return value is String ? value : jsonEncode(value);
  }

  Future<_WdaSize> _readWindowSize(
    http.Client client,
    CockpitIosWdaSession session, {
    required Duration timeout,
  }) async {
    final response = await _getSession(
      client,
      session,
      'window/size',
      timeout: timeout,
    );
    final decoded = _decodeObject(response.body);
    final value = decoded['value'];
    if (value is Map<Object?, Object?>) {
      final width = _readNumber(value['width'])?.round();
      final height = _readNumber(value['height'])?.round();
      if (width != null && height != null && width > 0 && height > 0) {
        return _WdaSize(width, height);
      }
    }
    throw StateError(
      'WebDriverAgent window size response did not include positive width and height.',
    );
  }

  num? _readNumber(Object? value) {
    if (value is num) {
      return value;
    }
    if (value is String) {
      return num.tryParse(value);
    }
    return null;
  }

  _WdaPoint? _findXmlNodeCenterForText(String source, String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return null;
    }
    for (final match in RegExp(r'<[^>]+>').allMatches(source)) {
      final node = match.group(0)!;
      if (!node.contains(normalized)) {
        continue;
      }
      final x = _readDoubleAttribute(node, 'x');
      final y = _readDoubleAttribute(node, 'y');
      final width = _readDoubleAttribute(node, 'width');
      final height = _readDoubleAttribute(node, 'height');
      if (x == null || y == null || width == null || height == null) {
        continue;
      }
      return _WdaPoint((x + width / 2).round(), (y + height / 2).round());
    }
    return null;
  }

  double? _readDoubleAttribute(String node, String name) {
    final match = RegExp('$name="([^"]+)"').firstMatch(node);
    if (match == null) {
      return null;
    }
    return double.tryParse(match.group(1)!);
  }

  String _trimForDiagnostics(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 1000) {
      return normalized;
    }
    return '${normalized.substring(0, 1000)}...';
  }

  List<Object?> _keyboardActions(String text) {
    return text.runes
        .map(String.fromCharCode)
        .expand(
          (character) => <Object?>[
            <String, Object?>{'type': 'keyDown', 'value': character},
            <String, Object?>{'type': 'keyUp', 'value': character},
          ],
        )
        .toList(growable: false);
  }

  String _mapKey(String key) {
    return switch (key.trim().toLowerCase()) {
      'enter' || 'return' || 'keycode_enter' => '\uE007',
      'tab' || 'keycode_tab' => '\uE004',
      'escape' || 'esc' || 'keycode_escape' => '\uE00C',
      'backspace' || 'delete' || 'keycode_del' => '\uE003',
      _ => key,
    };
  }

  String _mapOrientation(String orientation) {
    return switch (orientation) {
      'landscape' => 'LANDSCAPE',
      'reverseLandscape' => 'UIA_DEVICE_ORIENTATION_LANDSCAPERIGHT',
      'reversePortrait' => 'UIA_DEVICE_ORIENTATION_PORTRAIT_UPSIDEDOWN',
      _ => 'PORTRAIT',
    };
  }

  String _mapButtonName(String name) {
    return switch (name.trim().toLowerCase()) {
      'home' => 'home',
      'volumeup' || 'volume_up' || 'volume-up' => 'volumeUp',
      'volumedown' || 'volume_down' || 'volume-down' => 'volumeDown',
      'action' => 'action',
      'camera' => 'camera',
      _ => name,
    };
  }
}

bool _looksLikeIosSimulatorDeviceId(String deviceId) =>
    deviceId.toLowerCase() == 'booted' ||
    RegExp(
      r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$',
    ).hasMatch(deviceId);

final class CockpitIosWdaSession {
  const CockpitIosWdaSession({required this.baseUri, required this.sessionId});

  final Uri baseUri;
  final String sessionId;
}

final class CockpitIosWdaCommand {
  const CockpitIosWdaCommand({
    required this.baseUri,
    required this.action,
    this.stabilitySnapshot = false,
    this.parameters = const <String, Object?>{},
  });

  final Uri baseUri;
  final CockpitIosWdaAction action;
  final bool stabilitySnapshot;
  final Map<String, Object?> parameters;
}

enum CockpitIosWdaAction {
  tap,
  longPress,
  drag,
  typeText,
  pressKey,
  dismissSystemDialog,
  dismissKeyboard,
  pressButton,
  pressHome,
  activateApp,
  terminateApp,
  setOrientation,
  readUiTree,
  readDeviceInfo,
  readFocusState,
  expandNotifications,
  expandQuickSettings,
  collapseSystemUi,
  tapNotification,
  resolveBlockers,
}

final class _WdaSize {
  const _WdaSize(this.width, this.height);

  final int width;
  final int height;
}

final class _WdaPoint {
  const _WdaPoint(this.x, this.y);

  final int x;
  final int y;
}
