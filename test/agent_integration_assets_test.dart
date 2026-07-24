import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final root = Directory.current.absolute.path;

  String read(String path) => File('$root/$path').readAsStringSync();

  List<int> readBytes(String path) => File('$root/$path').readAsBytesSync();

  Map<String, Object?> readJson(String path) {
    return jsonDecode(read(path)) as Map<String, Object?>;
  }

  void expectStdioMcpServer(
    Map<String, Object?> server, {
    Object? command = 'dart',
  }) {
    expect(server['type'], anyOf('stdio', 'local'));
    expect(server['command'], command);
    expect(server['args'], <Object?>['run', 'cockpit', 'serve-mcp']);
  }

  List<String> listFiles(String path) {
    final base = Directory('$root/$path');
    return base
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) => file.path.substring(base.path.length + 1))
        .map((path) => path.replaceAll('\\', '/'))
        .toList()
      ..sort();
  }

  void expectSkillCopyMatchesCanonical(String path) {
    final canonicalPath = 'skills/flutter-cockpit';
    final canonicalFiles = listFiles(canonicalPath);
    final copyFiles = listFiles(path);

    expect(copyFiles, canonicalFiles, reason: path);
    for (final file in canonicalFiles) {
      expect(
        readBytes('$path/$file'),
        readBytes('$canonicalPath/$file'),
        reason: '$path/$file',
      );
    }
  }

  test('Codex plugin exposes the skill and MCP server', () {
    final marketplace = readJson('.agents/plugins/marketplace.json');
    expect(marketplace['name'], 'flutter-cockpit');
    final marketplacePlugins = marketplace['plugins']! as List<Object?>;
    final marketplaceEntry = marketplacePlugins.single as Map<String, Object?>;
    expect(marketplaceEntry['name'], 'flutter-cockpit');
    expect(marketplaceEntry['source'], <String, Object?>{
      'source': 'local',
      'path': './plugins/codex/flutter-cockpit',
    });
    expect(marketplaceEntry['policy'], <String, Object?>{
      'installation': 'AVAILABLE',
      'authentication': 'ON_INSTALL',
    });

    final manifest = readJson(
      'plugins/codex/flutter-cockpit/.codex-plugin/plugin.json',
    );
    expect(manifest['name'], 'flutter-cockpit');
    expect(manifest['skills'], './skills/');
    expect(manifest['mcpServers'], './.mcp.json');
    expect(manifest['interface'], isA<Map<String, Object?>>());

    final mcp = readJson('plugins/codex/flutter-cockpit/.mcp.json');
    final servers = mcp['mcpServers']! as Map<String, Object?>;
    final server = servers['flutterCockpit']! as Map<String, Object?>;
    expectStdioMcpServer(server);

    final skill = read(
      'plugins/codex/flutter-cockpit/skills/flutter-cockpit/SKILL.md',
    );
    expect(skill, contains('name: flutter-cockpit'));
    expect(skill, contains('dart run cockpit'));
  });

  test('Claude Code plugin exposes the skill and MCP server', () {
    final projectMcp = readJson('.mcp.json');
    final projectServers = projectMcp['mcpServers']! as Map<String, Object?>;
    expectStdioMcpServer(
      projectServers['flutter-cockpit']! as Map<String, Object?>,
    );

    final manifest = readJson(
      'plugins/claude-code/flutter-cockpit/.claude-plugin/plugin.json',
    );
    expect(manifest['name'], 'flutter-cockpit');
    expect(manifest['description'], contains('Flutter Cockpit'));

    final mcp = readJson('plugins/claude-code/flutter-cockpit/.mcp.json');
    final server = mcp['flutter-cockpit']! as Map<String, Object?>;
    expectStdioMcpServer(server);

    final skill = read(
      'plugins/claude-code/flutter-cockpit/skills/flutter-cockpit/SKILL.md',
    );
    expect(skill, contains('name: flutter-cockpit'));
    expect(skill, contains('dart run cockpit'));
  });

  test('repo-local agent adapters point to the canonical skill', () {
    final cursor = read('.cursor/rules/flutter-cockpit.mdc');
    expect(cursor, contains('alwaysApply: false'));
    expect(cursor, contains('skills/flutter-cockpit/SKILL.md'));
    expect(cursor, contains('dart run cockpit'));
    final cursorMcp = readJson('.cursor/mcp.json');
    final cursorServers = cursorMcp['mcpServers']! as Map<String, Object?>;
    expectStdioMcpServer(
      cursorServers['flutter-cockpit']! as Map<String, Object?>,
    );

    final kiro = read('.kiro/steering/flutter-cockpit.md');
    expect(kiro, contains('skills/flutter-cockpit/SKILL.md'));
    expect(kiro, contains('dart run cockpit'));
    final kiroMcp = readJson('.kiro/settings/mcp.json');
    final kiroServers = kiroMcp['mcpServers']! as Map<String, Object?>;
    expectStdioMcpServer(
      kiroServers['flutter-cockpit']! as Map<String, Object?>,
    );
    final kiroPower = read('plugins/kiro/flutter-cockpit/POWER.md');
    expect(kiroPower, contains('Flutter Cockpit'));
    expect(kiroPower, contains('dart run cockpit'));
    final kiroPowerMcp = readJson('plugins/kiro/flutter-cockpit/mcp.json');
    final kiroPowerServers =
        kiroPowerMcp['mcpServers']! as Map<String, Object?>;
    expectStdioMcpServer(
      kiroPowerServers['flutter-cockpit']! as Map<String, Object?>,
    );

    final opencode = readJson('opencode.json');
    expect(opencode['instructions'], <Object?>['AGENTS.md']);
    final mcp = opencode['mcp']! as Map<String, Object?>;
    final server = mcp['flutterCockpit']! as Map<String, Object?>;
    expect(server['type'], 'local');
    expect(server['command'], <Object?>['dart', 'run', 'cockpit', 'serve-mcp']);

    final ompSkill = read('.agents/skills/flutter-cockpit/SKILL.md');
    expect(ompSkill, contains('name: flutter-cockpit'));
    expect(ompSkill, contains('dart run cockpit'));
    final piSkill = read('.pi/skills/flutter-cockpit/SKILL.md');
    expect(piSkill, contains('name: flutter-cockpit'));
    expect(piSkill, contains('dart run cockpit'));
  });

  test('agent integration docs cover every supported host', () {
    final docs = read('docs/agent-integrations.md');
    final readme = read('README.md');
    final zhReadme = read('README.zh-CN.md');
    for (final host in <String>[
      'Codex',
      'Claude Code',
      'Cursor',
      'Kiro',
      'OpenCode',
      'OMP',
      'Oh My Pi',
    ]) {
      expect(docs, contains(host), reason: host);
    }
    expect(docs, contains('plugins/codex/flutter-cockpit'));
    expect(docs, contains('plugins/claude-code/flutter-cockpit'));
    expect(docs, contains('.claude/skills/flutter-cockpit'));
    expect(docs, contains('.mcp.json'));
    expect(docs, contains('.cursor/rules/flutter-cockpit.mdc'));
    expect(docs, contains('.cursor/mcp.json'));
    expect(docs, contains('.cursor/skills/flutter-cockpit'));
    expect(docs, contains('.kiro/steering/flutter-cockpit.md'));
    expect(docs, contains('.kiro/settings/mcp.json'));
    expect(docs, contains('plugins/kiro/flutter-cockpit'));
    expect(docs, contains('.agents/skills/flutter-cockpit'));
    expect(docs, contains('.opencode/skills/flutter-cockpit'));
    expect(docs, contains('.pi/skills/flutter-cockpit'));
    expect(docs, contains('opencode.json'));
    expect(readme, contains('docs/agent-integrations.md'));
    expect(zhReadme, contains('docs/agent-integrations.md'));
    expect(readme, contains('OpenCode/OMP skill'));
    expect(zhReadme, contains('OpenCode/OMP skill'));
  });

  test('packaged skills are complete copies of the canonical skill', () {
    final canonical = read('skills/flutter-cockpit/SKILL.md');

    expect(canonical.split(RegExp(r'\s+')).length, greaterThan(500));
    expectSkillCopyMatchesCanonical(
      'plugins/codex/flutter-cockpit/skills/flutter-cockpit',
    );
    expectSkillCopyMatchesCanonical(
      'plugins/claude-code/flutter-cockpit/skills/flutter-cockpit',
    );
    expectSkillCopyMatchesCanonical(
      'plugins/kiro/flutter-cockpit/skills/flutter-cockpit',
    );
    expectSkillCopyMatchesCanonical('.agents/skills/flutter-cockpit');
    expectSkillCopyMatchesCanonical('.claude/skills/flutter-cockpit');
    expectSkillCopyMatchesCanonical('.cursor/skills/flutter-cockpit');
    expectSkillCopyMatchesCanonical('.opencode/skills/flutter-cockpit');
    expectSkillCopyMatchesCanonical('.pi/skills/flutter-cockpit');
  });
}
