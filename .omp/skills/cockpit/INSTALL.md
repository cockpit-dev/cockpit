# Install `cockpit`

This directory is the complete, self-contained `cockpit` skill. Install the
whole directory, not only `SKILL.md`; the skill also needs its bundled
`agents/`, `assets/`, and `references/` files.

## Preferred AI Prompt

Ask the current AI host to install the skill:

```text
Install the cockpit skill for the current AI host by following https://github.com/cockpit-dev/cockpit/blob/main/skills/cockpit/INSTALL.md
```

Use the manual guidance below only when the host cannot install it directly.

## Host-First Rule

Identify the active AI host and use its native plugin, skill, rule, steering,
or MCP mechanism when available. Do not assume the host is Codex or Claude
Code. After installation, every file needed by the skill must live inside the
installed skill directory; do not leave links to a temporary clone or depend
on paths elsewhere in the Cockpit source repository.

## Repository Adapters

The Cockpit repository includes native adapters for common hosts:

- Codex marketplace and plugin: `.agents/plugins/marketplace.json`,
  `plugins/codex/cockpit`
- Claude Code skill and plugin: `.claude/skills/cockpit`,
  `.claude-plugin/marketplace.json`, `plugins/claude-code/cockpit`
- Cursor rule, skill, and MCP: `.cursor/rules/cockpit.mdc`,
  `.cursor/skills/cockpit`, `.cursor/mcp.json`
- Kiro steering, Power, and MCP: `.kiro/steering/cockpit.md`,
  `plugins/kiro/cockpit`, `.kiro/settings/mcp.json`
- Gemini CLI shared skill and MCP: `.agents/skills/cockpit`,
  `.gemini/settings.json`
- OpenCode skill and config: `.opencode/skills/cockpit`, `opencode.json`
- Pi skill and shared Agent Skill: `.pi/skills/cockpit`,
  `.agents/skills/cockpit`
- Oh My Pi skill and MCP: `.omp/skills/cockpit`, `.omp/mcp.json`
- Cline skill: `.cline/skills/cockpit`
- GitHub Copilot skill and MCP: `.agents/skills/cockpit`, `.mcp.json`
- Windsurf and Roo Code shared skill: `.agents/skills/cockpit`

Use the native adapter when the host supports it. Otherwise install this
portable skill directory and configure the `cockpit_mcp` stdio executable if
the host supports MCP.

## Native Installers

For Codex, add the repository marketplace, install Cockpit, then start a new
session so the bundled Skill and MCP server are loaded:

```bash
codex plugin marketplace add cockpit-dev/cockpit
codex plugin add cockpit@cockpit
```

For Claude Code, install the repository marketplace and plugin:

```bash
claude plugin marketplace add cockpit-dev/cockpit
claude plugin install cockpit@cockpit --scope user
```

For Gemini CLI, install the complete skill and MCP server at user scope:

```bash
gemini skills install https://github.com/cockpit-dev/cockpit.git \
  --path skills/cockpit --scope user --consent
gemini mcp add --scope user cockpit cockpit_mcp
```

## Typical Skill Directories

These are common locations; the host's current documentation is authoritative:

- Codex and shared Agent Skills: `~/.agents/skills/cockpit`
- Codex legacy/personal fallback: `~/.codex/skills/cockpit`
- Claude Code: `~/.claude/skills/cockpit`
- Cursor project skill: `.cursor/skills/cockpit`
- Gemini CLI: `~/.gemini/skills/cockpit` or project `.agents/skills/cockpit`
- OpenCode project skill: `.opencode/skills/cockpit`
- Pi: `~/.pi/agent/skills/cockpit` or project `.pi/skills/cockpit`
- Oh My Pi: `~/.omp/agent/skills/cockpit` or project `.omp/skills/cockpit`
- Cline: `~/.cline/skills/cockpit` or project `.cline/skills/cockpit`
- GitHub Copilot, Windsurf, and Roo Code: project `.agents/skills/cockpit`

Copy the complete `skills/cockpit` directory to the selected destination. The
installed directory must contain real copies of every bundled file and no
symbolic link that resolves outside it. A host may delete its downloaded source
checkout after installation without breaking the skill.

## Host Runtime Notes

- Pi has no built-in MCP client. Run Cockpit through Pi's shell tool, use
  `/reload` after installation, and load the workflow with `/skill:cockpit`.
- Oh My Pi supports `.omp/mcp.json`. Reload with `/reload-plugins`, then verify
  with `/skill:cockpit`, `/mcp reload`, and `/mcp test cockpit`.
- GitHub Copilot CLI uses `.agents/skills/cockpit` and `.mcp.json`; verify both
  with `copilot plugins list --kind mcp --kind skill`.
- Windsurf and Roo Code use the shared `.agents/skills/cockpit` directory.
- Cline uses `.cline/skills/cockpit`; add `cockpit_mcp` through Cline's MCP UI
  only when native MCP tools are needed.

## Install Runtime And MCP

Install the latest compatible CLI without embedding the current release number
in host configuration:

```bash
dart pub global activate cockpit any
```

Ensure Dart's global executable directory is on `PATH`. Configure the host's
stdio MCP server with executable `cockpit_mcp` and no arguments. Hosts without
MCP can use the same capabilities through the `cockpit` CLI.

## Verification

1. Reload or restart the AI host so it rescans skills and plugins.
2. Confirm the host discovers the `cockpit` skill and can open this
   `INSTALL.md` plus `agents/`, `assets/`, and `references/` inside the same
   installed directory.
3. Run `cockpit help`, `cockpit daemon status`, and `cockpit target discover`.
4. When MCP is configured, confirm the host can start `cockpit_mcp` and list
   Cockpit resources or tools.
5. Report the installed skill path, MCP configuration, and any host capability
   that is unavailable.
