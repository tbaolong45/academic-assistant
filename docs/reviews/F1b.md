# F1b — fixes from F1 and P4

Reviewer: DeepSeek #2 (read-only). Date: 2026-11-02.
Spec: `docs/tasks/F1b-review-fixes.md` (5 builder items + test-writer list).
Snapshot: `SchoolMail.swift` md5 `964c9447f21796932ac02c083e1016ba` (23:53), `Store.swift` md5 `52989c09f21983db5b99ce85f734a323` (23:53), `Classifier.swift` md5 `8e420bf1711881726dcf4e8900a463b8` (23:53), `SelfCheck.swift` md5 `89acd50a8ad9a3b2fd2bf9fdb074f945` (23:52); `.build/release/AcademicAssistant` 23:54.
Verification: ran `.build/release/AcademicAssistant --self-check` → **2 check(s) failed**:
```
✘ mail: a failing fetch is counted and saved, and doesn't stop the run (got [1, 2])
✘ mail: a closed connection stops the run without counting a failure (got [1])
```
Both are the old P4 expectations, which F1b item 1 deliberately reverses; the new `dyingDownload` check passes. The tree is therefore not green for F1b yet.

## Focus answer — can one network blip count more than one UID?

**Inside one `download` run: no.**
- `SchoolMail.download` (`SchoolMail.swift:45-58`) increments `failures[uid]` once for the in-flight UID and, if the error is `.timeout` or `.closed`, saves and `break`s (`:52-54`); later UIDs are never attempted or counted.
- `IMAPConnection.deadline` (`:423-429`) marks the connection dead and rethrows any `MailError` unchanged; every non-`MailError` (NWError, POSIX, TLS, `CancellationError`) becomes `.closed`. So a transport blip is always `.timeout`/`.closed` at the `download` catch and always ends the run after the one increment.
- Protocol errors (`MailError.server` from `status`, `MailError.busy`) are not transport blips: `status` runs outside `deadline` after a valid reply, and `.busy` is thrown before `deadline` re-enters. They count the current UID and the loop continues (connection alive).
- `Task.isCancelled` is tested before counting (`:52`), so a cancelled run counts nothing.

**Two residual ways one blip can count twice**, neither within a single loop:
1. **Concurrent `fetchMail` sessions.** `Store.setMail` calls `fetchMail` (`Store.swift:255-258`) and the set-mail button is not disabled while syncing (`ConnectView.swift:207`; only "Sync now" is disabled at `:116`). A sync's `fetchMail` and a set-mail `fetchMail` then run two `download` loops on the same UIDs; one blip can increment the same UID in both (and both save/notify). Low; add single-flight or disable set-mail while `store.syncing`.
2. **Cancellation race.** `deadline` maps `CancellationError` to `.closed`; if the task is cancelled just after `download`'s `Task.isCancelled` check, the `.closed` branch counts one failure. A disconnect/app-quit near a fetch can therefore record one failure (three such races skip a mail). Check `Task.isCancelled` again in the `.closed` branch, or don't count when cancelled.
A `.closed` from `command`'s dead guard for a UID that was never attempted would also be counted; it is unreachable today because every transport error breaks the loop immediately, but the types do not distinguish "never attempted" from "in flight" (worth a comment/test if a future error is mapped to `.closed` without breaking).

## Findings

1. **High (verification, not code) — the self-check is red because the two old P4 download tests were not updated.** `SelfCheck.swift:560-579`. `failedDownload` still expects `[1, 2, 4, 5]` (continuing after `.timeout`) and `closedDownload` expects `failures.isEmpty`; F1b item 1 now stops after counting the in-flight UID, so they fail. Replace them with the new contract (the `dyingDownload` fixture at `:580-587` already covers "timeout counts one, later `.closed` stops, 4–5 uncounted") and keep one test for "one in-flight `.closed` counts one and stops". Until then `./macos/build-app.sh` cannot pass, so F1b's done criterion is unmet.

2. **Low — one blip can double-count a UID through concurrent `fetchMail`s.** See focus answer #1 (`Store.swift:255-258`, `ConnectView.swift:207`). Two sessions build from the same `start`, fetch the same UIDs, and both can count the in-flight one; failures can reach 3 in one blip. No data corruption (the later `mail = fetched` wins), but the skip-early threshold is reached twice as fast.

3. **Low — a cancellation can be recorded as a failure.** `deadline` maps `CancellationError` to `.closed` (`SchoolMail.swift:428`); `download` checks `Task.isCancelled` before the increment, but a cancel arriving between the check and the branch still increments. Minor; only affects a disconnect/quit at the exact moment of a fetch.

4. **Low (test gap) — the two-digit-year date check is missing.** F1b item 5 changed the guard to `(?:(?:19|20)\d\d|\d\d)` (`Classifier.swift:150`), which covers `23.10.26` and `23.10.26 10.00` by inspection, but `SelfCheck` only has the `050 123 4567` case (`:486-488`); no `23.10.26` fixture. The F1b test list asks for it. Also add the explicit note that items 2–3 cannot be tested without the network.

## Item check
- **1** `download` counts the in-flight UID once and stops on `.timeout`/`.closed`; `deadline` maps transport errors to `.closed` (`SchoolMail.swift:45-58`, `:423-429`). Behaviour matches the spec; the test file needs the update in finding 1. **Verified by code + the new `dyingDownload` check.**
- **2** The per-message `save` now captures the first error (`Store.swift:233-237`) and sets `cacheNote` after the loop only if the final `save {}` did not already set it (`:242-243`). No data path is lost: `writeOwnerOnly` writes before throwing, and the final save still runs. ✓
- **3** `mailNote = updated.note` (`Store.swift:244`); the hand-built copy is gone. ✓
- **4** `MailError.busy` with "The mail connection was already running a command" (`SchoolMail.swift:273`, `:285`); `open`/`command` throw it (`:331`, `:350`), no more "Gmail refused". ✓
- **5** Two-digit-year dotted dates are protected before the phone pass (`Classifier.swift:150-157`); the existing `050 123 4567` check passes (`SelfCheck.swift:486-488`). Test gap in finding 4.
- **6** `(failed at 0)` is gone: `splitAt` is optional and only printed when set (`SelfCheck.swift:464`). ✓
- **7** The "items 2–3 cannot be tested without the network" note is not in `SelfCheck`; the test-writer list asks for it. Low.
