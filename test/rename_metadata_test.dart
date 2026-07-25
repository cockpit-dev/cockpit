import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('workspace metadata points at flutter_cockpit package paths', () {
    final rootPubspec = File('pubspec.yaml').readAsStringSync();
    final melosConfig = File('melos.yaml').readAsStringSync();

    expect(rootPubspec, contains('name: cockpit_workspace'));
    expect(rootPubspec, contains('workspace:'));
    expect(rootPubspec, contains('- packages/cockpit_protocol'));
    expect(rootPubspec, contains('- packages/flutter_cockpit'));
    expect(rootPubspec, contains('- packages/cockpit'));
    expect(rootPubspec, contains('- examples/cockpit_demo'));
    expect(melosConfig, contains('name: cockpit_workspace'));
    expect(melosConfig, contains('packages:'));
    expect(melosConfig, contains('- packages/cockpit_protocol'));
    expect(melosConfig, contains('- packages/flutter_cockpit'));
    expect(melosConfig, contains('- packages/cockpit'));
    expect(melosConfig, contains('- examples/cockpit_demo'));
    expect(melosConfig, contains('scripts:'));
  });

  test(
    'cockpit_demo workspace and standalone shell depend on cockpit packages',
    () {
      final examplePubspec = File(
        'examples/cockpit_demo/pubspec.yaml',
      ).readAsStringSync();
      final shellPubspec = File(
        'examples/cockpit_demo/cockpit/pubspec.yaml',
      ).readAsStringSync();
      final runtimeVersion = _readPackageVersion('packages/flutter_cockpit');
      final devtoolsVersion = _readPackageVersion('packages/cockpit');

      expect(shellPubspec, contains('flutter_cockpit: ^$runtimeVersion'));
      expect(shellPubspec, contains('cockpit: ^$devtoolsVersion'));
      expect(shellPubspec, contains('integration_test:'));
      expect(examplePubspec, isNot(contains('flutter_cockpit:')));
      expect(examplePubspec, isNot(contains('cockpit:')));
      expect(examplePubspec, isNot(contains('flutter_pilot: ^1.0.0')));
      expect(examplePubspec, isNot(contains('flutter_pilot_devtools: ^1.0.0')));
    },
  );
}

String _readPackageVersion(String packageDir) {
  final pubspec = File('$packageDir/pubspec.yaml').readAsStringSync();
  return RegExp(
    r'^version:\s*(.+)$',
    multiLine: true,
  ).firstMatch(pubspec)!.group(1)!.trim();
}
