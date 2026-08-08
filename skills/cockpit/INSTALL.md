# Install Cockpit For An AI Host

This directory is the complete, self-contained `cockpit` Skill. A complete AI
host integration has four parts:

1. the globally installed `cockpit` CLI and `cockpit_mcp` executable;
2. the whole Skill directory, including `SKILL.md`, `INSTALL.md`, `agents/`,
   `assets/`, and `references/`;
3. the host-native plugin, rule, steering, or MCP configuration it supports;
4. a host reload followed by CLI, Skill, and MCP verification.

Do not report a complete installation after copying only `SKILL.md`. Configure
MCP by default when the host supports it; use the CLI as the complete fallback
when it does not or when the user explicitly declines MCP.

## Preferred AI Prompt

Ask the current AI host to install every supported integration surface:

```text
Install Cockpit for the current AI host, including the CLI, complete cockpit Skill, native adapter, and cockpit_mcp when supported, by following https://github.com/cockpit-dev/cockpit/blob/main/skills/cockpit/INSTALL.md
```

Use the manual guidance below only when the host cannot complete the request.

## Common Runtime

Install the latest compatible release without embedding the current package
version in host configuration:

```bash
dart pub global activate cockpit any
```

Ensure Dart's global executable directory is on `PATH`, run `cockpit help`,
and confirm the host can resolve `cockpit_mcp`. Do not invoke `cockpit_mcp`
outside an MCP stdio handshake.

```bash
cockpit help
```

Every stdio MCP adapter launches `cockpit_mcp` with no arguments. It uses the
same per-user Supervisor, authorization, workspace isolation, and artifacts as
the CLI.

## Installation Rules

1. Identify the active host and install only its adapter below.
2. Prefer a native plugin or installer when one exists.
3. Otherwise copy this whole directory into the host's Skill directory and
   merge the MCP configuration without removing existing servers.
4. Copy real files. Do not leave a symlink to a temporary clone or any path
   outside the installed Skill directory. The source checkout may be deleted
   after installation.
5. Use project scope for repository adapters unless the host documents a
   stable user-scope location.

## Codex

The Cockpit Codex plugin bundles the complete Skill and MCP adapter. Install
the runtime first, then:

```bash
codex plugin marketplace add cockpit-dev/cockpit
codex plugin add cockpit@cockpit
```

Start a new Codex session. For direct MCP setup without the plugin:

```bash
codex mcp add cockpit -- cockpit_mcp
```

## Claude Code

The Claude Code plugin bundles the complete Skill and `.mcp.json` adapter:

```bash
claude plugin marketplace add cockpit-dev/cockpit
claude plugin install cockpit@cockpit --scope user
```

Run `/reload-plugins`. For direct MCP setup without the plugin:

```bash
claude mcp add --transport stdio cockpit -- cockpit_mcp
```

## Gemini CLI

Install the complete Skill and MCP server at user scope:

```bash
gemini skills install https://github.com/cockpit-dev/cockpit.git \
  --path skills/cockpit --scope user --consent
gemini mcp add --scope user cockpit cockpit_mcp
gemini skills list --all
gemini mcp list
```

## Cursor

Copy the whole Skill to `.cursor/skills/cockpit`. When installing from the
Cockpit repository, also copy `.cursor/rules/cockpit.mdc`; it provides the
project trigger without duplicating the Skill body. Merge this server into
`.cursor/mcp.json`:

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

Reload the Cursor window after changing Skills, rules, or MCP configuration.

## Kiro

For a project adapter, copy the complete Skill to
`.kiro/skills/cockpit`, install `.kiro/steering/cockpit.md`, and merge the
following Kiro-native local server into `.kiro/settings/mcp.json`:

```json
{
  "mcpServers": {
    "cockpit": {
      "command": "cockpit_mcp",
      "args": []
    }
  }
}
```

Do not add `type` to the workspace config; Kiro's own schema infers a local
server from `command`. Save the file to hot-reload it and confirm the Cockpit
server is connected in Kiro's MCP panel.

The distributable Power at `plugins/kiro/cockpit` uses the current Agent
Plugins format: `plugin.json`, a schema-qualified `mcp.json`, and the same
complete Skill. Open Powers, choose **Add Custom Power**, choose
**Import power from a folder**, and select that directory. The Power MCP schema
does require `type: stdio`; it is a different schema from the workspace file.
Kiro manages Power MCP servers internally and activates them with the Power;
do not also add that Power server to the user-level MCP configuration.

Reload Kiro and confirm the steering file can load
`.kiro/skills/cockpit/SKILL.md` before testing MCP. From Kiro's terminal, run
`cockpit --version` and `cockpit session list` to confirm its process inherits
Dart's global executable directory without requiring an active app. After a
Flutter project has the development shell described in `references/flutter.md`,
run `cockpit dev start`, then `cockpit dev status` as the live CLI smoke.

## OpenCode

Copy the complete Skill to `.opencode/skills/cockpit`, then merge this entry
into the project's `opencode.json`:

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

Restart OpenCode so it reloads both surfaces.

## Pi

Copy the complete Skill to `~/.pi/agent/skills/cockpit` or the project-local
`.pi/skills/cockpit`. Pi has no built-in MCP client, so use the installed
`cockpit` CLI through its shell tool. Run `/reload`, then load the workflow
with `/skill:cockpit`. When automatic discovery is unavailable, start Pi with:

```bash
pi --skill /absolute/path/to/cockpit
```

## Oh My Pi (OMP)

Copy the complete Skill to `~/.omp/agent/skills/cockpit` or
`.omp/skills/cockpit`, then merge the stdio server shown for Cursor into
`.omp/mcp.json`. Run `/reload-plugins`, `/skill:cockpit`, `/mcp reload`, and
`/mcp test cockpit` to verify both surfaces.

## Cline

Copy the complete Skill to `~/.cline/skills/cockpit` or
`.cline/skills/cockpit`. Add a stdio MCP server named `cockpit`, executable
`cockpit_mcp`, and no arguments through Cline's MCP UI. Cline owns its
user-specific MCP settings, so do not commit a machine-specific settings file.
Reload Cline after installing the Skill or changing MCP.

## GitHub Copilot CLI

Copy the complete Skill to `.agents/skills/cockpit` and merge the stdio server
shown for Cursor into the project `.mcp.json`. Confirm both integrations:

```bash
copilot plugins list --kind mcp --kind skill
```

## Windsurf

Copy the complete Skill to `.agents/skills/cockpit`. Add a stdio MCP server
named `cockpit`, executable `cockpit_mcp`, and no arguments through Windsurf's
current MCP settings, then reload the workspace.

## Roo Code

Copy the complete Skill to `.agents/skills/cockpit`. Add a stdio MCP server
named `cockpit`, executable `cockpit_mcp`, and no arguments through Roo Code's
MCP settings, then reload the extension.

## Other Hosts

For any host that supports the Agent Skills convention, install the complete
directory at `.agents/skills/cockpit`. If it also supports stdio MCP, configure
`cockpit_mcp` with no arguments. A host without either extension surface can
still use the full Cockpit control and reporting API through the installed
`cockpit` CLI; do not claim native Skill or MCP integration when the host does
not expose it.

## Verification

1. Reload or restart the host so it rescans plugins, Skills, rules, steering,
   and MCP configuration.
2. Confirm the host discovers `cockpit` and can open `INSTALL.md`, `agents/`,
   `assets/`, and `references/` from inside the installed Skill directory.
3. Run `cockpit help`, `cockpit daemon status`, and `cockpit target discover`.
4. When MCP is supported, confirm the host starts `cockpit_mcp` and can list
   Cockpit roots, workspaces, operations, targets, documents, cases, suites,
   runs, and artifacts.
5. Report the installed Skill path, CLI path, native adapter, MCP status, and
   any host capability that is unavailable.
