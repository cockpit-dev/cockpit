# Cockpit 2.0 AI Development Protocol

Use the authenticated Supervisor for both rapid development and release E2E.
Do not call host application services directly and do not rely on implicit
latest app, session, task, or workspace state.

## Bootstrap

```bash
dart run cockpit daemon start
dart run cockpit root add --path /absolute/project/root
dart run cockpit workspace register --root-id <rootId> --path /absolute/checkout
dart run cockpit target discover
```

Read the returned JSON and reuse its identifiers. When the current directory
belongs to exactly one active workspace, `--workspace-id` may be omitted.

Register an installed black-box app with its real platform identity:

```bash
dart run cockpit target register \
  --workspace-id <workspaceId> \
  --platform android \
  --device-id <deviceId> \
  --target-kind nativeApp \
  --environment test \
  --app-id com.example.app \
  --idempotency-key <uniqueKey>
dart run cockpit target launch \
  --workspace-id <workspaceId> \
  --target-id <targetId> \
  --idempotency-key <uniqueKey>
dart run cockpit target inspect --target-id <targetId> --profile minimal
```

For Flutter development shells, register a `flutterApp` target with an indexed
entrypoint document. Production Flutter code must not import
`flutter_cockpit`; the bridge belongs to the development shell.

## Fast Development Loop

1. Read `operation list` and target capabilities.
2. Execute only advertised operations using `operation run` with typed JSON.
3. Use hot reload/restart operations when the target exposes them.
4. Re-inspect target/UI/errors after mutation.
5. Capture evidence only when the requested claim needs it.

```bash
dart run cockpit operation list --workspace-id <workspaceId>
dart run cockpit operation run \
  --workspace-id <workspaceId> \
  --kind <advertisedKind> \
  --input-file /tmp/operation.json \
  --idempotency-key <uniqueKey>
```

Never guess operation parameters, target IDs, device IDs, or locators.

## Case And Suite Runs

Author YAML or JSON with `schemaVersion: cockpit.test/v2`. Validate before
indexing or running:

```bash
dart run cockpit case validate --file case.yaml --format yaml
dart run cockpit suite validate --file suite.yaml --format yaml
dart run cockpit case list
dart run cockpit suite list
dart run cockpit case run --case-id <caseId> --idempotency-key <uniqueKey>
dart run cockpit suite run --suite-id <suiteId> --idempotency-key <uniqueKey>
```

Observe and collect the terminal result:

```bash
dart run cockpit run events --run-id <runId> --after-sequence 0
dart run cockpit run get --run-id <runId>
dart run cockpit suite report --run-id <runId>
dart run cockpit artifact list --run-id <runId>
dart run cockpit artifact read \
  --run-id <runId> --artifact-id <artifactId> \
  --size <size> --sha256 <sha256>
```

Use `artifact list` as the authority for artifact IDs, media types, sizes, and
SHA-256 values. Never infer download metadata from filenames or report text.

Use a suite for dependency ordering, matrix coverage, fixtures, retries,
parallel rows, durable resume, and regression reports. Use a case for a focused
development proof.

## Acceptance Rule

Command success is not product proof. Compare baseline and terminal state,
read runtime errors, and use the canonical run report. A required missing
capability or artifact is a blocked/failed result, not a pass.
