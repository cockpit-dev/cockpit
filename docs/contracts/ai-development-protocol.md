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

Use `daemon start --yolo` only when the user explicitly requests unrestricted
local execution. It is scoped to that daemon process; read `daemon status` and
preserve the reported `authorizationMode` in run evidence.

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
Flutter launches accept repeatable `--dart-define`,
`--dart-define-from-file`, `--flutter-arg`, and `--env KEY=VALUE` options and a
`--launch-timeout-ms` value up to 1800000. Generic operations and third-party
clients send the equivalent nested `launchConfiguration` object with
`dartDefines`, `dartDefineFromFiles`, `flutterArgs`, and `environment`. Never
send this object for a non-Flutter black-box target, and never assume launch
configuration values will be echoed in a result.

Operation descriptors are the timeout and execution authority. Read
`executionMode`, `defaultTimeoutMs`, and `maximumTimeoutMs` before acting.
Synchronous operations block to a terminal result and accept either relative
`timeoutMs`/`--timeout-ms` or an absolute `deadline`/`--deadline`. Job
operations return a durable `runId`; case submissions default to 30 minutes
with a 6 hour maximum, while suites default to 2 hours with a 24 hour maximum.
Do not combine relative and absolute deadlines.

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

If interrupted work leaves a quarantined resource, read it with the advertised
Supervisor `lease.list` operation. Use `lease.recover` only after policy
explicitly authorizes the operation and its `reset` effect, and send the exact
lease, workspace, resource kind/id, and holder identities. Set
`forceRelease: true` only to acknowledge unverified logical-resource cleanup;
forwarded ports always require verified cleanup.

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
dart run cockpit run events --run-id <runId> --after-sequence 0 \
  --stdout-format jsonl
dart run cockpit run get --run-id <runId>
dart run cockpit suite report --run-id <runId>
dart run cockpit artifact list --run-id <runId>
dart run cockpit artifact read \
  --run-id <runId> --artifact-id <artifactId> \
  --output /absolute/path/to/artifact
```

Terminal output defaults to bounded semantic text for agent loops. Request
`--stdout-format json` only for exact machine data, or use `--output <file>` to
write the lossless JSON response and receive a path/size/SHA-256 receipt.
`artifact read` always writes verified bytes to a file and never emits Base64.
Use `artifact list` as the authority for artifact identity and metadata.

Use a suite for dependency ordering, matrix coverage, fixtures, retries,
parallel rows, durable resume, and regression reports. Use a case for a focused
development proof.

Select `plane` only when the step must override the case default. Otherwise let
the runtime route screenshot assertions to visual control, system and `travel`
actions to native control, and visual/coordinate/native-only locators to their
faithful driver. A Flutter bridge target can switch between its semantic and
secondary system drivers per step; inspect the reported capabilities before
using `copyText`, `eraseText`, `pasteText`, `travel`, visual locators, or
`assertScreenshot`.
Read secondary native capabilities from the sanitized
`target.inspect.output.systemControl` profile. Do not infer them from
`app.get`; platform application and process identities are intentionally
redacted outside the worker.

Visual templates and screenshot baselines must resolve inside the registered
workspace. Screenshot assertions produce actual, baseline, and diff files in
the report bundle. Express before/after behavior with suite fixtures, case
`setup`/`finally`, step `evidence`, and explicit `startRecording`/
`stopRecording` boundaries. Do not invent a client-only hook model that cannot
round-trip through `cockpit.test/v2` and the canonical report.

For a suite, download the complete report artifact set into one directory and
preserve its relative paths. Read `summary.md` for a bounded terminal handoff,
`report.json` for complete structured facts, and `index.html` only when a human
view is useful. Verify every declared size and SHA-256 in `manifest.json`
before reading evidence. Do not print binary content or expand it as Base64.

## Acceptance Rule

Command success is not product proof. Compare baseline and terminal state,
read runtime errors, and use the canonical run report. A required missing
capability or artifact is a blocked/failed result, not a pass.
