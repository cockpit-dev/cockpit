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
  `plugins/claude-code/cockpit`
- Cursor rule, skill, and MCP: `.cursor/rules/cockpit.mdc`,
  `.cursor/skills/cockpit`, `.cursor/mcp.json`
- Kiro steering, Power, and MCP: `.kiro/steering/cockpit.md`,
  `plugins/kiro/cockpit`, `.kiro/settings/mcp.json`
- OpenCode skill and config: `.opencode/skills/cockpit`, `opencode.json`
- Shared Agent Skill and Pi/OMP skill: `.agents/skills/cockpit`,
  `.pi/skills/cockpit`

Use the native adapter when the host supports it. Otherwise install this
portable skill directory and configure the `cockpit_mcp` stdio executable if
the host supports MCP.

## Typical Skill Directories

These are common locations; the host's current documentation is authoritative:

- Codex and shared Agent Skills: `~/.agents/skills/cockpit`
- Codex legacy/personal fallback: `~/.codex/skills/cockpit`
- Claude Code: `~/.claude/skills/cockpit`
- Cursor project skill: `.cursor/skills/cockpit`
- OpenCode project skill: `.opencode/skills/cockpit`
- Pi/OMP project skill: `.pi/skills/cockpit`

Copy the complete `skills/cockpit` directory to the selected destination. A
stable symlink is acceptable only when its source will remain available. Never
link an installed skill to a temporary checkout.

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
