import 'package:cockpit/src/application/cockpit_app_handle.dart';
import 'package:cockpit/src/application/cockpit_resize_viewport_service.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('forwards a typed viewport request to the owned app endpoint', () async {
    Uri? baseUri;
    CockpitViewportResizeRequest? captured;
    Duration? timeout;
    final service = CockpitResizeViewportService(
      resize: (uri, request, requestTimeout) async {
        baseUri = uri;
        captured = request;
        timeout = requestTimeout;
        return CockpitViewportResizeResult(
          available: true,
          changed: true,
          requestedWidth: request.width,
          requestedHeight: request.height,
          platform: 'macos',
        );
      },
    );

    final result = await service.resize(
      CockpitResizeViewportRequest(
        app: CockpitAppHandle(
          appId: 'app-1',
          mode: CockpitAppMode.development,
          platform: 'macos',
          deviceId: 'macos',
          projectDir: '/tmp/project',
          target: 'lib/main.dart',
          baseUrl: 'http://127.0.0.1:43123',
          launchedAt: DateTime.utc(2026, 8, 4),
        ),
        width: 800,
        height: 600,
        timeout: const Duration(seconds: 45),
      ),
    );

    expect(baseUri, Uri.parse('http://127.0.0.1:43123'));
    expect(captured?.toJson(), {'width': 800, 'height': 600});
    expect(timeout, const Duration(seconds: 45));
    expect(result.available, isTrue);
    expect(result.changed, isTrue);
  });
}
