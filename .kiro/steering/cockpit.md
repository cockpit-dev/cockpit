# Cockpit 2.0

Use this steering note when Flutter development or black-box application
testing needs live control, E2E execution, reports, or evidence.

Use the Cockpit Power when installed, or read
`skills/cockpit/SKILL.md` before controlling an application or
claiming validation.

```bash
dart run cockpit daemon status
dart run cockpit target discover
dart run cockpit target inspect --target-id <targetId> --profile minimal
dart run cockpit operation list --workspace-id <workspaceId>
```

Use a validated `cockpit.test/v2` case or suite for reusable E2E. Prefer
`.kiro/settings/mcp.json` when MCP is available. Judge success from terminal
run state, assertions, structured errors, and report-backed evidence.
