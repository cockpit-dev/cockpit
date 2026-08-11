# Cockpit Skill Contract

The Cockpit skill guides an AI agent through live development and E2E
verification using Cockpit public client surfaces.

## Required Behavior

- Start or reuse the authenticated Supervisor.
- Resolve an explicit root, workspace, target, and run identity.
- Inspect advertised capabilities before choosing an operation.
- Treat Flutter and black-box targets as peers in the target model.
- Select step planes and actions only from the target's advertised semantic,
  native, visual, coordinate, clipboard, location, and evidence capabilities.
- Keep visual templates and screenshot baselines inside the workspace, and use
  mixed semantic/system steps for Flutter/native stacks when available.
- Use `cockpit.test/v2` case/suite documents for reusable validation.
- Observe terminal run state and structured errors before judging success.
- Read only digest-checked artifacts referenced by the canonical report.
- Preserve the complete offline report directory and verify its root manifest.
- Preserve workspace isolation when several projects run concurrently.
- Respect authorization policy for production/unknown targets, dangerous
  operations, safety effects, and environment secrets.

## Evidence Policy

Use the cheapest evidence that proves the claim. State inspection is enough for
non-visual assertions. Use screenshots for visible state, recordings for motion
or reproduction, and suite reports for release/regression decisions. Artifact
existence alone is not proof.

Suite handoff uses neutral artifacts: `summary.md` for a bounded overview,
`report.json` for the complete fact graph, `index.html` for offline task-focused
sections, and `manifest.json` for directory integrity. Binary evidence stays in files and
is read only when a claim requires it.

Screenshot assertions retain actual, baseline, and diff files. Compose scoped
before/after behavior from suite fixtures, case `setup`/`finally`, step
`evidence`, and explicit recording boundaries.

## Failure Policy

Do not replay non-idempotent work after an uncertain transport failure. Resume
SSE from its last sequence, reuse submission idempotency keys, and read the run
resource before deciding whether to retry. Report unsupported or unavailable
capabilities as environment failures.
