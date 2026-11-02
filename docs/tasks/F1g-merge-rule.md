# F1g: date window by source (structural merge rule) + P9 follow-up

Queued after U5. Spec: deadline-priority.md §2.2 "Date window by source (F1g)". Source: `docs/reviews/F1e-P9.md`.

## Builder

| # | Fix | File |
|---|-----|------|
| 1 | **Anchors** are Moodle activities and assessments, syllabus placeholders included; they keep the 3-day window. Two **non-anchor** members (text, calendar, Outlook, PDF, course page, mail) merge only when they fall on the same local calendar day or within 12 h, unless the newer one supersedes (a stated move cue, ≤ 30 days). | Model.swift |
| 2 | **Cluster invariant:** every two non-anchor members of a cluster must merge directly (same day or 12 h, or supersede). Refuse a union that breaks it, the same way as the number-set and ref guards. The day-set, ref, calendar-ref and number guards stay as a second net. | Model.swift |
| 3 | P9 follow-up (F1e-P9 #6): `Summarizer.targets` asks only for events that can reach a card, meaning `hasContent` true and not deduped behind an assessment. | Summarizer.swift |
| 4 | F1e-P9 #5: a comment explaining why the calendar guard needs both refs; it clears at the next sync. | Model.swift |

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
