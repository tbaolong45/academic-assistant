# F1c — fixes from P2 and F1b

Reviewer: DeepSeek #2 (read-only). Date: 2026-11-03.
Spec: `docs/tasks/F1c-review-fixes.md` (6 builder items + test-writer list). Accepted deviation: a stale/cancelled AI run still saves its content-keyed titles/labels but skips prune and publish.
Snapshot: commit `0eb85e5` (00:07); `Store.swift` 50-line diff, `SchoolMail.swift` 3-line diff, `Resources/Info.plist`. `.build/release/AcademicAssistant` 00:07; app bundle rebuilt 00:07 with `LSMinimumSystemVersion 26.0`.
Verification: `--self-check` → **All checks passed**, including the new cancelled-download and `23.10.26` checks; B2's checks also pass. No live sync.

## Accepted deviation — verified
- `classify` saves `KindCache` before the generation/cancel guard (`Store.swift:172-175`); labels are content-keyed, so keeping them is safe; no `publish`/`summarize` after a stale/cancelled run.
- `summarize`'s stale/cancelled branch saves the unpruned `titles` and returns (`Store.swift:205-210`); the normal branch prunes against the subjects the run started from, saves and publishes (`:211-213`). This is exactly the accepted behaviour.

## Findings

1. **Low — `classify` never actually triggers `summarize`.** `Store.swift:164-177` with the guard at `:183`. The task does `defer { classifying = false }` at `:165` and calls `summarize()` at `:177`; `defer` runs only when the closure exits, so `classifying` is still `true` when `summarize` checks `!classifying` and returns. Consequence: after a sync that classifies new announcements, AI titles are not generated until the **next** sync's `scanDocuments` runs `classify()` (which returns early when there is nothing new) and then `summarize()` — about 5 minutes later; quitting before that leaves the titles for the next launch. Pre-existing, not introduced by F1c, but this is the code F1c reshaped; fix by clearing `classifying` before the `summarize()` call (or calling it after the task ends).

2. **Low — a cancelled waiter cancels the shared mail fetch.** `Store.swift:234-239`. Both `sync` and `setMail` go through the single-flight `fetchMail`; every waiter wraps `await task.value` in `onCancel: { task.cancel() }`. Scenario: the Connect sheet is dismissed (its task cancelled) while a sync's mail fetch is running; the waiter cancels the shared task, so the sync's fetch returns nil and the mail update waits for the next sync. Data stays consistent, but the owner should be the only one that cancels the shared task (or waiters should ignore their own cancellation).

3. **Low — `disconnect` can leave a standalone mail fetch running and a stale note re-appears.** F1c clears `mailNote`/`outlookNote`/`downloadNote` at `Store.swift:378-380`, but a `fetchMail` started by `setMail` (not through `syncTask`/`autoSync`) is not in `mailFetch`-cancelling code; it can finish after the disconnect and set `mailNote`/save `mail` again. `summaryNote`/`classifierNote` are also not cleared. Nothing reaches `subjects` (publish is gated), so this is cosmetic; cancel `mailFetch` in `disconnect` and clear the two AI notes for consistency.

4. **Low — `disconnect` sets `syncing = false` while the cancelled sync is still unwinding.** `Store.swift:376`. A quick reconnect can start a new `sync()` before the old cancelled one has exited; the generation gate keeps the old result from publishing, but two network sessions (Moodle/mail) can overlap briefly. This is the trade-off that prevents a permanently disabled "Sync now"; note it rather than change it unless the overlap shows up in measurements.

## Checked and correct
- **#1 generation/prune:** `classify`/`summarize` capture `generation` (`:163`, `:191`); both skip publish/prune when it changed or the task is cancelled; `disconnect` cancels `classifyTask`/`summarizeTask` (`:374-375`). The sample-prune path from `P2.md` is closed (also protected by `lastSynced != nil` guards at `:158`, `:183`).
- **#2 no AI on sample:** `init` passes `scanFirst: cache != nil` (`:63-64`); `classify`/`summarize` require `isConnected && lastSynced != nil` (`:158`, `:183`). A no-cache launch no longer scans or sends sample announcements to Jev; the first real scan happens after the sync's `use` (`:126`).
- **#3 notes/flags:** `disconnect` resets `syncing`, `downloading`, `mailNote`, `outlookNote`, `downloadNote` (`:376-380`) and leaves `mail`/`calendarItems` alone as specified.
- **#4 single-flight mail:** one `mailFetch` task (`:235-239`); a set-mail check waits for the sync's fetch or reuses its result; the double-count window in `F1b.md` is closed.
- **#5 cancellation:** `download` checks both `Task.isCancelled` and `error is CancellationError` (`SchoolMail.swift:52`); `deadline` maps cancellation to `CancellationError` before the transport `.closed` mapping (`SchoolMail.swift:423-429`). The new cancelled-download check passes, and a cancellation can no longer be counted as a failure.
- **#6 Info.plist:** `LSMinimumSystemVersion` is `26.0` in `Resources/Info.plist` and in the rebuilt bundle; matches `Package.swift` `.macOS(.v26)` (U3 finding 2 fixed).
- **Test writer:** `23.10.26`, `23.10.26 10.00`, the cancelled download and the "failed at" label are covered; B2's checks stay green. The generation-prune and single-flight behaviour are untested (the spec allows a manual check for #1; mention both in the report).
