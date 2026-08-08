import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/infrastructure/cockpit_flutter_tool_isolation.dart';
import 'package:cockpit/src/infrastructure/cockpit_process_manager.dart';
import 'package:process/process.dart';
import 'package:test/test.dart';

void main() {
  test('resident Flutter tool uses a checkout-local compiler', () async {
    final temp = await Directory.systemTemp.createTemp(
      'cockpit flutter isolation ',
    );
    addTearDown(() => temp.delete(recursive: true));
    final sdkBin = Directory('${temp.path}/sdk/bin')
      ..createSync(recursive: true);
    final flutterDev = File('${sdkBin.path}/flutter-dev')
      ..writeAsStringSync('#!/bin/sh\n');
    final flutter = Link('${sdkBin.path}/flutter')..createSync(flutterDev.path);
    final project = Directory('${temp.path}/project with spaces')
      ..createSync(recursive: true);

    final environment = cockpitIsolateFlutterTool(
      executable: flutter.path,
      workingDirectory: project.path,
      environment: const <String, String>{
        'API_TOKEN': 'value',
        'FLUTTER_TOOL_ARGS':
            '--enable-asserts --resident-compiler-info-file=/tmp/shared.json',
      },
      windows: false,
    );

    expect(environment, <String, String>{
      'API_TOKEN': 'value',
      'FLUTTER_TOOL_ARGS':
          '--enable-asserts '
          '--resident-compiler-info-file=.dart_tool/cockpit_flutter_compiler.json',
    });
    expect(Directory('${project.path}/.dart_tool').existsSync(), isTrue);
  });

  test('resident Flutter tool resolves a bare executable from PATH', () async {
    final temp = await Directory.systemTemp.createTemp('cockpit-flutter-path-');
    addTearDown(() => temp.delete(recursive: true));
    final flutterDev = File('${temp.path}/flutter-dev')
      ..writeAsStringSync('#!/bin/sh\n');
    Link('${temp.path}/flutter').createSync(flutterDev.path);
    final project = Directory('${temp.path}/project')..createSync();

    final environment = cockpitIsolateFlutterTool(
      executable: 'flutter',
      workingDirectory: project.path,
      environment: null,
      parentEnvironment: <String, String>{
        'PATH': temp.path,
        'FLUTTER_TOOL_ARGS': '--enable-asserts',
      },
      windows: false,
    );

    expect(
      environment?['FLUTTER_TOOL_ARGS'],
      '--enable-asserts '
      '--resident-compiler-info-file=.dart_tool/cockpit_flutter_compiler.json',
    );
  });

  test('snapshot Flutter tool keeps the original environment', () async {
    final temp = await Directory.systemTemp.createTemp(
      'cockpit-flutter-snapshot-',
    );
    addTearDown(() => temp.delete(recursive: true));
    final flutter = File('${temp.path}/flutter')
      ..writeAsStringSync('#!/bin/sh\n');
    final project = Directory('${temp.path}/project')..createSync();
    const original = <String, String>{'API_TOKEN': 'value'};

    final environment = cockpitIsolateFlutterTool(
      executable: flutter.path,
      workingDirectory: project.path,
      environment: original,
      windows: false,
    );

    expect(identical(environment, original), isTrue);
    expect(Directory('${project.path}/.dart_tool').existsSync(), isFalse);
  });

  test('isolated children retain required host runtime environment', () {
    final environment = cockpitMinimumChildEnvironment(
      parentEnvironment: const <String, String>{
        'PATH': '/usr/bin',
        'DISPLAY': ':99',
        'XAUTHORITY': '/tmp/xauthority',
        'DBUS_SESSION_BUS_ADDRESS': 'unix:path=/tmp/dbus',
        'SystemDrive': r'C:',
        'ProgramFiles': r'C:\Program Files',
        'LOCALAPPDATA': r'C:\Users\runner\AppData\Local',
        'COMSPEC': r'C:\Windows\System32\cmd.exe',
        'COCKPIT_HOME': '/tmp/cockpit-isolated',
        'PSModulePath': r'C:\Windows\System32\WindowsPowerShell\v1.0\Modules',
        'SECRET_TOKEN': 'must-not-leak',
      },
    );

    expect(environment, <String, String>{
      'PATH': '/usr/bin',
      'DISPLAY': ':99',
      'XAUTHORITY': '/tmp/xauthority',
      'DBUS_SESSION_BUS_ADDRESS': 'unix:path=/tmp/dbus',
      'SystemDrive': r'C:',
      'ProgramFiles': r'C:\Program Files',
      'LOCALAPPDATA': r'C:\Users\runner\AppData\Local',
      'COMSPEC': r'C:\Windows\System32\cmd.exe',
      'COCKPIT_HOME': '/tmp/cockpit-isolated',
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

  test('Windows isolated environment retains compiler toolchain paths', () {
    final environment = cockpitMinimumChildEnvironment(
      parentEnvironment: const <String, String>{
        'Path': r'C:\VisualStudio\VC\Tools\bin',
        'INCLUDE': r'C:\VisualStudio\VC\Tools\include',
        'LIB': r'C:\VisualStudio\VC\Tools\lib\x64',
        'LIBPATH': r'C:\VisualStudio\VC\Tools\lib\x64',
        'VCToolsInstallDir': r'C:\VisualStudio\VC\Tools\MSVC\14.44',
        'VSINSTALLDIR': r'C:\VisualStudio\2022\Enterprise',
        'WindowsSdkDir': r'C:\Program Files (x86)\Windows Kits\10',
        'WindowsSDKVersion': r'10.0.26100.0\',
        'SECRET_TOKEN': 'must-not-leak',
      },
      windows: true,
    );

    expect(environment, <String, String>{
      'Path': r'C:\VisualStudio\VC\Tools\bin',
      'INCLUDE': r'C:\VisualStudio\VC\Tools\include',
      'LIB': r'C:\VisualStudio\VC\Tools\lib\x64',
      'LIBPATH': r'C:\VisualStudio\VC\Tools\lib\x64',
      'VCToolsInstallDir': r'C:\VisualStudio\VC\Tools\MSVC\14.44',
      'VSINSTALLDIR': r'C:\VisualStudio\2022\Enterprise',
      'WindowsSdkDir': r'C:\Program Files (x86)\Windows Kits\10',
      'WindowsSDKVersion': r'10.0.26100.0\',
    });
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
