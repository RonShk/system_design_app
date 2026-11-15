# Progress and next actions

The backlog with acceptance criteria is in
[GitHub Issues](https://github.com/RonShk/system_design_app/issues). This file records
where the project stands so a new session can resume without the chat history.

## Working notes for whoever resumes

- Default branch: `main`. Work happens on focused branches merged by pull request.
- On the original development Mac, `git` writes and `gh` need to run outside the Claude
  Code sandbox, and npm needs `npm_config_cache=$TMPDIR/npm-cache`.
- Decisions: [DELIVERY.md](DELIVERY.md) (PWA + Web Push from GitHub Actions),
  [LEARNING_DESIGN.md](LEARNING_DESIGN.md) (evidence → mechanics).

## Milestones

| # | Milestone | Status |
|---|---|---|
| 1 | Repository inspection, learning research, delivery decision | Done |
| 2 | Curriculum map and content schema | Not started |
| 3 | Vertical slice: lesson → practice → delayed review, persisted | Not started |
| 4 | Notifications and installation path | Not started |
| 5 | Full curriculum, assessments, case studies | Not started |
| 6 | Content audit, functional tests, phone-size checks | Not started |
| 7 | Deployment and handoff | Not started |

## Next concrete actions

1. Scaffold the app and CI (#3).
2. Content schema and validator (#4), then the coverage matrix (#5).
