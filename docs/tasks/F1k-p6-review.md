# F1k: fixes from the P6 review (builder + test writer)

Next, now. Source: `docs/reviews/P6.md`.

## Builder

| # | From | Fix | File |
|---|------|-----|------|
| 1 | P6 #1 **High** | A failed or partial fast `mod_assign_get_assignments` call leaves `assignments` empty, and the merge keeps that, so every assignment card vanishes for up to 60 min. In `Moodle.merge`, keep the previous assignments for every ID the fast result didn't return. A deleted one may linger ≤ 60 min, the same as the deleted-forum note. | Moodle.swift |
| 2 | P6 #2 Medium | Messages, notifications and calendar/teacher events aren't carried over, so a failed or capped fetch drops them (and a message can be the only place a deadline was stated). Carry previous announcements and events missing from the fast result, of every source, not only `.moodle` posts and course-page dates. This includes a GENERAL made only of messages, notifications or events. | Moodle.swift |
| 3 | P6 #3 Medium | The 5-minute forward throttle compares against the slow sync's *start*, so a slow sync that ran longer than 5 min is followed straight away by another one. Compare against the time the slow sync *finished* (`lastSlowFinished`). | Store.swift |
| 4 | P6 #4 | `needsStatus` uses the raw cutoff and can miss an extension. Use the previous effective cutoff: `max(raw, previous effective cutoff)`. | Moodle.swift |

## Test writer
- #1: merge of a previous sync with 3 assignments and a fast result with none → 3 assignments kept. A fast result with 2 of them (one updated) → the updated one plus the third kept.
- #2: a previous `.message` announcement and a teacher event missing from the fast result → both kept, and a GENERAL of only messages survives.
- #3: a slow sync that started 10 min ago and finished 1 min ago → coming forward doesn't start another slow sync.
- #4: raw cutoff in the past, previous effective cutoff in the future (an extension), due 20 days ago → `needsStatus` true.
