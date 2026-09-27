import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/cli/cockpit_cli_runtime.dart';
import 'package:cockpit/src/cli/cockpit_command_runner.dart';
import 'package:cockpit/src/foundation/cockpit_home.dart';
import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/supervisor/cockpit_daemon_client.dart';
import 'package:cockpit/src/supervisor/cockpit_supervisor_api_client.dart';
import 'package:test/test.dart';

void main() {
  late Directory home;
  late CockpitSupervisorApiClient client;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('cockpit_daemon_logs');
    await File('${home.path}${Platform.pathSeparator}daemon.log').writeAsString(
      List<String>.generate(
        2500,
        (index) => 'line-${index + 1}',
        growable: false,
      ).join('\n'),
    );
    client = CockpitSupervisorApiClient(
      lifecycle: CockpitDaemonLifecycleClient(
        paths: CockpitHomePaths(home.path),
        executable: 'dart',
        daemonArguments: const <String>['run', 'cockpit_daemon'],
        restartArguments: const <String>[],
        permissionHardener: const CockpitPosixPermissionHardener(),
        directorySyncer: _NoopDirectorySyncer(),
        requiredEngineVersion: '4.10.0',
      ),
    );
    addTearDown(() async {
      if (await home.exists()) {
        await home.delete(recursive: true);
      }
    });
  });

  Future<(int, String, String)> runLogs(List<String> arguments) async {
    final stdout = StringBuffer();
    final stderr = StringBuffer();
    final runner = CockpitCommandRunner(
      runtime: CockpitCliRuntime(
        stdoutSink: stdout,
        stderrSink: stderr,
        clientProvider: () async => client,
      ),
    );
    final exitCode = await runner.run(<String>[
      'daemon',
      'logs',
      '--format=json',
      '--view',
      'full',
      ...arguments,
    ]);
    return (exitCode, stdout.toString(), stderr.toString());
  }

  test('daemon logs tails the requested number of lines', () async {
    final (exitCode, stdout, stderr) = await runLogs(const <String>[
      '--lines',
      '1',
    ]);
    expect(exitCode, cockpitSuccessExitCode);
    expect(stderr, isEmpty);
    expect((jsonDecode(stdout) as Map<Object?, Object?>)['lines'], <Object?>[
      'line-2500',
    ]);
  });

  test('daemon logs defaults to fifty trailing lines', () async {
    final (exitCode, stdout, _) = await runLogs(const <String>[]);
    expect(exitCode, cockpitSuccessExitCode);
    final lines =
        (jsonDecode(stdout) as Map<Object?, Object?>)['lines']!
            as List<Object?>;
    expect(lines, hasLength(50));
    expect(lines.first, 'line-2451');
    expect(lines.last, 'line-2500');
  });

  test(
    'daemon logs accepts the documented maximum of two thousand lines',
    () async {
      final (exitCode, stdout, _) = await runLogs(const <String>[
        '--lines',
        '2000',
      ]);
      expect(exitCode, cockpitSuccessExitCode);
      final lines =
          (jsonDecode(stdout) as Map<Object?, Object?>)['lines']!
              as List<Object?>;
      expect(lines, hasLength(2000));
      expect(lines.first, 'line-501');
      expect(lines.last, 'line-2500');
    },
  );

  test(
    'daemon logs rejects out-of-range and non-numeric line counts',
    () async {
      for (final raw in <String>['0', '-5', '2001', 'abc']) {
        final (exitCode, _, stderr) = await runLogs(<String>['--lines', raw]);
        expect(exitCode, cockpitDataExitCode, reason: '--lines $raw');
        expect(stderr, contains('--lines must be an integer from 1 to 2000.'));
      }
    },
  );
}

final class _NoopDirectorySyncer implements CockpitDirectorySyncer {
  @override
  Future<void> sync(String directoryPath) async {}
}
