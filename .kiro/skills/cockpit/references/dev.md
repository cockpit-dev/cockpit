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

Start once inside the checkout, then reuse the active handle:

```bash
cockpit dev start
cockpit dev status
```

Use `cockpit session list` for an immediate local index. It performs no daemon,
worker, Flutter attach, reconnect, or app launch work; `state` is only the
last saved state. Use `cockpit session show HANDLE` when live reachability is
actually required.

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

## Mixed-Stack Boundaries

Stay on Flutter in-app control for widgets, routes, focus, editing, scrolling,
logs, runtime errors, HTTP activity, and reload/restart. Screenshot routing is
platform-aware: Android/iOS use system capture first; desktop/web use Flutter
view capture first. Switch control to an advertised native/system plane only for:

- permissions and OS dialogs;
- notifications and system UI;
- platform views or WebViews without Flutter semantics;
- a native desktop shell outside the Flutter view;
- installed applications without the development bridge.

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

Keep using the same numeric handle while Cockpit reconciles the workspace, target,
app, bridge, port, and runtime session.

| State | Read command | Mutation command |
| --- | --- | --- |
| Healthy | Read current state | Execute normally |
| Port or bridge changed | Authenticated reconnect | Reconnect, then execute |
| Unexpected process exit | Report crashed | Relaunch once from the stored non-secret launch configuration |
| Intentionally stopped | Report stopped | Require `cockpit dev start` or `restart` |
| Ownership mismatch | Fail without adoption | Fail without signaling or launching the candidate |

Use:

```bash
cockpit dev status
cockpit dev diagnose --view more
cockpit dev restart
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
| Incidental Flutter dialog/sheet/banner/upgrade notice | Prefer an explicit neutral action such as Later, Not now, Skip, Cancel, or Close; otherwise use `cockpit dev dismiss` only when inspection proves the overlay is dismissible. |
| Unintended temporary route | Use `cockpit dev back` once only when current state proves the parent route is the intended destination. |
| Android/iOS system capture shows OS dialog, keyboard, or system UI | Require `system.action`; run `resolveBlockers` with `decision:dismiss` for an incidental blocker. Accept only when the scenario requires that exact decision. |
| Runtime exception or failed request | Read standard diagnostics, fix the cause, then hot reload and prove the expected anchor. |
| App crashed or stopped unexpectedly | Use `cockpit dev start` to reconcile and relaunch the owned app under the same handle. |
| Port/bridge changed | Use `cockpit dev start` to reconnect the owned app; do not create another session. |

Discover the native action before using it; live availability and schema remain
authoritative:

```bash
cockpit op list --kind system.action
cockpit explain system.action
cockpit op run system.action --input '{action:resolveBlockers parameters:{decision:dismiss}}'
```

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
recovery never reads a keychain or secret store. Values passed through `--env`
are not persisted; restart explicitly when those values are required.

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
placement is impossible. Add an explicit scroll-container locator only to override
automatic selection after diagnostics prove it is necessary.

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

Run commands from inside the intended Flutter project. Cockpit combines its
canonical project path with the checkout identity derived from the checkout root
and, for Git, the worktree-specific Git directory. Each project owns its active
handle, while checkout identity keeps every runtime resource isolated:

- project-scoped active numeric handle selection;
- workspace worker and target/app/session mapping;
- process and port ownership;
- mutation sequence and network state;
- artifact paths.

One monorepo may therefore run several Flutter projects without cross-selecting
sessions. A command from a common ancestor resolves one active descendant project;
if several match, it fails as ambiguous and requires running inside the project or
passing `--session HANDLE`.

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
