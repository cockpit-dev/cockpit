<p align="center">
  <img src="https://raw.githubusercontent.com/cockpit-dev/cockpit/main/assets/brand/cockpit-mark.svg" width="128" alt="Cockpit logo">
</p>

# Cockpit 2.0 Codex Plugin

This plugin exposes the Cockpit 2.0 skill and authenticated MCP control plane
for cross-platform development and black-box application E2E.

## Install

Add the repository marketplace, install Cockpit, then start a new Codex
session so the bundled Skill and MCP server are loaded:

```bash
codex plugin marketplace add cockpit-dev/cockpit
codex plugin add cockpit@cockpit
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
