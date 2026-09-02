import 'package:cockpit/src/application/cockpit_list_launch_targets_service.dart';
import 'package:cockpit/src/cli/cockpit_flutter_device_selection.dart';
import 'package:cockpit/src/supervisor/cockpit_supervisor_api_client.dart';
import 'package:test/test.dart';

void main() {
  final iphone = CockpitLaunchTarget(
    id: 'ios-device',
    name: 'Iota iPhone',
    platform: 'ios',
    platformType: 'ios',
    emulator: false,
    ephemeral: false,
    sdk: 'iOS 26',
  );
  final macos = CockpitLaunchTarget(
    id: 'macos',
    name: 'macOS',
    platform: 'macos',
    platformType: 'darwin',
    emulator: false,
    ephemeral: false,
    sdk: 'macOS 26',
  );

  test('requires an exact device when host and physical devices coexist', () {
    final error = catchCockpitError(
      () => cockpitSelectFlutterDevice(<CockpitLaunchTarget>[iphone, macos]),
    );

    expect(error.code, 'deviceAmbiguous');
    expect(error.message, contains('ios-device'));
    expect(error.message, contains('macos'));
    expect(error.message, contains('cockpit dev start --device <id>'));
  });

  test('returns the only discovered candidate without a platform guess', () {
    expect(
      cockpitSelectFlutterDevice(<CockpitLaunchTarget>[iphone]),
      same(iphone),
    );
  });

  test('filters by exact device and platform', () {
    expect(
      cockpitSelectFlutterDevice(
        <CockpitLaunchTarget>[iphone, macos],
        deviceId: 'ios-device',
        platform: 'ios',
      ),
      same(iphone),
    );
  });

  test('reports a reconnect action when the requested device is offline', () {
    final error = catchCockpitError(
      () => cockpitSelectFlutterDevice(<CockpitLaunchTarget>[
        macos,
      ], deviceId: 'android-offline'),
    );

    expect(error.code, 'deviceNotFound');
    expect(error.message, contains('cockpit target discover'));
    expect(error.message, contains('connect or boot'));
  });
}

CockpitSupervisorClientException catchCockpitError(void Function() callback) {
  try {
    callback();
  } on CockpitSupervisorClientException catch (error) {
    return error;
  }
  fail('Expected CockpitSupervisorClientException.');
}
