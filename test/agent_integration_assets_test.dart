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

  void expectStdioMcpServer(Map<String, Object?> server) {
    expect(server['type'], anyOf('stdio', 'local'));
    expect(server['command'], 'cockpit_mcp');
    expect(server['args'], <Object?>[]);
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
    final canonicalPath = 'skills/cockpit';
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
    expect(marketplace['name'], 'cockpit');
    final marketplacePlugins = marketplace['plugins']! as List<Object?>;
    final marketplaceEntry = marketplacePlugins.single as Map<String, Object?>;
    expect(marketplaceEntry['name'], 'cockpit');
    expect(marketplaceEntry['source'], <String, Object?>{
      'source': 'local',
      'path': './plugins/codex/cockpit',
    });
    expect(marketplaceEntry['policy'], <String, Object?>{
      'installation': 'AVAILABLE',
      'authentication': 'ON_INSTALL',
    });

    final manifest = readJson(
      'plugins/codex/cockpit/.codex-plugin/plugin.json',
    );
    expect(manifest['name'], 'cockpit');
    expect(manifest['skills'], './skills/');
    expect(manifest['mcpServers'], './.mcp.json');
    expect(manifest['interface'], isA<Map<String, Object?>>());

    final mcp = readJson('plugins/codex/cockpit/.mcp.json');
    final servers = mcp['mcpServers']! as Map<String, Object?>;
    final server = servers['cockpit']! as Map<String, Object?>;
    expectStdioMcpServer(server);

    final skill = read('plugins/codex/cockpit/skills/cockpit/SKILL.md');
    expect(skill, contains('name: cockpit'));
    expect(skill, contains('globally installed `cockpit` executable'));
  });

  test('Claude Code plugin exposes the skill and MCP server', () {
    final projectMcp = readJson('.mcp.json');
    final projectServers = projectMcp['mcpServers']! as Map<String, Object?>;
    expectStdioMcpServer(projectServers['cockpit']! as Map<String, Object?>);

    final manifest = readJson(
      'plugins/claude-code/cockpit/.claude-plugin/plugin.json',
    );
    expect(manifest['name'], 'cockpit');
    expect(manifest['description'], contains('Cockpit'));

    final mcp = readJson('plugins/claude-code/cockpit/.mcp.json');
    final server = mcp['cockpit']! as Map<String, Object?>;
    expectStdioMcpServer(server);

    final skill = read('plugins/claude-code/cockpit/skills/cockpit/SKILL.md');
    expect(skill, contains('name: cockpit'));
    expect(skill, contains('globally installed `cockpit` executable'));
  });

  test('repo-local agent adapters point to the canonical skill', () {
    final cursor = read('.cursor/rules/cockpit.mdc');
    expect(cursor, contains('alwaysApply: false'));
    expect(cursor, contains('.cursor/skills/cockpit/SKILL.md'));
    expect(cursor, isNot(contains('dart run cockpit')));
    final cursorMcp = readJson('.cursor/mcp.json');
    final cursorServers = cursorMcp['mcpServers']! as Map<String, Object?>;
    expectStdioMcpServer(cursorServers['cockpit']! as Map<String, Object?>);

    final kiro = read('.kiro/steering/cockpit.md');
    expect(kiro, contains('bundled self-contained `cockpit` skill'));
    expect(kiro, isNot(contains('dart run cockpit')));
    final kiroMcp = readJson('.kiro/settings/mcp.json');
    final kiroServers = kiroMcp['mcpServers']! as Map<String, Object?>;
    expectStdioMcpServer(kiroServers['cockpit']! as Map<String, Object?>);
    final kiroPower = read('plugins/kiro/cockpit/POWER.md');
    expect(kiroPower, contains('Cockpit'));
    expect(kiroPower, contains('globally installed `cockpit_mcp` server'));
    final kiroPowerMcp = readJson('plugins/kiro/cockpit/mcp.json');
    final kiroPowerServers =
        kiroPowerMcp['mcpServers']! as Map<String, Object?>;
    expectStdioMcpServer(kiroPowerServers['cockpit']! as Map<String, Object?>);

    final opencode = readJson('opencode.json');
    expect(opencode['instructions'], <Object?>['AGENTS.md']);
    final mcp = opencode['mcp']! as Map<String, Object?>;
    final server = mcp['cockpit']! as Map<String, Object?>;
    expect(server['type'], 'local');
    expect(server['command'], <Object?>['cockpit_mcp']);
    expect(server['enabled'], isTrue);

    final ompSkill = read('.agents/skills/cockpit/SKILL.md');
    expect(ompSkill, contains('name: cockpit'));
    expect(ompSkill, contains('globally installed `cockpit` executable'));
    final piSkill = read('.pi/skills/cockpit/SKILL.md');
    expect(piSkill, contains('name: cockpit'));
    expect(piSkill, contains('globally installed `cockpit` executable'));
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
    expect(docs, contains('plugins/codex/cockpit'));
    expect(docs, contains('plugins/claude-code/cockpit'));
    expect(docs, contains('.claude/skills/cockpit'));
    expect(docs, contains('.mcp.json'));
    expect(docs, contains('.cursor/rules/cockpit.mdc'));
    expect(docs, contains('.cursor/mcp.json'));
    expect(docs, contains('.cursor/skills/cockpit'));
    expect(docs, contains('.kiro/steering/cockpit.md'));
    expect(docs, contains('.kiro/settings/mcp.json'));
    expect(docs, contains('plugins/kiro/cockpit'));
    expect(docs, contains('.agents/skills/cockpit'));
    expect(docs, contains('.opencode/skills/cockpit'));
    expect(docs, contains('.pi/skills/cockpit'));
    expect(docs, contains('opencode.json'));
    expect(readme, contains('docs/agent-integrations.md'));
    expect(zhReadme, contains('docs/agent-integrations.md'));
    expect(readme, contains('OpenCode/OMP skill'));
    expect(zhReadme, contains('OpenCode/OMP skill'));
  });

  test('packaged skills are complete copies of the canonical skill', () {
    final canonical = read('skills/cockpit/SKILL.md');

    expect(canonical.split(RegExp(r'\s+')).length, greaterThan(500));
    expectSkillCopyMatchesCanonical('plugins/codex/cockpit/skills/cockpit');
    expectSkillCopyMatchesCanonical(
      'plugins/claude-code/cockpit/skills/cockpit',
    );
    expectSkillCopyMatchesCanonical('plugins/kiro/cockpit/skills/cockpit');
    expectSkillCopyMatchesCanonical('.agents/skills/cockpit');
    expectSkillCopyMatchesCanonical('.claude/skills/cockpit');
    expectSkillCopyMatchesCanonical('.cursor/skills/cockpit');
    expectSkillCopyMatchesCanonical('.opencode/skills/cockpit');
    expectSkillCopyMatchesCanonical('.pi/skills/cockpit');
  });
}
