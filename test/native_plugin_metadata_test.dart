import 'dart:io';

import 'package:test/test.dart';

void main() {
  final root = Directory.current.path;

  test(
    'runtime pubspec registers app-side plugins on every Flutter platform',
    () {
      final pubspec = File(
        '$root/packages/flutter_cockpit/pubspec.yaml',
      ).readAsStringSync();

      for (final entry in <String, String>{
        'android': 'pluginClass: FlutterCockpitPlugin',
        'ios': 'pluginClass: FlutterCockpitPlugin',
        'linux': 'pluginClass: FlutterCockpitPlugin',
        'macos': 'pluginClass: FlutterCockpitPlugin',
        'windows': 'pluginClass: FlutterCockpitPluginCApi',
        'web': 'pluginClass: FlutterCockpitWeb',
      }.entries) {
        expect(
          pubspec,
          matches(RegExp('^      ${entry.key}:\\s*\$', multiLine: true)),
          reason:
              'App-window capture and recording fallbacks require the runtime plugin to register on ${entry.key}.',
        );
        expect(pubspec, contains(entry.value));
      }
      expect(pubspec, contains('package: dev.cockpit.flutter_cockpit'));
      expect(pubspec, contains('web:'));
      expect(pubspec, contains('pluginClass: FlutterCockpitWeb'));
      expect(pubspec, contains('fileName: src/web/flutter_cockpit_web.dart'));
    },
  );

  test('production registrants stay Cockpit-free and shell registrants include it', () {
    final productionRegistrants = <String>[
      '$root/examples/cockpit_demo/macos/Flutter/GeneratedPluginRegistrant.swift',
      '$root/examples/cockpit_demo/linux/flutter/generated_plugin_registrant.cc',
      '$root/examples/cockpit_demo/windows/flutter/generated_plugin_registrant.cc',
    ];
    for (final path in productionRegistrants) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        isNot(contains('flutter_cockpit')),
        reason: '$path must remain a production registrant.',
      );
    }

    expect(
      File(
        '$root/examples/cockpit_demo/cockpit/macos/Flutter/GeneratedPluginRegistrant.swift',
      ).readAsStringSync(),
      allOf(
        contains('import flutter_cockpit'),
        contains('FlutterCockpitPlugin.register'),
      ),
    );
    expect(
      File(
        '$root/examples/cockpit_demo/cockpit/linux/flutter/generated_plugin_registrant.cc',
      ).readAsStringSync(),
      allOf(
        contains('#include <flutter_cockpit/flutter_cockpit_plugin.h>'),
        contains('flutter_cockpit_plugin_register_with_registrar'),
      ),
    );
    expect(
      File(
        '$root/examples/cockpit_demo/cockpit/windows/flutter/generated_plugin_registrant.cc',
      ).readAsStringSync(),
      allOf(
        contains('#include <flutter_cockpit/flutter_cockpit_plugin_c_api.h>'),
        contains('FlutterCockpitPluginCApiRegisterWithRegistrar'),
      ),
    );
  });

  test('example macOS project uses SwiftPM without CocoaPods integration', () {
    final macosRoot = Directory('$root/examples/cockpit_demo/macos');

    expect(File('${macosRoot.path}/Podfile').existsSync(), isFalse);
    expect(File('${macosRoot.path}/Podfile.lock').existsSync(), isFalse);

    final shellMacosRoot = Directory(
      '$root/examples/cockpit_demo/cockpit/macos',
    );
    expect(File('${shellMacosRoot.path}/Podfile').existsSync(), isTrue);
    expect(File('${shellMacosRoot.path}/Podfile.lock').existsSync(), isTrue);

    for (final relativePath in <String>[
      'Flutter/Flutter-Debug.xcconfig',
      'Flutter/Flutter-Release.xcconfig',
      'Runner.xcworkspace/contents.xcworkspacedata',
      'Runner.xcodeproj/project.pbxproj',
    ]) {
      final source = File('${macosRoot.path}/$relativePath').readAsStringSync();
      expect(source, isNot(contains('Pods')));
      expect(source, isNot(contains('PODS_ROOT')));
      expect(source, isNot(contains('[CP]')));
    }

    final project = File(
      '${macosRoot.path}/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    expect(project, contains('FlutterGeneratedPluginSwiftPackage'));
  });

  test('example iOS project uses SwiftPM without CocoaPods integration', () {
    final iosRoot = Directory('$root/examples/cockpit_demo/ios');

    expect(File('${iosRoot.path}/Podfile').existsSync(), isFalse);
    expect(File('${iosRoot.path}/Podfile.lock').existsSync(), isFalse);

    final shellIosRoot = Directory('$root/examples/cockpit_demo/cockpit/ios');
    expect(File('${shellIosRoot.path}/Podfile').existsSync(), isTrue);
    expect(
      File(
        '${shellIosRoot.path}/Runner.xcodeproj/project.pbxproj',
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        '${shellIosRoot.path}/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync(),
      isNot(contains('FlutterGeneratedPluginSwiftPackage')),
    );

    for (final relativePath in <String>[
      'Flutter/Debug.xcconfig',
      'Flutter/Release.xcconfig',
      'Runner.xcworkspace/contents.xcworkspacedata',
      'Runner.xcodeproj/project.pbxproj',
    ]) {
      final source = File('${iosRoot.path}/$relativePath').readAsStringSync();
      expect(source, isNot(contains('Pods')));
      expect(source, isNot(contains('PODS_ROOT')));
      expect(source, isNot(contains('[CP]')));
    }

    final project = File(
      '${iosRoot.path}/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    expect(project, contains('FlutterGeneratedPluginSwiftPackage'));
    expect(
      File(
        '${iosRoot.path}/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme',
      ).readAsStringSync(),
      contains('Run Prepare Flutter Framework Script'),
    );
  });

  test('iOS app and development shell remain 3.32-compatible', () {
    final appRoot = '$root/examples/cockpit_demo/ios/Runner';
    final appDelegate = File('$appRoot/AppDelegate.swift').readAsStringSync();
    final appInfoPlist = File('$appRoot/Info.plist').readAsStringSync();
    expect(
      appDelegate,
      contains('@objc class AppDelegate: FlutterAppDelegate {'),
    );
    expect(
      appDelegate,
      contains('GeneratedPluginRegistrant.register(with: self)'),
    );
    expect(appDelegate, isNot(contains('FlutterImplicitEngineDelegate')));
    expect(appInfoPlist, isNot(contains('UIApplicationSceneManifest')));

    final shellRoot = '$root/examples/cockpit_demo/cockpit/ios/Runner';
    final shellDelegate = File(
      '$shellRoot/AppDelegate.swift',
    ).readAsStringSync();
    final shellInfoPlist = File('$shellRoot/Info.plist').readAsStringSync();
    expect(
      shellDelegate,
      contains('GeneratedPluginRegistrant.register(with: self)'),
    );
    expect(shellDelegate, isNot(contains('FlutterImplicitEngineDelegate')));
    expect(shellInfoPlist, isNot(contains('UIApplicationSceneManifest')));
  });

  test('native plugin sources use flutter_cockpit channel names', () {
    final androidPlugin = File(
      '$root/packages/flutter_cockpit/android/src/main/kotlin/dev/cockpit/flutter_cockpit/FlutterCockpitPlugin.kt',
    );
    final iosPlugin = File(
      '$root/packages/flutter_cockpit/ios/flutter_cockpit/Sources/flutter_cockpit/FlutterCockpitPlugin.swift',
    );
    final macosPlugin = File(
      '$root/packages/flutter_cockpit/macos/flutter_cockpit/Sources/flutter_cockpit/FlutterCockpitPlugin.swift',
    );
    final linuxPlugin = File(
      '$root/packages/flutter_cockpit/linux/flutter_cockpit_plugin.cc',
    );

    expect(androidPlugin.existsSync(), isTrue);
    expect(iosPlugin.existsSync(), isTrue);
    expect(macosPlugin.existsSync(), isTrue);
    expect(linuxPlugin.existsSync(), isTrue);

    final androidSource = androidPlugin.readAsStringSync();
    final iosSource = iosPlugin.readAsStringSync();
    final macosSource = macosPlugin.readAsStringSync();
    final linuxSource = linuxPlugin.readAsStringSync();

    expect(androidSource, contains('dev.cockpit.flutter_cockpit/capture'));
    expect(androidSource, contains('dev.cockpit.flutter_cockpit/recording'));
    expect(iosSource, contains('dev.cockpit.flutter_cockpit/capture'));
    expect(iosSource, contains('dev.cockpit.flutter_cockpit/recording'));
    expect(macosSource, contains('dev.cockpit.flutter_cockpit/capture'));
    expect(macosSource, contains('dev.cockpit.flutter_cockpit/recording'));
    expect(linuxSource, contains('dev.cockpit.flutter_cockpit/capture'));
    expect(linuxSource, contains('dev.cockpit.flutter_cockpit/recording'));
  });

  test('iOS native capture and recording keep lifecycle and path contracts', () {
    final manager = File(
      '$root/packages/flutter_cockpit/ios/flutter_cockpit/Sources/flutter_cockpit/FlutterCockpitRecordingManager.swift',
    ).readAsStringSync();
    final plugin = File(
      '$root/packages/flutter_cockpit/ios/flutter_cockpit/Sources/flutter_cockpit/FlutterCockpitPlugin.swift',
    ).readAsStringSync();

    expect(manager, contains('enum RecordingState'));
    expect(manager, contains('case starting'));
    expect(manager, contains('case recording'));
    expect(manager, contains('case stopping'));
    expect(manager, contains('sessionToken'));
    expect(manager, contains('recordingAlreadyActive'));
    expect(manager, contains('recordingNotReady'));
    expect(manager, contains('recordingAlreadyStopping'));
    expect(manager, contains('recordingNotActive'));
    expect(manager, contains('recordingInvalidPath'));
    expect(manager, contains('resolvingSymlinksInPath'));
    expect(manager, contains('recordingOutputMissing'));
    expect(manager, contains('localizedDescription'));
    expect(plugin, contains('drawSucceeded = window.drawHierarchy'));
    expect(plugin, contains('captureDrawFailed'));
  });

  test(
    'Windows GDI capture makes copied pixels opaque before PNG encoding',
    () {
      final source = File(
        '$root/packages/flutter_cockpit/windows/flutter_cockpit_plugin.cpp',
      ).readAsStringSync();

      final alphaNormalization = source.indexOf('pixels[offset] = 0xFF;');
      final frameCopy = source.indexOf('frame->pixels.assign(');

      expect(alphaNormalization, isNonNegative);
      expect(frameCopy, greaterThan(alphaNormalization));
    },
  );

  test('Android recording source declares lifecycle and cleanup contracts', () {
    final source = File(
      '$root/packages/flutter_cockpit/android/src/main/kotlin/dev/cockpit/flutter_cockpit/FlutterCockpitRecordingCoordinator.kt',
    ).readAsStringSync();
    final pluginSource = File(
      '$root/packages/flutter_cockpit/android/src/main/kotlin/dev/cockpit/flutter_cockpit/FlutterCockpitPlugin.kt',
    ).readAsStringSync();
    final serviceSource = File(
      '$root/packages/flutter_cockpit/android/src/main/kotlin/dev/cockpit/flutter_cockpit/FlutterCockpitRecordingService.kt',
    ).readAsStringSync();

    expect(source, contains('enum class RecordingState'));
    expect(source, contains('Idle'));
    expect(source, contains('Starting'));
    expect(source, contains('Recording'));
    expect(source, contains('Stopping'));
    expect(source, contains('recordingDetached'));
    expect(source, contains('recordingAlreadyStopping'));
    expect(source, contains('recordingNotReady'));
    expect(source, contains('startActivityForResult'));
    expect(source, contains('catch'));
    expect(source, contains('MediaProjectionManager'));
    expect(pluginSource, contains('detachActivityForConfigChanges'));
    expect(pluginSource, contains('detachActivityPermanently'));
    expect(pluginSource, contains('finally'));
    expect(pluginSource, contains('bitmap.recycle()'));
    expect(pluginSource, contains('SurfaceView'));
    expect(pluginSource, contains('findFlutterSurface'));
    expect(
      serviceSource,
      contains('FlutterCockpitRecordingPathResolver.resolve'),
    );
    expect(serviceSource, contains('length() > 0'));
    expect(serviceSource, contains('mutableSetOf<Long>()'));
    expect(serviceSource, contains('resolveSessionTermination'));
    expect(source, contains('completeUnexpectedTermination'));
    expect(
      serviceSource.indexOf('mediaProjection = projection'),
      lessThan(serviceSource.indexOf('projection.registerCallback')),
    );
    expect(
      serviceSource.indexOf('mediaRecorder = recorder'),
      lessThan(serviceSource.indexOf('recorder.prepare()')),
    );
    expect(
      serviceSource.indexOf('projectionCallback = callback'),
      lessThan(serviceSource.indexOf('projection.registerCallback')),
    );
  });

  test('macOS recording source bounds frame work and finalization', () {
    final manager = File(
      '$root/packages/flutter_cockpit/macos/flutter_cockpit/Sources/flutter_cockpit/FlutterCockpitRecordingManager.swift',
    ).readAsStringSync();
    final plugin = File(
      '$root/packages/flutter_cockpit/macos/flutter_cockpit/Sources/flutter_cockpit/FlutterCockpitPlugin.swift',
    ).readAsStringSync();

    expect(manager, contains('enum RecordingState'));
    expect(manager, contains('case starting'));
    expect(manager, contains('case recording'));
    expect(manager, contains('case stopping'));
    expect(manager, contains('sessionToken'));
    expect(manager, contains('recordingAlreadyStopping'));
    expect(manager, contains('recordingInvalidPath'));
    expect(manager, contains('resolvingSymlinksInPath'));
    expect(manager, contains('framePending'));
    expect(manager, contains('reserveFrame'));
    expect(manager, contains('waitForRecordingFile'));
    expect(plugin, contains('queryRecordingCapabilities'));
  });

  test('Linux recording source finalizes asynchronously with safe paths', () {
    final source = File(
      '$root/packages/flutter_cockpit/linux/flutter_cockpit_plugin.cc',
    ).readAsStringSync();
    final cmake = File(
      '$root/packages/flutter_cockpit/linux/CMakeLists.txt',
    ).readAsStringSync();

    expect(source, contains('enum class RecordingState'));
    expect(source, contains('Starting'));
    expect(source, contains('Recording'));
    expect(source, contains('Stopping'));
    expect(source, contains('weakly_canonical'));
    expect(source, contains('recordingInvalidPath'));
    expect(source, contains('HasRecordingPipelineSupport'));
    expect(source, contains('g_main_context_invoke'));
    expect(source, contains('std::thread'));
    expect(cmake, contains('Threads::Threads'));
  });

  test('native package metadata uses flutter_cockpit names', () {
    final podspec = File(
      '$root/packages/flutter_cockpit/ios/flutter_cockpit.podspec',
    ).readAsStringSync();
    final macosPodspec = File(
      '$root/packages/flutter_cockpit/macos/flutter_cockpit.podspec',
    ).readAsStringSync();
    final manifest = File(
      '$root/packages/flutter_cockpit/android/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final androidGradle = File(
      '$root/packages/flutter_cockpit/android/build.gradle',
    ).readAsStringSync();
    final iosPackage = File(
      '$root/packages/flutter_cockpit/ios/flutter_cockpit/Package.swift',
    ).readAsStringSync();
    final macosPackage = File(
      '$root/packages/flutter_cockpit/macos/flutter_cockpit/Package.swift',
    ).readAsStringSync();

    expect(podspec, contains("s.name             = 'flutter_cockpit'"));
    expect(podspec, contains('flutter_cockpit.'));
    expect(podspec, contains('flutter_cockpit/Sources/flutter_cockpit'));
    expect(macosPodspec, contains("s.name             = 'flutter_cockpit'"));
    expect(macosPodspec, contains('flutter_cockpit'));
    expect(macosPodspec, contains('flutter_cockpit/Sources/flutter_cockpit'));
    expect(iosPackage, contains('name: "flutter_cockpit"'));
    expect(iosPackage, contains('.iOS("13.0")'));
    expect(iosPackage, contains('dependencies: []'));
    expect(iosPackage, contains('.process("PrivacyInfo.xcprivacy")'));
    expect(iosPackage, isNot(contains('FlutterFramework')));
    expect(macosPackage, contains('name: "flutter_cockpit"'));
    expect(macosPackage, contains('.macOS("10.15")'));
    expect(macosPackage, contains('dependencies: []'));
    expect(macosPackage, contains('.process("PrivacyInfo.xcprivacy")'));
    expect(macosPackage, isNot(contains('FlutterFramework')));
    expect(manifest, contains('package="dev.cockpit.flutter_cockpit"'));
    expect(
      androidGradle,
      contains('namespace = "dev.cockpit.flutter_cockpit"'),
    );
    expect(androidGradle, isNot(contains('agpMajor < 9')));
    expect(
      androidGradle,
      contains('org.jetbrains.kotlin:kotlin-gradle-plugin'),
    );
    expect(androidGradle, contains('id "org.jetbrains.kotlin.android"'));
    expect(androidGradle, contains('id "com.android.library"'));
    expect(androidGradle, isNot(contains('apply plugin:')));
    expect(androidGradle, contains('KotlinCompile'));
  });
}
