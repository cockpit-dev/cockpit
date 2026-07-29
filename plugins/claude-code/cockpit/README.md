<p align="center">
  <img src="https://raw.githubusercontent.com/cockpit-dev/cockpit/main/assets/brand/cockpit-mark.svg" width="128" alt="Cockpit logo">
</p>

# Cockpit 2.0 Claude Code Plugin

This plugin exposes the Cockpit 2.0 skill and authenticated MCP control plane
for cross-platform development and black-box application E2E.

## Install

Install from a local Claude Code plugin marketplace or copy this plugin directory into a marketplace under `plugins/cockpit`.

Then reload plugins in Claude Code:

```text
/reload-plugins
```

Install the published CLI once and keep Dart's global executable directory on
`PATH`:

```bash
dart pub global activate cockpit ^2.1.0
```

The plugin starts MCP through the dedicated `cockpit_mcp` executable, so the
target workspace does not need to declare a `cockpit` dependency.

## Source Of Truth

The AI and client workflow is bundled at:

```text
skills/cockpit/SKILL.md
```
