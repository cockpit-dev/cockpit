# Install Cockpit For An AI Host

This directory is the complete, self-contained `cockpit` Skill. A complete AI
host integration has a shared runtime and one active AI control surface:

1. the globally installed Cockpit runtime (`cockpit` and `cockpit_mcp`);
2. the whole Skill directory, including `SKILL.md`, `INSTALL.md`, `agents/`,
   `assets/`, and `references/`;
3. the CLI + Skill as the default control surface, or an optional host-native
   MCP configuration when typed tools are needed; a native plugin may bundle
   both;
4. a host reload followed by verification through the selected surface.

Do not report a complete installation after copying only `SKILL.md`. Use CLI +
Skill by default. Enable MCP only when the host cannot reliably run shell
commands or the user explicitly requests typed tools. Installing both
executables is not duplicate runtime state—`cockpit_mcp` is another transport
over the same Supervisor—but exposing both as active AI entry points is
unnecessary context and can cause duplicate mutations.

## Preferred AI Prompt

Ask the current AI host to install the shared runtime and the default CLI +
Skill integration; enable MCP only when the host needs typed tools:

```text
First fetch and read the complete Cockpit installation guide with `curl -fsSL https://raw.githubusercontent.com/cockpit-dev/cockpit/main/skills/cockpit/INSTALL.md`, then install or update the Cockpit runtime once and load the complete Skill. Use CLI + Skill as the default control surface; configure one Cockpit MCP server only if this host cannot reliably run shell commands or typed tools are explicitly needed. Do not configure a second MCP server or duplicate Skill copy.
```

Use the manual guidance below only when the host cannot complete the request.

Cockpit is opt-in on every host. Installing the CLI, Skill, plugin, or MCP
server does not authorize Cockpit to inspect, control, start, stop, or validate
an application automatically. Activate it only after the user explicitly asks
to use Cockpit or work on Cockpit itself.

## Common Runtime

Cockpit is a host-side Dart executable, not a Flutter application dependency.
Install and update it with `dart`; never use
`flutter pub global activate cockpit`, and do not run host installation from
an app's dependency graph.
Flutter is only required later for `cockpit dev` against a Flutter project.

Install the runtime:

```bash
dart pub global activate cockpit any
```

After the first installation, check for an upgrade:

```bash
cockpit update --check
```

Run the full update only when the check returns a `next` value for
`cockpit update`; when the installed version is already current, skip it. This
avoids needless activation and AOT compilation on legacy or source-installed
runtimes. When an update is needed, run:

```bash
cockpit update
```

It updates the CLI and running Supervisor to the latest verified Pub release
while preserving local authorization and durable state. Then run:

```bash
cockpit skill
```

`cockpit skill` prints the stable prompt for refreshing the current host's
complete Skill and default CLI integration; MCP is an optional typed transport.

The host runtime resolves only Cockpit's own global Pub package graph. If an
upgrade error mentions an unrelated Flutter plugin such as
`ffmpeg_kit_extended_flutter` or Dart `native-assets`, do not add compiler
experiment flags. Check `dart --version`, `which dart`, `which cockpit`, and
`cockpit --version`; reinstall with `dart pub global activate cockpit any` from
a neutral directory if the host command is mixed with an app's Flutter graph.

Update the host-native plugin through that host's plugin manager. For a manual
Skill installation, stage the complete new Skill directory, validate it, then
atomically replace the old directory. Never merge-copy a new Skill over the old
one because removed files from earlier releases would remain active.

Ensure Dart's global executable directory is on `PATH`, run `cockpit help`,
and confirm the host can resolve `cockpit_mcp`. Do not invoke `cockpit_mcp`
outside an MCP stdio handshake.

```bash
cockpit help
```

Every stdio MCP adapter launches `cockpit_mcp` with no arguments. It uses the
same per-user Supervisor, authorization, workspace isolation, and artifacts as
the CLI. MCP and CLI calls must not be run twice for one mutation; choose one
surface per task and keep the other as a fallback.

## Installation Rules

1. Identify the active host and install only its adapter below.
2. Prefer a native plugin or installer when one exists.
3. Otherwise atomically replace this whole directory in the host's Skill
   directory and merge the MCP configuration without removing existing servers.
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

For an existing installation, refresh the marketplace snapshot before running
the install command again:

```bash
codex plugin marketplace upgrade cockpit
codex plugin add cockpit@cockpit
```

Start a new Codex session after installing or updating. For direct MCP setup
without the plugin:

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
Kiro manages Power MCP servers internally. Select or invoke this Power only
when the user explicitly requests Cockpit; generic Flutter debugging, UI
automation, or E2E work must not activate it. Do not also add that Power server
to the user-level MCP configuration.

Reload Kiro and confirm the steering file can load
`.kiro/skills/cockpit/SKILL.md` before testing MCP. From Kiro's terminal, run
`cockpit --version` and `cockpit session list` to confirm its process inherits
Dart's global executable directory without requiring an active app. After a
Flutter project has the development shell described in `references/flutter.md`,
run `cockpit target discover`, choose the exact device id, then run
`cockpit dev start --device <id>` and `cockpit dev status` as the live CLI
smoke. In Kiro's MCP resource browser, confirm the server can list Cockpit
operations and read `cockpit://operations/schema`.

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
shown for Cursor into the project `.mcp.json`. In the Copilot CLI session,
reload and confirm both integrations:

```text
/skills reload
/skills info cockpit
/mcp show
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
`cockpit_mcp` with no arguments. Otherwise use the installed `cockpit` CLI.

## Verification

1. Reload or restart the host so it rescans plugins, Skills, rules, steering,
   and MCP configuration.
2. Confirm the host discovers `cockpit` and can open `INSTALL.md`, `agents/`,
   `assets/`, and `references/` from inside the installed Skill directory.
3. For a host-only check, run `cockpit help`, `cockpit --version`,
   `cockpit daemon status`, and `cockpit session list`.
4. Before launching or testing an app, run `cockpit target discover` and read
   the exact `id`, `name`, `platform`, `emulator`, and `sdk` rows. Pass the
   selected id to `cockpit dev start --device <id>` or
   `flutter test ... -d <id>`. If multiple compatible rows exist, ask the user
   which exact one to use; never choose the host, rely on Flutter's default, or
   switch between a simulator and a physical device implicitly. If start reports
   `deviceAmbiguous`, choose one listed id; if it reports `deviceNotFound`, repair
   that same device and rediscover it. For a registered black-box target, follow
   discovery with `cockpit target inspect --target-id <id> --profile evidence`
   and require the needed native capabilities. Discovery is not required for
   installing the host runtime or Skill itself.
5. When MCP is supported, confirm the host starts `cockpit_mcp` and can list
   Cockpit roots, workspaces, operations, targets, documents, cases, suites,
   runs, and artifacts.
6. Report the installed Skill path, CLI path, native adapter, MCP status, and
   any host capability that is unavailable.
