import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cockpit/src/supervisor/cockpit_lease_registry.dart';
import 'package:cockpit_protocol/cockpit_protocol.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'cockpit_lease_test_support.dart';

void main() {
  test('OS processes preserve durable FIFO lease admission', () async {
    final fixture = await CockpitLeaseTestFixture.create();
    addTearDown(fixture.dispose);
    final first = await fixture.registry.acquire(
      leaseRequest(
        key: 'multiprocess.parent',
        resourceId: 'multiprocess-device',
        waitTimeoutMs: 0,
      ),
    );
    final signalA = p.join(fixture.temporary.path, 'release-a');
    final signalB = p.join(fixture.temporary.path, 'release-b');
    final processA = await _spawnHelper(
      fixture,
      mode: 'lease',
      key: 'multiprocess.a',
      resourceId: 'multiprocess-device',
      holderId: 'processA',
      signalPath: signalA,
    );
    addTearDown(processA.kill);
    await _waitForState(
      fixture,
      holderId: 'processA',
      state: CockpitLeaseState.queued,
    );
    final processB = await _spawnHelper(
      fixture,
      mode: 'lease',
      key: 'multiprocess.b',
      resourceId: 'multiprocess-device',
      holderId: 'processB',
      signalPath: signalB,
    );
    addTearDown(processB.kill);
    await _waitForState(
      fixture,
      holderId: 'processB',
      state: CockpitLeaseState.queued,
    );

    await fixture.registry.release(first.leaseId, holderId: first.holderId);
    await _waitForState(
      fixture,
      holderId: 'processA',
      state: CockpitLeaseState.active,
    );
    await _waitForState(
      fixture,
      holderId: 'processB',
      state: CockpitLeaseState.queued,
    );
    expect((await processA.nextEvent())['event'], 'acquired');
    await File(signalA).writeAsString('release');
    await _waitForState(
      fixture,
      holderId: 'processB',
      state: CockpitLeaseState.active,
    );
    expect((await processB.nextEvent())['event'], 'acquired');
    await File(signalB).writeAsString('release');
    expect((await processA.nextEvent())['event'], 'released');
    expect((await processB.nextEvent())['event'], 'released');
    await processA.expectSuccess();
    await processB.expectSuccess();
  });

  test(
    'a new process replays the same port and lease after holder crash',
    () async {
      final fixture = await CockpitLeaseTestFixture.create();
      addTearDown(fixture.dispose);
      final firstSignal = p.join(fixture.temporary.path, 'port-first');
      final first = await _spawnHelper(
        fixture,
        mode: 'port',
        key: 'multiprocess.port',
        resourceId: 'unused',
        holderId: 'processPort',
        signalPath: firstSignal,
      );
      addTearDown(first.kill);
      final firstEvent = await first.nextEvent();
      final port = firstEvent['port']! as int;
      final leaseId = firstEvent['leaseId']! as String;
      await expectLater(
        ServerSocket.bind(InternetAddress.loopbackIPv4, port, shared: false),
        throwsA(isA<SocketException>()),
      );
      await first.kill();

      final replaySignal = p.join(fixture.temporary.path, 'port-replay');
      final replay = await _spawnHelper(
        fixture,
        mode: 'port',
        key: 'multiprocess.port',
        resourceId: 'unused',
        holderId: 'processPort',
        signalPath: replaySignal,
      );
      addTearDown(replay.kill);
      final replayEvent = await replay.nextEvent();
      expect(replayEvent['port'], port);
      expect(replayEvent['leaseId'], leaseId);
      await File(replaySignal).writeAsString('release');
      expect((await replay.nextEvent())['event'], 'released');
      await replay.expectSuccess();
    },
  );
}

Future<void> _waitForState(
  CockpitLeaseTestFixture fixture, {
  required String holderId,
  required CockpitLeaseState state,
}) => waitForLeaseCondition(
  () async {
    final leases = await fixture.registry.list(
      resourceId: 'multiprocess-device',
    );
    return leases.any(
      (lease) => lease.holderId == holderId && lease.state == state,
    );
  },
  // Each helper is a fresh Dart VM process, so its first lease transition
  // also covers kernel compilation; budget the same 20s the helper event
  // reads allow instead of the in-process 3s default.
  timeout: const Duration(seconds: 20),
);

Future<_HelperProcess> _spawnHelper(
  CockpitLeaseTestFixture fixture, {
  required String mode,
  required String key,
  required String resourceId,
  required String holderId,
  required String signalPath,
}) async {
  final packageLibrary = await Isolate.resolvePackageUri(
    Uri.parse('package:cockpit/cockpit.dart'),
  );
  if (packageLibrary == null) {
    throw StateError('Unable to resolve the cockpit package root.');
  }
  final packageRoot = p.dirname(p.dirname(packageLibrary.toFilePath()));
  final helper = p.join(
    packageRoot,
    'test',
    'src',
    'supervisor',
    'cockpit_lease_process_helper.dart',
  );
  final process = await Process.start(Platform.resolvedExecutable, <String>[
    helper,
    mode,
    fixture.paths.home,
    'workspaceA',
    key,
    resourceId,
    holderId,
    signalPath,
  ], workingDirectory: packageRoot);
  return _HelperProcess(process);
}

final class _HelperProcess {
  _HelperProcess(this.process)
    : _events = StreamIterator<String>(
        utf8.decoder.bind(process.stdout).transform(const LineSplitter()),
      ),
      _stderr = utf8.decoder.bind(process.stderr).join();

  final Process process;
  final StreamIterator<String> _events;
  final Future<String> _stderr;

  Future<Map<String, Object?>> nextEvent() async {
    final available = await _events.moveNext().timeout(
      const Duration(seconds: 20),
    );
    if (!available) throw StateError('Helper exited before emitting an event.');
    return (jsonDecode(_events.current) as Map<Object?, Object?>).cast();
  }

  Future<void> expectSuccess() async {
    final code = await process.exitCode.timeout(const Duration(seconds: 20));
    final error = await _stderr;
    expect(code, 0, reason: error);
  }

  Future<void> kill() async {
    process.kill();
    await process.exitCode.timeout(const Duration(seconds: 5));
  }
}
