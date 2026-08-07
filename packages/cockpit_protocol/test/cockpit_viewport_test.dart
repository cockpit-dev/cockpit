import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('viewport request validates bounds and round-trips', () {
    const request = CockpitViewportResizeRequest(width: 800, height: 600);

    expect(CockpitViewportResizeRequest.fromJson(request.toJson()).toJson(), {
      'width': 800,
      'height': 600,
    });
    expect(
      () => CockpitViewportResizeRequest.fromJson(const {
        'width': 199,
        'height': 600,
      }),
      throwsFormatException,
    );
    expect(
      () => CockpitViewportResizeRequest.fromJson(const {
        'width': 800.0,
        'height': 600,
      }),
      throwsFormatException,
    );
  });

  test('viewport result preserves effective metrics and alternatives', () {
    final result = CockpitViewportResizeResult(
      available: true,
      changed: true,
      requestedWidth: 800,
      requestedHeight: 600,
      platform: 'macos',
      logicalWidth: 800,
      logicalHeight: 600,
      physicalWidth: 1600,
      physicalHeight: 1200,
      devicePixelRatio: 2,
      alternatives: const <String>['managedBrowserViewport'],
    );

    expect(CockpitViewportResizeResult.fromJson(result.toJson()).toJson(), {
      'available': true,
      'changed': true,
      'requested': {'logicalWidth': 800, 'logicalHeight': 600},
      'platform': 'macos',
      'logical': {'width': 800.0, 'height': 600.0},
      'physical': {'width': 1600, 'height': 1200},
      'devicePixelRatio': 2.0,
      'alternatives': ['managedBrowserViewport'],
    });
  });
}
