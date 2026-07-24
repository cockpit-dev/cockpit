# Agent Integrations

Flutter Cockpit ships one canonical AI workflow at `skills/flutter-cockpit/SKILL.md` and host-native adapters for common coding agents. Keep the canonical skill as the source of truth; native skill directories and packaged plugins carry synced copies so installed or repo-local adapters work outside this repository.

## Codex

Codex supports installable plugins with `.codex-plugin/plugin.json`.

Repository asset:

```text
.agents/plugins/marketplace.json
plugins/codex/flutter-cockpit
```

The marketplace entry points Codex at the local plugin. The plugin exposes:

- `skills/flutter-cockpit` as a complete Codex skill.
- `.mcp.json` with `flutterCockpit -> dart run cockpit serve-mcp`.

For direct MCP setup without installing the plugin:

```bash
codex mcp add flutterCockpit -- dart run cockpit serve-mcp
```

## Claude Code

Claude Code supports plugins with `.claude-plugin/plugin.json`, skills, and `.mcp.json`.

Repository asset:

```text
.claude/skills/flutter-cockpit
.mcp.json
plugins/claude-code/flutter-cockpit
```

Repo-local Claude Code can discover `.claude/skills/flutter-cockpit` and the project `.mcp.json`. The plugin exposes:

- `skills/flutter-cockpit` as a complete Claude Code skill.
- `.mcp.json` with `flutter-cockpit -> dart run cockpit serve-mcp`.

For direct MCP setup without installing the plugin:

```bash
claude mcp add --transport stdio flutter-cockpit -- dart run cockpit serve-mcp
```

## Cursor

Cursor uses project rules, project skills, and project MCP config rather than this repository's plugin manifest.

Repository asset:

```text
.cursor/rules/flutter-cockpit.mdc
.cursor/skills/flutter-cockpit
.cursor/mcp.json
```

The rule gives Cursor the trigger, `.cursor/skills/flutter-cockpit` gives it the full on-demand workflow, and `.cursor/mcp.json` exposes the local MCP server:

```json
{
  "mcpServers": {
    "flutter-cockpit": {
      "type": "stdio",
      "command": "dart",
      "args": ["run", "cockpit", "serve-mcp"]
    }
  }
}
```

## Kiro

Kiro uses steering documents for project guidance, workspace MCP config for tools, and Powers for a distributable native bundle.

Repository asset:

```text
.kiro/steering/flutter-cockpit.md
.kiro/settings/mcp.json
plugins/kiro/flutter-cockpit
```

The workspace steering file is the repo-local trigger. `.kiro/settings/mcp.json` exposes the local MCP server. `plugins/kiro/flutter-cockpit` is the Kiro Power bundle with `POWER.md`, `mcp.json`, and the full skill copy.

## OpenCode

OpenCode discovers project skills from `.opencode/skills/<name>/SKILL.md`, also understands shared Agent Skills under `.agents/skills/<name>/SKILL.md`, and configures MCP servers through the `mcp` option. This repository uses `.opencode/skills/flutter-cockpit` for the OpenCode-native on-demand skill, `.agents/skills/flutter-cockpit` for shared agents, and `opencode.json` for the local MCP server.

Repository asset:

```text
opencode.json
.opencode/skills/flutter-cockpit
.agents/skills/flutter-cockpit
```

The repo-local config loads normal project instructions and the local MCP server:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "instructions": ["AGENTS.md"],
  "mcp": {
    "flutterCockpit": {
      "type": "local",
      "command": ["dart", "run", "cockpit", "serve-mcp"],
      "enabled": true
    }
  }
}
```

The skill body stays out of always-on instructions so OpenCode can load it only when a Flutter Cockpit task needs it.

## OMP / Oh My Pi

OMP / Pi discovers project skills from `.pi/skills/<name>/SKILL.md` and shared Agent Skills from `.agents/skills/<name>/SKILL.md`. The repository includes both so Pi-native and shared-agent discovery work without extra copying:

```text
.pi/skills/flutter-cockpit
.agents/skills/flutter-cockpit
```

If OMP is configured to import MCP servers from repo config, use the same `dart run cockpit serve-mcp` server. Otherwise run Flutter Cockpit through the CLI commands in the skill.

## Verification

After installing any adapter:

1. Restart or reload the host so it rescans plugins, skills, rules, or steering files.
2. Ask the host to load the `flutter-cockpit` skill, or read `skills/flutter-cockpit/SKILL.md` for repo-local rule/steering adapters.
3. Run `dart run cockpit daemon status`, then
   `dart run cockpit target discover`.
4. If MCP is configured, verify the host can see the Cockpit 2.0 workspace,
   target, operation, case, suite, run, and artifact resources.
5. Keep app proof proportional: inspect, act through an advertised operation
   or validated test document, re-inspect, and read report-backed evidence.
