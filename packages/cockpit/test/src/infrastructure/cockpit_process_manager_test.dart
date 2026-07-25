import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/infrastructure/cockpit_process_manager.dart';
import 'package:process/process.dart';
import 'package:test/test.dart';

void main() {
  test('isolated children retain required host runtime environment', () {
    final environment = cockpitMinimumChildEnvironment(
      parentEnvironment: const <String, String>{
        'PATH': '/usr/bin',
        'DISPLAY': ':99',
        'XAUTHORITY': '/tmp/xauthority',
        'DBUS_SESSION_BUS_ADDRESS': 'unix:path=/tmp/dbus',
        'ProgramFiles': r'C:\Program Files',
        'LOCALAPPDATA': r'C:\Users\runner\AppData\Local',
        'COMSPEC': r'C:\Windows\System32\cmd.exe',
        'SECRET_TOKEN': 'must-not-leak',
      },
    );

    expect(environment, <String, String>{
      'PATH': '/usr/bin',
      'DISPLAY': ':99',
      'XAUTHORITY': '/tmp/xauthority',
      'DBUS_SESSION_BUS_ADDRESS': 'unix:path=/tmp/dbus',
      'ProgramFiles': r'C:\Program Files',
      'LOCALAPPDATA': r'C:\Users\runner\AppData\Local',
      'COMSPEC': r'C:\Windows\System32\cmd.exe',
    });
  });

  test('Windows isolated environment removes case-insensitive duplicates', () {
    final environment = cockpitMinimumChildEnvironment(
      parentEnvironment: const <String, String>{
        'PATH': r'C:\tools',
        'Path': r'C:\Windows\System32',
        'SYSTEMROOT': r'C:\Windows',
      },
      windows: true,
    );

    expect(
      environment.keys.where((name) => name.toLowerCase() == 'path'),
      hasLength(1),
    );
    expect(
      environment.keys.where((name) => name.toLowerCase() == 'systemroot'),
      hasLength(1),
    );
  });

  group('LocalCockpitProcessManager', () {
    test('delegates run requests to the injected ProcessManager', () async {
      final delegate = _FakeProcessManager(
        onRun:
            ({
              required String executable,
              required List<String> arguments,
              String? workingDirectory,
            }) async {
              return ProcessResult(
                42,
                0,
                '$executable ${arguments.join(' ')}',
                workingDirectory,
              );
            },
      );
      final manager = LocalCockpitProcessManager(processManager: delegate);

      final result = await manager.run('flutter', const [
        'test',
        '--machine',
      ], workingDirectory: '/tmp/repo');

      expect(result.exitCode, 0);
      expect(result.stdout, 'flutter test --machine');
      expect(result.stderr, '/tmp/repo');
      expect(delegate.runExecutables, <String>['flutter']);
      expect(delegate.runArguments, <List<String>>[
        <String>['test', '--machine'],
      ]);
      expect(delegate.runWorkingDirectories, <String?>['/tmp/repo']);
    });

    test('delegates start requests to the injected ProcessManager', () async {
      final process = _FakeProcess();
      final delegate = _FakeProcessManager(
        onStart:
            ({
              required String executable,
              required List<String> arguments,
              String? workingDirectory,
              ProcessStartMode mode = ProcessStartMode.normal,
            }) async {
              return process;
            },
      );
      final manager = LocalCockpitProcessManager(processManager: delegate);

      final started = await manager.start(
        'dart',
        const ['run', 'tool.dart'],
        workingDirectory: '/workspace',
        mode: ProcessStartMode.detached,
      );

      expect(identical(started, process), isTrue);
      expect(delegate.startExecutables, <String>['dart']);
      expect(delegate.startArguments, <List<String>>[
        <String>['run', 'tool.dart'],
      ]);
      expect(delegate.startWorkingDirectories, <String?>['/workspace']);
      expect(delegate.startModes, <ProcessStartMode>[
        ProcessStartMode.detached,
      ]);
    });
  });

  group('cockpitRunManagedProcessWithTimeout', () {
    test('kills timed out processes and preserves captured output', () async {
      final process = _HangingProcess(stdout: 'started\n');
      final delegate = _FakeProcessManager(
        onStart:
            ({
              required String executable,
              required List<String> arguments,
              String? workingDirectory,
              ProcessStartMode mode = ProcessStartMode.normal,
            }) async {
              return process;
            },
      );
      final manager = LocalCockpitProcessManager(processManager: delegate);

      await expectLater(
        () => cockpitRunManagedProcessWithTimeout(
          manager,
          'tool',
          const <String>['wait'],
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(
          isA<CockpitManagedProcessTimeoutException>()
              .having((error) => error.executable, 'executable', 'tool')
              .having((error) => error.stdout, 'stdout', contains('started')),
        ),
      );
      expect(process.killSignals, contains(ProcessSignal.sigkill));
    });
  });

  test('process descendant parser returns children before grandchildren', () {
    const psOutput = '''
      10       1
      11      10
      12      11
      13      10
      20       1
      bad input
    ''';

    expect(cockpitProcessDescendantsFromPs(psOutput, 10), <int>[11, 13, 12]);
    expect(cockpitProcessDescendantsFromPs(psOutput, 20), isEmpty);
  });
}

typedef _RunHandler =
    Future<ProcessResult> Function({
      required String executable,
      required List<String> arguments,
      String? workingDirectory,
    });

typedef _StartHandler =
    Future<Process> Function({
      required String executable,
      required List<String> arguments,
      String? workingDirectory,
      ProcessStartMode mode,
    });

final class _FakeProcessManager implements ProcessManager {
  _FakeProcessManager({this.onRun, this.onStart});

  final _RunHandler? onRun;
  final _StartHandler? onStart;

  final List<String> runExecutables = <String>[];
  final List<List<String>> runArguments = <List<String>>[];
  final List<String?> runWorkingDirectories = <String?>[];

  final List<String> startExecutables = <String>[];
  final List<List<String>> startArguments = <List<String>>[];
  final List<String?> startWorkingDirectories = <String?>[];
  final List<ProcessStartMode> startModes = <ProcessStartMode>[];

  @override
  Future<ProcessResult> run(
    List<Object> command, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) {
    runExecutables.add(command.first as String);
    runArguments.add(command.skip(1).cast<String>().toList(growable: false));
    runWorkingDirectories.add(workingDirectory);
    return onRun!.call(
      executable: command.first as String,
      arguments: command.skip(1).cast<String>().toList(growable: false),
      workingDirectory: workingDirectory,
    );
  }

  @override
  Future<Process> start(
    List<Object> command, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) {
    startExecutables.add(command.first as String);
    startArguments.add(command.skip(1).cast<String>().toList(growable: false));
    startWorkingDirectories.add(workingDirectory);
    startModes.add(mode);
    return onStart!.call(
      executable: command.first as String,
      arguments: command.skip(1).cast<String>().toList(growable: false),
      workingDirectory: workingDirectory,
      mode: mode,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeProcess implements Process {
  final StreamController<List<int>> _stdoutController =
      StreamController<List<int>>();
  final StreamController<List<int>> _stderrController =
      StreamController<List<int>>();
  final StreamController<List<int>> _stdinController =
      StreamController<List<int>>();
  final Completer<int> _exitCode = Completer<int>()..complete(0);

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  int get pid => 1;

  @override
  IOSink get stdin => IOSink(_stdinController.sink);

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}

final class _HangingProcess implements Process {
  _HangingProcess({required String stdout})
    : _stdoutController = StreamController<List<int>>(),
      _stderrController = StreamController<List<int>>() {
    scheduleMicrotask(() {
      _stdoutController.add(utf8.encode(stdout));
    });
  }

  final StreamController<List<int>> _stdoutController;
  final StreamController<List<int>> _stderrController;
  final StreamController<List<int>> _stdinController =
      StreamController<List<int>>();
  final Completer<int> _exitCode = Completer<int>();
  final List<ProcessSignal> killSignals = <ProcessSignal>[];

  @override
  Future<int> get exitCode => _exitCode.future;

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
    if (!_exitCode.isCompleted) {
      _exitCode.complete(-1);
    }
    if (!_stdoutController.isClosed) {
      unawaited(_stdoutController.close());
    }
    if (!_stderrController.isClosed) {
      unawaited(_stderrController.close());
    }
    if (!_stdinController.isClosed) {
      unawaited(_stdinController.close());
    }
    return true;
  }
}
