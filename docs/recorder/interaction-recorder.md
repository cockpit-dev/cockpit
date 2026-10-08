# In-app interaction recorder (`cockpit.recording/v1`)

This document defines the architecture and contracts for recording **real
user interaction** inside a running Flutter app and converting it into a
replayable `cockpit.test/v2` case document. It is the implementation
baseline: every phase of the build references this file.

The recorder inverts the direction of the existing Cockpit automation stack.
Everything shipped so far **dispatches** synthetic input through the gesture
engine; the recorder **listens** to organic user input, resolves each hit to
Cockpit selector candidates, and emits the same typed step records the
automation side already understands.

## Design rules

1. **Capability, presentation, and host are separate layers.** The recording
   engine is UI-free and host-free. The panel is an embeddable widget, not a
   window. Any floating-window system (UME, flutter_mana, DoKit, a custom
   host) is a first-class host through four public surfaces — we do not ship
   per-ecosystem adapter packages.
2. **One typed contract, many transports.** The in-app panel (in-process),
   remote endpoints, CLI, and MCP all speak the same session commands and
   state machine defined in `cockpit_protocol`. Consistency is structural,
   not disciplinary.
3. **Selectors, never coordinates.** A recorded step stores ordered locator
   candidates (key > semanticId > text > tooltip > type), the same precedence
   the target registry's `_signalScore` already encodes. Raw hit positions
   are diagnostic metadata only.
4. **Exclusion degrades gracefully.** Recorder UI and host chrome are
   excluded from the recorded stream and from evidence screenshots. When an
   event resolves to no registered target (typical for third-party debug
   chrome, which carries no semantics), it is kept in the raw timeline as an
   `unresolved` noise step and dropped from the exported case — never a
   correctness failure.
5. **Waits, not timestamps.** Exported cases wait on conditions (visible /
   route / idle), never on recorded wall-clock deltas.

## Non-goals (v1)

- No recording of OS-level surfaces (permission dialogs, other apps). The
  native plane is observed where the existing dual-plane observation already
  covers it; native interruptions surface as guarded steps during export.
- No backward time travel. Replaying from step *k* means restart and
  fast-forward steps 1..k-1, not state restoration.
- No per-keystroke capture. Text entry records the final committed value per
  field.
- No SSE. Remote surfaces follow the existing pull model (`drain`), like
  runtime steps today.

## Layered architecture

```
L5  External surfaces   Console GUI · CLI (`cockpit record`) · MCP tools
L4  Hosts               Default floating-ball host (built in) · custom hosts
L3  Panel components    CockpitRecorderController + embeddable panel widgets
L2  Engine              Capture layer · session state machine · exclusion ·
                        evidence · verify-replay
L1  Contract            cockpit_protocol: session, steps, locator candidates,
                        flow bundle, case converter, YAML writer
```

Dependency direction is strictly downward. `flutter_cockpit` hosts L2–L4;
`cockpit` hosts L5; `cockpit_protocol` owns L1. No package depends on an
external floating-window framework.

## Contract models (`cockpit_protocol`, `lib/src/recorder/`)

All models follow package conventions: hand-written `final` classes, manual
`toJson`/`fromJson` with `path`-prefixed errors, `==`/`hashCode` via
`package:collection`. No embedded JSON schema is added (the existing video
recording models ship without one).

### Session

| Model | Fields |
| --- | --- |
| `CockpitInteractionRecordingSession` | `sessionId`, `phase`, `startedAt`, `pausedAt?`, `endedAt?`, `stepCount`, `unresolvedCount` |
| `CockpitRecorderPhase` | enum: `idle`, `recording`, `paused`, `stopped` |
| `CockpitInteractionRecordingRequest` | `name?`, `attachToStep?` (mirrors `CockpitRecordingRequest` shape) |
| `CockpitInteractionRecordingResult` | `session`, `steps`, `export?` |

Phase transitions: `idle → recording ⇄ paused → stopped` (terminal). Any
command issued from an incompatible phase throws `StateError`, except
`stop` which is valid from `recording` and `paused`.

### Steps

`CockpitInteractionStep` is the unit of the timeline:

| Field | Type | Description |
| --- | --- | --- |
| `stepId` | `String` | Monotonic `s1`, `s2`, … |
| `kind` | enum | `tap`, `longPress`, `text`, `scroll`, `routeChange`, `back`, `marker`, `note` |
| `locatorCandidates` | `List<CockpitLocatorCandidate>` | Ordered, deduped; empty for `unresolved` steps |
| `resolvedValue` | `String?` | Final committed text (kind `text`) |
| `scrollDirection` | enum? | `up/down/left/right` (kind `scroll`) |
| `routeName` | `String?` | Route active when the step settled |
| `fromRouteName` | `String?` | Previous route (kind `routeChange`) |
| `positionDx`, `positionDy` | `double?` | Diagnostic only; never used for replay (`cockpit_protocol` is pure Dart — no `Offset`) |
| `phase` | enum | `idle/recording/paused` — session phase at capture |
| `unresolved` | `bool` | True when no target resolved (noise chrome) |
| `segments` | `List<String>` | Segment marks active at capture (`markSegment` labels) |
| `annotation` | `String?` | Free-text note (kind `note`, or attached) |
| `settledAfterMs` | `int?` | Measured quiet window after the action |
| `recordedAt` | `DateTime` | Wall clock, diagnostic |

`CockpitLocatorCandidate`: `kind` (`cockpitLocatorKind` value: `key`,
`semanticId`, `text`, `tooltip`, `type`), `selector` (canonical
`CockpitSelector.format` output), `score` (registry precedence 4/3/2/1/0).

### Flow bundle

`CockpitRecordedFlowBundle`: `session`, `steps`, `caseDocument`
(`Map<String, Object?>` from `CockpitTestCase.toJson`), `caseYaml` — the
single export artifact every surface produces identically.

## Engine (`flutter_cockpit`, `lib/src/recorder/`)

### Mount topology

`FlutterCockpitRootState.build` currently composes
`Stack[surface(child), tapFeedbackOverlay?]`. The recorder extends it:

```
Stack
 ├─ CockpitInteractionCapture(          // NEW, wraps the surface
 │    enabled: recorder.isActive,
 │    child: CockpitSurface(... RepaintBoundary(child: app) ...))
 ├─ CockpitTapFeedbackOverlay?          // existing
 └─ recorder HUD host?                  // NEW, outside capture & boundary
```

Consequences (all structural, not checks):

- The capture `Listener` (`HitTestBehavior.translucent`) is an ancestor of
  the app, so every app hit appears in its hit-test path.
- The HUD sits **beside** the capture subtree: taps on the HUD never enter
  the capture path (siblings above absorb the hit), and the HUD is outside
  the surface `RepaintBoundary`, so `FlutterViewCapture` never screenshots
  it. This reuses the exact mechanism that keeps the tap-feedback overlay
  out of evidence today.
- Third-party host chrome (a UME ball) lives **inside** the app tree, inside
  the capture subtree — handled by the exclusion pipeline below.

### Capture pipeline

1. **Pointer events.** `onPointerDown` records position; `onPointerUp`
   completes the gesture. Classification: displacement < 8 lp → `tap`;
   hold ≥ 500 ms → `longPress`; displacement ≥ 64 lp on a scrollable →
   `scroll` with direction. Constants live in one place
   (`CockpitInteractionCaptureDefaults`) and are injectable for tests.
2. **Hit resolution.** At pointer-down, `GestureBinding.hitTestInView`
   (precedent: `CockpitTargetHitTestInspector.inspect`) yields the render
   path. The path is matched against registered `CockpitTarget`s
   (`diagnosticNodeProvider` element ancestry), preferring
   `visibleTargets` on the current route. A matched target's signals build
   deduped locator candidates: `key` → `@key`, `semanticId` →
   `#id`, `text` → bare text, `tooltip` → `[tip=…]`, `type` → bare type
   segment — formatted with `CockpitSelector.format`.
   No match → step is recorded with `unresolved: true`.
3. **Exclusion (three tiers).**
   a. `CockpitRecorderExclude` marker widget: the capture layer drops any
      event whose hit path contains the marker's render object (checked via
      `RenderObject` ancestry walk).
   b. `CockpitRecorderExclusionRegistry`: programmatic registration of
      subtree roots (keys or render objects) — used by the default HUD for
      its expanded panel and documented for hosts whose chrome they cannot
      wrap.
   c. Semantic fallback: exclusion tiers a/b run first; anything that still
      resolves to no target becomes `unresolved` noise.
4. **Text capture.** A `FocusManager` listener tracks focus entering an
   `EditableText`; when focus leaves (or `TextInputAction` fires), the
   final controller value plus the field's locator candidates are recorded
   as one `text` step. Empty values are skipped.
5. **Route changes.** The binding's existing `currentRouteName`
   `ValueNotifier` emits `routeChange` steps (any route-name diff). `back`
   is a contract-level kind reserved for richer observers; capture v1
   classifies every route diff as `routeChange`.
6. **Settle marking.** After each action step, a short scheduler-quiet
   watch (reusing `waitForCockpitSchedulerQuiet` semantics, non-blocking,
   test-clock injectable) fills `settledAfterMs`. Steps are appended
   immediately; settle back-fills the record — the timeline never blocks.

### Session engine

`CockpitInteractionRecorder` (`ChangeNotifier`): owns the phase machine,
step list, and segment stack. Commands: `start(request)`, `pause()`,
`resume()`, `stop()`, `beginSegment(label)`, `endSegment()`,
`annotate(stepId, note)`, `discardLastStep()`, `export()`,
`verifyReplay()`. Segments are a stack: steps snapshot the currently open
segment labels; a segment named `setup` delimits the exported setup block.
Pause suppresses capture but keeps subscriptions warm. Only one interaction
recording session exists at a time per binding; `start` while active throws
`StateError`. `export()` and `verifyReplay()` are added with their
implementations (converter / replay phases) — the engine never carries
stubs.

Integration: `FlutterCockpitConfig` gains a `recorder` block
(`enabled`, `host: floatingBall | guest | headless`, defaults for capture
thresholds). `FlutterCockpitRoot` constructs the recorder when enabled and
mounts capture + HUD accordingly. Recording is functional in debug and
profile; `kReleaseMode` disables it unconditionally (config error to request
otherwise).

### Verify replay

`verifyReplay()` replays the recorded steps **in-process** through the
existing automation path: locator candidate #1 of each step is resolved via
the target registry and executed with `CockpitGestureEngine.perform`
(tap/longPress/scroll) or the command executor (`type`), with
`waitForUiIdle` between steps. Result: `CockpitReplayReport` with per-step
`passed | deviated(reason)` — deviations are selector-resolution failures
or post-action observation mismatches. Replay pauses capture (a replay must
not re-record itself) and restores the prior phase afterwards.

## Panel components and host abstraction (`flutter_cockpit`, `lib/src/recorder/ui/`)

The four public host surfaces (documented in the host integration guide):

```dart
// Engine enablement is config-driven (no separate bootstrap call):
// FlutterCockpitApp(config: ...copyWith(recorder: ...enabled), child: app)
final c = CockpitRecorderScope.of(context); // state + steps + commands
const CockpitRecorderPanel();           // full panel content widget
const CockpitRecorderEntryButton();     // entry icon for host panels
const CockpitRecorderIndicator();       // passive REC indicator
CockpitRecorderExclude(child: …);       // host chrome exclusion marker
```

- `CockpitRecorderController` (`ChangeNotifier`): view model over the
  engine — phase, step list, replay report, export bundle; all commands.
  Panels and custom hosts bind to it exclusively; nothing reaches the
  engine directly.
- `CockpitRecorderPanel`: full-screen layout — header (phase badge, live
  step/unresolved counters, close), context-primary control row (Start+name /
  Pause+Stop / Resume+Stop, segments as a compact secondary row), the timeline
  as the hero area (kind-colored rows, monospace locators, replay status badges
  joined per step, annotate, delete-last), and a bottom bar (verify replay,
  copy YAML, save via an injectable `CockpitRecorderExportGateway`; the
  default writes the YAML to a caller-supplied directory with `dart:io`;
  share-sheet affordances are the host's concern).
- Default host `CockpitRecorderHost`: compact 40×40 draggable floating ball with edge
  docking; expands into a panel sheet. Collapsed ball is a small REC
  indicator. Host mode `guest` mounts no entry (panel content only, for
  embedding in an existing floating window); `headless` mounts nothing.

## Converter (`cockpit_protocol`, `lib/src/recorder/`)

`CockpitRecordedFlowConverter` turns `List<CockpitInteractionStep>` into a
`CockpitTestCase` (built through the existing `lib/src/test/` templates so
the document is schema-valid by construction):

- `unresolved` steps are dropped.
- `tap`/`longPress`/`text`/`scroll` map to the corresponding action step
  with the primary locator; remaining candidates become the locator's
  `fallbacks` chain.
- A `scroll` step immediately preceding a `tap` whose target it revealed is
  folded into a scroll-then-tap prelude (the same pattern the handwritten
  integration tests use).
- `routeChange` → `waitForRoute`; `back` → back action; `marker` steps
  delimit `setup` (everything in the segment named `setup`, if marked) from
  `steps`.
- Weak assertions are auto-emitted after each action: `waitFor` visible of
  the *next* step's primary locator, and `waitForRoute` when the route
  changed. This gives every exported case replay-verifiable liveness without
  inventing semantics the recorder cannot know.
- Known interruption patterns (a native-plane observation between two
  steps, e.g. a permission dialog) export as a guard step: `if
  visible('Allow') then tap('Allow')` — an `if` with no `else`. The
  trigger data comes from native-plane observation capture, which lands
  with dual-plane capture support; until then the pattern table is empty
  and no guards are emitted (documented v1 limitation, not a stub).
- The converter never guesses branches beyond the known-pattern table; the
  document metadata records `origin: recorded` with the session id so
  consumers know a human/agent should strengthen assertions.

`CockpitTestDocumentYamlWriter` renders `CockpitTestCase.toJson` to YAML
(write-only; ~100 lines, no external dependency added to the protocol
package).

## External surfaces

### Remote endpoints (`flutter_cockpit/lib/src/remote/`)

Following the existing string-route pattern in
`CockpitRemoteSessionEndpointHandler.handle`:

| Route | Method | Body / Result |
| --- | --- | --- |
| `/recorder/start` | POST | `CockpitInteractionRecordingRequest` → session |
| `/recorder/pause` | POST | → session |
| `/recorder/resume` | POST | → session |
| `/recorder/stop` | POST | → `CockpitInteractionRecordingResult` |
| `/recorder/session` | GET | → session JSON; `{"phase":"idle"}` before the first start (204 was rejected: the handler only speaks JSON bodies) |
| `/recorder/steps` | GET | → `?after=<n>` cursor — client-driven (recorded steps are never cleared server-side); response `{"steps":[…], "total":<n>}`; `after > total` → 400 |
| `/recorder/export` | GET | → `CockpitRecordedFlowBundle` |

Injected as one optional `recorderProvider` constructor parameter (nullable;
404 when absent, mirroring how absent capabilities behave today).
`CockpitRemoteSessionClient` (packages/cockpit) gains matching methods.

### CLI (`cockpit`)

`cockpit record` command group under `CockpitCommandRunner`, following
`CockpitLeafCommand` conventions: `record start [--name]`, `record pause`,
`record resume`, `record stop`, `record status`, `record steps [--after]`,
`record export [--out <file>] [--output-format yaml|json]` — all resolving
their target through `session.development.get` exactly like the
`cockpit dev` commands (shared service:
`CockpitInteractionRecordingService`), output through
`runtime.success`/error envelopes. The format flag is `--output-format`
because every leaf already owns a global `--format` output-encoding option.

### MCP

`cockpitMcpDevelopmentTools` gains seven tools — `recorder_start`,
`recorder_pause`, `recorder_resume`, `recorder_stop`, `recorder_status`,
`recorder_steps`, `recorder_export` — wrapping the same shared service
(session resolution via `session.development.get`). They are disabled by
default (`isEnabledByDefault: false`, e2e + session-management categories);
`recorder_export` returns the case YAML in the response and never writes
files. An agent can drive a recording session end to end.

## Console (`cockpit_console`)

A recorder screen (implemented): binds to the console-wide session-monitor
selection (reusing the session picker), resolves the recorder endpoint
through the same `session.development.get` → base-uri path as CLI/MCP, and
provides controls (phase matrix + optional recording name), a live timeline
(cursor polling), and an export pane (YAML preview, copy, save via the
console's established `FilePicker.saveFile` flow). Strings are localized
(en + zh-CN) through the slang workflow.

## Testing strategy

| Layer | Tests |
| --- | --- |
| Protocol models | Round-trip `toJson`/`fromJson`, phase-machine legality, candidate ordering/dedupe, converter rules (one file per rule family), YAML writer golden tests |
| Capture | `testWidgets` with `FlutterCockpitApp`: `tester.tapAt` drives real hit-tested events through the capture layer; marker/registry exclusion; unresolved classification; text/route/scroll classification with injected thresholds and fake clocks |
| Engine | Phase transitions incl. illegal ones; pause suppression; segment stack; discard; single-session guard |
| Panel | Widget tests per area; controller bindings; guest/headless modes mount nothing |
| Verify replay | Recorded steps replayed against the demo app in `testWidgets`; deviation reporting on a broken selector |
| Remote | Handler route table incl. absent-provider 404s; client methods against a local `HttpServer` (existing pattern) |
| CLI / MCP | Output envelope and args tests mirroring existing command tests |
| E2E proof | `flutter_cockpit` widget test drives a full record → stop → export cycle on a Material app and asserts the bundle; a `packages/cockpit` test feeds realistic recorded steps through the converter and asserts the emitted YAML compiles via `CockpitTestDocumentCompiler` (the compiler lives in `cockpit`, so the schema-validity proof lives there) |

## Release

Lockstep version bump to `4.12.0` across workspace packages (manual, per
convention), CHANGELOG entries per package, host integration guide at
`docs/recorder/host-integration.md`, and the `flutter_cockpit` README gains
a recorder section.
