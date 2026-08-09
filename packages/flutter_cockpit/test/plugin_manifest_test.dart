import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('runtime package registers app-window plugins on every platform', () {
    final pubspecFile = _packageFile('pubspec.yaml');
    expect(pubspecFile.existsSync(), isTrue);

    final source = pubspecFile.readAsStringSync();
    expect(source, contains('plugin:'));
    for (final entry in <String, List<String>>{
      'android': <String>[
        'package: dev.cockpit.flutter_cockpit',
        'pluginClass: FlutterCockpitPlugin',
      ],
      'ios': <String>['pluginClass: FlutterCockpitPlugin'],
      'linux': <String>['pluginClass: FlutterCockpitPlugin'],
      'macos': <String>['pluginClass: FlutterCockpitPlugin'],
      'windows': <String>['pluginClass: FlutterCockpitPluginCApi'],
      'web': <String>[
        'pluginClass: FlutterCockpitWeb',
        'fileName: src/web/flutter_cockpit_web.dart',
      ],
    }.entries) {
      expect(
        source,
        matches(RegExp('^      ${entry.key}:\\s*\$', multiLine: true)),
        reason:
            'The runtime plugin must register app-window capture and recording fallbacks on ${entry.key}.',
      );
      for (final expectedLine in entry.value) {
        expect(source, contains(expectedLine), reason: entry.key);
      }
    }
  });

  test('Darwin packages support SwiftPM and CocoaPods metadata', () {
    final iosPackage = _packageFile(
      'ios/flutter_cockpit/Package.swift',
    ).readAsStringSync();
    final macosPackage = _packageFile(
      'macos/flutter_cockpit/Package.swift',
    ).readAsStringSync();
    final iosPodspec = _packageFile(
      'ios/flutter_cockpit.podspec',
    ).readAsStringSync();
    final macosPodspec = _packageFile(
      'macos/flutter_cockpit.podspec',
    ).readAsStringSync();
    final macosPlugin = _packageFile(
      'macos/flutter_cockpit/Sources/flutter_cockpit/FlutterCockpitPlugin.swift',
    ).readAsStringSync();

    expect(iosPackage, contains('name: "flutter_cockpit"'));
    expect(iosPackage, contains('.iOS("13.0")'));
    expect(
      iosPackage,
      contains(
        '.package(name: "FlutterFramework", path: "../FlutterFramework")',
      ),
    );
    expect(
      iosPackage,
      contains(
        '.product(name: "FlutterFramework", package: "FlutterFramework")',
      ),
    );
    expect(iosPackage, contains('.process("PrivacyInfo.xcprivacy")'));

    expect(macosPackage, contains('name: "flutter_cockpit"'));
    expect(macosPackage, contains('.macOS("10.15")'));
    expect(
      macosPackage,
      contains(
        '.package(name: "FlutterFramework", path: "../FlutterFramework")',
      ),
    );
    expect(
      macosPackage,
      contains(
        '.product(name: "FlutterFramework", package: "FlutterFramework")',
      ),
    );
    expect(macosPackage, contains('.process("PrivacyInfo.xcprivacy")'));

    for (final podspec in <String>[iosPodspec, macosPodspec]) {
      expect(podspec, contains("s.version          = '3.0.5'"));
      expect(podspec, contains(":type => 'MIT'"));
      expect(
        podspec,
        contains(":git => 'https://github.com/cockpit-dev/cockpit.git'"),
      );
      expect(podspec, contains(':tag => "v#{s.version}"'));
      expect(
        podspec,
        matches(
          RegExp(
            "s\\.source_files\\s*=\\s*'flutter_cockpit/Sources/flutter_cockpit/\\*\\*/\\*\\.swift'",
          ),
        ),
      );
      expect(
        podspec,
        contains(
          "'flutter_cockpit/Sources/flutter_cockpit/PrivacyInfo.xcprivacy'",
        ),
      );
    }
    expect(iosPodspec, contains("s.dependency 'Flutter'"));
    expect(macosPodspec, contains("s.dependency 'FlutterMacOS'"));
    expect(macosPlugin, contains('flutterViewController(for: registrar.view)'));
    expect(macosPlugin, isNot(contains('registrar.viewController')));
  });
}

File _packageFile(String relativePath) {
  final workspaceFile = File('packages/flutter_cockpit/$relativePath');
  if (workspaceFile.existsSync()) {
    return workspaceFile;
  }
  return File(relativePath);
}
