import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Keeps the package example executable: it must run with `dart run` and
/// print the suite manifest plus the resolved locale lines.
void main() {
  test('settings_smoke example runs and prints its manifest', () async {
    // Test runners do not guarantee where Platform.script points, so resolve
    // the package root by walking up from the working directory until this
    // package's pubspec appears.
    var packageRoot = Directory.current;
    while (!File(
      '${packageRoot.path}/pubspec.yaml',
    ).readAsStringSync().contains('name: cockpit_test')) {
      final parent = packageRoot.parent;
      if (parent.path == packageRoot.path) {
        fail('Could not locate the cockpit_test package root.');
      }
      packageRoot = parent;
    }
    final result = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'example/settings_smoke.dart'],
      workingDirectory: packageRoot.path,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final output = result.stdout as String;
    expect(output, contains('"id": "settings-smoke"'));
    expect(output, contains('"id": "save-settings"'));
    expect(output, contains('en-US: Saved'));
    expect(output, contains('zh-CN: 已保存'));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
