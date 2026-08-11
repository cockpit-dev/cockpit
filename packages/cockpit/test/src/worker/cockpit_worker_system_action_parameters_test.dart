import 'dart:io';

import 'package:cockpit/src/foundation/cockpit_locked_json_store.dart';
import 'package:cockpit/src/foundation/cockpit_permissions.dart';
import 'package:cockpit/src/system_control/cockpit_system_control_profile.dart';
import 'package:cockpit/src/worker/cockpit_worker_document_index.dart';
import 'package:cockpit/src/worker/cockpit_worker_runtime_registry.dart';
import 'package:cockpit/src/worker/cockpit_worker_system_action_parameters.dart';
import 'package:cockpit/src/worker/cockpit_workspace_application_adapters.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'installApp resolves a document capability and rejects appPath',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      final prepared = await fixture.parameters.prepare(
        action: CockpitSystemControlAction.installApp,
        platform: 'android',
        idempotencyKey: 'install-app-key',
        parameters: <String, Object?>{
          'documentId': fixture.documentId,
          'grantPermissions': true,
        },
      );

      expect(prepared.parameters['appPath'], fixture.documentPath);
      expect(prepared.parameters['grantPermissions'], isTrue);
      await expectLater(
        fixture.parameters.prepare(
          action: CockpitSystemControlAction.installApp,
          platform: 'android',
          idempotencyKey: 'legacy-install-key',
          parameters: const <String, Object?>{'appPath': '/tmp/app.apk'},
        ),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test(
    'Android push and pull separate device paths from host authority',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      final push = await fixture.parameters.prepare(
        action: CockpitSystemControlAction.pushFile,
        platform: 'android',
        idempotencyKey: 'android-push-key',
        parameters: <String, Object?>{
          'documentId': fixture.documentId,
          'deviceDestinationPath': '/sdcard/Download/input.json',
        },
      );
      final pull = await fixture.parameters.prepare(
        action: CockpitSystemControlAction.pullFile,
        platform: 'android',
        idempotencyKey: 'android-pull-key',
        parameters: const <String, Object?>{
          'deviceSourcePath': '/sdcard/Download/output.json',
          'outputName': 'output.json',
        },
      );

      expect(push.parameters, <String, Object?>{
        'sourcePath': fixture.documentPath,
        'destinationPath': '/sdcard/Download/input.json',
      });
      expect(pull.parameters['sourcePath'], '/sdcard/Download/output.json');
      expect(p.isWithin(fixture.producerRoot, pull.producedPath!), isTrue);
      expect(p.basename(pull.producedPath!), endsWith('_output.json'));
    },
  );

  test('iOS push requires an explicit container destination', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);

    final prepared = await fixture.parameters.prepare(
      action: CockpitSystemControlAction.pushFile,
      platform: 'ios',
      idempotencyKey: 'ios-push-key',
      parameters: <String, Object?>{
        'documentId': fixture.documentId,
        'containerDestinationPath': 'Documents/input.json',
      },
    );

    expect(prepared.parameters['sourcePath'], fixture.documentPath);
    expect(prepared.parameters['destinationPath'], 'Documents/input.json');
    await expectLater(
      fixture.parameters.prepare(
        action: CockpitSystemControlAction.pushFile,
        platform: 'ios',
        idempotencyKey: 'ios-legacy-push-key',
        parameters: <String, Object?>{
          'documentId': fixture.documentId,
          'destinationPath': '/tmp/host-output',
        },
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'desktop file actions copy capabilities only into producer state',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      final prepared = await fixture.parameters.prepare(
        action: CockpitSystemControlAction.addMedia,
        platform: 'macos',
        idempotencyKey: 'desktop-media-key',
        parameters: <String, Object?>{
          'documentId': fixture.documentId,
          'outputName': 'media.json',
        },
      );

      expect(prepared.parameters['sourcePath'], fixture.documentPath);
      expect(prepared.parameters['destinationPath'], prepared.producedPath);
      expect(p.isWithin(fixture.producerRoot, prepared.producedPath!), isTrue);
    },
  );

  test('legacy and nested path-like keys fail closed', () {
    for (final key in <String>[
      'sourcePath',
      'destinationPath',
      'outputPath',
      'handleFile',
      'bundleDir',
      'state_root',
    ]) {
      expect(
        () => rejectCockpitWorkerHostPathInputs(<String, Object?>{
          'outer': <String, Object?>{key: '/tmp/private'},
        }, allowedKeys: const <String>{}),
        throwsA(isA<FormatException>()),
        reason: key,
      );
    }
    expect(
      () => rejectCockpitWorkerHostPathInputs(
        const <String, Object?>{
          'parameters': <String, Object?>{
            'deviceSourcePath': '/sdcard/input',
            'containerDestinationPath': 'Documents/output',
          },
        },
        allowedKeys: const <String>{
          'deviceSourcePath',
          'containerDestinationPath',
        },
      ),
      returnsNormally,
    );
  });

  test('logical UI paths are allowed without opening host path inputs', () {
    expect(
      () => rejectCockpitWorkerHostPathInputs(
        const <String, Object?>{
          'command': <String, Object?>{
            'locator': <String, Object?>{
              'path': '/scaffold/listview/textbutton',
            },
          },
        },
        allowedKeys: const <String>{'path'},
      ),
      returnsNormally,
    );
    expect(
      () => rejectCockpitWorkerHostPathInputs(
        const <String, Object?>{
          'command': <String, Object?>{
            'parameters': <String, Object?>{'sourcePath': '/tmp/private'},
          },
        },
        allowedKeys: const <String>{'path'},
      ),
      throwsA(isA<FormatException>()),
    );
  });
}

final class _Fixture {
  _Fixture({
    required this.root,
    required this.producerRoot,
    required this.documentPath,
    required this.documentId,
    required this.parameters,
  });

  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'cockpit-system-action-parameters-',
    );
    final workspace = await Directory(p.join(root.path, 'workspace')).create();
    final state = await Directory(p.join(root.path, 'state')).create();
    final producer = await Directory(p.join(state.path, 'producer')).create();
    final document = await File(
      p.join(workspace.path, 'input.json'),
    ).writeAsString('{"value":1}');
    final documents = CockpitWorkerDocumentIndex(
      workspaceRoot: await workspace.resolveSymbolicLinks(),
      stateRoot: await state.resolveSymbolicLinks(),
      permissionHardener: const _NoopPermissionHardener(),
      directorySyncer: const _NoopDirectorySyncer(),
    );
    final indexed = await documents.refresh();
    final documentId = indexed.single['documentId']! as String;
    final registry = CockpitWorkerRuntimeRegistry(
      workspaceId: 'workspaceA',
      workspaceRoot: await workspace.resolveSymbolicLinks(),
      stateRoot: await state.resolveSymbolicLinks(),
      stateStore: CockpitInMemoryWorkerRuntimeStateStore(),
    );
    return _Fixture(
      root: root,
      producerRoot: await producer.resolveSymbolicLinks(),
      documentPath: await document.resolveSymbolicLinks(),
      documentId: documentId,
      parameters: CockpitWorkerSystemActionParameters(
        producerRoot: await producer.resolveSymbolicLinks(),
        documents: documents,
        artifacts: registry,
      ),
    );
  }

  final Directory root;
  final String producerRoot;
  final String documentPath;
  final String documentId;
  final CockpitWorkerSystemActionParameters parameters;

  Future<void> dispose() => root.delete(recursive: true);
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

final class _NoopDirectorySyncer implements CockpitDirectorySyncer {
  const _NoopDirectorySyncer();

  @override
  Future<void> sync(String directoryPath) async {}
}
