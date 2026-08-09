# Changelog

## 3.0.3

- Kept independent workspace operations available while a timed-out worker
  request finishes its bounded terminal cleanup, preventing one slow native
  probe from blocking status, capture, cleanup, or subsequent automation.

## 3.0.2

- Completed the public REST and MCP control plane with strict operation help,
  request/response schemas, resource discovery, and case/suite submission
  through the same advertised operations used by the CLI.
- Bounded remote status and snapshot retries by the caller deadline, tightened
  network body retrieval to available artifact parts, and kept absent or
  continuing bodies explicit without emitting empty files.
- Isolated macOS Accessibility traversal from the worker, detected stale or
  cyclic AX trees, and made blocked native waits terminate immediately with
  actionable permission guidance instead of consuming the full step timeout;
  resolved native controls now execute through `AXPress` before any coordinate
  fallback so a successful input result reflects a real semantic action.
- Stopped durable worker replay after the Supervisor terminalizes a run,
  preventing sequence conflicts and worker restart loops after interruption.
- Replaced Windows PowerShell file identity and ACL probing with native
  handle-based identity leases plus Win32 owner, DACL, ACE, and SID inspection,
  including every ancestor checked during root and workspace registration.
- Removed cross-platform Flutter launch stalls, preserved command deadlines,
  and kept common status, inspection, network, capture, and reload paths
  responsive through the selected numeric session.

## 3.0.1

- Scoped active numeric session handles to canonical Flutter projects and
  checkout identity, including nested-project discovery, explicit selection,
  side-effect-free listing, and unambiguous concurrent target reuse.
- Preserved running Flutter applications across daemon and worker restarts by
  detaching the machine control plane and reconnecting the same session instead
  of stopping or relaunching unrelated apps.
- Added interactive `dev start` stage progress, project-relative entrypoint
  resolution, isolated Flutter tool state, and bounded recovery for faster,
  clearer startup from global AOT installations.
- Restored dependency resolution on the declared Flutter 3.32 minimum while
  retaining the process control, image comparison, XML parsing,
  source-location, and HTTP profiling APIs used by current Flutter releases.
- Replaced macOS System Events tree reads with bounded native Accessibility
  traversal, exact app activation, and stable locator bounds before input.
- Hardened platform-aware capture, native/system actions, focused semantic
  inspection, nested scrolling, runtime input binding, and terminal SSE replay.
- Batched durable suite events and artifacts while preserving append-only
  recovery, reducing large acceptance-run persistence and exchange overhead.

## 3.0.0

- Replaced the multi-identity development workflow with `cockpit dev` and one
  checkout-scoped numeric session handle for start, status, UI control,
  network, viewport, screenshot, reload, restart, diagnosis, and stop.
- Added exact AI-first UI locators, nested scrolling with alignment and signed
  offsets, platform-aware screenshots, responsive viewport control, and
  bounded diagnostics with artifact-path-only evidence output.
- Added newest-first network indexes, request/response body artifacts,
  credential masking with opt-in raw retrieval, SSE continuation state, and
  WebSocket frame summaries.
- Made minimal LON the default output and promoted LON, JSON, and YAML to equal
  structured input/output formats; `--verbosity` selects minimal, standard, or
  full response density.
- Added operation-specific default timeouts and a consistent `--timeout` on
  every bounded executable command, with cancellable timeout errors that leave
  owned development sessions reusable.
- Added concise `op`, `session`, `case`, `suite`, `run`, and `artifact`
  command paths with schema-driven inputs and durable run/report retrieval.
- Fixed macOS stop cleanup, daemon/session reconnection, screenshot fallback,
  report artifact handling, and run report export performance.
- Removed the 2.x command aliases, duplicate generic operation entrypoints,
  long-form output flags, and legacy session identifiers instead of carrying
  divergent compatibility behavior.

## 2.2.1

- Fixed valid retirement responses being rejected after `workspace unregister`
  and `root remove`, including cleanup after a workspace worker has run.

## 2.2.0

- Added dedicated minimal, standard, and full AI-first presenters for text and
  JSON output, with compact collection tables, no repeated response envelope,
  and file-only binary delivery.
- Fixed daemon and workspace-worker startup from global activation, `dart run`,
  and external project directories by preserving the Cockpit package config.
- Added monorepo-aware Flutter entrypoint resolution, isolated producer
  artifacts, short per-worker temporary roots for socket-bound toolchains,
  non-exclusive target inspection, actionable quarantined-resource failures,
  and paginated document listing with bounded operation journals.
- Expanded the release acceptance workflow and self-contained agent skill for
  Flutter-first development, black-box and mixed-stack E2E, launch injection,
  per-operation timeouts, evidence, offline reports, and platform recovery.

## 2.1.0

- Added `suite report --output-dir` to export a complete offline report bundle
  in one command with bounded parallel downloads, manifest metadata checks,
  verified artifact bytes, cleanup on failure, and atomic directory commit.

## 2.0.1

- Added the Cockpit logo to the published package documentation.

## 2.0.0

- Added durable suite campaigns with DAG dependencies, scoped fixtures,
  matrices, bounded concurrency, retries, fail-fast policy, recovery, and
  complete offline JSON/JUnit/HTML/Markdown report bundles.
- Added semantic report directories, full suite/case definitions, detailed
  step metadata, responsive task-focused offline HTML sections, search,
  filters, deep links, evidence galleries, diagnostics, and a root SHA-256
  manifest covering every exported file.
- Added a self-contained platform environment and recovery guide to every
  supported agent skill distribution, including Android SDK/ADB, iOS
  Simulator/WebDriverAgent, host permissions, and parallel target isolation.
- Added restart-safe suite node and attempt checkpoints. Active attempts recover
  as `interrupted`, completed nodes are not replayed, and persisted fixture/row
  session bindings must resolve to the same healthy resource.
- Added strict home-scoped Supervisor authorization policy persistence and
  `daemon policy show|validate|apply`, including explicit production/unknown
  target authority and allowlisted worker environment secrets.
- Added process-scoped `daemon start|restart --yolo` authorization with
  effective-mode status, worker propagation, and report provenance.
- Enforced suite `sharedSession`, `restartApp`, and `resetAppData` isolation
  before case fixtures, preserved dependency teardown ordering, propagated
  setup failures into blocked case reports, and kept attempted teardown active
  during cancellation.
- Added registered black-box targets for Android, iOS, desktop, browser, and
  system surfaces, with native accessibility locators, system setup/cleanup
  actions, screenshots, and capability-truthful failures.
- Added per-step semantic/native/visual/coordinate routing, including a
  secondary system driver for Flutter development sessions and plane-aware
  conditions, fragments, retries, loops, capture, and recording.
- Made the sanitized `target.inspect.output.systemControl` profile the
  capability authority for that secondary driver without exposing private app
  or process identities to clients.
- Changed macOS app recovery and activation to use the native application API,
  avoiding Automation and Accessibility permission requirements for focus
  recovery while retaining those permissions for real UI-tree and input work.
- Added deterministic workspace-confined visual template matching and
  screenshot baseline assertions with portable actual/baseline/diff artifacts.
- Added native and Flutter `copyText`, `eraseText`, and `pasteText` execution,
  bounded location-route travel, and efficient repeated platform key events.
- Added Android ADB execution and iOS simulator/physical-device WDA execution,
  including per-target WDA endpoints for concurrent workspaces and iOS
  physical-device install/uninstall through `devicectl`.
- Added a durable per-user Supervisor with isolated workspace workers,
  authenticated HTTP/SSE clients, idempotent admission, cancellation, and
  canonical artifact retention.
- Added paginated run artifact metadata across HTTP, CLI, and MCP plus
  streaming, size- and SHA-256-verified downloads for large evidence files.
- Migrated host CLI and MCP protocol imports to the platform-neutral
  `cockpit_protocol` package.
- Removed the `flutter_cockpit_protocol` dependency and established the 2.0
  package baseline without a compatibility forwarding layer.
- Removed the embedded HTML DevTools dashboard and browser-only assets. The
  local observability service is headless and exposes authenticated APIs for
  independently implemented clients.
- Added the standalone `cockpit.test/v2` YAML/JSON compiler, typed input and
  secret binding, deterministic Flutter case runner, safety policy checks,
  cancellation/cleanup kernel, and immutable `cockpit.report/v2` bundles.
- Added strict offline 1.x workflow import without a runtime compatibility
  path, plus package-local YAML and JSON case examples.
- Added deadline-scoped operation leases, optional adapter-backed abort, and
  late-completion isolation for deterministic cancellation and cleanup.
- Kept compiler/importer/runner/control/policy/secret/bundle verification as
  the public V2 boundary while retaining binder, plan, lowerer, kernel, and
  recorder as internal implementation modules.
- Aggregated independent structural compiler diagnostics through the published
  schema while retaining deterministic source paths and locations.
- Expanded release acceptance to cover DAGs, matrices, fixtures, loops,
  retries, semantic and gesture command families, recording lifecycles,
  mixed Flutter/native execution, and verified offline report bundles.
- Made Android and iOS release regressions require real native locator,
  action, and assertion proof under an isolated YOLO test daemon; iOS CI now
  boots and health-checks a digest-pinned WebDriverAgent runner.

## 1.1.4

- Added standalone `cockpit/` project support across CLI, MCP, validation
  examples, and CI without changing the production app dependency graph.
- Added platform-aware screenshot and recording preference with automatic app
  fallback when the preferred system path fails and fallback is allowed.
- Fixed development supervisor startup from global and project-local
  entrypoints by preserving the tool package resolution context for detached
  processes.
- Hardened iOS simulator shell and recorded validation, including truthful
  capability probing and traceable fallback evidence.
- Updated to stable `dart_mcp` 0.5.2 for normalized workspace root URIs and
  synced the real MCP verifier with the standalone development shell.
- Synced packaged MCP contract fallback documents with the repository contracts
  for AI development, workflow, and task-run bundle traceability.

## 1.1.3

- Removed the hosted CLI/MCP package dependency on the Flutter SDK by moving shared control, evidence, recording, runtime, and bridge DTOs to the pure Dart `flutter_cockpit_protocol` package.
- Fixed pub.dev global activation and project-local `dart run cockpit:cockpit` so development supervisor startup works from both installation modes.

## 1.1.2

- Fixed development supervisor startup so the background Dart process uses the `cockpit` tool package resolution context instead of the launched Flutter app workspace.

## 1.1.1

- Fixed the public `package:cockpit/cockpit.dart` export surface so launch configuration CLI/MCP helpers and their `args` types are available to downstream packages.

## 1.1.0

- Added shared Flutter launch configuration support across CLI, MCP, YAML workflows, development sessions, remote sessions, target launch, and platform launchers, including repeatable dart defines, dart define files, process environment values, and safe extra Flutter arguments.
- Added non-blocking AI development launch flows where `launch-app` returns after readiness while a background supervisor keeps logs, reload, restart, stop, screenshot, and recording control available.
- Added production workflow execution with YAML/JSON scripts, conditions, branching, loops, retry, step descriptions, traceable step artifacts, issue evidence, and bundle-ready output roots.
- Added Devtools live observability with scoped sessions, dense timeline ordering, collapsible panels, media previews, bundle download, workflow submission, and per-run artifact linking.
- Added system-first screenshot and recording orchestration with app-level fallback when allowed, plus representative recording previews and keyframe storyboards.
- Expanded Native/System Control Plane capability discovery and platform adapters for Android, iOS simulator/device, macOS, Windows, Linux, and web, with truthful availability metadata and explicit blocked-by-environment diagnostics.
- Improved CLI output rendering with AI-readable defaults, JSON output for pipelines, file output modes, and path-only terminal responses for file writes.
- Hardened host process, recorder, web bridge, simulator, and artifact download behavior so long-running development loops remain bounded and recoverable.

## 1.0.0

- Initial public release of the host-side tooling layer for `flutter_cockpit`
- Added CLI and MCP entrypoints for session bootstrap, control execution, snapshot collection, orchestration, and validation
- Added the Native/System Control Plane: `read-system-capabilities` and `run-system-action` (CLI and MCP) with capability-truthful Android adb, iOS simctl+WebDriverAgent, desktop, and web profiles, declared parameter contracts, and payload validation
- Added scene-level system macros for real debugging blockers: `resolveBlockers`, `preparePermissions`, `recoverToApp`, `tapNotification`, `readFocusState`, and `stabilizeForScreenshot`
- Added Android SystemUI demo-mode status bar overrides (`setStatusBar`/`clearStatusBar`) for deterministic screenshot evidence
- Added desktop host-plane actions through built-in tooling: system settings entry, host appearance, host file push/pull and media copy, app recovery, focus and device reads, notifications, and macOS `tccutil` permission resets
- Added web (browser) evidence through host window adapters so screenshots and recordings work once the browser app id or process id is known
- Added native system log reads (`readSystemLogs`: logcat, unified log, journalctl, Windows event log) so startup crashes are diagnosable before the runtime observer attaches
- Added Android battery simulation (`setBattery`) and connectivity toggles (`setConnectivity`), plus iOS simulator locale switching (`setLocale`)
- Added task-run bundle writing, summary shaping, structured `logs.json` evidence, and delivery evidence handling
- Added `read-task-bundle-summary` CLI output for low-token bundle review alongside MCP `read_task_bundle_summary`
- Added AI-readable default stdout rendering with JSON/path/file output formats for shell-friendly workflows
- Added sortable task-run bundle names, screenshot names, and recording keyframe paths for chronological artifact review
- Added host-side screenshot and recording adapters with validation and keyframe extraction
- Added remote session launchers for Android emulators, iOS simulators and devices, macOS, Windows, and Linux, with best-effort app cleanup when launch readiness fails
- Added collapsible Devtools dashboard panels with persisted panel layout and global collapse/expand controls for dense timeline, evidence, launcher, and inspector reviews
- Added live Devtools run scoping, timeline ordering controls, media preview, run bundle download, and workflow submission support for long-running validation sessions
- Fixed screenshot-only task bundle summaries so stale recording failure fields no longer block delivery gates when video was not requested
- Fixed development `launch-app` so it returns after readiness while the background supervisor keeps logs, reload, restart, and stop control alive
- Fixed `run-shell` and host recorder helper commands so short CLI/MCP calls are bounded, killable, and do not inherit recording startup timeouts
- Fixed stale development `stop-app` cleanup so platform app processes are stopped even when the supervisor is already unreachable
- Fixed the real MCP surface verifier so `serve-mcp` shutdown cleanup is bounded and cannot hang the validation run
- Fixed web bridge hot reload routing so stale browser reconnects cannot replace a ready client or hijack response ids
- Fixed transient artifact download timeouts by retrying retryable remote unavailability without masking structured artifact errors
- Fixed transient iOS simulator `simctl` clipboard/status/read failures with limited safe-action retries while preserving final failure diagnostics
