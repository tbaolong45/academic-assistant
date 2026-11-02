# F1g: date window by source (structural merge rule) + P9 follow-up

Queued after U5. Spec: deadline-priority.md §2.2 "Date window by source (F1g)". Source: `docs/reviews/F1e-P9.md`.

## Builder

| # | Fix | File |
|---|-----|------|
| 1 | **Anchors** are Moodle activities and assessments, syllabus placeholders included; they keep the 3-day window. Two **non-anchor** members (text, calendar, Outlook, PDF, course page, mail) merge only when they fall on the same local calendar day or within 12 h, unless the newer one supersedes (a stated move cue, ≤ 30 days). | Model.swift |
| 2 | **Cluster invariant:** every two non-anchor members of a cluster must merge directly (same day or 12 h, or supersede). Refuse a union that breaks it, the same way as the number-set and ref guards. The day-set, ref, calendar-ref and number guards stay as a second net. | Model.swift |
| 3 | P9 follow-up (F1e-P9 #6): `Summarizer.targets` asks only for events that can reach a card, meaning `hasContent` true and not deduped behind an assessment. | Summarizer.swift |
| 4 | F1e-P9 #5: a comment explaining why the calendar guard needs both refs; it clears at the next sync. | Model.swift |
| 5 | B6 review #1 **Medium** | The clean-sync gate before pruning marks ignores Outlook, mail and PDF failures. Example: the Outlook fetch fails (offline), the calendar items are empty, marks on Outlook events are pruned, and the events come back unmarked. Prune only when every configured source succeeded this sync: Moodle with no warnings, Outlook fetched (or no link), mail fetched (or no account), and the PDF downloads and scan without failure. | Store.swift |
| 6 | B6 review #3 | Restore clears the mark under every key the mark was written under, not just the current cluster keys, so a member that left the cluster can't bring the mark back. | Store.swift / BoardState.swift |
| 7 | Gate finding A (architect, §2.3) | Replace `Moodle.moveCue` with the regex in deadline-priority.md §2.3. It accepts base and -ing forms, and "to/until" must be followed by a date word. On the cache it gains 2 real moves and removes 3 false cues. | Moodle.swift |
| 8 | Gate finding B (architect, §2.2 rule 6) | A range counts as "same day" on any day it names, but only when it comes from the item's own title and spans ≤ 7 days. | Model.swift |

**Gate before reporting done:** print each of the 6 current real-cache clusters' members (via, date, no titles) before and after, and list every merge that is lost. Expected losses are only non-anchor pairs on different days without a cue. If any lost merge looks like a real duplicate, report it to the coordinator before the commit.

The −7…+120-day title window (#7) stays, per the architect.

## Test writer
- "Class cancelled" Mon + Tue → 2 cards.
- "Quiz 3 on 23/10" + "Quiz 3 on 25/10" → 2.
- "Quiz tomorrow" posted Mon + "Quiz today" posted Wed → 2.
- "TED Script due 1 Nov" + "TED Script due 1 Nov 9 am" (both news) → 1.
- A Moodle "Seminar" activity on 21 Oct + calendar "Seminar" on 20 Oct (ref 41) and 22 Oct (ref 42) → the activity merges with at most one of them.
- P9: an event with `hasContent == false` gets no summarizer request.
- B4 (a)–(h) and every F1e case still pass.
- #7 cue cases: the AI1110 "reschedule our Calculus 1 classes to Friday, 9 October" → cue. "the rescheduled lab is still on Tuesday, next to the library" → no cue. "moved from 20 Oct to 1 Nov" → cue. "Quiz moved to week 9" → no cue. "We will move to the new room on Tuesday" → no cue. "extended to 4 Nov", "postponed until next Monday", "changed to Wednesday 3 pm" and "moved to the 1st of November" → cue.
- #8: course-page "1-2 Dec National Day" + PDF "Dec 1 — National Day" → 1 card; "Commemoration Day (30 Nov)" stays separate; a "1 Oct – 15 Dec" range absorbs nothing.
- B6 #1: a sync whose Outlook fetch failed prunes no marks.
- B6 #3: Restore on a mark, followed by a cluster split and re-join, shows the item unmarked.
- B6 #4: `doNext` and `crunch` output is identical when only group, types, origins or showHidden change.
