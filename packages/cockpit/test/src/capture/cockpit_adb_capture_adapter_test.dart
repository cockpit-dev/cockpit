import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:cockpit/src/capture/cockpit_adb_capture_adapter.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'adb capture returns after process exit when stdout remains inherited',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_adb_capture_adapter',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });
      final process = _OpenStdoutProcess(
        stdoutPayload: _opaquePng,
        exitCode: Future<int>.value(0),
      );
      addTearDown(process.close);
      final adapter = CockpitAdbCaptureAdapter(
        deviceId: 'emulator-5554',
        processStarter: (_, _) async => process,
        tempFileFactory: (basename) async =>
            File(p.join(tempDir.path, basename)),
        timeout: const Duration(seconds: 2),
      );

      final execution = await adapter
          .capture(_captureCommand())
          .timeout(const Duration(milliseconds: 500));

      expect(execution.result.success, isTrue);
      final sourcePath = execution.artifactSourcePaths.values.single;
      expect(File(sourcePath).readAsBytesSync(), _opaquePng);
    },
  );

  test('adb capture timeout is not blocked by open stdout', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'cockpit_adb_capture_adapter_timeout',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });
    final process = _OpenStdoutProcess(
      stdoutPayload: const <int>[],
      exitCode: Completer<int>().future,
    );
    addTearDown(process.close);
    final adapter = CockpitAdbCaptureAdapter(
      deviceId: 'emulator-5554',
      processStarter: (_, _) async => process,
      tempFileFactory: (basename) async => File(p.join(tempDir.path, basename)),
      timeout: const Duration(milliseconds: 20),
    );

    final execution = await adapter
        .capture(_captureCommand())
        .timeout(const Duration(milliseconds: 500));

    expect(execution.result.success, isFalse);
    expect(execution.result.error?.message, 'adb screencap timed out.');
    expect(process.killSignals, contains(ProcessSignal.sigkill));
  });

  for (final scenario
      in <
        ({
          String name,
          String focus,
          String relation,
          String? front,
          String? degraded,
        })
      >[
        (
          name: 'identifies the expected app surface',
          focus: 'mCurrentFocus=Window{42 u0 dev.cockpit.demo/.MainActivity}',
          relation: 'app',
          front: null,
          degraded: null,
        ),
        (
          name: 'identifies an Android system overlay',
          focus:
              'mCurrentFocus=Window{42 u0 com.android.permissioncontroller/'
              'com.android.permissioncontroller.permission.ui.'
              'GrantPermissionsActivity}',
          relation: 'systemOverlay',
          front: 'com.android.permissioncontroller',
          degraded: null,
        ),
        (
          name: 'identifies a different foreground app',
          focus: 'mCurrentFocus=Window{42 u0 com.example.other/.MainActivity}',
          relation: 'differentApp',
          front: 'com.example.other',
          degraded: 'systemSurfaceMismatch',
        ),
      ]) {
    test('adb capture ${scenario.name}', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'cockpit_adb_capture_adapter_surface',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });
      final screencap = _ClosedProcess(stdoutPayload: _opaquePng);
      final surface = _ClosedProcess(
        stdoutPayload: utf8.encode('${scenario.focus}\n'),
      );
      addTearDown(screencap.close);
      addTearDown(surface.close);
      var startCount = 0;
      final adapter = CockpitAdbCaptureAdapter(
        deviceId: 'emulator-5554',
        platformAppId: 'dev.cockpit.demo',
        processStarter: (_, arguments) async {
          startCount += 1;
          return startCount == 1 ? screencap : surface;
        },
        tempFileFactory: (basename) async =>
            File(p.join(tempDir.path, basename)),
      );

      final execution = await adapter.capture(_captureCommand());

      expect(execution.result.success, isTrue);
      expect(execution.result.degradationReason, scenario.degraded);
      expect(execution.result.surface?['relation'], scenario.relation);
      expect(execution.result.surface?['front'], scenario.front);
      expect(
        execution.result.surface?.containsKey('app'),
        scenario.relation != 'app',
      );
    });
  }

  test('adb capture keeps the screenshot when focus probing fails', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'cockpit_adb_capture_adapter_unknown_surface',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });
    final screencap = _ClosedProcess(stdoutPayload: _opaquePng);
    final surface = _ClosedProcess(exitCode: 1);
    addTearDown(screencap.close);
    addTearDown(surface.close);
    var startCount = 0;
    final adapter = CockpitAdbCaptureAdapter(
      deviceId: 'emulator-5554',
      platformAppId: 'dev.cockpit.demo',
      processStarter: (_, arguments) async {
        startCount += 1;
        return startCount == 1 ? screencap : surface;
      },
      tempFileFactory: (basename) async => File(p.join(tempDir.path, basename)),
    );

    final execution = await adapter.capture(_captureCommand());

    expect(execution.result.success, isTrue);
    expect(execution.result.surface, <String, Object?>{
      'relation': 'unknown',
      'app': 'dev.cockpit.demo',
    });
  });

  test('adb capture waits for focus stdout after process exit', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'cockpit_adb_capture_adapter_delayed_surface',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });
    final screencap = _ClosedProcess(stdoutPayload: _opaquePng);
    final surface = _DelayedStdoutProcess(
      stdoutPayload: utf8.encode(
        'mCurrentFocus=Window{42 u0 dev.cockpit.demo/'
        'dev.cockpit.demo.MainActivity}\n',
      ),
      delay: const Duration(milliseconds: 30),
    );
    addTearDown(screencap.close);
    addTearDown(surface.close);
    var startCount = 0;
    final adapter = CockpitAdbCaptureAdapter(
      deviceId: 'emulator-5554',
      platformAppId: 'dev.cockpit.demo',
      processStarter: (_, arguments) async {
        startCount += 1;
        return startCount == 1 ? screencap : surface;
      },
      tempFileFactory: (basename) async => File(p.join(tempDir.path, basename)),
    );

    final stopwatch = Stopwatch()..start();
    final execution = await adapter.capture(_captureCommand());
    stopwatch.stop();

    expect(execution.result.surface, <String, Object?>{'relation': 'app'});
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
  });
}

CockpitCommand _captureCommand() => CockpitCommand(
  commandId: 'capture-adb',
  commandType: CockpitCommandType.captureScreenshot,
  screenshotRequest: const CockpitScreenshotRequest(
    reason: CockpitScreenshotReason.acceptance,
    name: 'adb-acceptance',
  ),
);

final class _OpenStdoutProcess implements Process {
  _OpenStdoutProcess({
    required List<int> stdoutPayload,
    required Future<int> exitCode,
  }) : _exitCode = exitCode {
    scheduleMicrotask(() {
      if (stdoutPayload.isNotEmpty) {
        _stdoutController.add(stdoutPayload);
      }
    });
  }

  final StreamController<List<int>> _stdoutController =
      StreamController<List<int>>();
  final StreamController<List<int>> _stderrController =
      StreamController<List<int>>();
  final StreamController<List<int>> _stdinController =
      StreamController<List<int>>();
  final Future<int> _exitCode;
  final List<ProcessSignal> killSignals = <ProcessSignal>[];

  @override
  Future<int> get exitCode => _exitCode;

  @override
  int get pid => 1;

  @override
  IOSink get stdin => IOSink(_stdinController.sink);

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killSignals.add(signal);
    return true;
  }

  Future<void> close() async {
    if (!_stdoutController.isClosed) {
      unawaited(_stdoutController.close());
    }
    if (!_stderrController.isClosed) {
      unawaited(_stderrController.close());
    }
    if (!_stdinController.isClosed) {
      unawaited(_stdinController.close());
    }
  }
}

final class _ClosedProcess implements Process {
  _ClosedProcess({List<int> stdoutPayload = const <int>[], int exitCode = 0})
    : _stdoutPayload = stdoutPayload,
      _exitCode = exitCode;

  final List<int> _stdoutPayload;
  final int _exitCode;
  final StreamController<List<int>> _stdinController =
      StreamController<List<int>>();

  @override
  Future<int> get exitCode => Future<int>.value(_exitCode);

  @override
  int get pid => 2;

  @override
  IOSink get stdin => IOSink(_stdinController.sink);

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  Stream<List<int>> get stdout => Stream<List<int>>.value(_stdoutPayload);

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;

  Future<void> close() async {
    if (!_stdinController.isClosed) {
      unawaited(_stdinController.close());
    }
  }
}

final class _DelayedStdoutProcess implements Process {
  _DelayedStdoutProcess({
    required List<int> stdoutPayload,
    required Duration delay,
  }) : _stdoutController = StreamController<List<int>>(),
       _stdinController = StreamController<List<int>>() {
    unawaited(
      Future<void>.delayed(delay, () async {
        _stdoutController.add(stdoutPayload);
        await _stdoutController.close();
      }),
    );
  }

  final StreamController<List<int>> _stdoutController;
  final StreamController<List<int>> _stdinController;

  @override
  Future<int> get exitCode => Future<int>.value(0);

  @override
  int get pid => 3;

  @override
  IOSink get stdin => IOSink(_stdinController.sink);

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;

  Future<void> close() async {
    if (!_stdoutController.isClosed) {
      unawaited(_stdoutController.close());
    }
    if (!_stdinController.isClosed) {
      unawaited(_stdinController.close());
    }
  }
}

final List<int> _opaquePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVQI12O8rmb7n4GBgQEADj0CO1/m6EIAAAAASUVORK5CYII=',
);
