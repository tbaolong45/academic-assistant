# F1b: fixes from reviews F1 and P4 (builder + test writer)

Next in the queue, right after P2 and before U3. Sources: `docs/reviews/F1.md`, `docs/reviews/P4.md`.

## Builder

| # | From | Fix | File |
|---|------|-----|------|
| 1 | P4 #1 **Medium** | A connection loss *during* a message (timeout, EOF → `.closed`) is never counted, so a mail that always kills the connection blocks every later mail on every sync. Count one failure for the in-flight UID, then stop the run. UIDs not yet attempted stay uncounted. | SchoolMail.swift |
| 2 | F1 #2 | The per-message mail saves still `try?`. Keep the first error and set `cacheNote` after the loop. | Store.swift |
| 3 | P4 #6 | Store's mail note: use `mail.note`, not a hand-built copy (skip if P2 already did). | Store.swift |
| 4 | F1 #4 | Re-entry throws a dedicated `MailError.busy`, not `.server("busy")` ("Gmail refused…" is misleading). | SchoolMail.swift |
| 5 | F1 #5 | Also protect two-digit-year dotted dates (`23.10.26`, `23.10.26 10.00`) from the phone scrub. | Classifier.swift |

Deferred, not in F1b: F1 #1 (the course page's endless Scores-tab ants, the AssessmentSheet spin and the board glow) stays in U4/U5 as planned. F1 #3 (course-page dates lost on a partial sync) goes to B2's Origin/merge. P4 #2 (a nil reply marks the mail seen) and #3 (failures never decay) are accepted as-is for now.

## Test writer (SelfCheck.swift)
- P4 #1/#5: a fixture that throws `.timeout` on UID 3 and then `.closed`. UID 3 gets one failure, the run stops, and 4 and 5 are not counted.
- P4 #4: `MailStore` encode → decode round-trip keeps messages, seen and failures.
- F1 #5: `23.10.26 10.00` is unchanged; `050 123 4567` is still scrubbed.
- F1 #6: the per-byte reader check must not print "(failed at 0)" when it passes.
- F1 #7: for F1 items 2–3, say explicitly in the check list that they can't be tested without the network.
