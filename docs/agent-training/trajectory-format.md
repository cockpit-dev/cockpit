# Agent training trajectory format (`cockpit.training/trajectory-v1`)

This document defines the canonical format produced by
`tool/record_trajectory.dart` and consumed by training-time renderers. The
format stores **raw command/observation records**, never model-specific chat
templates, so the same dataset can be rendered for any base model (dense
1B–4B or small-active MoE) without re-recording.

## Design rules

1. **Model-agnostic.** A trajectory is a flat list of executed commands and
   their verbatim observations. Mapping steps onto `assistant`/`user` turns
   and applying a chat template happens at training time, per base model.
2. **Agent-eye fidelity.** `observation` is byte-for-byte what `cockpit`
   printed on stdout for the recorded `command` under the recorded defaults
   (`cockpit.format` / `cockpit.view`). Recording uses the same defaults a
   real agent loop uses, so there is no train/inference observation skew.
3. **Command truthfulness.** `command` is the semantic command an agent
   issues. Two recording-only details differ from the executed argv: the
   recorder appends `--format`/`--view` to capture output, and screenshot
   `--save` paths are recorded as bare file names while the step's `image`
   field carries the dataset-relative asset path.

## Trajectory record

One JSON object per line in `<dataset>/<scenario-id>.jsonl`:

| Field | Type | Description |
| --- | --- | --- |
| `schema` | `string` | Always `cockpit.training/trajectory-v1`. |
| `id` | `string` | `<scenario-id>-<token>[-pN]`, unique within the dataset. |
| `derivedFrom` | `string?` | Base trajectory id for paraphrase variants. |
| `app` | `object` | `name`, `directory` (repo-relative), `platform`. |
| `session` | `object` | `handle`, `startedByRecorder`, `setupRecorded`, `stopped`. |
| `goal` | `string` | The natural-language instruction given to the agent. |
| `paraphrases` | `string[]` | Alternate phrasings of the same goal (metadata only). |
| `systemPrompt` | `object` | `id`, `sha256`, `text` — the fixed operating prompt. |
| `steps` | `step[]` | Ordered command/observation records. |
| `completion` | `string` | What the agent says when the goal is met (termination teaching signal). |
| `outcome` | `string` | `success` \| `recovered` \| `failure`. |
| `cockpit` | `object` | `version`, `format`, `view`, `bin` used while recording. |
| `recordedAt` | `string` | ISO-8601 UTC timestamp. |

`outcome` semantics:

- `success` — every step met its expectation, no deliberate failure steps.
- `recovered` — every step met its expectation and at least one step was a
  deliberate expected failure (`expect.ok: false`) that later steps recovered
  from. These trajectories teach ambiguity handling and recovery loops.
- `failure` — some expectation was not met. Kept for curation/debugging;
  exclude from training unless intentionally teaching abort behavior.

## Step record

| Field | Type | Description |
| --- | --- | --- |
| `index` | `int` | Zero-based position. |
| `command` | `string` | The agent-issued command (see rule 3 above). |
| `exitCode` | `int` | Process exit code (`0` ok; `64/65/66/69/75/77` failure classes). |
| `observation` | `string` | Verbatim stdout (LON by default, or JSON). |
| `stderr` | `string` | Verbatim stderr (CLI-level error envelopes land here). |
| `durationMs` | `int` | Wall time of the command. |
| `timedOut` | `bool` | True when the recorder killed the process. |
| `expect` | `object?` | Scenario expectation: `ok` (bool), `code` (string?). |
| `expectationMet` | `bool` | Whether the observation satisfied `expect`. |
| `image` | `object?` | `path` (dataset-relative), `sha256`, `sizeBytes` for screenshot steps. |

## Paraphrase variants

The writer emits one record per goal phrasing. The base record uses `goal`;
each entry in `paraphrases` produces a variant with the paraphrase as `goal`,
`id` suffixed `-p2`, `-p3`, …, and `derivedFrom` pointing at the base id. All
steps are shared — only the instruction text differs. This is the cheap
augmentation that buys phrasing generalization.

## Directory layout

```
tool/trajectory/
  scenarios/<app-name>/<scenario-id>.yaml   # committed scenario definitions
  datasets/<dataset-name>/                  # recorder output (gitignored)
    <scenario-id>.jsonl
    assets/<trajectory-id>/step-<NN>.png
  apps/                                     # generated pattern apps (gitignored)
```

## Rendering contract (training time)

A renderer converts one trajectory into a chat sample:

1. Emit the `systemPrompt.text` as the system message.
2. Emit `goal` as the first user message.
3. For each step in order: the `command` becomes an assistant action (plain
   text or a tool call, per base model); the `observation` (and `image` when
   present) becomes the following user/tool message.
4. Emit `completion` as the final assistant message.

Renderers belong to the training stack (Python/MLX side), not this repository.
