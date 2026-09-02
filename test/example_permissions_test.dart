import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Cockpit development shell declares the required platform access', () {
    final shellRoot = _root('examples/cockpit_demo/cockpit');
    final appRoot = _root('examples/cockpit_demo');

    final shellIosInfo = _read('$shellRoot/ios/Runner/Info.plist');
    expect(shellIosInfo, contains('<key>NSLocalNetworkUsageDescription</key>'));
    expect(shellIosInfo, contains('<key>NSAllowsLocalNetworking</key>'));
    expect(shellIosInfo, isNot(contains('<key>NSAllowsArbitraryLoads</key>')));

    final shellAndroidManifest = _read(
      '$shellRoot/android/app/src/main/AndroidManifest.xml',
    );
    expect(shellAndroidManifest, contains('android.permission.INTERNET'));
    expect(shellAndroidManifest, contains('PROCESS_TEXT'));
    expect(shellAndroidManifest, isNot(contains('android.permission.CAMERA')));
    expect(
      shellAndroidManifest,
      isNot(contains('android.permission.RECORD_AUDIO')),
    );

    final cockpitAndroidManifest = _read(
      'packages/flutter_cockpit/android/src/main/AndroidManifest.xml',
    );
    expect(
      cockpitAndroidManifest,
      contains('android.permission.FOREGROUND_SERVICE'),
    );
    expect(
      cockpitAndroidManifest,
      contains('android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION'),
    );

    for (final root in <String>[appRoot, shellRoot]) {
      for (final configuration in <String>[
        'macos/Runner/DebugProfile.entitlements',
        'macos/Runner/Release.entitlements',
      ]) {
        final entitlements = _read('$root/$configuration');
        expect(entitlements, contains('com.apple.security.network.client'));
        expect(entitlements, contains('com.apple.security.network.server'));
      }
    }
  });
}

String _root(String relativePath) {
  final fromWorkspace = Directory(relativePath);
  if (fromWorkspace.existsSync()) {
    return fromWorkspace.path;
  }
  return Directory('../$relativePath').path;
}

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: 'Missing platform file: $path');
  return file.readAsStringSync();
}
