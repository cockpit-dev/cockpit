import 'package:flutter/services.dart';
import 'package:flutter_cockpit/src/runtime/cockpit_native_viewport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.cockpit.test/viewport');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('resize returns an accepted native response', () async {
    MethodCall? invocation;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          invocation = call;
          return <String, Object?>{'accepted': true};
        });

    final result = await const CockpitNativeViewport(
      channel: channel,
    ).resize(width: 1200, height: 800);

    expect(invocation?.method, 'resizeViewport');
    expect(invocation?.arguments, <String, Object?>{
      'width': 1200,
      'height': 800,
    });
    expect(result.accepted, isTrue);
    expect(result.reason, isNull);
    expect(result.alternatives, isEmpty);
  });

  test('resize preserves a structured native rejection', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return <String, Object?>{
            'accepted': false,
            'reason': 'viewportExceedsScreen',
            'alternatives': <Object?>[
              'useViewportAtMost:1512x854',
              42,
              'moveWindowToLargerDisplay',
            ],
          };
        });

    final result = await const CockpitNativeViewport(
      channel: channel,
    ).resize(width: 1200, height: 900);

    expect(result.accepted, isFalse);
    expect(result.reason, 'viewportExceedsScreen');
    expect(result.alternatives, <String>[
      'useViewportAtMost:1512x854',
      'moveWindowToLargerDisplay',
    ]);
  });

  test('resize rejects a malformed native response', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return <String, Object?>{'accepted': 'yes'};
        });

    expect(
      const CockpitNativeViewport(
        channel: channel,
      ).resize(width: 1200, height: 800),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Native viewport resize returned an invalid payload.',
        ),
      ),
    );
  });
}
