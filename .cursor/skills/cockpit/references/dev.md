# Development Workflows

Use this reference for mixed Flutter/native boundaries, recovery decisions,
timeouts, and parallel checkout isolation. Use `cockpit dev` directly for the
normal Flutter loop.

## Contents

- [Fast loop](#fast-loop)
- [Mixed-stack boundaries](#mixed-stack-boundaries)
- [Recovery](#recovery)
- [Locators](#locators)
- [Timeouts](#timeouts)
- [Parallel projects](#parallel-projects)
- [Advanced operations](#advanced-operations)

## Fast Loop

Start once inside the intended Flutter project, then reuse the active handle:

```bash
cockpit dev start
cockpit dev status
```

Use `cockpit session list` for an immediate local index. It performs no daemon,
worker, Flutter attach, reconnect, or app launch work; `last` is only the
last saved state. Use `cockpit session show HANDLE` when live reachability is
actually required. Use `cockpit dev use HANDLE` only for a persistent selection
change. Explicit `--session HANDLE` and a returned recovery `next` stay scoped to
that exact handle without changing the saved active selection.

Interactive `dev start` prints bounded launch stages to stderr so a Flutter build
does not look frozen. Machine-readable stdout remains a single clean projection;
non-interactive and redirected runs emit no progress, and `--format none` is fully
silent. The stages correspond to real launch boundaries.

For each coherent edit:

1. Inspect only the state needed for the change.
2. Edit and run focused analysis.
3. Run `cockpit dev reload`.
4. Perform the exact UI action.
5. Run `cockpit dev wait`, then inspect current UI and diagnostics.
6. Capture a screenshot only for a visible claim.

Prefer `brief`; use `more` for diagnosis and `full` only when the entire
response is required. Do not relaunch while reload and the authenticated
bridge remain healthy.

Hot reload begins a new runtime-diagnostic generation. Errors captured before
the reload no longer fail current diagnosis or evidence; errors raised after it
remain visible and disqualifying.

## Mixed-Stack Boundaries

Stay on Flutter in-app control for widgets, routes, focus, editing, scrolling,
logs, runtime errors, HTTP activity, and reload/restart. Screenshot routing is
platform-aware: Android/iOS use system capture first; desktop/web use Flutter
view capture first. Switch to an advertised native driver or system action only for:

- permissions and OS dialogs;
- notifications and system UI;
- platform views or WebViews without Flutter semantics;
- a native desktop shell outside the Flutter view;
- installed applications without the development bridge.

Open a deep link, Android app link, iOS universal link, or ordinary URL through
the current target without constructing a generic operation payload:

```bash
cockpit dev open "myapp://tasks/42"
cockpit dev wait
cockpit dev inspect "EXPECTED_ANCHOR"
```

`dev open` dispatches through the selected session's platform adapter. A zero
exit proves the OS accepted the URI; the focused app and expected route remain
the required postcondition. If another application owns the URI, observe that
state instead of forcing Cockpit back to the original app.

Flutter in-app control walks the mounted Element/RenderObject tree and does not
require application-authored Semantics. Use `dev inspect QUERY` for bounded target
discovery. Use `dev tree` only for structural ambiguity; full output is path-based.

Re-inspect after crossing a boundary. A native action is complete only after a
Flutter or native observable postcondition proves the result. Do not use host
accessibility automation to resize a Flutter development window; use
`cockpit dev viewport`.

For an installed black-box application, use discovery and target registration
from live `--help`; those workflows require explicit platform ownership and are
not allowed to make a development session from another checkout implicit.

## Recovery

Keep using the same short base-36 handle while Cockpit reconciles the workspace,
target, app, bridge, port, and runtime session.

| State | Read command | Mutation command |
| --- | --- | --- |
| Healthy | Read current state | Execute normally |
| Port or bridge changed | Authenticated reconnect | Reconnect, then execute |
| Unexpected process exit | Report crashed | Relaunch once only when no custom launch values were used; otherwise require `dev start` with the original options |
| Intentionally stopped | Report stopped | Require `cockpit dev start` |
| Ownership mismatch | Fail without adoption | Fail without signaling or launching the candidate |

Use:

```bash
cockpit dev status
cockpit dev diagnose --view more
cockpit dev start
```

### Unexpected UI Or Flow Drift

A missing locator or failed assertion often means the UI changed, not that Cockpit
should retry the same input. Preserve the original expected postcondition and use a
bounded observe-decide-prove loop:

1. Read `cockpit dev status` without mutating the app.
2. Capture `cockpit dev screenshot --view more`; inspect the returned path
   with the host's local image tool when available. The reported source distinguishes
   an Android/iOS system screen from the Flutter view.
3. Run `cockpit dev inspect` for the mounted Flutter state. Use a focused query when
   the screenshot exposes a likely label. Use `dev tree` only for structural ambiguity.
4. If the screen identity is unclear, inspect the handle returned by status with
   `cockpit session show HANDLE`. Select the intended session before any mutation.
5. Run one recovery from the table below.
6. Run `cockpit dev wait`, inspect the original expected anchor, capture current evidence,
   then resume the interrupted action once.

| Observed state | Recovery |
| --- | --- |
| Original expected anchor is already present after a timeout | Treat the mutation as committed and continue; do not repeat it. |
| Screen belongs to another app, checkout, or target | Select the correct session; do not mutate, restart, or stop the observed app. |
| Transient non-interactive animation, toast, or loading state | Run `cockpit dev wait` once, then re-observe instead of tapping or dismissing it. |
| Expected product prompt | Execute its explicit expected action with an exact locator. |
| Incidental Flutter menu/popup/dialog/sheet/banner/upgrade notice | Prefer an explicit neutral action such as Later, Not now, Skip, Cancel, or Close. For a menu, popup, or other overlay with no state-changing action to select, use `cockpit dev dismiss`. |
| Unintended temporary route | Use `cockpit dev back` once only when current state proves the parent route is the intended destination. |
| Android/iOS system capture shows OS dialog, keyboard, or system UI | Run `cockpit dev recover` for the exact session. Use `--dialog accept` or `--keyboard` only when the scenario or capture proves it is required. |
| macOS recovery reports `macosSessionLocked` | Unlock the desktop, then retry the same session once. Do not request Accessibility permission or relaunch the app. |
| Runtime exception or failed request | Read standard diagnostics, fix the cause, then hot reload and prove the expected anchor. |
| App crashed or stopped unexpectedly | Use `cockpit dev start` to reconcile and relaunch the owned app under the same handle. |
| App is live while the bridge reconnects | Follow the exact `next` command from status, normally `cockpit dev recover --session HANDLE`; do not relaunch or create another session. |

Use the task command for routine recovery:

```bash
cockpit dev recover
cockpit dev recover --dialog dismiss
cockpit dev recover --dialog accept
cockpit dev recover --keyboard
```

`dev recover` owns the advertised `resolveBlockers` operation. Use the short
task command instead of constructing a generic operation payload. Omit
`--dialog` for focus-only recovery; add it only for a proven native dialog.

Unknown prompts default to the safe negative/neutral path. Never generically accept
upgrades, installations, permissions, authentication, payments, deletion, or external
navigation. Do not chain speculative taps, repeated Back presses, dismiss loops, or
restart loops. Do not clear app data, reinstall the app, reset a simulator/emulator,
kill unrelated processes, or create a second session as generic recovery. If one
targeted recovery does not change the state, collect standard diagnostics and fix the
application or environment cause. A missing native capability is `unavailable` or
`blocked`, not permission to simulate success.

Never recover by package name, working directory, or port alone. A reconnect
must remain bound to the same canonical checkout identity and target. Launch
recovery never reads a keychain or secret store. Custom Flutter launch values
are not persisted; after an exit, rerun `cockpit dev start --session HANDLE`
with the original options.

## Locators

Prefer, in order:

1. a stable Cockpit ID;
2. exact visible text or accessibility label;
3. a relationship plus state;
4. explicit contains/fuzzy matching;
5. an index only for a real ordered list.

Exact text is the default. Ambiguity is a failure, not permission to choose the
first match. Inspect candidates and strengthen the locator. Re-anchor after any
insertion, deletion, reorder, filter, dialog, sheet, or keyboard transition.

Scroll the target directly; Cockpit discovers and ranks containers without requiring
a container locator. It searches each candidate in both directions with independent
budgets, then reveals mounted nested ancestors from inner to outer and verifies the
target is fully inside every viewport. Use explicit placement only when the result
needs it:

```bash
cockpit dev scroll "Save"
cockpit dev scroll "Save" --align center --offset 12
```

Alignment is `nearest|start|center|end`. Positive offset moves toward the viewport
end; negative offset moves toward its start. Legal scroll extents win when an exact
placement is impossible. `nearest` keeps a fully visible, hittable target in place;
if a fixed Flutter overlay wins the hit test and scrolling can avoid it, Cockpit moves
the target to the viewport center. `--direction up|down` selects the initial search
direction only; reaching that boundary automatically starts a search in the opposite
direction. Cockpit owns scroll-container discovery; when a target is ambiguous,
strengthen the target selector with a real ancestor or identity instead of inventing
a container option.

For input that must behave like a physical mouse wheel or trackpad, use
`dev wheel` instead of a drag-based scroll:

```bash
cockpit dev wheel "List" --dy 120
cockpit dev wheel "List" --dy 120 --steps 3 --interval 40ms --device trackpad
```

Each step dispatches one real `PointerScrollEvent` at the target. `--dx` and
`--dy` are per-event logical-pixel deltas; `--steps` repeats the signal and
`--interval` spaces repeated signals. Use `--device trackpad` only when the
widget distinguishes device kind; mouse is the default. Cockpit advertises this
capability for `Scrollable`, a custom `Listener(onPointerSignal: ...)`, and
trackpad-aware `InteractiveViewer`. A source-known custom widget can be located
without a Key or Semantics label. Use `--at X,Y` only when no mounted target
owns the signal.

## Gestures and change observation

The Flutter development bridge exposes real pointer gestures in addition to tap,
hold, and double-tap:

`tap`, `hover`, `hold`, and `double` accept either a mounted selector or an
explicit `--at X,Y` point. Omit the selector only for the deliberate coordinate
fallback; coordinates are logical Flutter viewport pixels. Prefer source-derived
selectors or the `sel` returned by `dev inspect` whenever the target is
discoverable, because selectors remain stable across layout changes.

```bash
cockpit dev tap --at 320,640 --device mouse
cockpit dev hover --at 480,96
cockpit dev hold --at 320,640 --duration 900ms
cockpit dev double --at 320,640 --interval 120ms
cockpit dev drag "Canvas" --dx 120 --dy 0
cockpit dev fling "List" --dx 0 --dy -400 --velocity 1600
cockpit dev swipe "List" up
cockpit dev pinch "Map" 1.5
cockpit dev rotate "Canvas" 1.5708
cockpit dev pan "Canvas" --dx 80 --dy 20
cockpit dev multi "Canvas" --sequence-file /absolute/gesture.yaml
cockpit dev wheel "List" --dy 120 --steps 3 --device trackpad
```

Use `hold TARGET --duration 900ms` when the press duration is part of the
behavior under test; `--timeout` remains the outer command budget. Use
`double TARGET --interval 120ms` only when the inter-tap timing matters.
`drag`, `fling`, and `pan` use logical-pixel deltas. `swipe` uses a normalized
distance (`0.15..0.95`), `pinch` uses a scale different from 1, and `rotate`
uses radians. `multi` accepts LON, JSON, or YAML with a `steps` array containing
`pointer`, `phase` (`down|move|up`), `atMs`, `dx`, and `dy`. Every pointer must
end with `up`; failed sequences are cancelled so no pointer leaks into the next
command. Keep the same `--session` for concurrent apps.

Use `dev wait` for the final animation/settle proof. To inspect the animation or
any continuously changing page without flooding stdout, use bounded incremental
sampling:

```bash
cockpit dev watch "Loading" --for 5s --every 200ms
cockpit dev watch --for 10s --quiet 800ms
```

`dev watch` returns sample count, compact route, target, control-state, and
layout change events plus an `endedBy` reason
(`duration`, `timeout`, `quiet`, `eventLimit`, or `error`). It compares route and mounted
target identity, text, control state, and layout; full snapshots and screenshots
remain explicit follow-up reads. A changed page is reported as deltas, not
repeated trees. Use a current screenshot or focused `dev inspect` after a change
when visual or exact locator evidence is required.

Before delivery, select the smallest proofs required by the feature instead of
running every category blindly:

- pointer timing: hold, double, drag-after-hold, fling, pinch, rotate, and an
  explicit multi-pointer sequence;
- temporal UI: start/intermediate/end checkpoints, bounded `watch`, then final
  UI idle;
- changing data: polling counters, timers, SSE/WebSocket state, pagination,
  refresh, and unfinished network responses;
- boundaries: nested scrolling, keyboard/focus, Flutter overlays, proven system
  dialogs, back/deep links, viewport changes, and foreground recovery;
- isolation: the exact session for concurrent projects, targets, and platforms;
- resilience: one evidence-matched recovery after a timeout, disconnect, route
  mismatch, or unexpected overlay, followed by the original postcondition.

For a visible claim, take one current screenshot after the terminal state. For
an animation-specific visual claim, capture only named checkpoints; do not emit
or retain every frame.

## Timeouts

- Use the command default first.
- Increase launch timeout only for a measured slow build.
- Keep UI action, idle, network quiet, build, and outer workflow budgets
  independent.
- Do not add sleeps. Use `cockpit dev wait` and a bounded timeout.
- On mutation timeout or disconnect, inspect current state before retrying; the
  action may already have committed.
- Polling applications should use UI-only wait. Add `--network` only when the
  assertion depends on network completion.

Unsupported capability is an unavailable result. Use only alternatives named
by the live capability response.

## Parallel Projects

Run commands anywhere inside the intended Flutter project. Cockpit resolves the
nearest enclosing Flutter package and combines its canonical project path with
the checkout identity derived from the checkout root and, for Git, the
worktree-specific Git directory. Each project owns its active handle, while
checkout identity keeps every runtime resource isolated:

- project-scoped active short base-36 handle selection;
- workspace worker and target/app/session mapping;
- process and port ownership;
- mutation sequence and network state;
- artifact paths.

One monorepo may therefore run several Flutter projects without cross-selecting
sessions. Nested projects and nested worktree directories are resolved to their
nearest package boundary and never mixed with a neighboring checkout. A command
from a common ancestor with several active projects still requires entering the
intended project or passing `--session HANDLE`. Generic capability recovery must
use that same handle
for `op list`, `explain`, and `op run` so all three resolve one workspace and app.

Different worktrees of one repository may run concurrently and must remain
isolated even when they share a Git common directory and package name. Do not
copy session state, reuse artifact paths, or make a handle from another
checkout implicit.

## Advanced Operations

Use a generic operation only when no task command covers an advertised capability:

```bash
cockpit explain surface.inspect
cockpit op run surface.inspect --input '{}'
```

Trust the resolved live schema, precision, defaults, effects, scope, and
timeouts. Do not invent fields when precision is `generic`; prefer a task
command or the target-specific documented workflow. Keep non-trivial input in
an absolute-path file, and never put secrets in command output or generated
test documents.
