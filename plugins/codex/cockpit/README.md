# Cockpit 2.0 Codex Plugin

This plugin exposes the Cockpit 2.0 skill and authenticated MCP control plane
for cross-platform development and black-box application E2E.

## Install

Use it as a local plugin or add it to a Codex marketplace that points at `plugins/codex/cockpit`.

Install the published CLI once and keep Dart's global executable directory on
`PATH`:

```bash
dart pub global activate cockpit ^2.0.0
```

The plugin starts MCP through the dedicated `cockpit_mcp` executable, so the
target workspace does not need to declare a `cockpit` dependency.

## Source Of Truth

The AI and client workflow is bundled at:

```text
skills/cockpit/SKILL.md
```
