# Cockpit Protocol

Cockpit is a resource-oriented E2E automation protocol for arbitrary
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
Requests and strict responses reject unknown fields and unsupported schema
versions. Negotiated responses may ignore additive fields or preserve declared
extensible enum values only when the corresponding feature was negotiated.

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
- REST is the complete public command/resource control plane. Clients discover
  operation descriptors from `/api/v2/operations` and workspace operation
  catalogs, read exact request/response contracts from
  `/api/v2/operations/schema`, and execute through the matching global or
  workspace operation POST route.
- Public client control does not use WebSocket. The Flutter Web bridge may use
  WebSocket internally, but that transport is not a client API. Captured app
  WebSocket activity is network evidence, not a control channel.
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

Case runs provide typed inputs, setup, steps, always-eligible bounded cleanup,
safety authorization, evidence, and immutable attempt bundles. Suite runs add DAGs,
matrix expansion, fixtures, isolation, concurrency, retry, fail-fast,
checkpoint recovery, and complete offline regression report bundles.

The target declares a default execution plane and each step may override it as
`semantic`, `native`, `visual`, or `coordinate`. Hosts derive an omitted step
plane from its action and locator, propagate the effective plane through nested
control flow, and record requested and actual planes. A Flutter development
target may own both its semantic bridge driver and a secondary system driver
for the same app/device so mixed Flutter/native stacks stay in one run.
For a launched target, `target.inspect` returns the secondary driver profile as
`output.systemControl`.

The shared actions include semantic and native gestures, text and clipboard
editing, waits, assertions, evidence, explicit recording lifecycles, system
control, bounded location travel, visual template location, and screenshot
baseline comparison. Template and baseline paths are workspace-confined.
Screenshot comparison publishes actual, baseline, and diff files rather than
embedding binary data. Suite fixtures, case `setup`/`finally`, step evidence,
and explicit recording boundaries compose the execution lifecycle.

## Report Bundle

The immutable report fact graph is `run -> suite -> case -> attempt -> step ->
assertion/evidence`. `report.json` is the canonical single-file rendering input
and retains the effective suite and case definitions plus detailed execution
results. Derived views include:
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
other. Unsupported capabilities return explicit errors.
