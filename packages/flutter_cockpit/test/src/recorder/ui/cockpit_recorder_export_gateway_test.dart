import 'dart:io';

import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('writes the bundle YAML to <directory>/<caseId>.yaml', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cockpit_recorder_gateway_test',
    );
    addTearDown(() => directory.delete(recursive: true));
    const yaml = 'schemaVersion: cockpit.test/v2\nid: recorded-r1\n';
    final bundle = _bundle('recorded-r1', yaml);

    final gateway = CockpitRecorderFileExportGateway(
      directoryResolver: () => directory.path,
    );
    final path = await gateway.persist(bundle);

    final expected =
        '${directory.path}${Platform.pathSeparator}recorded-r1.yaml';
    expect(path, expected);
    expect(File(path).existsSync(), isTrue);
    expect(await File(path).readAsString(), yaml);
  });

  test('normalizes trailing separators from the resolver', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cockpit_recorder_gateway_test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final bundle = _bundle(
      'recorded-r1',
      'schemaVersion: cockpit.test/v2\nid: recorded-r1\n',
    );

    final gateway = CockpitRecorderFileExportGateway(
      directoryResolver: () => '${directory.path}${Platform.pathSeparator}',
    );
    final path = await gateway.persist(bundle);

    expect(path, '${directory.path}${Platform.pathSeparator}recorded-r1.yaml');
  });

  test('creates missing directories', () async {
    final root = await Directory.systemTemp.createTemp(
      'cockpit_recorder_gateway_test',
    );
    addTearDown(() => root.delete(recursive: true));
    final bundle = _bundle(
      'recorded-r2',
      'schemaVersion: cockpit.test/v2\nid: recorded-r2\n',
    );

    final gateway = CockpitRecorderFileExportGateway(
      directoryResolver: () =>
          '${root.path}${Platform.pathSeparator}nested${Platform.pathSeparator}deeper',
    );
    final path = await gateway.persist(bundle);

    expect(File(path).existsSync(), isTrue);
  });

  test('rejects bundles without a case id', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cockpit_recorder_gateway_test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final bundle = _bundle('', 'schemaVersion: cockpit.test/v2\n');

    final gateway = CockpitRecorderFileExportGateway(
      directoryResolver: () => directory.path,
    );

    await expectLater(gateway.persist(bundle), throwsStateError);
  });

  test('the default resolver writes into the system temp directory', () async {
    // No injected resolver: the gateway must fall back to Directory.systemTemp
    // and write <caseId>.yaml there.
    final gateway = CockpitRecorderFileExportGateway();
    final path = await gateway.persist(
      _bundle(
        'recorded-default-r1',
        'schemaVersion: cockpit.test/v2\nid: recorded-default-r1\n',
      ),
    );

    final file = File(path);
    expect(file.parent.path, Directory.systemTemp.path);
    expect(file.existsSync(), isTrue);
    addTearDown(() => file.delete().ignore);
  });

  test('an unwritable directory surfaces the file-system error', () async {
    // A regular file where the directory should be: creating the directory
    // must fail, and the failure must escape persist instead of being
    // swallowed.
    final blockingFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'cockpit_gateway_blocker_${DateTime.now().microsecondsSinceEpoch}',
    );
    await blockingFile.writeAsString('not a directory');
    addTearDown(() => blockingFile.delete().ignore);

    final gateway = CockpitRecorderFileExportGateway(
      directoryResolver: () => blockingFile.path,
    );

    await expectLater(
      gateway.persist(_bundle('recorded-r1', 'schemaVersion: x\n')),
      throwsA(isA<FileSystemException>()),
    );
  });
}

CockpitRecordedFlowBundle _bundle(String caseId, String yaml) {
  return CockpitRecordedFlowBundle(
    session: CockpitInteractionRecordingSession(
      sessionId: 'r1',
      phase: CockpitRecorderPhase.stopped,
      startedAt: DateTime.utc(2026, 10, 7, 9),
    ),
    caseDocument: <String, Object?>{'id': caseId},
    caseYaml: yaml,
  );
}
