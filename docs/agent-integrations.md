# Agent Integrations

Cockpit ships one canonical AI workflow at `skills/cockpit/SKILL.md` and host-native adapters for common coding agents. Keep the canonical skill as the source of truth; native skill directories and packaged plugins carry synced copies so installed or repo-local adapters work outside this repository.

Install the runtime once before enabling any MCP adapter, and ensure Dart's
global executable directory is on `PATH`:

```bash
dart pub global activate cockpit any
```

## Install With The Agent

Ask the current AI host to follow the self-contained installation guide:

```text
Install the cockpit skill for the current AI host by following https://github.com/cockpit-dev/cockpit/blob/main/skills/cockpit/INSTALL.md
```

The portable host-selection, copy, runtime, MCP, and verification instructions
live in [`skills/cockpit/INSTALL.md`](../skills/cockpit/INSTALL.md). This page
documents the repository's native adapter assets without duplicating that
installation workflow.

Host-native assets are included for Codex, Claude Code, Cursor, Kiro,
OpenCode, and OMP/Pi. A host outside that list is supported when it can load a
complete Agent Skill directory, launch a stdio MCP server, or execute the
installed CLI. Cockpit does not claim compatibility with a host that exposes
none of those extension surfaces.

## Codex

Codex supports installable plugins with `.codex-plugin/plugin.json`.

Repository asset:

```text
.agents/plugins/marketplace.json
plugins/codex/cockpit
```

The marketplace entry points Codex at the local plugin. The plugin exposes:

- `skills/cockpit` as a complete Codex skill.
- `.mcp.json` with the globally installed `cockpit_mcp` executable.

For direct MCP setup without installing the plugin:

```bash
dart pub global activate cockpit any
codex mcp add cockpit -- cockpit_mcp
```

## Claude Code

Claude Code supports plugins with `.claude-plugin/plugin.json`, skills, and `.mcp.json`.

Repository asset:

```text
.claude/skills/cockpit
.mcp.json
plugins/claude-code/cockpit
```

Repo-local Claude Code can discover `.claude/skills/cockpit` and the project `.mcp.json`. The plugin exposes:

- `skills/cockpit` as a complete Claude Code skill.
- `.mcp.json` with the globally installed `cockpit_mcp` executable.

For direct MCP setup without installing the plugin:

```bash
dart pub global activate cockpit any
claude mcp add --transport stdio cockpit -- cockpit_mcp
```

## Cursor

Cursor uses project rules, project skills, and project MCP config rather than this repository's plugin manifest.

Repository asset:

```text
.cursor/rules/cockpit.mdc
.cursor/skills/cockpit
.cursor/mcp.json
```

The rule gives Cursor the trigger, `.cursor/skills/cockpit` gives it the full on-demand workflow, and `.cursor/mcp.json` exposes the local MCP server:

```json
{
  "mcpServers": {
    "cockpit": {
      "type": "stdio",
      "command": "cockpit_mcp",
      "args": []
    }
  }
}
```

## Kiro

Kiro uses steering documents for project guidance, workspace MCP config for tools, and Powers for a distributable native bundle.

Repository asset:

```text
.kiro/steering/cockpit.md
.kiro/settings/mcp.json
plugins/kiro/cockpit
```

The workspace steering file is the repo-local trigger. `.kiro/settings/mcp.json` exposes the local MCP server. `plugins/kiro/cockpit` is the Kiro Power bundle with `POWER.md`, `mcp.json`, and the full skill copy.

## OpenCode

OpenCode discovers project skills from `.opencode/skills/<name>/SKILL.md`, also understands shared Agent Skills under `.agents/skills/<name>/SKILL.md`, and configures MCP servers through the `mcp` option. This repository uses `.opencode/skills/cockpit` for the OpenCode-native on-demand skill, `.agents/skills/cockpit` for shared agents, and `opencode.json` for the local MCP server.

Repository asset:

```text
opencode.json
.opencode/skills/cockpit
.agents/skills/cockpit
```

The repo-local config loads normal project instructions and the local MCP server:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "instructions": ["AGENTS.md"],
  "mcp": {
    "cockpit": {
      "type": "local",
      "command": ["cockpit_mcp"],
      "enabled": true
    }
  }
}
```

The skill body stays out of always-on instructions so OpenCode can load it only when a Cockpit task needs it.

## OMP / Oh My Pi

OMP / Pi discovers project skills from `.pi/skills/<name>/SKILL.md` and shared Agent Skills from `.agents/skills/<name>/SKILL.md`. The repository includes both so Pi-native and shared-agent discovery work without extra copying:

```text
.pi/skills/cockpit
.agents/skills/cockpit
```

If OMP is configured to import MCP servers from repo config, use the same
globally installed `cockpit_mcp` server. Otherwise run Cockpit through the CLI
commands in the skill.

## Verification

After installing any adapter:

1. Restart or reload the host so it rescans plugins, skills, rules, or steering files.
2. Ask the host to load the bundled self-contained `cockpit` skill.
3. Run `cockpit daemon status`, then `cockpit target discover`.
4. If MCP is configured, verify the host can see the Cockpit 2.0 workspace,
   target, operation, case, suite, run, and artifact resources.
5. Keep app proof proportional: inspect, act through an advertised operation
   or validated test document, re-inspect, and read report-backed evidence.
