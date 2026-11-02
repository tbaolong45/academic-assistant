# F1e: wrong merges from the B4 review (builder + test writer)

Queued after U1c and before P9, since P9 reads the clusters. Source: `docs/reviews/B4.md`. Rule: a vanished card is worse than a duplicate.

## Builder (Model.swift, `same` / `cluster`)

| # | From | Fix |
|---|------|-----|
| 1 | B4 #1 **Medium** | Two one-off calendar events with the same title merge (Moodle "Seminar" with ref 41 on 20 Oct and ref 42 on 22 Oct; two Outlook "Career Fair" events with different UIDs). If both members are `moodleCalendar`, or both `outlookCalendar`, and both refs are present and different, don't merge. A stated move cue can still allow it. |
| 2 | B4 #2 **Medium** | Titles that differ only in a weekday merge, because the skip list strips weekdays: "Class moved to Tuesday" / "Class moved to Thursday", "No classes on Monday" / "No classes on Tuesday". **Rule (architect, deadline-priority.md §2.2 As built):** let days(x) be the weekdays and explicit dates named in x's title or source sentence. If both members have non-empty days and the sets don't overlap, don't merge, unless the newer-posted member has a stated move cue and the older one doesn't (a supersede). Weekdays never count as shared words. |
| 3 | B4 #3 | The same-ref guard is pairwise, so a bridging item can chain one ref at two dates into one cluster. Keep a per-cluster `ref → date` map and refuse a union that puts one ref at two dates. |

B4 #4 (a Jev `class_change` label alone doesn't open the 30-day window) is an approved deviation (deadline-priority.md §2.2 "As built").

## Test writer
- #1: two Moodle calendar events "Seminar", refs 41 and 42, 2 days apart → 2 cards. The same pair for Outlook UIDs → 2 cards.
- #2: "Class moved to Tuesday" / "Class moved to Thursday" → 2 cards. "No classes on Monday" / "No classes on Tuesday" → 2 cards. The B4 TED/Presentation moved cases still merge. "Quiz 3 on Tuesday" (older) then "Quiz 3 moved to Thursday" (newer) → 1 card, dated Thursday; the same pair with the post order reversed → 2 cards.
- #3: a schedule PDF with "Final Presentation" (one ref) on 27 Oct and 6 Nov, plus a news mention on 1 Nov → the two PDF rows stay in different clusters.
