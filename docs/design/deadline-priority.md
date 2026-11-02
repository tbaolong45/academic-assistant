# Design: deadline priority, dedupe, done/snooze, filters, speed (T3)

Status: approved, 2026-11-02 (decisions in §8). T4 findings folded in (§6).

Everything here applies to the macOS app only. `lib/dashboard.ts` has no priority logic, so nothing needs porting.

## 0. What changes, in one picture

```
Moodle sync ─┐
Outlook ICS ─┼─► Store.subjects ──► boardItems(subjects, marks)  (pure, Model.swift, run once per change)
School mail ─┤                        1. collect   (today's deadlines(), with no date window)
PDF dates ───┘                        2. cluster   (dedupe + supersede, §2)
                                      3. weigh     (weight + effort estimates, §1)
                                      4. mark      (done / dismissed / snoozed, §3)
                                    ► Store.board: [BoardItem]  @Published
                                        └─ WeekView, HomeView, sidebar badge, crunch: slice by date + filter (§4), rank by priority(now:)
```

Today every view calls `deadlines()` on every redraw. Under this design they all read one precomputed `Store.board`. Only `priority(now:)` (a few arithmetic operations per item) runs at render time, because it depends on the clock.

## 1. Ranking model

### 1.1 Weight (% of the course grade), first match wins

| # | Source | Shown as | Example |
|---|--------|----------|---------|
| 1 | Moodle weight (`weight > 0`) | `12%` | sample LA Assignment 2 |
| 2 | Syllabus rule (`exactWeight`) | `7.5%` | AI1110 Quiz 4 |
| 3 | % in the title (`percentInTitle`) | `8%` | "TED-Talk Script (8%)" |
| 4 | Type default (table below) | `~5%`, marked as an estimate | "Problem sheet 7" |

- **Spare syllabus item** (`exactWeight == 0`, e.g. Calculus Quiz 5 while 4 slots are already filled): use the part's per-item weight (7.5) with the reason "7.5% if it counts". The student can't know in advance which quiz will be dropped.
- **Type** comes from `Moodle.kind(nil, title)` for Moodle items.
  - **"final" and "midterm" mean a sit-down exam only when the title has no hand-in word.** The hand-in words are paper, report, essay, presentation, submission, script, slides, project, portfolio, video and draft.
  - The exception is a title that also says "exam".
  - Otherwise `kind` skips the final/midterm match and carries on, so "Final Project" → project and "Critical Writing - Final Paper - 14%" → assignment.
  - This is fixed inside `Moodle.kind`, so gradebook types, crunch and Do next agree.
  - In the cached data it changes 3 of 57 items (2 final → assignment, 1 final → project) and keeps the 1 real final and all 6 midterms.
  A text item (announcement, mail, PDF and so on) uses that type only when the title names one (quiz, midterm, final, mini-exam, project, lab). Otherwise it is **other**. A text item that Jev labels `exam` with no type word counts as a quiz.

| Type | Default weight | Effort (hours) |
|------|---------------:|----------------|
| Final | 30 | 15 |
| Midterm | 25 | 10 |
| Mini-exam | 10 | 5 |
| Quiz | 5 | 3 |
| Project | 10 | max(6, 1 h per %) |
| Assignment (Moodle) | 5 | clamp(0.5 h per %, 2, 12) |
| Lab | 2 | 2 |
| Other (text item, no type word) | 2 | 2 |

Effort uses the final weight from the first table, so "Project (30%)" needs 30 h. All numbers live in one `let` table in `Model.swift`. They are starting values for the user to approve (decision D1).

### 1.2 Urgency: least slack, scaled by weight

```
daysLeft   = (due − now) / 1 day
effortDays = effortHours / H           H = focused hours per day for one item, default 3 (D1)
slack      = daysLeft − effortDays     days you can still wait before starting
priority   = weight / max(slack, 0.25)
startBy    = due − effortDays
```

- The higher the priority, the sooner it's done. Ties go to the earlier due date.
- `max(slack, 0.25)` puts every "start now" item in one band, ordered by weight. Without it, an item that is already behind would rank above everything else.
- This keeps today's shape (weight ÷ time) and replaces "time left" with "time left after the work". A 30% project due in 10 days gets slack 0, so it beats a reading due tomorrow.
- **[T4]** The researcher is comparing heuristics. If T4 recommends something else, only `priority` and the reason wording change. The inputs (weight, effort, due date) stay the same.

### 1.3 Reason line (Do next chip, second line; full text in `DeadlinePreview`)

`<weight> · <when> · <effort> → <start>`

- `12% · due in 2 days · ~6 h of work → start today`
- `~5% est. · due tomorrow · ~2.5 h of work → start today`
- `8% · due in 4 days · ~4 h of work → start by Sat 31 Oct`
- `25% · exam in 4 days · ~10 h prep → start today`
- When behind (`slack < 0`): `24% · due in 3 days · ~12 h of work, behind by ~1 day`

Effort always reads "~N h of work", or "~N h prep" for exams (quiz, midterm, final, mini-exam). `~` always means estimate. `DeadlinePreview` names where the estimate came from ("no weight on Moodle; typical for an assignment"). The reason line is built by a pure `reason(now:)` in `Model.swift`, so it can be self-checked.

### 1.4 What Do next contains

Do next shows the top 3 open items by `priority`, due between now and 28 days ahead (the horizon is from T4, §6), excluding done, dismissed and snoozed items.

- Today it holds only work to submit (`toSubmit`). The whole point of effort is that exams need lead time, so I propose adding exams to Do next (**D2**).
- Crunch keeps today's rule (submit + exams).
- **Overdue work (B3 review #5):** an open assignment past its due date stays in Do next only while it can still be handed in **and** we still check its status:
  - With a cutoff: until the cutoff.
  - Without one (Moodle accepts late work forever): for **14 days past due**.
  - The 14 days aren't arbitrary. P6's `needsStatus` stops fetching the submission status after 14 days, so after that the app can't know the work is still open.
  - Afterwards the item stays on the board as overdue, and the student can dismiss it (B5).
  - This is a Do next rule, not a filter.

### 1.4.1 One weight everywhere (B3 review #4)

Card tags, the preview, the reason line, Do next and crunch all read `weighting`. Nothing reads the raw `Deadline.weight`, which can be a misleading `0%` when Moodle weights an item 0.

| `weighting.from` | Tag | Counts toward crunch's 30% |
|---|---|---|
| Moodle, syllabus, title | `12%` | yes |
| spare syllabus item | `≤ 7.5%` | no |
| typical (type default) | `~5%` | no |

- Crunch's "≥ 3 items in 48 h" rule still counts every item.
- Only its weight rule ignores guesses. Otherwise three typical estimates could add up to a fake crunch.

### 1.5 Worked examples

H = 3. Sample data, where `days(n)` = n days from launch:

| Item | w | Effort | Days left | Slack | **New** | Old |
|------|---|-------:|----------:|------:|--------:|----:|
| LA Assignment 2 | 12 | 6 h | 2 | 0 | **48.0** | 6.0 |
| AI Midterm (exam) | 25 | 10 h | 4 | 0.67 | **37.5** | not in Do next |
| LA Problem sheet 7 | ~5 | 2.5 h | 1 | 0.17 | **20.0** | 2.0 |
| Python Assignment 2 | 12 | 6 h | 6 | 4 | 3.0 | 2.0 |
| LA Reading: Strang §6.1 | ~5 | 2.5 h | 3 | 2.17 | 2.3 | 0.67 |
| Python Code review: PR #12 | ~5 | 2.5 h | 4 | 3.17 | 1.6 | 0.5 |
| Python Lab 3: asyncio drills | ~2 | 2 h | 2 | 1.33 | 1.5 | 1.0 |
| LA Final | 40 | 15 h | 48 | 43 | 0.93 | 0.83 |

New Do next: LA Assignment 2, AI Midterm, Problem sheet 7. Old: Assignment 2, then a tie at 2.0 between Python Assignment 2 and Problem sheet 7.

Real cases from CLAUDE.md, now = Mon 2 Nov 09:00:

| Item | w (source) | Effort | Days left | Slack | Priority |
|------|-----------|-------:|----------:|------:|---------:|
| Communication "Critical Writing - Final Paper - 14%" (13 Nov, D6) | 14 (title) | 7 h | 11.6 | 9.3 | **1.51** |
| Calculus Quiz 4, Tue 10 Nov | 7.5 (syllabus) | 3 h | 8.6 | 7.6 | 0.98 |
| Calculus Final Exam, 12 Dec | 35 (syllabus) | 15 h | 40.6 | 35.6 | 0.98 (ties go to the earlier date, so it ranks after Quiz 4) |
| Calculus Quiz 5, 24 Nov (spare) | 7.5 "if it counts" | 3 h | 22.6 | 21.6 | 0.35 |
| Calculus Final Project Report, 10 Dec | 5 (syllabus) | 6 h | 38.6 | 36.6 | 0.14 |
| Intro to AI / Linear Algebra items, Moodle weight 0, no % | ~type default | | | | ranked as estimates |

TED Script, as of Wed 28 Oct 09:00 (due Sun 1 Nov 23:59, so 4.6 days left; 8% from the title, 4 h): slack 3.3, so priority 2.4, start by Sat 31 Oct.

- Old model: `percentInTitle` gave 8/4.6 = 1.7.
- The announcement "TED Script due 1 Nov" no longer shows as a second card (§2).

## 2. Dedupe and supersede

### 2.1 Origin (finer than today's `CourseEvent.Source`)

Today mail, messages and news are all `.announcement`, and course-page text and PDFs are both `.document` (told apart only by the `detail` prefix "On the course page"). Add `enum Origin` and set it where events are made. The field is called **`via`**: `CourseEvent` already has `origin: String?`, the summarizer's source text, which `Summarizer.id` hashes, so renaming it would re-bill every AI title.

| Rank (high wins) | Origin | Made in |
|---|---|---|
| 1 | `moodleActivity` (assignment, graded assessment) | `deadlines()` |
| 2 | `moodleCalendar` (teacher event) | `Moodle.calendarEvents` |
| 3 | `outlookCalendar` | `OutlookCalendar.merge` |
| 4 | `news`, `message`, `mail` (one tier; the newest post wins inside it) | `Moodle.sync`, `SchoolMail.merge` |
| 5 | `coursePage` | `Moodle.sync` (materials text) |
| 6 | `syllabus` placeholder | `withSyllabus` |
| 7 | `pdf` | `MaterialStore.documentEvents` |

- Syllabus placeholders rank below course pages. They are typed in from a tentative schedule, and a real Moodle item already replaces them by name.
- New `CourseEvent` fields, **all optional** so the existing `moodle-cache.json` still decodes (a non-optional field would make the app open on sample data):
  - `via: Origin?` (on `CourseEvent` and `Deadline`). Old cached events have no `via`, so all code reads the computed `resolvedVia`:
    - `via` when it's set;
    - otherwise `.calendar` → `moodleCalendar`, `.outlook` → `outlookCalendar`, `.announcement` → `news`, and `.document` → `coursePage` when `detail` starts with "On the course page", else `pdf`.
    - The builder refined `.announcement`: `mail` when `origin` starts with "✉︎", else `news`. Old Moodle messages still map to `news`. That's harmless. All three share one rank, B5's marks don't exist yet, and every event gets its real `via` at the first sync after the upgrade.
    - F1's `isPDFDate` becomes `resolvedVia == .pdf`.
  - `posted: Date?` (the post or mail date; for an edited Moodle post, `max(created, modified)`)
  - `posted` is used for ranking (newest post wins). **Relative dates ("on Tuesday", "tomorrow") stay resolved against the post's creation date**, not the edit:
    - Moodle bumps `modified` for any edit, including a typo fix.
    - Resolving against it would move every "Tuesday" in an edited post by up to a week.
    - A real move ("moved to 4 Nov") is caught by the `moved` cue (§2.4) and usually carries an absolute date.
  - `moved: Bool?` (see 2.3)
  - `ref: String?` (stable source id: Moodle calendar event `id`, ICS `UID`, file url, material title)
- `AssignmentItem` gets `moodleID: Int?` (from `Assign.id`). `CalendarEvent` decodes `id`.

### 2.2 Same item?

Two items A and B are one cluster when all of these hold:

1. **Course.** Same subject. Or one side is GENERAL and they share ≥ 2 keywords.
2. **Words.** Let `k = keywords(mainPoint(title))` (today's `keywords`, plus the skip words "deadline", "submit", "submitted"). Then `|kA ∩ kB| ≥ min(2, |kA|, |kB|)`, with at least 1.
3. **Numbers agree.** Numbers come from the title after removing dates and percentages ("(8%)"). If both titles have numbers, the sets must be equal, so "Quiz 3" ≠ "Quiz 4" and "Assignment 1" ≠ "Assignment 10". If only one has a number, the pair still counts. (Today's `words()` drops digits, so this rule is needed.)
4. **Date window.** |dateA − dateB| ≤ 3 days. The exception is a `moved` item, which joins a cluster at any distance up to 30 days, but only clusters whose members were posted before it.

Clustering runs per subject over all items: union-find on pairs, with n ≈ a few hundred per course. Today's `sameItem` prefix rule and exact-title rule are kept as a fast path: either one alone counts as a match.

**As built (B4, approved by the architect 2026-11-03).** Each of these four refinements only blocks merges. They were found on the real cache:
- *Words:* cluster words also drop move-cue words, weekdays and function words (has, been, will, with, from, this…). Otherwise "Lab has been moved to Tuesday" and "Lecture has been moved to Tuesday" merge.
- *Separate submissions:* two `moodleActivity` items never merge.
- *Number sets:* a union that would put two different non-empty number sets in one cluster is refused, so a numberless "Quiz on Tuesday" can't chain Quiz 3 and Quiz 4.
- *Same source text:* the same non-nil `ref` (one PDF or course-page note) with different dates means different items, e.g. a schedule listing "Final Project Presentation" on 8 and 10 Dec. A real move inside one text is unaffected, because §2.3 already drops the "from" date.
- *Moved window:* the 30-day window opens only for a stated cue (`moved == true`). Jev's `class_change` still picks the date (§2.4) but within 3 days only, because Jev labels holidays ("no classes") `class_change`.
- *Fast path:* `sameItem` uses the same 3-day window; F1's interim ±7 days is gone.
- **Named days (F1e #2, B4 review #2):**
  - Let `days(x)` be the weekdays and explicit dates named in x's title or source sentence. For **course-page and PDF** items, use the title only: their "sentence" is often a whole calendar label or schedule table, which names every row's dates.
  - If both members have non-empty `days` and the sets don't overlap, they don't merge. The one exception is when the **newer-posted** member has a stated move cue and the older one has none, which is a supersede.
  - Weekdays never count as shared words.
  - So "No classes on Monday" / "No classes on Tuesday" → 2 cards. "Class moved to Tuesday" / "Class moved to Thursday" → 2 cards (both moved: ambiguous, so keep both). "Quiz 3 on Tuesday" then "Quiz 3 moved to Thursday" → 1 card dated Thursday.
  - Rationale: a vanished cancellation is worse than a duplicate.
- **Date window by source (F1g, replaces the general 3-day window; architect 2026-11-03).** Three rounds of review found wrong merges, all from one cause: any two items within 3 days could merge, and each guard patched one shape. The new rule:
  1. **Anchor pairs.** A pair where one member is a Moodle activity or an assessment (syllabus placeholders included) may merge within **3 days**. Their date is authoritative, and the posts talk about them.
  2. **Every other pair** (text↔text, calendar↔text, calendar↔calendar) merges only on the **same local calendar day or within 12 h**. Same day covers a time-less "1 Nov" (23:59) against "1 Nov 9 am".
  3. **Supersede.** The one exception to rule 2 is the existing supersede case: the newer-posted member has a stated move cue, up to 30 days.
  4. **No bridging.** Every two non-anchor members of one cluster must satisfy rule 2 or 3 *directly*. A union that would break this is refused, like the number-set and ref guards. So no third item can chain two calendar events, two days or two dates together, through a news post or through an anchor.
  5. The day-set, ref, calendar-ref and number guards stay as a second net.
- Against the existing checks:
  - B4 (a), (f), (h) are anchor pairs; (d) is a supersede; (b), (c), (e), (g) are unaffected.
  - F1e's cases all hold.
  - Review F1e-P9 #1, #2 (numeric, dotted and relative days included, since the dates differ), #3 and #4 become 2 cards.
- **What it gives up:** two posts about one event that give dates on different days without a move cue (a typo, or "31 Oct" against "1 Nov"). These now show as 2 cards, which is the agreed trade.
- **Known, accepted:** "Monday office hours cancelled" (28 Sep) and "Wednesday office hours continue as usual" (30 Sep) merge into one card, and the second shows only in the preview. It's low stakes, and splitting them would need wording polarity.

TED example: "TED-Talk Script (8%)" gives {ted, talk, script}. "TED Script due 1 Nov" gives mainPoint "TED Script due", so {ted, script}. Overlap 2 ≥ min(2, 3, 2) ✓, no numbers ✓, same day ✓. One cluster, and the Moodle assignment wins.

### 2.3 "Moved to": the newer date replaces the old one

`Moodle.mentionedDates` checks the sentence around each date for a move cue:

`(?i)\b(moved|postponed|pushed(?: back)?|extended|rescheduled|delayed|shifted|changed)\b[^.]{0,60}?\b(to|until|till)\b`

- If the cue matches and the date follows it, set `moved = true`.
- Dates in the same sentence before the cue ("moved **from 20 Oct** to 1 Nov") are dropped.
- Jev's `class_change` label also counts as moved, so wording the regex misses is still caught.

### 2.4 Which member shows, and with what date

- **Winner (title, kind, click target):** highest `resolvedVia` rank, then the newest `posted`.
- **Date:**
  - If the winner is a Moodle activity, use the Moodle (effective, **[T4]**) date. If a newer `moved` post disagrees by more than 12 h, the card shows a note: "⚠ post on Thu 29 Oct says moved to Sun 1 Nov". Moodle is where the work is submitted, so its date is not silently overridden (**D3**).
  - Otherwise, if any member is `moved`, use the date of the newest-posted `moved` member.
  - Otherwise, use the winner's date.
- **Weight:** the first weight found across the members, in §1.1 order. The TED announcement adds nothing; a PDF line "Final Paper (14%)" can give a weight to a weightless Moodle item.
- **Kept, not lost:** the cluster's other members appear in `DeadlinePreview` as "Also mentioned in: announcement (Thu 29 Oct), syllabus PDF".

The notification rule is unchanged: notifications are never a date source.

## 3. Done, dismiss, snooze

### 3.1 Stable identity

`Deadline.id` today contains the title and, for events, the date, so it changes when a date moves. New `memberKey` per source item:

| Item | Key |
|------|-----|
| Open Moodle assignment | `a:<moodleID>` (falls back to `a:<subject>/<title>` for old caches) |
| Graded assessment / syllabus placeholder | `g:<subject>/<assessment.id>` (already stable: `<course>-gi<id>`, `syllabus/AI1110/Quiz 4`) |
| Moodle calendar event | `c:<event id>` |
| Outlook event | `o:<UID>` |
| Text item (news, message, mail, course page, PDF) | `t:<subject>/<resolvedVia>/<ref or announcement key>/<sorted keywords>/<n>`, where n = the ordinal among same-keyword dates in that one source |

A **cluster's** identity is the set of its member keys. A mark applies to a cluster if any member key is marked. A new post that moves a date joins the cluster (§2.2), so it inherits the mark.

A placeholder needs no migration. When Moodle posts the real "Quiz 4" with a mark, it has a score and leaves the board anyway.

### 3.2 Storage

`~/Library/Application Support/AcademicAssistant/board-state.json`, written with `writeOwnerOnly` (T1):

```swift
struct Mark: Codable { enum State: String, Codable { case done, dismissed, snoozed }
    var state: State; var until: Date?; var itemDate: Date; var at: Date }   // itemDate = the cluster's date when marked
typealias Marks = [String: Mark]                                             // key = SHA-256 of memberKey (like kinds.json)
```

- Marking writes the mark under **every** current member key of the cluster.
- Pruning, after each sync: drop marks whose key no longer exists in any source and whose `itemDate` is more than 30 days past.

### 3.3 When the source changes after a mark

| Mark | The cluster's date moves by more than 12 h | The source says it's done (Moodle submitted or graded) | The item disappears |
|------|------|------|------|
| done | stays done | stays done | pruned later |
| dismissed | **comes back**, tagged "date changed" (the dismiss may have meant "this date is wrong") (D4) | done | pruned later |
| snoozed | comes back now, tagged "date changed" | done | pruned later |

Snoozed items come back at `until`. The menu offers: tomorrow 08:00, next Monday 08:00, and "2 days before due".

Moodle's own status only ever moves an item toward done. A manual "done" on an open Moodle assignment is allowed (handed in on paper), and Moodle never undoes it.

### 3.4 UI

- `DeadlinePreview` gets three buttons: Done, Dismiss, Snooze ▾.
- Cards and Do next chips get the same three as a right-click `contextMenu`.
- Marked items leave the board, Do next, Overview, the sidebar badge and crunch.
- They can be seen again, and unmarked, through the "Show hidden" filter (§4), so no separate undo is needed.

## 4. Filters

Pure value type in `Model.swift`, with `func apply(_ items: [BoardItem]) -> [BoardItem]`:

```swift
struct BoardFilter: Codable, Equatable {
    var group: DeadlineGroup = .all       // existing To submit / Events / All
    var courses: Set<String> = []         // subject ids; empty = all
    var types: Set<ItemKind> = []         // deadline, exam, class_change, event; empty = all
    var origins: Set<Origin> = []         // empty = all
    var hideUnsure = false                // D5
    var showHidden = false                // done / dismissed / snoozed, shown dimmed
}
```

- **Unsure**, meaning a cluster that has any of the following and no Moodle or calendar member:
  - only PDF members
  - only unclassified members (no Jev key or not yet classified)
  - a Jev label below 0.6 confidence

  This needs `kindConfidence: Double?` on `CourseEvent`, set in `labeled()` (`Classifier.swift`). Today's rule that low-confidence "info"/"grades" stay on the board still holds; they just count as unsure.
- **Placement (WeekView header):**
  - Keep the segmented `To submit / Events / All` picker.
  - Add a `Filter` `Menu` next to it: Courses ▸ (each subject, with its hue dot), Type ▸, Source ▸, a "Hide unsure" toggle and a "Show hidden" toggle.
  - Active filters show as removable chips below the header.
  - Counts in the picker reflect the other filters.
  - The filter is stored with `@AppStorage` as JSON. It's a view preference, not user data.
- **Do next and crunch** follow the course and unsure filters. They never show hidden items. Overview and the sidebar badge ignore the filters and only drop hidden items.

## 5. Speed

1. **Board computed once.**
   - `Store` gets `@Published private(set) var board: [BoardItem]`, recomputed in a `didSet` on `subjects` and on `marks`.
   - It covers all dates, not just a window. The views slice it by date: `WeekView` by its week, `HomeView` by 7 or 60 days, `App.swift` for the badge.
   - `BoardItem` stores `headline`, `hasContent`, `keywords`, `weight`, `weightIsEstimate` and `effortHours` as plain values. `mainPoint` and its regexes therefore run once per item per change, not on every redraw.
   - The sync's frequent `subjects =` assignments (about 6 per sync) each trigger one recompute. That's fine at this size, and the builder must not debounce it.
2. **Regexes compiled once.**
   - The six `NSRegularExpression`s in `mentionedDates` become `static let`. `NSRegularExpression` is immutable and documented as thread-safe, which matters because PDFs are parsed on a detached task.
   - `mainPoint` keeps its string regexes, since §5.1 already takes it off the redraw path.
3. **PDF text cache (in memory).**
   - `PDFCache`: a `Mutex<[FileKey: Entry]>` (Synchronization, available because the package targets macOS 15).
   - `FileKey = (url, size, modified)`. `Entry = (text, dates)`.
   - Both `documentEvents` and `mentions` read through it, so each PDF is parsed once per app run and again only when Moodle reports a new size or modified time.
   - It stays in memory on purpose. The app runs continuously, and writing course-PDF text to disk would add a new sensitive file for little gain.
4. **Bounded parallel calls.**

   | Work | Today | New limit | Why this limit |
   |------|-------|-----------|----------------|
   | `Moodle.sync`: per-course grades, contents and forum discussions | serial | 4 courses at once | It's a shared university server. Matches `URLSession`'s per-host default (6) with headroom. More than that risks looking like scraping or hitting throttles. |
   | `mod_assign_get_submission_status` | serial, about 30 calls | 4 at once | Same reason |
   | Jev classify | serial | 4 at once | Rate limits are unknown, so stay low (D7) |
   | Summarizer (3–5 sequential calls per item) | serial | 2 items at once | DeepSeek rate limit plus Jev retries |

   - Implementation: a `TaskGroup` that keeps N children running and adds the next item as one finishes.
   - Results are merged **in input order**, so subject order, hues and warnings stay deterministic.
   - On the first error the group is cancelled, while answers already received are kept and cached. That's today's `break` behaviour.
   - `soft` warnings are collected per child and appended in order.
   - IMAP mail stays serial. It's out of scope, and each message is a separate login.

## 6. Effective due date (from T4, `docs/research/T4-moodle-due-dates.md`)

Verified by the researcher against MOODLE_405_STABLE. All of these calls are in `moodle_mobile_app`, so a student token can make them.

| Item | Where it comes from | Rule |
|---|---|---|
| Assignment due date, with user/group **overrides** | `mod_assign_get_assignments` → `duedate`. Overrides are already applied (`update_effective_access($USER->id)`). | Read as today. |
| Assignment **extension** | `mod_assign_get_submission_status` → `lastattempt.extensionduedate`. The app already makes this call per assignment. | `effectiveDue = extensionduedate > 0 ? max(duedate, extensionduedate) : duedate`. This is Moodle's own rule (`renderer::get_time_remaining`). |
| Assignment **cutoff** | `mod_assign_get_assignments` → `cutoffdate`, overrides applied. Students get it over REST even though the HTML view hides it. | `cutoff > 0` → late submissions close at `max(cutoff, extensionduedate)`. `cutoff == 0` → late work stays open. |
| Quiz close, with overrides | `mod_quiz_get_quizzes_by_courses` → `timeclose`, with overrides already applied (`quiz_update_effective_access`) | Read as today; nothing to add. |

What changes:
- **Fields:**
  - `Moodle.Assign` decodes `cutoffdate`.
  - `SubmissionStatus.Attempt` decodes `extensionduedate`.
  - `AssignmentItem` gets `due` = effectiveDue and the optional new fields `cutoff: Date?` and `extended: Bool?` (true when the extension moved the date).
  - All new fields are optional, so old caches decode.
- **Reason line:**
  - "extended" when `extended`.
  - Past due but before the cutoff: "late until Fri 6 Nov", ranked as overdue (slack < 0).
  - Past the cutoff: the item leaves Do next and the board shows it as "closed".
- **Dedupe:** the extension date is the Moodle activity's date. T3 §2.4's rule (Moodle wins, with a ⚠ note) now compares against the *effective* date. A teacher post "extended to 4 Nov" for the whole class usually matches `duedate` once the teacher updates Moodle.

Considered and not adopted: T4 also proposed a different score, "slack-damped weight" `P = w / (0.5 + max(0, s) + 0.5·clamp(t/L, 0, 1))`, with its own defaults.
- It behaves like the approved formula (§1.2, D1): both rank by weight over slack.
- Its advantage is a smooth rise inside the work window instead of the 0.25-day floor.
- The user approved §1's formula and tables, so a switch would be a new decision. Revisit it if the floor's ties feel wrong in use.

**Adopted from T4: the Do next horizon.**
- Do next ranks candidates due within the next **28 days**, not just the board's week. Otherwise a 30% project due in 10 days never reaches the ranking.
- The week board itself is unchanged.

## 7. Implementation plan

**Prerequisite:** T1 lands first. It owns `Moodle.swift`, `Classifier.swift` and `SchoolMail.swift`, and provides `writeOwnerOnly`.

Each builder task is one reviewable diff. After each one, the test writer adds the listed checks to `SelfCheck.swift`, and `./macos/build-app.sh` must pass.

| # | Builder task | Files | Reuse | Test-writer checks (exact cases) |
|---|---|---|---|---|
| B1 | Board computed once + static regexes (behaviour-preserving) | Model.swift (`BoardItem`, `boardItems`), Store.swift, WeekView.swift, HomeView.swift, App.swift, Moodle.swift | `deadlines()` logic as-is | (a) For the sample `Subject.all`, `boardItems` sliced to [now, now+7d) gives the same ids and order as today's `deadlines(…, days: 7)`. (b) `mentionedDates("Quiz on 3rd October", …)` gives the same result as before. |
| B2 | Origin, identity and new optional fields | Model.swift, Moodle.swift (set via/posted/ref, decode `Assign.id`, `CalendarEvent.id`), Outlook.swift, SchoolMail.swift, Materials.swift | | (a) A `moodle-cache.json` written before B2 (a fixture string without the new fields) still decodes. (b) `memberKey` of an event is unchanged when only its date changes. (c) Two dates with the same keywords in one post get keys `/0` and `/1`. |
| B3 | Ranking + reason + effective due date (§6) | Model.swift, Moodle.swift (decode `cutoffdate`, `extensionduedate`), WeekBoardParts.swift (chip second line, preview text), WeekView.swift (Do next uses `priority`, exams included, 28-day horizon) | `percentInTitle`, `Moodle.kind`, `share` | With H = 3, now fixed: (a) every row of the sample table in §1.5 (priority to 0.1). (b) Weight order: Moodle 12 beats a title "(8%)"; syllabus 7.5 beats the title; neither gives `~5`, estimate = true. (c) Spare quiz (`exactWeight` 0) → 7.5 with "if it counts". (d) Reason strings exactly as in §1.3 for: 12% in 2 days → "start today"; 8% in 4.6 days → "start by Sat 31 Oct" (now = 28 Oct 09:00, due 1 Nov 23:59); slack −1 → "behind by ~1 day". (e) 30% project in 10 days ranks above a "~5%" item due tomorrow. (f) Do next includes a 30% project due in 10 days (the 28-day horizon), and excludes an item due in 29 days. (g) Effective due date: `duedate` 1 Nov, `extensionduedate` 4 Nov → due 4 Nov, `extended`; `extensionduedate` 0 → 1 Nov; an extension *earlier* than `duedate` → `duedate` (max). (h) Cutoff: now = 2 Nov, due 1 Nov, cutoff 6 Nov → overdue, reason contains "late until Fri 6 Nov"; cutoff 1 Nov 12:00 → leaves Do next; cutoff 0 → stays as overdue. |
| B4 | Cluster + supersede + move cue | Model.swift (`cluster`), Moodle.swift (`moved` in `mentionedDates`) | `keywords`, `mainPoint`, `sameItem` | (a) "TED-Talk Script (8%)" (Moodle, 1 Nov) + "TED Script due 1 Nov" (news) → 1 item, Moodle title. (b) "Quiz 3" + "Quiz 4" same day → 2 items. (c) "Assignment 1" vs "Assignment 10" → 2. (d) News on 20 Oct "Presentation on 27 Oct" + news on 25 Oct "Presentation moved to 3 Nov" → 1 item dated 3 Nov. (e) `mentionedDates("The quiz has been moved from 20 Oct to 1 Nov")` → one date, 1 Nov, `moved == true`. (f) Moodle assignment 1 Nov + newer post "extended to 4 Nov" → date stays 1 Nov, with the conflict note (if D3 holds). (g) Same keywords 10 days apart, no cue → 2 items. (h) A PDF line "Final Paper (14%)" gives weight 14 to a weightless Moodle "Final Paper" item. |
| B5 | Done / dismiss / snooze | new `BoardState.swift` (Marks, load/save via `writeOwnerOnly`), Model.swift (apply marks), Store.swift, WeekBoardParts.swift (buttons, context menu) | `Jev.id` for hashing | (a) Dismiss, then the date moves 2 days → visible, tagged "date changed". (b) Done, then the date moves → still hidden. (c) Snooze until T → hidden before T, visible at T. (d) A mark on member A applies after member B (a moved post) joins the cluster. (e) The board-state file is 0600 and its folder 0700. (f) Pruning drops a mark 31 days past with no source, and keeps one at 29 days. |
| B6 | Filters | Model.swift (`BoardFilter.apply`), WeekView.swift (menu and chips) | `DeadlineGroup.isIn` | (a) Empty filter = identity. (b) Course filter keeps only that subject. (c) `hideUnsure` drops a PDF-only cluster, a Jev 0.45 item and an unclassified item, and keeps a cluster with a Moodle member. (d) `showHidden` returns marked items with `hidden == true`. (e) Do next ignores the type and origin filters but obeys the course filter. |
| B7 | PDF cache + bounded parallel sync | Materials.swift, Moodle.swift, Store.swift | | (a) `PDFCache` returns the stored entry for the same key without reading the file (count reads with an injected loader), and re-reads after `modified` changes. (b) An order-preserving limited-concurrency helper on 10 inputs with random delays returns the outputs in input order and never runs more than 4 at once. (c) Live check: run `--moodle-check` from the app bundle before and after; the counts must match. |

- B1 can start right after T1.
- B2 must come before B4 and B5.
- B3, B4 and B6 are independent of each other once B2 is in.
- B7 is independent of B3–B6 and can go to a second builder if one is free.
- CLAUDE.md gets one concise update after B4 and after B7 (new caches/files, the regex-thread-safety note). I'll write it as the architect when they land.

## 8. Decisions (accepted by the user on 2026-11-02, relayed by the coordinator)

All seven were accepted with the recommended defaults:

- **D1:** the effort and default-weight tables in §1.1 and H = 3 focused hours per item per day are the starting values.
- **D2:** exams are in Do next, as items to prepare for.
- **D3:** when a newer post says a Moodle assignment moved, Moodle's date stays and the card shows a ⚠ note.
- **D4:** a dismissed item comes back when its date changes by more than 12 h.
- **D5:** "Hide unsure" is off by default.
- **D6:** the Communication final paper is due **13 Nov**.
- **D7:** concurrency is 4 for Moodle and Jev, 2 for DeepSeek.

B1 was dispatched to the builder and test writer on 2026-11-02.
