<p align="center">
  <img src="https://raw.githubusercontent.com/cockpit-dev/cockpit/main/assets/brand/cockpit-mark.svg" width="128" alt="Cockpit logo">
</p>

# Cockpit 3.0 Claude Code Plugin

This plugin exposes the Cockpit 3.0 skill and authenticated MCP control plane
for cross-platform development and black-box application E2E.

## Install

Add the repository marketplace and install the plugin:

```bash
claude plugin marketplace add cockpit-dev/cockpit
claude plugin install cockpit@cockpit --scope user
```

Then reload plugins in Claude Code:

```text
/reload-plugins
```

Install the published CLI once and keep Dart's global executable directory on
`PATH`:

```bash
dart pub global activate cockpit any
```

The plugin starts MCP through the dedicated `cockpit_mcp` executable, so the
target workspace does not need to declare a `cockpit` dependency.

## Source Of Truth

The AI and client workflow is bundled at:

```text
skills/cockpit/SKILL.md
```
