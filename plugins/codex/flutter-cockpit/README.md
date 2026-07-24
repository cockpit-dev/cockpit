# Flutter Cockpit 2.0 Codex Plugin

This plugin exposes the Cockpit 2.0 skill and authenticated MCP control plane
for Flutter development and black-box application E2E.

## Install

Use it as a local plugin or add it to a Codex marketplace that points at `plugins/codex/flutter-cockpit`.

The MCP server starts with:

```bash
dart run cockpit serve-mcp
```

Install the Dart packages first so `cockpit` resolves in the target workspace.

## Source Of Truth

The AI and client workflow is bundled at:

```text
skills/flutter-cockpit/SKILL.md
```
