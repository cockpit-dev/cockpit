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

For each coherent edit:

1. Inspect only the state needed for the change.
2. Edit and run focused analysis.
3. Run `cockpit dev reload`.
4. Perform the exact UI action.
5. Run `cockpit dev wait`, then inspect current UI and diagnostics.
6. Capture a screenshot only for a visible claim.

Prefer `minimal`; use `standard` for diagnosis and `full` only when the entire
semantic object is required. Do not relaunch while reload and the authenticated
bridge remain healthy.

## Mixed-Stack Boundaries

Stay on Flutter semantic control for widgets, routes, focus, editing, scrolling,
logs, runtime errors, HTTP activity, and reload/restart. Screenshot routing is
platform-aware: Android/iOS use system capture first; desktop/web use Flutter
view capture first. Switch control to an advertised native/system plane only for:

- permissions and OS dialogs;
- notifications and system UI;
- platform views or WebViews without Flutter semantics;
- a native desktop shell outside the Flutter view;
- installed applications without the development bridge.

Re-inspect after crossing a boundary. A native action is complete only after a
Flutter or native observable postcondition proves the result. Do not use host
accessibility automation to resize a Flutter development window; use
`cockpit dev viewport`.

For an installed black-box application, use discovery and target registration
from live `--help`; those workflows require explicit platform ownership and are
not allowed to make a development session from another checkout implicit.

## Recovery

Keep using the same numeric handle. Cockpit reconciles workspace, target, app, bridge,
port, and runtime session internally.

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
cockpit dev diagnose --verbosity standard
cockpit dev restart
```

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

Run commands from inside the intended checkout. Cockpit derives a canonical
identity from the checkout root and, for Git, the worktree-specific Git
directory. Each checkout owns separate:

- active numeric handle selection;
- workspace worker and target/app/session mapping;
- process and port ownership;
- mutation sequence and network state;
- artifact paths.

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
