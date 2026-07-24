# Flutter Cockpit 2.0 Claude Code Plugin

This plugin exposes the Cockpit 2.0 skill and authenticated MCP control plane
for Flutter development and black-box application E2E.

## Install

Install from a local Claude Code plugin marketplace or copy this plugin directory into a marketplace under `plugins/flutter-cockpit`.

Then reload plugins in Claude Code:

```text
/reload-plugins
```

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
