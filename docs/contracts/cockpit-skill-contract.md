# Cockpit 2.0 Skill Contract

The Cockpit skill guides an AI agent through live development and E2E
verification using only Cockpit 2.0 public client surfaces.

## Required Behavior

- Start or reuse the authenticated Supervisor.
- Resolve an explicit root, workspace, target, and run identity.
- Inspect advertised capabilities before choosing an operation.
- Treat Flutter and black-box targets as peers in the target model.
- Use `cockpit.test/v2` case/suite documents for reusable validation.
- Observe terminal run state and structured errors before judging success.
- Read only digest-checked artifacts referenced by the canonical report.
- Preserve workspace isolation when several projects run concurrently.
- Respect authorization policy for production/unknown targets, dangerous
  operations, safety effects, and environment secrets.

## Evidence Policy

Use the cheapest evidence that proves the claim. State inspection is enough for
non-visual assertions. Use screenshots for visible state, recordings for motion
or reproduction, and suite reports for release/regression decisions. Artifact
existence alone is not proof.

## Failure Policy

Do not replay non-idempotent work after an uncertain transport failure. Resume
SSE from its last sequence, reuse submission idempotency keys, and read the run
resource before deciding whether to retry. Report unsupported or unavailable
capabilities as environment failures rather than faking success.

## Client Boundary

The skill must never recommend retired 1.x direct commands, embedded
dashboards, legacy artifact layouts, or implicit global sessions. Those
surfaces are not part of Cockpit 2.0.
