import 'dart:convert';
import 'dart:io';

import 'package:cockpit/cockpit.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory.current.absolute.path;

  test('root README uses Cockpit branding and the project logo', () {
    final readme = File('$root/README.md').readAsStringSync();
    final logo = File('$root/assets/brand/cockpit-mark.svg');
    final rasterLogo = File('$root/assets/brand/cockpit-mark.png');

    expect(readme, contains('<h1>Cockpit</h1>'));
    expect(readme, contains('assets/brand/cockpit-mark.svg'));
    expect(readme, contains('packages/flutter_cockpit'));
    expect(readme, contains('docs/agent-integrations.md'));
    expect(readme, isNot(contains('packages/flutter_pilot`')));
    expect(readme, isNot(contains('skills/flutter-pilot')));
    expect(logo.existsSync(), isTrue);
    expect(rasterLogo.existsSync(), isTrue);
    expect(
      logo.readAsStringSync(),
      contains('<title id="title">Cockpit</title>'),
    );
  });

  test('active skill assets use Cockpit branding and paths', () {
    final skillDir = Directory('$root/skills/cockpit');
    final legacySkillDir = Directory('$root/skills/flutter-pilot');
    final skill = File('$root/skills/cockpit/SKILL.md').readAsStringSync();
    final agent = File(
      '$root/skills/cockpit/agents/openai.yaml',
    ).readAsStringSync();
    final contract = File(
      '$root/docs/contracts/cockpit-skill-contract.md',
    ).readAsStringSync();

    expect(skillDir.existsSync(), isTrue);
    expect(legacySkillDir.existsSync(), isFalse);
    expect(skill, contains('name: cockpit'));
    expect(skill, contains('# Cockpit'));
    expect(agent, contains('display_name: "Cockpit"'));
    expect(skill, isNot(contains('name: flutter-pilot')));
    expect(contract, contains('# Cockpit Skill Contract'));
    expect(contract, isNot(contains('`flutter-pilot` skill')));
  });

  test('public Cockpit branding is release-version independent', () {
    final publicFiles = <String>[
      'README.md',
      'README.zh-CN.md',
      'packages/cockpit/README.md',
      'packages/cockpit/README.zh-CN.md',
      'packages/cockpit_protocol/README.md',
      'packages/flutter_cockpit/README.md',
      'packages/flutter_cockpit/README.zh-CN.md',
      'skills/cockpit/SKILL.md',
      'plugins/codex/cockpit/.codex-plugin/plugin.json',
      'plugins/claude-code/cockpit/.claude-plugin/plugin.json',
      '.github/workflows/example-e2e.yml',
      'examples/cockpit_demo/cockpit/tool/verify.dart',
      'examples/cockpit_demo/cockpit/e2e/suites/regression.suite.yaml',
    ];
    final versionedBrand = RegExp(
      r'\bCockpit(?:[\s_-]+v?)\d+(?:\.\d+){0,2}\b',
      caseSensitive: false,
    );

    for (final relativePath in publicFiles) {
      expect(
        File('$root/$relativePath').readAsStringSync(),
        isNot(matches(versionedBrand)),
        reason: '$relativePath binds permanent branding to a release version.',
      );
    }
  });

  test('active docs and launchers use flutter_cockpit dart defines', () {
    final files = <String>[
      'README.md',
      'README.zh-CN.md',
      'packages/flutter_cockpit/README.md',
      'packages/flutter_cockpit/README.zh-CN.md',
      'skills/cockpit/SKILL.md',
      'packages/flutter_cockpit/lib/src/remote/cockpit_remote_session_configuration.dart',
      'packages/flutter_cockpit/lib/src/runtime/cockpit_runtime_environment.dart',
      'packages/cockpit/lib/src/development/cockpit_development_session_machine_launcher.dart',
      'packages/cockpit/lib/src/session/cockpit_android_remote_session_launcher.dart',
      'packages/cockpit/lib/src/session/cockpit_ios_physical_remote_session_launcher.dart',
      'packages/cockpit/lib/src/session/cockpit_ios_simulator_remote_session_launcher.dart',
      'packages/cockpit/lib/src/session/cockpit_linux_remote_session_launcher.dart',
      'packages/cockpit/lib/src/session/cockpit_macos_remote_session_launcher.dart',
      'packages/cockpit/lib/src/session/cockpit_windows_remote_session_launcher.dart',
    ];

    for (final relativePath in files) {
      final content = File('$root/$relativePath').readAsStringSync();
      expect(
        content,
        isNot(contains('FLUTTER_PILOT')),
        reason: '$relativePath still exposes legacy dart-define branding.',
      );
    }

    final runtimeConfig = File(
      '$root/packages/cockpit_protocol/lib/src/remote/cockpit_remote_session_configuration.dart',
    ).readAsStringSync();
    expect(runtimeConfig, contains('FLUTTER_COCKPIT_REMOTE_ENABLED'));
    expect(runtimeConfig, contains('FLUTTER_COCKPIT_REMOTE_HOST'));
    expect(runtimeConfig, contains('FLUTTER_COCKPIT_REMOTE_PORT'));
    expect(runtimeConfig, contains('FLUTTER_COCKPIT_REMOTE_ROUTE_PREFIX'));

    final runtimeEnvironment = File(
      '$root/packages/flutter_cockpit/lib/src/runtime/cockpit_runtime_environment.dart',
    ).readAsStringSync();
    expect(runtimeEnvironment, contains('FLUTTER_COCKPIT_FLUTTER_VERSION'));
  });

  test('active package trees do not keep legacy flutter_pilot filenames', () {
    final packageRoots = <Directory>[
      Directory('$root/packages/flutter_cockpit'),
      Directory('$root/packages/cockpit'),
    ];

    final legacyPaths = packageRoots
        .expand((directory) => directory.listSync(recursive: true))
        .whereType<FileSystemEntity>()
        .map((entity) => _relativePath(entity.absolute.path, root))
        .where(
          (path) =>
              path.contains('flutter_pilot') || path.contains('flutter-pilot'),
        )
        .toList(growable: false);

    expect(legacyPaths, isEmpty);
  });

  test('root readmes teach the Cockpit resource workflow', () {
    final readme = File('$root/README.md').readAsStringSync();
    final readmeZh = File('$root/README.zh-CN.md').readAsStringSync();
    final packageReadme = File(
      '$root/packages/cockpit/README.md',
    ).readAsStringSync();
    final packageReadmeZh = File(
      '$root/packages/cockpit/README.zh-CN.md',
    ).readAsStringSync();

    for (final document in <String>[readme, readmeZh]) {
      expect(document, contains('daemon start'));
      expect(document, contains('workspace register'));
      expect(document, contains('target register'));
      expect(document, contains('case run'));
      expect(document, contains('suite run'));
      expect(document, contains('/api/v2'));
      expect(document, isNot(contains('app.json')));
      expect(document, isNot(contains('run-task')));
      expect(document, isNot(contains('validate-task')));
    }
    expect(readme, contains('workspaces for routine `cockpit dev`'));
    expect(packageReadme, contains('routine development never needs'));
    expect(readmeZh, contains('日常使用 `cockpit dev` 无需'));
    expect(packageReadmeZh, contains('日常开发无需'));
    expect(readme, contains('`--session HANDLE` targets only that command'));
    expect(readmeZh, contains('显式 `--session HANDLE` 只作用于当前命令'));
    for (final document in <String>[
      readme,
      readmeZh,
      packageReadme,
      packageReadmeZh,
    ]) {
      expect(document, contains('development session'));
    }
  });

  test('root authorization examples match the live policy schema', () {
    for (final path in <String>['README.md', 'README.zh-CN.md']) {
      final document = File('$root/$path').readAsStringSync();
      final policySource = RegExp(r'```json\n([\s\S]*?)\n```')
          .allMatches(document)
          .map((match) => match.group(1)!)
          .firstWhere(
            (source) => source.contains('cockpit.supervisor.authorization/v2'),
          );
      final policy = CockpitSupervisorAuthorizationPolicy.fromJson(
        jsonDecode(policySource),
      );

      expect(policy.allowedEnvironmentSecretNames, isEmpty, reason: path);
    }
  });

  test('public docs distinguish control planes from system actions', () {
    final documents = <String>[
      File('$root/README.md').readAsStringSync(),
      File('$root/README.zh-CN.md').readAsStringSync(),
      File('$root/skills/cockpit/references/dev.md').readAsStringSync(),
      File('$root/skills/cockpit/references/flutter.md').readAsStringSync(),
    ];

    for (final document in documents) {
      expect(document, isNot(contains('native/system')));
      expect(document, isNot(contains('accessibility、system、visual')));
      expect(document, isNot(contains('accessibility, system, visual')));
    }
  });

  test('protocol docs preserve negotiated response compatibility', () {
    final protocol = File(
      '$root/docs/contracts/cockpit-protocol.md',
    ).readAsStringSync();

    expect(protocol, contains('Requests and strict responses reject'));
    expect(protocol, contains('Negotiated responses may ignore additive'));
    expect(protocol, contains('corresponding feature was negotiated'));
  });

  test('readmes document the public MCP control surface by category', () {
    final readmes = <String, String>{
      'README.md': File('$root/README.md').readAsStringSync(),
      'README.zh-CN.md': File('$root/README.zh-CN.md').readAsStringSync(),
      'packages/cockpit/README.md': File(
        '$root/packages/cockpit/README.md',
      ).readAsStringSync(),
      'packages/cockpit/README.zh-CN.md': File(
        '$root/packages/cockpit/README.zh-CN.md',
      ).readAsStringSync(),
    };
    for (final entry in readmes.entries) {
      for (final resource in const <String>[
        'roots',
        'workspaces',
        'operations',
        'targets',
        'documents',
        'cases',
        'suites',
        'runs',
        'artifacts',
      ]) {
        expect(
          entry.value,
          contains(resource),
          reason: '${entry.key} does not document MCP resource $resource.',
        );
      }
      expect(entry.value, contains('/api/v2'));
      expect(entry.value, contains('Supervisor'));
      expect(entry.value, isNot(contains('`run_task`')));
      expect(entry.value, isNot(contains('`validate_task`')));
    }
  });

  test('cockpit readmes keep the v2 API boundary explicit', () {
    final readme = File('$root/packages/cockpit/README.md').readAsStringSync();
    final readmeZh = File(
      '$root/packages/cockpit/README.zh-CN.md',
    ).readAsStringSync();
    for (final content in <String>[readme, readmeZh]) {
      expect(content, contains('/api/v2'));
      expect(content, contains('cockpit_mcp'));
      expect(content, contains('index.html'));
      expect(content, isNot(contains('run-script --script')));
      expect(content, isNot(contains('control-workflow')));
    }
  });

  test('tracked text files do not keep TODO or FIXME markers', () {
    final trackedFilesResult = Process.runSync('git', const <String>[
      'ls-files',
    ], workingDirectory: root);

    expect(trackedFilesResult.exitCode, 0);

    final offenders = <String>[];
    for (final relativePath
        in (trackedFilesResult.stdout as String)
            .split('\n')
            .where((path) => path.trim().isNotEmpty)
            .where(_isScannableTextFile)) {
      final file = File('$root/$relativePath');
      if (!file.existsSync()) {
        continue;
      }
      final content = _tryReadUtf8Text(file);
      if (content == null) {
        continue;
      }
      if (RegExp(r'\b(?:TODO|FIXME):').hasMatch(content)) {
        offenders.add(relativePath);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Tracked text files still contain TODO/FIXME markers:\n'
          '${offenders.join('\n')}',
    );
  });
}

String _relativePath(String absolutePath, String root) {
  final normalizedRoot = root.replaceAll('\\', '/');
  final normalizedPath = absolutePath.replaceAll('\\', '/');
  if (normalizedPath.startsWith('$normalizedRoot/')) {
    return normalizedPath.substring(normalizedRoot.length + 1);
  }
  return normalizedPath;
}

bool _isScannableTextFile(String relativePath) {
  if (relativePath.endsWith('.png') ||
      relativePath.endsWith('.jpg') ||
      relativePath.endsWith('.jpeg') ||
      relativePath.endsWith('.gif') ||
      relativePath.endsWith('.webp') ||
      relativePath.endsWith('.ttf') ||
      relativePath.endsWith('.otf') ||
      relativePath.endsWith('.jar') ||
      relativePath.endsWith('.so') ||
      relativePath.endsWith('.dll') ||
      relativePath.endsWith('.dylib') ||
      relativePath.endsWith('.ico') ||
      relativePath.endsWith('.icns')) {
    return false;
  }
  return true;
}

String? _tryReadUtf8Text(File file) {
  try {
    return file.readAsStringSync();
  } on FileSystemException {
    return null;
  }
}
