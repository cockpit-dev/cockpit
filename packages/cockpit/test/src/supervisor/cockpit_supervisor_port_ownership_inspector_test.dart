import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/supervisor/cockpit_supervisor_port_ownership_inspector.dart';
import 'package:test/test.dart';

void main() {
  test('parses locale-independent Windows netstat listeners', () {
    const output = '''
  TCP    127.0.0.1:47331      0.0.0.0:0       LISTENING       1204
  TCP    127.0.0.1:47331      127.0.0.1:52000 ESTABLISHED     1204
  TCP    [::1]:47331          [::]:0          ABHOREN         1204
  TCP    127.0.0.1:48000      0.0.0.0:0       LISTENING       9300
''';

    expect(
      cockpitParseWindowsNetstatListenerProcessIds(output, port: 47331),
      <int>{1204},
    );
  });

  test('keeps all POSIX listeners for one logical loopback endpoint', () {
    const output = '''
p1204
f6
tIPv4
p9300
f7
tIPv6
p1204
f8
tIPv6
''';

    expect(cockpitParsePosixLsofListenerProcessIds(output), <int>{1204, 9300});
  });

  test('accepts a real listener owned by the captured process', () async {
    final socket = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    addTearDown(socket.close);
    final inspector =
        await CockpitSystemSupervisorPortOwnershipInspector.capture(
          workerProcessId: pid,
        );

    final evidence = await inspector.inspect(
      address: InternetAddress.loopbackIPv4,
      port: socket.port,
      deadline: DateTime.now().toUtc().add(const Duration(seconds: 5)),
    );

    expect(evidence, isNotNull);
    expect(evidence!.listenerProcessId, pid);
    expect(evidence.ownedByWorker, isTrue);
  });

  test('rejects a real listener outside the captured process tree', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'cockpit-port-owner-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final childScript = File('${temporary.path}/wait.dart');
    await childScript.writeAsString('''
Future<void> main() async {
  print('ready');
  await Future<void>.delayed(const Duration(days: 1));
}
''');
    final child = await Process.start(
      Platform.resolvedExecutable,
      <String>[childScript.path],
      environment: _minimumEnvironment(),
      includeParentEnvironment: false,
    );
    addTearDown(() async {
      child.kill(ProcessSignal.sigkill);
      await child.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () => -1,
      );
    });
    final ready = await child.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 5));
    expect(ready, 'ready');
    final inspector =
        await CockpitSystemSupervisorPortOwnershipInspector.capture(
          workerProcessId: child.pid,
        );
    final socket = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    addTearDown(socket.close);

    final evidence = await inspector.inspect(
      address: InternetAddress.loopbackIPv4,
      port: socket.port,
      deadline: DateTime.now().toUtc().add(const Duration(seconds: 5)),
    );

    expect(evidence, isNotNull);
    expect(evidence!.listenerProcessId, pid);
    expect(evidence.ownedByWorker, isFalse);
  });
}

Map<String, String> _minimumEnvironment() {
  const names = <String>{
    'PATH',
    'HOME',
    'USERPROFILE',
    'TMPDIR',
    'TMP',
    'TEMP',
    'SystemRoot',
    'WINDIR',
  };
  return <String, String>{
    for (final entry in Platform.environment.entries)
      if (names.contains(entry.key)) entry.key: entry.value,
  };
}
