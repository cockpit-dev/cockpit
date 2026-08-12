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
    expect(manifest['version'], '4.0.1');
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
    final marketplace = readJson('.claude-plugin/marketplace.json');
    expect(marketplace['name'], 'cockpit');
    expect(marketplace['owner'], isA<Map<String, Object?>>());
    final plugins = marketplace['plugins']! as List<Object?>;
    expect(plugins, hasLength(1));
    expect(plugins.single, containsPair('name', 'cockpit'));
    expect(
      plugins.single,
      containsPair('source', './plugins/claude-code/cockpit'),
    );

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
    expect(cursor, isNot(contains('globs:')));
    expect(cursor, contains('.cursor/skills/cockpit/SKILL.md'));
    expect(cursor, isNot(contains('dart run cockpit')));
    final cursorMcp = readJson('.cursor/mcp.json');
    final cursorServers = cursorMcp['mcpServers']! as Map<String, Object?>;
    expectStdioMcpServer(cursorServers['cockpit']! as Map<String, Object?>);

    final kiro = read('.kiro/steering/cockpit.md');
    expect(kiro, startsWith('---\ninclusion: auto\nname: cockpit\n'));
    expect(kiro, contains('.kiro/skills/cockpit/SKILL.md'));
    expect(kiro, contains('Cockpit Power'));
    expect(kiro, isNot(contains('dart run cockpit')));
    final kiroMcp = readJson('.kiro/settings/mcp.json');
    final kiroServers = kiroMcp['mcpServers']! as Map<String, Object?>;
    expect(kiroServers['cockpit'], <String, Object?>{
      'command': 'cockpit_mcp',
      'args': <Object?>[],
    });

    final gemini = readJson('.gemini/settings.json');
    final geminiServers = gemini['mcpServers']! as Map<String, Object?>;
    final geminiCockpit = geminiServers['cockpit']! as Map<String, Object?>;
    expect(geminiCockpit['command'], 'cockpit_mcp');
    expect(geminiCockpit['args'], <Object?>[]);
    final kiroPower = readJson('plugins/kiro/cockpit/plugin.json');
    expect(
      kiroPower[r'$schema'],
      'https://agent-plugins.org/schemas/1.0.0/plugin.schema.json',
    );
    expect(kiroPower['name'], 'cockpit');
    expect(kiroPower['version'], '4.0.1');
    expect(
      kiroPower['keywords'],
      containsAll(<Object?>['cockpit', 'flutter', 'e2e']),
    );
    final kiroPowerMcp = readJson('plugins/kiro/cockpit/mcp.json');
    expect(
      kiroPowerMcp[r'$schema'],
      'https://agent-plugins.org/schemas/1.0.0/mcp.schema.json',
    );
    final kiroPowerServers =
        kiroPowerMcp['mcpServers']! as Map<String, Object?>;
    expectStdioMcpServer(kiroPowerServers['cockpit']! as Map<String, Object?>);

    final opencode = readJson('opencode.json');
    expect(opencode, isNot(contains('instructions')));
    final mcp = opencode['mcp']! as Map<String, Object?>;
    final server = mcp['cockpit']! as Map<String, Object?>;
    expect(server['type'], 'local');
    expect(server['command'], <Object?>['cockpit_mcp']);
    expect(server['enabled'], isTrue);

    final sharedSkill = read('.agents/skills/cockpit/SKILL.md');
    expect(sharedSkill, contains('name: cockpit'));
    expect(sharedSkill, contains('globally installed `cockpit` executable'));
    final piSkill = read('.pi/skills/cockpit/SKILL.md');
    expect(piSkill, contains('name: cockpit'));
    expect(piSkill, contains('globally installed `cockpit` executable'));

    final ompSkill = read('.omp/skills/cockpit/SKILL.md');
    expect(ompSkill, contains('name: cockpit'));
    expect(ompSkill, contains('globally installed `cockpit` executable'));
    final ompMcp = readJson('.omp/mcp.json');
    expect(ompMcp[r'$schema'], contains('can1357/oh-my-pi'));
    final ompServers = ompMcp['mcpServers']! as Map<String, Object?>;
    expectStdioMcpServer(ompServers['cockpit']! as Map<String, Object?>);

    final clineSkill = read('.cline/skills/cockpit/SKILL.md');
    expect(clineSkill, contains('name: cockpit'));
    expect(clineSkill, contains('globally installed `cockpit` executable'));
  });

  test('agent integration docs cover every supported host', () {
    final docs = read('docs/agent-integrations.md');
    final install = read('skills/cockpit/INSTALL.md');
    final readme = read('README.md');
    final zhReadme = read('README.zh-CN.md');
    const prompt =
        'Install Cockpit for the current AI host, including the CLI, complete '
        'cockpit Skill, native adapter, and cockpit_mcp when supported, by following '
        'https://github.com/cockpit-dev/cockpit/blob/main/skills/cockpit/'
        'INSTALL.md';
    for (final host in <String>[
      'Codex',
      'Claude Code',
      'Cursor',
      'Gemini CLI',
      'Kiro',
      'OpenCode',
      'GitHub Copilot',
      'Windsurf',
      'Cline',
      'Roo Code',
      'Pi',
      'OMP',
      'Oh My Pi',
    ]) {
      expect(docs, contains(host), reason: host);
      expect(install, contains(host), reason: 'INSTALL.md: $host');
    }
    expect(docs, contains('plugins/codex/cockpit'));
    expect(docs, contains('plugins/claude-code/cockpit'));
    expect(docs, contains('.claude-plugin/marketplace.json'));
    expect(docs, contains('.claude/skills/cockpit'));
    expect(docs, contains('.mcp.json'));
    expect(docs, contains('.cursor/rules/cockpit.mdc'));
    expect(docs, contains('.cursor/mcp.json'));
    expect(docs, contains('.cursor/skills/cockpit'));
    expect(docs, contains('.gemini/settings.json'));
    expect(docs, contains('.kiro/steering/cockpit.md'));
    expect(docs, contains('.kiro/settings/mcp.json'));
    expect(docs, contains('.kiro/skills/cockpit'));
    expect(docs, contains('plugins/kiro/cockpit'));
    expect(docs, contains('Import power from a folder'));
    expect(docs, contains('plugin.json'));
    expect(docs, contains('.agents/skills/cockpit'));
    expect(docs, contains('.opencode/skills/cockpit'));
    expect(docs, contains('.pi/skills/cockpit'));
    expect(docs, contains('.omp/skills/cockpit'));
    expect(docs, contains('.omp/mcp.json'));
    expect(docs, contains('.cline/skills/cockpit'));
    expect(docs, contains('opencode.json'));
    expect(docs, contains('codex plugin marketplace add cockpit-dev/cockpit'));
    expect(docs, contains('codex plugin add cockpit@cockpit'));
    expect(
      docs,
      contains(
        'gemini skills install https://github.com/cockpit-dev/cockpit.git',
      ),
    );
    expect(docs, contains('gemini mcp add --scope user cockpit cockpit_mcp'));
    expect(docs, contains('claude plugin marketplace add cockpit-dev/cockpit'));
    expect(docs, contains('dart pub global activate cockpit any'));
    expect(docs, contains(prompt));
    expect(install, contains('whole directory'));
    expect(install, contains('dart pub global activate cockpit any'));
    expect(
      install,
      contains('codex plugin marketplace add cockpit-dev/cockpit'),
    );
    expect(install, contains('codex plugin add cockpit@cockpit'));
    expect(
      install,
      contains(
        'gemini skills install https://github.com/cockpit-dev/cockpit.git',
      ),
    );
    expect(install, contains('cockpit_mcp'));
    expect(install, contains('Import power from a folder'));
    expect(install, contains('Do not add `type` to the workspace config'));
    expect(install, contains('.kiro/skills/cockpit'));
    expect(install, contains('Pi has no built-in MCP client'));
    expect(install, contains('.omp/mcp.json'));
    expect(install, contains('.cline/skills/cockpit'));
    expect(install, contains('cockpit target discover'));
    for (final bundledDirectory in <String>[
      'agents/',
      'assets/',
      'references/',
    ]) {
      expect(install, contains(bundledDirectory));
    }

    expect(readme, contains('skills/cockpit/INSTALL.md'));
    expect(zhReadme, contains('skills/cockpit/INSTALL.md'));
    for (final host in <String>[
      'GitHub Copilot',
      'Windsurf',
      'Cline',
      'Roo Code',
      'Pi',
      'Oh My Pi',
    ]) {
      expect(readme, contains(host), reason: host);
      expect(zhReadme, contains(host), reason: host);
    }
    for (final document in <String>[readme, zhReadme]) {
      expect(document, contains(prompt));
    }

    for (final path in <String>[
      'packages/cockpit/README.md',
      'packages/cockpit/README.zh-CN.md',
      'packages/flutter_cockpit/README.md',
      'packages/flutter_cockpit/README.zh-CN.md',
    ]) {
      final packageReadme = read(path);
      expect(packageReadme, contains(prompt));
      expect(packageReadme, contains('skills/cockpit/INSTALL.md'));
    }

    expect(
      read('plugins/codex/cockpit/README.md'),
      allOf(
        contains('codex plugin marketplace add cockpit-dev/cockpit'),
        contains('codex plugin add cockpit@cockpit'),
      ),
    );
  });

  test('packaged skills are complete copies of the canonical skill', () {
    expectSkillCopyMatchesCanonical('plugins/codex/cockpit/skills/cockpit');
    expectSkillCopyMatchesCanonical(
      'plugins/claude-code/cockpit/skills/cockpit',
    );
    expectSkillCopyMatchesCanonical('plugins/kiro/cockpit/skills/cockpit');
    expectSkillCopyMatchesCanonical('.kiro/skills/cockpit');
    expectSkillCopyMatchesCanonical('.agents/skills/cockpit');
    expectSkillCopyMatchesCanonical('.claude/skills/cockpit');
    expectSkillCopyMatchesCanonical('.cursor/skills/cockpit');
    expectSkillCopyMatchesCanonical('.opencode/skills/cockpit');
    expectSkillCopyMatchesCanonical('.pi/skills/cockpit');
    expectSkillCopyMatchesCanonical('.omp/skills/cockpit');
    expectSkillCopyMatchesCanonical('.cline/skills/cockpit');
  });
}
