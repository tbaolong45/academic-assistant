# F1h: move-cue and range fixes from the F1g review (builder + test writer)

Next, before P6 (both touch Moodle.swift). Spec: deadline-priority.md §2.3 (regex in a code block, plus the second net) and §2.2 rule 6 (range forms). **Copy the regex from the doc.** Source: `docs/reviews/F1g.md`.

## Builder

| # | Fix | File |
|---|-----|------|
| 1 | Replace `Moodle.moveCue` with the §2.3 regex. It takes every verb form, and "to/until/till" must be followed by a date *shape*; a bare number or ordinal never counts. | Moodle.swift |
| 2 | **Second net** (§2.3, about `Moodle.swift:621`): drop pre-cue dates only if at least one date was found at or after `cueEnd`. Otherwise ignore the cue: keep all dates, `moved = nil`. With this, a cue can never make a date vanish. | Moodle.swift |
| 3 | Ranges (§2.2 rule 6): only course-page and PDF items, only an explicit range form in their own title, span ≤ 7 days. The forms are "1-2 Dec", "Dec 1-2", "1 Dec – 3 Dec" / "Dec 1 - Dec 3" (with -, – or —), and "1 Dec to/until/till/through 3 Dec". Two separate dates are not a range. Posts and mail never get ranges. | Model.swift / Moodle.swift (`namedDays`) |
| 4 | P9 follow-up (F1g review #4): `Summarizer.targets` also skips events that `deadlines()` dedupes behind an assessment (`sameItem`, ±7 days). | Summarizer.swift |
| 5 | F1g review #5 (architect, revised) | A mark on a PDF date is pruned in a run where that PDF couldn't be read, so the item comes back unmarked. `documentEvents` returns how many PDFs it skipped (text unavailable, or > 300 MB); Store doesn't prune PDF-date marks when that count is > 0. | Materials.swift, Store.swift |

Backlog, not now: F1g review #6 (Restore clears by value). It needs two clusters with identical mark values, which is practically impossible.

## Test writer: cue cases (1 = cue, 0 = no cue)
- 1: "…approval to reschedule our Calculus 1 classes to Friday, 9 October 2026"
- 0: "The quiz on 20 Oct has moved to room 3" → result 20 Oct, moved nil (second net)
- 0: "Quiz moved to week 9"; "moved to room 3B"; "moved to the 3rd floor"
- 1: "Lab on Tuesday moved to the 3rd of December"
- 0: "the rescheduled lab is still on Tuesday, next to the library"
- 1: "moved from 20 Oct to 1 Nov"
- 0: "We will move to the new room on Tuesday"
- 1: "extended to 4 Nov"; "moved to the 1st of November"; "postponed until next Monday"; "changed to Wednesday 3 pm"; "The exam is pushing to 12/11"; "Quiz delays to 3pm"; "We are extending the deadline to Dec 3"; "The lab shifts to Thu"; "move tomorrow's office hours to today"; "Submission moved to 23.11"; "class moved to 10:30"
- 0: "grades changed to marks"; "moved to Satisfactory"; "changed to the monitor room"

## Test writer: ranges and P9
- "Quiz 1 on 1 Dec, Quiz 2 on 5 Dec" (PDF) → no range
- "Dec 1-2 National Day" → {1 Dec, 2 Dec}
- course-page "1-2 Dec National Day" + PDF "Dec 1 — National Day" → 1 card
- "1 Oct – 15 Dec" → no range (span too long)
- #5: a fixture where one marked PDF date's file is unreadable → the mark survives the run.
- P9: an announcement event deduped behind an assessment within ±7 days gets no summarizer request

Gate: the real-cache clusters stay as after F1g (5 clusters). Report any change before the commit.
