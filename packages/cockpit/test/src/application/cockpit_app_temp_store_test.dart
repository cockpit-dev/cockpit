import 'dart:io';

import 'package:cockpit/src/application/cockpit_app_temp_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('app temp survives store replacement until explicit release', () async {
    final testRoot = await Directory.systemTemp.createTemp('cockpit-app-temp-');
    addTearDown(() => testRoot.delete(recursive: true));
    final root = p.join(testRoot.path, 'apps');

    final first = CockpitAppTempStore(
      root: root,
      permissionHardener: const _NoopPermissionHardener(),
    );
    final firstPath = await first.prepare('ds-sessionA');
    await File(p.join(firstPath, 'devfs.marker')).writeAsString('active');

    final replacement = CockpitAppTempStore(
      root: root,
      permissionHardener: const _NoopPermissionHardener(),
    );
    final replacementPath = await replacement.prepare('ds-sessionA');
    final remoteKey = cockpitRemoteAppTempKey(
      platform: 'linux',
      hostPort: 57331,
    );
    final otherPath = await replacement.prepare(remoteKey);

    expect(replacementPath, firstPath);
    expect(
      await File(p.join(replacementPath, 'devfs.marker')).readAsString(),
      'active',
    );
    expect(otherPath, isNot(firstPath));
    expect(await Directory(otherPath).exists(), isTrue);
    expect(cockpitAppTempEnvironment(otherPath), <String, String>{
      'TMPDIR': otherPath,
      'TMP': otherPath,
      'TEMP': otherPath,
    });

    await replacement.release('ds-sessionA');

    expect(await Directory(firstPath).exists(), isFalse);
    expect(await Directory(otherPath).exists(), isTrue);
  });
}

final class _NoopPermissionHardener implements CockpitPermissionHardener {
  const _NoopPermissionHardener();

  @override
  CockpitPermissionPolicy get policy => CockpitPermissionPolicy.posixOwnerOnly;

  @override
  Future<void> hardenDirectory(Directory directory) async {}

  @override
  Future<void> hardenFile(File file) async {}
}
