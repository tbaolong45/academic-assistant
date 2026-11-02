# F1: fixes from reviews R1, B1, P1 (builder + test writer)

Goes into the queue right after U2 and before P4. P4 builds on the same IMAP connection, so the hang fix comes first.
Sources: `docs/reviews/R1.md`, `docs/reviews/B1.md`, `docs/reviews/P1.md` (finding numbers below refer to those files).

## Builder

| # | From | Fix | File |
|---|------|-----|------|
| 1 | P1 #1 **High** | A pending `send` can hang the session forever. Wrap `send` in `withTaskCancellationHandler { … } onCancel: { connection.cancel() }`, and cancel the connection in `deadline`'s timeout child before throwing. Add a hard `connection.cancel()` in `session`'s catch as a second net. | SchoolMail.swift |
| 2 | P1 #3 | Move the `isSafeCredential` guard into `IMAPConnection.open` (keep the one in `session`), so no path can build an AUTHENTICATE line from unsafe input. | SchoolMail.swift |
| 3 | P1 #4 | One command at a time on `IMAPConnection`: an `isBusy` guard (throw if re-entered) or a serial chain. | SchoolMail.swift |
| 4 | P1 #5 | `runMailCheck` "newly seen": compare only UIDs the second FLAGS fetch actually returned. | SchoolMail.swift |
| 5 | P1 #6 + R1 #7 | `MailError.badCredential` text: "The address or app password is empty or contains a control character". | SchoolMail.swift |
| 6 | R1 #1 | Phone scrub misses `050 - 123 - 4567`. Allow a separator run of up to 3 characters (space, `-`, `.`, `(`, `)`). | Classifier.swift |
| 7 | R1 #2 | Phone scrub eats dotted dates (`23.10.2026`, `23.10.2026-25.10.2026`, `23.10.2026 10.00`). A `d.m.yyyy` / `dd.mm.yyyy` pattern must never become `[phone]`: protect dates first, or exclude dot-only digit groups that form a valid date. | Classifier.swift |
| 8 | R1 #3 | CRLF defeats the signature cut. Normalise `\r\n` / `\r` to `\n` at the start of `scrubPersonal`. | Classifier.swift |
| 9 | R1 #6 | Caches: don't silently swallow a `writeOwnerOnly` failure. At least keep the data write and surface the chmod failure as a store note; no crash. Keep it small. | Classifier.swift, Summarizer.swift, SchoolMail.swift, Moodle.swift |
| 10 | B1 #1 Medium | Event-vs-assessment dedupe spans all dates. Only let an assessment or assignment hide an event when their dates are within ±7 days (B4's clustering replaces this later). | Model.swift |
| 11 | B1 #4 | Sidebar badge: compute `weekStart(of: .now)` once. | App.swift |
| 12 | R2 #1 **High** (confirmed by the architect) | Course-page and university-calendar dates vanish from the board after every sync. `Store.swift:123` strips all `.document` events, and `:58` carries old ones (course-page too) into the new sync. Use one predicate `isPDFDate(e)` = `.source == .document && !(detail ?? "").hasPrefix("On the course page")` at **both** lines (fixing only one duplicates them). B2's Origin replaces this later. Do it in the same pass as #10 (both touch Model/Store). | Store.swift (+ Model.swift if the predicate lives there) |
| 13 | R2 #6 | `Moodle.route` must skip the GENERAL subject. Today its code "GENERAL" matches any text containing "general", so "General Chemistry review" lands in GENERAL instead of the course. Text that names no course still falls back to GENERAL as before. | Moodle.swift |
| 15 | Proposal 5 (idle CPU), moved up from U5 | Remove the 60 fps `TimelineView(.animation)` at `CourseView.swift:466`; nothing may loop forever while a course page is open. Re-measure idle CPU with a course page open (target under 5 %). | CourseView.swift |
| 14 | R2 #3 | Board items unique by `id` before `ForEach` (keep the first, drop later duplicates). Full cross-source dedupe stays in B4. | Model.swift (`boardItems`) |

B1 #2 (board recomputed about 8× per sync) is P2's job ("one publish per sync"); don't fix it here.

Done when: `./macos/build-app.sh` passes, including the test writer's F1 checks. Report the self-check line and the files changed.

## Test writer (SelfCheck.swift)

- P1 #2: in check (f), feed a small literal reply split at **every** byte offset (`for cut in 1..<whole.count`), expecting `nil` until the tagged line arrives and then the identical literal. Use a multibyte (UTF-8) fixture for the 256 KB-cut check. Assert that `MailError.badLogin`'s description contains neither the fixture address nor the password.
- R1 #1/#2/#3: `050 - 123 - 4567` → `[phone]`. `23.10.2026-25.10.2026` and `23.10.2026 10.00` are unchanged. `"Submit.\r\n\r\nBest regards,\r\nDr. Jane Doe"` contains no `Jane`.
- R1 #5: a check that exercises `Jev.yesNo`'s scrubbing on both a String state and a dictionary state (test the pure helper the builder exposes; ask the builder for its name).
- B1 #3: a fixture subject with an event whose title starts with the name of an open assignment due **3 weeks** away. The event must still be on the board (fix 10). Its `headlineCache == mainPoint(title)`.
- F1-12: a subject with one course-page event and one PDF event, run through `applyDocumentDates([:])` (or the pure helper the builder exposes), keeps the course-page event and drops the PDF one. Applying the same sync twice doesn't duplicate the course-page event.
- F1-13: `Moodle.route("General Chemistry review", [GENERAL, CHEM101 "General Chemistry"])` → the CHEM101 index.
- F1-14: `boardItems` of subjects that produce two items with the same `id` → the ids are unique, and the first one is kept.
- P1 fixes 2–3: `IMAPConnection.open` with an unsafe credential throws before connecting (if testable without the network; otherwise skip and say so).
