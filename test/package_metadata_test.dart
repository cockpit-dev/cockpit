import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('published packages share the Cockpit 3.0 release version', () {
    final runtimePubspec = File(
      'packages/flutter_cockpit/pubspec.yaml',
    ).readAsStringSync();
    final protocolPubspec = File(
      'packages/cockpit_protocol/pubspec.yaml',
    ).readAsStringSync();
    final devtoolsPubspec = File(
      'packages/cockpit/pubspec.yaml',
    ).readAsStringSync();
    final supervisorRuntime = File(
      'packages/cockpit/lib/src/supervisor/cockpit_supervisor_runtime.dart',
    ).readAsStringSync();
    final runtimeVersion = _readPackageVersion('packages/flutter_cockpit');
    final protocolVersion = _readPackageVersion('packages/cockpit_protocol');
    final devtoolsVersion = _readPackageVersion('packages/cockpit');

    expect(runtimePubspec, contains('name: flutter_cockpit'));
    expect(runtimePubspec, isNot(contains('name: flutter_pilot')));
    expect(protocolPubspec, contains('name: cockpit_protocol'));
    expect(devtoolsPubspec, contains('name: cockpit'));
    expect(runtimeVersion, '3.0.12');
    expect(protocolVersion, '3.0.12');
    expect(devtoolsVersion, '3.0.12');
    expect(runtimePubspec, contains('cockpit_protocol: ^3.0.12'));
    expect(devtoolsPubspec, contains('cockpit_protocol: ^3.0.12'));
    expect(
      supervisorRuntime,
      contains('const cockpitSupervisorEngineVersion = cockpitVersion;'),
    );
    expect(runtimePubspec, isNot(contains('flutter_cockpit_protocol:')));
    expect(devtoolsPubspec, isNot(contains('flutter_cockpit_protocol:')));
    expect(
      devtoolsPubspec,
      isNot(contains('flutter_cockpit: ^$runtimeVersion')),
    );
    expect(
      devtoolsPubspec,
      isNot(contains('flutter:\n    sdk: flutter')),
      reason: 'The hosted cockpit executable must support pub global run.',
    );
    expect(devtoolsPubspec, contains('dart_mcp: ^0.5.2'));
    expect(devtoolsPubspec, isNot(contains('flutter_pilot: ^1.0.0')));
  });

  test('Cockpit V2 barrel exposes only stable case runtime boundaries', () {
    final barrel = File('packages/cockpit/lib/cockpit.dart').readAsStringSync();

    for (final stableExport in <String>[
      'cockpit_test_attempt_bundle_writer.dart',
      'cockpit_active_operation_aborter.dart',
      'cockpit_case_execution_control.dart',
      'cockpit_case_runner.dart',
      'cockpit_control_workflow_importer.dart',
      'cockpit_test_document_compiler.dart',
      'cockpit_test_safety_policy.dart',
      'cockpit_test_secret_resolver.dart',
    ]) {
      expect(barrel, contains(stableExport));
    }
    for (final internalExport in <String>[
      'cockpit_test_attempt_recorder.dart',
      'cockpit_case_execution_kernel.dart',
      'cockpit_test_action_lowerer.dart',
      'cockpit_test_execution_plan.dart',
      'cockpit_test_variable_binder.dart',
    ]) {
      expect(barrel, isNot(contains(internalExport)));
    }
  });

  test('supported Flutter floor matches package, tooling, and CI bounds', () {
    final workspacePubspec = File('pubspec.yaml').readAsStringSync();
    final workspaceLockfile = File('pubspec.lock').readAsStringSync();
    final protocolPubspec = File(
      'packages/cockpit_protocol/pubspec.yaml',
    ).readAsStringSync();
    final runtimePubspec = File(
      'packages/flutter_cockpit/pubspec.yaml',
    ).readAsStringSync();
    final devtoolsPubspec = File(
      'packages/cockpit/pubspec.yaml',
    ).readAsStringSync();
    final demoPubspec = File(
      'examples/cockpit_demo/pubspec.yaml',
    ).readAsStringSync();
    final shellPubspec = File(
      'examples/cockpit_demo/cockpit/pubspec.yaml',
    ).readAsStringSync();
    final consolePubspec = File(
      'packages/cockpit_console/pubspec.yaml',
    ).readAsStringSync();
    final rootReadme = File('README.md').readAsStringSync();
    final rootReadmeZh = File('README.zh-CN.md').readAsStringSync();
    final runtimeReadme = File(
      'packages/flutter_cockpit/README.md',
    ).readAsStringSync();
    final runtimeReadmeZh = File(
      'packages/flutter_cockpit/README.zh-CN.md',
    ).readAsStringSync();
    final devtoolsReadme = File(
      'packages/cockpit/README.md',
    ).readAsStringSync();
    final devtoolsReadmeZh = File(
      'packages/cockpit/README.zh-CN.md',
    ).readAsStringSync();
    final acceptanceWorkflow = File(
      '.github/workflows/example-e2e.yml',
    ).readAsStringSync();
    final devtoolsVersion = _readPackageVersion('packages/cockpit');

    expect(
      workspacePubspec,
      contains('uses-material-design: true'),
      reason:
          'Flutter tests may use the workspace pubspec as the primary manifest; '
          'it must opt into Material Icons when the cockpit_demo workspace '
          'package does.',
    );
    expect(
      runtimePubspec,
      contains('uses-material-design: true'),
      reason:
          'Runtime package widget tests use Material Icons and may treat '
          'workspace packages as dependencies during asset assembly.',
    );
    for (final pubspec in <String>[
      workspacePubspec,
      protocolPubspec,
      runtimePubspec,
      devtoolsPubspec,
      demoPubspec,
      shellPubspec,
      consolePubspec,
    ]) {
      expect(pubspec, contains("sdk: '>=3.8.0 <4.0.0'"));
      expect(pubspec, isNot(contains("sdk: '>=3.5.0 <4.0.0'")));
      expect(pubspec, isNot(contains("sdk: '>=3.6.0 <4.0.0'")));
      expect(pubspec, isNot(contains("sdk: '>=3.7.0 <4.0.0'")));
    }
    expect(runtimePubspec, contains("flutter: '>=3.32.0'"));
    expect(demoPubspec, contains("flutter: '>=3.32.0'"));
    expect(shellPubspec, contains("flutter: '>=3.32.0'"));
    expect(consolePubspec, contains("flutter: '>=3.44.0'"));
    if (Platform.version.startsWith('3.8.')) {
      expect(workspaceLockfile, contains('dart: ">=3.8.0 <4.0.0"'));
      expect(workspaceLockfile, contains('flutter: ">=3.32.0"'));
      expect(workspaceLockfile, isNot(contains('>=3.10.0-0')));
    }
    expect(acceptanceWorkflow, contains("MINIMUM_FLUTTER_VERSION: '3.32.0'"));
    expect(acceptanceWorkflow, contains("CURRENT_FLUTTER_VERSION: '3.44.0'"));
    for (final job in const <String>[
      'static_analysis',
      'minimum_flutter',
      'dart_tests',
      'flutter_tests',
      'publication',
      'darwin_packaging',
      'regression',
      'release_gate',
    ]) {
      expect(acceptanceWorkflow, contains('\n  $job:\n'));
    }
    expect(
      RegExp(
        'prepare-minimum-flutter-workspace\\.sh',
      ).allMatches(acceptanceWorkflow),
      hasLength(5),
    );
    expect(acceptanceWorkflow, isNot(contains('needs: quality')));
    expect(
      RegExp('--require-recording').allMatches(acceptanceWorkflow),
      hasLength(2),
    );
    expect(rootReadme, contains('Flutter 3.32.0'));
    expect(rootReadme, contains('Dart 3.8.0'));
    expect(rootReadmeZh, contains('Flutter 3.32.0'));
    expect(rootReadmeZh, contains('Dart 3.8.0'));
    expect(runtimeReadme, contains('Flutter 3.32.0'));
    expect(runtimeReadmeZh, contains('Flutter 3.32.0'));
    expect(devtoolsReadme, contains('Dart 3.8.0'));
    expect(devtoolsReadme, contains('Flutter 3.32.0'));
    expect(devtoolsReadmeZh, contains('Dart 3.8.0'));
    expect(devtoolsReadmeZh, contains('Flutter 3.32.0'));
    expect(workspacePubspec, contains('lints: ^6.1.0'));
    expect(protocolPubspec, contains('lints: ^6.1.0'));
    expect(
      workspacePubspec,
      contains('melos: 6.3.3'),
      reason:
          'melos 7.7.0 requires Dart 3.9+, but this package supports Dart 3.8.',
    );
    expect(runtimePubspec, contains('web_socket_channel: ^3.0.3'));
    expect(runtimePubspec, contains('flutter_lints: ^6.0.0'));
    expect(protocolPubspec, contains('collection: ^1.19.1'));
    expect(devtoolsPubspec, contains('lints: ^6.1.0'));
    expect(demoPubspec, contains('flutter_lints: ^6.0.0'));
    expect(devtoolsPubspec, contains('dart_mcp: ^0.5.2'));
    expect(shellPubspec, contains('cockpit: ^$devtoolsVersion'));
    expect(shellPubspec, contains('flutter_cockpit:'));
    expect(shellPubspec, contains('integration_test:'));
    expect(demoPubspec, isNot(contains('flutter_cockpit:')));
    expect(demoPubspec, isNot(contains('cockpit:')));
    expect(demoPubspec, isNot(contains('integration_test:')));
    expect(
      demoPubspec,
      contains('drift: ">=2.29.0 <2.30.0"'),
      reason:
          'drift 2.30+ pulls analyzer 8.x constraints that do not solve '
          'with Flutter 3.32 flutter_test/test_api pins.',
    );
    expect(demoPubspec, contains('drift_flutter: ">=0.2.7 <0.2.8"'));
    expect(
      demoPubspec,
      contains('drift_dev: ">=2.29.0 <2.30.0"'),
      reason:
          'drift_dev 2.30+ requires analyzer >=8.1, but Flutter 3.32 '
          'resolves test 1.25.15 with analyzer <8.0.',
    );
    expect(demoPubspec, contains('sqlite3: ">=2.9.4 <3.0.0"'));
    expect(demoPubspec, contains('sqlite3_flutter_libs: ">=0.5.42 <0.6.0"'));
    expect(workspacePubspec, contains("test: '>=1.25.15 <2.0.0'"));
    expect(runtimePubspec, contains("test: '>=1.25.15 <2.0.0'"));
    expect(devtoolsPubspec, contains("test: '>=1.25.15 <2.0.0'"));
  });

  test('package readmes teach flutter_cockpit installation and usage', () {
    final runtimeReadme = File(
      'packages/flutter_cockpit/README.md',
    ).readAsStringSync();
    final runtimeReadmeZh = File(
      'packages/flutter_cockpit/README.zh-CN.md',
    ).readAsStringSync();
    final devtoolsReadme = File(
      'packages/cockpit/README.md',
    ).readAsStringSync();
    final devtoolsReadmeZh = File(
      'packages/cockpit/README.zh-CN.md',
    ).readAsStringSync();

    expect(runtimeReadme, contains('<h1>flutter_cockpit</h1>'));
    expect(runtimeReadme, contains('flutter_cockpit: any'));
    expect(
      runtimeReadme,
      contains("package:flutter_cockpit/flutter_cockpit_flutter.dart"),
    );
    expect(runtimeReadme, contains('cd cockpit'));
    expect(runtimeReadme, contains('--target main.dart'));
    expect(runtimeReadme, contains('https://pub.dev/packages/cockpit'));
    expect(runtimeReadme, isNot(contains('flutter_pilot')));

    expect(devtoolsReadme, contains('<h1>cockpit</h1>'));
    expect(devtoolsReadme, contains('dart pub global activate cockpit any'));
    expect(devtoolsReadme, isNot(contains('dart run cockpit')));
    expect(devtoolsReadme, contains('serve-mcp'));
    expect(devtoolsReadme, contains('cockpit_mcp'));
    expect(devtoolsReadme, contains('case validate'));
    expect(devtoolsReadme, contains('suite run'));
    expect(devtoolsReadme, contains('/api/v2'));
    expect(devtoolsReadme, isNot(contains('flutter_pilot_devtools')));
    expect(devtoolsReadme, isNot(contains('flutter_pilot')));

    expect(runtimeReadmeZh, contains('flutter_cockpit: any'));
    expect(runtimeReadmeZh, contains('https://pub.dev/packages/cockpit'));
    expect(devtoolsReadmeZh, contains('dart pub global activate cockpit any'));
  });

  test('setup docs keep cockpit wiring outside production lib code', () {
    final rootReadme = File('README.md').readAsStringSync();
    final runtimeReadme = File(
      'packages/flutter_cockpit/README.md',
    ).readAsStringSync();
    final skill = File('skills/cockpit/SKILL.md').readAsStringSync();

    for (final document in <String>[rootReadme, runtimeReadme]) {
      expect(
        document,
        contains(
          'Do not add `flutter_cockpit` imports to production `lib/` code',
        ),
      );
    }
    expect(
      skill,
      contains('production Flutter code must not import the bridge package'),
    );
  });

  test('demo keeps cockpit integration out of production lib code', () {
    final productionPubspec = File(
      'examples/cockpit_demo/pubspec.yaml',
    ).readAsStringSync();
    final shellPubspec = File(
      'examples/cockpit_demo/cockpit/pubspec.yaml',
    ).readAsStringSync();
    final devDependenciesIndex = shellPubspec.indexOf('dev_dependencies:');

    expect(devDependenciesIndex, isNonNegative);
    expect(
      shellPubspec.indexOf('  flutter_cockpit:'),
      greaterThan(devDependenciesIndex),
    );
    expect(
      shellPubspec.indexOf('  cockpit:'),
      greaterThan(devDependenciesIndex),
    );
    expect(
      shellPubspec.indexOf('  integration_test:'),
      greaterThan(devDependenciesIndex),
    );
    expect(productionPubspec, isNot(contains('flutter_cockpit:')));
    expect(productionPubspec, isNot(contains('cockpit:')));
    expect(productionPubspec, isNot(contains('integration_test:')));

    for (final file
        in Directory('examples/cockpit_demo/lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(contains('package:flutter_cockpit/')),
        reason: '${file.path} must remain production-only.',
      );
      expect(
        source,
        isNot(contains('package:cockpit/')),
        reason: '${file.path} must remain production-only.',
      );
    }
  });

  test('published package readme language links target repository files', () {
    final runtimeReadme = File(
      'packages/flutter_cockpit/README.md',
    ).readAsStringSync();
    final runtimeReadmeZh = File(
      'packages/flutter_cockpit/README.zh-CN.md',
    ).readAsStringSync();
    final devtoolsReadme = File(
      'packages/cockpit/README.md',
    ).readAsStringSync();
    final devtoolsReadmeZh = File(
      'packages/cockpit/README.zh-CN.md',
    ).readAsStringSync();

    expect(runtimeReadme, isNot(contains('](README.zh-CN.md)')));
    expect(devtoolsReadme, isNot(contains('](README.zh-CN.md)')));
    expect(runtimeReadmeZh, isNot(contains('](README.md)')));
    expect(devtoolsReadmeZh, isNot(contains('](README.md)')));

    expect(
      runtimeReadme,
      contains(
        'https://github.com/cockpit-dev/cockpit/blob/main/packages/flutter_cockpit/README.zh-CN.md',
      ),
    );
    expect(
      devtoolsReadme,
      contains(
        'https://github.com/cockpit-dev/cockpit/blob/main/packages/cockpit/README.zh-CN.md',
      ),
    );
    expect(
      runtimeReadmeZh,
      contains(
        'https://github.com/cockpit-dev/cockpit/blob/main/packages/flutter_cockpit/README.md',
      ),
    );
    expect(
      devtoolsReadmeZh,
      contains(
        'https://github.com/cockpit-dev/cockpit/blob/main/packages/cockpit/README.md',
      ),
    );
  });

  test('published packages exclude local-only editor metadata', () {
    for (final packageDir in <String>[
      'packages/flutter_cockpit',
      'packages/cockpit',
    ]) {
      final pubignore = File('$packageDir/.pubignore').readAsStringSync();
      expect(pubignore, contains('*.iml'));
    }
  });

  test('published packages include package-local examples', () {
    final runtimeExample = File('packages/flutter_cockpit/example/main.dart');
    final devtoolsExample = File('packages/cockpit/example/main.dart');
    final caseYaml = File('packages/cockpit/example/cases/flutter_login.yaml');
    final caseJson = File('packages/cockpit/example/cases/flutter_login.json');
    final caseSchema = File(
      'packages/cockpit_protocol/schema/cockpit.test.v2.schema.json',
    );
    final foundationExample = File(
      'packages/cockpit_protocol/example/foundation_contract.dart',
    );
    final foundationSchema = File(
      'packages/cockpit_protocol/schema/cockpit.foundation.v2.schema.json',
    );
    final foundationOpenApi = File(
      'packages/cockpit_protocol/openapi/cockpit.v2.openapi.json',
    );

    expect(runtimeExample.existsSync(), isTrue);
    expect(devtoolsExample.existsSync(), isTrue);
    expect(caseYaml.existsSync(), isTrue);
    expect(caseJson.existsSync(), isTrue);
    expect(caseSchema.existsSync(), isTrue);
    expect(foundationExample.existsSync(), isTrue);
    expect(foundationSchema.existsSync(), isTrue);
    expect(foundationOpenApi.existsSync(), isTrue);

    final runtimeSource = runtimeExample.readAsStringSync();
    final devtoolsSource = devtoolsExample.readAsStringSync();

    expect(
      runtimeSource,
      contains("package:flutter_cockpit/flutter_cockpit_flutter.dart"),
    );
    expect(
      runtimeSource,
      contains('CockpitRemoteSessionConfiguration.resolveFromEnvironment'),
    );
    expect(runtimeSource, contains('FlutterCockpit.navigatorObserver'));
    expect(runtimeSource, contains('FlutterCockpit.setCurrentRouteName'));

    expect(devtoolsSource, contains("package:cockpit/cockpit.dart"));
    expect(devtoolsSource, contains('CockpitCommandRunner'));
    expect(devtoolsSource, contains('cockpit dev start'));
    expect(devtoolsSource, contains('cockpit dev status'));
    expect(devtoolsSource, contains('cockpit dev inspect'));
    expect(devtoolsSource, contains('case list'));
    expect(devtoolsSource, contains('cockpit_mcp'));
  });

  test(
    'pure Dart runtime export does not expose dart:io implementation files',
    () {
      final exportGraph = _runtimeLibraryGraph();
      expect(
        exportGraph,
        isNot(contains('src/network/cockpit_http_network_observer.dart')),
        reason:
            'package:flutter_cockpit/flutter_cockpit.dart is consumed by host '
            'tools and web model code; dart:io observers belong in the Flutter '
            'entrypoint export.',
      );
    },
  );

  test(
    'published cockpit readmes do not present pubignored tools as package commands',
    () {
      final devtoolsReadme = File(
        'packages/cockpit/README.md',
      ).readAsStringSync();
      final devtoolsReadmeZh = File(
        'packages/cockpit/README.zh-CN.md',
      ).readAsStringSync();

      for (final document in <String>[devtoolsReadme, devtoolsReadmeZh]) {
        expect(
          document,
          isNot(contains('dart run tool/verify_mcp_surface.dart')),
        );
        expect(document, contains('github.com/cockpit-dev/cockpit'));
      }
    },
  );

  test('devtools package includes MCP contract fallback documents', () {
    final contractFiles = <String>[
      'ai-development-protocol.md',
      'cockpit-protocol.md',
      'cockpit-skill-contract.md',
    ];

    for (final fileName in contractFiles) {
      final rootContract = File('docs/contracts/$fileName');
      final packageContract = File('packages/cockpit/doc/contracts/$fileName');
      expect(packageContract.existsSync(), isTrue);
      expect(
        packageContract.readAsBytesSync(),
        rootContract.readAsBytesSync(),
        reason:
            'MCP workspace contract resources must work from a published '
            'cockpit package with the same contract text as the monorepo root.',
      );
    }

    for (final retiredFile in <String>[
      'task-run-bundle.md',
      'control-workflow-protocol.md',
      'control-workflow.schema.json',
    ]) {
      expect(File('docs/contracts/$retiredFile').existsSync(), isFalse);
      expect(
        File('packages/cockpit/doc/contracts/$retiredFile').existsSync(),
        isFalse,
      );
    }
  });

  test('cockpit skill exposes a local protocol reference', () {
    final skill = File('skills/cockpit/SKILL.md').readAsStringSync();
    final protocolReference = File(
      'skills/cockpit/references/protocol.md',
    ).readAsStringSync();
    final testSchema = File(
      'skills/cockpit/references/cockpit.test.v2.schema.json',
    );

    expect(skill, contains('references/protocol.md'));
    expect(protocolReference, contains('## Runtime Authorities'));
    expect(protocolReference, contains('cockpit.test.v2.schema.json'));
    expect(protocolReference, contains('## Command Map'));
    expect(protocolReference, isNot(contains('packages/cockpit')));
    expect(protocolReference, isNot(contains('docs/contracts/')));
    expect(testSchema.existsSync(), isTrue);
  });

  test('agent integrations use installed executables and bundled skills', () {
    for (final path in <String>[
      '.mcp.json',
      '.cursor/mcp.json',
      '.gemini/settings.json',
      '.kiro/settings/mcp.json',
      '.omp/mcp.json',
      'opencode.json',
      'plugins/codex/cockpit/.mcp.json',
      'plugins/claude-code/cockpit/.mcp.json',
      'plugins/kiro/cockpit/mcp.json',
    ]) {
      final config = File(path).readAsStringSync();
      expect(config, contains('cockpit_mcp'), reason: path);
      expect(config, isNot(contains('dart run cockpit')), reason: path);
    }

    final cursorRule = File('.cursor/rules/cockpit.mdc').readAsStringSync();
    final kiroSteering = File('.kiro/steering/cockpit.md').readAsStringSync();
    final kiroPlugin = File(
      'plugins/kiro/cockpit/plugin.json',
    ).readAsStringSync();
    expect(cursorRule, contains('.cursor/skills/cockpit/SKILL.md'));
    expect(cursorRule, isNot(contains('dart run cockpit')));
    expect(kiroSteering, contains('.kiro/skills/cockpit/SKILL.md'));
    expect(kiroSteering, isNot(contains('dart run cockpit')));
    expect(kiroPlugin, contains('agent-plugins.org/schemas/1.0.0'));
    expect(kiroPlugin, contains('"version": "3.0.12"'));

    for (final path in <String>[
      'plugins/codex/cockpit/README.md',
      'plugins/claude-code/cockpit/README.md',
    ]) {
      final readme = File(path).readAsStringSync();
      expect(readme, contains('dart pub global activate cockpit any'));
      expect(readme, contains('cockpit_mcp'));
    }
  });

  test('cockpit package readmes expose the v2 API contract', () {
    final devtoolsReadme = File(
      'packages/cockpit/README.md',
    ).readAsStringSync();
    final devtoolsReadmeZh = File(
      'packages/cockpit/README.zh-CN.md',
    ).readAsStringSync();

    for (final document in <String>[devtoolsReadme, devtoolsReadmeZh]) {
      expect(document, contains('/api/v2'));
      expect(document, contains('CockpitSupervisorApiClient'));
      expect(document, contains('targets'));
      expect(document, contains('suites'));
      expect(document, contains('runs'));
      expect(document, contains('artifacts'));
      expect(document, contains('cockpit_mcp'));
      expect(document, isNot(contains('control-workflow')));
      expect(document, isNot(contains('run-script --script')));
    }
  });

  test('devtools package ships a copyable MCP config example', () {
    final example = File('packages/cockpit/example/mcp_config.json');
    expect(example.existsSync(), isTrue);
    expect(
      example.readAsStringSync(),
      allOf(
        contains('"mcpServers"'),
        contains('"cockpit"'),
        contains('"command": "cockpit_mcp"'),
        contains('"cockpit_mcp"'),
      ),
    );
  });

  test('tracked repository markdown local links resolve', () {
    final missingLinks = _localMarkdownLinkIssues();
    expect(missingLinks, isEmpty, reason: missingLinks.join('\n'));
  });

  test('cockpit demo web database assets match resolved dependencies', () {
    final lockfile = File('pubspec.lock').readAsStringSync();
    final sourceMap = File(
      'examples/cockpit_demo/web/drift_worker.js.map',
    ).readAsStringSync();
    final wasm = File('examples/cockpit_demo/web/sqlite3.wasm');
    final wasmHeader = wasm.readAsBytesSync().take(4).toList();

    final driftVersion = _readLockfilePackageVersion(lockfile, 'drift');
    final sqliteVersion = _readLockfilePackageVersion(lockfile, 'sqlite3');

    expect(sourceMap, contains('/drift-$driftVersion/'));
    expect(sourceMap, contains('/sqlite3-$sqliteVersion/'));
    expect(wasm.existsSync(), isTrue);
    expect(wasm.lengthSync(), greaterThan(512 * 1024));
    expect(wasmHeader, equals(<int>[0x00, 0x61, 0x73, 0x6d]));
  });

  test('Windows acceptance workspace is owned by the current runner', () {
    final workflow = File(
      '.github/workflows/example-e2e.yml',
    ).readAsStringSync();

    expect(workflow, contains(r'$owner = "$env:USERDOMAIN\$env:USERNAME"'));
    expect(
      workflow,
      contains(r'& icacls.exe $workspace /setowner $owner /T /C'),
    );
    expect(
      workflow,
      contains(r'if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }'),
    );
  });
}

String _readPackageVersion(String packageDir) {
  final pubspec = File('$packageDir/pubspec.yaml').readAsStringSync();
  final match = RegExp(
    r'^version:\s+([0-9]+\.[0-9]+\.[0-9]+)$',
    multiLine: true,
  ).firstMatch(pubspec);
  if (match == null) {
    throw StateError('Unable to read version from $packageDir/pubspec.yaml');
  }
  return match.group(1)!;
}

Set<String> _runtimeLibraryGraph() {
  final visited = <String>{};
  final pending = <String>['packages/flutter_cockpit/lib/flutter_cockpit.dart'];
  while (pending.isNotEmpty) {
    final path = pending.removeLast();
    if (!visited.add(path)) {
      continue;
    }
    final file = File(path);
    if (!file.existsSync()) {
      continue;
    }
    final source = file.readAsStringSync();
    for (final match in RegExp(
      r"(?:export|import)\s+'([^']+)';",
    ).allMatches(source)) {
      final rawTarget = match.group(1)!;
      if (rawTarget.startsWith('dart:') || rawTarget.startsWith('package:')) {
        continue;
      }
      if (!rawTarget.endsWith('.dart')) {
        continue;
      }
      final resolved = rawTarget.startsWith('src/')
          ? 'packages/flutter_cockpit/lib/$rawTarget'
          : _normalizePackagePath('${file.parent.path}/$rawTarget');
      pending.add(resolved);
    }
  }
  return visited
      .map((path) => path.replaceFirst('packages/flutter_cockpit/lib/', ''))
      .toSet();
}

String _normalizePackagePath(String path) {
  final segments = <String>[];
  for (final segment in path.split('/')) {
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      if (segments.isNotEmpty) {
        segments.removeLast();
      }
      continue;
    }
    segments.add(segment);
  }
  return segments.join('/');
}

List<String> _localMarkdownLinkIssues() {
  final files = _trackedMarkdownFiles();
  final missing = <String>[];
  for (final path in files) {
    final markdown = _stripMarkdownCode(File(path).readAsStringSync());
    final linkPattern = RegExp(r'!?\[[^\]]+\]\(([^)\s]+)(?:\s+"[^"]*")?\)');
    for (final match in linkPattern.allMatches(markdown)) {
      final rawLink = match.group(1)!.trim();
      if (_isExternalOrAnchorLink(rawLink)) {
        continue;
      }
      final targetPath = Uri.decodeComponent(rawLink).split('#').first;
      if (targetPath.isEmpty) {
        continue;
      }
      final resolvedPath = targetPath.startsWith('/')
          ? targetPath.substring(1)
          : '${File(path).parent.path}/$targetPath';
      if (!File(resolvedPath).existsSync() &&
          !Directory(resolvedPath).existsSync()) {
        missing.add('$path -> $rawLink ($resolvedPath)');
      }
    }
  }
  return missing;
}

List<String> _trackedMarkdownFiles() {
  final result = Process.runSync('git', <String>['ls-files', '*.md']);
  if (result.exitCode != 0) {
    throw StateError('Unable to list tracked markdown files: ${result.stderr}');
  }
  final tracked = (result.stdout as String)
      .split('\n')
      .where((path) => path.endsWith('.md'))
      .where((path) => !path.split('/').contains('third'))
      .where((path) => File(path).existsSync())
      .toList();
  final shellValidationReadme =
      'examples/cockpit_demo/cockpit/validation/README.md';
  if (File(shellValidationReadme).existsSync()) {
    tracked.add(shellValidationReadme);
  }
  return tracked;
}

String _stripMarkdownCode(String markdown) {
  final withoutFencedBlocks = markdown.replaceAll(
    RegExp(r'```[\s\S]*?```'),
    '',
  );
  return withoutFencedBlocks.replaceAll(RegExp(r'`[^`\n]*`'), '');
}

bool _isExternalOrAnchorLink(String link) {
  if (link.startsWith('#')) {
    return true;
  }
  return RegExp(r'^[a-z][a-z0-9+.-]*:').hasMatch(link);
}

String _readLockfilePackageVersion(String lockfile, String packageName) {
  final match = RegExp(
    '^  ${RegExp.escape(packageName)}:\\n'
    r'(?:    .+\n)*?'
    r'    version: "([^"]+)"',
    multiLine: true,
  ).firstMatch(lockfile);
  if (match == null) {
    throw StateError('Unable to read $packageName from pubspec.lock');
  }
  return match.group(1)!;
}
