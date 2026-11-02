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
