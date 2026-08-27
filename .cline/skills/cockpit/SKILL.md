---
name: cockpit
description: Use only when the user explicitly asks to use Cockpit, invokes a Cockpit command or skill, or asks to install, configure, develop, debug, inspect, or verify Cockpit itself; do not activate for generic app, Flutter, UI, or E2E work.
---

# Cockpit

## Activation Boundary

Cockpit is opt-in. Activate this Skill only after an explicit user request to
use Cockpit or to work on Cockpit itself. A generic request about app
development, Flutter, UI, debugging, screenshots, mobile, desktop, browser, or
E2E does not activate it. Before activation, do not invoke Cockpit commands,
inspect sessions or targets, start or stop a daemon or app, load Cockpit MCP
resources, or suggest a Cockpit workflow. Do not carry Cockpit into an unrelated
later task unless the user explicitly activates it again.

`cockpit dev` owns Flutter discovery, processes, ports, and Supervisor state.
Development handles are short lowercase base-36 values (`1` through `9`, then
`a`, `b`, ...). Copy other generated IDs exactly; never replace them with paths.
Use the globally installed `cockpit` executable everywhere. Live capabilities
are authoritative.

## Flutter Preflight

Before running any `cockpit dev` command in a Flutter source checkout, first
confirm that its development-only Cockpit shell is integrated. A normal Flutter
app does not expose a Cockpit bridge by itself, so `dev start` rejects it during
bridge-shell preflight before launching Flutter.

Check `cockpit/pubspec.yaml` and `cockpit/main.dart`. The non-published shell
package must keep the production package graph untouched, depend on the real
application locally by path or Pub workspace constraint, resolve
`flutter_cockpit` as a development dependency, wrap the real application root
in `FlutterCockpitApp`, and install the Cockpit navigator observer for every
Navigator the app owns. Run `flutter pub get` in the package-resolution root
after changing dependencies. If any part is absent or does not match the app's
actual public bootstrap/router API, read and complete
[flutter.md](references/flutter.md) before `cockpit dev start`.

Only an already integrated checkout takes the fast path below. `cockpit/main.dart`
is the default development entrypoint; pass another entrypoint only when the
checkout intentionally uses one.

## Choose The Command

Use the highest-level command that owns the task:

| Need | Command |
| --- | --- |
| Install or refresh the current AI host integration | `cockpit skill` |
| Check for a newer CLI release without changing anything | `cockpit update --check` |
| Update the installed CLI and running Supervisor | `cockpit update` |
| Start, inspect, control, debug, resize, capture, or reload Flutter | `cockpit dev` |
| Validate or run reusable Flutter/black-box tests | `cockpit case` / `cockpit suite` |
| Read a durable run, event stream, report, or artifact | `cockpit run` / `cockpit artifact` |
| Confirm session identity, checkout, entrypoint, or reachability | `cockpit session` |
| Discover one generic live capability | `cockpit op list --kind KIND` |
| Learn an operation schema and its safer task command | `cockpit explain KIND` |
| Execute an advertised operation without a task command | `cockpit op run KIND` |

Use `dev` for normal Flutter work; it resolves the required project resources.
`case` runs one journey, `suite` runs a durable campaign, and `op` executes an
advertised operation that has no task command.

## Flutter Fast Path

Start once inside the intended Flutter project, specifying only real launch
choices. From a monorepo common ancestor, pass the entrypoint explicitly:

```bash
cockpit dev start
cockpit dev start --platform macos
cockpit dev start --device emulator-5554
cockpit dev start --flavor staging --dart-define API_URL=https://example.test
```

Normal loop:

```bash
cockpit dev status
cockpit dev inspect "Documents"
cockpit dev tree
cockpit dev tap "Documents"
cockpit dev type "hello" --into "Message"
cockpit dev press enter
cockpit dev scroll "Operations"
cockpit dev open "myapp://tasks/42"
cockpit dev wait
cockpit dev viewport 800x600
cockpit dev screenshot
cockpit dev reload
cockpit dev restart
cockpit dev diagnose
cockpit dev stop
```

When the route and every action are already known, join the commands in one shell
call with `&&` to remove repeated Agent/tool round trips while keeping every default
LON result visible:

```bash
cockpit dev tap '@open-settings' &&
cockpit dev tap '@open-profile' &&
cockpit dev type "Iota" --into '@name' &&
cockpit dev tap '@save' &&
cockpit dev inspect "Saved"
```

`&&` preserves order and stops at the first failed command. Never use a single `&`:
it runs commands concurrently and can reorder UI mutations. End the chain with the
smallest read that proves the final state. If an intermediate result determines the
next route, locator, prompt action, or network-dependent branch, stop the chain at
that decision and observe before continuing. In a project with concurrent handles,
pass the same explicit `--session HANDLE` to every command in the chain.

After an edit, use the smallest proof loop: focused analyzer/test, `dev reload`,
the exact interaction, `dev wait`, a focused `dev inspect`, then a current screenshot
for visible claims. Use `restart` only when reload cannot apply the change. Do not
start a second app to recover a healthy session, and never restart or stop sessions
other than the selected handle.

`dev reload` starts a fresh runtime-diagnostic generation. Runtime errors from the
previous generation no longer fail current diagnosis or evidence, while any error
raised after the reload remains visible and disqualifying.

Use `dev open URI` for a custom-scheme deep link, Android app link, iOS
universal link, or ordinary HTTP(S) URL. It targets the selected session's
platform and does not print the URI. After opening, run `dev wait` and inspect
the expected route or anchor; command success proves platform dispatch, not
application routing.

On a human terminal, `dev start` reports its real launch stages on stderr while
Flutter builds and the bridge becomes ready. Structured stdout remains clean;
Agent/CI or redirected runs stay quiet, and `--format none` suppresses progress.
Do not add polling, sleeps, or verbose flags just to prove that launch is active.

Reads never relaunch stopped apps. Mutations may recover one owned crash. Use
`cockpit dev start` to explicitly relaunch a stopped or crashed app. Bridge and
port changes keep the existing handle.

## Unexpected-State Recovery

Treat a missing target, failed postcondition, wait timeout, unexpected route or
overlay, changed screenshot, and disconnect as a state change. Do not repeat the
failed action blindly. Preserve the intended postcondition and the same session
handle, then observe the current state once:

```bash
cockpit dev status
cockpit dev screenshot --view more
cockpit dev inspect
```

Inspect the returned screenshot path with the host's local image tool when
available. On Android/iOS, a system-sourced capture may reveal an OS prompt that
cannot appear in the Flutter tree. Use `cockpit dev diagnose --view more`
only when status, screenshot, and bounded inspection do not explain the blocker.
If status returns `developmentTargetUnavailable`, do not poll status: run its
`next`, normally `cockpit target discover`, and restore or select the intended
device before reusing the same session handle.

If a timed-out mutation already produced the expected anchor, treat it as committed
and continue without repeating it. If the screen does not belong to the intended app,
project, or target, inspect the handle returned by status with `cockpit session show
HANDLE` and select the correct session before any mutation; never repair the wrong app.

Apply exactly one matching recovery:

- For a transient, non-interactive animation, toast, or loading state, run
  `cockpit dev wait` once and re-observe; do not tap or dismiss it speculatively.
- For an expected prompt, perform the scenario's explicit action with an exact
  locator.
- For an unexpected Flutter dialog, sheet, banner, or upgrade notice, prefer its
  explicit safe action such as Later, Not now, Skip, Cancel, or Close. For a menu,
  popup, or other dismissible Flutter overlay that has no state-changing action to
  select, run `cockpit dev dismiss`.
- For an unintended child route, run `cockpit dev back` once only when the current
  state proves that returning is correct.
- When a system-sourced capture proves that the keyboard, system UI, or an OS dialog
  blocks the app, use the selected development session's recovery command. It is a
  safe no-op when the app already has focus. Incidental blockers default to dismiss;
  accept only when the scenario explicitly requires it, and request keyboard
  dismissal only when the capture proves the keyboard is the blocker:

  ```bash
  cockpit dev recover
  cockpit dev recover --dialog dismiss
  cockpit dev recover --dialog accept
  cockpit dev recover --keyboard
  ```
  This task command owns the advertised `resolveBlockers` operation; do not
  build a generic `op run` payload for routine recovery. Omit `--dialog` for
  permission-free focus recovery; add it only when a native dialog is proven.
  On macOS, `macosSessionLocked` means the login window or screen saver owns
  the foreground. Unlock the desktop and retry the same session once; do not
  grant Accessibility permission, restart the app, or create another session.
  From a common ancestor with several active Flutter projects, append the exact
  `--session HANDLE`; never recover an implicitly selected neighboring app.
- For a runtime exception or failed request, diagnose and fix the cause, then use
  `cockpit dev reload`. For a stopped or crashed owned app, use `cockpit dev start`
  so Cockpit reconciles the existing handle; never launch a second app as recovery.

Do not generically accept an upgrade, installation, permission, sign-in, payment,
deletion, or external navigation. Do not loop taps, dismissals, Back, reload, or
restart. Do not clear app data, reinstall the app, reset a simulator/emulator, kill
unrelated processes, or create a second session as generic recovery. If the same
blocker survives one targeted recovery, collect standard diagnostics and fix the app
or environment cause instead of trying random actions. After any mutation timeout,
read status and inspect the expected anchor before retrying because it may have committed.

Prove recovery before resuming the original flow:

```bash
cockpit dev wait
cockpit dev inspect "EXPECTED_ANCHOR"
cockpit dev screenshot
```

Resume the original action once only after the expected anchor is present. Re-read
[dev.md](references/dev.md) when the blocker crosses Flutter/native boundaries or
the same state returns.

## Sessions And Isolation

The short handle is the only routine session selector. Cockpit stores one active
handle per canonical Flutter project, guarded by checkout identity. Commands run
inside that project reuse it automatically. One checkout may contain many Flutter
projects, and one project may keep concurrent platform or target handles. `cockpit
dev use HANDLE` changes the active selection for that handle's project. The selection persists.
An explicit `--session HANDLE` selects exactly one command and never changes the
saved active selection. A session-bound `next` command keeps that exact handle;
execute it as returned instead of dropping `--session`.

```bash
cockpit session list
cockpit session show 1
cockpit dev use 2
cockpit dev status --session 2
```

`session show` reports the Flutter project, entrypoint, platform/device,
lifecycle, and current live state. Add `--view more` when canonical workspace,
checkout, target, or runtime IDs are needed. Check it before a destructive
mutation when concurrent apps look similar. Omitting `--session` is safe
when running inside the intended project and its active handle is the intended
target. Read readiness as two independent signals: `appLive:true` with
`bridgeLive:false` means the application still runs but its control bridge is
blocked or reconnecting. Never run `dev start` for that state; follow `next`, normally
`cockpit dev recover --session HANDLE`, then read status once. Only an explicit stopped
or crashed state with `appLive:false` justifies `dev start`.
With concurrent targets for that project, select once with `dev use`, or
pass `--session HANDLE` on the exact command. From a common ancestor containing
multiple active projects, Cockpit fails as ambiguous instead of guessing.

`session list` is a fast, side-effect-free local index: it never starts a worker,
attaches Flutter, reconnects, or relaunches an app. Its `state` is the last saved
state, not a live probe. Use `session show HANDLE` or `dev status --session HANDLE`
only when current reachability is needed.

Never register roots, targets, apps, ports, or runtime sessions manually for the
fast path. If a session is unreachable, inspect `status` or `diagnose`; `dev start`
reconciles the owned target and preserves the local handle when recovery is safe.
Reads do not relaunch an intentionally stopped app. A timed-out request cancels that
request, not the owned app; check `dev status` before retrying. Cockpit does not read a
keychain or secret store. `--env` values are process-only and are not persisted.

For black-box platform targets, use only capabilities returned by `target inspect`.
Android uses ADB/UiAutomator, iOS uses simctl or target-scoped WDA, macOS uses
Accessibility, Windows uses UI Automation, and Linux probes AT-SPI. Flutter Web
keeps the in-app Flutter tree. A generic Chromium page needs an explicit target
`--cdp-url`; Cockpit never scans a default port or attaches to another browser
profile. Read [environments.md](references/environments.md) before registering a
browser page or repairing a blocked platform driver.

Use `cockpit update --check` for a side-effect-free release check. Use `cockpit
update` for normal upgrades; it updates the CLI and Supervisor while preserving
authorization and durable state. Then run `cockpit skill` and give its prompt to
the current AI host so the complete Skill, native adapter, and MCP integration can
be refreshed. Do not manually delete Cockpit home data, Pub caches, sessions,
executables, or ports.

`cockpit daemon start` and an unflagged
`daemon restart` preserve the authorization of a healthy running daemon; with no
running daemon they start restricted. Add `--yolo` only to explicitly require yolo.
To return to restricted, stop the daemon and start it without `--yolo`. Lifecycle
lock waits consume the command's own timeout instead of blocking indefinitely.

## Timeout Defaults

Every executable command has `--timeout VALUE`; values accept `ms`, `s`, `m`, or `h`.
Use the default first and override only a measured slow operation. Common defaults:

| Command | Default |
| --- | ---: |
| `dev start` | `20m` |
| `dev status`, inspect, tree, direct UI actions, open, viewport, screenshot, diagnose | `1m` |
| `dev wait` | `30s` |
| `dev network`, recover, reload, stop | `2m` |
| `dev scroll` | `3m` |
| `dev restart` | `5m` |
| `target discover` | `2m` |
| case/suite validation | `1m` |
| `case run` | `30m` (maximum `6h`) |
| `suite run` | `2h` (maximum `24h`) |

Do not add sleeps around Cockpit. `dev wait` waits for UI quiet; add `--network` only
when the assertion depends on network completion. Its `--quiet` option changes the
settle window, not response view. After a mutation timeout, inspect state before
retrying because the mutation may already have committed.

## UI And Evidence

Execute exact text directly only when that text names the intended actionable
target, or use a stable locator. Do not add a pre-inspect round trip merely to
confirm an already-known action. If an action returns `unsupportedCapability`,
`ambiguousTarget`, `targetNotFound`, or `targetNotHittable`, do not guess that a
nearby control owns passive text. Run the exact `next` command once. A failed
stable selector performs a bounded inspect of the same query; an expired live
target ref refreshes the current control surface. Copy the returned actionable
`sel` and retry the original action once. If bounded inspect returns `count:0`,
use its current `route` and default bounded `mounted` targets to identify a wrong
route or visible blocker;
do not repeat the missing locator or load a full tree. Capture the current screen
only when those mounted targets do not explain the state.

For a first-party Flutter checkout, source is the default locator channel during
development, not an inspect fallback. The feature being edited and its build or
callback code are normally already known. Use that code directly; if it is not in
context, use `rg` with visible text, route names, Widget types, tooltips, or callback
names, then read only the containing build method and interaction callback. Construct
the exact structural selector and execute the action without a pre-inspect round trip.
Use `CompanyButton >> Text["Save"]` for a labeled custom control, or
`Toolbar >> [type="CompanyIconButton"]` when it has no text, key, or Semantics.
Cockpit traverses the mounted Element tree for explicit actions even when compact
inspect omitted that Element, requires one visible match, and performs a real
hit-tested `tap`, `hold`, or `double`. Equal matches fail as ambiguous; add a real
ancestor, route, key, or other source-proven condition instead of guessing or using
coordinates.

Use `dev inspect` before an action only for runtime facts source cannot determine:
which route or overlay is mounted, runtime-generated content or ordering, lazy
mounting, or a selector that failed or returned ambiguous. Source removes guesswork
but is not runtime proof: validate the source-defined live postcondition after the
action.

For runtime-only ambiguity or exploration, run the smallest `dev inspect QUERY`. It
searches mounted Flutter Element targets, independent of developer-authored
Semantics, and returns the shortest stable `sel` plus compact known `can` actions.
Copy `sel` exactly into `tap`, `type --into`, or `scroll`; every selector condition
intersects and equal matches fail instead of guessing. `inspect` prefers the shortest
unique stable selector: identity or exact text, then an ancestor scope, then path,
with `:nth()` reserved for truly ordered peers. Semantics remains one optional signal
and action fallback. Icon-only controls expose readable tooltips. Lazy lists expose
only mounted rows; pass an off-screen target directly to `dev scroll`, which owns
mounting and reveal.

With no query, `dev inspect` returns the current mounted control surface in
visual order, normally the whole screen in one bounded response. Read each
`targets` row as `sel`, optional `label`, executable `can`, optional `state`, and
optional `value`. State can report `disabled`, `selected|unselected`,
`on|off|mixed`, `focused`, `readonly`, or `obscured`; obscured inputs never expose
their value. A `sel` beginning with `:` is an opaque live ref for this mounted UI;
copy it directly into the command named by `can` without another inspect. Live
refs are deliberately transient: re-inspect after navigation, overlay, filtering,
reorder, keyboard, or other control-surface changes. Never store them in a case or
suite. A disabled target intentionally has no executable action. Use these rows
directly instead of querying every control or loading a tree merely to discover
actions. A targeted `dev inspect QUERY` still searches passive content and returns
a stable selector for durable reuse when text or structure, rather than the whole
control surface, is the question.

Interaction ownership stays explicit: merged ancestor `Semantics` never makes
passive descendants actionable, and descendants below `IgnorePointer(ignoring:
true)` or `AbsorbPointer(absorbing: true)` advertise no mutation actions. When
one actionable outer row
delegates selection to exactly one blocked control, the outer target carries
that control's state; multiple delegated controls leave state unresolved instead
of guessing. Execute only the `sel` whose own `can` advertises the command.

`can` maps directly to task commands:

| `can` | Command |
| --- | --- |
| `tap` | `dev tap TARGET` |
| `type` | `dev type VALUE --into TARGET` |
| `hold` | `dev hold TARGET` |
| `double` | `dev double TARGET` |
| `inc` / `dec` | `dev inc TARGET` / `dev dec TARGET` |
| `dismiss` | `dev dismiss TARGET` |
| `scroll` | `dev scroll TARGET` |

Do not substitute a gesture or coordinate action when a direct command is
advertised.

Selector quick reference:

| Need | Selector |
| --- | --- |
| Current mounted control | `:a7b9x2` |
| Exact text | `Save` |
| Cockpit ID | `#save` |
| Flutter Key | `@save-key` |
| Type + text | `FilledButton["Save"]` |
| Source-only custom type | `[type="CompanyIconButton"]` |
| Multiple conditions | `#save[type="FilledButton"][route="/edit"]` |
| Ancestor scope | `Dialog >> FilledButton["Continue"]` |
| Keyed row scope | `@task-row >> FilledButton["Open"]` |
| Contains / fuzzy text | `[*="Save"]` / `[~="Svae"]` |
| Contains / fuzzy tooltip | `[tip*="Save"]` / `[tip~="Svae"]` |
| Stable ordered item, last resort | `Button["Item"]:nth(2)` |

Selector string values use JSON quoting and `:nth()` is 1-based. Plain positional
text is exact. Prefer `#id`, exact text, `@key`, type/ancestor, route, then path;
use `:nth()` only for a real ordered list. Do not invent selector syntax: use the
table or copy `sel` from `inspect`.

```bash
cockpit dev inspect
cockpit dev tap ':a7b9x2'
cockpit dev inspect "Save changes"
cockpit dev tap '#save-button'
cockpit dev hold ':k4m2p8'
cockpit dev inc ':v8c1r6'
cockpit dev tap 'Dialog >> FilledButton["Save"]'
cockpit dev tap 'Toolbar >> [type="CompanyIconButton"]'
cockpit dev type "hello" --into '@message'
cockpit dev scroll "Operations"
```

Use `dev tree` only when bounded target inspection cannot explain the structure:

```bash
cockpit dev tree
cockpit dev tree --view more
cockpit dev tree --view full
```

The default tree is a compact actionable target index with reusable `sel`, not a
partial raw tree. `more` writes the mounted public Widget structure to an artifact;
`full` writes every mounted Element, including private/offstage nodes, with
Widget/Element/State/Render types, geometry, scroll ancestry, and bounded diagnostic
properties. Both structural views print only the verified absolute artifact path.

`dev scroll TARGET` uses exact matching by default and automatically ranks visible
scroll containers. Lazy targets are searched with independent forward and reverse
budgets; once mounted, every scrollable ancestor is revealed from inner to outer and
the target must be fully visible through all ancestor viewports. `nearest` also verifies
the real hit test: when a fixed Flutter overlay covers an otherwise visible target and
scrolling can avoid it, Cockpit moves the target to the viewport center. Use
`[*="text"]` only when exact text is insufficient. `--direction up|down` selects only
the initial search direction; after reaching that boundary Cockpit automatically tries
the opposite direction. Use `--align start|center|end` only for deliberate placement;
`--offset PX` moves the target toward the viewport end for positive values and toward
the start for negative values. Omit `--align nearest`, zero offset, direction, and
default budgets.

Re-inspect after list reorder, filtering, navigation, dialogs, sheets, or keyboard
transitions. `type VALUE --into
TARGET` replaces the field value; use `press enter` for a separate IME/key action.

`dev wait` is UI-only by default; add `--network` only for request-dependent
assertions. `--timeout VALUE` accepts `ms`, `s`, `m`, or `h`; every command has a
generous operation-specific default, so override only when the app genuinely needs
more time. `--quiet` on `wait` changes its settle window, not output view.

Default screenshot routing follows what must be visible:

- Android/iOS capture the system screen first for OS dialogs, then Flutter.
- Desktop/Web capture Flutter first, then an available system fallback.
- `--view more` shows the source; brief still reports fallback.

```bash
cockpit dev screenshot
cockpit dev screenshot --format path
cockpit dev screenshot --save /absolute/current.png
cockpit dev screenshot --compare /absolute/baseline.png --diff /absolute/diff.png
```

Visible claims require a current screenshot. Return only paths, never bytes,
Base64, data URIs, image contents, or hashes. RGBA comparison is exact unless a
pixel tolerance is explicitly required. `--save` selects an exact output path;
`--compare` accepts a baseline and `--diff` writes the diff. Do not compare captures
from different sources or viewport sizes. Android/iOS system capture is essential for
permissions and OS dialogs; the response identifies Flutter fallback.

## Network And Diagnostics

The network command returns a bounded newest-first index, not unbounded bodies. The
default page is 12 rows. Each request has a numeric ID; request/response body retrieval
writes separate verified artifact files and prints their paths. Inspect the row first,
then retrieve only the needed side. `--before ID` pages backward without repeating the
current page.

Sensitive query, header, cookie, structured-body, and credential-like values are
masked with `*` by default, not removed. Use `--raw` only with `--body` when complete
values or binary bytes are required; raw data remains in the saved body file rather
than stdout. Metadata and bounded previews remain safe and small.

SSE and other unfinished HTTP responses remain `receiving`; repeated `dev network`
reads show their current state and body artifact until the response ends. WebSocket
connections and frame activity are indexed. Text frames may be previewed; binary and
unsafe payloads stay metadata or files. Raw socket interception is unsupported.

```bash
cockpit dev network
cockpit dev network 37
cockpit dev network --before 37
cockpit dev network --failures --method GET --uri /api
cockpit dev network 37 --body response
cockpit dev network 37 --body both --raw
```

Use `dev diagnose --view more` for bounded UI, error, log, and network
health. Use `full` only when the complete response is needed; large response
bodies should be read from their reported paths. Start with `--failures`, `--method`,
or `--uri` when the app generates heavy traffic.

## Output And Input

Brief canonical LON is the default. For routine human or Agent reads, omit
`--format`; never request JSON merely because it is structured. Use `--format json`
only on a pipeline that uses `jq`, when the next consumer/API explicitly requires
JSON, or when inspecting JSON-specific wire behavior. Omit
`--view brief`, `--format lon`, the current session, inferred input, and
default wait/screenshot settings. Add an option only when it changes the requested
behavior.
LON may table-encode repeated object arrays, for example
`mounted:[sel label can;@save Save tap;...]`. The first row declares columns; it is
not an empty target. Read later rows by those columns instead of switching to JSON
only to expand the same data.
Formats are `lon|json|yaml|jsonl|path|none`. `path` prints one verified artifact/output
path, `none` is silent, and `--output` writes an atomic projection whose stdout is
only its verified path.

```bash
cockpit dev diagnose --view more
cockpit dev diagnose --view full --output /absolute/diagnose.lon
cockpit dev status --format json | jq '.lifecycle'
cockpit op run viewport.set --input '{width:800 height:600}'
```

`--input` and `--input-file` accept LON, JSON, or YAML. File extensions are
preferred because input format is inferred; specify an input format only when a
source is ambiguous. Never invent fields: use `cockpit explain OPERATION` or the
advertised schema first.

Brief output contains only the next-decision fields. Use `--view more`
for diagnosis and `full` only for the complete response. Do not request or
print screenshots, file contents, Base64, data URIs, hashes, or unneeded
byte counts. Stdout reports verified paths; read an artifact file only when its
metadata proves it is the needed evidence.

`more:N` means N projected values were omitted; request `--view more` only when
those values affect the next decision. Copy operation input
names only from `explain` under `input.fields`.

## Flutter E2E And Black-Box E2E

Validate documents before running them. During local development, run the same
validated file directly; use the indexed identity when the document is a durable
shared workspace asset or CI source.
Run IDs are durable; observe bounded events and export the finalized report bundle
only after the run reaches a terminal state.

```bash
cockpit case validate --file /absolute/case.lon
cockpit suite validate --file /absolute/suite.yaml
cockpit case run --file /absolute/case.lon --idempotency-key KEY
cockpit suite run --file /absolute/suite.yaml --idempotency-key KEY
cockpit case list --id CASE
cockpit suite list --id SUITE
cockpit case run --case-id CASE --idempotency-key KEY
cockpit suite run --suite-id SUITE --idempotency-key KEY
cockpit run list
cockpit run get --run-id RUN
cockpit run events --run-id RUN
cockpit suite report --run-id RUN --output-dir /absolute/report
cockpit artifact list --run-id RUN
cockpit artifact read --run-id RUN --artifact-id ARTIFACT --output /absolute/artifact
```

`.lon`, `.json`, `.yaml`, and `.yml` documents infer their input format, so omit
`--input-format`. Run inputs accept LON, JSON, or YAML through `--inputs` or
`--inputs-file`. `--file` and the indexed `--case-id`/`--suite-id` form are
mutually exclusive. A submission idempotency key identifies one logical run: reuse it
after transport uncertainty and never invent a new key until `run get` proves the
first submission does not exist.

Case and suite runs reuse the current Flutter project's active development session
when one exists. Pass `--session HANDLE` only to select another exact development
session, or `--target-id TARGET` for an explicitly registered black-box target; the
two selectors are mutually exclusive. Use `list --id ID` for exact lookup and add
`--path SUBSTRING` only when mirrored templates or fixtures make an ID ambiguous.

`run events` reads a bounded resumable SSE sequence until terminal or disconnect.
Resume with the last sequence or event ID; sequence numbers are monotonic. Do not
export `suite report` before terminal completion. `artifact list` returns metadata;
`artifact read` verifies the artifact and writes only to the requested output path.
Use `run list` to recover or switch to a recent durable run in the current workspace;
add `--cursor` only when the first bounded page does not contain the needed run.

Use real live capabilities only. Report unsupported capabilities as `unavailable`
or `blocked`. Distinguish product failure, authoring failure,
environment block, and infrastructure failure in reports. A passing process exit is
not sufficient: require terminal run state, expected assertions, no disqualifying
runtime/network errors, and current evidence.

## Advanced And References

Use generic operations only when no task command covers a live capability. Query one
kind instead of loading the full catalog, inspect its schema, then execute it:

```bash
cockpit op list --kind viewport.set
cockpit explain viewport.set
cockpit op run viewport.set --input '{width:800 height:600}'
```

`--scope` belongs only to `op list`; use `op list --scope supervisor` when
discovering a Supervisor operation. `explain KIND` and `op run KIND` resolve the
advertised scope automatically and do not accept `--scope`. Workspace discovery
resolves the current checkout by default. From a common ancestor with several active
Flutter projects, pass the same `--session HANDLE` to `op list`, `explain`, and
`op run`. Pass `--root-id` only when the live
descriptor declares root scope. `--session` injects the canonical runtime session only
when the schema declares it; do not put `sessionId` into input manually. Cockpit
generates an idempotency key only where the descriptor allows it. `op run` adopts the
descriptor's default timeout; add `--timeout` only to override it within the advertised
maximum.

## Public Client Control

REST is the complete external command and resource control plane. A client reads
the live catalogs and operation schema, then executes the same advertised
operations used by CLI and MCP:

```text
GET  /api/v2/server
GET  /api/v2/capabilities
GET  /api/v2/operations
GET  /api/v2/workspaces/{workspaceId}/operations
GET  /api/v2/operations/schema
POST /api/v2/operations
POST /api/v2/workspaces/{workspaceId}/operations
GET  /api/v2/runs/{runId}/events
```

`/api/v2/capabilities` is the static Supervisor-wide catalog and never starts,
attaches, or reconnects workspace workers. Use the selected workspace's operations
route when exact workspace-live operation availability is required.

Use the bearer token and loopback endpoint from Supervisor discovery, send the
negotiated API/feature headers, and use `cockpit_protocol` for strict DTO,
OpenAPI, and JSON Schema contracts. Supervisor operations use the global POST;
workspace operations use the workspace POST. The operation invocation envelope
owns workspace/root identity, idempotency, and deadline; its `input` contains
only the selected operation's advertised request fields.

SSE is the durable, resumable stream for run events. Resume with
`afterSequence` or `Last-Event-ID`; do not replace it with terminal polling.
WebSocket is only an internal Flutter Web bridge transport and is not a public
client command protocol. App network WebSocket frames may still appear in
`dev network`; that capture feature is unrelated to client control.

Checkouts/worktrees isolate sessions, ports, mutations, network data, and artifacts;
never make another checkout's session implicit. Keep Cockpit wiring in a development
entrypoint; production Flutter code must not import the bridge package.

Read [flutter.md](references/flutter.md) for bridge shells,
[dev.md](references/dev.md) for recovery/native boundaries,
[e2e.md](references/e2e.md) for black-box E2E,
[reporting.md](references/reporting.md) for CI,
[environments.md](references/environments.md) for unavailable platforms, and
[protocol.md](references/protocol.md) for live operation contracts.

A pass requires terminal UI/state, no disqualifying runtime/network error, and
current evidence. An unavailable required capability prevents a pass.
