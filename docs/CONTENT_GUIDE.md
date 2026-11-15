# Content authoring guide

All teaching content lives in `content/` as Markdown + YAML and is compiled and validated
by `npm run content` (see `scripts/content-lib.mjs` for the exact rules). The build fails
on any violation, so run it after every file you write.

```
content/
  modules.yaml              module list (order = curriculum order)
  curriculum-plan.yaml      planned lesson ids, order, prerequisites (the contract between authors)
  sources/*.yaml            source registry, merged; one file per author/module to avoid conflicts
  lessons/<module>/NN-<slug>.md
  cases/<slug>.md
  labs/<slug>.md
  items/*.yaml              standalone items (cumulative and final assessment)
```

## Ids

Lowercase words joined by hyphens. Lesson, concept and item ids share one namespace and
must be unique. Prefix by module: `fnd-`, `dat-`, `dst-`, `scl-`, `prd-`; cases `case-`,
labs `lab-`. Items: `<concept-id>-p1…` for practice, `-a1…` for assessment.
**Never rename an id after it has shipped** — stored progress refers to it.

## Lesson file

```markdown
---
id: fnd-latency-percentiles
title: Latency distributions and percentiles
module: foundations
order: 3                      # position inside the module
minutes: 9                    # honest reading time
objective: One sentence starting with a verb: what the learner can do afterwards.
prereqs: [fnd-other-lesson]   # lesson ids that come earlier; [] if none
concepts:                     # 1–3 concepts this lesson teaches; these are what progress tracks
  - id: fnd-tail-latency
    name: Tail latency
    def: One-sentence glossary definition, at least 25 characters.
sources:                      # where the lesson's claims come from
  - ref: sre-book             # key in content/sources/*.yaml
    section: "Ch. 4, Service Level Objectives — Indicators in Practice"
    url: https://sre.google/sre-book/service-level-objectives/   # optional deep link
---
## Intuition
## How it works
## Example
## Why it matters
## Tradeoffs and limits
## Common misconceptions
## Worked scenario

=== items ===
- id: fnd-tail-latency-p1
  ...
```

The seven `##` headings are required, exactly as written and in that order. Minimum 450
words; aim for 600–900. Write original prose; do not copy source text.

- **Intuition**: plain-language picture first, no jargon that has not been introduced.
- **How it works**: the actual mechanism, precise enough to predict behaviour.
- **Example**: concrete, with specific values. Label invented numbers as hypothetical.
- **Why it matters**: what it buys you and where it shows up in real designs.
- **Tradeoffs and limits**: costs, when not to use it, what it does not solve.
- **Common misconceptions**: a bulleted list; state the wrong belief, then the correction.
- **Worked scenario**: a small problem solved step by step, showing the reasoning.

### Supported Markdown

Paragraphs, `###` sub-headings, bullet and numbered lists (one level of nesting),
`**bold**`, `*italic*`, `` `code` ``, links, block quotes, fenced code blocks, and tables
of at most 4 columns. No raw HTML, no images.

### Diagrams

Use a fenced block with language `diagram` where structure or message order matters.

````
```diagram
flow
Client -> Load balancer: HTTPS
Load balancer -> App 1
Load balancer -> App 2
App 1 -> Database: SQL
App 2 -> Database: SQL
```
````

`flow`: one edge per line, drawn top to bottom; at most 12 nodes, 3 per row, node names
≤ 22 characters. A node's row is the longest path from the first-declared nodes.

````
```diagram
seq
Client -> Leader: write x=1
Leader -> Follower: append
Follower --> Leader: ack
Leader -x Slow: append
note Leader: commit at majority
Leader --> Client: ok
```
````

`seq`: 2–4 actors (names ≤ 12 characters), one step per line, labels ≤ 34 characters.
`->` solid, `-->` dashed (replies), `-x` lost message, `note Actor: text` for a local step.

## Items

Each lesson needs **at least 4 practice and 2 assessment items**, at least **3 different
formats**, and each concept needs ≥ 2 practice items, ≥ 1 assessment item and at least one
item that is not multiple choice.

Common fields:

```yaml
- id: fnd-tail-latency-p1
  concept: fnd-tail-latency        # or concepts: [a, b]; the first is primary
  pool: practice                   # practice | assess | final
  skill: predict                   # recall | explain | predict | compare | estimate | diagnose | design | implement
  format: mcq                      # mcq | multi | numeric | order | free
  difficulty: 2                    # 1 recall/definition, 2 apply, 3 analyse or design
  prompt: |
    Markdown. A self-contained question (at least 20 characters).
  hints:                           # required for practice items; progressively more specific
    - First nudge, does not give the answer away.
  explanation: |
    Why the answer is right and why the tempting alternatives are wrong.
  assumptions: Optional note labelling hypothetical numbers.
  sources:                         # optional; defaults to the lesson's sources
    - { ref: sre-book, section: "Ch. 6 …" }
```

Format-specific fields:

| format | fields |
|---|---|
| `mcq` | `choices` (3–6 strings), `answer` (0-based index). Choices are shuffled in the app. |
| `multi` | `choices`, `answers` (list of 0-based indexes; at least one choice must be wrong). |
| `numeric` | `answer`, `unit`, exactly one of `tolerance` (relative, e.g. `0.1`) or `tolAbs`, and `calc` — an arithmetic expression that reproduces the answer (checked by the build), e.g. `calc: "500e6 * 100 / 1e9"`. |
| `order` | `steps`: 3–7 strings in the **correct** order (shuffled in the app). |
| `free` | `model` (model answer, Markdown) and `rubric` (2–7 checkable points). Self-assessed by the learner against the rubric. |

Rules:

- `explain` and `design` skills must not be multiple choice.
- **Pools are separate.** `practice` items are shown during learning and spaced review.
  `assess` items appear only in quizzes and delayed checks, so they must test the same
  concept with a *different scenario*, not a reworded practice question. `final` items
  (in `content/items/final-*.yaml`) use scenarios that appear nowhere else.
- Distractors must be plausible — real misconceptions, not jokes.
- Rubric points describe the reasoning an answer must contain ("explains that the
  follower may lag, so the read can be stale"), not key words. More than one design can
  satisfy a rubric; say so in the model answer when true.
- Estimation items must state every assumption in the prompt and say what to compute.
- No "all of the above"; no trick wording; one unambiguous answer for auto-checked formats.

## Case study file (`content/cases/<slug>.md`)

Front matter: `id`, `title`, `summary`, `minutes`, `prereqs` (lesson ids), `concepts`
(≥ 3 existing concept ids exercised), `sources`, and

```yaml
unguided:
  minutes: 35
  prompt: |
    The same problem class with different constraints, with no stage prompts.
  rubric: [at least 5 points]
```

Body: exactly these eight `##` stages in order — Requirements, Estimates, API and data
model, Initial architecture, Bottlenecks, Failure modes, Alternatives, Evolution. Each
stage **starts** with `> **Your turn:** <what to attempt before reading on>` followed by
a blank line, then the reference discussion. At least 1100 words. Optional `=== items ===`.

## Lab file (`content/labs/<slug>.md`)

Front matter: `id`, `title`, `summary`, `requiresDev: true`, `hours`, `lessons` (linked
lesson ids), `sources`. Body sections, exactly: Goal, What to build, Checkpoints, Measure
and break it. Items after `=== items ===` are phone-only reasoning questions.

## Sources

- Cite the most specific section you actually checked (chapter/section number or heading).
  **Never cite from memory**: open the source and confirm the section exists and says
  what the lesson claims.
- To add a source, add a key to `content/sources/<your-module>.yaml` with `title`, `url`,
  `license`. Prefer primary material: the listed course notes and books, original papers,
  RFCs, and official product documentation.
- If a source cannot be reached, use a credible alternative and note the substitution in
  `docs/SOURCES.md`.
