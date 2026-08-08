import 'dart:convert';
import 'dart:io';

import 'package:cockpit/src/supervisor/cockpit_daemon_client.dart';
import 'package:test/test.dart';

void main() {
  test('daemon log tail reads requested lines from a large file', () async {
    final temp = await Directory.systemTemp.createTemp('cockpit-daemon-log-');
    addTearDown(() => temp.delete(recursive: true));
    final file = File('${temp.path}/daemon.log');
    final sink = file.openWrite();
    final padding = List<int>.filled(64 * 1024, 0x78, growable: false);
    for (var index = 0; index < 145; index += 1) {
      sink.add(padding);
    }
    sink.add(utf8.encode('\nold\nlatest-1\nlatest-2\nlatest-3\n'));
    await sink.close();

    expect(await file.length(), greaterThan(8 * 1024 * 1024));
    expect(await cockpitReadLogTail(file, maximumLines: 3), <String>[
      'latest-1',
      'latest-2',
      'latest-3',
    ]);
  });

  test('daemon log tail bounds a single oversized line', () async {
    final temp = await Directory.systemTemp.createTemp(
      'cockpit-daemon-long-line-',
    );
    addTearDown(() => temp.delete(recursive: true));
    final file = File('${temp.path}/daemon.log');
    final sink = file.openWrite();
    final chunk = List<int>.filled(64 * 1024, 0x78, growable: false);
    for (var index = 0; index < 40; index += 1) {
      sink.add(chunk);
    }
    sink.add(utf8.encode('tail-marker'));
    await sink.close();

    final lines = await cockpitReadLogTail(file, maximumLines: 1);

    expect(lines, hasLength(1));
    expect(lines.single, startsWith('…[truncated]'));
    expect(lines.single, endsWith('tail-marker'));
    expect(lines.single.length, lessThan(17 * 1024));
  });
}
