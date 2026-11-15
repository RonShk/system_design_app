# Learning design: evidence and product decisions

This document maps what the learning research says to what the app does. It separates
three levels of support:

- **Strong** – stated directly in the sources read for this project, with broad evidence.
- **Moderate** – supported in the sources, with stated limits.
- **Design choice** – a reasonable engineering decision that the sources do not settle.
  Nothing marked as a design choice is claimed to be optimal.

## Sources read

| Key | Source | What was read |
|---|---|---|
| D-AFT | Dunlosky, "Strengthening the Student Toolbox", *American Educator*, Fall 2013 — https://www.aft.org/ae/fall2013/dunlosky | Full article |
| D-PSPI | Dunlosky et al., "Improving Students' Learning With Effective Learning Techniques", *PSPI* 14(1), 2013 — https://www.psychologicalscience.org/publications/journals/pspi/learning-techniques.html | Journal summary page only (the monograph itself was not read; D-AFT is the authors' own practical summary of it) |
| LS | The Learning Scientists, "Six Strategies for Effective Learning" — https://www.learningscientists.org/blog/2016/8/18-1 | Full post |
| RP-FAQ | retrievalpractice.org FAQ — https://www.retrievalpractice.org/faq | Full page |
| SG | Carpenter & Agarwal, "How to Use Spaced Retrieval Practice to Boost Learning", 2020 — https://pdf.retrievalpractice.org/SpacingGuide.pdf | Full guide (12 pages) |

## Evidence → decision map

| # | Finding | Support | Source | Product decision |
|---|---|---|---|---|
| 1 | Practice testing (retrieving from memory) substantially beats rereading. Recall-style tests work better than recognition. | Strong | D-AFT "Practice testing"; D-PSPI summary; RP-FAQ | Every lesson is followed by retrieval practice. At least 40% of all items are free-recall, explanation, calculation, ordering, or design; multiple choice is never the only evidence for a concept (enforced by the content validator and by the mastery rules). |
| 2 | Distributed practice gives longer retention than massed practice for the same total time. | Strong | D-AFT "Distributed practice"; SG pp. 3–7 | Concepts are re-tested on later days by a spaced scheduler. The app does not let a same-day success count as retention. |
| 3 | No specific spacing interval is optimal: "any spacing is better than no spacing, and exactly how much time should occur between learning sessions is less critical"; equal vs. non-equal gaps make little difference. | Strong (as a *negative* result) | SG p. 10 FAQ | The interval ladder (1, 3, 7, 14, 30, 60, 120 days) is a **design choice** picked for practicality: short first gaps to catch early forgetting, longer gaps to keep daily load low. It is documented as such and is a single constant in `src/domain/scheduler.ts`. |
| 4 | Retrieval should be effortful ("desirable difficulty"); spacing works *because* some forgetting occurs. | Strong | SG p. 5; RP-FAQ | Reviews are scheduled so material is no longer fresh. Reviewing early (before half the interval has elapsed) is allowed but does not advance the schedule. |
| 5 | Feedback after an attempt improves learning, and elaborated feedback (with explanation) is more powerful; retrieval without feedback still helps. | Strong | RP-FAQ "feedback"; SG p. 11 | The answer and an explanation are shown only after a committed attempt. Every item must have an explanation and a source reference (validator-enforced). |
| 6 | Retrieval practice is a learning strategy, not an assessment; keep it low-stakes. | Strong | RP-FAQ | Practice and assessment are separate modes with separate item pools. Practice never blocks progress and is not scored as a grade. |
| 7 | Cumulative quizzes provide spacing and keep earlier material alive. | Strong | SG p. 8; D-AFT | Cumulative assessments span every module studied so far. Daily sessions mix due concepts from all modules. |
| 8 | Interleaving (mixing problem types) slows practice but improves retention and choosing the right method; the benefit does not extend to all material and "much more research is needed". | Moderate | D-AFT "Interleaved practice"; SG p. 11 | Reviews and cumulative quizzes are interleaved across topics. Practice immediately after a *new* lesson stays on that lesson (blocked), because interleaving presupposes the concepts are already introduced. |
| 9 | Self-explanation improves transfer to new problems; paraphrasing is not self-explanation. | Moderate | D-AFT "Self-explanation" | "Explain why" and "predict what happens" items ask for a mechanism, and their rubrics list the causal points an answer must contain rather than key phrases. |
| 10 | Elaborative interrogation ("why is this true?") helps, but needs background knowledge. | Moderate | D-AFT "Elaborative interrogation"; LS | "Why" prompts appear in practice after the lesson has supplied the background, not before. |
| 11 | Concrete examples and combining words with visuals (dual coding) support learning. | Moderate | LS | Every lesson has a concrete example and a worked scenario; diagrams are used where structure or message order matters. |
| 12 | Spacing and retrieval support transfer, not only memorisation, when questions require application. | Moderate | SG p. 6; RP-FAQ "transfer" | Assessment uses scenario variants not seen in practice; application problems are part of every daily session. |
| 13 | Rereading, highlighting, and summarising have low utility on their own. | Strong | D-AFT; D-PSPI summary | The app has no "mark as read = learned" path. Lesson completion only moves a concept to *Introduced*. |
| 14 | Students mistake fluency for learning ("illusion of knowing"); spaced practice feels worse while working better. | Strong | SG p. 5, p. 9 | Confidence is recorded before feedback and shown beside actual results, but never counts as evidence. High-confidence errors are flagged for earlier review. |

## Things the listed sources do not establish

- **Worked examples followed by fading guidance.** This is requested in the project brief and
  is implemented (lesson worked scenario → guided case study with stage prompts → unguided
  design exercise). The five sources above do not review it. The worked-example literature
  (e.g. Renkl & Atkinson, 2003, *Educational Psychologist* 38(1)) was **not** re-read for
  this project, so it is treated as a design choice here.
- **Mastery thresholds.** "Two independent successes on different items", "retained after
  a gap of at least 7 days" and similar thresholds are design choices. They exist to
  prevent one lucky answer from counting as mastery, not because the numbers are validated.
- **Session length.** 10–20 minutes follows the brief and D-AFT's advice to use short
  study blocks; no source gives an optimal length.
- **Self-assessment accuracy.** Free-text answers are self-graded against a rubric. The
  sources say self-grading is an acceptable way to deliver feedback (RP-FAQ) but do not
  claim it is accurate, so self-graded evidence is stored and displayed separately from
  automatically checked evidence.

## Concept states (design choice)

| State | Rule |
|---|---|
| Not started | No lesson completed, no attempts. |
| Introduced | The lesson teaching the concept was completed. |
| Practiced | At least one answered item on the concept. |
| Demonstrated | Independent (no hint, not revealed) successes on at least two *different* items, at least one of which is not multiple choice. |
| Retained | Independent success on an item answered at least 7 days after the previous retrieval of that concept, where the item differs from the previous one. |
| Needs review | The most recent attempt failed or was revealed, the concept is overdue by more than its own interval, or a high-confidence answer was wrong. Overrides the display state until the next success. |

Assessment-pool results count toward Demonstrated/Retained; practice results count toward
Practiced/Demonstrated, and toward Retained only when the gap rule is met.

## Scheduler (design choice, see `src/domain/scheduler.ts`)

- Scheduling is per **concept**, not per question, so repeated reviews use different
  questions and wording cannot be memorised.
- Interval ladder in days: 1, 3, 7, 14, 30, 60, 120.
- Independent success: move up one step. If the review happened so late that the elapsed
  gap already exceeds the *next* interval, move up two steps (the longer gap was survived).
- Success with a hint: stay on the same step.
- Failure or reveal: move down two steps (minimum step 0) and become due the next day.
- High-confidence failure: drop to step 0.
- Early review (less than half the interval elapsed): recorded, but the step and due date
  do not advance.
- Item choice for a due concept: never the item used last time; prefer items never seen,
  then least recently seen; prefer a different question format from last time.
