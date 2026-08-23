import 'dart:convert';

import 'package:cockpit/src/cli/cockpit_flutter_bridge_shell_inspector.dart';
import 'package:cockpit/src/infrastructure/cockpit_file_system.dart';
import 'package:cockpit/src/supervisor/cockpit_supervisor_api_client.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

void main() {
  test('accepts an indirect development bridge shell', () {
    final fileSystem = MemoryFileSystem();
    _writePackageConfig(fileSystem, includeFlutterCockpit: true);
    fileSystem.file('/workspace/cockpit/main.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        "import 'cockpit_bootstrap.dart';\n"
        'void main() => runApp(buildCockpitApp());\n',
      );
    fileSystem.file('/workspace/cockpit/cockpit_bootstrap.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        "import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';\n"
        'Widget buildCockpitApp() => FlutterCockpitApp(child: App());\n',
      );

    _inspector(fileSystem).validate(
      checkoutRoot: '/workspace',
      projectPath: '/workspace',
      entrypoint: 'cockpit/main.dart',
    );
  });

  test('rejects a production entrypoint without a bridge', () {
    final fileSystem = MemoryFileSystem();
    _writePackageConfig(fileSystem, includeFlutterCockpit: true);
    fileSystem.file('/workspace/lib/main.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
// import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';
const misleading = 'FlutterCockpitApp';
void main() => runApp(const App());
''');

    expect(
      () => _inspector(fileSystem).validate(
        checkoutRoot: '/workspace',
        projectPath: '/workspace',
        entrypoint: 'lib/main.dart',
      ),
      throwsA(_errorCode('flutterBridgeShellMissing')),
    );
  });

  test('rejects an unused flutter_cockpit import', () {
    final fileSystem = MemoryFileSystem();
    _writePackageConfig(fileSystem, includeFlutterCockpit: true);
    fileSystem.file('/workspace/cockpit/main.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        "import 'package:flutter_cockpit/flutter_cockpit_flutter.dart';\n"
        'void main() => runApp(const App());\n',
      );

    expect(
      () => _inspector(fileSystem).validate(
        checkoutRoot: '/workspace',
        projectPath: '/workspace',
        entrypoint: 'cockpit/main.dart',
      ),
      throwsA(_errorCode('flutterBridgeShellMissing')),
    );
  });

  test('requires flutter pub get before bridge inspection', () {
    final fileSystem = MemoryFileSystem();
    fileSystem.file('/workspace/cockpit/main.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('void main() {}\n');

    expect(
      () => _inspector(fileSystem).validate(
        checkoutRoot: '/workspace',
        projectPath: '/workspace',
        entrypoint: 'cockpit/main.dart',
      ),
      throwsA(_errorCode('flutterPubGetRequired')),
    );
  });

  test('requires the flutter_cockpit dependency to be resolved', () {
    final fileSystem = MemoryFileSystem();
    _writePackageConfig(fileSystem, includeFlutterCockpit: false);
    fileSystem.file('/workspace/cockpit/main.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('void main() {}\n');

    expect(
      () => _inspector(fileSystem).validate(
        checkoutRoot: '/workspace',
        projectPath: '/workspace',
        entrypoint: 'cockpit/main.dart',
      ),
      throwsA(_errorCode('flutterCockpitDependencyMissing')),
    );
  });
}

CockpitFlutterBridgeShellInspector _inspector(MemoryFileSystem fileSystem) {
  return CockpitFlutterBridgeShellInspector(
    fileSystem: LocalCockpitFileSystem(fileSystem: fileSystem),
  );
}

Matcher _errorCode(String code) {
  return isA<CockpitSupervisorClientException>().having(
    (error) => error.code,
    'code',
    code,
  );
}

void _writePackageConfig(
  MemoryFileSystem fileSystem, {
  required bool includeFlutterCockpit,
}) {
  fileSystem.file('/workspace/.dart_tool/package_config.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode(<String, Object?>{
        'configVersion': 2,
        'packages': <Map<String, Object?>>[
          <String, Object?>{
            'name': 'demo',
            'rootUri': 'file:///workspace/',
            'packageUri': 'lib/',
          },
          if (includeFlutterCockpit)
            <String, Object?>{
              'name': 'flutter_cockpit',
              'rootUri': 'file:///deps/flutter_cockpit/',
              'packageUri': 'lib/',
            },
        ],
      }),
    );
}
