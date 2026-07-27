# Reports, Evidence, And Release Gates

Use this reference after a case/suite reaches terminal state or when preparing
a CI/release handoff.

## Contents

- [Truth hierarchy](#truth-hierarchy)
- [Offline bundle](#offline-bundle)
- [Role views](#role-views)
- [Artifact download](#artifact-download)
- [Failure triage](#failure-triage)
- [Release acceptance](#release-acceptance)

## Truth Hierarchy

1. Terminal `run get` state and canonical report outcome.
2. Required assertions and recorded runtime errors.
3. Report-linked evidence with verified size and SHA-256.
4. Human/CI projections generated from the same report fact graph.

Command success, a created file, or an artifact reference alone is not product
proof. A required unavailable capability or unreadable artifact is blocked or
failed according to policy, never silently passed.

## Offline Bundle

The suite bundle is one portable directory with no network or external asset
dependency:

```text
manifest.json
report.json
index.html
summary.md
junit.xml
run/
  run.json
  events.jsonl
cases/
  <ordered-case>/
    case.json
    attempts/
      <ordered-attempt>/
        manifest.json
        steps/steps.json
        evidence/...
fixtures/...
```

The exact tree varies with fixtures and evidence, but `manifest.json` declares
every other file with semantic kind, owner IDs, media type, byte size, and
SHA-256. Preserve relative paths. Reject undeclared, missing, size-mismatched,
or digest-mismatched files before trusting the bundle.

`report.json` is the canonical single-file rendering input. It contains the
effective suite/case definitions, environment, cases, attempts, steps,
assertions, errors, locator/plane/driver results, and evidence index.
`run/events.jsonl` is the chronological machine trace. Per-attempt
`steps.json` is the detailed local step record.

## Role Views

- Product: outcome, covered journeys, visible evidence, user-facing failures.
- Quality/test: cases, matrices, retries, skipped/blocked reasons, assertions,
  evidence chain, stability.
- Engineering: operation, timeout, requested/actual plane, driver, locator
  signals, diagnostics, runtime errors.
- Project/release: duration, coverage, trend input, platform matrix, gate
  status, complete/incomplete state.
- Machine/AI: `report.json`, `manifest.json`, `events.jsonl`, `junit.xml`.

`index.html` exposes offline role lenses over the same facts. `summary.md` is a
bounded neutral handoff, not an AI-authored summary. Do not rename it based on
whether AI participated.

## Artifact Download

```bash
cockpit suite report --run-id <runId>
cockpit artifact list \
  --run-id <runId> \
  --stdout-format json \
  --output /absolute/bundle/artifacts.json
cockpit artifact read \
  --run-id <runId> \
  --artifact-id <artifactId> \
  --output /absolute/bundle/<relativePath>
```

Use artifact metadata to map each `artifactId` to its report `relativePath` and
download every required bundle file without flattening directories. The CLI
verifies bytes before the destination is committed. Keep binary screenshots,
recordings, diffs, and other media on disk; read them only when the unresolved
claim requires their content.

## Failure Triage

Read in this order:

1. run/report outcome, completeness, stability, counts
2. failed/blocked case and latest relevant attempt
3. failed step code/message and timeout/plane/driver/locator diagnostics
4. bounded runtime/system errors and chronological neighboring events
5. only the evidence files referenced by those facts

Separate product failure, test-authoring failure, environment/capability block,
infrastructure interruption, and incomplete evidence. Do not increase timeouts
until the trace shows the operation was merely slow; do not change a locator
until resolution diagnostics show it was absent or ambiguous.

## Release Acceptance

A release gate needs:

- formatting, static analysis, all package/example tests, and publication dry
  runs
- complete supported platform regression jobs (Android, iOS, macOS, Linux,
  web, Windows when those are release targets)
- at least one real business mutation with an observable final assertion
- applicable advertised gesture, text, keyboard, wait, semantic/native/mixed,
  system-control, screenshot, recording, and report behavior
- expected passed/skipped/blocked counts and terminal outcome
- a complete readable offline bundle whose manifest verifies

Wait for the entire CI matrix to finish once. Then inspect failed jobs and all
uploaded regression bundles together. Never declare release readiness from a
partial matrix, one local platform, or CI process exit alone.
