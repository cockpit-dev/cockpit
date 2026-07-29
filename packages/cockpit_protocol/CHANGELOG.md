# Changelog

## 2.0.1

- Added the Cockpit logo to the published package documentation.

## 2.0.0

- Added the public automation target DTOs plus foundation JSON Schema and
  OpenAPI contracts used by CLI, MCP, and independent clients.
- Added the strict `cockpit.test/v2` case/suite DSL and aggregate report models
  shared by Flutter semantic and native black-box drivers.
- Added the complete `cockpit.report.bundle/v2` fact graph and
  `cockpit.report.manifest/v2` file integrity contracts for offline renderers,
  GUI clients, and third-party consumers.
- Added restricted/YOLO authorization provenance to attempt run contexts so
  reports and independent clients can identify the authority used for a run.
- Added project, suite, fixture, matrix, campaign policy, aggregate report, and
  report-case contracts to `cockpit.test/v2`.
- Added conjunctive semantic locators, ordered fallbacks, native state,
  hierarchy and spatial constraints, coordinate/visual degraded modes, and a
  system action contract for black-box setup, device control, and cleanup.
- Added explicit exact/contains/fuzzy/regex locator matching with deterministic
  unique-best selection, ambiguity failures, and 0-based list indexing.
- Added step-level execution-plane overrides, visual locator thresholds,
  screenshot baseline assertions with explicit pixel tolerance, differing-pixel
  budgets and locator-scoped crops, clipboard text actions, and bounded
  location-travel routes to the shared case and report contracts.
- Renamed the pure-Dart package from `flutter_cockpit_protocol` to
  `cockpit_protocol` as the sole owner of platform-neutral Cockpit models.
- Renamed the public libraries to `cockpit_protocol.dart` and
  `cockpit_remote_bridge_protocol.dart` without a compatibility forwarding
  package.
- Added the strict `cockpit.test/v2` case, action, locator, variable, policy,
  run/result/error, import, and `cockpit.report/v2` bundle contracts with a
  published JSON Schema 2020-12 document.
- Published a generated, byte-identical Dart representation of the test schema
  so compiled host tools validate against the same contract as non-Dart clients.
- Added the strict `cockpit.foundation/v2` DTOs, JSON Schema 2020-12 document,
  and OpenAPI 3.1 contract for Supervisor discovery, roots, workspaces, typed
  operations, standalone runs, durable events, artifacts, leases, paging,
  idempotency, version/feature negotiation, and structured recovery.
- Published byte-identical embedded foundation schema and OpenAPI constants for
  compiled CLI, MCP, GUI, and third-party Dart clients.
- Added the paginated run artifact collection contract so independent clients
  can resolve immutable download metadata without private server access.

## 1.1.4

- Synced the published protocol contract fallback documents with the repository contracts so global tooling and MCP resources expose the same AI development and bundle traceability protocol as monorepo checkouts.

## 1.1.3

- Initial pure Dart protocol package extracted from `flutter_cockpit` so `cockpit` can run as a hosted global Dart executable.
