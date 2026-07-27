# Cockpit 2.0

Use this power when application development or black-box testing needs
live control, reusable E2E cases or suites, system actions, screenshots,
recordings, reports, or regression evidence.

Install the runtime once and ensure Dart's global executable directory is on
`PATH`:

```bash
dart pub global activate cockpit ^2.0.0
```

## Bundled Assets

- `mcp.json` exposes the globally installed `cockpit_mcp` server.
- `skills/cockpit/SKILL.md` defines the Cockpit 2.0 AI workflow.

## Control Plane

Use the authenticated Supervisor and resolve explicit workspace and target
identities before acting:

```bash
cockpit daemon start --yolo
cockpit root add --path /absolute/project/root
cockpit workspace register --root-id <rootId> --path /absolute/checkout
cockpit target discover
cockpit target inspect --target-id <targetId> --profile minimal
```

For focused development work, choose an advertised operation. For repeatable
validation, submit a validated `cockpit.test/v2` case or suite:

```bash
cockpit operation list --workspace-id <workspaceId>
cockpit operation run --workspace-id <workspaceId> --kind <kind> \
  --input-file /tmp/operation.json --idempotency-key <uniqueKey>
cockpit case validate --file case.yaml --format yaml
cockpit suite run --suite-id <suiteId> --idempotency-key <uniqueKey>
cockpit run events --run-id <runId> --after-sequence 0
cockpit suite report --run-id <runId>
```

Trust only advertised capabilities. A pass requires terminal run state,
successful assertions, no disqualifying runtime errors, and readable
digest-checked evidence.
