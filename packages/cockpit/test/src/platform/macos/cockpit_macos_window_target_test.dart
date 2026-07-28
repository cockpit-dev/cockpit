import 'dart:io';

import 'package:cockpit/src/platform/macos/cockpit_macos_window_target.dart';
import 'package:test/test.dart';

void main() {
  test(
    'passes app id and settle delay to the macOS window resolver script',
    () async {
      late List<String> invocation;

      final target = await cockpitResolveMacosWindowTarget(
        appId: 'dev.cockpit.cockpitDemo',
        osascriptExecutable: 'osascript',
        processRunner: (executable, arguments) async {
          expect(executable, 'osascript');
          invocation = List<String>.from(arguments);
          return ProcessResult(0, 0, '1234,48,64,960,720', '');
        },
        timeout: const Duration(seconds: 1),
        activationSettleDelay: const Duration(milliseconds: 250),
      );

      expect(invocation[0], '-l');
      expect(invocation[1], 'JavaScript');
      expect(invocation[2], '-e');
      expect(invocation[4], 'dev.cockpit.cockpitDemo');
      expect(invocation[5], '250');
      expect(invocation[3], isNot(contains('System Events')));
      expect(invocation[3], contains('CGWindowListCopyWindowInfo'));
      expect(invocation[3], contains('IOPMAssertionDeclareUserActivity'));
      expect(target.windowId, 1234);
      expect(target.left, 48);
      expect(target.top, 64);
      expect(target.width, 960);
      expect(target.height, 720);
    },
  );

  test('accepts legacy bounds-only payloads for injected resolvers', () async {
    final target = await cockpitResolveMacosWindowTarget(
      appId: 'dev.cockpit.cockpitDemo',
      osascriptExecutable: 'osascript',
      processRunner: (_, _) async => ProcessResult(0, 0, '48,64,960,720', ''),
      timeout: const Duration(seconds: 1),
      activationSettleDelay: Duration.zero,
    );

    expect(target.windowId, isNull);
    expect(target.left, 48);
    expect(target.top, 64);
  });

  test('rejects invalid macOS window bounds payloads', () async {
    expect(
      () => cockpitResolveMacosWindowTarget(
        appId: 'dev.cockpit.cockpitDemo',
        osascriptExecutable: 'osascript',
        processRunner: (_, _) async {
          return ProcessResult(0, 0, '48,64,0,720', '');
        },
        timeout: const Duration(seconds: 1),
        activationSettleDelay: Duration.zero,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('invalid bounds'),
        ),
      ),
    );
  });
}
