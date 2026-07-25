---
name: cockpit
description: Use when application development or black-box application E2E work must prove live UI, interaction, route, runtime, system control, screenshots, recordings, cases, suites, or regression state across mobile, desktop, web, or Flutter targets through Cockpit 2.0.
---

# Cockpit 2.0

Use the authenticated Supervisor as the single control plane. Resolve explicit
workspace, target, and run identities; inspect capabilities before acting; and
judge results from terminal state plus evidence rather than command success.

Read [`references/protocol.md`](references/protocol.md) when exact contract or
command selection is uncertain.

## Workflow

1. **Bootstrap**: run `dart run cockpit daemon status`; start the daemon when
   unavailable. Register the project root and checkout once.
2. **Resolve**: read workspace IDs, run `target discover`, then register or
   reuse a workspace-owned target. Never guess IDs.
3. **Inspect**: run `target inspect --profile minimal` and `operation list`.
   Choose only reported capabilities and operation parameters.
4. **Act**: use `operation run` for a focused development action. Use a
   `cockpit.test/v2` case or suite for reusable E2E.
5. **Observe**: re-inspect state and errors after mutation. For a run, consume
   events until terminal and then read its report.
6. **Prove**: read only report-referenced, digest-checked artifacts. Capture a
   screenshot for visible claims and a recording for motion or reproduction.

## Bootstrap Commands

```bash
dart run cockpit daemon start
dart run cockpit root add --path /absolute/project/root
dart run cockpit workspace register --root-id <rootId> --path /absolute/checkout
dart run cockpit target discover
```

CLI output defaults to compact semantic text optimized for agents. Use
`--stdout-format json` only when exact structured data is required, or
`--output <file>` to preserve the complete JSON response while stdout returns a
small path/size/SHA-256 receipt. The workspace can be inferred only when the
current directory belongs to exactly one active workspace.

## Targets

For installed black-box applications, register the real device and platform
app identifier. Cockpit supports capability-driven Android, iOS, macOS,
Windows, Linux, browser, and Flutter targets. Use a target-scoped `--wda-url`
for iOS automation when needed.
For Flutter, keep bridge wiring in a development shell and index its entrypoint
document; production Flutter code must not import the bridge package.

```bash
dart run cockpit target register \
  --workspace-id <workspaceId> \
  --platform <platform> \
  --device-id <deviceId> \
  --target-kind <targetKind> \
  --environment test \
  --app-id <appId> \
  --idempotency-key <uniqueKey>
dart run cockpit target launch \
  --workspace-id <workspaceId> \
  --target-id <targetId> \
  --idempotency-key <uniqueKey>
dart run cockpit target inspect --target-id <targetId> --profile minimal
```

Do not treat persisted target records as liveness proof. Inspect the target.
Unsupported actions remain unavailable; never simulate success.

## Development Operations

```bash
dart run cockpit operation list --workspace-id <workspaceId>
dart run cockpit operation run \
  --workspace-id <workspaceId> \
  --kind <advertisedKind> \
  --input-file /tmp/operation.json \
  --idempotency-key <uniqueKey>
```

Prefer a small read-act-read loop. Use hot reload/restart only when advertised.
After timeout or transport loss, read state before retrying non-idempotent work.

## E2E Cases And Suites

Author YAML or JSON against
`packages/cockpit_protocol/schema/cockpit.test.v2.schema.json`. Start from
`packages/cockpit/example/cases/` or `packages/cockpit/example/suites/`.

```bash
dart run cockpit case validate --file case.yaml --format yaml
dart run cockpit suite validate --file suite.yaml --format yaml
dart run cockpit case run --case-id <caseId> --idempotency-key <uniqueKey>
dart run cockpit suite run --suite-id <suiteId> --idempotency-key <uniqueKey>
dart run cockpit run events --run-id <runId> --after-sequence 0 \
  --stdout-format jsonl
dart run cockpit run get --run-id <runId>
dart run cockpit suite report --run-id <runId>
dart run cockpit artifact list --run-id <runId>
dart run cockpit artifact read \
  --run-id <runId> --artifact-id <artifactId> \
  --output /absolute/path/to/artifact
```

Use a case for focused validation. Use a suite for dependency DAGs, matrices,
fixtures, isolation, parallel rows, retry, durable recovery, and regression
reports. AI may generate documents, but must validate them before submission.

## Authorization And Concurrency

The Supervisor isolates workers by workspace and engine version. Keep every
target and operation bound to its workspace when several projects run in
parallel. Production/unknown environments, dangerous operations, safety
effects, and secret names require explicit policy. Inspect with
`daemon policy show`; validate and atomically apply policy files before restart.
Quarantined resources remain blocked. Read exact identities with `lease.list`
and use the `reset`-authorized `lease.recover`; force release is limited to
explicitly acknowledged logical resources and never applies to forwarded ports.

## Acceptance

A pass requires terminal run state, required assertions, no disqualifying
runtime errors, and readable required evidence. Artifact existence alone is
not proof. Resume event streams by sequence and reuse idempotency keys; do not
replay uncertain mutations blindly.
