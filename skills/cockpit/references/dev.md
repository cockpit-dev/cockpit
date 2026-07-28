# Development Workflows

Use this reference for fast implementation, diagnosis, and targeted live
verification. It assumes Cockpit is installed; no Cockpit source checkout is
required.

## Contents

- [Resolve context](#resolve-context)
- [Local YOLO mode](#local-yolo-mode)
- [Register a target](#register-a-target)
- [Flutter development shell](#flutter-development-shell)
- [Fast loop](#fast-loop)
- [Common development flows](#common-development-flows)
- [Practical heuristics](#practical-heuristics)
- [Operation execution](#operation-execution)
- [Timeouts and failures](#timeouts-and-failures)
- [Parallel projects](#parallel-projects)

## Resolve Context

```bash
cockpit daemon status
cockpit root list
cockpit workspace list
cockpit target discover
```

Start the daemon and register the project root/checkout only when missing.
Reuse IDs from output. If exact machine data is necessary, write it to a file:

```bash
cockpit workspace list \
  --stdout-format json \
  --output /absolute/path/to/workspaces.json
```

The default semantic output is preferable when an agent only needs the next
command and resolved IDs.

## Local YOLO Mode

For a user-requested local development or test workflow, prefer unrestricted
authorization for the daemon process:

```bash
cockpit daemon start --yolo
```

If `daemon status` reports a running restricted daemon, use
`cockpit daemon restart --yolo`. This is the normal fast path for iterative
reloads, UI control, screenshots, recordings, environment injection, and
capability-advertised system actions. Do not carry this choice into
production/unknown targets or real external side effects.

## Register A Target

Installed black-box app:

```bash
cockpit target register \
  --workspace-id <workspaceId> \
  --platform <platformFromDiscovery> \
  --device-id <deviceIdFromDiscovery> \
  --target-kind nativeApp \
  --environment development \
  --app-id <realPlatformAppId> \
  --idempotency-key <uniqueKey>
```

Use `desktopApp` for an installed desktop process and `browserPage` for a web
page. Use an iOS target-scoped `--wda-url` only when discovery/capabilities say
WDA is required. Launch or activate the target, then inspect it. Persisted
registration or launch metadata is not liveness proof.

## Flutter Development Shell

Use a `flutterApp` target with an indexed development entrypoint document.
Follow [flutter.md](flutter.md) for the complete development-only entrypoint,
document lookup, target registration, and router wiring. This enables semantic
UI, route, runtime/network inspection, hot reload/restart, and mixed
Flutter/native control without shipping the bridge in production.

Launch supports repeatable configuration:

```bash
cockpit target launch \
  --workspace-id <workspaceId> \
  --target-id <targetId> \
  --mode development \
  --dart-define API_URL=https://example.test \
  --dart-define-from-file config/development.json \
  --env API_TOKEN=secret \
  --flutter-arg --track-widget-creation \
  --launch-timeout-ms 900000 \
  --idempotency-key <uniqueKey>
```

Generic operation/MCP clients send equivalent `launchConfiguration` fields:
`dartDefines`, `dartDefineFromFiles`, `flutterArgs`, and `environment`.
Cockpit owns target, device, flavor, mode, machine, remote-control, and
debug/profile/release arguments; do not override those through `flutterArgs`.
Do not send Flutter launch configuration to a black-box target.

## Fast Loop

1. Inspect target state and available operations.
2. Edit one coherent change.
3. Run the smallest advertised analysis/reload/action that exercises it.
4. Inspect state and bounded errors after the mutation.
5. Capture a screenshot only for a visible claim; record only for motion or a
   reproduction claim.
6. Repeat without relaunching unless state or capabilities require it.

Prefer target/operation reads over broad forensic collection. Use
`minimal -> standard -> inspect -> evidence` as an escalation ladder. A
successful reload or action dispatch is transport proof, not product proof.

## Common Development Flows

| Goal | Smallest useful flow |
| --- | --- |
| UI copy, spacing, color, or layout | baseline inspect -> edit -> focused analysis -> hot reload -> inspect changed UI -> screenshot |
| Route or interaction behavior | inspect route/UI -> perform one action -> wait for idle if advertised -> assert route/text/state -> read bounded errors |
| Runtime or network behavior | inspect baseline -> trigger request -> wait for idle -> inspect network/runtime errors -> assert resulting UI/state |
| Installed black-box app | discover -> register `nativeApp` -> launch/activate -> inspect capabilities -> native/visual/coordinate action -> observable assertion |
| Flutter plus native dialog | semantic action to the boundary -> native/system action for the dialog -> return to semantic assertion |
| Slow build or launch | set the launch/operation timeout from measured cost -> keep inner step budgets independent -> reuse the live target |
| Ambiguous locator | inspect current UI -> stable ID/label -> relationship/state -> ordered fallback -> 0-based index only for a real list |
| Timed-out mutation | inspect current state first -> reuse the logical idempotency key -> resume only the remaining safe work |

Use a case when the flow should be repeatable across runs. Use a suite only for
multi-case regression, matrix, dependency, fixture, retry, or release work.

## Practical Heuristics

- Keep the daemon, worker, target, and development session alive while more
  edits are likely. Relaunch only for unhealthy state, launch configuration
  changes, clean-start behavior, or failed reload recovery.
- Ask the runtime for one missing fact at a time. Start with compact semantic
  output and a minimal profile; inspect heavier UI or evidence only when the
  smaller read cannot decide the next action.
- Do not parallelize a mutation with the read that depends on its result.
- After a list insertion, deletion, filter, reorder, keyboard transition,
  banner, sheet, or dialog, re-inspect or re-anchor before the next deep action.
- Prefer stable product semantics over brittle coordinates. Use visual or
  coordinate control when the target does not advertise a stronger plane.
- Do not add arbitrary sleeps for a slow transition. Use advertised idle/wait
  operations and a timeout that matches the specific step.
- Preserve environment variables, Dart defines, flavors, and Flutter arguments
  in the target launch configuration; do not relaunch them through ad hoc shell
  commands.
- Keep secrets as authorized references. Never echo injected values into
  stdout, screenshots, reports, or generated test documents.
- Treat unsupported capability as blocked/unavailable and switch planes only
  when the target advertises the alternative.
- Before claiming a visible fix, capture current evidence after the final
  mutation. Before release, leave the fast loop and run the complete suite and
  offline report gate.

Typical operation families can include file analysis, package/search/LSP,
Flutter reload/restart, UI actions, runtime/network inspection, system control,
and evidence. Names and payload fields vary by target and installed version;
select them only from `operation list`.

## Operation Execution

```bash
cockpit operation list --workspace-id <workspaceId>
cockpit operation run \
  --workspace-id <workspaceId> \
  --kind <exactAdvertisedKind> \
  --input-file /absolute/path/to/operation.json \
  --idempotency-key <stableLogicalActionKey> \
  --timeout-ms <advertisedBudget>
```

Omit `--idempotency-key` only when the descriptor confirms a read-only action
that does not require one. Prefer file input for non-trivial JSON. Do not print
secrets or expect launch environment values to be echoed back.

## Timeouts And Failures

- Start from the descriptor's default timeout; increase only for known slow
  builds, launches, scrolls, platform transitions, or long tools.
- Keep one timeout per operation/step. The outer case/suite deadline does not
  replace inner command and cleanup budgets.
- On timeout or disconnect after a mutation, inspect target/run state before
  retrying; the original action may already have committed.
- On locator ambiguity, inspect current UI and strengthen stable signals or
  choose `index`; do not immediately change application code.
- Unsupported platform control is an environment/capability result, not a
  reason to manufacture success.
- Read structured error code/details and referenced diagnostics before opening
  large artifacts.

## Parallel Projects

Register each checkout as its own workspace, keep every target and operation
bound to that workspace, and assign each physical/logical resource through the
Supervisor. Use a separate iOS WDA URL per target. Do not share manual temp
files, ports, run IDs, or output directories between jobs. A long operation in
one worker must not block unrelated workspaces; inspect `lease.list` only when
a resource is actually contended or quarantined.
