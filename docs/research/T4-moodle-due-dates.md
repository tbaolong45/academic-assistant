   Task T4 Research Report (Q1, Q2 & Q3)

  No repository files were edited (git checkout untouched). All Moodle 4.5 claims below are [Verified]
  directly against the MOODLE_405_STABLE branch source (db/services.php, db/install.xml, db/access.php,
  externallib.php, classes/external*.php, locallib.php, lib.php, and course/format/classes/local/*),
  never the Moodle wiki. Design syntheses and codebase implications are explicitly marked [Inferred].
  ──────
  ## Q1. Effective Due Date for a Student on Moodle 4.5

  ### 1.1 Assignments (mod_assign): Overrides vs. Extensions vs. Cutoff ([Verified])

  Moodle 4.5 stores per-student assignment deadline adjustments in two separate tables defined in
  mod/assign/db/install.xml
  https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/db/install.xml#L19-L167:

  1. User/group overrides ({assign_overrides}, mod/assign/db/install.xml#L149-L167 https://github.
  com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/db/install.xml#L149-L167):
      • Nullable allowsubmissionsfromdate, duedate, cutoffdate, timelimit keyed by assignid + (userid or
      groupid, sortorder).
      • Merged into $assign->get_instance($userid) by assign::update_effective_access($userid) →
      assign::override_exists($userid) (mod/assign/locallib.php#L996-L1072 https://github.
      com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/locallib.php#L996-L1072, #L1818-L1854
      https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/locallib.php#L1818-L1854): user
      override > winning sortorder group override > {assign} default (after relative course dates in
      calculate_properties()).
  2. Individual extension ({assign_user_flags}.extensionduedate, mod/assign/db/install.xml#L129-L139
  https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/db/install.xml#L129-L139):
      • INT(10) (default 0), granted from the grading table (assign::save_user_extension(),
      mod/assign/locallib.php#L6998-L7027 https://github.
      com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/locallib.php#L6998-L7027).
      • update_effective_access() never reads {assign_user_flags} and does not mutate duedate or
      cutoffdate.
  3. Moodle's own effective-date rules ([Verified]):
      • Effective on-time due date (renderer::get_time_remaining(),mod/assign/classes/output/renderer.
      php#L1307-L1308 https://github.
      com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/classes/output/renderer.php#L1307-L1308):


    effectiveDue = (extensionduedate > 0) ?  max(duedate,  extensionduedate) : duedate

  • Effective hard lock / cutoff (assign::submissions_open(), mod/assign/locallib.php#L6288-L6318
  https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/locallib.php#L6288-L6318):
  If cutoffdate > 0, submissions close at finalDate = max(cutoffdate,  extensionduedate) (unless locked);
  if cutoffdate == 0, late submissions stay open indefinitely unless locked. (Moodle's HTML STUDENT_VIEW
  hides cutoffdate at renderer.php#L788-L795 https://github.
  com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/classes/output/renderer.php#L788-L795, but REST
  returns cutoffdate to students.)

  ### 1.2 Which mod_assign Web Services a Student Token (moodle_mobile_app) Can Call ([Verified])

  Checked against mod/assign/db/services.php
  https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/db/services.php,
  mod/assign/db/access.php
  https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/db/access.php, and
  mod/assign/externallib.php
  https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/externallib.php:

   Web-service function │ In moo… │ Student… │ Date/lock fields returned (*_returns()) & exact behaviour
  ──────────────────────┼─────────┼──────────┼───────────────────────────────────────────────────────────
   mod_assign_get_assig │ Yes     │ YES      │ Calls $assign->update_effective_access($USER->id) at
   nments               │ (servic │ (mod/ass │ #L391[3]. Returns duedate (#L422[4], #L541[5]),
                        │ es.php# │ ign:view │ allowsubmissionsfromdate (#L423[6],#L542[7]), and
                        │ L47-    │ ,        │ cutoffdate (#L427[8], #L546[9]) with {assign_overrides}
                        │ L56[1]) │ external │ applied, without extensionduedate.
                        │         │ lib.php# │
                        │         │ L378[2]) │
   mod_assign_get_submi │ Yes     │ YES      │ get_submission_status_returns() (externallib.php#L2546-
   ssion_status         │ (servic │ (mod/ass │ L2618[12]) returns lastattempt.extensionduedate
                        │ es.php# │ ign:view │ (PARAM_INT, #L2579[13]), plus cansubmit, caneditowner,
                        │ L194-   │ +        │ locked, submissionsenabled (#L2573-L2578[14]). Strips
                        │ L202[10 │ viewowns │ duedate/cutoffdate.
                        │ ])      │ ubmissio │
                        │         │ nsummary │
                        │         │ ,        │
                        │         │ CAP_ALLO │
                        │         │ W for    │
                        │         │ student  │
                        │         │ at       │
                        │         │ access.p │
                        │         │ hp#L202- │
                        │         │ L208[11] │
                        │         │ )        │
   mod_assign_get_user_ │ Yes     │ NO       │ Checks require_capability('mod/assign:grade', $context)
   flags                │ (servic │          │ (externallib.php#L1109[16]; teacher/manager only,
                        │ es.php# │          │ access.php#L49-L59[17]); returns assignments: [] +
                        │ L84-    │          │ warning '1'.
                        │ L92[15] │          │
                        │ )       │          │
   mod_assign_get_parti │ Yes     │ NO       │ All require mod/assign:viewgrades (services.php#L210[18],
   cipant /             │         │          │ #L231[19]; externallib.php#L95[20], #L751[21],
   list_participants /  │         │          │ #L2682[22], #L2868[23]; access.php#L152-L160[24]).
   get_grades /         │         │          │
   get_submissions      │         │          │
   core_course_get_cont │ Yes     │ Partial  │ mod_assign_cm_info_dynamic() (mod/assign/lib.php#L532-
   ents                 │         │          │ L595[25]) applies assign_overrides, but
   (modules[].dates)    │         │          │ mod/assign/classes/dates.php#L53-L98[26] omits cutoffdate
                        │         │          │ and ignores extensionduedate.

   [1]: services.php#L47-L56 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/db/servi…
   [2]: externallib.php#L378 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/external…
   [3]: #L391 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/externallib.php#L391
   [4]: #L422 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/externallib.php#L422
   [5]: #L541 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/externallib.php#L541
   [6]: #L423 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/externallib.php#L423
   [7]: #L542 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/externallib.php#L542
   [8]: #L427 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/externallib.php#L427
   [9]: #L546 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/externallib.php#L546
  [10]: services.php#L194-L202 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/db/ser…
  [11]: access.php#L202-L208 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/db/acces…
  [12]: externallib.php#L2546-L2618 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/e…
  [13]: #L2579 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/externallib.php#L2579
  [14]: #L2573-L2578 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/externallib.php#…
  [15]: services.php#L84-L92 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/db/servi…
  [16]: externallib.php#L1109 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/externa…
  [17]: access.php#L49-L59 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/db/access.…
  [18]: services.php#L210 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/db/services…
  [19]: #L231 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/db/services.php#L231
  [20]: externallib.php#L95 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/externall…
  [21]: #L751 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/externallib.php#L751
  [22]: #L2682 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/externallib.php#L2682
  [23]: #L2868 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/externallib.php#L2868
  [24]: access.php#L152-L160 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/db/acces…
  [25]: mod/assign/lib.php#L532-L595 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/…
  [26]: mod/assign/classes/dates.php#L53-L98 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod…

  • Zero extra calls & JSON null gotcha ([Verified]): Moodle.sync already calls both
  mod_assign_get_assignments and mod_assign_get_submission_status. When no {assign_user_flags} row exists
  for the student, $extensionduedate is PHP null (mod/assign/locallib.php#L5438-L5441https://github.
  com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/locallib.php#L5438-L5441); external_value defaults
  $allownull = NULL_ALLOWED (lib/external/classes/external_value.php#L40-L46 https://github.
  com/moodle/moodle/blob/MOODLE_405_STABLE/lib/external/classes/external_value.php#L40-L46) and
  clean_returnvalue() preserves null (lib/external/classes/external_api.php#L406-L408 https://github.
  com/moodle/moodle/blob/MOODLE_405_STABLE/lib/external/classes/external_api.php#L406-L408). Decode
  lastattempt.extensionduedate as Int? (nil / 0 / > 0).

  ### 1.3 Quizzes (mod_quiz_get_quizzes_by_courses) ([Verified])

  • YES — user/group overrides are already applied: mod_quiz_external::get_quizzes_by_courses()
  (mod/quiz/classes/external.php#L80-L163 https://github.
  com/moodle/moodle/blob/MOODLE_405_STABLE/mod/quiz/classes/external.php#L80-L163,
  get_quizzes_by_courses_returns() #L171-L276 https://github.
  com/moodle/moodle/blob/MOODLE_405_STABLE/mod/quiz/classes/external.php#L171-L276; mod/quiz:view,
  MOODLE_OFFICIAL_MOBILE_SERVICE in mod/quiz/db/services.php#L31-L39 https://github.
  com/moodle/moodle/blob/MOODLE_405_STABLE/mod/quiz/db/services.php#L31-L39) calls $quiz =
  quiz_update_effective_access($quiz, $USER->id) at #L109 https://github.
  com/moodle/moodle/blob/MOODLE_405_STABLE/mod/quiz/classes/external.php#L109 before copying timeopen,
  timeclose, timelimit, attempts (#L117 https://github.
  com/moodle/moodle/blob/MOODLE_405_STABLE/mod/quiz/classes/external.php#L117, #L152-L154 https://github.
  com/moodle/moodle/blob/MOODLE_405_STABLE/mod/quiz/classes/external.php#L152-L154).
  • Merge rule (quiz_update_effective_access(), mod/quiz/lib.php#L237-L330 https://github.
  com/moodle/moodle/blob/MOODLE_405_STABLE/mod/quiz/lib.php#L237-L330): {quiz_overrides}
  (mod/quiz/db/install.xml#L124-L142 https://github.
  com/moodle/moodle/blob/MOODLE_405_STABLE/mod/quiz/db/install.xml#L124-L142) is the sole override table.
  User override wins per non-null field; multiple group overrides take the most lenient value
  (min(timeopen), max(timeclose), or 0 = no close date if any group override has timeclose == 0 at #L291-
  L297 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/quiz/lib.php#L291-L297).
  • mod_quiz_get_overrides (mod/quiz/db/services.php#L251-L257 https://github.
  com/moodle/moodle/blob/MOODLE_405_STABLE/mod/quiz/db/services.php#L251-L257) requires
  mod/quiz:manageoverrides and is not in moodle_mobile_app. mod_quiz_get_attempt_access_information
  (mod/quiz/classes/external.php#L1949-L2030 https://github.
  com/moodle/moodle/blob/MOODLE_405_STABLE/mod/quiz/classes/external.php#L1949-L2030) is student-callable
  if finished-attempt status (isfinished) is ever needed.
  • Codebase dedupe note ([Inferred] from Moodle.calendarEvents): calendarEvents filters out modulename
  == "assign" and "attendance" (#L437), not "quiz", so T3's activity-wins dedupe should suppress
  duplicate quiz calendar events.
  ──────
  ## Q2. Prioritising Student Deadlines: Sourced Comparison & Recommendation

  ### 2.1 Comparison of Simple, Explainable Heuristics

  Let tᵢ = (dᵢ - now)/86400 be days remaining, wᵢ be course-grade percentage weight, and Lᵢ be the
  required calendar lead/prep window (days):

   Heuristic & Primary Source     │ … │ Strengths                      │ Failure Mode for University St…
  ────────────────────────────────┼───┼────────────────────────────────┼─────────────────────────────────
   1. Earliest Due Date (EDD) —   │ - │ Minimises maximum lateness on  │ Ignores stakes and prep window.
   Jackson (1955); Pinedo,        │ d │ unit tasks ([Verified]         │ Current Deadline.priority
   Scheduling (6th ed., 2022,     │ ᵢ │ theorem); trivial to explain.  │ ((weight ?? 2) / max(t, 0.25))
   doi:10.1007/978-3-031-05921-   │   │                                │ collapses to EDD whenever
   6[1])                          │   │                                │ Moodle weights are 0
                                  │   │                                │ ([Verified] in
                                  │   │                                │ T3-T4-design-research.md:8).
   2. Weight × Hyperbolic Urgency │   │                                │
   (TMT) — Steel & König, Academy │   │                                │
   of Management Review           │   │                                │
   31(4):889–913 (2006,           │   │                                │
   doi:10.5465/amr.2006.22527462[ │   │                                │
   2])                            │   │                                │

  [1]: doi:10.1007/978-3-031-05921-6 https://doi.org/10.1007/978-3-031-05921-6
  [2]: doi:10.5465/amr.2006.22527462 https://doi.org/10.5465/amr.2006.22527462

      wᵢ
    ───────
    1 + Γtᵢ

  | Fixes w / t near-zero blow-up; matches empirical deadline discounting ([Verified] model). | Still
  treats every item as instantaneous (Lᵢ = 0): a 30% project due in 10 days (30/11 = 2.73) loses to a 4%
  lab due tomorrow (4/2 = 2.0–4.0) even when the project needs 5+ days of lead time ([Inferred]). |
  | 3. Least Slack / Least Laxity First (LLF) — Mok (1983); Leung, Algorithmica 4:209–219 (1989,
  doi:10.1007/BF00365329 https://doi.org/10.1007/BF00365329) | -(tᵢ - Lᵢ) | Directly answers "must I
  start today?" (sᵢ = tᵢ - Lᵢ ≤ 0) ([Verified] property). | Ignores grade weight wᵢ: a 1% form due in 4h
  (sᵢ = -0.08) outranks a 25% midterm in 3 days (sᵢ = -0.75 vs +0.2) ([Inferred]). |
  | 4. Apparent Tardiness Cost (ATC) — Vepsalainen & Morton, Management Science 33(8):1035–1047 (1987,
  doi:10.1287/mnsc.33.8.1035 https://doi.org/10.1287/mnsc.33.8.1035) |

     wᵢ     ⎛  max(0, tᵢ - pᵢ)⎞
    ──── exp⎜- ───────────────⎟
     pᵢ     ⎝        kp̄       ⎠

  | Unifies stakes wᵢ, effort pᵢ, and slack tᵢ - pᵢ ([Verified] dispatch rule). | Dividing by pᵢ (WSPT
  throughput bias) penalises long exams/projects relative to 15-minute tasks, and exp(·) is harder to
  explain in a one-line student chip ([Inferred]). |

  Effort / lead-window grounding ([Verified] sources, [Inferred] daily mapping): Under the European
  Commission ECTS Users' Guide (2015, §2.2, 25–30 h/ECTS) https://op.europa.eu/en/publication-detail/-
  /publication/da7467e6-8450-11e5-b8b7-01aa75ed71a1 and Rice CTE's Course Workload Estimator
  https://cte.rice.edu/resources/workload-estimator (Barre & Esarey), a 5-course term affords ~1.2–1.8
  focused self-study hours per course per day, so multi-hour assessments require multi-day calendar lead
  windows Lᵢ rather than raw clock hours.

  ### 2.2 Recommended Formula: Slack-Damped Weight ([Inferred] Synthesis)

  1. Weight fallback wᵢ (isEstimated: Bool):
      • Syllabus Assessment.exactWeight (if 0 because currently dropped in "best k of n", use a 1.0 floor
      rather than 0, preserving spare-quiz insurance) → coherent Moodle gradebook weight (> 0) →
      percentInTitle (e.g. "TED-Talk Script (8%)" → 8, isEstimated = false) → type default (isEstimated =
      true: final: 35, midterm: 25, project: 20, miniExam: 15, assignment: 8, quiz: 5, lab: 3, deadline:
      3 [reading/survey/form: 1.5], event: 1).
  2. Calendar lead window Lᵢ (days): Lᵢ = clamp(L_{base}(type) + k(type) · wᵢ,  0.25,  14.0):
      • Reading/form: (0.25,  0); lab: (0.5,  0.10); quiz: (1.0,  0.10); assignment: (1.0,  0.15);
      miniExam: (2.0,  0.12); project: (3.0,  0.20); midterm: (3.0,  0.15); final: (5.0,  0.15).
  3. Priority score (sᵢ = tᵢ - Lᵢ):

                               wᵢ
    Pᵢ = ──────────────────────────────────────────────
         0.5 + max(0,  sᵢ) + 0.5 · clamp(tᵢ/Lᵢ,  0,  1)

  • Behaviour: Removes ATC's 1/pᵢ penalty against big projects while replacing TMT's raw tᵢ with slack sᵢ.
  When sᵢ ≥ 0 (ahead of start window), Pᵢ = wᵢ/(1 + sᵢ); at the exact "start today" boundary (sᵢ = 0), Pᵢ
  = wᵢ; inside the prep window (0 ≤ tᵢ < Lᵢ), Pᵢ rises smoothly from wᵢ to 2wᵢ at tᵢ = 0 with no
  singularity. Overdue items still open (now < effectiveCutoff) stay at 2wᵢ; items past effectiveCutoff
  or locked leave "Do next".
  • Sanity check: A 30% project due in 10d (L = 9d, s = +1d ⇒ P = 15.0) outranks a 1.5% reading due
  tomorrow (L = 0.25d, s = +0.75d ⇒ P = 0.86) and "TED-Talk Script (8%)" due in 5d (L = 2.2d, s = +2.8d ⇒
  P = 2.11), while "TED-Talk Script (8%)" due in 2d (s = -0.2d ⇒ P = 8.38, "start today") rises into top
  "Do next".
  • One-line reason: "[est. ]\(w)% · due in \(t) · start today" (sᵢ ≤ 0 ≤ tᵢ), "… · start in
  \(Int(ceil(s)))d" (sᵢ > 0), or "… · overdue" (tᵢ < 0).
  • Horizon fix required ([Verified] in WeekView.swift:20): "Do next" currently slices store.board.
  between(now, now + 7 * 86_400), which hides any 10-day project/midterm before ranking runs; widen "Do
  next"'s candidate slice to 21–28 days.
  ──────
  ## Q3. core_course_get_updates_since & core_course_check_updates on Moodle 4.5 (for
  backend-review.md:109 §3 O3 & §5)

  ### 3.1 Can a Student Token (moodle_mobile_app) Call Them? ([Verified])

  • YES — both are in moodle_mobile_app and student-callable.
  • lib/moodlelib.php#L555 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/lib/moodlelib.php#L555
  defines MOODLE_OFFICIAL_MOBILE_SERVICE = 'moodle_mobile_app' (registered in lib/db/services.php#L3283-
  L3292 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/lib/db/services.php#L3283-L3292).
  • lib/db/services.php#L710-L727 https://github.
  com/moodle/moodle/blob/MOODLE_405_STABLE/lib/db/services.php#L710-L727 registers both
  'core_course_check_updates' (#L710-L718, core_course_external::check_updates) and
  'core_course_get_updates_since' (#L719-L727, core_course_external::get_updates_since) with 'type' =>
  'read', 'ajax' => true, 'services' => array(MOODLE_OFFICIAL_MOBILE_SERVICE), and no extra capabilities
  gate.
  • Runtime permission checks:
      • check_updates() (course/externallib.php#L3491-L3494 https://github.
      com/moodle/moodle/blob/MOODLE_405_STABLE/course/externallib.php#L3491-L3494) calls
      self::validate_context(context_course::instance($course->id)) (lib/external/classes/external_api.
      php#L495-L523 https://github.
      com/moodle/moodle/blob/MOODLE_405_STABLE/lib/external/classes/external_api.php#L495-L523), which
      runs require_login($course, false, $cm, false, true) — any enrolled student passes.
      • get_updates_since($courseid, $since, $filter) (course/externallib.php#L3597-L3627 https://github.
      com/moodle/moodle/blob/MOODLE_405_STABLE/course/externallib.php#L3597-L3627) enumerates $modinfo-
      >get_cms(), skips !$cm->uservisible (#L3616), builds $tocheck[] = ['id' => $cm->id, 'contextlevel'
      => 'module', 'since' => $since], and delegates to self::check_updates().


  ### 3.2 Return Schema & Per-Module Update Areas ([Verified])

  get_updates_since_returns() delegates to check_updates_returns() (course/externallib.php#L3536-L3563
  https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/course/externallib.php#L3536-L3563, #L3635-
  L3637 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/course/externallib.php#L3635-L3637):
  { instances: [{ contextlevel: "module", id: Int /* cmid, NOT instance id */, updates: [{ name: String,
  timeupdated?: Int, itemids?: [Int] }] }], warnings: [...] }. Only areas with updated == true and
  modules with ≥ 1 updated area are returned (#L3500-L3522
  https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/course/externallib.php#L3500-L3522).

  1. Common areas checked for every supported module in course_check_module_updates_since($cm, $from,
  $fileareas, $filter) (course/lib.php#L4276-L4381 https://github.
  com/moodle/moodle/blob/MOODLE_405_STABLE/course/lib.php#L4276-L4381):
      • configuration (#L4287-L4292 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/course/lib.
      php#L4287-L4292): {<modname>}.timemodified > $from; sets timeupdated. (Inplace module rename and
      module/section visibility toggles do bump {<modname>}.timemodified:
      course/format/classes/local/cmactions.php#L95-L102 https://github.
      com/moodle/moodle/blob/MOODLE_405_STABLE/course/format/classes/local/cmactions.php#L95-L102, #L170-
      L176 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/course/format/classes/local/cmactions.
      php#L170-L176; sectionactions.php#L428-L437 https://github.
      com/moodle/moodle/blob/MOODLE_405_STABLE/course/format/classes/local/sectionactions.php#L428-L437.)
      • Files (<filearea>files, NOT "contents" or "fileareas") (#L4295-L4308 https://github.
      com/moodle/moodle/blob/MOODLE_405_STABLE/course/lib.php#L4295-L4308, filter token 'fileareas'):
      queries {files} modified after $from and emits introfiles (all FEATURE_MOD_INTRO modules),
      contentfiles (resource mod/resource/lib.php#L549-L552 https://github.
      com/moodle/moodle/blob/MOODLE_405_STABLE/mod/resource/lib.php#L549-L552, folder mod/folder/lib.
      php#L796-L799 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/folder/lib.php#L796-L799,
      page mod/page/lib.php#L532-L535 https://github.
      com/moodle/moodle/blob/MOODLE_405_STABLE/mod/page/lib.php#L532-L535, url mod/url/lib.php#L375-L378
      https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/url/lib.php#L375-L378), and
      introattachmentfiles (assign mod/assign/lib.php#L1468 https://github.
      com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/lib.php#L1468), each with itemids = [files.id].
      (label checks only introfiles, mod/label/lib.php#L365-L368 https://github.
      com/moodle/moodle/blob/MOODLE_405_STABLE/mod/label/lib.php#L365-L368.)
      • completion (#L4311-L4321 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/course/lib.
      php#L4311-L4321): $completiondata->timemodified > $from. Moodle 4.5 wire bug: #L4319
      https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/course/lib.php#L4319 writes $updates-
      >completion->timemodified instead of timeupdated, while course/externallib.php#L3507
      https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/course/externallib.php#L3507 reads $data-
      >timeupdated — so "completion" arrives as {"name": "completion"} with neither timeupdated nor
      itemids.
      • gradeitems & outcomes (#L4324-L4353 https://github.
      com/moodle/moodle/blob/MOODLE_405_STABLE/course/lib.php#L4324-L4353): grade_get_grades($course->id,
      'mod', $cm->modname, $mod->id, $USER->id) where datesubmitted > $from || dategraded > $from
      (itemids = [grade_items.id]).
      • comments & ratings (#L4356-L4378 https://github.
      com/moodle/moodle/blob/MOODLE_405_STABLE/course/lib.php#L4356-L4378): when supported by the module
      (itemids).
  2. Module-specific areas returned to a student (<mod>_check_updates_since):
      • assign (mod/assign/lib.php#L1463-L1518 https://github.
      com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/lib.php#L1463-L1518): submissions
      ({assign_submission}) and grades ({assign_grades}) for $USER->id (timecreated > $from OR
      timemodified > $from, itemids). (Teacher-only usersubmissions/usergrades gated by
      mod/assign:viewgrades at #L1488.)
      • quiz (mod/quiz/lib.php#L1864-L1934 https://github.
      com/moodle/moodle/blob/MOODLE_405_STABLE/mod/quiz/lib.php#L1864-L1934): questions ({question}
      timestamps), attempts ({quiz_attempts}), and grades ({quiz_grades}) for $USER->id (itemids).
      (Teacher-only userattempts/usergrades gated by mod/quiz:viewreports at #L1905.)
      • forum (mod/forum/lib.php#L6378-L6397 https://github.
      com/moodle/moodle/blob/MOODLE_405_STABLE/mod/forum/lib.php#L6378-L6397): discussions via
      forum_get_discussions(..., $from) (#L1607-L1746 https://github.
      com/moodle/moodle/blob/MOODLE_405_STABLE/mod/forum/lib.php#L1607-L1746), checking d.timemodified >
      $from (#L1727). Because new replies bump {forum_discussions}.timemodified, discussions catches both
      new threads and new replies (itemids = [discussion.id]).


  ### 3.3 Limits & Direct Implications for Proposal O3 ([Verified] Limits, [Inferred] O3 Guidance)

  1. Blind to manual gradebook items & weight edits ([Verified] — critical for MBZUAI): Only itemtype =
  'mod' grade items are queried (course/lib.php#L4328 https://github.
  com/moodle/moodle/blob/MOODLE_405_STABLE/course/lib.php#L4328), and only datesubmitted/dategraded are
  checked (#L4334). Manual grade items (itemtype = 'manual', used heavily at MBZUAI per CLAUDE.md:11) and
  grade_items weight/max edits never trigger an update. [Inferred]: Never gate
  gradereport_user_get_grade_items solely on get_updates_since without O2's periodic refresh.
  2. Blind to deadline extensions & overrides ([Verified]): assign::save_user_extension()
  (mod/assign/locallib.php#L6998-L7060 https://github.
  com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/locallib.php#L6998-L7060), mod/assign/overrideedit.
  php#L187-L242 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/assign/overrideedit.php#L187-
  L242, and override_manager::save_override() (mod/quiz/classes/local/override_manager.php#L237-L285
  https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/mod/quiz/classes/local/override_manager.
  php#L237-L285) do not update {assign}.timemodified or {quiz}.timemodified. (Keep
  mod_assign_get_assignments, mod_quiz_get_quizzes_by_courses, and live mod_assign_get_submission_status
  on O2's fast tier.)
  3. Blind to section summaries, deletions/hidings, date-restriction unlocks, and non-implementing
  plugins ([Verified]):
• Section summary edits update {course_sections}.timemodified (sectionactions.php#L366-L368
https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/course/format/classes/local/sectionactions.
php#L366-L368), not any module (contextlevel != 'module' fails with contextlevelnotsupported at
course/lib.php#L3853-L3860 https://github.com/moodle/moodle/blob/MOODLE_405_STABLE/course/lib.
php#L3853-L3860).
• Deleted or newly hidden modules silently disappear from get_updates_since (!$cm->uservisible at
course/externallib.php#L3616 https://github.
com/moodle/moodle/blob/MOODLE_405_STABLE/course/externallib.php#L3616; check_updates with cached
cmids emits cmidnotincourse / nonuservisible warnings at course/lib.php#L3819-L3835 https://github.
com/moodle/moodle/blob/MOODLE_405_STABLE/course/lib.php#L3819-L3835). Pre-created modules whose
date availability restriction passes by wall-clock time keep their old timemodified < $since.
• Third-party modules without <mod>_check_updates_since (e.g. mod_attendance) emit warningcode:
'missingcallback' (course/lib.php#L3837-L3845 https://github.
com/moodle/moodle/blob/MOODLE_405_STABLE/course/lib.php#L3837-L3845) and report no updates.
• filter (PARAM_ALPHANUM, course/externallib.php#L3577 https://github.
com/moodle/moodle/blob/MOODLE_405_STABLE/course/externallib.php#L3577) is ignored by the module-
specific SQL in assign, quiz (which still preloads quiz questions), and forum. There is no server-
side $since age limit, and one call is needed per member Moodle courseid (~13 calls across lecture +
      - Lab courses in Moodle.groupCourses).


  • Bottom line for O3 ([Inferred]): core_course_get_updates_since works well to trigger immediate
  core_course_get_contents and mod_forum_get_forum_discussions refetches between O2's 60-minute full
  syncs, as long as O2's 60-minute full refresh stays in place to catch manual grades, section-summary
  edits, deletions, and timed availability unlocks.

