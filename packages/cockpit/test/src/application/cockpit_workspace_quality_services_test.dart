import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:isolate';

import 'package:file/memory.dart';
import 'package:cockpit/src/application/cockpit_analyze_workspace_service.dart';
import 'package:cockpit/src/application/cockpit_apply_workspace_fixes_service.dart';
import 'package:cockpit/src/application/cockpit_format_workspace_service.dart';
import 'package:cockpit/src/application/cockpit_run_workspace_tests_service.dart';
import 'package:cockpit/src/infrastructure/cockpit_file_system.dart';
import 'package:cockpit/src/infrastructure/cockpit_process_manager.dart';
import 'package:cockpit/src/infrastructure/cockpit_sdk_environment.dart';
import 'package:test/test.dart';

void main() {
  test(
    'workspace process helper does not keep an unbounded run branch',
    () async {
      final sourceUri = await Isolate.resolvePackageUri(
        Uri.parse(
          'package:cockpit/src/application/cockpit_workspace_tooling_support.dart',
        ),
      );
      expect(sourceUri, isNotNull);
      final source = File.fromUri(sourceUri!).readAsStringSync();

      expect(source, isNot(contains('if (timeout == null)')));
      expect(source, isNot(contains('processManager.run(')));
    },
  );

  test('uses flutter analyze for flutter workspaces', () async {
    final fileSystem = MemoryFileSystem();
    fileSystem.file('/workspace/app/pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        'name: app\n\ndependencies:\n  flutter:\n    sdk: flutter\n',
      );
    final processManager = _RecordingProcessManager();

    final service = CockpitAnalyzeWorkspaceService(
      fileSystem: LocalCockpitFileSystem(fileSystem: fileSystem),
      processManager: processManager,
      sdkEnvironment: const CockpitSdkEnvironment(
        dartExecutable: 'dart-sdk',
        flutterExecutable: 'flutter-sdk',
      ),
    );

    final result = await service.analyze(
      const CockpitAnalyzeWorkspaceRequest(workspaceRoot: '/workspace/app'),
    );

    expect(result.command.executable, 'flutter-sdk');
    expect(result.command.arguments, <String>['analyze']);
  });

  test(
    'runs format, tests, and fixes through bounded workspace commands',
    () async {
      final fileSystem = MemoryFileSystem();
      fileSystem.file('/workspace/pkg/pubspec.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('name: pkg\n');
      final processManager = _RecordingProcessManager();
      final wrappedFileSystem = LocalCockpitFileSystem(fileSystem: fileSystem);

      final formatResult =
          await CockpitFormatWorkspaceService(
            fileSystem: wrappedFileSystem,
            processManager: processManager,
            sdkEnvironment: const CockpitSdkEnvironment(
              dartExecutable: 'dart-sdk',
              flutterExecutable: 'flutter-sdk',
            ),
          ).format(
            const CockpitFormatWorkspaceRequest(
              workspaceRoot: '/workspace/pkg',
            ),
          );
      expect(formatResult.command.arguments, <String>['format', '.']);

      final testResult =
          await CockpitRunWorkspaceTestsService(
            fileSystem: wrappedFileSystem,
            processManager: processManager,
            sdkEnvironment: const CockpitSdkEnvironment(
              dartExecutable: 'dart-sdk',
              flutterExecutable: 'flutter-sdk',
            ),
          ).run(
            const CockpitRunWorkspaceTestsRequest(
              workspaceRoot: '/workspace/pkg',
              paths: <String>['test/unit'],
              name: 'directory selector',
            ),
          );
      expect(testResult.command.arguments, <String>[
        'test',
        '--name',
        'directory selector',
        'test/unit',
      ]);

      final fixResult =
          await CockpitApplyWorkspaceFixesService(
            fileSystem: wrappedFileSystem,
            processManager: processManager,
            sdkEnvironment: const CockpitSdkEnvironment(
              dartExecutable: 'dart-sdk',
              flutterExecutable: 'flutter-sdk',
            ),
          ).apply(
            const CockpitApplyWorkspaceFixesRequest(
              workspaceRoot: '/workspace/pkg',
            ),
          );
      expect(fixResult.command.arguments, <String>['fix', '--apply']);
    },
  );

  test('workspace commands time out instead of hanging forever', () async {
    final fileSystem = MemoryFileSystem();
    fileSystem.file('/workspace/pkg/pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('name: pkg\n');

    final service = CockpitFormatWorkspaceService(
      fileSystem: LocalCockpitFileSystem(fileSystem: fileSystem),
      processManager: _HangingProcessManager(),
      sdkEnvironment: const CockpitSdkEnvironment(
        dartExecutable: 'dart-sdk',
        flutterExecutable: 'flutter-sdk',
      ),
    );

    expect(
      () => service.format(
        const CockpitFormatWorkspaceRequest(
          workspaceRoot: '/workspace/pkg',
          timeout: Duration(milliseconds: 20),
        ),
      ),
      throwsA(isA<Exception>()),
    );
  });

  test(
    'workspace commands return after exit when stdout remains inherited',
    () async {
      final fileSystem = MemoryFileSystem();
      fileSystem.file('/workspace/pkg/pubspec.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('name: pkg\n');
      final processManager = _OpenOutputProcessManager();
      addTearDown(processManager.dispose);

      final service = CockpitFormatWorkspaceService(
        fileSystem: LocalCockpitFileSystem(fileSystem: fileSystem),
        processManager: processManager,
        sdkEnvironment: const CockpitSdkEnvironment(
          dartExecutable: 'dart-sdk',
          flutterExecutable: 'flutter-sdk',
        ),
      );

      final result = await service
          .format(
            const CockpitFormatWorkspaceRequest(
              workspaceRoot: '/workspace/pkg',
              timeout: Duration(seconds: 2),
            ),
          )
          .timeout(const Duration(milliseconds: 500));

      expect(result.exitCode, 0);
      expect(result.stdout, contains('formatted'));
    },
  );
}

final class _RecordingProcessManager implements CockpitProcessManager {
  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) async {
    return ProcessResult(
      1,
      0,
      jsonEncode(<String, Object?>{
        'executable': executable,
        'arguments': arguments,
        'workingDirectory': workingDirectory,
      }),
      '',
    );
  }

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) async {
    return _CompletedFakeProcess(
      stdout: jsonEncode(<String, Object?>{
        'executable': executable,
        'arguments': arguments,
        'workingDirectory': workingDirectory,
      }),
    );
  }
}

final class _HangingProcessManager implements CockpitProcessManager {
  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) async {
    return _FakeProcess();
  }
}

final class _OpenOutputProcessManager implements CockpitProcessManager {
  _OpenOutputProcessManager();

  _OpenOutputProcess? process;

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) async {
    return process = _OpenOutputProcess(stdout: 'formatted\n');
  }

  Future<void> dispose() async {
    await process?.close();
  }
}

final class _OpenOutputProcess implements Process {
  _OpenOutputProcess({required String stdout})
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

  @override
  Future<int> get exitCode => Future<int>.value(0);

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
    unawaited(close());
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

final class _FakeProcess implements Process {
  final StreamController<List<int>> _stdoutController =
      StreamController<List<int>>();
  final StreamController<List<int>> _stderrController =
      StreamController<List<int>>();
  final StreamController<List<int>> _stdinController =
      StreamController<List<int>>();

  @override
  Future<int> get exitCode => Completer<int>().future;

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
    _stdoutController.close();
    _stderrController.close();
    _stdinController.close();
    return true;
  }
}

final class _CompletedFakeProcess implements Process {
  _CompletedFakeProcess({required String stdout, String stderr = ''})
    : _stdout = Stream<List<int>>.value(utf8.encode(stdout)),
      _stderr = Stream<List<int>>.value(utf8.encode(stderr));

  final Stream<List<int>> _stdout;
  final Stream<List<int>> _stderr;
  final StreamController<List<int>> _stdinController =
      StreamController<List<int>>();
  @override
  Future<int> get exitCode => Future<int>.value(0);

  @override
  int get pid => 1;

  @override
  IOSink get stdin => IOSink(_stdinController.sink);

  @override
  Stream<List<int>> get stderr => _stderr;

  @override
  Stream<List<int>> get stdout => _stdout;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    _stdinController.close();
    return true;
  }
}
