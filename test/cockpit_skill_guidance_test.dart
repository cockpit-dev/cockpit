import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const _skillRoots = <String>[
  'skills/cockpit',
  '.agents/skills/cockpit',
  '.claude/skills/cockpit',
  '.cursor/skills/cockpit',
  '.cline/skills/cockpit',
  '.opencode/skills/cockpit',
  '.omp/skills/cockpit',
  '.pi/skills/cockpit',
  'plugins/claude-code/cockpit/skills/cockpit',
  'plugins/codex/cockpit/skills/cockpit',
  'plugins/kiro/cockpit/skills/cockpit',
];

void main() {
  final repositoryRoot = Directory.current.absolute.path;

  String read(String path) => File('$repositoryRoot/$path').readAsStringSync();

  test('all distributed skills are exact minimal mirrors', () {
    final canonicalFiles = _relativeFiles(repositoryRoot, _skillRoots.first);

    for (final root in _skillRoots) {
      expect(
        _relativeFiles(repositoryRoot, root),
        canonicalFiles,
        reason: '$root must contain the complete deployable 2.0 skill.',
      );
      for (final relativePath in canonicalFiles) {
        expect(
          File('$repositoryRoot/$root/$relativePath').readAsBytesSync(),
          File(
            '$repositoryRoot/${_skillRoots.first}/$relativePath',
          ).readAsBytesSync(),
          reason: '$root/$relativePath',
        );
      }
    }
  });

  test('skill teaches the Cockpit 2.0 control and evidence workflow', () {
    final skill = read('${_skillRoots.first}/SKILL.md');
    final frontmatterEnd = skill.indexOf('\n---\n', 4);

    expect(skill, startsWith('---\n'));
    expect(frontmatterEnd, greaterThan(0));
    final frontmatter = skill.substring(4, frontmatterEnd).split('\n');
    expect(frontmatter, hasLength(2));
    expect(frontmatter.first, 'name: cockpit');
    expect(
      frontmatter.last,
      allOf(
        startsWith('description: Use when '),
        contains('black-box application'),
        contains('Cockpit 2.0'),
      ),
    );

    for (final contract in <String>[
      'authenticated Supervisor',
      'daemon start --yolo',
      'workspace',
      'target discover',
      'target register',
      'target inspect --target-id',
      'workspace documents',
      'operation list',
      'operation run',
      'cockpit.test/v2',
      'case validate',
      'case run',
      'suite validate',
      'suite run',
      'run events',
      'run get',
      'suite report',
      'daemon policy show',
      'idempotency',
      'terminal run state',
      'cockpit.test.v2.schema.json',
      'Binary',
      'Rapid Development Validation',
      'resolve -> baseline -> edit -> execute -> observe -> judge -> repeat',
      'references/flutter.md',
      'references/environments.md',
    ]) {
      expect(skill, contains(contract), reason: contract);
    }
  });

  test('skill distribution contains no retired client surface', () {
    final distribution = _skillRoots
        .expand(
          (root) => _relativeFiles(
            repositoryRoot,
            root,
          ).map((path) => read('$root/$path')),
        )
        .join('\n');

    for (final retired in <String>[
      'launch-app',
      'read-app',
      'run-script',
      'run-task',
      'validate-task',
      'control-workflow',
      'task-run-bundle',
      'latest-task',
      'live-run',
      'Maestro',
      'Dify',
    ]) {
      expect(distribution, isNot(contains(retired)), reason: retired);
    }
  });

  test('skill is self-contained after isolated installation', () {
    final canonicalRoot = '$repositoryRoot/${_skillRoots.first}';
    final textFiles = _relativeFiles(
      repositoryRoot,
      _skillRoots.first,
    ).where((path) => path.endsWith('.md') || path.endsWith('.yaml'));

    for (final relativePath in textFiles) {
      final source = read('${_skillRoots.first}/$relativePath');
      for (final forbidden in <String>[
        'packages/cockpit',
        'packages/flutter_cockpit',
        'docs/contracts/',
        'examples/cockpit_demo',
      ]) {
        expect(
          source,
          isNot(contains(forbidden)),
          reason: '$relativePath depends on repository-only path $forbidden',
        );
      }
      for (final match in RegExp(r'\[[^\]]+\]\(([^)]+)\)').allMatches(source)) {
        final target = match.group(1)!;
        if (target.startsWith('#') || Uri.tryParse(target)?.hasScheme == true) {
          continue;
        }
        final path = target.split('#').first;
        final resolved = File(
          '${File('$canonicalRoot/$relativePath').parent.path}/$path',
        ).absolute.uri.normalizePath().toFilePath();
        expect(
          FileSystemEntity.typeSync(resolved),
          isNot(FileSystemEntityType.notFound),
          reason: '$relativePath links to missing skill-local file $target',
        );
        expect(
          Uri.file(resolved).path.startsWith(Uri.file(canonicalRoot).path),
          isTrue,
          reason: '$relativePath links outside the installed skill: $target',
        );
      }
    }

    expect(
      Directory(
        canonicalRoot,
      ).listSync(recursive: true, followLinks: false).whereType<Link>(),
      isEmpty,
      reason: 'The installed skill must not depend on external symlinks.',
    );
  });

  test('skill bundles the authoritative 2.0 authoring schema', () {
    final protocol = read('${_skillRoots.first}/references/protocol.md');

    for (final authority in <String>[
      'cockpit.test.v2.schema.json',
      'cockpit help',
      'operation list',
      'target inspect',
      'SSE sequence numbers are monotonic and resumable',
      'session affinity',
      'SHA-256',
    ]) {
      expect(protocol, contains(authority), reason: authority);
    }

    expect(
      File(
        '$repositoryRoot/${_skillRoots.first}/references/'
        'cockpit.test.v2.schema.json',
      ).readAsBytesSync(),
      File(
        '$repositoryRoot/packages/cockpit_protocol/schema/'
        'cockpit.test.v2.schema.json',
      ).readAsBytesSync(),
    );
  });

  test('skill includes an executable Flutter development-shell workflow', () {
    final flutter = read('${_skillRoots.first}/references/flutter.md');

    for (final requirement in <String>[
      'flutter_cockpit: any',
      'cockpit/main.dart',
      'FlutterCockpitApp',
      'CockpitRemoteSessionConfiguration.resolveFromEnvironment',
      'FlutterCockpit.createNavigatorObserver()',
      'workspace documents',
      '--entrypoint-document-id',
      'target launch',
      'bindRouteInformationProvider',
      'setCurrentRouteName',
    ]) {
      expect(flutter, contains(requirement), reason: requirement);
    }
  });

  test('skill bundles version-independent installation guidance', () {
    final install = read('${_skillRoots.first}/INSTALL.md');

    for (final requirement in <String>[
      'Install Cockpit for the current AI host',
      'including the CLI, complete cockpit Skill, native adapter, and '
          'cockpit_mcp when supported',
      'whole directory',
      'dart pub global activate cockpit any',
      'cockpit_mcp',
      'Cursor',
      'Kiro',
      'OpenCode',
      'GitHub Copilot CLI',
      'Windsurf',
      'Roo Code',
      'Pi has no built-in MCP client',
      '.omp/mcp.json',
      '.cline/skills/cockpit',
      'agents/',
      'assets/',
      'references/',
    ]) {
      expect(install, contains(requirement), reason: requirement);
    }
  });

  test('skill command examples match the current CLI parser', () {
    final development = read('${_skillRoots.first}/references/dev.md');
    final environments = read(
      '${_skillRoots.first}/references/environments.md',
    );

    expect(development, contains('--flutter-arg=--track-widget-creation'));
    expect(development, isNot(contains('--flutter-arg --')));
    expect(environments, contains('## Contents'));
    expect(environments, contains('cockpit help'));
    expect(environments, isNot(contains('cockpit --version')));
  });

  test('skill includes platform environment recovery guidance', () {
    final environments = read(
      '${_skillRoots.first}/references/environments.md',
    );

    for (final requirement in <String>[
      '## Android',
      'adb devices -l',
      '## iOS And iPadOS',
      'WebDriverAgent',
      'curl --fail http://127.0.0.1:8100/status',
      '## macOS',
      'Accessibility',
      '## Parallel Projects And Devices',
      'authorizationMode: yolo',
    ]) {
      expect(environments, contains(requirement), reason: requirement);
    }
  });

  test('referenced OpenAPI and schemas expose the complete 2.0 resources', () {
    final openApi = _json(
      read('packages/cockpit_protocol/openapi/cockpit.v2.openapi.json'),
    );
    final foundation = _json(
      read(
        'packages/cockpit_protocol/schema/'
        'cockpit.foundation.v2.schema.json',
      ),
    );
    final testDocument = _json(
      read('packages/cockpit_protocol/schema/cockpit.test.v2.schema.json'),
    );

    expect(openApi['openapi'], '3.1.0');
    expect((openApi['info'] as Map<String, Object?>)['version'], '2.0.0');
    final paths = (openApi['paths'] as Map<String, Object?>).keys;
    for (final path in <String>[
      '/api/v2/workspaces',
      '/api/v2/workspaces/{workspaceId}/operations',
      '/api/v2/workspaces/{workspaceId}/targets',
      '/api/v2/workspaces/{workspaceId}/cases',
      '/api/v2/workspaces/{workspaceId}/runs',
      '/api/v2/runs/{runId}/events',
      '/api/v2/runs/{runId}/report',
      '/api/v2/runs/{runId}/artifacts/{artifactId}',
    ]) {
      expect(paths, contains(path), reason: path);
    }

    expect(
      foundation[r'$schema'],
      'https://json-schema.org/draft/2020-12/schema',
    );
    final foundationDefinitions =
        (foundation[r'$defs'] as Map<String, Object?>).keys;
    for (final definition in <String>[
      'WorkspaceResource',
      'AutomationTargetResource',
      'OperationDescriptor',
      'RunResource',
      'ArtifactResource',
    ]) {
      expect(foundationDefinitions, contains(definition), reason: definition);
    }

    expect(
      testDocument[r'$schema'],
      'https://json-schema.org/draft/2020-12/schema',
    );
    expect(testDocument['oneOf'], <Object?>[
      <String, Object?>{r'$ref': r'#/$defs/project'},
      <String, Object?>{r'$ref': r'#/$defs/suite'},
      <String, Object?>{r'$ref': r'#/$defs/case'},
    ]);
    final testDefinitions =
        (testDocument[r'$defs'] as Map<String, Object?>).keys;
    for (final definition in <String>[
      'project',
      'suite',
      'case',
      'suiteReport',
      'caseReport',
    ]) {
      expect(testDefinitions, contains(definition), reason: definition);
    }
  });
}

Map<String, Object?> _json(String source) =>
    jsonDecode(source) as Map<String, Object?>;

List<String> _relativeFiles(String repositoryRoot, String directory) {
  final absoluteRoot = '$repositoryRoot/$directory';
  final files =
      Directory(absoluteRoot)
          .listSync(recursive: true)
          .whereType<File>()
          .map(
            (file) => file.absolute.path
                .substring(absoluteRoot.length + 1)
                .replaceAll('\\', '/'),
          )
          .toList()
        ..sort();
  return files;
}
