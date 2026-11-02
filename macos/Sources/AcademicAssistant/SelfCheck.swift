import CryptoKit
import Foundation

// `AcademicAssistant --self-check` verifies the grade math and exits.
// (Swift Testing / XCTest need Xcode; the Command Line Tools lack their macro plugins.)
func runSelfCheck() -> Never {
    var failures = 0
    func check(_ ok: Bool, _ what: String) { print(ok ? "✔ \(what)" : "✘ \(what)"); if !ok { failures += 1 } }

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
    var splitOK = true, splitAt = 0
    for cut in 1..<whole.count {
        var r = IMAPReader()
        r.feed(whole.prefix(cut))
        if r.response(tag: "A4") != nil { splitOK = false; splitAt = cut; break }
        r.feed(whole.suffix(whole.count - cut))
        guard let reply = r.response(tag: "A4"), SchoolMail.literal(reply) == Data(literalBody.utf8) else {
            splitOK = false; splitAt = cut; break
        }
    }
    check(splitOK, "mail: a reply split at every byte offset is nil until complete, then the same literal (failed at \(splitAt))")
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
    let dottedRange = "23.10.2026-25.10.2026", dottedTime = "23.10.2026 10.00"
    check(scrubPersonal(dottedRange) == dottedRange && scrubPersonal(dottedTime) == dottedTime,
          "scrub: dotted dates ('23.10.2026-25.10.2026', '23.10.2026 10.00') are not phone numbers")
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
        if uid == 3 { throw MailError.timeout }
        return SchoolMail.Message(uid: uid, subject: "s\(uid)", from: "f", date: .now, body: "b")
    }
    check(failedDownload.store.messages.map(\.uid) == [1, 2, 4, 5] && failedDownload.store.failures[3] == 1 && failedDownload.saves == 5,
          "mail: a failing fetch is counted and saved, and doesn't stop the run (got \(failedDownload.store.messages.map(\.uid)))")
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
    check(closedDownload.store.messages.map(\.uid) == [1] && closedDownload.store.failures.isEmpty && closedDownload.saves == 1,
          "mail: a closed connection stops the run without counting a failure (got \(closedDownload.store.messages.map(\.uid)))")
    let someMail = SchoolMail.Message(uid: 1, subject: "S", from: "F", date: .now, body: "B")
    let unreadableNote = MailStore(messages: Array(repeating: someMail, count: 49), seen: [7])
    let cleanNote = MailStore(messages: Array(repeating: someMail, count: 49))
    check(unreadableNote.note == "49 school emails · 1 skipped (unreadable date)" && cleanNote.note == "49 school emails",
          "mail: the note counts skipped-unreadable mail, and has no '·' part when nothing was skipped (got \(unreadableNote.note))")

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

    print(failures == 0 ? "All checks passed" : "\(failures) check(s) failed")
    exit(failures == 0 ? 0 : 1)
}
