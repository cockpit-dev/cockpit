# Cockpit 2.0

Use this power when application development or black-box testing needs
live control, reusable E2E cases or suites, system actions, screenshots,
recordings, reports, or regression evidence.

## Bundled Assets

- `mcp.json` exposes `cockpit -> dart run cockpit serve-mcp`.
- `skills/cockpit/SKILL.md` defines the Cockpit 2.0 AI workflow.

## Control Plane

Use the authenticated Supervisor and resolve explicit workspace and target
identities before acting:

```bash
dart run cockpit daemon start
dart run cockpit root add --path /absolute/project/root
dart run cockpit workspace register --root-id <rootId> --path /absolute/checkout
dart run cockpit target discover
dart run cockpit target inspect --target-id <targetId> --profile minimal
```

For focused development work, choose an advertised operation. For repeatable
validation, submit a validated `cockpit.test/v2` case or suite:

```bash
dart run cockpit operation list --workspace-id <workspaceId>
dart run cockpit operation run --workspace-id <workspaceId> --kind <kind> \
  --input-file /tmp/operation.json --idempotency-key <uniqueKey>
dart run cockpit case validate --file case.yaml --format yaml
dart run cockpit suite run --suite-id <suiteId> --idempotency-key <uniqueKey>
dart run cockpit run events --run-id <runId> --after-sequence 0
dart run cockpit suite report --run-id <runId>
```

Trust only advertised capabilities. A pass requires terminal run state,
successful assertions, no disqualifying runtime errors, and readable
digest-checked evidence.
