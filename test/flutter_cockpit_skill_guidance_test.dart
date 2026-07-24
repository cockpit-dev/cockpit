import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const _skillRoots = <String>[
  'skills/flutter-cockpit',
  '.agents/skills/flutter-cockpit',
  '.claude/skills/flutter-cockpit',
  '.cursor/skills/flutter-cockpit',
  '.opencode/skills/flutter-cockpit',
  '.pi/skills/flutter-cockpit',
  'plugins/claude-code/flutter-cockpit/skills/flutter-cockpit',
  'plugins/codex/flutter-cockpit/skills/flutter-cockpit',
  'plugins/kiro/flutter-cockpit/skills/flutter-cockpit',
];

void main() {
  final repositoryRoot = Directory.current.absolute.path;

  String read(String path) => File('$repositoryRoot/$path').readAsStringSync();

  test('all distributed skills are exact minimal mirrors', () {
    final canonicalSkill = read('${_skillRoots.first}/SKILL.md');
    final canonicalProtocol = read(
      '${_skillRoots.first}/references/protocol.md',
    );

    for (final root in _skillRoots) {
      expect(
        _relativeFiles(repositoryRoot, root),
        <String>['SKILL.md', 'references/protocol.md'],
        reason: '$root must contain only the deployable 2.0 skill assets.',
      );
      expect(read('$root/SKILL.md'), canonicalSkill, reason: root);
      expect(
        read('$root/references/protocol.md'),
        canonicalProtocol,
        reason: root,
      );
    }
  });

  test('skill teaches the Cockpit 2.0 control and evidence workflow', () {
    final skill = read('${_skillRoots.first}/SKILL.md');
    final frontmatterEnd = skill.indexOf('\n---\n', 4);

    expect(skill, startsWith('---\n'));
    expect(frontmatterEnd, greaterThan(0));
    final frontmatter = skill.substring(4, frontmatterEnd).split('\n');
    expect(frontmatter, hasLength(2));
    expect(frontmatter.first, 'name: flutter-cockpit');
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
      'workspace',
      'target discover',
      'target register',
      'target inspect --target-id',
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
      'digest-checked artifacts',
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

  test('skill protocol points clients at the authoritative 2.0 contracts', () {
    final protocol = read('${_skillRoots.first}/references/protocol.md');

    for (final authority in <String>[
      'cockpit.v2.openapi.json',
      'cockpit.foundation.v2.schema.json',
      'cockpit.test.v2.schema.json',
      'flutter-cockpit-protocol.md',
      'ai-development-protocol.md',
      'COCKPIT_HOME/authorization.json',
      'SSE sequence numbers are monotonic and resumable',
      'session affinity',
      'always-run teardown',
      'SHA-256',
    ]) {
      expect(protocol, contains(authority), reason: authority);
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
