---
inclusion: manual
name: cockpit
description: Load only when the user explicitly asks to use Cockpit or work on Cockpit itself.
---

# Cockpit

This steering note is opt-in. Load it only when the user explicitly asks to use
Cockpit or to work on Cockpit itself. Generic Flutter development, UI work,
debugging, screenshots, or E2E requests do not activate it.

Load the self-contained Cockpit workflow from
`.kiro/skills/cockpit/SKILL.md` before controlling an application or
claiming validation. When the Cockpit Power is installed, its bundled
`skills/cockpit` directory provides the same workflow; select or invoke this
Power only for explicit Cockpit requests.

```bash
cockpit session list
cockpit dev status
cockpit dev inspect "TARGET"
cockpit dev diagnose --view more
```

Use a validated `cockpit.test/v2` case or suite for reusable E2E. Prefer the
CLI task commands for the shortest Flutter loop and use
`.kiro/settings/mcp.json` when MCP resources are needed. Judge success from
terminal run state, assertions, structured errors, and report-backed evidence.
