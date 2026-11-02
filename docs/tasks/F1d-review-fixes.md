# F1d: fixes from reviews B2 and F1c (builder + test writer)

Queued right after U4. Sources: `docs/reviews/B2.md`, `docs/reviews/F1c.md`.

## Builder

| # | From | Fix | File |
|---|------|-----|------|
| 1 | B3 note 2 (architect decision) | "Critical Writing - Final Paper - 14%" is typed as a *final*: 15 h of effort and `.exam` in `deadlines()`. In `Moodle.kind`, match `mid-?term` and `\bfinal\b` only when the title has no hand-in word (paper, report, essay, presentation, submission, script, slides, project, portfolio, video, draft), unless it also says "exam". Otherwise fall through, so "Final Project" → .project and "Final Paper" → .assignment. On the cached data this changes 3 of 57 items. | Moodle.swift |
| 1b | B2 #3 (architect: if cheap) | Count the memberKey ordinal `/n` only over events with `hasContent`, so a bare "Dec 8 — -" line can't shift it. | Model.swift |
| 1c | B3 review #3 **Medium** | Crunch still counts items past their cut-off (CLOSED), so it can warn about work Moodle no longer accepts. Add `!$0.isClosed(now:)` to the crunch filter (`WeekView.swift` ~29). | WeekView.swift |
| 1d | B3 review #4 (architect, deadline-priority.md §1.4) | Everything reads `weighting`, never the raw `Deadline.weight`. Card tags: `12%` for Moodle, syllabus or title weights; `≤ 7.5%` for a spare; `~5%` for a typical estimate. Crunch's ≥ 30% weight rule sums only known weights (Moodle, syllabus, title); spares and estimates add 0. The ≥ 3 items in 48 h rule still counts everything. | Model.swift, WeekBoardParts.swift, WeekView.swift |
| 1e | B3 review #5 (architect, §1.4.1) | An overdue open assignment stays in Do next until its cut-off, or, with no cut-off, for 14 days past due; after that it stays on the board as overdue. Use one shared constant for the 14 days; P6's `needsStatus` will reuse it. | Model.swift |
| 2 | F1c #1 | `classify` never triggers `summarize`: `classifying` is still true (it's cleared in a `defer`) when `summarize()` checks it. New announcements then wait about 5 minutes for their AI titles. Clear the flag before calling `summarize()`, or call it after the task ends. | Store.swift |
| 3 | F1c #2 | A cancelled *waiter* cancels the shared mail fetch. Only the owner may cancel `mailFetch`; waiters ignore their own cancellation. | Store.swift |
| 4 | F1c #3 | `disconnect` also cancels `mailFetch` and clears `summaryNote` and `classifierNote`. | Store.swift |

Noted, not fixed:
- B2 #1 (edited post re-resolves relative dates): **rejected by the architect**. Moodle bumps `modified` on any edit, typo fixes included, so "Quiz on Tuesday" would jump a week. Relative dates stay anchored to the creation date; `posted` is only for "newest wins", and real moves are B4's `moved` cue (deadline-priority.md §2.1).
- B2 #2: old mail maps to `.mail`, not `.news`; same rank, so harmless.
- F1c #4: the brief overlap on a quick reconnect is the accepted trade-off.

B3 review #6 and #7 are accepted.

## Test writer (SelfCheck.swift)
- F1d #1 (`Moodle.kind`): "Critical Writing - Final Paper - 14%" → .assignment; "Final Project Presentation" → .project; "Final Exam" → .final; "Final" → .final; "Midterm exam" → .midterm; "Final exam paper" → .final.
- F1d #1b: adding a bare-date event with the same keywords doesn't change the visible items' memberKeys.
- F1d #1c: crunch over a week holding one CLOSED assignment ignores it.
- F1d #1d: a weightless Moodle assessment's tag is "~N%", never "0%". A spare Calculus quiz's tag is "≤ 7.5%". A crunch of three ~5% items within 48 h fires on the count rule, but its weight is 0. A crunch of one 30% syllabus item still fires on weight.
- F1d #1e: due 13 days ago with no cut-off → in Do next. 15 days ago → not in Do next, still on the board. 20 days ago with the cut-off tomorrow → in Do next.
- B2 #4: a Moodle calendar event with `ref: "41"` gets key `c:41`; an Outlook item gets `o:<UID>`; `deadlines()` puts the same `memberKey` on the produced `Deadline`.
