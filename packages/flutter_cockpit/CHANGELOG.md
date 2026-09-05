# Changelog

## 4.6.1

- Synchronized the Flutter bridge release with the corrected streamed
  performance contracts and AI integration guidance.

## 4.6.0

- Improved locator traversal and visibility handling for nested and layered
  Flutter surfaces, including structurally addressable Stack and Overlay
  branches without test-only keys.
- Added bounded command/gesture execution cleanup so failed or concurrent
  actions leave no active pointer or pump state behind.

## 4.5.0

- Added the Flutter bridge lifecycle for sequential performance capture
  segments and exposed active capture/build-mode status to remote clients.

## 4.4.6

- Discovers asynchronously mounted Router providers without an unbounded
  per-frame tree scan, while preserving automatic route tracking.

## 4.4.5

- Serialized executor settle and wait callbacks so concurrent in-app commands
  cannot overlap guarded Flutter test pumps.
- Synchronized the Flutter bridge release with the iOS native source recovery
  fix and updated native package metadata.

## 4.4.4

- Synchronized the Flutter bridge release with the iOS native wait recovery
  fix and updated native package metadata.

## 4.4.3

- Synchronized the Flutter bridge release with the iOS native wait recovery
  fix and updated native package metadata.

## 4.4.2

- Synchronized the Flutter bridge release with the iOS native capability probe
  fix and updated native package metadata.

## 4.4.1

- Synchronized the Flutter bridge release with the corrected cross-platform
  package metadata and CI validation contracts.

## 4.4.0

- Added reusable stateful `CockpitPerformancePluginRun` instances so each
  capture owns its hooks, subscriptions, and cleanup state independently.
- Kept plugin setup and cleanup bounded and isolated so instrumentation cannot
  block or invalidate the measured Flutter interaction.

## 4.3.0

- Synchronized the Flutter bridge package with the lossless performance archive
  and source-aware VM debugger release.

## 4.2.0

- Added explicit development-only performance plugins for AOP, business,
  network, database, and rendering instrumentation.
- Merged bounded plugin events into the same monotonic timeline as VM events,
  with source/isolate/location attribution, category filtering, sampling,
  payload limits, lifecycle deadlines, and isolated failure reporting.
- Closed frame, VM, memory, and plugin capture windows before teardown so
  cleanup and report-export work cannot inflate measured interaction timings.

## 4.1.0

- Synchronized the Flutter bridge package with the expanded DevTools evidence
  contract and current performance profiling release.

## 4.0.50

- Synchronized the Flutter bridge package with the current Cockpit performance
  tooling release.
- Allowed performance collectors to attach the bounded DevTools profile to the
  canonical report without changing normal app runtime behavior.

## 4.0.49

- Hardened off-screen reveal for fixed and non-viewport targets by using
  null-safe render-viewport discovery in profile and release builds.
- Performance reports now carry the complete total-frame phase alongside
  build/raster/vsync and can include memory samples supplied by test hosts.
- Synchronized the Flutter bridge package with the current Cockpit release.
- Added opt-in engine frame timing collection with cache peaks, jank budgets,
  percentiles, bounded retention, and truthful unavailable/partial metadata.
- Performance captures now preserve raster-finish wall-time, use the exact
  60Hz fallback interval, and label retained-sample aggregates explicitly.
- Every report records whether it was collected in debug, profile, or release
  mode so the result cannot be misclassified.

## 4.0.48

- Fixed Flutter pointer lifecycle delivery, double-tap settling, direct long
  press activation, and nested listener/slider target resolution.
- Extended the command lab acceptance path with real hover and wheel input.

## 4.0.47

- Fixed pinch gestures in nested scrollables so the delivered scale matches the
  requested ratio after gesture-arena recognition.
- Allocated independent pointer identities for double-tap sequences to mirror
  real platform input and avoid duplicate-pointer assertions.

## 4.0.46

- Added real hover, wheel/trackpad, coordinate, timed gesture, multi-pointer,
  animation-settle, and bounded live-watch support for Flutter development.
- Improved source-first target discovery and native fallback diagnostics without
  requiring developer-authored semantics labels.

## 4.0.45

- Synchronized the Flutter bridge package with the current Cockpit release.
- Added real hover and wheel/trackpad pointer-signal execution, including
  bounded wheel steps and correct device identity propagation.
- Extended animation and gesture settling to cover hover, wheel, and all
  multi-pointer mutations without exposing unbounded frame history.

## 4.0.44

- Synchronized native package metadata with the current Cockpit release.

## 4.0.43

- Synchronized native package metadata and documentation with the current
  Cockpit release; Flutter runtime behavior is unchanged.
- Added a bounded native recording-start cancellation path for callers that
  time out while an OS consent request is still pending.

## 4.0.42

- Exposed a development-only root key and in-app command executor factory so
  dedicated Dart integration-test adapters can reuse Cockpit's real control
  path without a loopback server, including test-binding frame hooks.

- Prevented merged ancestor semantics from assigning aggregate labels and
  actions to passive Flutter content or controls blocked by `IgnorePointer`
  and `AbsorbPointer`.
- Kept the real outer action target for delegated selection rows and exposed
  the unique blocked descendant control's current selection state without
  duplicating its implementation control.

## 4.0.41

- Synchronized native package metadata and documentation with the current
  Cockpit release; Flutter runtime behavior is unchanged.

## 4.0.40

- Synchronized native package metadata and development shell integration with
  the current Cockpit release; Flutter runtime behavior is unchanged.

## 4.0.39

- Cleared previous-generation runtime errors and unconsumed recorded steps at
  the Flutter hot-reload boundary while continuing to capture new errors.
- Required scroll visibility probes to win the real Flutter hit test and made
  default nearest reveal reposition targets that a fixed Flutter overlay
  covers when the scroll viewport can expose them.

## 4.0.38

- Synchronized native package metadata and development shell integration with
  the current Cockpit release; Flutter runtime behavior is unchanged.

## 4.0.37

- Documented the production-isolated `cockpit/` shell package for ordinary
  projects and Pub workspaces, including the correct direct Flutter launch
  flow and globally installed CLI boundary.
- Synchronized package metadata with the current Cockpit release.

## 4.0.36

- Synchronized native package metadata and development shell integration locks
  with the current Cockpit release.

## 4.0.35

- Added visibility-aware mounted target snapshots so offscreen Flutter controls
  remain inspectable without being reported as visible.
- Added automatic reveal for direct interactions across ordinary, lazy, and
  nested scrollable layouts, with forward and reverse search and final
  alignment validation.
- Made brief action results skip full target discovery while detailed and
  failure profiles retain proportional diagnostics.
- Replaced unsafe partial pipeline flushing with bounded real or synthetic
  visual frames on desktop and web.

## 4.0.34

- Aligned the Flutter package with the source-first Cockpit development
  workflow and its non-invasive structural selector guidance.

## 4.0.33

- Restored Flutter 3.32 compatibility for Material and Cupertino radio control
  state by deriving availability from their stable callback contract, and
  derived Material segmented-button state without relying on newer Semantics.
- Kept explicit source-derived custom-control selectors accurately ambiguous
  when multiple mounted Elements match, so a real ancestor scope can select the
  intended hit-tested target without falling back to compact discovery.

## 4.0.32

- Added non-invasive control-state discovery for standard Material and
  Cupertino controls, including disabled controls and safe text-input values.
- Discovered nested public controls independently while suppressing framework
  implementation duplicates, and exposed direct tap, text, hold, double-tap,
  increase, decrease, dismiss, and scroll capabilities without app annotations.
- Preserved stable keyed ancestors through deep framework layout wrappers,
  collapsed equivalent framework and Semantics control wrappers, and let
  targeted snapshots find matching mounted targets outside the viewport.
- Added direct semantics-independent Slider adjustment, InkResponse discovery,
  and hit-tested gestures for unique source-derived structural selectors so
  custom controls remain operable without keys or authored semantics.
- Made target-driven scrolling observe newly laid-out lazy children in the scroll
  step itself, avoiding repeated full settle waits before a target is mounted.
- Kept investigate diagnostics on the live filtered Widget ancestry instead of
  replacing it with the smaller selector ancestry.

## 4.0.31

- Reused text copied by the current Cockpit runtime and bounded fallback
  platform clipboard access, preventing iOS pasteboard reads from stalling
  text-input commands past their deadline.

## 4.0.30

- Resolved unique mounted Flutter actions from the target's root-to-element
  chain instead of scanning the complete surface, with full discovery retained
  for indexed, ambiguous, and complex fallbacks.
- Reused scroll-container discovery during one target search and kept tooltip
  matching limited to real Flutter tooltip signals.

## 4.0.29

- Let locator-free dismiss actions invoke Flutter's current `DismissIntent`,
  closing standard menus, popups, dialogs, drawers, and modal routes before
  falling back to explicit semantic dismiss targets.

## 4.0.28

- Synchronized the Flutter bridge package with the current Cockpit release.
- Kept remote health reads lightweight while exposing bounded runtime and
  network failure summaries for live session monitoring.
- Added request capture filters so development shells can exclude internal
  control-plane traffic from application network evidence and idle waits.

## 4.0.27

- Synchronized the Flutter bridge package with the current Cockpit release.

## 4.0.26

- Kept Flutter control, idle waits, and screenshots responsive when desktop or
  web frame delivery stalls, while retaining normal vsync as the primary path.
- Applied exact, contains, fuzzy, and regex matching consistently to semantic
  identifiers used by Flutter-first multi-condition selectors.
- Removed redundant screenshot settling and preserved correct post-action frame
  commits without requiring application-authored Semantics.

## 4.0.25

- Synchronized the Flutter bridge package with the current Cockpit release.

## 4.0.24

- Kept direct Cupertino discovery while preventing type-only container matches
  from suppressing their real actionable descendants.
- Preserved public semantics-owned slider and dropdown targets without relying
  on a global interactive-widget type boundary.

## 4.0.23

- Added direct, semantics-independent discovery and control for public
  Cupertino buttons, rows, selection controls, sliders, and text fields.
- Exposed stable option targets for Cupertino segmented controls and report
  only committed selection changes.
- Kept remote snapshots responsive when Flutter has no pending frame or a
  backgrounded engine cannot finish one.

## 4.0.22

- Report committed selection and value changes for Flutter controls even when
  their mounted element structure and visible text remain unchanged.

## 4.0.21

- Report committed Flutter text mutations independently of structural widget
  changes.

## 4.0.20

- Synchronized the Flutter bridge package with the current Cockpit release.

## 4.0.19

- Synchronized the Flutter bridge package with the current Cockpit release.

## 4.0.18

- Synchronized the Flutter bridge package with the current Cockpit release.

## 4.0.17

- Synchronized the Flutter bridge package with the current Cockpit release.

## 4.0.16

- Synchronized the Flutter bridge package with the current Cockpit release.

## 4.0.15

- Synchronized the Flutter bridge package with the current Cockpit release.

## 4.0.14

- Synchronized the Flutter bridge package with the Cockpit 4.0.14 release.

## 4.0.13

- Synchronized the Flutter bridge package with the Cockpit 4.0.13 release.

## 4.0.12

- Aligned the Flutter bridge with the Cockpit CLI and protocol release while
  retaining the bounded large-snapshot transport introduced in 4.0.6.

## 4.0.6

- Externalized large Flutter snapshots while keeping a bounded transport
  summary, so complex mounted Widget trees remain fully inspectable without
  exceeding worker message limits.
- Preserved complete target data in downloadable artifacts while bounding
  inline target count and text size for responsive AI-driven inspection.

## 4.0.5

- Synchronized the Flutter bridge package with the Cockpit 4.0.5 release.

## 4.0.4

- Made focused Flutter inspection execute the same conjunctive selector
  matching as actions, including key, type, route, ancestor, and index signals.
- Kept free-text inspection queries as bounded exploratory searches.

## 4.0.3

- Made mounted Flutter Element probes use the same deterministic text matching
  and ranking semantics as registry-backed actions and assertions.

## 4.0.2

- Filtered snapshot targets before limits so focused inspection cannot miss a
  matching mounted Flutter element on large pages.
- Preserved `Semantics(explicitChildNodes: true)` isolation so container labels
  no longer overwrite descendant control identities.
- Made action resolution intersect every selector condition and rank indexed
  matches by visual geometry.
- Kept structural Widget trees in verified path-only artifacts for detailed
  inspection without expanding routine output.

## 4.0.1

- Made mounted Flutter Element discovery independent of developer-authored
  Semantics for key, text, type, route, path, and ancestor conditions.
- Associated wrapper locators with the nearest command-capable descendant or
  ancestor while keeping equal actionable matches explicitly ambiguous.
- Kept read-only assertions bound to the matched Element itself, preventing
  nearby controls from making `assertVisible` ambiguous.
- Added gesture hit-test preflight so covered or off-viewport targets fail or
  warn according to the requested policy instead of reporting false success.

## 4.0.0

- Added bounded descendant text parts to mounted Flutter target discovery so
  composite rows and controls expose their exact visible child labels.
- Added readable Tooltip locators for icon-only controls.
- Fixed `scrollUntilVisible` verification when repeated rendered labels make a
  direct Element probe ambiguous but the intended target is visibly mounted.
- Preserved successful text mutations when their exact `EditableText` value is
  already committed but optional post-action settling reaches the command
  deadline.
- Runtime session and event identifiers now use compact lowercase IDs.

## 3.0.14

- Synchronized the Flutter bridge with Cockpit's stale development-session
  recovery and Agent workflow release; bridge behavior is unchanged.

## 3.0.13

- Added semantics-independent mounted Element and RenderObject tree capture
  with minimal, standard, and full profiles. Full trees include bounded
  Widget/Element/State/Render diagnostics and are exposed through verified
  artifacts instead of oversized inline responses.
- Preserved direct Widget text below `ExcludeSemantics`, normalized common key
  spellings, and hardened lazy/nested scrolling by observing layout after
  direct position jumps.
- Wait for both an idle scheduler phase and any scheduled frame before
  completing actions, preventing hidden desktop frames from exposing stale UI.

## 3.0.12

- Synchronized the Flutter bridge release with Cockpit's daemon concurrency,
  capability startup, and development-session reconnect corrections; public
  bridge contracts are unchanged.

## 3.0.11

- Synchronized the Flutter bridge with Cockpit's latest-release updater
  correction; bridge behavior is unchanged.

## 3.0.10

- Captured Android and iOS through the system screen first so permissions and
  operating-system dialogs remain visible, while desktop and web keep the
  lower-latency Flutter capture path as their default.
- Advanced a bounded Flutter frame timeline for hidden desktop and web
  surfaces that cannot receive normal vsync, allowing actions, routes, and
  animations to commit before Cockpit observes their result.

## 3.0.9

- Synchronized the Flutter bridge with Cockpit's Supervisor-restart recovery;
  bridge behavior is unchanged.

## 3.0.8

- Synchronized the Flutter bridge with Cockpit's downgrade-safe updater;
  bridge behavior is unchanged.

## 3.0.7

- Synchronized the Flutter bridge with the Cockpit 3.0.7 updater repair;
  bridge behavior is unchanged.

## 3.0.6

- Synchronized the Flutter bridge with the Cockpit 3.0.6 runtime identity
  recovery patch release; bridge behavior is unchanged.

## 3.0.5

- Rejected macOS logical viewport sizes that cannot fit the active display
  immediately with `viewportExceedsScreen` and an exact maximum-size
  alternative, instead of waiting for an impossible resize to settle.
- Preserved exact native window resizing for dimensions that fit the display.

## 3.0.4

- Preserved real Enter key delivery for focused multiline inputs so app-level
  Flutter shortcuts run, while single-line fields still receive their declared
  IME submit, search, navigation, or completion action.
- Resolved the focused `EditableText` through its actual focus-node ancestry
  instead of silently treating non-default input actions as `done`.

## 3.0.3

- Synchronized the Flutter bridge patch release with Cockpit 3.0.3 and the
  matching protocol package while preserving the validated runtime behavior.

## 3.0.2

- Routed Enter on a focused Flutter text field through its real IME action so
  submit, next, search, send, and related application callbacks execute
  correctly during Cockpit control.
- Settled key actions against observable route and semantic state before
  reporting whether the UI changed, avoiding stale success projections.
- Tightened recording wire values and required recording request fields so
  malformed client input fails explicitly instead of selecting aliases or
  implicit names.

## 3.0.1

- Aligned iOS and macOS plugin packaging with Flutter's dual-distribution
  guidance by keeping current CocoaPods podspecs and adding the required
  FlutterFramework dependencies to both SwiftPM packages.
- Exposed Flutter semantics through the native macOS accessibility tree for
  black-box locators without changing production application entrypoints.
- Hardened nested and lazy scrolling with bidirectional search, deterministic
  alignment and offsets, and full visibility through every scroll ancestor.
- Reduced routine semantic snapshots and visible-target probes so live UI
  inspection stays accurate and token-efficient on large trees.

## 3.0.0

- Added fast exact semantic discovery with conjunctive multi-condition
  locators, actionable-target filtering, and duplicate descendant suppression.
- Added nested scroll-container search with forward and reverse probing,
  `start`/`center`/`end` alignment, signed offsets, and full ancestor viewport
  visibility checks.
- Added native viewport resizing across desktop plugin platforms and remote
  bridge reporting for deterministic responsive verification.
- Added bounded HTTP, SSE, and WebSocket observation with masked credentials,
  explicit raw body artifacts, binary-safe metadata, and truthful unfinished
  response state.
- Changed default tap fallback so passive text cannot report a false success;
  explicit gesture activation remains available for deliberate pointer input.
- Removed the 2.x bridge compatibility surface and adopted the 3.0 protocol
  contracts directly.

## 2.2.1

- Synchronized the Flutter bridge patch release with Cockpit 2.2.1; Flutter
  runtime behavior remains compatible with 2.2.0.
- Redacted captured network credentials by default while preserving useful
  authentication structure, with an explicit development-only raw capture
  configuration for local diagnosis.

## 2.2.0

- Updated the Android plugin to the modern Gradle plugins DSL while preserving
  Kotlin 17 compilation and the full cross-platform Flutter bridge contract.
- Clarified the Flutter-first development path and its structured runtime,
  widget, route, log, error, network, reload, capture, and command capabilities.

## 2.1.0

- Synchronized the Flutter bridge release with Cockpit 2.1.0 and its
  `cockpit_protocol` 2.1 contract baseline.

## 2.0.1

- Added the Cockpit logo to the published package documentation.

## 2.0.0

- Integrated the Flutter semantic bridge with the workspace-scoped 2.0 target,
  case, suite, checkpoint, and artifact runtime.
- Kept Flutter semantic execution as one driver behind the shared 2.0 case and
  suite runtime while native black-box targets execute independently in the
  host package.
- Added bridge-native copy, erase, and paste editing actions while allowing the
  host runner to switch individual Flutter case steps to a secondary system
  driver for native, visual, coordinate, and mixed-stack interaction.
- Migrated all shared runtime, control, evidence, and bridge models to the
  platform-neutral `cockpit_protocol` package.
- Removed the `flutter_cockpit_protocol` dependency and established the 2.0
  package baseline without a compatibility forwarding layer.

## 1.1.4

- Added automatic route tracking for plain and nested `Navigator` stacks and
  Router-based libraries, including `go_router`, while keeping all integration
  inside the standalone `cockpit/` development shell.
- Added platform-aware screenshot routing with native/app fallback and truthful
  source metadata when the preferred system capture path is unavailable.
- Hardened native screenshot and recording lifecycles across Android, iOS,
  macOS, Linux, and Windows, including Android surface capture and bounded video
  dimensions.
- Documented and verified dual CocoaPods and Swift Package Manager support for
  iOS and macOS from the same native sources and privacy manifests.
- Kept Cockpit packages and imports out of the production app dependency graph
  by moving the complete development integration into a standalone shell.

## 1.1.3

- Re-exported shared AI control, evidence, recording, and runtime protocol models from the pure Dart `flutter_cockpit_protocol` package so host tooling can run without a Flutter SDK dependency.

## 1.1.0

- Added shared Flutter launch configuration support for `--dart-define`, `--dart-define-from-file`, extra Flutter arguments, and process-scoped environment values across CLI, MCP, development sessions, remote sessions, workflow scripts, and platform launchers.
- Added centralized internal remote-control dart define generation so cockpit-owned launch flags stay consistent across platforms and cannot be accidentally overridden by user-provided raw Flutter arguments.
- Improved AI-first runtime evidence flows through app, native, system, host, and recording planes while preserving low-intrusion `cockpit/` entrypoint integration.
- Improved task and recording artifact traceability with step-attached screenshots, recording evidence metadata, and chronological artifact naming.

## 1.0.0

- Initial public release of the in-app runtime layer for `flutter_cockpit`
- Added low-intrusion root bootstrap and Flutter-native target discovery
- Added in-app control, gesture, wait/assert, capture, and recording primitives
- Added native acceptance capture and recording across Android, iOS, macOS, Windows, and Linux, with capability-truthful web rejection
- Added rich runtime snapshots, network observation, and runtime event observation
- Added remote session server, a WebSocket bridge client for web, and shared bundle/domain models
- Added sortable, readable artifact naming helpers for screenshots, diagnostics, and task-run bundles
- Added `waitFor` absent mode (`parameters.absent: true`) so flows can wait for spinners, dialogs, or routes to disappear
- Added `dismissKeyboard` command and focus-state snapshots (`snapshot.focus`) reporting the focused widget and whether text input is active
- Added direct activation for Radio/RadioListTile and the real tristate Checkbox cycle, with occlusion-safe multi-touch validation and pointer-cancel cleanup
- Added release-build semantics resolution through the live SemanticsOwner tree so the semantic plane stays truthful outside debug builds
- Defaulted `CockpitInteractionPolicy.hitTestMissPolicy` to `fail` so taps that miss their target surface as errors instead of silently passing as no-ops
- Fixed screenshot-only acceptance bundles so video evidence gates are satisfied when recording was not requested, while real recording failures still surface explicitly
- Guarded Android window PixelCopy capture behind API 26 so older devices report `captureUnavailable` instead of crashing
