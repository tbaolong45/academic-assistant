import CryptoKit
import Foundation

// `AcademicAssistant --self-check` verifies the grade math and exits.
// (Swift Testing / XCTest need Xcode; the Command Line Tools lack their macro plugins.)
func runSelfCheck() -> Never {
    final class FailureCount { var n = 0 } // a box: a plain `var` made the compiler treat the summary's else-branch as dead
    let failures = FailureCount()
    func check(_ ok: Bool, _ what: String) { print(ok ? "✔ \(what)" : "✘ \(what)"); if !ok { failures.n += 1 } }

    check(Subject.find("linear-algebra")?.runningGrade == 80.6, "Linear Algebra running grade 80.6") // (4*85+4*72+10*90+30*78)/48
    check(Subject.find("intro-to-ai")?.runningGrade == 85.9, "Intro to AI running grade 85.9")
    check(Subject.find("advanced-python")?.runningGrade == 83.0, "Advanced Python running grade 83.0")
    check(Subject.all.map(\.stillToCome) == [52, 60, 77], "still to come 52/60/77")
    check([3, 4, 5, 12, 15, 20, 30, 35, 40].map(band) == [0, 0, 1, 1, 1, 2, 2, 3, 3], "shade bands")
    check(thisWeek().map(\.id) == ["linear-algebra/a2", "intro-to-ai/mid", "advanced-python/a2"], "this week = next 3, soonest first")

    let la = Subject.find("linear-algebra")!
    check(la.projected(["a2": 80, "final": 80]) == 80.3, "what-if: Linear Algebra with 80 on both upcoming = 80.3") // (3868+52*80)/100
    check(la.projected([:]) == la.runningGrade, "what-if with no assumptions = running grade")
    check(la.needed(for: 80) == 79.5, "needed for 80 in Linear Algebra = 79.5") // (8000-3868)/52
    check(Subject.find("advanced-python")?.needed(for: 90) == 92.1, "needed for 90 in Advanced Python = 92.1") // (9000-1910)/77

    let week = deadlines(Subject.all)
    check(week.count == 9, "week board: 3 graded + 6 other deadlines in the next 7 days (got \(week.count))")
    check(!week.contains { $0.title == "Assignment 2: Eigenvalues" }, "week board: assignment matching an assessment is not listed twice")
    check(week.map(\.date) == week.map(\.date).sorted(), "week board: soonest first")

    // MARK: - Board (B1): computed once over every date; the week is a slice of it.

    let boardNow = Date.now
    let boardAll = boardItems(Subject.all)
    let boardWeek = boardAll.between(boardNow, boardNow.addingTimeInterval(7 * 86_400))
    check(boardWeek.map(\.id) == deadlines(Subject.all, from: boardNow, days: 7).map(\.id),
          "board: sliced to this week it is the same ids, in the same order, as deadlines(…, days: 7)")
    // A literal snapshot: `deadlines` now shares the same private code, so only pinned ids catch a behaviour change.
    let weekIDs = ["linear-algebra/task/Problem sheet 7", "linear-algebra/a2", "advanced-python/task/Lab 3: asyncio drills",
                   "linear-algebra/task/Reading: Strang §6.1", "intro-to-ai/task/Lab 3: Bayes net sampling", "intro-to-ai/mid",
                   "advanced-python/task/Code review: PR #12", "intro-to-ai/task/Paper summary", "advanced-python/a2"]
    check(boardWeek.map(\.id) == weekIDs, "board: this week's ids are unchanged by the refactor (got \(boardWeek.map(\.id)))")
    check(boardAll.count > boardWeek.count && boardAll.map(\.date) == boardAll.map(\.date).sorted(),
          "board: every date kept (not just 7 days), soonest first (\(boardAll.count) items, \(boardWeek.count) this week)")
    check(!boardAll.isEmpty && boardAll.allSatisfy { $0.headlineCache != nil },
          "board: each item's headline is worked out once, so views don't re-run mainPoint's regexes per redraw")
    let b1Posted = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 25))!
    let b1Quiz = Moodle.mentionedDates("Quiz on 3rd October", posted: b1Posted, source: .announcement)
    check(b1Quiz.count == 1 && b1Quiz[0].title == "Quiz on 3rd October"
          && Calendar.current.dateComponents([.year, .month, .day], from: b1Quiz[0].date) == DateComponents(year: 2026, month: 10, day: 3),
          "board: 'Quiz on 3rd October' still parses to 3 Oct 2026 (got \(b1Quiz.map(\.title)))")

    // Crunch: the worst 48h window with ≥3 deadlines or ≥30% weight.
    let s0 = Subject.all[0], t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func d(_ h: Double, _ w: Int?) -> Deadline { Deadline(id: "\(h)", subject: s0, title: "x", date: t0 + h * 3600, weight: w) }
    check(crunch([d(0, 5), d(10, nil), d(100, 5)]) == nil, "crunch: 2 items in 48h, 10% → none")
    check(crunch([d(0, nil), d(20, nil), d(47, nil)])?.items.count == 3, "crunch: 3 items within 48h → crunch")
    check(crunch([d(0, 30), d(60, 5)])?.weight == 30, "crunch: one 30% item alone qualifies by weight")
    check(crunch([d(0, 10), d(10, 10), d(20, 10), d(200, 40), d(210, 5)])?.weight == 45, "crunch: picks the heaviest window")

    // Moodle mapping, fixtures shaped like the 4.5 web-service replies.
    let gradesJSON = #"""
        {"usergrades":[{"courseid":7,"gradeitems":[
        {"id":1,"itemname":null,"itemtype":"course","iteminstance":7,"weightraw":null,"graderaw":80,"grademax":100},
        {"id":11,"itemname":"Assignment 1","itemtype":"mod","itemmodule":"assign","iteminstance":3,"weightraw":0.15,"graderaw":17.5,"grademax":20,"gradedategraded":1761000000},
        {"id":12,"itemname":"Quiz 2","itemtype":"mod","itemmodule":"quiz","iteminstance":9,"weightraw":0.104,"graderaw":null,"grademax":10}]}],"warnings":[]}
        """#
    let assignsJSON = #"{"courses":[{"id":7,"fullname":"X","assignments":[{"id":3,"cmid":40,"course":7,"name":"Assignment 1: Proofs","duedate":1759000000}]}],"warnings":[]}"#
    let quizzesJSON = #"{"quizzes":[{"id":9,"course":7,"coursemodule":41,"name":"Quiz 2","timeclose":1765000000}],"warnings":[]}"#
    do {
        let dec = JSONDecoder()
        let items = try dec.decode(Moodle.GradeItems.self, from: Data(gradesJSON.utf8)).usergrades[0].gradeitems
        let assigns = try dec.decode(Moodle.Assigns.self, from: Data(assignsJSON.utf8)).courses[0].assignments
        let quizzes = try dec.decode(Moodle.Quizzes.self, from: Data(quizzesJSON.utf8)).quizzes
        let out = Moodle.assessments(items, assigns: assigns, quizzes: quizzes, fallback: .distantPast)
        check(out.map(\.id) == ["gi11", "gi12"], "moodle: only mod grade items become assessments, by date")
        check(out.first?.weight == 15 && out.first?.raw == .init(got: 175, max: 200) && out.first?.score == 88,
              "moodle: weight = round(weightraw·100), raw = graderaw/grademax (17.5/20 → 88%)")
        check(out.first?.date == Date(timeIntervalSince1970: 1_759_000_000), "moodle: grade item dated by its assignment's duedate")
        check(out.last.map { $0.raw == nil && $0.weight == 10 && $0.type == .quiz && $0.date == Date(timeIntervalSince1970: 1_765_000_000) } == true,
              "moodle: ungraded quiz is upcoming, dated by timeclose")
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let later = [Moodle.Assign(id: 5, name: "A", duedate: 1_760_500_000), Moodle.Assign(id: 6, name: "B", duedate: 1_760_600_000)]
        check(Moodle.assignmentItems(later, pending: [5], now: now).map(\.status) == [.open, .open],
              "moodle: future assignment with no submission info is open, with or without a calendar action")
        let missed = [Moodle.Assign(id: 7, name: "Late", duedate: 1_759_500_000)]
        check(Moodle.assignmentItems(missed, pending: [7], now: now).first?.status == .open,
              "moodle: past-due assignment still holding an action stays open (overdue), not 'submitted'")
    } catch {
        check(false, "moodle fixtures decode (\(error))")
    }
    let invalid = Data(#"{"exception":"moodle_exception","errorcode":"invalidtoken","message":"Invalid token - token not found"}"#.utf8)
    check(Moodle.error(in: invalid)?.localizedDescription == "Key rejected — copy it again from Security keys", "moodle: invalidtoken → friendly message")
    check(Moodle.error(in: Data("[]".utf8)) == nil, "moodle: a plain array reply is not an error")
    check(Moodle.redact("https://x/server.php?wstoken=ab12&wsfunction=f") == "https://x/server.php?wstoken=[redacted]&wsfunction=f", "moodle: wstoken redacted")
    check((try? Moodle.siteURL("http://lms.example.edu")) == nil, "moodle: non-HTTPS site refused")

    // Course naming / ranking (credit courses first).
    let ai = Moodle.courseLabel("Fall 2026/2027 Introduction to AI (AI1010-001)")
    check(ai?.name == "Introduction to AI" && ai?.code == "AI1010", "course label: term and section stripped")
    check(Moodle.courseLabel("Fall 2026/2027 Communication (GE1005-001)")?.code == "GE1005", "course label: GE code")
    check(Moodle.courseLabel("Peer Tutoring - Undergraduate") == nil && Moodle.courseLabel("AI Tools: Responsible Use at MBZUAI") == nil,
          "course label: trainings are not credit courses")

    func course(_ id: Int, _ short: String, _ full: String) -> Moodle.Course {
        Moodle.Course(id: id, shortname: short, fullname: full, visible: 1, startdate: nil, enddate: nil)
    }
    let grouped = Moodle.groupCourses([
        course(1, "Peer_Tutoring", "Peer Tutoring - Undergraduate"),
        course(2, "20096L", "Fall 2026/2027 Introduction to AI - Lab (AI1010-002)"),
        course(3, "20096", "Fall 2026/2027 Introduction to AI (AI1010-001)"),
        course(4, "20108", "Fall 2026/2027 Linear Algebra (AI1120-001)"),
    ])
    check(grouped.map(\.code) == ["AI1010", "AI1120", "Peer_Tutoring"], "groups: one per code, credit courses first, trainings last")
    check(grouped[0].name == "Introduction to AI" && grouped[0].members.map(\.id) == [3, 2], "groups: lab merged into its lecture, lecture leads")

    do {
        let manualJSON = #"""
            {"usergrades":[{"courseid":9,"gradeitems":[
            {"id":21,"itemname":"Quiz 1","itemtype":"manual","weightraw":0,"graderaw":8,"grademax":10},
            {"id":22,"itemname":"Class Attendance","itemtype":"mod","itemmodule":"attendance","iteminstance":1,"weightraw":0,"graderaw":100,"grademax":100},
            {"id":23,"itemname":null,"itemtype":"course","weightraw":null,"graderaw":80,"grademax":100}]}],"warnings":[]}
            """#
        let items = try JSONDecoder().decode(Moodle.GradeItems.self, from: Data(manualJSON.utf8)).usergrades[0].gradeitems
        let out = Moodle.assessments(items, assigns: [], quizzes: [], fallback: .distantPast)
        check(out.map(\.name) == ["Quiz 1"] && out.first?.type == .quiz, "grades: teacher-entered (manual) quiz kept; attendance and course total dropped")
    } catch { check(false, "manual grade fixture decodes (\(error))") }

    // Materials: files kept with their Moodle URL; one-file material goes straight into the course folder.
    do {
        let contentsJSON = #"""
            [{"modules":[
             {"name":"Lecture 1","modname":"resource","uservisible":true,"contents":[{"type":"file","filename":"L1: intro.pdf","fileurl":"https://x/webservice/pluginfile.php/1/L1.pdf","filesize":1234,"timemodified":1760000000,"mimetype":"application/pdf"}]},
             {"name":"Week 2","modname":"folder","contents":[{"type":"file","filename":"a.pdf","fileurl":"https://x/a","filesize":1},{"type":"file","filename":"b.pdf","fileurl":"https://x/b","filesize":2}]},
             {"name":"Docs","modname":"url","contents":[{"type":"url","fileurl":"https://docs.example.org"}]}]}]
            """#
        let mats = Moodle.materials(try JSONDecoder().decode([Moodle.Section].self, from: Data(contentsJSON.utf8)), fallback: .distantPast)
        let lec = mats.first { $0.title == "Lecture 1" }, folder = mats.first { $0.title == "Week 2" }
        check(lec?.files?.first?.url == "https://x/webservice/pluginfile.php/1/L1.pdf" && folder?.files?.count == 2
              && mats.first { $0.title == "Docs" }?.link == "https://docs.example.org", "materials: files and links mapped")
        let s = Subject.all[0]
        check(MaterialStore.localURL(s, lec!, lec!.files![0]).path(percentEncoded: false).hasSuffix("Academic Assistant/Linear Algebra/L1- intro.pdf"),
              "materials: single file saved in the course folder, ':' made safe")
        check(MaterialStore.localURL(s, folder!, folder!.files![1]).path(percentEncoded: false).hasSuffix("Linear Algebra/Week 2/b.pdf"),
              "materials: multi-file folder gets its own sub-folder")
    } catch { check(false, "materials fixture decodes (\(error))") }

    // Practice (assignments tab) vs lectures & material.
    func m(_ t: String) -> Material { Material(title: t, kind: .notes, date: .now) }
    check(["Exercise set 6 - Definite Integrals", "Lab#4_Questions", "Quiz 2 Solution", "Sample Exam", "AnswerKey", "WorkSheet",
           "Practice Exercises with Solutions (pdf)", "Assignment 1 Brief"].allSatisfy { m($0).isPractice },
          "practice: exercises, labs, quiz solutions, sample exams, answer keys")
    check(!["(SLIDE) Week 5 - Derivatives (Part 2)", "Lecture Slides 6", "Week 8: Determinants and Inverses (Vectoria)",
            "Course Syllabus", "Midterm Exam Room Distribution", "OOP Example (slides)"].contains { m($0).isPractice },
          "lectures: slides, notes, syllabus and exam-room info stay in Lectures & Material")

    check(["Quiz 2 Solution", "Sample Exam", "Quiz 1 Questions", "Lab 7 Brief", "Exercise Sheet 1", "Lab#4_Answers"].map { m($0).practiceLabel }
          == ["SOLUTION", "SAMPLE EXAM", "QUIZ", "LAB", "EXERCISE", "SOLUTION"], "practice labels (incl. Lab#4_Answers → SOLUTION)")

    // Full extraction: weights in titles, announcement text, mentioned dates, teacher calendar events, submission status.
    let posted = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 25))!
    check(percentInTitle("TED-Talk Script (8%)") == 8 && percentInTitle("Critical Writing - Final Paper - 14%") == 14
          && percentInTitle("Week 6 Slides") == nil, "weight read from title")
    check(Moodle.plainText("<p>Due at 11:59&nbsp;pm on <b>3rd October</b>.</p><p>Don&#39;t be late</p>") == "Due at 11:59 pm on 3rd October.\nDon't be late",
          "announcement HTML → text")
    let more = Moodle.mentionedDates("OCTOBER 28th There will be no regular classes on this day. Combined class at 6:30 pm on 28 Oct", posted: posted, source: .announcement)
    check(more.count == 2 && more.allSatisfy { Calendar.current.component(.day, from: $0.date) == 28 },
          "mentioned date: 'OCTOBER 28th' and '28 Oct' both found")
    check(Moodle.mentionedDates("OCTOBER 28th\nThere will be no regular classes on this day.", posted: posted, source: .announcement).first?.title
          == "OCTOBER 28th — There will be no regular classes on this day.", "mentioned date: a date alone on a line takes the next sentence")
    let pm = Moodle.mentionedDates("Combined class at 6:30 pm on 28 Oct", posted: posted, source: .announcement).first?.date
    check(pm.map { Calendar.current.dateComponents([.hour, .minute], from: $0) } == DateComponents(hour: 18, minute: 30), "mentioned date: time 6:30 pm kept")
    let found = Moodle.mentionedDates("Please check the submission deadline for the draft. It is due at 11:59 pm on 3rd October, which is a Saturday. See you tomorrow.",
                                      posted: posted, source: .announcement)
    let oct3 = found.first.map { Calendar.current.dateComponents([.year, .month, .day], from: $0.date) }
    check(found.count == 2 && oct3?.year == 2026 && oct3?.month == 10 && oct3?.day == 3 && found[0].title.contains("3rd October"),
          "mentioned date: '3rd October' in a Sept post → 3 Oct 2026")
    let cal = [Moodle.CalendarEvent(name: "Midterm Exam", description: "<p>Room 1A</p>", modulename: nil, eventtype: "course", courseid: 7, timestart: 1_762_000_000),
               Moodle.CalendarEvent(name: "Class Attendance", description: nil, modulename: "attendance", eventtype: "course", courseid: 7, timestart: 1_762_000_000),
               Moodle.CalendarEvent(name: "TED-Talk Script (8%) is due", description: nil, modulename: "assign", eventtype: "due", courseid: 7, timestart: 1_762_000_000),
               Moodle.CalendarEvent(name: "Other course exam", description: nil, modulename: nil, eventtype: "course", courseid: 9, timestart: 1_762_000_000)]
    let kept = Moodle.calendarEvents(cal, courseIDs: [7])
    check(kept.map(\.title) == ["Midterm Exam"] && kept.first?.detail == "Room 1A", "calendar: teacher events kept; attendance, activity events, other courses dropped")
    let quizEv = Moodle.calendarEvents([Moodle.CalendarEvent(name: "Quiz 3 closes", description: nil, modulename: "quiz", eventtype: "close", courseid: 7, timestart: 1_762_000_000),
                                        Moodle.CalendarEvent(name: "Holiday: National Day", description: nil, modulename: nil, eventtype: "site", courseid: 1, timestart: 1_762_000_000)],
                                       courseIDs: [7])
    check(quizEv.map(\.title) == ["Quiz 3 closes"], "calendar: activity events (quiz) kept for the course; site events go to General")
    check(Moodle.calendarEvents([Moodle.CalendarEvent(name: "Holiday: National Day", description: nil, modulename: nil, eventtype: "site", courseid: 1, timestart: 1_762_000_000)],
                                courseIDs: [0, 1]).count == 1, "calendar: site event collected for General")
    let nextTime = Moodle.mentionedDates("OCTOBER 28th\nCombined class at 6:30 pm in the DO.", posted: posted, source: .announcement).first?.date
    check(nextTime.map { Calendar.current.component(.hour, from: $0) } == 18, "mentioned date: time taken from the following sentence")
    let tue20 = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9))!
    let rel = Moodle.mentionedDates("Tuesday: Keynote session 3:30pm 1A IEC 1F. See you tomorrow in class. Next Monday we start TED talks.", posted: tue20, source: .announcement)
    let relDays = rel.map { Calendar.current.dateComponents([.month, .day, .hour], from: $0.date) }
    check(relDays == [DateComponents(month: 10, day: 27, hour: 15), DateComponents(month: 10, day: 21, hour: 23), DateComponents(month: 10, day: 26, hour: 23)],
          "relative dates from a Tue 20 Oct post: 'Tuesday' → 27 Oct 3:30pm, 'tomorrow' → 21 Oct, 'Next Monday' → 26 Oct")
    let doc = Moodle.mentionedDates("m = 2/3, U = 3 6. TASK FOR NEXT MONDAY. Lab Overview 23/10/2026. Final exam 15 December.", posted: posted, source: .document, strict: true)
    check(doc.count == 2, "documents (strict): '2/3' and 'next Monday' ignored; '23/10/2026' and '15 December' kept")
    let table = Moodle.mentionedDates("9\nOct 20\nOct 22\nOct 23\nTue - Midterm Examination (Weeks 1-7 material)\nThu - 4.9 Antiderivatives\nFri - 5.1 Areas and Distances",
                                      posted: posted, source: .document, strict: true)
    check(table.map(\.title) == ["Oct 20 — Tue - Midterm Examination (Weeks 1-7 material)", "Oct 22 — Thu - 4.9 Antiderivatives", "Oct 23 — Fri - 5.1 Areas and Distances"],
          "schedule table read by columns: each date gets its own topic line")
    let dueAt = Moodle.mentionedDates("Assignment due 28 October 11:59 PM", posted: posted, source: .announcement)
    check(dueAt.count == 1 && Calendar.current.dateComponents([.month, .day, .hour, .minute], from: dueAt[0].date) == DateComponents(month: 10, day: 28, hour: 23, minute: 59),
          "dates: '28 October 11:59 PM' is one date at 23:59, not also 11 Oct")
    check(Moodle.mentionedDates("The class average was 9/10 on the quiz", posted: posted, source: .announcement).isEmpty, "dates: a score '9/10' is not a date")
    check(Moodle.mentionedDates("Deadline 31 April", posted: posted, source: .announcement).isEmpty, "dates: '31 April' doesn't roll over to 1 May")
    let twoDays = Moodle.mentionedDates("Quiz on Oct 20. Lab on Oct 22 at 3 PM.", posted: posted, source: .announcement)
    check(twoDays.map { Calendar.current.component(.hour, from: $0.date) } == [23, 15], "dates: a time belongs to its own sentence's date")
    check(Moodle.mentionedDates("Final exam Dec 1, 2027", posted: posted, source: .document, strict: true).first.map { Calendar.current.component(.year, from: $0.date) } == 2027,
          "dates: a written year is kept")
    let posts = [Announcement(title: "TED talk script feedback", source: .moodle, from: "Dr. T", date: .now, body: "Send your script by Sunday"),
                 Announcement(title: "Room change", source: .moodle, from: "Dr. T", date: .now, body: "Talk to you in B204")]
    check(related("TED-Talk Script (8%)", in: posts).map(\.title) == ["TED talk script feedback"], "preview: related announcements contain the title's words")
    check(sameItem("Quiz 3 closes", "Quiz 3") && !sameItem("Assignment 10", "Assignment 1"), "deadlines: 'Assignment 10' is not 'Assignment 1'")
    check(MaterialStore.safe("..") == "Untitled" && MaterialStore.safe(".zshrc") == "zshrc", "files: names can't climb out of the folder")
    check(Moodle.redact("…pluginfile.php/1/a.pdf?token=abc123&x=1 wstoken=def") == "…pluginfile.php/1/a.pdf?token=[redacted]&x=1 wstoken=[redacted]",
          "redact: both token= and wstoken= are hidden")
    let unweighted = Subject(id: "u", name: "U", code: "U", hue: .blue, assessments: [
        Assessment(id: "1", name: "Quiz 1", type: .quiz, date: posted, weight: 0, raw: .init(got: 8, max: 10), topics: []),
        Assessment(id: "2", name: "Quiz 2", type: .quiz, date: posted, weight: 0, raw: .init(got: 6, max: 10), topics: [])], assignments: [], materials: [], announcements: [])
    check(unweighted.assessments.map(\.score) == [80, 60] && unweighted.runningGrade == 70 && unweighted.doneShare == nil,
          "grades: results with weight 0 still give a running grade (plain average); no fake '% done'")
    check(Moodle.plainText("<style>p{x}</style>A &amp;lt; B<script>alert(1)</script>") == "A &lt; B", "plainText: drops script/style, decodes &amp; last")
    let tomorrowTime = Moodle.mentionedDates("Assignment 1 due 28 Oct. Office hours are tomorrow at 2:00 pm.", posted: posted, source: .announcement)
    check(tomorrowTime.first.map { Calendar.current.component(.hour, from: $0.date) } == 23, "dates: '28 Oct' doesn't take the time of 'tomorrow at 2 pm'")
    // Jev classifier: request shape, reply parsing, and what the board keeps
    let jevBody = (try? JSONSerialization.jsonObject(with: Jev.body("No class on Thursday"))) as? [String: Any]
    let jevQ = ((jevBody?["questions"] as? [String: Any])?["kind"] as? [String: Any])
    check(jevBody?["model"] as? String == "jev-latest" && jevBody?["state"] as? String == "No class on Thursday" && jevQ?["type"] as? String == "choice"
          && Set(((jevQ?["criteria"] as? [String: String]) ?? [:]).keys) == Set(ItemKind.allCases.map(\.rawValue)),
          "jev: request is one choice question over the six kinds")
    let jevReply = #"{"model":"jev-latest","answers":{"kind":{"type":"choice","choice":"class_change","confidence":0.83,"probabilities":{"class_change":0.9}}},"usage":{"input_tokens":120,"output_tokens":12}}"#
    check((try? Jev.parse(Data(jevReply.utf8))) == Jev.Answer(kind: .classChange, confidence: 0.83), "jev: reply parsed to label + confidence")
    check((try? Jev.parse(Data(#"{"answers":{"kind":{"choice":"banana"}}}"#.utf8))) == nil, "jev: an unknown label is rejected")
    let soon = Date.now.addingTimeInterval(86_400)
    let infoEvent = CourseEvent(title: "Marks are live", date: soon, source: .announcement, detail: "Marks are live on Moodle tomorrow")
    let talk = CourseEvent(title: "Keynote", date: soon, source: .announcement, detail: "Keynote tomorrow at 3pm")
    let plain = Subject(id: "j", name: "J", code: "J", hue: .blue, assessments: [], assignments: [], materials: [], announcements: [], events: [infoEvent, talk])
    let tagged = labeled([plain], [Jev.id(infoEvent.classifyText): .init(kind: .grades, confidence: 0.9), Jev.id(talk.classifyText): .init(kind: .event, confidence: 0.8)])
    check(deadlines([plain], from: .now).count == 2 && deadlines(tagged, from: .now).map(\.title) == ["Keynote"]
          && deadlines(tagged, from: .now).first?.kind == .event,
          "jev: 'grades out' leaves the board, an event stays labelled; unclassified items all stay")
    // Calculus syllabus: quizzes 30% (best 4 of 5), midterm 30, final 35, project 5
    func quiz(_ n: Int, _ got: Int?) -> Assessment {
        Assessment(id: "q\(n)", name: "Quiz \(n)", type: .quiz, date: Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: n))!,
                   weight: 0, raw: got.map { .init(got: $0, max: 100) }, topics: [])
    }
    let calc = withSyllabus("AI1110", [quiz(1, 73), quiz(2, 88)])
    let calcSubject = Subject(id: "c", name: "Calculus", code: "AI1110", hue: .orange, assessments: calc, assignments: [], materials: [], announcements: [])
    check(calc.count == 8 && calc.filter { $0.type == .quiz }.count == 5 && calc.contains { $0.name == "Final Exam" && $0.share == 35 },
          "syllabus: Calculus gets Quiz 3–5, midterm, final and project as upcoming")
    check(calcSubject.runningGrade == 80.5 && calcSubject.stillToComeShare == 85 && calcSubject.needed(for: 90) == 91.7,
          "syllabus: 2 quizzes (73, 88) → 80.5%; 85% still to come; 90% overall needs 91.7% on the rest")
    let allFive = withSyllabus("AI1110", [quiz(1, 73), quiz(2, 88), quiz(3, 60), quiz(4, 90), quiz(5, 95)]).filter { $0.type == .quiz }
    check(allFive.first { $0.name == "Quiz 3" }?.share == 0 && allFive.filter { $0.share == 7.5 }.count == 4,
          "syllabus: with all 5 quizzes graded only the best 4 count (the 60 is dropped)")
    check(withSyllabus("GE1005", [quiz(1, 73)]).count == 1, "syllabus: courses without a rule are untouched")
    let tedScript = Deadline(id: "a", subject: plain, title: "TED-Talk Script (8%)", date: soon, weight: 8, kind: .deadline)
    let keynote = Deadline(id: "b", subject: plain, title: "Keynote", date: soon, weight: nil, source: .announcement, kind: .event)
    let unsorted = Deadline(id: "c", subject: plain, title: "Oct 29 — no classes", date: soon, weight: nil, source: .document)
    check([tedScript, keynote, unsorted].filter { $0.isIn(.submit) }.map(\.id) == ["a"] && [tedScript, keynote, unsorted].filter { $0.isIn(.events) }.map(\.id) == ["b", "c"],
          "board split: 'To submit' = work to hand in; events and unclassified dates go to 'Events'")
    check(Moodle.route("Dear Linear Algebraists, I need to move tomorrow's class", Subject.all) == Subject.all.firstIndex { $0.name == "Linear Algebra" }
          && Moodle.route("Fall 2026/2027 Calculus (AI1110-001) new content", Subject.all) == nil, "messages: routed by course name/code; unknown → General")
    let exact = Subject(id: "x", name: "X", code: "X", hue: .blue, assessments: [
        Assessment(id: "1", name: "Quiz 1", type: .quiz, date: posted, weight: 0, raw: .init(got: 73, max: 100), topics: []),
        Assessment(id: "2", name: "Quiz 2", type: .quiz, date: posted, weight: 0, raw: .init(got: 875, max: 1000), topics: [])], assignments: [], materials: [], announcements: [])
    check(exact.runningGrade == 80.3, "grades: exact marks (73 and 87.5 → 80.25 → 80.3), not rounded first")
    check(mainPoint("• Final Research Submission (14%) DUE WEEK (Deadline 13th November)") == "Final Research Submission (14%)"
          && mainPoint("OCTOBER 28th — There will be no regular classes on this day.") == "No regular classes"
          && mainPoint("Oct 29 — Thu - Research Showcase - no classes") == "Research Showcase - no classes"
          && mainPoint("Tuesday: Keynote session 3:30pm 1A IEC 1F.") == "Keynote session 3:30pm 1A IEC 1F"
          && mainPoint("Dear Linear Algebraists, unfortunately I need to move tomorrow's office hours to today") == "I need to move tomorrow's office hours to today",
          "headlines: dates, bullets and filler removed; the main point kept")
    let page = Moodle.materials([Moodle.Section(name: "Week 8", summary: "<p>Final paper due <b>13th November</b></p>", modules: [])], fallback: posted)
    check(page.first?.text == "Final paper due 13th November" && page.first?.title == "Week 8", "course page: section summaries are kept as text")
    let unsure = labeled([plain], [Jev.id(infoEvent.classifyText): .init(kind: .info, confidence: 0.45)])
    check(unsure[0].events?.first?.kind == nil && deadlines(unsure, from: .now).count == 2, "jev: an unsure 'info' (< 0.6) keeps the item on the board")
    // Summarizer: request/response shapes and the extractive pick
    let dsBody = (try? JSONSerialization.jsonObject(with: DeepSeek.body(parts: ["Final paper due 13th November"], date: "Fri 13 Nov"))) as? [String: Any]
    check(dsBody?["model"] as? String == "deepseek-flash" && (dsBody?["messages"] as? [[String: String]])?.last?["content"]?.contains("Fri 13 Nov") == true,
          "deepseek: chat request carries the parts and the date")
    check((try? DeepSeek.parse(Data(#"{"choices":[{"message":{"role":"assistant","content":"\"Final paper due Fri 13 Nov.\""}}]}"#.utf8))) == "Final paper due Fri 13 Nov",
          "deepseek: title read from the reply, quotes and period trimmed")
    check((try? Jev.parseYesNo(Data(#"{"model":"jev-latest","answers":{"date":{"type":"noul","noul":0.98},"point":{"type":"noul","noul":0.4}}}"#.utf8)))
          == ["date": 0.98, "point": 0.4], "jev: yes/no answers read as probabilities")
    let sents = ["Hi all", "The final paper is due 13th November", "Use APA style", "Have a good weekend"]
    check(Summarizer.pick(sents, yes: ["p0": 0.1, "p1": 0.97, "p2": 0.6, "p3": 0.05], own: "The final paper is due 13th November")
          == ["The final paper is due 13th November", "Use APA style"], "summarizer: Jev's important parts kept in reading order")
    check(Summary(title: "x", parts: [], mentionsDate: 0.9, keepsPoint: 0.3, faithful: 0.9, specific: 0.9).accepted == false, "summarizer: a title missing the point is rejected")
    check(!hasContent("Dec 8 — -") && hasContent("Dec 10 — Tue – Final Project Presentation") && hasContent("Seeya tonight at 6:30pm."),
          "summarizer: a date with nothing else ('Dec 8 — -') isn't sent to DeepSeek")
    check(!Summary(title: "Calculus tentative schedule material due Tue 8 Dec", parts: [], mentionsDate: 0.99, keepsPoint: 0.58, faithful: 0.9, specific: 0.9).accepted
          && Summary(title: "Final Research Submission due Fri 13 Nov", parts: [], mentionsDate: 0.99, keepsPoint: 0.95, faithful: 0.95, specific: 0.9).accepted,
          "summarizer: a barely-passing 0.58 'keeps the point' is no longer enough")
    let gap = Moodle.mentionedDates("16\nDec 8\nDec 10\n-\nTue – Final Project Presentation\nThu - Final Project Presentation", posted: posted, source: .document, strict: true)
    check(gap.map(\.title) == ["Dec 8 — Tue – Final Project Presentation", "Dec 10 — Thu - Final Project Presentation"],
          "schedule table: an empty '-' row doesn't shift dates onto the wrong rows")
    check(Summary(title: "x", parts: [], mentionsDate: 0.9, keepsPoint: 0.9, faithful: 0.2, specific: 0.3).failures
          == ["it adds or changes a fact that isn't in the parts", "it's too vague: name the specific item"], "summarizer: failed checks become retry feedback")
    check(String(data: DeepSeek.body(parts: ["a"], date: "Fri 13 Nov", feedback: "“x” it's too vague"), encoding: .utf8)?.contains("previous title was rejected") == true,
          "deepseek: the retry tells it why the last title was rejected")
    let ics = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nDTSTART;TZID=Arabian Standard Time:20261027T153000\r\nSUMMARY:Keynote: Bruce Holsinger\r\nLOCATION:1A-FF-IEC\r\nDESCRIPTION:Songs of the\r\n  Machine\\, a talk\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nDTSTART;TZID=Arabian Standard Time:20260825T090000\r\nRRULE:FREQ=WEEKLY;BYDAY=TU\r\nSUMMARY:Calculus\r\nEND:VEVENT\r\nEND:VCALENDAR"
    let ical = OutlookCalendar.parse(ics)
    let icsKeynote = ical.first
    let keynoteWhen = icsKeynote.map { Calendar.current.dateComponents([.month, .day, .hour, .minute], from: $0.start) }
    let parsedRight = ical.count == 2 && icsKeynote?.title == "Keynote: Bruce Holsinger" && icsKeynote?.notes == "Songs of the Machine, a talk"
    let timeRight = keynoteWhen == DateComponents(month: 10, day: 27, hour: 15, minute: 30)
    let recurRight = icsKeynote?.recurring == false && ical.last?.recurring == true
    check(parsedRight && timeRight && recurRight, "outlook: ICS events parsed (folded lines, escapes, local time, recurring flag)")
    let merged = OutlookCalendar.merge(ical, into: Subject.all, now: icsKeynote?.start ?? .now)
    let outlookTitles: [String] = merged.flatMap { $0.events ?? [] }.filter { $0.source == CourseEvent.Source.outlook }.map(\.title)
    check(outlookTitles == ["Keynote: Bruce Holsinger"] && merged.last?.code == "GENERAL",
          "outlook: one-off events go on the board (General if no course is named); recurring classes don't")
    let raw = "From: =?UTF-8?B?VW5kZXJncmFkdWF0ZSBPZmZpY2U=?= <ug@mbzuai.ac.ae>\r\nTo: student@mbzuai.ac.ae\r\nSubject: =?utf-8?Q?Quiz_moved_to_Thursday?=\r\nDate: Wed, 28 Oct 2026 16:25:00 +0400\r\nContent-Type: multipart/alternative; boundary=\"b1\"\r\n\r\n--b1\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\nThe Calculus quiz is moved to 5th November =\r\nat 10am.\r\n--b1\r\nContent-Type: text/html\r\n\r\n<p>html</p>\r\n--b1--"
    let mailMsg = SchoolMail.parse(raw, uid: 7)
    check(mailMsg?.from == "Undergraduate Office" && mailMsg?.subject == "Quiz moved to Thursday" && mailMsg?.body == "The Calculus quiz is moved to 5th November at 10am.",
          "mail: MIME parsed (encoded-word From/Subject, multipart, quoted-printable soft breaks)")
    let withMail = SchoolMail.merge(mailMsg.map { [$0] } ?? [], into: Subject.all)
    check(withMail.contains { $0.announcements.contains { $0.source == .outlook && $0.title == "Quiz moved to Thursday" } }
          && withMail.flatMap { $0.events ?? [] }.contains { $0.announcement != nil && $0.origin?.hasPrefix("✉︎") == true },
          "mail: an email becomes an announcement and its date goes on the board, linked back to it")
    check(SchoolMail.decodeWords("=?windows-1252?Q?Training_data_is_up_=96_start_building?=") == "Training data is up – start building",
          "mail: windows-1252 subjects decode ('–', not '�')")
    // Calendar page: weekly class series expanded, exception skipped, moved session shown at its new time
    let series = "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:calc\nDTSTART;TZID=Arabian Standard Time:20261006T090000\nDTEND;TZID=Arabian Standard Time:20261006T101500\nRRULE:FREQ=WEEKLY;UNTIL=20261211T000000Z;INTERVAL=1;BYDAY=TU,TH\nEXDATE;TZID=Arabian Standard Time:20261013T090000,20261015T090000\nSUMMARY:Calculus\nEND:VEVENT\nBEGIN:VEVENT\nUID:calc\nRECURRENCE-ID;TZID=Arabian Standard Time:20261020T090000\nDTSTART;TZID=Arabian Standard Time:20261020T110000\nDTEND;TZID=Arabian Standard Time:20261020T121500\nSUMMARY:Calculus\nEND:VEVENT\nEND:VCALENDAR"
    let seriesItems = OutlookCalendar.parse(series)
    let oct = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5))!
    let sessions = OutlookCalendar.occurrences(seriesItems, from: oct, to: oct.addingTimeInterval(21 * 86_400))
    let when: [String] = sessions.map { let c = Calendar.current.dateComponents([.day, .hour], from: $0.start); return "\(c.day!)@\(c.hour!)" }
    check(when == ["6@9", "8@9", "20@11", "22@9"] && sessions.allSatisfy { $0.end.timeIntervalSince($0.start) == 75 * 60 },
          "calendar: weekly Tue/Thu classes expanded, fall-break EXDATEs skipped, the moved 20 Oct session shown at 11:00")
    check(OutlookCalendar.merge(seriesItems, into: Subject.all, now: oct).flatMap { $0.events ?? [] }.allSatisfy { $0.source != .outlook },
          "calendar: class sessions (series and moved ones) stay off the deadline board")
    let st = Moodle.assignmentItems([Moodle.Assign(id: 1, name: "TED-Talk Script (8%)", duedate: 1_762_000_000)], pending: [], now: .now, submitted: [1: false])
    check(st.first?.status == .open, "status: real 'not submitted' wins over the capped calendar fallback")
    let nowT = Date(timeIntervalSince1970: 1_761_600_000)
    let fallback = Moodle.assignmentItems([Moodle.Assign(id: 1, name: "TED-Talk Script (8%)", duedate: 1_761_950_000),
                                           Moodle.Assign(id: 2, name: "Research Draft (Viva) 4%", duedate: 1_759_380_000)],
                                          pending: [2], now: nowT, graded: [2])
    check(fallback.map(\.status) == [.submitted, .open], "status fallback: future unsubmitted → open; graded viva → done")

    do {
        let actJSON = #"[{"modules":[{"name":"Phishing basics","modname":"scorm","url":"https://x/mod/scorm/view.php?id=5"},{"name":"Intro","modname":"label"},{"name":"News","modname":"forum"}]}]"#
        let acts = Moodle.materials(try JSONDecoder().decode([Moodle.Section].self, from: Data(actJSON.utf8)), fallback: .distantPast)
        check(acts.map(\.title) == ["Phishing basics"] && acts.first?.link == "https://x/mod/scorm/view.php?id=5",
              "materials: other activities (SCORM…) kept as links; labels and forums skipped")
    } catch { check(false, "activity fixture decodes (\(error))") }
    check(!Moodle.isResult("scheduler", "Appointments Booking Fall 26/27") && !Moodle.isResult("organizer", "Appointments Booking Fall 26/27"), "results: scheduler/organizer bookings excluded")

    let base = Subject.all[0]
    let newer = Subject(id: base.id, name: base.name, code: base.code, hue: base.hue, assessments: base.assessments, assignments: base.assignments,
                        materials: base.materials, announcements: base.announcements + [Announcement(title: "Room change", source: .moodle, from: "Dr. X", date: .now, body: "Room B204")])
    let ch = Notifier.changes(old: [base], new: [newer])
    check(ch.count == 1 && ch[0].title.contains("Room change") && Notifier.changes(old: [base], new: [base]).isEmpty, "notifications: only what's new")

    // Not results: attendance and the mid-term course-feedback survey.
    check(!Moodle.isResult("assign", "Class Attendance (Week 4-14)") && !Moodle.isResult("feedback", "Anything")
          && !Moodle.isResult("assign", "Mid-Term Evaluation"), "results: attendance / evaluation / feedback excluded")
    check(Moodle.isResult("assign", "Quiz 1 Results") && Moodle.isResult("quiz", "Midterm Exam"), "results: quizzes and exams kept")
    check(!Moodle.isResult("assign", "Lab 7 Submission") && Moodle.isResult("assign", "Assignment 1 Submission"),
          "results: lab submissions excluded, assignment submissions kept")
    check(Moodle.kind("assign", "Quiz 2 Results") == .quiz, "kind: 'Quiz … Results' posted as an assignment is a quiz")

    // SSO callback: moodlemobile://token=BASE64(md5(wwwroot+passport):::token:::privatetoken)
    let ssoSite = URL(string: "https://lms.example.edu")!, passport = "abc123"
    let sig = Insecure.MD5.hash(data: Data(("https://lms.example.edu" + passport).utf8)).map { String(format: "%02x", $0) }.joined()
    let reply = "moodlemobile://token=" + Data("\(sig):::tok999:::priv".utf8).base64EncodedString()
    check((try? MoodleSSO.token(from: reply, site: ssoSite, passport: passport)) == "tok999", "sso: signed callback → token")
    check((try? MoodleSSO.token(from: reply, site: ssoSite, passport: "other")) == nil, "sso: wrong passport rejected")
    check((try? MoodleSSO.token(from: "moodlemobile://token=%%%", site: ssoSite, passport: passport)) == nil, "sso: garbage rejected")

    // MARK: - Palette (U1): Campus tokens, checked in both appearances.

    func hexLum(_ hex: String) -> Double {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let v = UInt32(h, radix: 16) ?? 0
        func ch(_ x: UInt32) -> Double {
            let c = Double(x) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * ch(v >> 16 & 0xff) + 0.7152 * ch(v >> 8 & 0xff) + 0.0722 * ch(v & 0xff)
    }
    func contrast(_ a: String, _ b: String) -> Double {
        let l1 = hexLum(a), l2 = hexLum(b)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
    check(abs(contrast("#ffffff", "#2563eb") - 5.17) < 0.01,
          "palette: WCAG contrast(white, #2563eb) = 5.17 (got \(String(format: "%.3f", contrast("#ffffff", "#2563eb"))))")
    let textPairs: [(String, Token, Token)] = [
        ("text on bg", Palette.text, Palette.bg), ("text on surface", Palette.text, Palette.surface),
        ("text on raised", Palette.text, Palette.raised), ("text on accentSoft", Palette.text, Palette.accentSoft),
        ("text2 on surface", Palette.text2, Palette.surface), ("text2 on raised", Palette.text2, Palette.raised),
        ("text3 on bg", Palette.text3, Palette.bg), ("text3 on surface", Palette.text3, Palette.surface),
        ("text3 on raised", Palette.text3, Palette.raised), ("accentInk on surface", Palette.accentInk, Palette.surface),
        ("accentInk on bg", Palette.accentInk, Palette.bg), ("accentInk on accentSoft", Palette.accentInk, Palette.accentSoft),
        ("onAccent on accent", Palette.onAccent, Palette.accent),
    ]
    for light in [true, false] {
        let mode = light ? "light" : "dark"
        var worst = (value: Double.infinity, name: "")
        for (name, a, b) in textPairs {
            let c = contrast(light ? a.light : a.dark, light ? b.light : b.dark)
            if c < worst.value { worst = (c, name) }
        }
        check(worst.value >= 4.5,
              "palette: every text pair is ≥ 4.5:1 in \(mode) (worst: \(worst.name) \(String(format: "%.2f", worst.value)):1)")
    }
    // U1c: the brighter dark appearance.
    let darkOnlyPairs: [(String, Token, Token)] = [
        ("accentInk on raised", Palette.accentInk, Palette.raised), ("good on surface", Palette.good, Palette.surface),
        ("warning on surface", Palette.warning, Palette.surface), ("critical on surface", Palette.critical, Palette.surface),
        ("good on raised", Palette.good, Palette.raised), ("critical on raised", Palette.critical, Palette.raised),
    ]
    let darkPairFails = darkOnlyPairs.map { ($0.0, contrast($0.1.dark, $0.2.dark)) }.filter { $0.1 < 4.5 }
    check(darkPairFails.isEmpty,
          "palette: status and accentInk text is ≥ 4.5:1 on dark surface/raised (failing: \(darkPairFails.map { "\($0.0) \(String(format: "%.2f", $0.1))" }))")
    let surfaceStep = contrast(Palette.surface.dark, Palette.bg.dark)
    let raisedStep = contrast(Palette.raised.dark, Palette.surface.dark)
    check(surfaceStep >= 1.12 && raisedStep >= 1.2,
          "palette: dark cards stand off the page (surface/bg \(String(format: "%.2f", surfaceStep)) ≥ 1.12, raised/surface \(String(format: "%.2f", raisedStep)) ≥ 1.2)")
    check(contrast(Palette.accent.light, Palette.surface.light) >= 3 && contrast(Palette.accent.dark, Palette.surface.dark) >= 3,
          "palette: accent is ≥ 3:1 against surface in both appearances")
    let washFails = Hue.allCases.compactMap { hue -> (String, Double)? in
        let wash = hue.palette.wash
        let low = min(contrast(Palette.text3.light, wash.light), contrast(Palette.text3.dark, wash.dark))
        return low >= 4.5 ? nil : (hue.rawValue, low)
    }
    check(washFails.isEmpty,
          "palette: text3 is ≥ 4.5:1 on every course wash in both appearances (failing: \(washFails.map { "\($0.0) \(String(format: "%.2f", $0.1))" }))")
    check(Hue.courseHues == [.green, .orange, .yellow, .magenta, .violet] && !Hue.courseHues.contains(.blue)
          && Set(Hue.courseHues).count == 5,
          "palette: course hues are green, orange, yellow, magenta, violet (5, no repeats); blue belongs to the UI")
    for hue in Hue.courseHues {
        let p = hue.palette
        let lightL = p.ramp.map { hexLum($0.light) }, darkL = p.ramp.map { hexLum($0.dark) }
        let light2 = contrast(p.ramp[0].light, Palette.surface.light)
        let dark2 = contrast(p.ramp[0].dark, Palette.surface.dark)
        check(p.ramp.count == 4 && zip(lightL, lightL.dropFirst()).allSatisfy { $0 > $1 } && light2 >= 2,
              "palette: \(hue) light ramp is 4 steps running light→dark; band 0 is ≥ 2:1 on surface (\(String(format: "%.2f", light2)):1)")
        check(zip(darkL, darkL.dropFirst()).allSatisfy { $0 < $1 } && dark2 >= 2,
              "palette: \(hue) dark ramp is 4 steps running dark→bright; band 0 is ≥ 2:1 on surface (\(String(format: "%.2f", dark2)):1)")
    }
    let oldCache = #"[{"id":"old","name":"Old","code":"OLD","hue":"blue","assessments":[],"assignments":[],"materials":[],"announcements":[]}]"#
    check((try? JSONDecoder().decode([Subject].self, from: Data(oldCache.utf8)))?.first?.hue == .blue,
          "palette: an old cache whose subject says hue blue still decodes")

    // MARK: - Mail (P1): PEEK partial fetch, literal parsing, chunked reads.

    check(SchoolMail.fetchCommand(uid: 7) == "UID FETCH 7 BODY.PEEK[]<0.262144>",
          "mail: the fetch uses BODY.PEEK (nothing is marked read) and only the first 256 KB")
    let literalBody = "Subject: hi\r\n\r\nhello\r\n"
    let literalReply = Data("* 1 FETCH (UID 7 BODY[]<0> {\(literalBody.utf8.count)}\r\n\(literalBody))\r\n".utf8)
    let literalBytes = SchoolMail.literal(literalReply)
    check(literalBytes == Data(literalBody.utf8),
          "mail: the literal is the exact byte count after {n} (kept \(literalBytes?.count ?? -1) of \(literalBody.utf8.count) bytes)")
    let utf8Body = "Subject: hi\r\n\r\nh\u{00E9}llo\r\n" // é is 2 bytes, 1 character
    let utf8Reply = Data("* 1 FETCH (UID 7 BODY[]<0> {\(utf8Body.utf8.count)}\r\n\(utf8Body))\r\n".utf8)
    check(utf8Body.utf8.count > utf8Body.count && SchoolMail.literal(utf8Reply) == Data(utf8Body.utf8),
          "mail: the literal counts bytes, not characters (a 2-byte letter keeps \(utf8Body.utf8.count) bytes)")
    let bigUnit = "héllo — the final paper is due on 13 November. "
    let bigRaw = "From: UG <ug@mbzuai.ac.ae>\r\nTo: student@mbzuai.ac.ae\r\nSubject: Big mail\r\n"
        + "Date: Wed, 28 Oct 2026 16:25:00 +0400\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n"
        + String(repeating: bigUnit, count: 9_000)
    let cutMsg = SchoolMail.parse(String(decoding: Data(bigRaw.utf8).prefix(262_144), as: UTF8.self), uid: 9)
    check(cutMsg?.subject == "Big mail" && cutMsg?.body.contains("final paper") == true,
          "mail: a multibyte message cut at 262,144 bytes (mid-character) still parses to a subject and a body")
    let whole = Data("* 1 FETCH (UID 7 BODY[]<0> {\(literalBody.utf8.count)}\r\n\(literalBody))\r\nA4 OK Fetch completed\r\n".utf8)
    var reader = IMAPReader()
    reader.feed(whole.prefix(whole.count - 12))
    let early = reader.response(tag: "A4")
    reader.feed(whole.suffix(12))
    let complete = reader.response(tag: "A4")
    check(early == nil && complete != nil && SchoolMail.literal(complete!) == Data(literalBody.utf8),
          "mail: bytes fed in two chunks give nil until the tagged line arrives, then the whole response")
    // F1 / P1 #2: every byte offset, not just one lucky split.
    var splitOK = true, splitAt: Int? = nil
    for cut in 1..<whole.count {
        var r = IMAPReader()
        r.feed(whole.prefix(cut))
        if r.response(tag: "A4") != nil { splitOK = false; splitAt = cut; break }
        r.feed(whole.suffix(whole.count - cut))
        guard let reply = r.response(tag: "A4"), SchoolMail.literal(reply) == Data(literalBody.utf8) else {
            splitOK = false; splitAt = cut; break
        }
    }
    check(splitOK, "mail: a reply split at every byte offset is nil until complete, then the same literal"
          + (splitAt.map { " (failed at \($0))" } ?? ""))
    func mailError(_ response: String, login: Bool) -> MailError? {
        do { try SchoolMail.status(Data(response.utf8), tag: "A3", login: login); return nil }
        catch { return error as? MailError }
    }
    check(mailError("A3 NO [AUTHENTICATIONFAILED] Invalid credentials\r\n", login: true) == .badLogin
          && mailError("A3 NO [AUTHENTICATIONFAILED] Invalid credentials\r\n", login: false) == .server("NO"),
          "mail: a rejected sign-in is badLogin with no server text; another NO is server(NO)")
    let rejected = mailError("A3 NO [AUTHENTICATIONFAILED] a@x.com p\"w\\", login: true)
    let rejectedText = rejected?.errorDescription ?? ""
    check(rejected == .badLogin && !rejectedText.contains("a@x.com") && !rejectedText.contains("p\"w\\"),
          "mail: a rejected sign-in's message repeats neither the address nor the password")
    let authLine = SchoolMail.authenticateLine(tag: "A2", address: "a@x.com", password: "p\"w\\")
    check(authLine == "A2 AUTHENTICATE PLAIN " + Data("\0a@x.com\0p\"w\\".utf8).base64EncodedString()
          && !authLine.hasSuffix("\r\n"),
          "mail: AUTHENTICATE PLAIN carries NUL-separated address+password, base64, with no CRLF")

    // MARK: - F1 (review fixes): scrub, dedupe, document dates, routing

    let spacedPhone = scrubPersonal("Call 050 - 123 - 4567")
    check(spacedPhone.contains("[phone]") && !spacedPhone.contains(where: \.isNumber),
          "scrub: '050 - 123 - 4567' (3-character separator runs) becomes [phone] (got \(spacedPhone))")
    let plainSpacedPhone = scrubPersonal("Call 050 123 4567")
    check(plainSpacedPhone.contains("[phone]") && !plainSpacedPhone.contains(where: \.isNumber),
          "scrub: '050 123 4567' is still scrubbed (got \(plainSpacedPhone))")
    let dottedRange = "23.10.2026-25.10.2026", dottedTime = "23.10.2026 10.00"
    check(scrubPersonal(dottedRange) == dottedRange && scrubPersonal(dottedTime) == dottedTime,
          "scrub: dotted dates ('23.10.2026-25.10.2026', '23.10.2026 10.00') are not phone numbers")
    let shortDotted = "23.10.26 10.00"
    check(scrubPersonal(shortDotted) == shortDotted, "scrub: a two-digit-year dotted date ('23.10.26 10.00') is not a phone number")
    check(scrubPersonal("23.10.26") == "23.10.26", "scrub: a two-digit-year dotted date ('23.10.26') alone is not a phone number")
    let crlfSig = scrubPersonal("Submit.\r\n\r\nBest regards,\r\nDr. Jane Doe")
    check(crlfSig.contains("Submit.") && !crlfSig.contains("Jane"),
          "scrub: a CRLF signature block is cut too (got \(crlfSig))")
    let strState = Jev.scrubbedState("Contact jane.doe@mbzuai.ac.ae") as? String
    let dictScrubbed = Jev.scrubbedState(["text": "Call +971 50 123 4567", "n": 3]) as? [String: Any]
    check(strState == "Contact [email]" && dictScrubbed?["text"] as? String == "Call [phone]" && dictScrubbed?["n"] as? Int == 3,
          "scrub: Jev's yes/no state is scrubbed as a string and inside a dictionary, other values untouched")

    // B1 #3: an event is only hidden by a matching assessment/assignment within ±7 days.
    let f1Subject = Subject(id: "f1", name: "F1", code: "F1", hue: .green, assessments: [],
        assignments: [AssignmentItem(title: "Final Paper", due: Date.now.addingTimeInterval(21 * 86_400), status: .open)],
        materials: [], announcements: [],
        events: [CourseEvent(title: "Final Paper submission", date: Date.now.addingTimeInterval(2 * 86_400),
                             source: .announcement, detail: "Final Paper submission opens")])
    let f1Board = boardItems([f1Subject])
    let f1Event = f1Board.first { $0.source == .announcement }
    check(f1Board.count == 2 && f1Event?.headlineCache == f1Event.map { mainPoint($0.title) },
          "board: an event 3 weeks away from a same-named open assignment is still shown, headline cached (got \(f1Board.count) items)")

    // F1-12: course-page dates survive a re-sync; only PDF dates are replaced.
    let pageDate = CourseEvent(title: "Quiz 2", date: Date.now.addingTimeInterval(86_400), source: .document,
                               detail: "On the course page: Quiz 2 is on 12 November")
    let pdfDate = CourseEvent(title: "Final", date: Date.now.addingTimeInterval(2 * 86_400), source: .document,
                              detail: "Final exam 15 December")
    let chemSubject = Subject(id: "chem", name: "Chemistry", code: "CHEM101", hue: .green, assessments: [], assignments: [],
                              materials: [], announcements: [], events: [pageDate, pdfDate])
    let stripped = withPDFDates([chemSubject], [:])
    let reapplied = withPDFDates(stripped, ["chem": [pdfDate]])
    let appliedTwice = withPDFDates(reapplied, ["chem": [pdfDate]])
    check(isPDFDate(pdfDate) && !isPDFDate(pageDate)
          && stripped.first?.events?.map(\.title) == ["Quiz 2"]
          && reapplied.first?.events?.count == 2 && appliedTwice.first?.events?.count == 2,
          "documents: re-syncing drops the stale PDF date, keeps the course-page one, and never duplicates it")

    // F1-13: the GENERAL entry must not swallow a real course whose name starts with "General".
    let generalSubject = Subject(id: "general", name: "MBZUAI · General", code: "GENERAL", hue: .slate, assessments: [],
                                 assignments: [], materials: [], announcements: [])
    let chemCourse = Subject(id: "chem", name: "General Chemistry", code: "CHEM101", hue: .green, assessments: [],
                             assignments: [], materials: [], announcements: [])
    let routed = Moodle.route("General Chemistry review", [generalSubject, chemCourse])
    check(routed == 1, "messages: 'General Chemistry review' routes to CHEM101, not to GENERAL (got \(String(describing: routed)))")

    // F1-14: two board items that work out the same id collapse to the first.
    let dupWhen = Date.now.addingTimeInterval(86_400)
    let dupSubject = Subject(id: "dup", name: "Dup", code: "DUP", hue: .green, assessments: [], assignments: [], materials: [],
        announcements: [], events: [CourseEvent(title: "Quiz 3", date: dupWhen, source: .announcement, detail: "a"),
                                     CourseEvent(title: "Quiz 3", date: dupWhen, source: .announcement, detail: "b")])
    let dupBoard = boardItems([dupSubject])
    check(dupBoard.count == 1 && Set(dupBoard.map(\.id)).count == dupBoard.count && dupBoard.first?.detail == "a",
          "board: items sharing an id are collapsed, the first one kept (got \(dupBoard.count) items)")

    // F1 #7: F1 items 2–3 (the isSafeCredential guard inside IMAPConnection.open, and one command at a time on an
    // IMAPConnection) cannot be checked here: they need a live IMAP connection. They are covered by review only.

    // MARK: - Mail progress (P4)

    let oldMail = #"[{"uid":1,"subject":"S","from":"F","date":0,"body":"B"}]"#
    check((try? JSONDecoder().decode(MailStore.self, from: Data(oldMail.utf8)))?.messages.map(\.uid) == [1],
          "mail: an old mail.json (a plain array of messages) still decodes, so nothing is downloaded twice")
    check(SchoolMail.toFetch(uids: [1, 2, 3, 4, 5], have: [1], seen: [2], failures: [3: 3, 4: 1]) == [4, 5],
          "mail: toFetch skips stored and unparseable UIDs, and one that failed 3 times")

    final class MailBox: @unchecked Sendable { var store = MailStore(); var saves = 0 }
    func runDownload(_ box: MailBox, _ fetch: @escaping @Sendable (Int) async throws -> SchoolMail.Message?) {
        let sem = DispatchSemaphore(value: 0)
        Task {
            await SchoolMail.download([1, 2, 3, 4, 5], into: &box.store, fetch: fetch, save: { _ in box.saves += 1 })
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 10)
    }
    let failedDownload = MailBox()
    runDownload(failedDownload) { uid in
        if uid == 3 { throw MailError.server("NO") } // a per-message failure, not a lost connection
        return SchoolMail.Message(uid: uid, subject: "s\(uid)", from: "f", date: .now, body: "b")
    }
    check(failedDownload.store.messages.map(\.uid) == [1, 2, 4, 5] && failedDownload.store.failures == [3: 1] && failedDownload.saves == 5,
          "mail: a per-message failure is counted and saved, and doesn't stop the run (got \(failedDownload.store.messages.map(\.uid)), \(failedDownload.store.failures))")
    let unreadableMail = MailBox()
    runDownload(unreadableMail) { uid in
        uid == 2 ? nil : SchoolMail.Message(uid: uid, subject: "s\(uid)", from: "f", date: .now, body: "b")
    }
    check(unreadableMail.store.seen == [2] && unreadableMail.store.messages.map(\.uid) == [1, 3, 4, 5],
          "mail: an unparseable message goes into seen, so the next sync doesn't fetch it again")
    let closedDownload = MailBox()
    runDownload(closedDownload) { uid in
        if uid == 2 { throw MailError.closed }
        return SchoolMail.Message(uid: uid, subject: "s\(uid)", from: "f", date: .now, body: "b")
    }
    check(closedDownload.store.messages.map(\.uid) == [1] && closedDownload.store.failures == [2: 1] && closedDownload.saves == 2,
          "mail: a lost connection counts one failure for the mail in flight, saves, then stops (got \(closedDownload.store.failures))")
    let cancelledDownload = MailBox()
    let cancelDone = DispatchSemaphore(value: 0)
    Task {
        await SchoolMail.download([1, 2, 3], into: &cancelledDownload.store, fetch: { uid in
            if uid == 2 {
                withUnsafeCurrentTask { $0?.cancel() }
                throw CancellationError()
            }
            return SchoolMail.Message(uid: uid, subject: "s\(uid)", from: "f", date: .now, body: "b")
        }, save: { _ in cancelledDownload.saves += 1 })
        cancelDone.signal()
    }
    _ = cancelDone.wait(timeout: .now() + 10)
    check(cancelledDownload.store.messages.map(\.uid) == [1] && cancelledDownload.store.failures.isEmpty && cancelledDownload.saves == 1,
          "mail: a cancelled download stops without counting a failure (got \(cancelledDownload.store.failures))")
    let dyingDownload = MailBox()
    runDownload(dyingDownload) { uid in
        if uid == 3 { throw MailError.timeout }
        if uid >= 4 { throw MailError.closed }
        return SchoolMail.Message(uid: uid, subject: "s\(uid)", from: "f", date: .now, body: "b")
    }
    check(dyingDownload.store.messages.map(\.uid) == [1, 2] && dyingDownload.store.failures == [3: 1] && dyingDownload.saves == 3,
          "mail: a timeout counts one failure, a later closed connection stops the run, and 4–5 stay uncounted")
    let someMail = SchoolMail.Message(uid: 1, subject: "S", from: "F", date: .now, body: "B")
    let unreadableNote = MailStore(messages: Array(repeating: someMail, count: 49), seen: [7])
    let cleanNote = MailStore(messages: Array(repeating: someMail, count: 49))
    check(unreadableNote.note == "49 school emails · 1 skipped (unreadable date)" && cleanNote.note == "49 school emails",
          "mail: the note counts skipped-unreadable mail, and has no '·' part when nothing was skipped (got \(unreadableNote.note))")
    let roundTrip = MailStore(messages: [someMail], seen: [9], failures: [4: 2])
    check((try? JSONDecoder().decode(MailStore.self, from: JSONEncoder().encode(roundTrip))) == roundTrip,
          "mail: MailStore survives an encode → decode round-trip (messages, seen and failures)")

    // MARK: - One publish per sync (P2)

    let p2ICS = "BEGIN:VCALENDAR\nBEGIN:VEVENT\nDTSTART;TZID=Arabian Standard Time:20261110T090000\nSUMMARY:Keynote: Bruce Holsinger\nDESCRIPTION:Songs of the Machine\nEND:VEVENT\nEND:VCALENDAR"
    let p2Outlook = OutlookCalendar.parse(p2ICS)
    let p2Mail = [SchoolMail.Message(uid: 42, subject: "Quiz moved", from: "Undergraduate Office", date: .now,
                                     body: "The quiz is on 5th November at 10am.")]
    let p2Docs = [Subject.all[0].id: [CourseEvent(title: "Final", date: Date.now.addingTimeInterval(30 * 86_400),
                                                  source: .document, detail: "Final exam 15 December")]]
    let p2Normalized = normalize(moodle: Subject.all, outlook: p2Outlook, mail: p2Mail, docs: p2Docs, known: [:], titles: [:])
    let p2Chain = summarized(labeled(SchoolMail.merge(p2Mail, into: OutlookCalendar.merge(p2Outlook,
        into: withPDFDates(Subject.all, p2Docs))), [:]), [:])
    func eventKeys(_ subjects: [Subject]) -> [String] {
        subjects.flatMap { s in (s.events ?? []).map { "\(s.id)|\($0.source.rawValue)|\($0.title)|\(Int($0.date.timeIntervalSince1970))" } }.sorted()
    }
    let p2Events = p2Normalized.flatMap { s in (s.events ?? []).map { (s.id, $0) } }
    check(eventKeys(p2Normalized) == eventKeys(p2Chain)
          && p2Events.contains { $0.1.source == .outlook } && p2Events.contains { $0.1.announcement != nil },
          "sync: normalize equals the old chain by event ids, with the Outlook event and the dated mail in place")
    let p2Title = Summary(title: "Keynote", parts: [], mentionsDate: 0.9, keepsPoint: 0.9, faithful: 0.9, specific: 0.9)
    if let p2OutlookEvent = p2Events.first(where: { $0.1.source == .outlook })?.1,
       let p2MailEvent = p2Events.first(where: { $0.1.announcement != nil })?.1 {
        let p2Titles = [Summarizer.id(p2OutlookEvent): p2Title, Summarizer.id(p2MailEvent): p2Title, "stale": p2Title]
        let p2Pruned = Summarizer.prune(p2Titles, to: p2Normalized)
        check(Set(p2Pruned.keys) == [Summarizer.id(p2OutlookEvent), Summarizer.id(p2MailEvent)],
              "sync: the title prune keeps the Outlook and mail titles normalize produces, and drops a stale one")
    } else {
        check(false, "sync: normalize produced an Outlook event and a dated mail to prune")
    }
    let gate = MainActor.assumeIsolated { (Store.isCurrent(generation: 3, current: 3), Store.isCurrent(generation: 3, current: 4)) }
    check(gate.0 && !gate.1, "sync: a result from generation 3 applies only while 3 is still current")

    // MARK: - Origin & identity (B2)

    let oldCacheJSON = #"""
    [{"id":"old","name":"Old","code":"OLD","hue":"green","assessments":[],
      "assignments":[{"title":"A","due":0,"status":"Open"}],"materials":[],
      "announcements":[{"title":"N","source":"Moodle","from":"T","date":0}],
      "events":[{"title":"Quiz on 3 Oct","date":0,"source":"Document","detail":"On the course page: quiz"}]}]
    """#
    do {
        let oldCache = try JSONDecoder().decode([Subject].self, from: Data(oldCacheJSON.utf8))
        check(oldCache.first?.events?.first?.resolvedVia == .coursePage && oldCache.first?.assignments.first?.moodleID == nil
              && oldCache.first?.announcements.first?.modified == nil,
              "b2: a cache written before B2 decodes; a missing `via` is inferred (course page) and new fields stay nil")
    } catch { check(false, "b2: an old cache decodes (\(error))") }
    let oldAnnouncement = #"{"title":"N","source":"Moodle","from":"T","date":0}"#
    check((try? JSONDecoder().decode(Announcement.self, from: Data(oldAnnouncement.utf8)))?.modified == nil,
          "b2: an announcement without `modified` decodes (edited-post support is optional)")

    let keyDate = Date(timeIntervalSince1970: 1_800_000_000)
    let movedEvent = CourseEvent(title: "Assignment 2: Eigenvalues", date: keyDate.addingTimeInterval(2 * 86_400),
                                 source: .announcement, via: .news, posted: .now)
    let originalEvent = CourseEvent(title: "Assignment 2: Eigenvalues", date: keyDate,
                                    source: .announcement, via: .news, posted: .now)
    check(memberKeys([originalEvent], subject: "la") == memberKeys([movedEvent], subject: "la"),
          "b2: a member key contains no date, so moving the date keeps the item's identity")
    let sameWords = [CourseEvent(title: "Quiz 3", date: keyDate, source: .announcement, via: .news),
                     CourseEvent(title: "Quiz 3", date: keyDate.addingTimeInterval(86_400), source: .announcement, via: .news)]
    let sameKeys = memberKeys(sameWords, subject: "s")
    check(sameKeys.count == 2 && sameKeys[0].hasSuffix("/0") && sameKeys[1].hasSuffix("/1")
          && String(sameKeys[0].dropLast(2)) == String(sameKeys[1].dropLast(2)),
          "b2: two same-keyword dates in one post get /0 and /1 (got \(sameKeys))")

    let oct1 = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 9))!
    let oct5 = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!
    let edited = Moodle.announcement(Moodle.Discussion(name: "Moved", subject: nil, message: "<p>New room</p>",
        userfullname: "Dr. X", created: Int(oct1.timeIntervalSince1970), timemodified: Int(oct5.timeIntervalSince1970)))
    check(edited.date == oct1 && edited.modified == oct5 && edited.posted == oct5 && edited.body == "New room",
          "b2: an edited post keeps its creation `date` but `posted` moves to the edit")
    let plainPost = Moodle.announcement(Moodle.Discussion(name: "Plain", subject: nil, message: nil, userfullname: nil,
        created: Int(oct1.timeIntervalSince1970), timemodified: nil))
    check(plainPost.modified == nil && plainPost.posted == plainPost.date && plainPost.from == "Moodle",
          "b2: without `timemodified`, posted == created")
    let editedPost = Announcement(title: "Room change", source: .moodle, from: "Dr. X", date: oct1,
                                  body: "The quiz moved to tomorrow", modified: oct5)
    let editedDate = editedPost.body.flatMap { Moodle.mentionedDates($0, posted: editedPost.posted, source: .announcement, via: .news).first?.date }
    check(editedPost.posted == oct5
          && editedDate.map { Calendar.current.dateComponents([.year, .month, .day], from: $0) } == DateComponents(year: 2026, month: 10, day: 6),
          "b2: 'tomorrow' in a post edited on 5 Oct resolves to 6 Oct, not to 2 Oct from its creation date")

    let calendarRef = CourseEvent(title: "Midterm Exam", date: keyDate, source: .calendar, ref: "41")
    let outlookRef = CourseEvent(title: "Keynote", date: keyDate, source: .outlook, ref: "UID-9")
    check(memberKeys([calendarRef], subject: "s") == ["c:41"] && memberKeys([outlookRef], subject: "s") == ["o:UID-9"],
          "b2: a calendar event's key is c:<event id>, an Outlook event's is o:<UID>")
    let refEvent = CourseEvent(title: "Keynote", date: Date.now.addingTimeInterval(86_400), source: .outlook, ref: "UID-9")
    let refSubject = Subject(id: "refs", name: "Refs", code: "REF", hue: .green, assessments: [], assignments: [], materials: [],
                             announcements: [], events: [refEvent])
    let refBoard = deadlines([refSubject], from: Date.now, days: 7)
    check(refBoard.count == 1 && refBoard[0].memberKey == "o:UID-9"
          && refBoard[0].memberKey == memberKeys([refEvent], subject: "refs").first,
          "b2: deadlines() puts the same memberKey on the item it produces")

    // MARK: - Ranking & reason (B3)

    var b3Cal = Calendar(identifier: .gregorian)
    b3Cal.timeZone = TimeZone(identifier: "Asia/Dubai") ?? .current
    func b3At(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 9, _ mi: Int = 0) -> Date {
        b3Cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }
    let b3LA = Subject.all[0]
    func b3Deadline(_ title: String, _ date: Date, _ w: Double, _ type: AssessmentType?, cutoff: Date? = nil) -> Deadline {
        Deadline(id: title, subject: b3LA, title: title, date: date, weight: Int(w), kind: .deadline,
                 type: type, givenWeight: Weighting(value: w, from: .moodle), cutoff: cutoff)
    }
    let b3Now = b3At(2026, 10, 28)
    let b3Board = boardItems(Subject.all)
    let b3Table: [(String, Double)] = [
        ("linear-algebra|Assignment 2", 48.0), ("intro-to-ai|Midterm", 37.5), ("linear-algebra|Problem sheet 7", 20.0),
        ("advanced-python|Assignment 2", 3.0), ("linear-algebra|Reading: Strang §6.1", 2.3),
        ("advanced-python|Code review: PR #12", 1.6), ("advanced-python|Lab 3: asyncio drills", 1.5),
        ("linear-algebra|Final", 0.93),
    ]
    let b3Actual = b3Table.compactMap { name, want in
        b3Board.first { "\($0.subject.id)|\($0.title)" == name }.map { (name, want, $0.priority(now: Date.now)) }
    }
    let b3Off = b3Actual.filter { abs($0.2 - $0.1) > 0.1 }
    check(b3Actual.count == b3Table.count && b3Off.isEmpty,
          "ranking: every §1.5 sample row within 0.1; off: \(b3Off.map { "\($0.0) \(String(format: "%.2f", $0.2)) vs \($0.1)" }))")
    check(doNext(b3Board, now: Date.now).map(\.title) == ["Assignment 2", "Midterm", "Problem sheet 7"],
          "ranking: Do next picks Assignment 2, the AI Midterm and Problem sheet 7 (got \(doNext(b3Board, now: Date.now).map(\.title)))")

    let wMoodle = Ranking.weighting(moodle: 12, syllabus: 7.5, spare: nil, title: "TED-Talk Script (8%)", type: .assignment)
    let wSyllabus = Ranking.weighting(moodle: 0, syllabus: 7.5, spare: nil, title: "TED-Talk Script (8%)", type: .quiz)
    let wTypical = Ranking.weighting(moodle: nil, syllabus: nil, spare: nil, title: "Problem sheet 7", type: .assignment)
    check(wMoodle.value == 12 && wMoodle.text == "12%" && wSyllabus.value == 7.5 && wSyllabus.text == "7.5%"
          && wTypical.value == 5 && wTypical.estimate && wTypical.text == "~5% est.",
          "ranking: Moodle 12 beats a title's (8%); the syllabus 7.5 beats it too; with neither it is a ~5% estimate")
    let spareWeight = Ranking.weighting(moodle: nil, syllabus: nil, spare: 7.5, title: "Quiz 5", type: .quiz)
    check(spareWeight.value == 7.5 && spareWeight.spare && spareWeight.text == "7.5% if it counts"
          && syllabusPerItem("AI1110", "Quiz 5") == 7.5,
          "ranking: a spare syllabus quiz counts 7.5% with 'if it counts'")

    check(b3Deadline("Assignment 2", b3Now.addingTimeInterval(2 * 86_400), 12, .assignment).reason(now: b3Now, calendar: b3Cal)
          == "12% · due in 2 days · ~6 h of work → start today",
          "ranking: 12% due in 2 days reads '→ start today' (got \(b3Deadline("Assignment 2", b3Now.addingTimeInterval(2 * 86_400), 12, .assignment).reason(now: b3Now, calendar: b3Cal)))")
    let b3TED = b3Deadline("TED-Talk Script (8%)", b3At(2026, 11, 1, 23, 59), 8, .assignment)
    check(b3TED.reason(now: b3Now, calendar: b3Cal) == "8% · due in 4 days · ~4 h of work → start by Sat 31 Oct",
          "ranking: 8% due 1 Nov reads '→ start by Sat 31 Oct' (got \(b3TED.reason(now: b3Now, calendar: b3Cal)))")
    let b3Behind = b3Deadline("Project Report", b3Now.addingTimeInterval(3 * 86_400), 24, .assignment)
    check(b3Behind.reason(now: b3Now, calendar: b3Cal) == "24% · due in 3 days · ~12 h of work, behind by ~1 day",
          "ranking: slack −1 reads 'behind by ~1 day' (got \(b3Behind.reason(now: b3Now, calendar: b3Cal)))")
    let b3Project = b3Deadline("Final Project Report", b3Now.addingTimeInterval(10 * 86_400), 30, .project)
    let b3Small = b3Deadline("Problem sheet 8", b3Now.addingTimeInterval(86_400), 5, .assignment)
    check(b3Project.priority(now: b3Now) > b3Small.priority(now: b3Now),
          "ranking: a 30% project in 10 days outranks a ~5% item due tomorrow")
    let b3Far = b3Deadline("Far away", b3Now.addingTimeInterval(29 * 86_400), 10, .project)
    let b3Next = doNext([b3Project, b3Small, b3Far], now: b3Now, limit: 10).map(\.title)
    check(b3Next.contains("Final Project Report") && !b3Next.contains("Far away"),
          "ranking: Do next keeps a 30% project 10 days out and drops one 29 days out (got \(b3Next))")

    let nov1 = Int(b3At(2026, 11, 1, 23, 59).timeIntervalSince1970)
    let nov4 = Int(b3At(2026, 11, 4, 23, 59).timeIntervalSince1970)
    let b3Assign = Moodle.Assign(id: 1, name: "Final Paper", duedate: nov1)
    let extended = Moodle.effective(b3Assign, extension: nov4)
    let noExtension = Moodle.effective(b3Assign, extension: 0)
    let earlyExtension = Moodle.effective(b3Assign, extension: nov1 - 86_400)
    check(extended.duedate == nov4 && extended.extended == true
          && noExtension.duedate == nov1 && noExtension.extended == nil
          && earlyExtension.duedate == nov1 && earlyExtension.extended == false,
          "ranking: an extension moves the due date and flags 'extended'; 0 and an earlier date leave it alone")

    let b3Nov2 = b3At(2026, 11, 2)
    let late = b3Deadline("Late paper", b3At(2026, 11, 1, 23, 59), 10, .assignment, cutoff: b3At(2026, 11, 6, 23, 59))
    let closed = b3Deadline("Closed paper", b3At(2026, 11, 1, 23, 59), 10, .assignment, cutoff: b3At(2026, 11, 1, 12))
    let overdue = b3Deadline("Overdue paper", b3At(2026, 11, 1, 23, 59), 10, .assignment)
    let b3Open = doNext([late, closed, overdue], now: b3Nov2, limit: 10).map(\.title)
    check(late.reason(now: b3Nov2, calendar: b3Cal).contains("late until Fri 6 Nov")
          && !b3Open.contains("Closed paper") && b3Open.contains("Overdue paper")
          && overdue.reason(now: b3Nov2, calendar: b3Cal).contains("overdue"),
          "ranking: past due but before the cutoff is 'late until …'; past the cutoff it leaves Do next; no cutoff stays overdue")

    // MARK: - F1d: kinds, tags, ordinals, overdue, crunch

    let kindCases: [(String, AssessmentType)] = [
        ("Critical Writing - Final Paper - 14%", .assignment), ("Final Project Presentation", .project),
        ("Final Exam", .final), ("Final", .final), ("Midterm exam", .midterm), ("Final exam paper", .final),
    ]
    let kindWrong = kindCases.filter { Moodle.kind(nil, $0.0) != $0.1 }
    check(kindWrong.isEmpty, "kind: hand-in words beat 'final'/'midterm' (wrong: \(kindWrong.map { "\($0.0) → \(Moodle.kind(nil, $0.0))" }))")
    let bareDate = CourseEvent(title: "Dec 8 — -", date: b3Now.addingTimeInterval(-86_400), source: .announcement, via: .news)
    let quizA = CourseEvent(title: "Quiz 3", date: b3Now.addingTimeInterval(86_400), source: .announcement, via: .news)
    let quizB = CourseEvent(title: "Quiz 3", date: b3Now.addingTimeInterval(2 * 86_400), source: .announcement, via: .news)
    let keysWithoutBare = memberKeys([quizA, quizB], subject: "s")
    let keysWithBare = memberKeys([bareDate, quizA, quizB], subject: "s")
    check(Array(keysWithBare.dropFirst()) == keysWithoutBare && keysWithBare.first?.hasSuffix("/-") == true,
          "b2: a bare-date line takes no ordinal and doesn't shift the visible items' memberKeys (got \(keysWithBare))")
    let closedItem = b3Deadline("Closed one", b3Now.addingTimeInterval(3 * 3600), 5, .assignment, cutoff: b3Now.addingTimeInterval(-60))
    let twoOpen = [b3Deadline("A", b3Now.addingTimeInterval(3600), 5, .assignment),
                   b3Deadline("B", b3Now.addingTimeInterval(7200), 5, .assignment)]
    check(crunch(twoOpen, now: b3Now) == nil && crunch(twoOpen + [closedItem], now: b3Now) == nil,
          "crunch: a closed assignment doesn't count toward the 3-in-48-h rule")
    let noWeightTag = Ranking.weighting(moodle: nil, syllabus: nil, spare: nil, title: "Problem sheet 7", type: .assignment).tag
    let spareTag = Ranking.weighting(moodle: nil, syllabus: nil, spare: 7.5, title: "Quiz 5", type: .quiz).tag
    check(noWeightTag == "~5%" && spareTag == "≤ 7.5%",
          "tags: a weightless Moodle item reads ~N%, never 0%; a spare reads ≤ 7.5% (got \(noWeightTag) / \(spareTag))")
    func guess(_ title: String, _ date: Date) -> Deadline {
        Deadline(id: title, subject: b3LA, title: title, date: date, weight: nil, kind: .deadline, type: .assignment)
    }
    let threeGuesses = (0..<3).map { guess("Guess \($0)", b3Now.addingTimeInterval(Double($0) * 3600 + 3600)) }
    let guessCrunch = crunch(threeGuesses, now: b3Now)
    let heavy = Deadline(id: "Final paper", subject: b3LA, title: "Final paper", date: b3Now.addingTimeInterval(10 * 86_400),
                         weight: 30, kind: .deadline, type: .final, givenWeight: Weighting(value: 30, from: .syllabus))
    let heavyCrunch = crunch([heavy], now: b3Now)
    check(guessCrunch?.items.count == 3 && guessCrunch?.weight == 0 && heavyCrunch?.weight == 30,
          "crunch: three ~5% estimates fire on the count rule with 0% weight; one 30% syllabus item fires on weight")
    let late13 = AssignmentItem(title: "Late work", due: b3Now.addingTimeInterval(-13 * 86_400), status: .open)
    let late15 = AssignmentItem(title: "Too late", due: b3Now.addingTimeInterval(-15 * 86_400), status: .open)
    let late20 = AssignmentItem(title: "Still open", due: b3Now.addingTimeInterval(-20 * 86_400), status: .open,
                                cutoff: b3Now.addingTimeInterval(86_400))
    let lateSubject = Subject(id: "late", name: "Late", code: "LATE", hue: .green, assessments: [],
                              assignments: [late13, late15, late20], materials: [], announcements: [])
    let lateBoard = boardItems([lateSubject])
    let lateNext = doNext(lateBoard, now: b3Now).map(\.title)
    check(lateBoard.count == 3 && Set(lateNext) == ["Late work", "Still open"] && !lateNext.contains("Too late"),
          "ranking: overdue work stays in Do next for 14 days (13 ✓, 15 ✗) or until its cutoff (20 days + cutoff ✓); got \(lateNext)")

    // MARK: - Clusters (B4)

    func b4(_ title: String, _ date: Date, via: Origin = .news, posted: Date? = nil, moved: Bool? = nil,
            kind: ItemKind = .deadline, ref: String? = nil, detail: String? = nil) -> Deadline {
        Deadline(id: "b4/" + title, subject: b3LA, title: title, date: date, weight: nil,
                 source: via == .moodleActivity ? nil : (via == .pdf || via == .coursePage ? .document : .announcement),
                 detail: detail, kind: kind, via: via, posted: posted, moved: moved, ref: ref)
    }
    func b4Is(_ date: Date, _ y: Int, _ mo: Int, _ d: Int) -> Bool {
        b3Cal.dateComponents([.year, .month, .day], from: date) == DateComponents(year: y, month: mo, day: d)
    }
    let b4SameDay = b3At(2026, 11, 2)
    let tedCluster = cluster([b4("TED-Talk Script (8%)", b3At(2026, 11, 1, 23, 59), via: .moodleActivity),
                              b4("TED Script due 1 Nov", b3At(2026, 11, 1, 23, 59), posted: b3At(2026, 10, 27))])
    check(tedCluster.count == 1 && tedCluster[0].title == "TED-Talk Script (8%)" && tedCluster[0].resolvedVia == .moodleActivity,
          "cluster: the TED script and its news mention are one item, with the Moodle title")
    check(cluster([b4("Quiz 3", b4SameDay), b4("Quiz 4", b4SameDay)]).count == 2,
          "cluster: 'Quiz 3' and 'Quiz 4' on one day stay two items")
    check(cluster([b4("Assignment 1", b4SameDay), b4("Assignment 10", b4SameDay)]).count == 2,
          "cluster: 'Assignment 1' and 'Assignment 10' stay two items")
    let presentation = cluster([b4("Presentation", b3At(2026, 10, 27), posted: b3At(2026, 10, 20)),
                                b4("Presentation", b3At(2026, 11, 3), posted: b3At(2026, 10, 25), moved: true)])
    check(presentation.count == 1 && b4Is(presentation[0].date, 2026, 11, 3),
          "cluster: a newer 'moved to' post joins its earlier mention and takes the new date (got \(presentation.count) items)")
    let movedMention = Moodle.mentionedDates("The quiz has been moved from 20 Oct to 1 Nov",
                                             posted: b3At(2026, 10, 20), source: .announcement, via: .news)
    check(movedMention.count == 1 && movedMention[0].moved == true && b4Is(movedMention[0].date, 2026, 11, 1),
          "cluster: 'moved from 20 Oct to 1 Nov' keeps only 1 Nov and marks it moved (got \(movedMention.map { "\($0.title) moved=\($0.moved ?? false)" }))")
    let moodlePaper = b4("Final Paper", b3At(2026, 11, 1, 23, 59), via: .moodleActivity)
    let conflicting = cluster([moodlePaper, b4("Final Paper", b3At(2026, 11, 4, 23, 59), posted: b3At(2026, 10, 29), moved: true)])
    check(conflicting.count == 1 && b4Is(conflicting[0].date, 2026, 11, 1)
          && conflicting[0].conflict?.contains("says moved to") == true,
          "cluster: Moodle's date wins over a newer 'moved' post, which becomes a conflict note (got \(conflicting.first?.conflict ?? "none"))")
    check(cluster([b4("Presentation", b3At(2026, 10, 27)), b4("Presentation", b3At(2026, 11, 6))]).count == 2,
          "cluster: the same words 10 days apart, with no move cue, stay two items")
    check(cluster([b4("Final Project Presentation", b3At(2026, 12, 8), ref: "schedule.pdf"),
                   b4("Final Project Presentation", b3At(2026, 12, 10), ref: "schedule.pdf")]).count == 2,
          "cluster: two rows of one schedule PDF (same ref) stay two cards even 2 days apart")
    check(cluster([b4("Presentation", b3At(2026, 10, 27)),
                   b4("Presentation", b3At(2026, 11, 6), kind: .classChange)]).count == 2,
          "cluster: a Jev classChange label alone doesn't open the 30-day window")
    check(cluster([b4("Lab 3", b4SameDay, via: .moodleActivity), b4("Lab 3", b4SameDay, via: .moodleActivity)]).count == 2,
          "cluster: two Moodle activities with the same title on one day stay two items")
    let weighted = cluster([moodlePaper, b4("Final Paper (14%)", b3At(2026, 11, 1, 23, 59), via: .pdf)])
    check(weighted.count == 1 && weighted[0].weighting.value == 14 && weighted[0].weighting.text == "14%",
          "cluster: a PDF's '(14%)' gives the weightless Moodle item its weight (got \(weighted.first?.weighting.text ?? "none"))")

    // MARK: - Wrong merges (F1e)

    let seminar1 = b4("Seminar", b3At(2026, 10, 20), via: .moodleCalendar, ref: "41")
    let seminar2 = b4("Seminar", b3At(2026, 10, 22), via: .moodleCalendar, ref: "42")
    check(cluster([seminar1, seminar2]).count == 2, "cluster: two Moodle 'Seminar' events with different ids stay two cards")
    let fair1 = b4("Career Fair", b3At(2026, 10, 20), via: .outlookCalendar, ref: "UID-A")
    let fair2 = b4("Career Fair", b3At(2026, 10, 22), via: .outlookCalendar, ref: "UID-B")
    check(cluster([fair1, fair2]).count == 2, "cluster: two Outlook 'Career Fair' events with different UIDs stay two cards")
    let classTuesday = b4("Class moved to Tuesday", b3At(2026, 11, 3), posted: b3At(2026, 10, 30), moved: true)
    let classThursday = b4("Class moved to Thursday", b3At(2026, 11, 5), posted: b3At(2026, 10, 30), moved: true)
    check(cluster([classTuesday, classThursday]).count == 2,
          "cluster: 'Class moved to Tuesday' and '… to Thursday' stay two cards")
    check(cluster([b4("No classes on Monday", b3At(2026, 11, 2)), b4("No classes on Tuesday", b3At(2026, 11, 3))]).count == 2,
          "cluster: 'No classes on Monday' and '… on Tuesday' stay two cards")
    let quizOnTuesday = b4("Quiz 3 on Tuesday", b3At(2026, 11, 3), posted: b3At(2026, 10, 28))
    let quizMovedThursday = b4("Quiz 3 moved to Thursday", b3At(2026, 11, 5), posted: b3At(2026, 10, 30), moved: true)
    let superseded = cluster([quizOnTuesday, quizMovedThursday])
    check(superseded.count == 1 && b4Is(superseded[0].date, 2026, 11, 5),
          "cluster: a newer 'moved to Thursday' supersedes 'on Tuesday' (got \(superseded.count) cards)")
    let reversedDays = cluster([quizMovedThursday, b4("Quiz 3 on Tuesday", b3At(2026, 11, 3), posted: b3At(2026, 11, 1))])
    check(reversedDays.count == 2, "cluster: with the move posted first, the same pair stays two cards")
    let pdfFirst = b4("Final Presentation", b3At(2026, 10, 27), via: .pdf, ref: "schedule.pdf")
    let pdfSecond = b4("Final Presentation", b3At(2026, 11, 6), via: .pdf, ref: "schedule.pdf")
    let pdfOut = cluster([pdfFirst, pdfSecond, b4("Final Presentation", b3At(2026, 11, 1), posted: b3At(2026, 10, 31))])
    check(!pdfOut.contains { d in
        (d.date == pdfFirst.date || d.alsoIn.contains { $0.date == pdfFirst.date })
            && (d.date == pdfSecond.date || d.alsoIn.contains { $0.date == pdfSecond.date })
    }, "cluster: two rows of one schedule PDF stay in different clusters")
    let bridgeFirst = b4("Final Presentation", b3At(2026, 10, 27), via: .pdf, ref: "schedule.pdf")
    let bridgeSecond = b4("Final Presentation", b3At(2026, 10, 29), via: .pdf, ref: "schedule.pdf")
    let bridgeNews = b4("Final Presentation", b3At(2026, 10, 28), posted: b3At(2026, 10, 27))
    let bridged = cluster([bridgeFirst, bridgeSecond, bridgeNews])
    check(bridged.count == 3 && !bridged.contains { d in
        (d.date == bridgeFirst.date || d.alsoIn.contains { $0.date == bridgeFirst.date })
            && (d.date == bridgeSecond.date || d.alsoIn.contains { $0.date == bridgeSecond.date })
    }, "cluster: a news mention can't chain one PDF ref at two dates into one cluster")

    // F1f #5: holidays named in one label keep their own dates; the day rule reads titles, not the shared sentence.
    let holidayLabel = "On the course page: Commemoration Day 30 Nov. UAE National Day 1-2 Dec."
    let commemorationPage = b4("Commemoration Day (30 Nov)", b3At(2026, 11, 30), via: .coursePage, ref: "holidays", detail: holidayLabel)
    let nationalPage = b4("UAE National Day (1-2 Dec)", b3At(2026, 12, 1), via: .coursePage, ref: "holidays", detail: holidayLabel)
    check(cluster([commemorationPage, nationalPage]).count == 2,
          "cluster: two holidays from one course-page label stay two cards (got \(cluster([commemorationPage, nationalPage]).count))")
    let commemorationPDF = b4("Commemoration Day (30 Nov)", b3At(2026, 11, 30), via: .pdf, ref: "schedule.pdf", detail: holidayLabel)
    let nationalPDF = b4("UAE National Day (1-2 Dec)", b3At(2026, 12, 1), via: .pdf, ref: "schedule.pdf", detail: holidayLabel)
    check(cluster([commemorationPDF, nationalPDF]).count == 2,
          "cluster: the same two holiday rows from a PDF stay two cards")
    check(cluster([quizOnTuesday, quizMovedThursday]).count == 1,
          "cluster: the Quiz 3 Tuesday→Thursday news pair still merges")

    // MARK: - Filters (B6)

    let filterOther = Subject(id: "oth", name: "Other", code: "OTH", hue: .orange, assessments: [], assignments: [],
                              materials: [], announcements: [])
    func fItem(_ id: String, _ subject: Subject, _ date: Date, _ via: Origin, kind: ItemKind? = .deadline,
               also: [Deadline] = [], ref: String? = nil, confidence: Double? = nil) -> Deadline {
        Deadline(id: id, subject: subject, title: id, date: date, weight: nil,
                 source: via == .moodleActivity ? nil : (via == .pdf || via == .coursePage ? .document : .announcement),
                 kind: kind, via: via, alsoIn: also, ref: ref, kindConfidence: confidence)
    }
    let pdfOnlyItem = fItem("pdf-only", b3LA, b3At(2026, 11, 11), .pdf, ref: "p.pdf")
    let softKindItem = fItem("soft", b3LA, b3At(2026, 11, 12), .news, confidence: 0.45)
    let unclassifiedItem = fItem("unclassified", b3LA, b3At(2026, 11, 13), .news, kind: nil)
    let mixedItem = fItem("mixed", b3LA, b3At(2026, 11, 14), .moodleActivity,
                          also: [fItem("mixed-pdf", b3LA, b3At(2026, 11, 14), .pdf, ref: "q.pdf")])
    let plainItem = fItem("plain", b3LA, b3At(2026, 11, 10), .news)
    let otherItem = fItem("other", filterOther, b3At(2026, 11, 15), .news)
    let filterItems = [plainItem, pdfOnlyItem, softKindItem, unclassifiedItem, mixedItem, otherItem]
    check(BoardFilter().apply(filterItems).map(\.id) == filterItems.map(\.id),
          "filter: an empty filter keeps every item, in order")
    var courseFilter = BoardFilter()
    courseFilter.courses = [filterOther.id]
    check(courseFilter.apply(filterItems).map(\.id) == ["other"], "filter: a course filter keeps only that course")
    var hideFilter = BoardFilter()
    hideFilter.hideUnsure = true
    check(hideFilter.apply(filterItems).map(\.id) == ["plain", "mixed", "other"],
          "filter: hideUnsure drops PDF-only, a 0.45 label and unclassified items, keeps a Moodle member (got \(hideFilter.apply(filterItems).map(\.id)))")
    var markedItem = fItem("marked", b3LA, b3At(2026, 11, 16), .news)
    markedItem.memberKey = "m1"
    let markedBoard = applyMarks([markedItem], [BoardState.key("m1"): Mark(state: .done, itemDate: markedItem.date, at: b3Now)], now: b3Now)
    var showFilter = BoardFilter()
    showFilter.showHidden = true
    check(BoardFilter().apply(markedBoard).isEmpty && showFilter.apply(markedBoard).map(\.id) == ["marked"]
          && showFilter.apply(markedBoard)[0].hidden,
          "filter: showHidden brings a marked item back, still marked hidden")
    var picky = BoardFilter()
    picky.courses = [filterOther.id]
    picky.types = [.exam]
    picky.origins = [.pdf]
    picky.hideUnsure = true
    let rankingFilter = picky.forRanking
    check(rankingFilter.types.isEmpty && rankingFilter.origins.isEmpty && rankingFilter.courses == [filterOther.id]
          && rankingFilter.hideUnsure,
          "filter: Do next follows the course and unsure filters only, not type or origin")
    check(Moodle.namedDays("1-2 Dec") == ["12/1", "12/2"], "dates: a range '1-2 Dec' names both days")
    var variantFilter = BoardFilter()
    variantFilter.group = .submit
    variantFilter.types = [.exam]
    variantFilter.origins = [.pdf]
    variantFilter.showHidden = true
    let rankingItems = variantFilter.forRanking.apply(filterItems)
    check(variantFilter.forRanking == BoardFilter()
          && doNext(rankingItems, now: b3Now).map(\.id) == doNext(filterItems, now: b3Now).map(\.id)
          && crunch(rankingItems, now: b3Now)?.weight == crunch(filterItems, now: b3Now)?.weight,
          "filter: group, type, origin and showHidden never change Do next or crunch")

    // F1g: text mentions only merge on the same local day; Moodle items are anchors with the 3-day window.
    check(cluster([b4("Quiz 3 on 23/10", b3At(2026, 10, 23)), b4("Quiz 3 on 25/10", b3At(2026, 10, 25))]).count == 2,
          "cluster: 'Quiz 3 on 23/10' and 'on 25/10' stay two cards")
    check(cluster([b4("Quiz tomorrow", b3At(2026, 10, 27), posted: b3At(2026, 10, 26)),
                   b4("Quiz today", b3At(2026, 10, 28), posted: b3At(2026, 10, 28))]).count == 2,
          "cluster: 'Quiz tomorrow' from Monday and 'Quiz today' from Wednesday stay two cards")
    let cueYes = ["reschedule our Calculus 1 classes to Friday, 9 October", "moved from 20 Oct to 1 Nov",
                  "extended to 4 Nov", "postponed until next Monday", "changed to Wednesday 3 pm",
                  "moved to the 1st of November"]
    let cueNo = ["the rescheduled lab is still on Tuesday, next to the library", "Quiz moved to week 9",
                 "We will move to the new room on Tuesday", "the room has changed to the new building"]
    let cueMissed = cueYes.filter { $0.range(of: Moodle.moveCue, options: .regularExpression) == nil }
    let cueFalse = cueNo.filter { $0.range(of: Moodle.moveCue, options: .regularExpression) != nil }
    check(cueMissed.isEmpty && cueFalse.isEmpty,
          "cluster: move cues take base/-ing verbs and need a date after to/until (missed: \(cueMissed), false: \(cueFalse))")
    let rescheduleEvent = Moodle.mentionedDates(
        "…make-up classes scheduled for Saturday, 10 October 2026, I have obtained approval to reschedule our classes to Friday, 9 October 2026",
        posted: b3At(2026, 9, 28), source: .announcement, via: .news)
    check(rescheduleEvent.count == 1 && b4Is(rescheduleEvent[0].date, 2026, 10, 9) && rescheduleEvent[0].moved == true,
          "cluster: 'reschedule … to Friday, 9 October' keeps only 9 Oct and marks it moved (got \(rescheduleEvent.map { "\($0.title) moved=\($0.moved ?? false)" }))")
    let shortRangePage = b4("1-2 Dec National Day", b3At(2026, 12, 2), via: .coursePage, ref: "label")
    let shortRangePDF = b4("Dec 1 National Day", b3At(2026, 12, 1), via: .pdf, ref: "schedule.pdf")
    check(cluster([shortRangePage, shortRangePDF]).count == 1,
          "cluster: a ≤7-day range in the item's own title counts as the same day")
    let longRangePage = b4("1-9 Dec National Day", b3At(2026, 12, 9), via: .coursePage, ref: "label")
    check(cluster([longRangePage, shortRangePDF]).count == 2,
          "cluster: an 8-day range is not a same day, so the pair stays two cards")
    let seminarActivity = b4("Seminar", b3At(2026, 10, 21), via: .moodleActivity)
    let seminarClusters = cluster([seminarActivity, b4("Seminar", b3At(2026, 10, 20), via: .moodleCalendar, ref: "41"),
                                   b4("Seminar", b3At(2026, 10, 22), via: .moodleCalendar, ref: "42")])
    check(seminarClusters.count == 2, "cluster: the Moodle Seminar activity merges with at most one calendar event (got \(seminarClusters.count))")
    check(cluster([b4("Class cancelled Monday", b3At(2026, 11, 2)), b4("Class cancelled Tuesday", b3At(2026, 11, 3))]).count == 2,
          "cluster: 'Class cancelled' on Monday and Tuesday stay two cards")
    check(cluster([b4("TED Script due 1 Nov", b3At(2026, 11, 1, 23, 59)),
                   b4("TED Script due 1 Nov 9 am", b3At(2026, 11, 1, 9))]).count == 1,
          "cluster: two news mentions of one 1 Nov deadline are one card")

    // MARK: - Done / dismiss / snooze (B5)

    func b5(_ title: String, _ date: Date, key: String) -> Deadline {
        Deadline(id: "b5/" + title, subject: b3LA, title: title, date: date, weight: nil, source: .announcement,
                 kind: .deadline, memberKey: key, via: .news)
    }
    let b5When = b3At(2026, 11, 5)
    let b5Key = "t:s/news/-/essay/0", b5Hashed = BoardState.key(b5Key)
    let b5Item = b5("Essay", b5When, key: b5Key)
    let b5Moved = b5("Essay", b5When.addingTimeInterval(2 * 86_400), key: b5Key)
    let dismissMark = [b5Hashed: Mark(state: .dismissed, itemDate: b5When, at: b3Now)]
    let dismissedNow = applyMarks([b5Item], dismissMark, now: b3Now)[0]
    let dismissedMoved = applyMarks([b5Moved], dismissMark, now: b3Now)[0]
    check(dismissedNow.hidden && !dismissedMoved.hidden && dismissedMoved.dateChanged,
          "marks: a dismissed item comes back when its date moves 2 days, tagged as changed (D4)")
    let doneMark = [b5Hashed: Mark(state: .done, itemDate: b5When, at: b3Now)]
    check(applyMarks([b5Item], doneMark, now: b3Now)[0].hidden && applyMarks([b5Moved], doneMark, now: b3Now)[0].hidden,
          "marks: a done item stays hidden after its date moves")
    let snoozeUntil = b3Now.addingTimeInterval(3 * 86_400)
    let snoozeMark = [b5Hashed: Mark(state: .snoozed, until: snoozeUntil, itemDate: b5When, at: b3Now)]
    check(applyMarks([b5Item], snoozeMark, now: b3Now)[0].hidden
          && !applyMarks([b5Item], snoozeMark, now: snoozeUntil.addingTimeInterval(60))[0].hidden,
          "marks: a snoozed item is hidden until its snooze time, then visible")
    let joinedMember = Deadline(id: "b5/member", subject: b3LA, title: "Essay", date: b5When, weight: nil,
                                source: .announcement, kind: .deadline, memberKey: "t:s/news/-/essay/1", via: .news)
    let mergedByMove = cluster([b5Item, joinedMember].map { var d = $0; if d.memberKey.hasSuffix("/1") { d.moved = true; d.posted = b3Now }; return d })
    let memberMark = [BoardState.key("t:s/news/-/essay/1"): Mark(state: .dismissed, itemDate: b5When, at: b3Now)]
    check(mergedByMove.count == 1 && mergedByMove[0].alsoIn.count == 1
          && applyMarks(mergedByMove, memberMark, now: b3Now)[0].hidden,
          "marks: a mark on a member applies to the whole cluster")
    let oldMarkKey = BoardState.key("t:s/news/-/old/0"), keptMarkKey = BoardState.key("t:s/news/-/keep/0")
    let ageing = [oldMarkKey: Mark(state: .done, itemDate: b3Now.addingTimeInterval(-31 * 86_400), at: b3Now),
                  keptMarkKey: Mark(state: .done, itemDate: b3Now.addingTimeInterval(-29 * 86_400), at: b3Now)]
    check(pruneMarks(ageing, live: [], now: b3Now).keys.sorted() == [keptMarkKey]
          && pruneMarks(ageing, live: [oldMarkKey], now: b3Now).count == 2,
          "marks: pruning drops a 31-day-old mark with no source, keeps a 29-day one and any live key")
    let b5Monday = b3At(2026, 11, 2, 7) // a Monday, before 08:00
    let mondaySnooze = snoozeOptions(b5("Essay", b3At(2026, 11, 10), key: b5Key), now: b5Monday, calendar: b3Cal)
        .first { $0.label.contains("Monday") }?.until
    check(mondaySnooze.map { b3Cal.dateComponents([.year, .month, .day, .hour], from: $0) }
          == DateComponents(year: 2026, month: 11, day: 9, hour: 8),
          "marks: on Monday 07:00, the Monday snooze means the next Monday 08:00")
    let edgeKey = BoardState.key("t:s/news/-/edge/0")
    check(pruneMarks([edgeKey: Mark(state: .done, itemDate: b3Now.addingTimeInterval(-30 * 86_400), at: b3Now)],
                     live: [], now: b3Now).count == 1
          && pruneMarks([edgeKey: Mark(state: .done, itemDate: b3Now.addingTimeInterval(-31 * 86_400), at: b3Now)],
                        live: [], now: b3Now).isEmpty,
          "marks: exactly 30 days old is kept; 31 days is dropped")
    let boardStateBase = FileManager.default.temporaryDirectory.appendingPathComponent("aa-board-state-\(UUID().uuidString)", isDirectory: true)
    do {
        defer { try? FileManager.default.removeItem(at: boardStateBase) }
        let boardStateFile = boardStateBase.appendingPathComponent("board-state.json")
        try writeOwnerOnly(Data("{}".utf8), to: boardStateFile)
        check(perms(boardStateFile.deletingLastPathComponent().path(percentEncoded: false)) == 0o700
              && perms(boardStateFile.path(percentEncoded: false)) == 0o600,
              "marks: board-state.json lands in a 0700 folder as a 0600 file")
    } catch { check(false, "marks: board-state.json write runs (\(error))") }

    // MARK: - Summarizer targets (P9)

    let p9When = b3At(2026, 11, 1, 23, 59)
    let p9Event = CourseEvent(title: "Final Paper due 1 Nov", date: p9When, source: .announcement,
                              detail: "Final Paper due 1 Nov", origin: "Final Paper due 1 Nov", via: .news)
    func p9Subject(_ status: AssignmentItem.Status) -> Subject {
        Subject(id: "p9", name: "P9", code: "P9", hue: .green, assessments: [],
                assignments: [AssignmentItem(title: "Final Paper", due: p9When, status: status)],
                materials: [], announcements: [], events: [p9Event])
    }
    let p9Window = b3At(2026, 10, 1)...b3At(2026, 12, 1)
    let p9OpenSubject = p9Subject(.open)
    let p9DoneSubject = p9Subject(.submitted)
    let p9OpenTargets = Summarizer.targets([p9OpenSubject], board: boardItems([p9OpenSubject]), titles: [:], window: p9Window)
    let p9DoneTargets = Summarizer.targets([p9DoneSubject], board: boardItems([p9DoneSubject]), titles: [:], window: p9Window)
    let p9Bare = CourseEvent(title: "Dec 8 — -", date: p9When, source: .announcement, via: .news)
    let p9BareSubject = Subject(id: "p9b", name: "P9B", code: "P9B", hue: .green, assessments: [], assignments: [],
                                materials: [], announcements: [], events: [p9Bare])
    check(Summarizer.targets([p9BareSubject], board: boardItems([p9BareSubject]), titles: [:], window: p9Window).isEmpty,
          "summarizer: an event with no content ('Dec 8 — -') never gets a request")
    check(p9OpenTargets.isEmpty && p9DoneTargets.count == 1 && p9DoneTargets[0].event.title == p9Event.title,
          "summarizer: a post behind an open Moodle assignment isn't summarized; once submitted it is (got \(p9OpenTargets.count) / \(p9DoneTargets.count))")

    let hiddenPost = CourseEvent(title: "Final Paper", date: b3At(2026, 11, 1, 23, 59), source: .announcement,
                                 detail: "Final Paper due 1 Nov", origin: "Final Paper due 1 Nov", via: .news)
    let hiddenSubject = Subject(id: "hidden", name: "Hidden", code: "HID", hue: .green, assessments: [],
                                assignments: [AssignmentItem(title: "Final Paper", due: b3At(2026, 11, 1, 23, 59), status: .open)],
                                materials: [], announcements: [], events: [hiddenPost])
    let hiddenBoard = boardItems([hiddenSubject])
    let hiddenTitle = [Summarizer.id(hiddenPost): Summary(title: "Final paper due", parts: [], mentionsDate: 0.9,
                                                          keepsPoint: 0.9, faithful: 0.9, specific: 0.9)]
    check(hiddenBoard.count == 1 && hiddenBoard[0].alsoIn.count == 1
          && Summarizer.prune(hiddenTitle, to: [hiddenSubject]).count == 1,
          "summarizer: a hidden cluster member keeps its paid title (prune drops nothing it would re-buy)")

    // MARK: - PDF cache & bounded parallelism (B7)

    var pdfLoads = 0
    let pdfKey = PDFCache.Key(path: "/tmp/aa-fixture-1.pdf", size: 10, modified: 100)
    let pdfEntry1 = PDFCache.entry(pdfKey) { pdfLoads += 1; return "Quiz on 10 Oct" }
    let pdfEntry2 = PDFCache.entry(pdfKey) { pdfLoads += 1; return "should not be read" }
    let pdfEntry3 = PDFCache.entry(PDFCache.Key(path: "/tmp/aa-fixture-1.pdf", size: 10, modified: 200)) {
        pdfLoads += 1
        return "Final on 1 Nov"
    }
    check(pdfEntry1?.text == "Quiz on 10 Oct" && pdfEntry1?.found.count == 1
          && pdfEntry2?.text == "Quiz on 10 Oct" && pdfLoads == 2 && pdfEntry3?.text == "Final on 1 Nov",
          "b7: PDFCache reads a file once, serves the stored entry, and re-reads after its modified time changes (loads \(pdfLoads))")

    final class LoadBox: @unchecked Sendable {
        private let lock = NSLock()
        private var current = 0
        private(set) var peak = 0
        func enter() { lock.lock(); current += 1; peak = max(peak, current); lock.unlock() }
        func leave() { lock.lock(); current -= 1; lock.unlock() }
    }
    final class MapResult: @unchecked Sendable { var values: [Int] = [] }
    let loadBox = LoadBox(), mapResult = MapResult()
    let mapDone = DispatchSemaphore(value: 0)
    Task {
        mapResult.values = (try? await boundedMap(Array(0..<10), limit: 4) { i in
            loadBox.enter()
            try? await Task.sleep(nanoseconds: UInt64.random(in: 2_000_000...25_000_000))
            loadBox.leave()
            return i * 10
        }) ?? []
        mapDone.signal()
    }
    _ = mapDone.wait(timeout: .now() + 30)
    check(mapResult.values == (0..<10).map { $0 * 10 } && loadBox.peak <= 4 && loadBox.peak > 1,
          "b7: boundedMap keeps input order and never runs more than 4 at once (peak \(loadBox.peak))")

    // MARK: - Cue, range and PDF-mark fixes (F1h)

    let cueTable: [(String, Bool)] = [
        ("…approval to reschedule our Calculus 1 classes to Friday, 9 October 2026", true),
        ("The quiz on 20 Oct has moved to room 3", false),
        ("Quiz moved to week 9", false),
        ("moved to room 3B", false),
        ("moved to the 3rd floor", false),
        ("Lab on Tuesday moved to the 3rd of December", true),
        ("the rescheduled lab is still on Tuesday, next to the library", false),
        ("moved from 20 Oct to 1 Nov", true),
        ("We will move to the new room on Tuesday", false),
        ("extended to 4 Nov", true),
        ("moved to the 1st of November", true),
        ("postponed until next Monday", true),
        ("changed to Wednesday 3 pm", true),
        ("The exam is pushing to 12/11", true),
        ("Quiz delays to 3pm", true),
        ("We are extending the deadline to Dec 3", true),
        ("The lab shifts to Thu", true),
        ("move tomorrow's office hours to today", true),
        ("Submission moved to 23.11", true),
        ("class moved to 10:30", true),
        ("grades changed to marks", false),
        ("moved to Satisfactory", false),
        ("changed to the monitor room", false),
    ]
    let cueWrong = cueTable.filter { ($0.0.range(of: Moodle.moveCue, options: .regularExpression) != nil) != $0.1 }
    check(cueWrong.isEmpty, "cluster: the 23 §2.3 cue sentences classify correctly (wrong: \(cueWrong.map(\.0)))")
    let roomMove = Moodle.mentionedDates("The quiz on 20 Oct has moved to room 3", posted: b3At(2026, 10, 10),
                                         source: .announcement, via: .news)
    check(roomMove.count == 1 && b4Is(roomMove[0].date, 2026, 10, 20) && roomMove[0].moved == nil,
          "cluster: 'moved to room 3' keeps its only date and sets no move (second net)")
    let movedToToday = Moodle.mentionedDates("We will move tomorrow's office hours to today at 3 pm",
                                             posted: b3At(2026, 10, 26), source: .announcement, via: .news)
    check(movedToToday.count == 1 && movedToToday[0].moved == true
          && b3Cal.dateComponents([.year, .month, .day, .hour], from: movedToToday[0].date)
          == DateComponents(year: 2026, month: 10, day: 26, hour: 15),
          "cluster: 'move tomorrow's … to today at 3 pm' keeps only today, moved (got \(movedToToday.count))")
    check(Moodle.namedDays("Dec 1-2 National Day") == ["12/1", "12/2"], "dates: 'Dec 1-2' names both days")
    check(Moodle.range("Dec 1-2 National Day")?.from.day == 1 && Moodle.range("Dec 1-2 National Day")?.to.day == 2,
          "dates: 'Dec 1-2' parses as a 1→2 Dec range")
    check(cluster([b4("Dec 1-2 National Day", b3At(2026, 12, 2), via: .coursePage, ref: "label"),
                   b4("Dec 1 National Day", b3At(2026, 12, 1), via: .pdf, ref: "s.pdf")]).count == 1,
          "cluster: a month-first range counts as the same day")
    check(Moodle.range("1 Oct – 15 Dec") != nil, "dates: an explicit range form parses (the span rule lives in cluster)")
    check(cluster([b4("1 Oct – 15 Dec National Day", b3At(2026, 12, 15), via: .coursePage, ref: "label"),
                   b4("Dec 1 National Day", b3At(2026, 12, 1), via: .pdf, ref: "s.pdf")]).count == 2,
          "cluster: a 75-day range absorbs nothing")
    check(cluster([b4("Quiz 1 on 1 Dec", b3At(2026, 12, 1), via: .pdf, ref: "s.pdf"),
                   b4("Quiz 1 on 5 Dec", b3At(2026, 12, 5), via: .pdf, ref: "s2.pdf")]).count == 2,
          "cluster: two separate dates in a PDF title are not a range")
    let p9DedupedAssessment = Assessment(id: "gi9", name: "Quiz 9", type: .quiz, date: b3At(2026, 11, 20), weight: 5, raw: nil, topics: [])
    let p9DedupedEvent = CourseEvent(title: "Quiz 9 closes", date: b3At(2026, 11, 22), source: .announcement,
                                     detail: "Quiz 9 closes on 22 November", origin: "Quiz 9 closes on 22 November", via: .news)
    let p9Deduped = Subject(id: "p9d", name: "P9D", code: "P9D", hue: .green, assessments: [p9DedupedAssessment],
                            assignments: [], materials: [], announcements: [], events: [p9DedupedEvent])
    check(Summarizer.targets([p9Deduped], board: boardItems([p9Deduped]), titles: [:],
                             window: b3At(2026, 10, 1)...b3At(2026, 12, 1)).isEmpty,
          "summarizer: an event deduped behind an assessment within 7 days gets no request")
    let pdfMarkKey = BoardState.key("t:s/pdf/-/final/0")
    let pdfMark = [pdfMarkKey: Mark(state: .done, itemDate: b3Now.addingTimeInterval(-40 * 86_400), at: b3Now, pdf: true)]
    check(pruneMarks(pdfMark, live: [], now: b3Now, keepPDF: true).count == 1
          && pruneMarks(pdfMark, live: [], now: b3Now).isEmpty,
          "marks: a PDF date's mark survives a run where the file couldn't be read")

    // MARK: - B7 review fixes (F1i)

    let savedDir = FileManager.default.temporaryDirectory.appendingPathComponent("aa-saved-\(UUID().uuidString)", isDirectory: true)
    do {
        defer { try? FileManager.default.removeItem(at: savedDir) }
        try FileManager.default.createDirectory(at: savedDir, withIntermediateDirectories: true)
        let savedURL = savedDir.appendingPathComponent("doc.pdf")
        let savedPath = savedURL.path(percentEncoded: false)
        let moodleModified = 1_700_000_000
        try Data(repeating: 0x41, count: 64).write(to: savedURL)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(moodleModified - 3600))], ofItemAtPath: savedPath)
        let remoteFile = MaterialFile(name: "doc.pdf", url: "https://x/doc.pdf", size: 64, modified: moodleModified)
        let staleSaved = MaterialStore.isSaved(savedURL, remoteFile)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(moodleModified))], ofItemAtPath: savedPath)
        let freshSaved = MaterialStore.isSaved(savedURL, remoteFile)
        try Data().write(to: savedURL)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(moodleModified + 3600))], ofItemAtPath: savedPath)
        let emptySaved = MaterialStore.isSaved(savedURL, remoteFile)
        check(!staleSaved && freshSaved && !emptySaved,
              "b7: a same-size file older than Moodle's modified time is re-downloaded; an empty file isn't saved (got \(staleSaved)/\(freshSaved)/\(emptySaved))")
    } catch { check(false, "b7: isSaved fixtures run (\(error))") }

    final class PDFLoads: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func bump() { lock.lock(); n += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return n }
    }
    let flightLoads = PDFLoads()
    let flightKey = PDFCache.Key(path: "/tmp/aa-fixture-flight.pdf", size: 5, modified: 300)
    let flightDone = DispatchSemaphore(value: 0)
    Task {
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    _ = PDFCache.entry(flightKey) {
                        flightLoads.bump()
                        Thread.sleep(forTimeInterval: 0.2)
                        return "Quiz on 5 Nov"
                    }
                }
            }
        }
        flightDone.signal()
    }
    _ = flightDone.wait(timeout: .now() + 10)
    check(flightLoads.count == 1, "b7: two first-time callers of one PDF parse it once (loads \(flightLoads.count))")

    // MARK: - Tiered cadence (P6)

    let tierNow = b3At(2026, 11, 2, 12)
    check(Tier.next(now: tierNow, lastSlow: nil, manual: false, cameForward: false) == .slow
          && Tier.next(now: tierNow, lastSlow: tierNow.addingTimeInterval(-60 * 60), manual: false, cameForward: false) == .slow
          && Tier.next(now: tierNow, lastSlow: tierNow.addingTimeInterval(-59 * 60), manual: false, cameForward: false) == .fast
          && Tier.next(now: tierNow, lastSlow: tierNow.addingTimeInterval(-60), manual: true, cameForward: false) == .slow
          && Tier.next(now: tierNow, lastSlow: tierNow.addingTimeInterval(-60), manual: false, cameForward: true) == .slow,
          "sync: 60 min, a manual refresh or a forward clock jump runs slow; 59 min runs fast")
    check(needsStatus(dueDate: b3Now.addingTimeInterval(86_400), cutoff: nil, graded: false, now: b3Now)
          && needsStatus(dueDate: b3Now.addingTimeInterval(-13 * 86_400), cutoff: nil, graded: false, now: b3Now)
          && needsStatus(dueDate: b3Now.addingTimeInterval(-14 * 86_400), cutoff: nil, graded: false, now: b3Now)
          && !needsStatus(dueDate: b3Now.addingTimeInterval(-15 * 86_400), cutoff: nil, graded: false, now: b3Now)
          && !needsStatus(dueDate: b3Now.addingTimeInterval(86_400), cutoff: nil, graded: true, now: b3Now)
          && needsStatus(dueDate: .distantFuture, cutoff: nil, graded: false, now: b3Now),
          "sync: submission status is asked while ungraded and up to 14 days past due (graded, 15 days and no due date excluded)")
    let prevAssessment = Assessment(id: "p1", name: "Quiz 1", type: .quiz, date: b3Now, weight: 10,
                                    raw: .init(got: 8, max: 10), topics: [])
    let prevMaterial = Material(title: "Slides", kind: .slides, date: b3Now)
    let prevAnnouncement = Announcement(title: "Old news", source: .moodle, from: "T", date: b3Now.addingTimeInterval(-86_400))
    let prevPageEvent = CourseEvent(title: "Quiz 2 on 5 Nov", date: b3Now, source: .document,
                                    detail: "On the course page: Quiz 2", via: .coursePage)
    let prevSubject = Subject(id: "c1", name: "C1", code: "C1", hue: .green, assessments: [prevAssessment],
                              assignments: [AssignmentItem(title: "Old", due: b3Now, status: .open)], materials: [prevMaterial],
                              announcements: [prevAnnouncement], events: [prevPageEvent])
    let fastSubject = Subject(id: "c1", name: "C1", code: "C1", hue: .green, assessments: [],
                              assignments: [AssignmentItem(title: "New task", due: b3Now.addingTimeInterval(86_400), status: .open)],
                              materials: [], announcements: [Announcement(title: "New news", source: .moodle, from: "T", date: b3Now)],
                              events: [CourseEvent(title: "Exam", date: b3Now.addingTimeInterval(2 * 86_400), source: .calendar)])
    let mergedFast = Moodle.merge(fast: MoodleSync(siteName: "X", subjects: [fastSubject], warnings: [], synced: b3Now), previous: [prevSubject]).subjects
    check(mergedFast.count == 1 && mergedFast[0].assessments.map(\.id) == ["p1"]
          && mergedFast[0].materials.map(\.title) == ["Slides"]
          && mergedFast[0].assignments.map(\.title) == ["New task"]
          && mergedFast[0].announcements.map(\.title) == ["New news", "Old news"]
          && (mergedFast[0].events ?? []).map(\.title) == ["Quiz 2 on 5 Nov", "Exam"],
          "sync: a fast sync keeps the previous grades, materials and course-page dates, and takes the new assignments and news")
    let generalPrev = Subject(id: "general", name: "General", code: "GENERAL", hue: .slate, assessments: [], assignments: [],
                              materials: [], announcements: [],
                              events: [CourseEvent(title: "Holiday", date: b3Now, source: .document,
                                                   detail: "On the course page: Holiday", via: .coursePage)])
    let generalMerged = Moodle.merge(fast: MoodleSync(siteName: "X", subjects: [], warnings: [], synced: b3Now), previous: [generalPrev]).subjects
    check(generalMerged.count == 1 && generalMerged[0].id == "general" && generalMerged[0].events?.map(\.title) == ["Holiday"],
          "sync: a General course made of course-page dates survives a fast sync that doesn't see it")

    // MARK: - Security (T1)

    // S2: personal details never leave the Mac in a Jev / DeepSeek request.
    let scrubbedMail = scrubPersonal("Contact jane.doe@mbzuai.ac.ae today")
    check(scrubbedMail.contains("[email]") && !scrubbedMail.contains("@"), "scrub: an email address becomes [email] (got \(scrubbedMail))")
    let phone1 = scrubPersonal("+971 50 123 4567"), phone2 = scrubPersonal("050-123-4567")
    check(phone1.contains("[phone]") && !phone1.contains(where: \.isNumber)
          && phone2.contains("[phone]") && !phone2.contains(where: \.isNumber),
          "scrub: '+971 50 123 4567' and '050-123-4567' become [phone] (got \(phone1) / \(phone2))")
    let harmless = "Quiz 2 is on 12/11/2026 at 10:00 in B204 (AI1110), worth 8%"
    check(scrubPersonal(harmless) == harmless, "scrub: dates, times, rooms, course codes and percentages are untouched")
    let signed = scrubPersonal("Submit by Oct 20.\n\nBest regards,\nDr. Jane Doe\nAssistant Professor")
    check(signed.contains("Submit by Oct 20") && !signed.contains("Jane") && !signed.contains("Assistant Professor"),
          "scrub: a sign-off and the signature below it are dropped (got \(signed))")
    let inlineThanks = "Thanks, the quiz is Monday"
    check(scrubPersonal(inlineThanks) == inlineThanks, "scrub: 'Thanks' inside a sentence is not a sign-off")
    let jevScrubbed = (try? JSONSerialization.jsonObject(with: Jev.body("Contact jane.doe@mbzuai.ac.ae about the quiz"))) as? [String: Any]
    let jevState = jevScrubbed?["state"] as? String ?? ""
    check(jevState.contains("[email]") && !jevState.contains("jane.doe@"), "scrub: Jev's request state is scrubbed before it is sent")
    let dsScrubbed = (try? JSONSerialization.jsonObject(with: DeepSeek.body(parts: ["Email jane.doe@mbzuai.ac.ae"], date: "Fri 13 Nov"))) as? [String: Any]
    let dsUser = (dsScrubbed?["messages"] as? [[String: String]])?.last?["content"] ?? ""
    check(dsUser.contains("[email]") && !dsUser.contains("jane.doe@"), "scrub: DeepSeek's request parts are scrubbed before they are sent")
    let sentScrubbed = Summarizer.sentences(scrubPersonal("Quiz moved to Oct 20.\n\nBest regards,\nDr. Jane Doe\nAssistant Professor\njane@x.edu"))
    check(!sentScrubbed.contains { $0.contains("Jane") || $0.contains("Professor") || $0.contains("@") },
          "scrub: the sentences summarized carry no signature, title or email (got \(sentScrubbed))")

    // S4: a credential with a control character must be refused before curl runs.
    check(SchoolMail.isSafeCredential("abcdabcdabcdabcd")
          && !SchoolMail.isSafeCredential("") && !SchoolMail.isSafeCredential("pass\nurl = x") && !SchoolMail.isSafeCredential("a\rb"),
          "mail: isSafeCredential accepts a plain secret and rejects empty or control-character credentials")

    // S1: a grade alert names the assessment but never the score (lock screen).
    func graded(_ raw: Assessment.Raw?) -> Subject {
        Subject(id: "sec", name: "Security", code: "SEC100", hue: .blue,
                assessments: [Assessment(id: "g1", name: "Lab 3 — Buffer Overflow", type: .quiz, date: .now, weight: 10, raw: raw, topics: [])],
                assignments: [], materials: [], announcements: [])
    }
    let gradeAlerts = Notifier.changes(old: [graded(nil)], new: [graded(.init(got: 45, max: 50))])
    let gradeEntry = gradeAlerts.first { $0.title.contains("new grade") }
    check(gradeAlerts.count == 1 && gradeEntry != nil
          && gradeEntry?.title == "🎯 Security: new grade"
          && gradeEntry?.body == "Lab 3 — Buffer Overflow"
          && gradeEntry?.body.contains("%") == false && gradeEntry?.body.contains("90") == false,
          "notifier: a new grade's body is just the assessment name, no score (got \(gradeEntry?.body ?? "none"))")

    // S3: cache files stay owner-only, including after the folder's mode is loosened.
    func perms(_ path: String) -> Int? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return attrs[.posixPermissions] as? Int
    }
    let ownerBase = FileManager.default.temporaryDirectory.appendingPathComponent("aa-owner-only-\(UUID().uuidString)", isDirectory: true)
    do {
        defer { try? FileManager.default.removeItem(at: ownerBase) }
        let folder = ownerBase.appendingPathComponent("cache", isDirectory: true)
        let file = folder.appendingPathComponent("moodle-cache.json")
        try FileManager.default.createDirectory(at: ownerBase, withIntermediateDirectories: true)
        try writeOwnerOnly(Data("{}".utf8), to: file)
        let filePath = file.path(percentEncoded: false), folderPath = folder.path(percentEncoded: false)
        check(perms(folderPath) == 0o700 && perms(filePath) == 0o600 && FileManager.default.fileExists(atPath: filePath),
              "owner-only: a fresh folder is 0700 and its cache file is 0600 (got \(perms(folderPath).map { String($0, radix: 8) } ?? "nil") / \(perms(filePath).map { String($0, radix: 8) } ?? "nil"))")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folderPath)
        try writeOwnerOnly(Data("{\"x\":1}".utf8), to: file)
        check(perms(folderPath) == 0o700 && perms(filePath) == 0o600,
              "owner-only: writing again resets a loosened folder back to 0700 (got \(perms(folderPath).map { String($0, radix: 8) } ?? "nil"))")
    } catch { check(false, "owner-only: writeOwnerOnly runs (\(error))") }

    if failures.n == 0 { print("All checks passed") } else { print("\(failures.n) check(s) failed") }
    exit(failures.n == 0 ? 0 : 1)
}
