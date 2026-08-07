---
inclusion: auto
name: cockpit
description: Use when Flutter development or black-box application testing needs live control, E2E execution, reports, or evidence.
---

# Cockpit 3.0

Use this steering note when Flutter development or black-box application
testing needs live control, E2E execution, reports, or evidence.

Load the self-contained Cockpit workflow from
`.kiro/skills/cockpit/SKILL.md` before controlling an application or
claiming validation. When the Cockpit Power is installed, its bundled
`skills/cockpit` directory provides the same workflow and activates for
Cockpit, Flutter debugging, UI automation, and E2E requests.

```bash
cockpit dev status
cockpit dev inspect
cockpit dev diagnose --verbosity standard
```

Use a validated `cockpit.test/v2` case or suite for reusable E2E. Prefer the
CLI task commands for the shortest Flutter loop and use
`.kiro/settings/mcp.json` when MCP resources are needed. Judge success from
terminal run state, assertions, structured errors, and report-backed evidence.
