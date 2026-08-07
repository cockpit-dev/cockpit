<div align="center">
  <a href="https://github.com/cockpit-dev/cockpit">
    <img src="https://raw.githubusercontent.com/cockpit-dev/cockpit/main/assets/brand/cockpit-mark.svg" width="128" alt="Cockpit logo">
  </a>
  <h1>cockpit_protocol</h1>
  <p><strong>Stable, platform-neutral contracts for Cockpit tests, clients, runtimes, and reports.</strong></p>
  <p>
    <a href="https://pub.dev/packages/cockpit_protocol"><img src="https://img.shields.io/pub/v/cockpit_protocol?logo=dart&amp;label=pub.dev" alt="cockpit_protocol version on pub.dev"></a>
    <a href="https://pub.dev/packages/cockpit_protocol/score"><img src="https://img.shields.io/pub/points/cockpit_protocol?logo=dart" alt="cockpit_protocol pub points"></a>
    <a href="https://pub.dev/packages/cockpit_protocol/score"><img src="https://img.shields.io/pub/likes/cockpit_protocol?logo=dart" alt="cockpit_protocol likes on pub.dev"></a>
    <a href="https://pub.dev/packages/cockpit_protocol/score"><img src="https://img.shields.io/pub/popularity/cockpit_protocol?logo=dart" alt="cockpit_protocol popularity on pub.dev"></a>
  </p>
  <p>
    <a href="https://github.com/cockpit-dev/cockpit/actions/workflows/example-e2e.yml"><img src="https://github.com/cockpit-dev/cockpit/actions/workflows/example-e2e.yml/badge.svg?branch=main" alt="CI"></a>
    <a href="https://dart.dev"><img src="https://img.shields.io/badge/Dart-%E2%89%A53.8.0-0175C2?logo=dart&amp;logoColor=white" alt="Dart 3.8.0 or newer"></a>
    <a href="https://github.com/cockpit-dev/cockpit/tree/main/packages/cockpit_protocol"><img src="https://img.shields.io/badge/contract-platform--neutral-455A64" alt="Platform-neutral protocol contract"></a>
    <a href="https://github.com/cockpit-dev/cockpit/blob/main/packages/cockpit_protocol/LICENSE"><img src="https://img.shields.io/github/license/cockpit-dev/cockpit" alt="BSD 3-Clause license"></a>
  </p>
</div>

Platform-neutral Dart protocol models shared by Cockpit clients, runtimes,
drivers, and host tooling.

Most users should depend on `flutter_cockpit` in Flutter apps and `cockpit` for
host tooling. Direct protocol consumers import
`package:cockpit_protocol/cockpit_protocol.dart`. This package has no Flutter SDK
dependency, so CLI, MCP, GUI, and third-party clients can share the same wire
models.

Version 3.0 is the current breaking release. It replaces no APIs through a
compatibility forwarding package; the former `flutter_cockpit_protocol` name
is not supported.

## Standalone E2E contract

`cockpit.test/v2` is the stable, platform-neutral project, suite, fixture,
matrix, and case contract. Cases own target requirements, typed
constants/inputs/secret references, local fragments, setup/main/finally
sections, bounded control flow, evidence policy, and explicit safety
declarations. Suites own dependency-aware campaigns, scoped fixtures, matrix
expansion, concurrency, retry, fail-fast, and report policy. The published JSON Schema is
[`schema/cockpit.test.v2.schema.json`](schema/cockpit.test.v2.schema.json).

The protocol deliberately separates authored templates from bound execution
values:

- `CockpitTestProject`, `CockpitTestSuite`, `CockpitTestFixture`,
  `CockpitTestCase`, step/action/condition templates, locators, variables, and
  policies describe authored documents.
- `CockpitTestRunContext` provides the full
  `projectId -> workspaceId -> runId -> caseId -> attemptId` identity chain.
- `CockpitTestAttemptResult`, `CockpitTestSuiteReport`,
  `CockpitTestReportBundle`, `CockpitTestReportBundleManifest`,
  `CockpitTestError`, step occurrences, and immutable artifact manifests are
  the stable client/report contract. The canonical bundle retains authored
  definitions, detailed step metadata, and a semantic evidence index.
- Secrets are authored as provider references. Resolved values are not part of
  any protocol object, JSON representation, result, diagnostic, or report.

The package contains no parser, YAML, filesystem, Flutter, driver, service, or
GUI dependency. Host execution belongs to `package:cockpit`; future official
or third-party clients can parse these DTOs and consume the same result and
bundle contracts independently.

`schemaVersion: cockpit.test/v2` accepts `kind: project`, `kind: suite`, and
`kind: case`. Execution remains a host responsibility: the Supervisor and
isolated workspace workers schedule cases and suites while clients consume the
same DTO, event, and artifact contracts.

Locators are declarative intersections rather than a single strategy/value
pair. Signals on one locator (`text`, `label`, `nativeId`, `testId`, `role`,
`type`, and `path`) must all match. Optional state, hierarchy, and spatial
constraints further narrow native accessibility matches; `index` resolves an
otherwise ambiguous match in UI order. `fallbacks` are attempted in order as
explicit alternatives. Coordinate and visual locators are separate degraded
modes and cannot be mixed with semantic constraints. Runtimes reject any
constraint they cannot execute faithfully instead of silently weakening it.
`text` and `label` default to `matchMode: exact`; opt into `contains`,
typo-tolerant `fuzzy`, or `regex` explicitly. When several candidates match, the runtime selects only a
unique highest-quality candidate (current route, exact text, then path
specificity). A tied best score returns `ambiguousTarget` instead of guessing.

```yaml
locator:
  text: Save
  matchMode: contains
  role: button
  enabled: true
  ancestor: {label: Task editor}
  below: {text: Notes}
  fallbacks:
    - {testId: save-task}
```

Every step can override the target default with `plane: semantic|native|visual|coordinate`.
When omitted, the host derives the effective plane from the action and locator;
nested fragment, condition, retry, and loop steps inherit it. This permits one
Flutter development case to combine semantic bridge steps with a secondary
system driver for native screens, platform views, system UI, visual templates,
and coordinates while preserving the requested and actual plane in results.

The portable action contract includes clipboard-backed `copyText` and
`pasteText`, cursor-aware `eraseText`, bounded location `travel`, and
`assertScreenshot`. Visual templates and screenshot baselines are file
references, not encoded bytes. Hosts confine them to the workspace and publish
actual, baseline, and diff images as digest-addressed bundle artifacts. Lifecycle
work composes from suite fixtures, case `setup`/`finally`, per-step `evidence`,
and explicit recording operations; control flow remains available inside each
scope without a separate generic hook protocol.

## Supervisor foundation contract

`cockpit.foundation/v2` is the stable client contract for the per-user
Supervisor. It defines strict DTOs for API/feature negotiation, registered
roots and workspaces, discoverable typed operations, case and suite
submission, run lifecycle and outcome, durable events, immutable artifacts,
leases, pagination, idempotency, and structured failures.

The published contracts are:

- [`schema/cockpit.foundation.v2.schema.json`](schema/cockpit.foundation.v2.schema.json)
  for JSON request, response, resource, and event shapes;
- [`openapi/cockpit.v2.openapi.json`](openapi/cockpit.v2.openapi.json) for the
  authenticated `/api/v2` HTTP and SSE surface;
- `cockpitFoundationV2SchemaJson` and `cockpitV2OpenApiJson` for compiled Dart
  clients that cannot read package data files at runtime.

Requests always reject unknown fields and enum values. Negotiated responses may
ignore additive fields or preserve declared extensible enum values only when
the corresponding feature id was negotiated. API lifecycle (`queued`,
`running`, `completed`) is distinct from product outcome and stability. A
failure keeps one primary error plus ordered cleanup/evidence warnings, so
secondary failures never replace the original cause.

The API supports indexed case runs and durable suite campaigns with matrix,
fixture, retry, dependency, concurrency, and aggregate report semantics.
Native black-box execution is selected through registered targets and remains
behind the same operation, event, and artifact contracts. Official or
third-party GUI clients consume these boundaries without linking host runtime
services in-process.
