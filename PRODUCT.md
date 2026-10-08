# Product

## Register

product

## Users

Flutter developers and AI agents building and verifying real Flutter apps.
They work inside a running app (often on a device beside an IDE/terminal) and
need to capture what they just did, turn it into replayable evidence, and
hand that evidence to a teammate, a CI runner, or an agent.

## Product Purpose

Cockpit is an AI-first control plane for running Flutter apps: observe the
live tree, act on the real UI, capture proof. The interaction recorder turns
organic usage into a typed, selector-based `cockpit.test/v2` case document
with per-step evidence, so a recorded human flow becomes a reviewable,
replayable, agent-editable artifact. Success: a developer records a flow in
one pass, trusts the timeline they see, exports a case that compiles, and
replays it — or immediately sees where and why it deviates.

## Brand Personality

Precise, calm, professional. The tool disappears into the task; density is
fine, decoration is not. Visual language follows the Cockpit Console system
(Linear/Vercel-inspired dark-first neutrals, a single blue accent, monospace
for selectors and data).

## Anti-references

Generic Material dialogs floating over the host app; toy-like dev overlays
with oversized rounded cards; colorful badge soup; anything that looks like a
different product from Cockpit Console.

## Design Principles

1. Earned familiarity: standard affordances, consistent component vocabulary,
   no invented controls.
2. Evidence-first: the timeline is the product; every pixel serves reading
   steps, locators, and replay verdicts quickly.
3. One accent: blue is reserved for primary actions and live state; state
   colors (running/paused/deviated) carry meaning only.
4. The overlay is a tool, not the app: visually distinct dark panel, never
   confused with host-app UI, identical in light and dark hosts.
5. Immediate feedback: every command reflects in the panel within one frame;
   errors surface inline, never in snackbars.

## Accessibility & Inclusion

WCAG AA contrast (≥4.5:1 body) in both themes; full keyboard operability of
the panel is a stated non-goal for v1 (pointer-first dev tool) but hit targets
stay ≥40px; no color-only signaling — state always pairs color with text or
glyph.
