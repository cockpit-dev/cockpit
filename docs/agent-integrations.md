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

Host-native assets are included for Codex, Claude Code, Cursor, Gemini CLI,
Kiro, OpenCode, Pi, Oh My Pi, and Cline. GitHub Copilot, Windsurf, and Roo Code
use the shared Agent Skills convention. A host outside that list is supported
when it can load a complete Agent Skill directory, launch a stdio MCP server,
or execute the installed CLI. Cockpit does not claim compatibility with a host
that exposes none of those extension surfaces.

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

Add the repository marketplace, install Cockpit, then start a new Codex
session so the bundled Skill and MCP server are loaded:

```bash
codex plugin marketplace add cockpit-dev/cockpit
codex plugin add cockpit@cockpit
```

For direct MCP setup without installing the plugin:

```bash
dart pub global activate cockpit any
codex mcp add cockpit -- cockpit_mcp
```

## Claude Code

Claude Code supports plugins with `.claude-plugin/plugin.json`, skills, and `.mcp.json`.

Repository asset:

```text
.claude-plugin/marketplace.json
.claude/skills/cockpit
.mcp.json
plugins/claude-code/cockpit
```

Repo-local Claude Code can discover `.claude/skills/cockpit` and the project `.mcp.json`. The plugin exposes:

- `skills/cockpit` as a complete Claude Code skill.
- `.mcp.json` with the globally installed `cockpit_mcp` executable.

Install the repository marketplace and plugin without embedding a package
release number:

```bash
claude plugin marketplace add cockpit-dev/cockpit
claude plugin install cockpit@cockpit --scope user
```

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

## Gemini CLI

Gemini CLI discovers the shared Agent Skill convention and project MCP
configuration directly.

Repository asset:

```text
.agents/skills/cockpit
.gemini/settings.json
```

The repo-local skill is available without another copy. For direct user-level
installation, use Gemini's native installer so the complete skill directory is
retained. The project config starts the globally installed `cockpit_mcp`;
equivalent user-level setup is:

```bash
gemini skills install https://github.com/cockpit-dev/cockpit.git \
  --path skills/cockpit --scope user --consent
gemini mcp add --scope user cockpit cockpit_mcp
gemini skills list --all
gemini mcp list
```

## Kiro

Kiro uses steering documents for project guidance, workspace MCP config for tools, and Powers for a distributable native bundle.

Repository asset:

```text
.kiro/steering/cockpit.md
.kiro/settings/mcp.json
plugins/kiro/cockpit
```

The auto-included-on-demand workspace steering file is the repo-local trigger.
`.kiro/settings/mcp.json` exposes the local MCP server.
`plugins/kiro/cockpit` is the Kiro Power bundle with `POWER.md`, `mcp.json`,
and the full skill copy.

## OpenCode

OpenCode discovers project skills from `.opencode/skills/<name>/SKILL.md`, also understands shared Agent Skills under `.agents/skills/<name>/SKILL.md`, and configures MCP servers through the `mcp` option. This repository uses `.opencode/skills/cockpit` for the OpenCode-native on-demand skill, `.agents/skills/cockpit` for shared agents, and `opencode.json` for the local MCP server.

Repository asset:

```text
opencode.json
.opencode/skills/cockpit
.agents/skills/cockpit
```

The repo-local config exposes the local MCP server. OpenCode discovers
`AGENTS.md` independently when a project tracks one, so this portable config
does not depend on a repository-external instruction file:

```json
{
  "$schema": "https://opencode.ai/config.json",
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

## Pi

Pi discovers project skills from `.pi/skills/<name>/SKILL.md` and
`.agents/skills/<name>/SKILL.md`. The repository includes both forms:

```text
.pi/skills/cockpit
.agents/skills/cockpit
```

Pi does not provide a built-in MCP client. Use Cockpit through Pi's shell tool
and the installed `cockpit` CLI. Start Pi with an explicit Skill when automatic
discovery is unavailable:

```bash
pi --skill /absolute/path/to/cockpit
```

Use `/reload` after changing the installed files and `/skill:cockpit` to load
the workflow explicitly.

## Oh My Pi

Oh My Pi (OMP) gives its native `.omp/skills` directory the highest Skill
priority and supports project MCP configuration at `.omp/mcp.json`.

Repository asset:

```text
.omp/skills/cockpit
.omp/mcp.json
```

The MCP config launches the globally installed `cockpit_mcp` stdio server.
After installation or changes, use `/reload-plugins`, `/skill:cockpit`,
`/mcp reload`, and `/mcp test cockpit` to verify both surfaces.

## GitHub Copilot

GitHub Copilot CLI discovers shared project Skills and the project MCP config
already included by Cockpit:

```text
.agents/skills/cockpit
.mcp.json
```

Run `copilot plugins list --kind mcp --kind skill` to confirm discovery. No
Copilot-only Skill copy is needed.

## Windsurf

Windsurf discovers `.agents/skills/cockpit` directly. Use the installed
`cockpit` CLI from the agent shell; configure `cockpit_mcp` through Windsurf's
current MCP settings only when MCP tools are desired.

## Cline

Cline's native project Skill is included at:

```text
.cline/skills/cockpit
```

Use the installed `cockpit` CLI from Cline's terminal tools. Cline MCP settings
are user-managed, so add the `cockpit_mcp` stdio executable through Cline's MCP
UI when required instead of committing a machine-specific settings file.

## Roo Code

Roo Code discovers `.agents/skills/cockpit` directly. Use the installed
`cockpit` CLI from the agent shell; add `cockpit_mcp` through Roo Code's MCP
settings when native tools are required. No duplicate Roo-only Skill is needed.

## Verification

After installing any adapter:

1. Restart or reload the host so it rescans plugins, skills, rules, or steering files.
2. Ask the host to load the bundled self-contained `cockpit` skill.
3. Run `cockpit daemon status`, then `cockpit target discover`.
4. If MCP is configured, verify the host can see the Cockpit 2.0 workspace,
   target, operation, case, suite, run, and artifact resources.
5. Keep app proof proportional: inspect, act through an advertised operation
   or validated test document, re-inspect, and read report-backed evidence.
