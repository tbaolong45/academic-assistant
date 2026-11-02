# T3 (Architect) + T4 (Researcher): design for better deadline processing

The goal for phase 2: the board and "Do next" should show what actually matters first, without duplicates or stale dates, and
the user should be able to clear and filter items. This phase is design and research only; no app code changes.

## Problems found in the current code (coordinator's read, 2026-11-02)

1. **Priority is effectively "earliest due first".** `Deadline.priority` = weight ÷ days left, and ungraded items count as 2%. MBZUAI's gradebook weights are mostly 0, so nearly everything counts as 2% and only the date matters. A 30% project due in 10 days ranks below a reading due tomorrow. Preparation time is ignored (an exam needs days, a form needs minutes).
2. **Text-derived items can't be cleared.** Dates found in announcements, PDFs, course pages, mail and Outlook can't be marked done, dismissed or snoozed. Wrong or finished ones stay on the board forever.
3. **Duplicates and stale dates.** Dedupe is only `sameItem` (one title is a prefix of the other) plus exact lowercase titles. "TED Script due 1 Nov" in an announcement and the Moodle assignment "TED-Talk Script (8%)" both show. When a newer post says a deadline "moved/postponed/extended to …", the older date isn't replaced.
4. **The due date may be wrong for this student.** Only `duedate` / `timeclose` are read; extensions, cutoff dates and quiz overrides are ignored (T4 finds out which are reachable).
5. **Filters are thin.** The board filters only by To submit / Events / All. There's no filter by course, type or source, and no way to hide low-confidence items (PDF-only, unclassified) or done ones.
6. **Speed.**
   - `deadlines()` (with the `mainPoint`/`hasContent` regexes) runs on every redraw of WeekView and HomeView.
   - `Moodle.mentionedDates` compiles its regexes on every call.
   - `MaterialStore.documentEvents` re-reads every PDF after each sync, and `mentions` does again on each preview open.
   - The Moodle sync and the Jev/DeepSeek calls run one at a time.

## Constraints

- **No per-course target grade.** The user decided it's too complex for now. The priority uses only data the app already has, plus the T4 findings.
- **Explainable.** Every item on "Do next" can show a one-line reason ("8% · due in 2 days · start today").
- **Pure and testable.** Ranking, dedupe and filtering are pure functions in `Model.swift`, self-checkable in `SelfCheck.swift`. No new dependencies.
- **User state stays local and owner-only.** Done, dismissed and snoozed live in a local file written with `writeOwnerOnly` (T1). Items need a stable identity that survives a re-sync and a moved date. Note that today's `Deadline.id` contains the title and, for events, the date.
- **Follow CLAUDE.md gotchas:** `@Local`, no `#Preview`/`@Test`, breakpoints from `GeometryReader`, Reduce Motion, the `WindowGroup` first.
- **Keep the existing rules:**
  - A syllabus placeholder in the past means awaiting a mark.
  - Jev "info"/"grades" below 0.6 confidence stay on the board.
  - Notifications are never used as a date source.

## T3: Architect, deliverable `docs/design/deadline-priority.md`

The design covers these parts:

1. **Ranking model:**
   - Weight inference when Moodle gives none, in order: syllabus → % in the title → type default, marked as an estimate.
   - Effort or lead time by type and weight.
   - The urgency formula (e.g. least slack: time left − effort still needed).
   - The reason line.
   - Worked examples using the sample data and the real cases in CLAUDE.md (TED Script, Calculus quizzes).
2. **Dedupe and supersede:**
   - How items from different sources are judged the same (keywords plus a date window).
   - Which source wins: Moodle activity > calendar > announcement/message/mail > course page > PDF.
   - How "moved to" in a newer post replaces an older date.
3. **Done, dismiss and snooze:** stable item identity, storage, and what happens when the source item changes after a dismiss.
4. **Filters:** course, type, source and confidence, plus hide-done; where they appear on the board.
5. **Speed:**
   - Compute the board once per data change in `Store`.
   - Compile the regexes once.
   - Cache PDF text by (url, size, modified).
   - Bounded parallel sync and AI calls, with a limit and the reason for it.
6. **Implementation plan:** files to change, and an ordered split into builder tasks and test-writer checks (with the exact check cases), sized so each can be reviewed alone.

- Use T4's findings. The coordinator forwards them when they arrive. Draft the parts that don't depend on them first.
- Don't edit app code, and don't edit `CLAUDE.md` in this task.
- Done when: the doc exists and you report a five-line summary plus the decisions you need from the user.

## T4: Researcher, report in your terminal (no repo edits)

1. **Effective due date for a student on Moodle 4.5** (check against the MOODLE_405_STABLE source, `*_returns()` and the external function definitions, not the wiki; cite file paths):
   - Which fields hold an assignment's per-student extension (`extensionduedate`) and cutoff (`cutoffdate`)?
   - Which web-service functions can a **student** token call to get them (`mod_assign_get_submission_status`, `mod_assign_get_assignments`, `mod_assign_get_user_flags`, …)?
   - For quizzes: does `mod_quiz_get_quizzes_by_courses` apply the user's override to `timeclose`, or which call does?
2. **Prioritising student deadlines:** a short, sourced comparison of simple, explainable heuristics (earliest deadline, least slack / least laxity, weight × urgency, effort estimates by assessment type). Recommend one formula that fits the constraints above. Keep it to about one page.
