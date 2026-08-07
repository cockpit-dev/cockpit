import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/platform/ios/cockpit_ios_device_connection.dart';
import 'package:test/test.dart';

void main() {
  test('recognizes simulator-style iOS device identifiers', () {
    expect(
      cockpitLooksLikeIosSimulatorDeviceId(
        '6FD25DED-11E9-4AE9-B4B5-EDF4601981DC',
      ),
      isTrue,
    );
    expect(cockpitLooksLikeIosSimulatorDeviceId('simulator'), isTrue);
    expect(cockpitLooksLikeIosSimulatorDeviceId('ios-simulator'), isTrue);
    expect(
      cockpitLooksLikeIosSimulatorDeviceId('00008110-0009341C2EF3801E'),
      isFalse,
    );
  });

  test('parses devicectl device details into a physical tunnel connection', () {
    final connection = CockpitIosDeviceConnection.fromDevicectlJson(
      <String, Object?>{
        'connectionProperties': <String, Object?>{
          'tunnelIPAddress': 'fd69:8f18:f0a9::1',
        },
        'hardwareProperties': <String, Object?>{'reality': 'physical'},
      },
    );

    expect(connection.isPhysical, isTrue);
    expect(connection.tunnelIpAddress, 'fd69:8f18:f0a9::1');
  });

  test(
    'probe uses a unique temp file per invocation and cleans it up',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_ios_device_connection_probe_test',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final outputPaths = <String>[];
      final probe = CockpitIosDeviceConnectionProbe(
        tempDirectoryPathProvider: () => tempDir.path,
        processRunner:
            (executable, arguments, {String? workingDirectory}) async {
              final outputPath =
                  arguments[arguments.indexOf('--json-output') + 1];
              outputPaths.add(outputPath);
              final outputFile = File(outputPath);
              await outputFile.parent.create(recursive: true);
              await outputFile.writeAsString(
                jsonEncode(<String, Object?>{
                  'result': <String, Object?>{
                    'connectionProperties': <String, Object?>{
                      'tunnelIPAddress': 'fd69:8f18:f0a9::1',
                    },
                    'hardwareProperties': <String, Object?>{
                      'reality': 'physical',
                    },
                  },
                }),
              );
              return ProcessResult(0, 0, '', '');
            },
      );

      final connections =
          await Future.wait(<Future<CockpitIosDeviceConnection?>>[
            probe.probe('00008110-0009341C2EF3801E'),
            probe.probe('00008110-0009341C2EF3801E'),
          ]);

      expect(connections, everyElement(isNotNull));
      expect(outputPaths, hasLength(2));
      expect(outputPaths[0], isNot(equals(outputPaths[1])));
      expect(tempDir.listSync(), isEmpty);
    },
  );

  test('probe returns null when devicectl is unavailable', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'cockpit_ios_device_connection_missing_devicectl',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    final probe = CockpitIosDeviceConnectionProbe(
      tempDirectoryPathProvider: () => tempDir.path,
      processRunner: (executable, arguments, {String? workingDirectory}) async {
        throw ProcessException(
          executable,
          arguments,
          'No such file or directory',
        );
      },
    );

    final connection = await probe.probe('00008110-0009341C2EF3801E');

    expect(connection, isNull);
    expect(tempDir.listSync(), isEmpty);
  });

  test(
    'probe returns null when devicectl exceeds its process budget',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_ios_device_connection_timeout',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final probe = CockpitIosDeviceConnectionProbe(
        tempDirectoryPathProvider: () => tempDir.path,
        processRunner:
            (executable, arguments, {String? workingDirectory}) async {
              throw TimeoutException('devicectl timed out');
            },
      );

      final connection = await probe.probe('00008110-0009341C2EF3801E');

      expect(connection, isNull);
      expect(tempDir.listSync(), isEmpty);
    },
  );
}
