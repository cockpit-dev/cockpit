# Changelog

## 4.0.27

- Prevented iOS black-box idle waits from timing out on expensive accessibility
  attributes while retaining complete WebDriverAgent trees for native locators.
- Made iOS native-tree taps, repeated taps, and text focus execute the uniquely
  resolved WebDriverAgent element, and mapped visual screenshot pixels into the
  WebDriverAgent viewport before coordinate gestures.
- Kept healthy `dev diagnose --view more` output focused by omitting snapshot
  profile noise, routine next steps, empty logs, and non-failing endpoint rows.

## 4.0.26

- Added bounded newest-first lease pagination so large durable registries remain
  fast and usable from CLI, Console, REST, and MCP.
- Added recent durable run listing with resumable workspace pagination and
  preserved run reconstruction across Supervisor and worker restarts.
- Replaced macOS JXA activation with native application activation, avoiding
  unnecessary System Events Automation permission prompts.
- Stabilized screenshot and native-system capture immediately after E2E runs by
  allowing genuine device/capture contention to settle within the command budget.
- Improved Flutter label lowering, network body artifacts, compact run output,
  and recovery behavior for concurrent and interrupted development sessions.
- Allowed `suite report` to atomically export into pre-created empty
  directories while preserving any destination populated during export.

## 4.0.25

- Made explicit Flutter selectors use the same conjunctive route, ancestor,
  text-mode, and index matching as live actions, preventing unrelated mounted
  targets from appearing as inspect matches.

## 4.0.24

- Restored reliable Flutter locator and action discovery for nested controls
  while retaining direct Cupertino support.

## 4.0.23

- Added complete direct Flutter control for public Cupertino widgets without
  requiring application-authored semantics or exposing internal widget noise.
- Prevented remote inspect, scroll, and tree reads from failing with a generic
  server timeout while Flutter is paused, backgrounded, or between routes.

## 4.0.22

- Report successful Flutter selection and value mutations as `changed:true`
  without adding control state to the default compact output.

## 4.0.21

- Report successful Flutter text mutations as `changed:true` even when the
  mounted element structure is unchanged.
- Confirm successful scroll actions with compact `visible:true` output so an
  agent can continue without an extra inspection command.

## 4.0.20

- Kept Skill refresh guidance AI-ready and token-efficient: `cockpit skill`
  prints one complete installation/update prompt, release checks return the
  executable update step, and completed updates point to `cockpit skill`.
- Preserved unknown platform-app reachability instead of reporting an offline
  or unavailable device as a stopped Flutter application, and direct agents to
  target discovery rather than repeated status polling.
- Included up to four mounted actionable targets in default zero-match Flutter
  inspection output, eliminating an extra diagnostic command while keeping
  successful inspection output unchanged.

## 4.0.19

- Added `cockpit skill` to print one stable prompt and authoritative path for
  installing or refreshing the current AI host's complete Cockpit integration.
- Added `cockpit update --check` for a fast, side-effect-free Pub release check,
  and point completed runtime upgrades to the Skill refresh command.
- Returned the current route and a bounded mounted-target index when focused
  Flutter inspection finds no match, without loading or printing a broad tree.
- Relaunched stopped development handles through the requested yolo Supervisor
  before workspace capability discovery, eliminating a redundant daemon/worker
  cycle and preventing relaunch requests from appearing stuck.

## 4.0.18

- Applied exact bounded-inspection recovery to locator failures returned inside
  completed Flutter command results, matching the real hosted development path
  as well as operation-level failures.

## 4.0.17

- Directed failed Flutter locator actions to a bounded inspection of the exact
  selector so agents can copy a verified actionable target instead of loading
  broad diagnostics or guessing a nearby control.
- Clarified the bundled agent skill so passive text is never implicitly mapped
  to an adjacent action and the original mutation is retried at most once.

## 4.0.16

- Kept live Flutter applications in a reconnecting state when their control
  bridge is temporarily unavailable, instead of misreporting them as crashed
  or launching a duplicate application instance.
- Added platform process reachability checks for Android, iOS simulators,
  macOS, Linux, and Windows, while treating unavailable platform probes as
  inconclusive rather than proof that an application exited.
- Clarified compact session and status output with independent `ready`,
  `appLive`, and `bridgeLive` fields, and direct safe-recovery guidance for a
  live Android application whose bridge is blocked in the background.
- Bounded interactive screenshot resource waits and preserved structured
  `resourceBusy` failures so concurrent sessions fail quickly without crossing
  project, checkout, device, or capture ownership boundaries.
- Recognized Android ANR and application-error overlays as system-sourced
  screenshot surfaces so AI agents can diagnose blockers outside Flutter.

## 4.0.15

- Made Android development launches fail within a bounded readiness probe when
  ADB is missing, unauthorized, offline, not booted, or unresponsive instead
  of appearing stuck inside Flutter device discovery.
- Bounded Android port-forward operations so a stalled ADB connection cannot
  consume the complete development command timeout.
- Directed stopped, crashed, and unreachable development sessions back to
  `dev start` with the same handle, preserving project and target isolation
  without creating another application instance.

## 4.0.14

- Added live Linux AT-SPI D-Bus tree inspection with runtime capability
  probing, bounded traversal, native state and geometry signals, and explicit
  blocked results when the accessibility bus or target is unavailable.
- Added target-scoped Chromium CDP automation for generic browser pages,
  including bounded DOM trees, nested same-origin iframe coordinates, input,
  pointer, navigation, dialog, window, and state operations.
- Carried exact Chromium CDP endpoints through CLI, MCP, Supervisor schemas,
  target persistence, lifecycle operations, and compact target inspection
  without scanning browser ports or attaching to unrelated profiles.
- Unified native role matching across platform naming conventions and marked
  system scroll gestures explicitly so browser wheel input does not degrade
  into drag input.
- Kept Flutter Web development on the in-app Element/RenderObject bridge while
  advertising generic DOM actions only after a live CDP probe succeeds.

## 4.0.13

- Added `cockpit dev recover` for exact-session native blocker recovery with
  focus-only defaults, safe dismissal of proven Android dialogs, explicit
  keyboard handling, and fast no-op detection when the app already has focus.
- Bundled and verified Android UI Automation drivers beside AOT installations,
  including atomic updates and a version-checked hosted-package handoff path.
- Preserved Flutter apps when the Supervisor detaches, preventing daemon restarts
  from terminating or relaunching unrelated development sessions.
- Improved Android dialog handling so an absent matching dialog never sends a
  speculative global Back action.
- Made macOS recovery use permission-free foreground inspection and activation,
  report locked desktop sessions precisely, and stop claiming that failed
  recovery changed application state.
- Verified macOS activation reaches the foreground instead of treating an
  accepted activation request as completed recovery.
- Gave native, visual, and coordinate E2E condition probes enough bounded time
  for platform tree reads while preserving the fast Flutter semantic path.
- Kept native and mixed-plane acceptance retries from replaying mutations that
  already reached their expected UI state.
- Retried one transient Windows directory-authority probe and preserved
  native filesystem diagnostics instead of misclassifying failures as success.
- Made Linux and macOS home resolution use target-platform path semantics even
  when Cockpit runs on a Windows host.

## 4.0.12

- Reduced complete Flutter snapshot artifacts inside workspace workers and
  returned only bounded locator results, preventing complex UI inspection from
  exceeding the worker message limit.
- Applied the same complete multi-condition locator ranking to public
  `ui.inspect` and `surface.inspect` operations while keeping structural trees
  path-only.
- Externalized evidence UI payloads without losing diagnostic or artifact
  metadata, and cleaned temporary locator artifacts after in-process parsing.
- Kept `dev diagnose` aligned with bounded inspection by reading the compact UI
  summary plus dedicated runtime, network, and log diagnostics instead of
  treating an intentionally externalized locator snapshot as an empty screen.
- Avoided duplicate runtime and network collection in `dev diagnose`, keeping
  its Flutter UI summary focused while the dedicated readers collect details.
- Flattened the diagnostic UI summary into short decision fields instead of
  repeating route, profile, snapshot, and nested summary data.
- Added `cockpit dev open URI` for direct deep-link, universal-link, app-link,
  and URL testing through the selected development session.
- Made failed native system actions return a failed operation consistently to
  CLI, REST, and MCP clients instead of a successful receipt with an error body.

## 4.0.11

- Restored Flutter development sessions without waiting for every retained E2E
  event stream to replay, keeping cold inspect and control commands responsive
  while durable recovery continues in the background.

## 4.0.10

- Made `cockpit update` wait within its command timeout when Pub package APIs
  expose a new Cockpit release before Dart Pub's solver index can resolve it,
  avoiding a transient first-update failure immediately after publication.

## 4.0.9

- Made Flutter inspection prefer stable ancestor-scoped selectors before
  widget paths and use ancestor keys, text, tooltips, and types as exact
  intersecting signals.
- Collapsed derived text proxies when their stable logical control covers the
  same actions, avoiding fragile indexed selectors for repeated Flutter rows.

## 4.0.8

- Made the update version lookup request the identity-encoded Pub metadata
  representation so a stale compressed CDN variant cannot hide a newly
  published release.

## 4.0.7

- Made compact output preserve pre-existing omission counts when the final
  token projection removes additional values, so `more` always reports the
  complete number of hidden results.

## 4.0.6

- Made `cockpit update` pin the Pub release discovered by its uncached lookup
  and recover stale Dart Pub dependency indexes through the official package
  cache command before retrying installation.

## 4.0.5

- Added a unique Pub metadata query to `cockpit update` so a newly published
  release is discoverable without waiting for the shared CDN cache to expire.
- Compacted Flutter target output by omitting labels already represented by a
  stable selector and collapsing duplicate text candidates from the same
  logical control during free-text inspection.

## 4.0.4

- Made `dev inspect` preserve and verify explicit Flutter selectors before
  returning them for direct action reuse.
- Bypassed cached Pub metadata during `cockpit update` so newly published
  versions become discoverable immediately.
- Removed an acceptance-only full-screen semantics wrapper that distorted the
  macOS native accessibility tree and blocked native Back actions.

## 4.0.3

- Unified fuzzy target ranking between Flutter development commands and native
  black-box E2E so the same locator selects the same closest text candidate.

## 4.0.2

- Replaced legacy locator flags with one compact selector accepted directly by
  Flutter development actions.
- Made `dev inspect QUERY` push bounded search into Flutter before target
  limits, return concise reusable selectors, and report partial only when
  matching targets are actually omitted.
- Preferred stable Flutter keys over duplicated native discovery identities in
  locator advice while preserving explicit Cockpit IDs.
- Made `dev tree --view more|full` write complete structure to a verified
  artifact and print only its path.
- Expanded the distributed Cockpit skill with the canonical selector,
  unexpected-state recovery, and AI-first Flutter workflow guidance.

## 4.0.1

- Added direct execution of validated local case and suite documents through
  `case run --file` and `suite run --file`, while retaining durable indexed
  identities for shared and CI workflows.
- Reused API-compatible newer Supervisors from older clients and replaced only
  genuinely older or malformed daemon engines, preserving authorization mode.
- Added Android foreground-surface diagnostics to system screenshots so app,
  operating-system overlay, and different-app captures cannot be mistaken for
  the same Flutter state.
- Preserved screenshot surface metadata through fallback, remote automation,
  visual comparison, and concise CLI projections.
- Avoided reinstalling an already-current canonical hosted AOT executable during
  `cockpit update`, while still reconnecting the Supervisor and cleaning retired
  source payloads.

## 4.0.0

- **Breaking:** renamed `--verbosity minimal|standard|full` to
  `--view brief|more|full`.
- **Breaking:** shortened CLI projection fields and flattened development and
  session status output. Operation input fields remain available through
  `cockpit explain`.
- **Breaking:** resource identifiers now use compact lowercase IDs.
- Fixed WebSocket network projection to read the actual frame activity contract
  (`sentFrames`, `receivedFrames`, recent frames, truncation, and byte metadata).
- Made `cockpit dev inspect QUERY` recommend exact child-text locators for
  composite Flutter controls and readable Tooltip locators for icon-only
  controls.
- Preserved slash-command UI labels such as `/inspect` while continuing to
  redact real absolute paths from diagnostic output.
- Fixed `cockpit dev scroll` timeouts when a visible field and its rendered
  label both match the same query; mutation commands still require a uniquely
  resolved target.
- Prevented a proven Flutter text mutation from being reported as failed when
  only optional post-action settling exhausts the remaining command deadline.

## 3.0.14

- Fixed `cockpit dev start` recovery for stopped or crashed handles whose
  worker-owned session no longer exists. Explicit relaunch now skips the stale
  stop request, replaces the same target, and reuses the original numeric
  handle instead of failing with `opaqueReferenceNotFound` or creating another
  app instance.
- Kept non-persisted custom-launch sessions stopped when their original launch
  options are required, and now directs the caller back to `dev start` with
  those options instead of suggesting an ineffective restart.
- Added a bounded unexpected-state recovery workflow to every distributed
  Cockpit Skill: observe the current UI, choose one safe recovery, preserve
  session identity, and prove the expected postcondition before resuming.

## 3.0.13

- Added `cockpit dev tree` with minimal, standard, and full Flutter structure
  profiles. Routine output remains bounded LON; complete trees are retained as
  verified artifacts and stdout returns only their paths.
- Made `dev inspect` and action locators use mounted Flutter Element signals
  without requiring application-authored Semantics, including structural
  `--path` disambiguation when stable public signals are insufficient.
- Replaced an existing app before relaunching the same target while preserving
  every other target and session, preventing duplicate windows and commands
  from binding to stale instances.
- Removed terminal runs from the active-run registry so a completed run cannot
  block a later worker refresh, and serialized per-workspace build selection
  without affecting unrelated projects.
- Replaced dynamically compiled PowerShell/C# automation on Windows with
  in-process Win32 FFI for window discovery, activation, focused-control
  inspection, and native input. Ambiguous application-ID matches now fail
  explicitly instead of risking control of another project or checkout.
- Captured Windows system screenshots in process through Win32 GDI with Dart
  PNG encoding. The Windows regression path dropped from roughly 28 seconds to
  407 milliseconds while retaining real system-screen evidence for native
  dialogs and operating-system UI.

## 3.0.12

- Serialized every daemon lifecycle transition under one bounded cross-process
  lock. Concurrent reads no longer race an authorization change, lifecycle lock
  waits honor each command timeout, and an unflagged `daemon start` or restart
  preserves the authorization of an already running daemon instead of silently
  downgrading yolo mode. Discovery reads also treat a record that disappears
  during an expected daemon shutdown as absent without weakening canonical-file
  validation for records that still exist.
- Made the global capability document a static Supervisor catalog, reducing a
  real Console cold request from 3.89 seconds to 5 milliseconds without
  launching or reconnecting workers from unrelated workspaces. Workspace-scoped
  operation routes remain the exact live authority for a selected workspace.
- Wait for Flutter's `app.started` event when a development session reconnects
  after Supervisor replacement, preventing the first reload or restart from
  being rejected while device initialization is still incomplete.
- Select the iOS regression simulator from the newest runtime supported by the
  active Xcode installation, so WebDriverAgent and `simctl` always address the
  same compatible destination on moving GitHub runner images.

## 3.0.11

- Fixed `cockpit update` to ask Pub for the current latest hosted release
  instead of passing a lower-bound constraint that could treat the already
  active version as sufficient and skip a newer release. Installed-version
  verification, downgrade blocking, rollback, AOT optimization, and Supervisor
  reconnection remain enforced.

## 3.0.10

- Preserved a stable application temporary directory across Supervisor and
  worker replacement for desktop Flutter development, restoring DevFS reload
  and restart without relaunching the app or touching concurrent sessions.
- Applied the same isolated temporary-directory lifecycle to detached Linux,
  Windows, and environment-driven macOS automation apps, with cleanup on stop
  and launch failure and explicit rejection of conflicting user temp settings.
- Released logical leases immediately when they require no external cleanup,
  removed unnecessary session leases from safe reads, and required the device
  lease for screenshots so concurrent commands remain correctly isolated.

## 3.0.9

- Fixed development-session recovery after a Supervisor restart. Lazy Flutter
  attach now waits for `app.started`, persisted VM-service WebSocket URLs are
  normalized to Flutter's HTTP attach base, and rejected `app.restart`
  responses no longer advance generation or mark a reachable app as crashed.

## 3.0.8

- Prevented `cockpit update` from accepting a stale Pub version index that
  resolves an older hosted release. Activation now requires a version at least
  as new as the running executable, and verification blocks any downgrade before
  the hosted installation is accepted or compiled to AOT.

## 3.0.7

- Fixed `cockpit update` when the fast source installer had placed a native AOT
  executable in Dart Pub's launcher directory. The updater now hands the live
  executable to Pub through a recoverable text launcher, verifies the hosted
  package, recompiles it to AOT, atomically restores the single fast executable,
  and removes takeover files without losing sessions or Supervisor state.

## 3.0.6

- Added `cockpit update` to install and verify the latest hosted release,
  reconcile the running Supervisor in place, and remove the retired split AOT
  source-install payload without touching Dart Pub's shared package cache.
- Kept registered target handles synchronized when Flutter attach, reload, or
  suite isolation replaces the runtime application identity, including
  self-healing persisted pre-upgrade state and preserving the Supervisor log
  reference. `dev diagnose` no longer fails after an otherwise healthy
  Supervisor reconnect.
- Made routine LON output explicit across the AI Skill and public guidance;
  JSON is now reserved for `jq`, JSON-only consumers, and wire inspection.

## 3.0.5

- Reported impossible macOS viewport requests immediately as unavailable with
  the active display's exact logical content limit and recovery alternatives,
  avoiding a misleading settle timeout while preserving exact valid resizes.
- Versioned Supervisor and worker engines with the installed Cockpit package;
  the first managed command after an upgrade now drains and replaces an older
  running engine automatically while preserving authorization and durable state.
- Made the Agent Skill keep default LON output for routine work and reserve
  JSON for `jq`, JSON-only consumers, or explicit wire-format inspection.

## 3.0.4

- Fixed `cockpit dev press enter` for multiline Flutter controls that bind
  Enter through app-level shortcuts, without regressing normal IME submission
  for single-line text fields.
- Isolated suite retry resource leases by attempt and observed heartbeat
  failures from session preparation onward, preventing a transient native
  activation timeout from terminating the workspace worker on retry.

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
