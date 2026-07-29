---
inclusion: auto
name: cockpit
description: Use when Flutter development or black-box application testing needs live control, E2E execution, reports, or evidence.
---

# Cockpit 2.0

Use this steering note when Flutter development or black-box application
testing needs live control, E2E execution, reports, or evidence.

Load the self-contained Cockpit workflow from
`.agents/skills/cockpit/SKILL.md` before controlling an application or
claiming validation. When the Cockpit Power is installed, its bundled
`skills/cockpit` directory provides the same workflow.

```bash
cockpit daemon status
cockpit target discover
cockpit target inspect --target-id <targetId> --profile minimal
cockpit operation list --workspace-id <workspaceId>
```

Use a validated `cockpit.test/v2` case or suite for reusable E2E. Prefer
`.kiro/settings/mcp.json` when MCP is available. Judge success from terminal
run state, assertions, structured errors, and report-backed evidence.
