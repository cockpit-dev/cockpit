# E2E Authoring And Execution

Use this reference for reusable black-box, Flutter, mixed-stack, suite, and CI
flows. Exact authored fields live in the adjacent
[`cockpit.test.v2.schema.json`](cockpit.test.v2.schema.json).

## Contents

- [Start from a local template](#start-from-a-local-template)
- [Case model](#case-model)
- [Locators and planes](#locators-and-planes)
- [Actions and evidence](#actions-and-evidence)
- [Flow control and lifecycle](#flow-control-and-lifecycle)
- [Variables and secrets](#variables-and-secrets)
- [Suites](#suites)
- [Run protocol](#run-protocol)

## Start From A Local Template

Copy the needed skill asset into the registered application workspace and
adapt target requirements, locators, inputs, capabilities, and expected state:

- `../assets/templates/e2e/cases/black-box-login.case.yaml`
- `../assets/templates/e2e/cases/black-box-settings.case.yaml`
- `../assets/templates/e2e/cases/flutter-mixed-stack.case.yaml`
- `../assets/templates/e2e/suites/regression.suite.yaml`

Keep test documents, visual templates, and screenshot baselines within that
workspace. Suite file sources are workspace-relative paths. Validate every
changed case/suite before listing or running it.

## Case Model

A case contains:

- `schemaVersion: cockpit.test/v2`, `kind: case`, stable `id`
- target requirements: platform, target kind, default plane, optional app ID
  and required capabilities
- defaults: command/cleanup timeout, fail-fast, evidence policy, compiler
  bounds
- typed variables and reusable fragments
- `setup`, main `steps`, and always-eligible `finally`

Use one case for one coherent user journey or focused product claim. Every
mutation needs an assertion against resulting observable UI/state. Set
`timeoutMs` on known-slow steps instead of inflating every command.

## Locators And Planes

Semantic/native locators support `text`, `label`, `nativeId`, `testId`, `role`,
`type`, `path`, state predicates, relationships (`ancestor`, `child`,
`descendant`, `above`, `below`, `leftOf`, `rightOf`), ordered `fallbacks`, and
0-based `index`. Coordinate locators use normalized `x`/`y`; visual locators
use a workspace-relative template and similarity threshold. Screenshot
assertions use a per-pixel RGB `pixelTolerance` plus a bounded
`maxDifferingPixelRatio`; an optional locator crops the comparison to the
resolved element.

Signals in the same locator are conjunctive. Start with one stable identity,
add relationships/state to disambiguate, then use `index` only for a genuine
list. Put alternate platform representations in `fallbacks`; they are not
extra AND conditions. Text/label matching defaults to `exact`; choose
`contains`, typo-tolerant `fuzzy`, or `regex` explicitly.

Use the target's default plane unless a step needs `semantic`, `native`,
`visual`, or `coordinate`. A Flutter bridge target can use semantic steps and
its secondary native driver in one case, which covers native dialogs and
hybrid Flutter/native stacks. A production app without a bridge is controlled
non-invasively through its advertised black-box drivers.

## Actions And Evidence

The schema includes:

- taps, long/double press, semantics increase/decrease/dismiss
- text focus/entry/editing/copy/erase/paste, IME actions, key events
- drag, fling, swipe, pinch, rotate, pan/zoom, multi-touch, scroll/reveal
- back, keyboard dismissal, UI/network idle, waits
- visible/text/screenshot assertions
- screenshots, snapshots, recording start/stop
- bounded travel and advertised system actions

Search the bundled schema by action name for exact fields, for example:

```bash
rg -n '"scrollUntilVisibleAction"|"assertScreenshotAction"' \
  <skill-directory>/references/cockpit.test.v2.schema.json
```

Use step `evidence` for automatic screenshot/snapshot policy. Use explicit
`captureScreenshot` for named product proof. Use `startRecording` before the
bounded motion/reproduction window and `stopRecording` in `finally` so cleanup
still attempts finalization after a failed main step. Request only advertised
capture layers and record fallback/degradation in the report.

Screenshot baseline and visual-template paths must remain workspace-confined.
Screenshot assertions publish actual, baseline, and diff artifacts; do not
embed image bytes in YAML/JSON or terminal output.

Use `captureOptions.profile: nativePreferred` for device/application baselines
and `flutterPreferred` for Flutter-view or locator-cropped baselines. Keep
fallback disabled for visual assertions so the actual capture scope cannot
silently differ from the baseline scope.

## Flow Control And Lifecycle

- `setup`: preconditions for one case attempt.
- `finally`: bounded cleanup/post actions, including recording finalization.
- `if`: evaluates a visible/text/route/idle condition and runs `then` or
  `else` steps.
- `retry`: re-runs nested steps up to `maxAttempts` with optional delay.
- `loop`: while its condition is satisfied, runs nested steps up to
  `maxIterations`; it succeeds when the condition becomes unsatisfied.
- `call`: expands a named fragment without duplicating steps.
- suite fixtures: reusable suite- or case-attempt-scoped setup/teardown.

Use bounded control flow only. Cleanup gets a separate `cleanupTimeoutMs` and
individual step budgets. Do not add another pre/post DSL outside these
canonical primitives because it would be absent from the report fact graph.

## Variables And Secrets

Case variables may be constants, run inputs, or secret references. Use
`{$var: name}` in supported fields. Secrets remain references such as
`env:COCKPIT_TEST_PASSWORD`; do not put secret values into source files,
stdout, screenshots, or report metadata. Suite case entries bind `inputs`; a
suite matrix can bind selected axes with `{$matrix: axis}`.

Policy must authorize referenced environment secret names and sensitive
effects. Declare step `safety.effects` for credential-sensitive, permission,
communication, financial, destructive, or external-navigation work.

## Suites

Suites add:

- a dependency DAG through `dependsOn`
- bounded `maxConcurrency` and truthful `failFast`
- `sharedSession`, `restartApp`, or `resetAppData` isolation
- retry only for selected blocked/interrupted/internal outcomes
- suite and case-attempt fixtures
- include/exclude tags
- matrix axes/include/exclude with a maximum combination bound
- JSON/JUnit/HTML/summary report selection

`failFast` stops eligible new work after a qualifying failure; an intentional
skip does not invalidate independent cases. Give unrelated cases no dependency
edge so the scheduler can run them concurrently. Use deterministic fixture
ownership and isolated output/state when several rows or projects execute.

## Run Protocol

```bash
cockpit case validate --file <case.yaml> --format yaml
cockpit suite validate --file <suite.yaml> --format yaml
cockpit case list --workspace-id <workspaceId>
cockpit suite list --workspace-id <workspaceId>
cockpit case run \
  --workspace-id <workspaceId> \
  --case-id <caseId> \
  --target-id <targetId> \
  --inputs-file <inputs.json> \
  --idempotency-key <uniqueKey> \
  --timeout-ms <overallCaseBudget>
cockpit run events --run-id <runId> --after-sequence 0
cockpit run get --run-id <runId>
```

Use `suite run` for a suite and
`suite report --run-id <runId> --output-dir <newDirectory>` after terminal
completion. Case
runs default to the advertised case budget (normally 30 minutes, maximum 6
hours); suites normally default to 2 hours, maximum 24 hours. Trust the live
descriptor if these policies differ.

Resume an interrupted event stream from the last sequence. Reuse the original
submission idempotency key; do not resubmit with a new key until run state
proves the first submission did not exist.
