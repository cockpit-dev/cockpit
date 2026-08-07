import 'dart:io';

import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_cockpit/src/remote/cockpit_remote_session_endpoint_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'viewport endpoint returns effective metrics from the Flutter resizer',
    () async {
      CockpitViewportResizeRequest? captured;
      final handler = _handler(
        viewportResizer: (request) async {
          captured = request;
          return CockpitViewportResizeResult(
            available: true,
            changed: true,
            requestedWidth: request.width,
            requestedHeight: request.height,
            platform: 'macos',
            logicalWidth: request.width.toDouble(),
            logicalHeight: request.height.toDouble(),
            physicalWidth: request.width * 2,
            physicalHeight: request.height * 2,
            devicePixelRatio: 2,
          );
        },
      );

      final response = await handler.handle(
        CockpitRemoteSessionEndpointRequest(
          method: 'POST',
          uri: Uri.parse('/viewport'),
          jsonBody: const <String, Object?>{'width': 800, 'height': 600},
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(captured?.toJson(), {'width': 800, 'height': 600});
      expect(response.jsonBody?['available'], isTrue);
      expect(response.jsonBody?['physical'], {'width': 1600, 'height': 1200});
    },
  );

  test('viewport endpoint reports typed unavailability', () async {
    final response = await _handler().handle(
      CockpitRemoteSessionEndpointRequest(
        method: 'POST',
        uri: Uri.parse('/viewport'),
        jsonBody: const <String, Object?>{'width': 800, 'height': 600},
      ),
    );

    expect(response.statusCode, HttpStatus.notImplemented);
    expect(response.jsonBody?['error'], 'viewportUnavailable');
  });

  test('viewport endpoint rejects invalid dimensions', () async {
    final response =
        await _handler(
          viewportResizer: (_) async => throw StateError('must not run'),
        ).handle(
          CockpitRemoteSessionEndpointRequest(
            method: 'POST',
            uri: Uri.parse('/viewport'),
            jsonBody: const <String, Object?>{'width': 199, 'height': 600},
          ),
        );

    expect(response.statusCode, HttpStatus.badRequest);
    expect(response.jsonBody?['error'], 'invalidPayload');
  });
}

CockpitRemoteSessionEndpointHandler _handler({
  CockpitRemoteViewportResizer? viewportResizer,
}) => CockpitRemoteSessionEndpointHandler(
  configuration: const CockpitRemoteSessionConfiguration(
    enabled: true,
    autoStart: false,
    port: 0,
  ),
  statusProvider: () async => throw StateError('unused'),
  snapshotProvider: ({required options}) async => throw StateError('unused'),
  commandExecutor: (_) async => throw StateError('unused'),
  viewportResizer: viewportResizer,
  startRecording: (_) async => throw StateError('unused'),
  stopRecording: () async => throw StateError('unused'),
);
