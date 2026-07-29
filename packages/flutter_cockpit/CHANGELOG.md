# Changelog

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
