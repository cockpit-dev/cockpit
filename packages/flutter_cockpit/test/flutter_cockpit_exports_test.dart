import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exports flutter_cockpit public runtime surface', () {
    expect(CockpitSessionController, isNotNull);
    expect(FlutterCockpit, isNotNull);
    expect(FlutterCockpitApp, isNotNull);
    expect(FlutterCockpitRoot, isNotNull);
    expect(FlutterCockpitHost, isNotNull);
    expect(FlutterCockpitConfig, isNotNull);
    expect(FlutterCockpitConfiguration, isNotNull);
    expect(CockpitDiscoveryPolicy, isNotNull);
    expect(CockpitDiscoveryEngine, isNotNull);
    expect(CockpitGestureProfile, isNotNull);
    expect(CockpitHitTestMissPolicy, isNotNull);
    expect(CockpitTextInputRequest, isNotNull);
    expect(CockpitPerformanceCollector, isNotNull);
  });
}
