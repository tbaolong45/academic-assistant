# F1j: fixes from the F1h and F1i reviews (builder + test writer)

After U6. Sources: `docs/reviews/F1h.md`, `docs/reviews/F1i.md`.

## Builder

| # | From | Fix | File |
|---|------|-----|------|
| 1 | F1h #1 **High (conditional)** | Marks saved before F1h have no `pdf` flag, so the PDF-skip guard doesn't protect them. When a PDF is unreadable, keep every mark whose `pdf != false` (unknown counts as possibly PDF). | BoardState.swift |
| 2 | F1h #2 Medium | The relative day word is picked without looking at the cue: "move today's office hours to tomorrow" gives today; "Quiz Tuesday moved to Thursday" gives Tuesday; "Quiz on 20 Oct moved to Thursday" gives 20 Oct with moved nil. Collect every relative word with its position, also when absolute dates exist, so dates after `cueEnd` are found. The second net only counts a post-cue date that builds a valid `Date`. | Moodle.swift |
| 3 | F1h #3 | `namedDays` adds range endpoints for every source and span. Restrict them to `.coursePage` / `.pdf` titles and ≤ 7 days, the same as `onDays`. | Moodle.swift / Model.swift |
| 4 | F1i #2 Medium | The PDF parse lock is global, so a main-thread `mentions` call can wait behind a whole scan. Make it per key: an in-flight map, so only a second caller of the same file waits. | Materials.swift |
| 5 | F1i #1 Medium | When Moodle reports `timemodified == 0`, a same-size change is missed. Re-download once whenever the timestamp is unknown and the local file wasn't stamped by our own download; record the stamp. Keep it small. Document the limit for a back-dated replacement in a comment. | Materials.swift |

## Test writer
- #1: an old board-state JSON (no `pdf` key) with a 40-day-old mark, plus a skipped PDF → the mark is kept.
- #2: "move today's office hours to tomorrow" → tomorrow, moved. "Quiz Tuesday moved to Thursday" → Thursday, moved. "Quiz on 20 Oct moved to Thursday" → that Thursday, moved. "today's quiz is moved to room 3" (a relative word only before the cue) → today, moved nil.
- #3: a news post "moved from 1 Oct to 15 Dec" adds no range days.
- #4: two different PDFs parse concurrently; the same PDF parses once.
- #5: `timemodified == 0` with a same-size unstamped local file → re-downloaded once, then saved.
