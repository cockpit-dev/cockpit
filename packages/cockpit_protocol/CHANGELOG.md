# Changelog

## 3.0.3

- Synchronized the protocol patch release with Cockpit 3.0.3 so the CLI,
  Flutter bridge, and independent clients keep one published version baseline.

## 3.0.2

- Added strict bounded decoding for network queries, runtime queries, snapshot
  options, recording requests, and public automation target fields.
- Expanded the foundation OpenAPI and JSON Schema contracts for complete
  external REST clients while keeping unknown, malformed, and oversized input
  fail-closed.
- Removed recording aliases and implicit request names so LON, JSON, and YAML
  clients share one canonical wire contract.

## 3.0.1

- Reduced the default live semantic projection to a bounded set of concise
  locator and capability fields while preserving detailed target resolution
  for explicit inspection.

## 3.0.0

- Added the canonical command `changed` signal, viewport resize contracts, and
  numeric development-session handle metadata used by the 3.0 task commands.
- Added bounded network indexing and body retrieval contracts with masked
  previews, explicit raw artifact access, SSE receiving state, and WebSocket
  frame metadata.
- Added signed scroll alignment and offset policy fields for deterministic
  nested Flutter viewport placement.
- Added LON as a first-class document format alongside JSON and YAML, including
  strict format inference for case and suite documents.
- Removed the 2.x compatibility surface for renamed command and output fields;
  clients must use the 3.0 schema names.

## 2.2.1

- Synchronized the public protocol patch release with Cockpit 2.2.1.
- Added the default-safe `redact` network observer configuration used by the
  Flutter development bridge.

## 2.2.0

- Synchronized the public protocol release with Cockpit 2.2.0 so the CLI,
  Flutter bridge, and independent clients can use one release baseline.

## 2.1.0

- Synchronized the public protocol release with Cockpit 2.1.0 so clients can
  pin one version across the CLI, protocol, and Flutter bridge packages.

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
