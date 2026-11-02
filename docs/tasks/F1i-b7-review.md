# F1i: fixes from the B7 review (builder + test writer)

After F1h, before P6 (P6 also reshapes Moodle.sync). Source: `docs/reviews/B7.md`.

## Builder

| # | From | Fix | File |
|---|------|-----|------|
| 1 | B7 #1 **High** | A PDF updated on Moodle with the **same byte size** is never re-downloaded (`isSaved` compares size only), so the board keeps the old dates. This is older than B7, but B7's cache now hides it. After a download, set the file's modification date to Moodle's `timemodified`. `isSaved` then needs size **and** that date to match. *As built (approved by the coordinator):* the local modification date must be `>=` `timemodified`, not equal to it. Files saved before F1i carry their download time, so an exact match would re-download all 171 files once. A same-size update on Moodle is still fetched again. Blind spot: a copy the user edits locally isn't refreshed. | Materials.swift |
| 2 | B7 #2 | `PDFCache` keys on Moodle metadata only. Key it on the **local file** (size + modification date from the file system), so whatever is on disk is what gets parsed. A `size == 0` file never counts as saved. | Materials.swift |
| 3 | B7 #3 | Cancellation is swallowed: `soft` turns `CancellationError` into a warning, and `courseData` keeps calling after its group is cancelled. Rethrow `CancellationError` from `soft` (and the status closure), and call `Task.checkCancellation()` between `courseData`'s calls. | Moodle.swift |
| 4 | B7 #5 | Two first-time callers can parse the same PDF twice. Single-flight per key: the second caller awaits the first parse. Skip it if it isn't small. | Materials.swift |

Accepted: #4 (course data finished before a fatal invalid-token error is lost; the next sync refetches it).

## Test writer
- #1: a saved file with the same size but an older modification date than Moodle's `timemodified` → not saved, so it's re-downloaded.
- #2: the same path with a changed local file → re-parsed; a `size == 0` file → not saved.
- #3: `soft` rethrows `CancellationError`.
- B7 #7: the warnings order is the same for serial and parallel runs, and the `calls` counter increments once per call, failures included.
