# Cockpit AI Development Protocol

Use the authenticated Supervisor for both rapid development and release E2E.
Do not call host application services directly. For Flutter source development,
use a project-scoped numeric handle guarded by checkout identity and let Cockpit
own internal resources.

## Flutter Bootstrap

```bash
cockpit dev start
```

Run from anywhere inside the intended checkout. Specify only real launch
choices when discovery cannot choose uniquely:

```bash
cockpit dev start apps/mobile/cockpit/main.dart --platform macos
cockpit dev start --device emulator-5554 --flavor staging
cockpit dev start --dart-define API_URL=https://example.test --env LOG_LEVEL=debug
```

The bridge belongs in a development-only entrypoint; production Flutter code
must not import `flutter_cockpit`. Cockpit discovers/registers the workspace,
entrypoint, target, app, process, port, and runtime session internally. It
returns a short handle such as `1`; later commands infer the active handle for
the canonical Flutter project. A monorepo may have independent active handles
for multiple Flutter projects, and one project may keep several platform/target
handles. `dev use HANDLE` changes that project's active handle; explicit
`--session HANDLE` selects one command without changing it. A common ancestor
with multiple active projects fails as ambiguous instead of guessing.

`--env`, `--dart-define`, and custom Flutter arguments are never persisted or
printed. Cockpit does not access a keychain or secret store. A session launched
with custom values remains fully usable while running, but an unexpected exit
requires `cockpit dev start` with those values again.

## Fast Development Loop

1. Read `cockpit dev status` or the smallest `inspect` query.
2. Edit one coherent change and run focused static analysis.
3. Run `cockpit dev reload`.
4. Perform the exact UI action and wait for its terminal state.
5. Inspect current UI/errors; capture a screenshot only for a visible claim.

```bash
cockpit dev status
cockpit dev tap "Documents"
cockpit dev wait
cockpit dev viewport 800x600
cockpit dev screenshot
cockpit dev diagnose
```

Use exact text by default. An ambiguous locator fails and returns bounded
candidates. `dev wait` is UI-only by default; add `--network` only when the
assertion requires completed network activity.

Keep using the same handle after a process, port, bridge, app, or runtime session
changes. Reconciliation proves the same checkout, Flutter project, workspace, target, owned
process, and authenticated bridge. Read commands never relaunch an exited app;
a mutation may relaunch one unexpectedly exited app once. An intentionally
stopped session requires `dev start` or `restart`.

Each Flutter project owns its active selection. Checkout and Git worktree identity
independently protect worker state, process/port ownership, network state, mutation
sequence, and artifact paths. Shared repository metadata or package names never make
another project or checkout handle implicit.

Normal output is bounded canonical LON at `--verbosity minimal`. Preserve
`minimal|standard|full`, LON/JSON/YAML/JSONL, and `path|none`. Artifact and
file output contains only the verified absolute path; never image/file bytes,
Base64, data URIs, hashes, byte counts, or file contents.

Use the advanced protocol only when no task command covers a live capability:

```bash
cockpit explain viewport.set
cockpit op run viewport.set --input '{width:800 height:600}'
```

`explain` resolves the authenticated live request/response schema. Do not guess
fields when schema precision is `generic`.

Operation descriptors remain timeout and execution authority for generic and E2E
operations. Read `executionMode`, timeout bounds, idempotency, scope, and safety
effects before acting. Synchronous operations block to a terminal result; job
operations return a durable `runId`.

If advanced or E2E work leaves a quarantined resource, read it with the advertised
Supervisor `lease.list` operation. Use `lease.recover` only after policy
explicitly authorizes the operation and its `reset` effect, and send the exact
lease, workspace, resource kind/id, and holder identities. Set
`forceRelease: true` only to acknowledge unverified logical-resource cleanup;
forwarded ports always require verified cleanup.

## Case And Suite Runs

Author LON, JSON, or YAML with `schemaVersion: cockpit.test/v2`. Validate before
indexing or running:

```bash
cockpit case validate --file case.yaml
cockpit suite validate --file suite.yaml
cockpit case list
cockpit suite list
cockpit case run --case-id <caseId> --idempotency-key <uniqueKey>
cockpit suite run --suite-id <suiteId> --idempotency-key <uniqueKey>
```

Observe and collect the terminal result:

```bash
cockpit run events --run-id <runId> --after-sequence 0 \
  --format jsonl
cockpit run get --run-id <runId>
cockpit suite report --run-id <runId>
cockpit artifact list --run-id <runId>
cockpit artifact read \
  --run-id <runId> --artifact-id <artifactId> \
  --output /absolute/path/to/artifact
```

Terminal output defaults to minimal canonical LON for agent loops. Omit default
output options. Request `--format json` only with `jq`, a JSON-only consumer, or
JSON wire inspection. Otherwise use `--verbosity full --output <file>.lon` to
write the complete response and receive only its verified path. Verbosity
changes information density, not operation accuracy.
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
