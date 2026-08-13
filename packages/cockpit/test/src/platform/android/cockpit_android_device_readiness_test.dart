import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/platform/android/cockpit_android_device_readiness.dart';
import 'package:test/test.dart';

void main() {
  test('accepts a responsive fully booted Android device', () async {
    await cockpitRequireAndroidDeviceReady(
      deviceId: 'emulator-5554',
      processRunner: (executable, arguments, {required timeout}) async {
        expect(executable, 'adb');
        expect(arguments, <String>[
          '-s',
          'emulator-5554',
          'shell',
          'getprop',
          'sys.boot_completed',
        ]);
        expect(timeout, const Duration(seconds: 8));
        return ProcessResult(1, 0, '1\n', '');
      },
    );
  });

  test('classifies an ADB shell timeout as an unresponsive device', () async {
    await expectLater(
      cockpitRequireAndroidDeviceReady(
        deviceId: 'emulator-5554',
        processRunner: (executable, arguments, {required timeout}) =>
            Future<ProcessResult>.error(TimeoutException('adb timed out')),
      ),
      throwsA(
        isA<CockpitAndroidDeviceReadinessException>()
            .having((error) => error.code, 'code', 'androidDeviceUnresponsive')
            .having(
              (error) => error.message,
              'message',
              allOf(
                contains('listed by ADB'),
                contains('same development session'),
              ),
            ),
      ),
    );
  });

  test(
    'distinguishes unauthorized, offline, and incomplete boot states',
    () async {
      await expectLater(
        cockpitRequireAndroidDeviceReady(
          deviceId: 'emulator-5554',
          processRunner: (executable, arguments, {required timeout}) async =>
              ProcessResult(1, 1, '', 'error: device unauthorized'),
        ),
        throwsA(
          isA<CockpitAndroidDeviceReadinessException>().having(
            (error) => error.code,
            'code',
            'androidDeviceUnauthorized',
          ),
        ),
      );
      await expectLater(
        cockpitRequireAndroidDeviceReady(
          deviceId: 'emulator-5554',
          processRunner: (executable, arguments, {required timeout}) async =>
              ProcessResult(1, 1, '', 'error: device offline'),
        ),
        throwsA(
          isA<CockpitAndroidDeviceReadinessException>().having(
            (error) => error.code,
            'code',
            'androidDeviceOffline',
          ),
        ),
      );
      await expectLater(
        cockpitRequireAndroidDeviceReady(
          deviceId: 'emulator-5554',
          processRunner: (executable, arguments, {required timeout}) async =>
              ProcessResult(1, 0, '0\n', ''),
        ),
        throwsA(
          isA<CockpitAndroidDeviceReadinessException>().having(
            (error) => error.code,
            'code',
            'androidDeviceNotBooted',
          ),
        ),
      );
    },
  );

  test('decodes byte output and reports a missing ADB executable', () async {
    await expectLater(
      cockpitRequireAndroidDeviceReady(
        deviceId: 'physical-device',
        processRunner: (executable, arguments, {required timeout}) async =>
            ProcessResult(
              1,
              1,
              const <int>[],
              utf8.encode('error: device offline'),
            ),
      ),
      throwsA(
        isA<CockpitAndroidDeviceReadinessException>().having(
          (error) => error.code,
          'code',
          'androidDeviceOffline',
        ),
      ),
    );
    await expectLater(
      cockpitRequireAndroidDeviceReady(
        deviceId: 'physical-device',
        processRunner: (executable, arguments, {required timeout}) =>
            Future<ProcessResult>.error(
              ProcessException('adb', arguments, 'No such file'),
            ),
      ),
      throwsA(
        isA<CockpitAndroidDeviceReadinessException>()
            .having((error) => error.code, 'code', 'androidAdbUnavailable')
            .having(
              (error) => error.message,
              'message',
              contains('same development session'),
            ),
      ),
    );
  });
}
