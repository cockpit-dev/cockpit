import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('snapshot target round-trips overlay coverage', () {
    final target = CockpitSnapshotTarget(
      registrationId: 'native.page-action',
      keyValue: 'page-action',
      text: 'Open dialog',
      routeName: '/page',
      visible: false,
      coveredByOverlay: true,
    );

    final decoded = CockpitSnapshotTarget.fromJson(target.toJson());

    expect(decoded, target);
    expect(target.toJson()['coveredByOverlay'], isTrue);
  });

  test('snapshot target omits overlay coverage when not covered', () {
    final target = CockpitSnapshotTarget(
      registrationId: 'native.dialog-action',
      routeName: '/page',
    );

    expect(target.toJson().containsKey('coveredByOverlay'), isFalse);
    expect(
      CockpitSnapshotTarget.fromJson(target.toJson()).coveredByOverlay,
      isFalse,
    );
  });

  test('snapshot target decodes legacy payloads without overlay coverage', () {
    final decoded = CockpitSnapshotTarget.fromJson(const <String, Object?>{
      'registrationId': 'native.legacy',
      'routeName': '/page',
      'supportedCommands': <String>['tap'],
    });

    expect(decoded.coveredByOverlay, isFalse);
    expect(decoded.visible, isTrue);
  });
}
