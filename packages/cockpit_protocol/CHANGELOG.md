# Changelog

## 4.4.4

- Synchronized the protocol release with the iOS native wait recovery fix.

## 4.4.3

- Synchronized the protocol release with the iOS native wait recovery fix.

## 4.4.2

- Synchronized the protocol release with the iOS native capability probe fix.

## 4.4.1

- Synchronized the protocol release with the corrected cross-platform package
  metadata and CI validation contracts.

## 4.4.0

- Synchronized the validated protocol release with the stateful Flutter
  performance-plugin lifecycle and current iOS session handoff behavior.

## 4.3.0

- Extended the validated DevTools runtime contract with source-aware extension
  RPC metadata and immutable runtime-profile updates.

## 4.2.0

- Added validated performance-plugin statistics and source/isolate location
  fields for attributable application instrumentation events.

## 4.1.0

- Extended the DevTools report contract with VM Logging zone context and
  bounded retention metadata for runtime log/debug evidence.

## 4.0.50

- Synchronized the protocol package with the current Cockpit performance
  tooling release.
- Added compact, validated DevTools projections for VM CPU samples, heap and
  allocation classes, and evidence-only GPU/shader timeline signals.
- Added bounded VM heap timeline samples, isolate health/lifecycle snapshots,
  isolate-group memory points, and VM timeline recorder/stream metadata.
- Added VM runtime identity, target/host CPU, architecture, process start, and
  isolate inventory metadata to the same validated DevTools projection.
- Added bounded all-isolate health snapshots and VM Isolate stream lifecycle
  event contracts with explicit retention-drop counts.
- Added bounded VM Service process-memory tree contracts with before/after
  snapshots, child retention limits, and explicit dropped-child counts.
- Added opt-in selected-class allocation call-stack contracts and Perfetto
  CPU/timeline metadata with raw payloads reserved for complete exports.

## 4.0.49

- Added a bounded process-memory report contract for native integration-test
  captures, including RSS samples and start/end/peak/delta aggregates.
- Synchronized the protocol package with the current Cockpit release.
- Added bounded, display-aware performance report contracts with strict
  duration, timestamp, sample-count, wall-time, and payload validation.
- Performance reports use schema v2 so raw raster-finish wall-time and bounded
  sample semantics cannot be confused with the earlier contract.
- Reports record the Flutter build mode so debug measurements cannot be
  mistaken for profile or release evidence.

## 4.0.48

- Synchronized the protocol package with the current Cockpit release.

## 4.0.47

- Synchronized the protocol package with the current Cockpit release.

## 4.0.46

- Synchronized the public protocol contracts with the Flutter-first interaction,
  gesture, diagnostics, and compact output surface.

## 4.0.45

- Synchronized the public protocol package with the current Cockpit release.

## 4.0.44

- Synchronized the public protocol package with the current Cockpit release.

## 4.0.43

- Synchronized the public protocol package with the current Cockpit release.

## 4.0.42

- Synchronized the public protocol package with the current Cockpit release;
  public protocol contracts are unchanged.

## 4.0.41

- Synchronized the public protocol package with the current Cockpit release;
  public protocol contracts are unchanged.

## 4.0.40

- Synchronized the public protocol package with the current Cockpit release;
  public protocol contracts are unchanged.

## 4.0.39

- Synchronized the public protocol package with the current Cockpit release;
  public protocol contracts are unchanged.

## 4.0.38

- Synchronized the public protocol package with the current Cockpit release;
  public protocol contracts are unchanged.

## 4.0.37

- Synchronized the public protocol package with the current Cockpit release;
  public protocol contracts are unchanged.

## 4.0.36

- Synchronized the public protocol package with the current Cockpit release.

## 4.0.35

- Added target visibility to runtime snapshots and registry access to bounded
  hidden targets for mounted offscreen inspection.

## 4.0.34

- Synchronized the public protocol package with the current Cockpit release.

## 4.0.33

- Synchronized the public protocol package with the current Cockpit release.

## 4.0.32

- Added compact Flutter control state for enabled, selection, check, focus,
  read-only, obscured, and current-value inspection.
- Added standalone live target selectors with collision-aware base-36 refs and
  a safe minimum reference length.

## 4.0.31

- Synchronized the public protocol package with the current Cockpit release.

## 4.0.30

- Added explicit-target resolution and scoped discovery snapshots so Flutter
  actions and diagnostics can avoid repeated full target discovery.

## 4.0.29

- Synchronized the public protocol package with the current Cockpit release.

## 4.0.28

- Synchronized the public protocol package with the current Cockpit release.

## 4.0.27

- Synchronized the public protocol package with the current Cockpit release.

## 4.0.26

- Added the public paginated workspace run-list resource to the foundation
  schema and OpenAPI contract.
- Added semantic-identifier match modes and ranking to the shared conjunctive
  selector contract used by Flutter and native execution planes.

## 4.0.25

- Synchronized the public protocol package with the current Cockpit release.

## 4.0.24

- Synchronized the public protocol package with the current Cockpit release.

## 4.0.23

- Synchronized the public protocol package with the current Cockpit release.

## 4.0.22

- Synchronized the public protocol package with the current Cockpit release.

## 4.0.21

- Synchronized the public protocol package with the current Cockpit release.

## 4.0.20

- Synchronized the public protocol package with the current Cockpit release.

## 4.0.19

- Synchronized the public protocol package with the current Cockpit release.

## 4.0.18

- Synchronized the public protocol package with the current Cockpit release.

## 4.0.17

- Synchronized the public protocol package with the current Cockpit release.

## 4.0.16

- Synchronized the public protocol package with the current Cockpit release.

## 4.0.15

- Synchronized the public protocol package with the current Cockpit release.

## 4.0.14

- Synchronized the public protocol package with the Cockpit 4.0.14 release.

## 4.0.13

- Synchronized the public protocol package with the Cockpit 4.0.13 release.

## 4.0.12

- Synchronized the public protocol package with the Cockpit 4.0.12 release.

## 4.0.5

- Synchronized the protocol package with the Cockpit 4.0.5 release.

## 4.0.4

- Added canonical detection for explicit compact selectors so inspection can
  distinguish reusable selector syntax from free-text exploration queries.

## 4.0.3

- Unified exact, contains, fuzzy, and regex text matching and ranking across
  Flutter target discovery, mounted Element control, and native black-box E2E.
- Made misspelled fuzzy phrases prefer the tightest matching label consistently
  across every execution plane.

## 4.0.2

- Added compact conjunctive Flutter selectors with exact, contains, fuzzy,
  ancestor, route, path, and deterministic index conditions.
- Added bounded snapshot queries so large mounted Flutter pages filter targets
  before applying output limits.
- Improved fuzzy matching for misspelled text fragments within longer UI
  labels without weakening short-text safeguards.

## 4.0.1

- Added bounded foreground-surface metadata to command results so system
  captures can identify the expected app, an operating-system overlay, a
  different foreground app, or an unknown surface.

## 4.0.0

- Added bounded descendant `textParts` to Flutter target and snapshot
  contracts so clients can address composite controls by their exact visible
  child text without requiring application-authored Semantics.

## 3.0.14

- Synchronized the protocol package with Cockpit's stale development-session
  recovery release; public protocol contracts are unchanged.

## 3.0.13

- Added typed minimal, standard, and full Flutter Widget tree contracts,
  including bounded node properties, geometry, scroll ancestry, actionable
  locator paths, and snapshot artifact references.
- Added strict Widget tree options to snapshot and test-document schemas so
  REST, CLI, E2E, and third-party clients share the same validated capture
  contract.

## 3.0.12

- Synchronized the protocol package with Cockpit's daemon concurrency,
  capability startup, and development-session reconnect corrections; public
  protocol contracts are unchanged.

## 3.0.11

- Synchronized the protocol package with Cockpit's latest-release updater
  correction; public protocol contracts are unchanged.

## 3.0.10

- Synchronized the protocol package with Cockpit's desktop-session recovery,
  resource-lease, and capture corrections; public protocol contracts are
  unchanged.

## 3.0.9

- Synchronized the protocol package with Cockpit's Supervisor-restart recovery;
  public protocol contracts are unchanged.

## 3.0.8

- Synchronized the protocol package with Cockpit's downgrade-safe updater;
  public protocol contracts are unchanged.

## 3.0.7

- Synchronized the protocol package with the Cockpit 3.0.7 updater repair;
  public protocol contracts are unchanged.

## 3.0.6

- Synchronized the protocol package with the Cockpit 3.0.6 runtime identity
  recovery patch release; public protocol contracts are unchanged.

## 3.0.5

- Synchronized the protocol package with the Cockpit 3.0.5 patch release so
  the CLI, Flutter bridge, and public client contracts retain one version.

## 3.0.4

- Synchronized the protocol package with the Cockpit 3.0.4 patch release so
  the CLI, Flutter bridge, and public client contracts retain one version.

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
