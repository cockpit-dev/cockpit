# Changelog

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
