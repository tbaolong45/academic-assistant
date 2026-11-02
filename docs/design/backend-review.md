# Backend review: faults, pipeline options, ranked proposals (T6)

Status: approved in part, 2026-11-02 (§5). R2's findings (the reviewer's fault hunt) aren't in yet; §2.4 will hold them.

Scope: `Moodle.swift`, `Store.swift`, `SchoolMail.swift`, `Outlook.swift`, `Materials.swift`, `Classifier.swift`, `Summarizer.swift`, `Notifier.swift` and the `deadlines()` / `crunch()` path. Line numbers were rechecked against the working tree on 2026-11-02, after the builder started B1.

## 1. Measurements

| What | Result | How |
|---|---|---|
| One full Moodle sync, wall time | **27.9 s and 16.8 s** (two runs) | `/usr/bin/time` on `--moodle-check`, run from inside `macos/build/Academic Assistant.app` |
| Same sync, CPU time | 0.6–0.7 s user + 0.1–0.2 s sys | same |
| Moodle calls per sync | **≈ 93 (estimate)** | Code paths times current counts: 11 fixed calls; 27 `mod_assign_get_submission_status` (one per assignment); about 13 course members × (grades + contents); about 26 forum discussion pages; a few conversations. Not instrumented, because T3 forbids code changes. |
| Calls per hour while the app runs | ≈ 1,100 (estimate) | 93 × 12 syncs per hour (5-minute timer) |
| Data held | 9 subjects, 27 assignments, 30 assessments, 85 announcements, 361 materials, 69 dated events, 49 mails, 380 Jev answers, 47 titles | counts from the owner-only caches; no content printed |
| Idle CPU of the running app (Overview open) | **35–45 %** of one core, 3 samples 2 s apart | `ps -o %cpu`. `sample` shows `TimelineView.UpdateFilter`, `CanvasDisplayList` and display-link updates on the stacks. |
| curl's IMAP fetch command | `UID FETCH 7 BODY[]` after a read-write `SELECT` | `/usr/bin/curl` 8.7.1 run against a local fake IMAP server that logs commands (no real account). The app fetches with the same URL form. |

**Conclusion:** sync time is almost entirely network round trips made one after another. CPU isn't the bottleneck; at idle, the animated background is.

## 2. Faults worth fixing

Severity: **High** = harms the user's data or trust. **Medium** = wrong or missing items, wasted paid calls, or battery. **Low** = edge case.

Verdict: **Confirmed** = reproduced or measured, or follows directly from the code with no other path. **Plausible** = the mechanism is in the code, but it wasn't observed in the user's data.

### 2.1 High

**H1. Reading school mail marks it as read in Gmail.**
- Where: `SchoolMail.swift:49`, with the fetch in `curl()` at `:16`.
- Scenario: forwarded mail arrives unread in Gmail. Within 5 minutes the app fetches it with `imaps://…/All Mail;UID=n`, which makes curl send `SELECT` (read-write) and then `UID FETCH n BODY[]`. `BODY[]` without `.PEEK` sets `\Seen`, so the user's Gmail shows the mail as read and they may never open it there.
- Verdict: **Confirmed** (fake-server log, §1).
- Fix:
  - Fetch with a custom command on the mailbox URL: `-X "UID FETCH n BODY.PEEK[]<0.262144>"`, then parse the literal out of the untagged reply.
  - The partial fetch (first 256 KB) also stops one big attachment from blowing the 60 s limit (M2).

### 2.2 Medium

**M1. Outlook and mail items vanish from the board during every sync, and their AI titles can be thrown away.**
- Where: `Store.swift:89–92` and `:177`.
- Scenario:
  - `apply(result)` publishes the Moodle-only subjects.
  - The Outlook and mail items come back only after `await addOutlookCalendar()` and `await addSchoolMail()`, which takes seconds. For that time they're missing from the published board. That's a flicker every 5 minutes, and anything that reads `subjects` in between sees them gone.
  - If a summarizer run ends in that window, `titles.filter { live.contains }` (`:177`) deletes their titles. Each one is re-made on the next run at 3–5 paid Jev/DeepSeek calls.
- Verdict: **Confirmed** from the code (the only path); not observed live.
- Fix: build the full subject list from every source first, then publish once (pipeline O1).

**M2. One slow or huge email stalls mail sync forever.**
- Where: `Store.swift:204–209`.
- Scenario: a 25 MB attachment can't be fetched in curl's `--max-time 60`. The error leaves the loop, the messages already fetched in `fresh` are dropped (they're saved only after the loop), and every sync re-downloads them and fails at the same message again.
- Verdict: **Confirmed** from the code.
- Fix:
  - Save after each message.
  - Fetch at most 256 KB (H1).
  - Record a UID that fails 3 times, so it's skipped.

**M3. Mail that can't be parsed is downloaded again on every sync.**
- Where: `Store.swift:205`.
- Scenario: `SchoolMail.parse` returns nil (no `Date:` header, or a format `rfc2822` doesn't know). The UID is never added to `mail`, so it isn't in `have`, so it's fetched again every 5 minutes, up to the `.suffix(200)` cap.
- Verdict: **Confirmed** from the code.
- Fix: keep a set of seen UIDs, parsed or not, inside the existing `mail.json`.

**M4. Idle CPU 35–45 % (battery).**
- Where: `Effects.swift:10`.
- Scenario: `TechBackground` redraws a full-window `Canvas` at 30 fps through `TimelineView(.animation)` whenever the window is visible, paused only under Reduce Motion.
- Verdict: CPU **measured**; the attribution to `TechBackground` is **plausible** (the sample shows `TimelineView` and `Canvas` display-link work, but no A/B run with it removed).
- Fix: T5 U2 deletes `TechBackground`. If T5 is delayed, pause it when the window isn't key.

**M5. An edited announcement keeps its original date.**
- Where: `Moodle.swift:595`.
- Scenario: a teacher edits a post to change a deadline. `Announcement.date` is `created`, so:
  - The edit is invisible to `Notifier` (its key is title plus date).
  - T3's "the newest post wins" would rank the edited post by its *old* date.
- Verdict: **Confirmed** from the code.
- Fix: read `timemodified` into a new optional `modified`. T3 B2's `posted` = max(created, modified). The notification on edit stays out of scope unless the user asks for it.

**M6. Everything is fetched again every 5 minutes.**
- Where: `Moodle.swift:120–272`, `Store.swift:68–76`.
- Scenario: about 93 calls per sync and about 1,100 per hour, even when nothing changed. That includes 27 submission-status calls for assignments already graded or long past, and full `core_course_get_contents` payloads for every course.
- Verdict: **Confirmed** (code); the counts are estimates (§1).
- Fix: O2 (tiers) and O3 (incremental), §3.

### 2.3 Low

| # | Where | Scenario | Verdict | Fix |
|---|---|---|---|---|
| L1 | `SchoolMail.swift:161` (merge → `mentionedDates`) | Quoted reply history ("On Mon, 26 Oct 2026 at 10:15, … wrote:", "From: … Sent: …") becomes a dated board item | **Plausible**: 2 of 49 cached mails contain quoted history | Cut the body at the first quote marker before date extraction |
| L2 | `Moodle.swift:451` | "Questions 1–10 may be skipped" → a 10 May date (`dayMonth` is case-insensitive, and "may" is a common word) | **Plausible**: 0 hits in the current cache | Match the month "May" case-sensitively, or require a year or ordinal |
| L3 | `Moodle.swift:171`, `:244` | A forum with more than 100 discussions loses the older ones (`perpage 100`, page 0 only) | Plausible | Fine for now; page only if a course gets there |
| L4 | `Materials.swift:21` | A file replaced on Moodle with the same byte size is never downloaded again | Plausible | Also compare `modified` (set the file's mtime from Moodle after download) |
| L5 | `Classifier.swift` `KindCache` | `kinds.json` is never pruned | Confirmed; 380 entries, 38 KB | None needed at this size |
| L6 | `Outlook.swift:59` | TZID times read as the Mac's zone are wrong after travel | Known (ponytail note) | Map the few Windows zone names when it matters |
| L7 | `Moodle.swift:588` | A message containing "communication" routes to the Communication course | Plausible | Prefer the code; match names only as whole words |

### 2.4 R2 (reviewer) findings

Pending. The coordinator will forward them; I'll mark each one confirmed or not here.

## 3. Pipeline and algorithm options

**Today:** sources are fetched one after another and published as they arrive (≈ 6 `subjects =` assignments per sync). The board is derived on every redraw. AI runs serially afterwards.

The four criteria: **latency** = time until fresh data shows; **flexibility** = ease of adding a source or rule; **efficiency** = API calls, cost, CPU and battery; **speed** = UI responsiveness.

| Option | What changes | Latency | Flexibility | Efficiency | Speed |
|---|---|---|---|---|---|
| **O1. Staged pipeline, one publish** | Each source returns a `SourceBatch` (Moodle, Outlook, Mail, PDF dates), fetched concurrently. A pure `normalize(batches, marks)` builds subjects plus the board: T3's collect → cluster → weigh → mark. `Store` publishes once. | = the slowest source, not the sum. Removes the M1 gap. | **High**: a new source is one producer plus an `Origin` case. Rules live in one pure function. | same calls; one board recompute instead of ~6 | no flicker; one SwiftUI update per sync |
| **O2. Tiered cadence** | Fast tier every 5 min: open or future assignments' status, calendar, news forums, messages, notifications, Outlook, mail. Slow tier every 60 min, on ⌘R, and when the window comes forward: grades, course contents, all discussions, downloads, PDF parse. Submission status only for assignments not yet graded whose due date is in the future or within 14 days past. | fast items unchanged; grades and files up to 60 min late (⌘R overrides) | medium: each source declares its tier | **≈ 93 → ≈ 25–35 calls per fast sync (estimate)**, so ~65–75 % fewer calls per hour | less background work |
| **O3. Incremental sync** | One `core_course_get_updates_since` per course (since the last sync). Refetch contents and grades only for courses that report changes. **[needs T4]**: confirm a student token may call it and what it reports on 4.5. | same as O2's fast tier, with no 60-min wait for changed courses | medium: the per-source "since" bookkeeping lives in the cache | idle sync ≈ 15–20 calls (estimate) | — |
| **O4. Bounded parallel fetch** (T3 §5.4) | TaskGroup with 4 concurrent Moodle calls, results merged in input order | **17–28 s → ~6 s (estimate:** ~93 calls × ~0.25 s ÷ 4) | none | same calls, shorter radio-on time | — |
| **O5. Rules first, then batched AI** | Local rules label the obvious items: Moodle activities → deadline/exam; "cancelled / no class / moved" → class_change; "grades released" → grades. Only the rest go to Jev, up to 10 texts per call (state = a dict of texts, one choice question each). | first-run classification much shorter | rules are code; Jev stays the fallback | today the cache already makes repeats free, so the gain is only on **new** texts (tens per week) | — |
| **O6. Persistent PDF index** | The parsed dates per (url, size, modified) saved to disk as well | parses saved once per launch | — | saves one parse per launch; the app rarely relaunches | none |

**Recommended pipeline: O1 + O4 now, O2 next, O3 once T4 confirms.** O5 and O6 aren't worth it at the current volume.

Fit with T3:
- O1's `normalize` stage *is* T3's `boardItems` (T3 §0), so this doc doesn't repeat T3's cluster, weigh and mark design.
- O4 is T3's B7.
- O1 is a small extension of T3's B1: B1 computes the board once; O1 also makes the sources feed it in one publish.

## 4. Optimisation proposals, ranked

All of these **need user approval**. Effort: S ≈ one small diff, M ≈ one or two builder tasks. The risk column says what could go wrong.

| Rank | Proposal | Why | Gain (measured or estimated) | Risk | Effort |
|---|---|---|---|---|---|
| 1 | **Fix H1**: `BODY.PEEK[]` with a 256 KB partial fetch | The app silently marks the user's school mail as read | no more mail marked read; also fixes M2's timeout cause | a mail longer than 256 KB loses its tail (the text part comes first in practice) | S |
| 2 | **O1: one publish per sync** | Fixes M1 (flicker, lost paid titles) and gives T3 one place to slot in | 1 publish instead of ~6; latency = slowest source | a larger refactor of `Store.sync`; do it straight after T3 B1 | M |
| 3 | **O4: bounded parallel Moodle fetch** (= T3 B7) | The sync is network-serial | 17–28 s → ~6 s (est.) | server throttling, hence the limit of 4; order-preserving merge keeps the results deterministic | S–M |
| 4 | **M2 + M3: mail progress** (save per message, record failed or unparseable UIDs) | Mail sync can stall forever or refetch the same messages | no repeated downloads | none worth noting | S |
| 5 | **M4: stop the 30 fps background** (T5 U2, or pause when the window isn't key) | Battery | 35–45 % idle CPU → near 0 (est.; re-measure after) | none | S |
| 6 | **O2: tiered cadence** + status only for live assignments | ~1,100 calls per hour for mostly unchanged data | ~65–75 % fewer calls (est.) | grades and files up to 60 min late; ⌘R and window focus refresh at once | S–M |
| 7 | **M5: announcement `timemodified`** | Edited deadlines must win in T3's supersede | correct newest post | none (an optional field) | S |
| 8 | **O3: incremental sync** | After O2, the remaining calls are mostly unchanged courses | idle sync ≈ 15–20 calls (est.) | depends on T4. If the function isn't callable or is unreliable, O2 alone stays. | M |
| 9 | **L1 + L2: mail quote cut, "May" matching** | Fewer false dates | small | could drop a real date written inside a quoted reply | S |
| 10 | O5 rules-first + batched Jev | Only new texts benefit | small at today's volume | batched answers might differ from single ones; would need an A/B test on the 380 cached labels first | M |

Not proposed: O6 (no measurable gain) and L3–L7 (fix when they occur).

## 5. Decisions (user, 2026-11-02, relayed by the coordinator)

- **Approved now:** proposals 1, 2, 3, 4, 5, 6 and 7. Build IDs and queue positions are in `ui-redesign.md` §8.

  | Proposal | Build ID |
  |---|---|
  | 1 | P1 |
  | 2 | P2 |
  | 3 | B7 |
  | 4 | P4 |
  | 5 | merged into U2 |
  | 6 | P6 |
  | 7 | merged into B2 |

- **Approved on condition:** proposal 8 (O3, incremental sync) once the researcher confirmed Q3. **Outcome: not built.**
  - T4 confirms a student can call it, but it is blind to manual grade items, extensions and overrides, section summaries and deletions.
  - So it can't replace a refetch and would only add about 13 calls per fast sync. See `ui-redesign.md` §8.1 P8.
- **Skipped:** proposals 9 and 10.
- **Q2:** up to 60 minutes' delay for grades and files is fine. ⌘R and bringing the window forward refresh at once.
- **Q3:** with the researcher. Can a student token call `core_course_get_updates_since` / `core_course_check_updates` on MOODLE_405_STABLE, and what does it report?
