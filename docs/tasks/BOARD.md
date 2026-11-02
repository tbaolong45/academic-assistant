# Task board (owned by the coordinator, academic-assistant-9e)

Only the coordinator edits this file. Agents report status in their terminal; the coordinator updates the board.

| ID | Task | Owner | Files owned | Status |
|----|------|-------|-------------|--------|
| T1 | Security fixes S1–S4 (macOS) | Builder (Claude e9) | Notifier.swift, Classifier.swift, Summarizer.swift, SchoolMail.swift, Moodle.swift | done (+T1b: Summarizer scrubs whole origin) |
| T2 | Self-checks for T1 | Test writer (DeepSeek #1) | SelfCheck.swift | done (T2b origin-scrub check pending) |
| T3 | Design: deadline priority, dedupe, done/snooze, filters, speed | Architect (Claude de) | docs/design/deadline-priority.md | done; user accepted D1–D7 (recommended) |
| T4 | Research: effective due dates on Moodle 4.5; prioritisation heuristics | Researcher (Antigravity) | docs/research/T4-moodle-due-dates.md | done; folded into deadline-priority §6 |
| R1 | Review T1 + T2 diff | Reviewer (DeepSeek #2) | docs/reviews/R1.md | done → F1 |
| T5 | UI redesign proposal: blue primary, modern, 3 directions | Architect | docs/design/ui-redesign.md | done; user chose A Campus, system light/dark, macOS 26, new course hues |
| T6 | Backend audit, ≥3 pipeline options, ranked optimisations (each needs user approval) | Architect | docs/design/backend-review.md | done; user approved proposals 1–7 (8 after T4), 60-min slow tier OK |
| T7 | Research: macOS 26 design guidance, student-app patterns, accessible blues | Researcher | none (reports in terminal) | assigned (after T4) |
| R2 | Read-only backend fault hunt, feeds T6 | Reviewer | docs/reviews/R2.md | done; architect folding into backend-review §2.4 |
| P0 | Remove personal emails before the public push (ConnectView default Gmail; SelfCheck school address) | Builder + Test writer | ConnectView.swift / SelfCheck.swift | done |
| B1 | First build step of T3 (doc §7) | Builder + Test writer | per doc §7 | done |
| U1 | Campus tokens + new course hues | Builder + Test writer | Theme.swift, Model.swift | done (checks pending) |
| P1 | Gmail never marked read: built-in IMAP client | Builder | SchoolMail.swift | done; reviewed (docs/reviews/P1.md), 1 High → F1 |
| F1 | Fixes from reviews R1, B1, P1, R2 (15 items) | Builder + Test writer | see docs/tasks/F1-review-fixes.md | done (9b8a6f4); review pending |
| P2 | One publish per sync, sync generation, concurrent sources | Builder + Test writer | Store.swift, Summarizer.swift | built; checks (a),(b),(d) pending; (c) waits for the signing identity; (e) user-run, optional |
| F1b | Fixes from reviews F1, P4 (5 items) | Builder + Test writer | see docs/tasks/F1b-review-fixes.md | done (8a50e39), reviewed |
| U3 | Native sidebar, follow system appearance, macOS 26 | Builder | App.swift, Package.swift | done (8a50e39); screenshots wait for signing cert |
| B2 | Origin (`via`) on every dated item, memberKey | Builder + Test writer | Model, Moodle, Outlook, SchoolMail, Materials | done; B2 checks pending; review pending |
| F1c | Fixes from reviews P2, F1b (5 items, 2 Medium) | Builder + Test writer | see docs/tasks/F1c-review-fixes.md | done; checks pending; review pending |
| B3 | Priority + Do next (cutoffdate/extensionduedate, 28-day Do next) | Builder + Test writer | Model, Moodle, WeekView, WeekBoardParts | done; checks (a)-(h) pending; review pending |
| F1d | Fixes from reviews B2, F1c (4 items, 1 Medium) | Builder + Test writer | see docs/tasks/F1d-review-fixes.md | done (d962b69 + next commit); review pending |
| B4 | Cross-source dedupe (clusters), moved cue | Builder + Test writer | Model, Moodle, WeekBoardParts | done (e864d77); 4 deviations approved by architect (§2.2 As built); checks + review pending |
| F1e | Wrong merges from B4 review (2 Medium) | Builder + Test writer | Model.swift (see docs/tasks/F1e-review-fixes.md) | next (before P9); #2 rule decided |
| P9 | Skip AI titles for members hidden behind a Moodle-activity winner | Builder + Test writer | Summarizer.swift, Model.swift | APPROVED by user 2026-11-03; build after U1c |
| B5 | Marks (done/dismiss/snooze) keyed by memberKey | Builder + Test writer | BoardState (new), Model, Store, WeekBoardParts | done; checks + review pending |
| U1c (build) | Dark retune | Builder | Theme.swift | done; palette checks (a)-(e) pending; screenshots wait for cert |
| U4 | Overview + Deadlines restyle, endless-animation removal | Builder | HomeView, WeekView, WeekBoardParts | done (code); screenshots + idle CPU wait for signing cert |
| U1c | Dark mode: brighter, more contrast, livelier hues (user request) | Architect → Builder | ui-redesign.md, then Theme.swift | APPROVED by user 2026-11-03 (as previewed); build after B5 |
| P4 | Mail progress: per-message saves, retry cap, skipped-date count | Builder + Test writer | SchoolMail.swift, Store.swift | done; checks (c),(e) pending; review pending |
| G1 | Entire + GitHub: public code repo, private checkpoints repo | Coordinator | git config, .entire/ | done: github.com/tbaolong45/academic-assistant (public), Entire mirror aws-ap-south-1 |

Decisions from the user (2026-11-02):
- Grade notifications must not show the score.
- Personal details (email addresses, phone numbers, signatures) are removed before any text goes to Jev or DeepSeek.
- No per-course target grade in the priority model (too complex for now).
- Phase 2 (building the new priority/filters/dedupe) starts only after the user has seen the T3 design.
- UI: the terminal look goes. Blue is the main colour, with a modern design; the user picks one of T5's three directions before building.
- Optimisations: each one is proposed with its reason and its effect on latency, flexibility, efficiency and speed, and the user approves it before it's built.
- T5: direction A "Campus", follow system appearance, deployment target macOS 26, courses use green/orange/yellow/magenta/violet (blue reserved for UI).
- T6: approved proposals 1 (Gmail BODY.PEEK), 2 (one publish per sync), 3 (parallel Moodle ×4), 4 (mail progress), 5 (idle CPU), 6 (tiered cadence, 60-min slow tier), 7 (announcement timemodified); 8 (incremental sync) after T4 confirms; 9–10 skipped.
- GitHub: code repo public (tbaolong45/academic-assistant); Entire checkpoints in a separate private repo.
- Build queue: docs/design/ui-redesign.md §8 (merged U/B/T6 steps), owned by the architect.
- P8 (incremental sync): not built. core_course_get_updates_since misses manual grades, extensions and overrides, so it can't replace the refetches (T4 §3.3).
- Reports: reviewer → docs/reviews/<ID>.md, researcher → docs/research/<ID>.md (report folders only, no code).
- Git: only the coordinator commits and pushes, at green points (build-app.sh + self-check pass). Agents never commit, push or rewrite history.
- Commits: stage only the files the finished step lists (never `git add -A` while the builder is mid-step).
- User 2026-11-03: U1c dark retune approved as previewed (dark labels on blue). P9 (skip titles for posts hidden behind a Moodle card) approved.
