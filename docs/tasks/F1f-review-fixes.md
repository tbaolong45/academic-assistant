# F1f: B5 review fixes, done inside the B6 pass (same files)

Source: `docs/reviews/B5.md`.

| # | From | Fix | File |
|---|------|-----|------|
| 1 | B5 #1 **Medium** | A partial sync (any `result.warnings`: a course's grades or contents call failed, status unavailable) builds the board without that course, and `pruneMarks` then drops its live marks. Prune only after a sync with **no** warnings. | Store.swift |
| 2 | B5 #2 | Prune after the PDF scan has run for this generation, not before it, so PDF-only marks are live. | Store.swift |
| 3 | B5 #4 | "Date changed" also shows on Do next chips and in the preview, with an icon next to the label (U4 rule). | WeekBoardParts.swift |
| 4 | B5 #8 | "Monday 08:00" on a Monday before 08:00 means *next* Monday. Prune drops marks *more than* 30 days past, so exactly 30 days is kept. | BoardState.swift |
| 5 | F1e follow-up (architect, deadline-priority.md §2.2) | `days(x)` comes from the title only when `resolvedVia` is `.coursePage` or `.pdf`; otherwise from the title plus the source sentence. A range like "1-2 Dec" gives {1 Dec, 2 Dec}, or at least its first day. This splits "Commemoration Day (30 Nov)" from "UAE National Day (1-2 Dec)". | Model.swift / Moodle.swift (`namedDays`) |

Accepted as-is:
- #3: `live` means "on the board". An item that leaves the board is pruned after 30 days.
- #6: snooze expiry is recomputed at the next publish.
- #7: when two members of a cluster carry different marks, the newest mark wins.
- #5: undo is B6's Show hidden.

## Test writer
- #1: a sync result with warnings leaves every mark in place.
- #3: a dismissed item whose date moved shows "Date changed" in Do next.
- #5: "Commemoration Day (30 Nov)" + "UAE National Day (1-2 Dec)" from one course-page label → 2 cards; the same two as PDF rows → 2 cards; "Quiz 3 on Tuesday" then "Quiz 3 moved to Thursday" (news) → still 1 card.
- #4: `snoozeOptions` on a Monday at 07:00 → next Monday 08:00. A mark exactly 30 days old is kept; one 31 days old is dropped.
