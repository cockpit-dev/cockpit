# Cockpit 2.0 Protocol

Cockpit 2.0 is a resource-oriented E2E automation protocol for arbitrary
applications, with an optional semantic bridge for Flutter. A per-user Supervisor owns authentication, workspace
isolation, target authority, run admission, events, artifacts, and worker
lifecycle. CLI, MCP, GUI, and third-party clients use the same public contract.

## Canonical Contracts

| Contract | Source |
| --- | --- |
| Authenticated HTTP/SSE API | `packages/cockpit_protocol/openapi/cockpit.v2.openapi.json` |
| Foundation DTOs | `packages/cockpit_protocol/schema/cockpit.foundation.v2.schema.json` |
| Case, suite, and project documents | `packages/cockpit_protocol/schema/cockpit.test.v2.schema.json` |
| Dart DTOs and strict codecs | `package:cockpit_protocol/cockpit_protocol.dart` |

Generated schemas and Dart constants must remain byte-for-byte synchronized.
Clients must reject unknown fields and unsupported schema versions.

## Resource Model

```text
Supervisor
  root
    workspace
      document
      target
      operation
      case / suite
  run
    case attempt
      step
      artifact
    event stream
    report
```

Every workspace-owned request carries a `workspaceId`. Run and artifact
resources are resolved through Supervisor-owned indexes, never through global
"latest" state. Multiple projects and checkouts can run concurrently.

## Transport

- `cockpitd` binds loopback only and publishes authenticated discovery data in
  `COCKPIT_HOME`.
- HTTP uses `/api/v2`; event streams use authenticated SSE and resumable event
  sequence identifiers.
- CLI and MCP are thin clients. They do not construct drivers or application
  services in process.
- `cockpit_worker` is private Supervisor infrastructure and is not a public
  client transport.

## Execution

1. Register a project root and workspace checkout.
2. Discover or register a workspace-owned target.
3. Inspect capabilities before selecting operations or authored test steps.
4. Validate and index a `cockpit.test/v2` case, suite, or project document.
5. Submit a case or suite with an idempotency key.
6. Observe the run event stream until a terminal state.
7. Read the canonical report and digest-checked artifacts.

Case runs provide typed inputs, setup, steps, guaranteed cleanup, safety
authorization, evidence, and immutable attempt bundles. Suite runs add DAGs,
matrix expansion, fixtures, isolation, concurrency, retry, fail-fast,
checkpoint recovery, and complete offline regression report bundles.

The target declares a default execution plane and each step may override it as
`semantic`, `native`, `visual`, or `coordinate`. Hosts derive an omitted step
plane from its action and locator, propagate the effective plane through nested
control flow, and record requested and actual planes. A Flutter development
target may own both its semantic bridge driver and a secondary system driver
for the same app/device so mixed Flutter/native stacks stay in one run.
For a launched target, `target.inspect` computes the secondary driver profile
inside the worker from its private app identity and returns only the sanitized
profile as `output.systemControl`. Clients must treat that profile as
authoritative instead of reconstructing it from redacted app resources.

The shared actions include semantic and native gestures, text and clipboard
editing, waits, assertions, evidence, explicit recording lifecycles, system
control, bounded location travel, visual template location, and screenshot
baseline comparison. Template and baseline paths are workspace-confined.
Screenshot comparison publishes actual, baseline, and diff files rather than
embedding binary data. Suite fixtures, case `setup`/`finally`, step evidence,
and explicit recording boundaries are the lifecycle composition primitives;
the protocol has no duplicate generic pre/post hook layer.

## Report Bundle

The immutable report fact graph is `run -> suite -> case -> attempt -> step ->
assertion/evidence`. `report.json` is the canonical single-file rendering input
and retains the effective suite and case definitions plus detailed execution
results. Human views are projections of that graph, never separate facts:
`index.html` provides offline Summary, Coverage, Executions, Evidence,
Diagnostics, and Environment/files sections; `summary.md` and `junit.xml`
provide portable summary and CI
interchange; semantic case/attempt directories contain detailed steps and
evidence. Root `manifest.json` declares every other file with its semantic kind,
run/case/attempt/step ownership, byte size, media type, and SHA-256. The HTML
contains no external dependency or network fetch.

## Target Families

Flutter apps, native mobile apps, desktop apps, browser pages, system surfaces,
devices, and host workspaces share one target contract. App-like black-box
targets require a platform app identifier. iOS WebDriverAgent endpoints are
target-scoped so concurrent devices and workspaces cannot overwrite each
other. Unsupported capabilities remain explicit rather than being simulated.

## Compatibility

There is no 1.x runtime client, embedded dashboard, legacy artifact layout, or
global session store. The offline importer is the only supported migration
surface and produces a canonical 2.0 case plus migration manifest.
