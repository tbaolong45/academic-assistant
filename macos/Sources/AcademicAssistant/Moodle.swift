import Foundation

// Moodle web-service client (REST, JSON) + mapping to the app model. Field names checked against the
// MOODLE_405_STABLE source (*_returns() definitions). Everything not guaranteed by Moodle is optional.
// The key only ever goes into the request URL and the Keychain: never into errors, logs, the cache or stdout.

enum MoodleError: LocalizedError, Equatable {
    case invalidToken, insecureSite, keychain
    case server(code: String, message: String)
    case http(Int)
    case network(String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .invalidToken: "Key rejected — copy it again from Security keys"
        case .insecureSite: "The site must be an https:// address"
        case .keychain: "Couldn't save the key to the Keychain"
        case .server(let code, let message): message.isEmpty ? code : "\(message) (\(code))"
        case .http(let status): "Moodle answered HTTP \(status)"
        case .network(let message): message
        case .badResponse(let fn): "Unexpected reply from \(fn)"
        }
    }
}

/// Result of one full sync; also the on-disk cache format.
struct MoodleSync: Codable, Sendable {
    var siteName: String
    var subjects: [Subject]
    var warnings: [String]
    var synced: Date
}

struct Moodle: Sendable {
    let site: URL
    private let token: String
    // Ephemeral: no disk URL cache, so token-bearing request URLs are never written to ~/Library/Caches.
    private static let session = URLSession(configuration: .ephemeral)

    init(site: URL, token: String) { self.site = site; self.token = token }

    /// "https://host[/path]" with trailing slashes removed; anything not HTTPS is refused.
    static func siteURL(_ text: String) throws -> URL {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), url.scheme?.lowercased() == "https", url.host() != nil else { throw MoodleError.insecureSite }
        return url
    }

    static func redact(_ text: String) -> String {
        text.replacingOccurrences(of: #"\b(ws)?token=[^&\s"']*"#, with: "$1token=[redacted]", options: .regularExpression)
    }

    /// A JSON body carrying `exception` or `errorcode` is an error, whatever the HTTP status.
    static func error(in data: Data, token: String = "") -> MoodleError? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              obj["exception"] != nil || obj["errorcode"] != nil else { return nil }
        let code = obj["errorcode"] as? String ?? "error"
        if code == "invalidtoken" { return .invalidToken }
        var message = redact(obj["message"] as? String ?? "")
        if !token.isEmpty { message = message.replacingOccurrences(of: token, with: "[redacted]") }
        return .server(code: code, message: message)
    }

    func call<T: Decodable>(_ fn: String, _ params: [(String, String)] = []) async throws -> T {
        var c = URLComponents(url: site.appending(path: "webservice/rest/server.php"), resolvingAgainstBaseURL: false)
        c?.queryItems = [.init(name: "wstoken", value: token), .init(name: "wsfunction", value: fn), .init(name: "moodlewsrestformat", value: "json")]
            + params.map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = c?.url, url.scheme == "https" else { throw MoodleError.insecureSite }
        let data: Data, response: URLResponse
        do { (data, response) = try await Self.session.data(from: url) } catch {
            // Only the description: the NSError's userInfo holds the full URL (with the key).
            throw MoodleError.network(Self.redact(error.localizedDescription).replacingOccurrences(of: token, with: "[redacted]"))
        }
        if let e = Self.error(in: data, token: token) { throw e }
        if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 { throw MoodleError.http(status) }
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw MoodleError.badResponse(fn) }
    }

    func siteInfo() async throws -> SiteInfo { try await call("core_webservice_get_site_info") }

    /// Non-fatal call: on failure, records a warning and returns nil. A rejected key still fails the sync.
    private func soft<T: Decodable>(_ label: String, _ fn: String, _ params: [(String, String)], _ warnings: inout [String]) async throws -> T? {
        do { return try await call(fn, params) } catch MoodleError.invalidToken { throw MoodleError.invalidToken } catch {
            warnings.append("\(label): \(error.localizedDescription)")
            return nil
        }
    }

    /// "Fall 2026/2027 Introduction to AI (AI1010-001)" → ("Introduction to AI", "AI1010"); nil for trainings without a course code.
    static func courseLabel(_ fullname: String) -> (name: String, code: String)? {
        guard let m = fullname.firstMatch(of: /^(?:(?:Fall|Spring|Summer|Winter)\s+\d{4}(?:\/\d{4})?\s+)?(.+?)\s*\(([A-Z]{2,5}\s?\d{3,4}[A-Z]?)(?:-\d+)?\)\s*$/)
        else { return nil }
        return (String(m.1), String(m.2))
    }

    struct CourseGroup { let code: String, name: String; let members: [Course]; var isCredit = true }

    /// One group per course code, credit courses first (in Moodle's order), then trainings (HR_…, Peer_Tutoring) one each.
    /// The lecture (the member whose name isn't "… - Lab") names the group and leads its members.
    static func groupCourses(_ courses: [Course]) -> [CourseGroup] {
        var order: [String] = [], byCode: [String: [Course]] = [:], other: [CourseGroup] = []
        for c in courses {
            guard let l = courseLabel(c.fullname ?? "") else {
                other.append(CourseGroup(code: c.shortname ?? "Course \(c.id)", name: c.fullname ?? c.shortname ?? "Course", members: [c], isCredit: false))
                continue
            }
            if byCode[l.code] == nil { order.append(l.code) }
            byCode[l.code, default: []].append(c)
        }
        let isLab = { (c: Course) in (c.fullname ?? "").range(of: #"\bLab\b"#, options: [.regularExpression, .caseInsensitive]) != nil }
        return order.map { code in
            let members = byCode[code]!.sorted { !isLab($0) && isLab($1) }
            let name = courseLabel(members[0].fullname ?? "")!.name.replacingOccurrences(of: #"\s*[-–]\s*Lab$"#, with: "", options: .regularExpression)
            return CourseGroup(code: code, name: name, members: members)
        } + other
    }

    // ponytail: calls run one after another (~3 per course + 5 shared); parallelise with a TaskGroup if syncs feel slow.
    func sync(now: Date = .now) async throws -> MoodleSync {
        let info = try await siteInfo()
        let uid = String(info.userid)
        let enrolled: [Course] = try await call("core_enrol_get_users_courses", [("userid", uid)])
        let current = Self.current(enrolled, now: now)
        var warnings: [String] = []
        // Every current course is kept. Credit courses take the validated colours in order; trainings (and any
        // credit course beyond five) are slate, so a colour is never reused.
        let shown = Self.groupCourses(current)
        var nextHue = Hue.courseHues.makeIterator()
        let hues = shown.map { g in g.isCredit ? (nextHue.next() ?? .slate) : .slate }
        let siteName = info.sitename ?? site.host() ?? "Moodle"

        let ids = shown.flatMap(\.members).enumerated().map { ("courseids[\($0.offset)]", String($0.element.id)) }
        let assigns: Assigns? = try await soft("Assignments", "mod_assign_get_assignments", ids, &warnings)
        let quizzes: Quizzes? = try await soft("Quizzes", "mod_quiz_get_quizzes_by_courses", ids, &warnings)
        let events: Events? = try await soft("Calendar", "core_calendar_get_action_events_by_timesort",
                                             [("timesortfrom", String(Int(now.timeIntervalSince1970) - 30 * 86_400)), ("limitnum", "50")], &warnings)
        let forums: [Forum]? = try await soft("Forums", "mod_forum_get_forums_by_courses", ids, &warnings)
        // Fallback only: an assignment still waiting on the student keeps its calendar action ("Add submission").
        let pending = Set((events?.events ?? []).filter { $0.modulename == "assign" && $0.action != nil }.compactMap(\.instance))
        // The real status of every assignment (the action list above is capped and fills up with attendance sessions).
        var submitted: [Int: Bool] = [:], statusError: String?
        for a in (assigns?.courses ?? []).flatMap(\.assignments) {
            do {
                let s: SubmissionStatus = try await call("mod_assign_get_submission_status", [("assignid", String(a.id))])
                if let st = s.lastattempt?.submission?.status ?? s.lastattempt?.teamsubmission?.status { submitted[a.id] = st == "submitted" }
            } catch { statusError = statusError ?? Self.redact(error.localizedDescription) }
        }
        if let statusError { warnings.append("Submission status unavailable (\(statusError)); using dates and grades instead") }
        // Every calendar event of the semester (exams and deadlines teachers add by hand, not only activities).
        let semesterStart = shown.flatMap(\.members).compactMap { Self.date($0.startdate ?? 0) }.min() ?? now.addingTimeInterval(-120 * 86_400)
        let calParams = shown.flatMap(\.members).enumerated().map { ("events[courseids][\($0.offset)]", String($0.element.id)) }
            + [("options[userevents]", "1"), ("options[siteevents]", "1"), ("options[ignorehidden]", "1"),
               ("options[timestart]", String(Int(semesterStart.timeIntervalSince1970))),
               ("options[timeend]", String(Int(now.timeIntervalSince1970) + 365 * 86_400))]
        let calendar: CalendarEvents? = try await soft("Calendar events", "core_calendar_get_calendar_events", calParams, &warnings)

        var subjects: [Subject] = []
        for (i, g) in shown.enumerated() {
            // A lecture and its "- Lab" share a course code: one subject, items merged from every Moodle course in the group.
            var assessments: [Assessment] = [], assignments: [AssignmentItem] = [], materials: [Material] = [], news: [Announcement] = [], teacherNews: [Announcement] = []
            for c in g.members {
                let code = g.code
                let start = Self.date(c.startdate ?? 0) ?? now
                let grades: GradeItems? = try await soft("\(code) grades", "gradereport_user_get_grade_items",
                                                         [("courseid", String(c.id)), ("userid", uid)], &warnings)
                let contents: [Section]? = try await soft("\(code) materials", "core_course_get_contents", [("courseid", String(c.id))], &warnings)
                for f in forums ?? [] where f.course == c.id { // announcements + every discussion forum
                    let d: Discussions? = try await soft("\(code) announcements", "mod_forum_get_forum_discussions",
                                                         [("forumid", String(f.id)), ("page", "0"), ("perpage", "100")], &warnings)
                    let posts = (d?.discussions ?? []).map(Self.announcement)
                    news += posts
                    if f.type == "news" { teacherNews += posts } // dates only from the teacher's news, not classmates' posts
                }
                let courseAssigns = assigns?.courses.first { $0.id == c.id }?.assignments ?? []
                assessments += Self.assessments(grades?.usergrades.first?.gradeitems ?? [], assigns: courseAssigns,
                                                quizzes: (quizzes?.quizzes ?? []).filter { $0.course == c.id }, fallback: start)
                    .map { Assessment(id: "\(c.id)-\($0.id)", name: $0.name, type: $0.type, date: $0.date, weight: $0.weight, raw: $0.raw, topics: $0.topics, feedback: $0.feedback) }
                let gradedAssigns = Set((grades?.usergrades.first?.gradeitems ?? [])
                    .filter { $0.itemmodule == "assign" && $0.graderaw != nil }.compactMap(\.iteminstance))
                assignments += Self.assignmentItems(courseAssigns, pending: pending, now: now, submitted: submitted, graded: gradedAssigns)
                materials += Self.materials(contents ?? [], fallback: start) + Self.briefs(courseAssigns, fallback: start)
            }
            let courseIDs = Set(g.members.map(\.id))
            let events = Self.calendarEvents(calendar?.events ?? [], courseIDs: courseIDs)
                + teacherNews.flatMap { a in a.body.map { b in
                    Self.mentionedDates(b, posted: a.date, source: .announcement, via: .news)
                        .map { var e = $0; e.origin = "\(a.title)\n\n\(b)"; e.announcement = a.key; e.posted = a.posted; return e }
                } ?? [] }
                // Dates written on the course page itself (labels, section summaries, activity descriptions).
                + materials.flatMap { m in m.text.map { t in
                    // `via` is set here, before shared dates move to General (which keeps the detail prefix too).
                    Self.mentionedDates(t, posted: m.date, source: .document, strict: true)
                        .map { CourseEvent(title: $0.title, date: $0.date, source: .document, detail: "On the course page (“\(m.title)”): \($0.detail ?? "")",
                                           origin: "\(m.title)\n\n\(t)", via: .coursePage, posted: $0.posted, ref: m.title) }
                } ?? [] }
            var seenEvents = Set<String>()
            let uniqueEvents = events.filter { seenEvents.insert("\($0.date.timeIntervalSince1970)|\($0.title)").inserted }
            subjects.append(Subject(
                id: String(g.members[0].id), name: g.name, code: g.code, hue: hues[i],
                assessments: withSyllabus(g.code, assessments.sorted { $0.date < $1.date }),
                assignments: assignments.sorted { $0.due < $1.due },
                materials: materials,
                announcements: news.sorted { $0.date > $1.date },
                events: uniqueEvents.sorted { $0.date < $1.date }
            ))
        }
        // Moodle messages (a teacher's "I need to move tomorrow's class") and notifications ("Due on…", "new content"):
        // each goes to the course whose code or name it mentions, else to General. Dates are taken from messages only;
        // notification reminders repeat (sometimes stale) assignment dates, which come from the assignments themselves.
        var generalInbox: [Announcement] = []
        func file(_ a: Announcement, dates: Bool) {
            guard let i = Self.route("\(a.title) \(a.body ?? "")", subjects) else { generalInbox.append(a); return }
            subjects[i].announcements.append(a)
            if dates, let body = a.body {
                let found = Self.mentionedDates(body, posted: a.date, source: .announcement, via: a.source == .message ? .message : .news).map { var e = $0; e.origin = "\(a.title)\n\n\(body)"; e.announcement = a.key; return e }
                subjects[i].events = ((subjects[i].events ?? []) + found).sorted { $0.date < $1.date }
            }
        }
        let convs: Conversations? = try await soft("Messages", "core_message_get_conversations", [("userid", uid), ("limitnum", "50")], &warnings)
        for c in convs?.conversations ?? [] {
            let names = Dictionary((c.members ?? []).map { ($0.id, $0.fullname ?? "Someone") }, uniquingKeysWith: { a, _ in a })
            let msgs: ConversationMessages? = try await soft("Messages", "core_message_get_conversation_messages",
                [("currentuserid", uid), ("convid", String(c.id)), ("limitnum", "100"), ("newest", "1")], &warnings)
            for m in msgs?.messages ?? [] {
                let from = m.useridfrom == info.userid ? "You" : names[m.useridfrom] ?? c.name ?? "Someone"
                let body = Self.plainText(m.text ?? "")
                file(Announcement(title: "Message from \(from)", source: .message, from: from, date: Self.date(m.timecreated ?? 0) ?? now,
                                  body: body.isEmpty ? nil : body), dates: m.useridfrom != info.userid)
            }
        }
        let notes: Notifications? = try await soft("Notifications", "message_popup_get_popup_notifications",
                                                   [("useridto", uid), ("limit", "100"), ("offset", "0"), ("newestfirst", "1")], &warnings)
        for n in notes?.notifications ?? [] {
            let body = Self.plainText(n.fullmessagehtml ?? n.fullmessage ?? n.smallmessage ?? "")
            file(Announcement(title: Self.plainText(n.subject ?? "Notification"), source: .notification, from: n.userfromfullname ?? "Moodle",
                              date: Self.date(n.timecreated ?? 0) ?? now, body: body.isEmpty ? nil : body), dates: false)
        }

        // General: site-wide and personal calendar events, plus the site's own announcements (front-page news).
        let siteForums: [Forum]? = try await soft("Site announcements", "mod_forum_get_forums_by_courses", [("courseids[0]", "1")], &warnings)
        var siteNews: [Announcement] = []
        for f in siteForums ?? [] where f.type == "news" {
            let d: Discussions? = try await soft("Site announcements", "mod_forum_get_forum_discussions",
                                                 [("forumid", String(f.id)), ("page", "0"), ("perpage", "100")], &warnings)
            siteNews += (d?.discussions ?? []).map(Self.announcement)
        }
        // The same course-page date in several courses is the university calendar (holidays, reading days): list it once, in General.
        let pageKey = { (e: CourseEvent) in "\(e.date.timeIntervalSince1970)|\(e.title)" }
        let pageEvents = subjects.flatMap { ($0.events ?? []).filter { $0.resolvedVia == .coursePage } }
        let shared = Set(Dictionary(grouping: pageEvents, by: pageKey).filter { $0.value.count > 1 }.keys)
        var sharedEvents: [String: CourseEvent] = [:]
        for i in subjects.indices {
            subjects[i].events = subjects[i].events?.filter { e in
                guard shared.contains(pageKey(e)) else { return true }
                sharedEvents[pageKey(e)] = e
                return false
            }
        }
        let generalEvents = Array(sharedEvents.values) + Self.calendarEvents(calendar?.events ?? [], courseIDs: [0, 1])
            + siteNews.flatMap { a in a.body.map { Self.mentionedDates($0, posted: a.date, source: .announcement, via: .news)
                .map { var e = $0; e.announcement = a.key; e.posted = a.posted; return e } } ?? [] }
        if !generalEvents.isEmpty || !siteNews.isEmpty || !generalInbox.isEmpty {
            subjects.append(Subject(id: "general", name: "MBZUAI · General", code: "GENERAL", hue: .slate, assessments: [], assignments: [],
                                    materials: [], announcements: (siteNews + generalInbox).sorted { $0.date > $1.date },
                                    events: generalEvents.sorted { $0.date < $1.date }))
        }
        for i in subjects.indices { subjects[i].announcements.sort { $0.date > $1.date } }
        return MoodleSync(siteName: siteName, subjects: subjects, warnings: warnings, synced: now)
    }
}

// MARK: - Wire types (only the fields we use)

extension Moodle {
    struct SiteInfo: Decodable { let sitename: String?; let userid: Int }
    struct Conversations: Decodable {
        struct Conversation: Decodable {
            struct Member: Decodable { let id: Int; let fullname: String? }
            let id: Int; let name: String?; let members: [Member]?
        }
        let conversations: [Conversation]
    }
    struct ConversationMessages: Decodable {
        struct Message: Decodable { let id: Int; let useridfrom: Int; let text: String?; let timecreated: Int? }
        let messages: [Message]
    }
    struct Notifications: Decodable {
        struct Note: Decodable {
            let id: Int; let subject: String?; let fullmessage: String?; let fullmessagehtml: String?; let smallmessage: String?
            let timecreated: Int?; let userfromfullname: String?
        }
        let notifications: [Note]
    }
    struct Course: Decodable { let id: Int; let shortname: String?; let fullname: String?; let visible: Int?; let startdate: Int?; let enddate: Int? }
    struct GradeItems: Decodable {
        struct User: Decodable { let gradeitems: [GradeItem] }
        let usergrades: [User]
    }
    struct GradeItem: Decodable {
        let id: Int
        let itemname: String?, itemtype: String?, itemmodule: String?
        let iteminstance: Int?
        let weightraw: Double?, graderaw: Double?, grademax: Double?
        let gradedatesubmitted: Int?, gradedategraded: Int?
        var feedback: String? = nil
    }
    struct Assigns: Decodable {
        struct CourseAssigns: Decodable { let id: Int; let assignments: [Assign] }
        let courses: [CourseAssigns]
    }
    struct Assign: Decodable {
        let id: Int; let name: String; let duedate: Int?
        var intro: String? = nil
        var introattachments: [Module.Content]? = nil
        init(id: Int, name: String, duedate: Int?) { self.id = id; self.name = name; self.duedate = duedate }
    }
    struct SubmissionStatus: Decodable {
        struct Attempt: Decodable { struct Sub: Decodable { let status: String? }; let submission: Sub?; let teamsubmission: Sub? }
        let lastattempt: Attempt?
    }
    struct CalendarEvents: Decodable { let events: [CalendarEvent] }
    struct CalendarEvent: Decodable {
        let name: String?, description: String?, modulename: String?, eventtype: String?
        let courseid: Int?, timestart: Int?
        var id: Int? = nil
    }
    struct Quizzes: Decodable { let quizzes: [Quiz] }
    struct Quiz: Decodable { let id: Int; let course: Int; let name: String?; let timeclose: Int? }
    struct Events: Decodable { let events: [Event] }
    struct Event: Decodable {
        struct Action: Decodable { let actionable: Bool? }
        let modulename: String?, instance: Int?, action: Action?
    }
    struct Forum: Decodable { let id: Int; let course: Int; let type: String? }
    struct Discussions: Decodable { let discussions: [Discussion] }
    struct Discussion: Decodable { let name: String?, subject: String?, message: String?, userfullname: String?; let created: Int?, timemodified: Int? }
    struct Section: Decodable { var name: String? = nil; var summary: String? = nil; let modules: [Module]? }
    struct Module: Decodable {
        struct Content: Decodable {
            let type: String?, filename: String?, fileurl: String?, mimetype: String?
            let filesize: Int?, timemodified: Int?
        }
        struct Info: Decodable { let lastmodified: Int?; let mimetypes: [String]? }
        let name: String?, modname: String?, url: String?
        var description: String? = nil // label text / activity description (HTML)
        let uservisible: Bool?
        let contents: [Content]?
        let contentsinfo: Info?
    }
}

// MARK: - Mapping (pure, covered by --self-check)

extension Moodle {
    static func date(_ t: Int) -> Date? { t > 0 ? Date(timeIntervalSince1970: Double(t)) : nil }

    /// Visible courses that haven't ended (enddate 0 = open-ended).
    static func current(_ courses: [Course], now: Date) -> [Course] {
        courses.filter { ($0.visible ?? 1) == 1 && (date($0.enddate ?? 0).map { $0 > now } ?? true) }
    }

    /// Activity grade items → assessments, dated by the matching assignment's duedate / quiz's timeclose
    /// (itemmodule + iteminstance), else the grade's own dates, else `fallback` (course start). Ordered by date.
    static func assessments(_ items: [GradeItem], assigns: [Assign], quizzes: [Quiz], fallback: Date) -> [Assessment] {
        var dates: [String: Date] = [:], names: [String: String] = [:]
        for a in assigns { dates["assign#\(a.id)"] = date(a.duedate ?? 0); names["assign#\(a.id)"] = a.name }
        for q in quizzes { dates["quiz#\(q.id)"] = date(q.timeclose ?? 0); names["quiz#\(q.id)"] = q.name }
        // "manual" = grades the teacher typed into the gradebook (e.g. paper quizzes); they show on the Grades tab too.
        return items.filter { ($0.itemtype == "mod" || $0.itemtype == "manual") && isResult($0.itemmodule, $0.itemname ?? "") }.map { g in
            let key = "\(g.itemmodule ?? "")#\(g.iteminstance ?? 0)"
            let name = g.itemname ?? names[key] ?? "Item \(g.id)"
            let raw: Assessment.Raw? = if let got = g.graderaw, let max = g.grademax, max > 0 { rawScore(got, max) } else { nil }
            let when = dates[key] ?? date(g.gradedatesubmitted ?? 0) ?? date(g.gradedategraded ?? 0) ?? fallback
            let fb = g.feedback.map(plainText).flatMap { $0.isEmpty ? nil : $0 }
            return Assessment(id: "gi\(g.id)", name: name, type: kind(g.itemmodule, name), date: when,
                              weight: Int(((g.weightraw ?? 0) * 100).rounded()), raw: raw, topics: [], feedback: fb)
        }
        .sorted { $0.date < $1.date }
    }

    /// Raw has whole numbers, so 17.5 / 20 becomes 175 / 200 (same score).
    static func rawScore(_ got: Double, _ max: Double) -> Assessment.Raw {
        let whole = { (x: Double) in abs(x - x.rounded()) < 1e-6 }
        let k = [1.0, 10, 100].first { whole(got * $0) && whole(max * $0) } ?? 100
        return .init(got: Int((got * k).rounded()), max: Int((max * k).rounded()))
    }

    /// Attendance, course-feedback ("Mid-Term Evaluation" survey) and lab hand-ins ("Lab 7 Submission") are not results.
    static func isResult(_ module: String?, _ name: String) -> Bool {
        if ["attendance", "feedback", "questionnaire", "survey", "choice", "scheduler", "organizer"].contains(module ?? "") { return false }
        return name.range(of: #"\b(attendance|evaluation|feedback|survey|questionnaire)\b|\blab\s*\d*\s*submission\b"#,
                          options: [.regularExpression, .caseInsensitive]) == nil
    }

    static func kind(_ module: String?, _ name: String) -> AssessmentType {
        let n = name.lowercased()
        func has(_ pattern: String) -> Bool { n.range(of: pattern, options: .regularExpression) != nil }
        if has(#"\bquiz"#) { return .quiz } // "Quiz 1 Results" posted as an assignment is still a quiz
        if has(#"mid-?term"#) { return .midterm }
        if has(#"\bfinal\b"#) { return .final }
        if has(#"\bmini[- ]?exam"#) { return .miniExam }
        if has(#"\bproject"#) { return .project }
        if has(#"\blab"#) { return .lab }
        return module == "quiz" ? .quiz : .assignment
    }

    /// Status from mod_assign_get_submission_status when known ("submitted" → submitted, anything else → open);
    /// otherwise from the calendar: still holding an action → open (past due = overdue), no action → submitted.
    static func assignmentItems(_ assigns: [Assign], pending: Set<Int>, now: Date, submitted: [Int: Bool] = [:],
                                graded: Set<Int> = []) -> [AssignmentItem] {
        assigns.compactMap { a in
            Optional(date(a.duedate ?? 0) ?? .distantFuture).map { // no due date → .distantFuture ("no due date"); still listed
                // Done = submitted, or already graded (e.g. a viva marked in person). With no status from Moodle:
                // still in the future → open; in the past → open only if the calendar still asks for a submission.
                let done = graded.contains(a.id) || (submitted[a.id] ?? ($0 > now ? false : !pending.contains(a.id)))
                return AssignmentItem(title: a.name, due: $0, status: done ? .submitted : .open,
                                      details: a.intro.map(plainText).flatMap { $0.isEmpty ? nil : $0 }, moodleID: a.id)
            }
        }
        .sorted { $0.due < $1.due }
    }

    /// Files attached to an assignment's instructions, as practice material ("Assignment brief: …").
    static func briefs(_ assigns: [Assign], fallback: Date) -> [Material] {
        assigns.compactMap { a in
            let files = (a.introattachments ?? []).compactMap { c -> MaterialFile? in
                guard let fn = c.filename, let url = c.fileurl else { return nil }
                return MaterialFile(name: fn, url: url, size: c.filesize ?? 0, modified: c.timemodified ?? 0)
            }
            return files.isEmpty ? nil : Material(title: "Assignment brief: \(a.name)", kind: .reading,
                                                   date: date(a.duedate ?? 0) ?? fallback, files: files)
        }
    }

    /// Calendar events for these course ids (teacher-added events, quizzes, feedback, etc.); assignment events
    /// (already listed with their real status) and attendance sessions are left out. Course id 0/1 = personal/site.
    static func calendarEvents(_ events: [CalendarEvent], courseIDs: Set<Int>) -> [CourseEvent] {
        events.compactMap { e in
            guard let cid = e.courseid, courseIDs.contains(cid), !["assign", "attendance"].contains(e.modulename ?? ""),
                  let name = e.name, name.range(of: "attendance", options: .caseInsensitive) == nil,
                  let when = date(e.timestart ?? 0) else { return nil }
            let d = e.description.map(plainText).flatMap { $0.isEmpty ? nil : $0 }
            return CourseEvent(title: name, date: when, source: .calendar, detail: d, via: .moodleCalendar, ref: e.id.map(String.init))
        }
    }

    /// Explicit dates written in text ("3rd October", "OCTOBER 28th", "12/11"), each with the sentence it sits in.
    /// Relative words ("tomorrow", "next week") are ignored; the year is taken as the one nearest after `posted`.
    // NSDataDetector misses "3rd October", so explicit forms are parsed here (day/month order as used in the UAE).
    // Compiled once: NSRegularExpression is immutable and thread-safe (PDFs are parsed on a detached task).
    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    private static let mon = #"(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)"#
    private static let dayMonth = try! NSRegularExpression(pattern: #"(?i)\b(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?"# + mon + #"\b(?:,?\s+(\d{4})\b)?"#)
    private static let monthDay = try! NSRegularExpression(pattern: #"(?i)\b"# + mon + #"\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?(?![\d:])(?!\s*(?:am|pm)\b)"#)
    private static let numeric = try! NSRegularExpression(pattern: #"\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b"#)
    private static let time = try! NSRegularExpression(pattern: #"(?i)\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b|\b(\d{1,2}):(\d{2})\b"#)
    private static let dateOnly = try! NSRegularExpression(pattern: #"(?i)^(?:"# + mon + #"\.?\s+\d{1,2}(?:st|nd|rd|th)?|\d{1,2}(?:st|nd|rd|th)?\s+"# + mon + #")$"#)

    static func mentionedDates(_ text: String, posted: Date, source: CourseEvent.Source, strict: Bool = false, via: Origin? = nil) -> [CourseEvent] {
        let cal = Calendar.current
        var out: [CourseEvent] = []
        let parts = text.components(separatedBy: CharacterSet(charactersIn: "!?\n")).flatMap { $0.components(separatedBy: ". ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        func isDateOnly(_ s: String) -> Bool { dateOnly.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }
        for (i, sentence) in parts.enumerated() {
            // A date alone on a line ("OCTOBER 28th") takes the next sentence as its context.
            var context = sentence.count < 30 && i + 1 < parts.count ? "\(sentence) — \(parts[i + 1])" : sentence
            // A table read column by column ("Oct 13 / Oct 15 / Oct 16 / Tue - … / Thu - … / Fri - …"): the n-th date of the run
            // goes with the n-th line after it.
            if isDateOnly(sentence) {
                var start = i, end = i
                while start > 0, isDateOnly(parts[start - 1]) { start -= 1 }
                while end + 1 < parts.count, isDateOnly(parts[end + 1]) { end += 1 }
                // Rows after the run, skipping empty ones ("-"), which shifted Dec 10 onto Tue's row.
                let rows = parts[(end + 1)...].filter { $0.contains(where: \.isLetter) }
                if end > start, i - start < rows.count { context = "\(sentence) — \(rows[rows.startIndex + i - start])" }
            }
            let ns = sentence as NSString, all = NSRange(location: 0, length: ns.length)
            func g(_ m: NSTextCheckingResult, _ i: Int) -> String? { m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i)) }
            func monthIndex(_ s: String) -> Int? { months.firstIndex { s.lowercased().hasPrefix($0) }.map { $0 + 1 } }
            var found: [(day: Int, month: Int, year: Int?)] = []
            for m in dayMonth.matches(in: sentence, range: all) { if let d = Int(g(m, 1) ?? ""), let mo = monthIndex(g(m, 2) ?? "") { found.append((d, mo, g(m, 3).flatMap(Int.init))) } }
            for m in monthDay.matches(in: sentence, range: all) { if let d = Int(g(m, 2) ?? ""), let mo = monthIndex(g(m, 1) ?? "") { found.append((d, mo, g(m, 3).flatMap(Int.init))) } }
            // 2: "average was 9/10" is a score, not 9 October
            let scoreTalk = sentence.range(of: #"(?i)\b(score[sd]?|grade[sd]?|marks?|average|points|out of|got)\b"#, options: .regularExpression) != nil
            for m in numeric.matches(in: sentence, range: all) {
                // Strict (documents): "2/3" in maths is not a date, so numbers need a year ("23/10/2026").
                if let d = Int(g(m, 1) ?? ""), let mo = Int(g(m, 2) ?? ""), (1...12).contains(mo), (!strict && !scoreTalk) || g(m, 3) != nil {
                    found.append((d, mo, g(m, 3).flatMap(Int.init).map { $0 < 100 ? 2000 + $0 : $0 }))
                }
            }
            // Relative words are resolved against the post date: today/tonight, tomorrow, a weekday ("Tuesday" = the next one
            // after the post; "next Tuesday" = the one in the following week).
            var relative: Date?
            if found.isEmpty && !strict { // relative words only make sense in a dated post, not in reused slides
                let low = sentence.lowercased(), postedDay = cal.startOfDay(for: posted)
                let days = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
                if low.range(of: #"\b(today|tonight|this evening)\b"#, options: .regularExpression) != nil { relative = postedDay }
                else if low.range(of: #"\btomorrow\b"#, options: .regularExpression) != nil { relative = cal.date(byAdding: .day, value: 1, to: postedDay) }
                else if let m = low.firstMatch(of: /\b(next\s+)?(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b/),
                        let wd = days.firstIndex(of: String(m.2)) {
                    var d = cal.nextDate(after: postedDay, matching: DateComponents(weekday: wd + 1), matchingPolicy: .nextTime) ?? postedDay
                    var monWeek = cal; monWeek.firstWeekday = 2
                    if m.1 != nil, monWeek.isDate(d, equalTo: postedDay, toGranularity: .weekOfYear) { d = cal.date(byAdding: .day, value: 7, to: d) ?? d }
                    relative = d
                }
                if let r = relative { let c = cal.dateComponents([.year, .month, .day], from: r); found.append((c.day!, c.month!, c.year!)) }
            }
            guard !found.isEmpty else { continue }
            var hour = 23, minute = 59 // a date with no time is a "by the end of that day" deadline
            func hasDate(_ s: String) -> Bool {
                let r = NSRange(s.startIndex..., in: s)
                return [dayMonth, monthDay, numeric].contains { $0.firstMatch(in: s, range: r) != nil }
                    || s.range(of: #"(?i)\b(today|tonight|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#, options: .regularExpression) != nil
            }
            func clock(_ s: String) -> (Int, Int)? {
                let n = s as NSString
                guard let t = time.firstMatch(in: s, range: NSRange(location: 0, length: n.length)) else { return nil }
                func g(_ i: Int) -> String? { t.range(at: i).location == NSNotFound ? nil : n.substring(with: t.range(at: i)) }
                if let h = Int(g(1) ?? ""), h <= 12 { return (h % 12 + ((g(3) ?? "").lowercased() == "pm" ? 12 : 0), Int(g(2) ?? "") ?? 0) }
                if let h = Int(g(4) ?? ""), let mi = Int(g(5) ?? ""), h < 24, mi < 60 { return (h, mi) }
                return nil
            }
            // The context line counts only if it has no date of its own ("Quiz on Oct 20. Lab on Oct 22 at 3 PM": 3 PM is the lab's).
            var places = [sentence]
            if context != sentence, !hasDate(String(context.dropFirst(sentence.count + 3))) { places.append(context) }
            for next in parts.dropFirst(i + 1).prefix(2) { if hasDate(next) { break }; places.append(next) }
            if let (h, mi) = places.lazy.compactMap(clock).first { hour = h; minute = mi }
            let postedYear = cal.component(.year, from: posted)
            for f in found where (1...31).contains(f.day) {
                guard var when = cal.date(from: DateComponents(year: f.year ?? postedYear, month: f.month, day: f.day, hour: hour, minute: minute)),
                      cal.component(.day, from: when) == f.day else { continue }
                if f.year == nil, when < posted.addingTimeInterval(-30 * 86_400), let next = cal.date(byAdding: .year, value: 1, to: when) { when = next }
                out.append(CourseEvent(title: String(context.prefix(110)), date: when, source: source, detail: context, via: via, posted: posted))
            }
        }
        return out
    }

    /// HTML → readable plain text (paragraphs and line breaks kept, tags dropped, common entities decoded).
    static func plainText(_ html: String) -> String {
        var s = html.replacingOccurrences(of: #"(?is)<(script|style)\b[^>]*>.*?</\1>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)<br\s*/?>|</p>|</li>|</div>|</h\d>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (e, c) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&rsquo;", "’"), ("&lsquo;", "‘"), ("&ldquo;", "“"), ("&rdquo;", "”"), ("&ndash;", "–"), ("&mdash;", "—"), ("&amp;", "&")] {
            s = s.replacingOccurrences(of: e, with: c)
        }
        return s.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n\s*\n+"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func materials(_ sections: [Section], fallback: Date) -> [Material] {
        func text(_ html: String?) -> String? { html.map(plainText).flatMap { $0.isEmpty ? nil : $0 } }
        // Teacher-written text on the course page: section summaries and labels (assessment notes, rubrics, dates).
        let summaries = sections.compactMap { s in
            text(s.summary).map { Material(title: plainText(s.name ?? "Section"), kind: .notes, date: fallback, text: $0) }
        }
        let labels = sections.flatMap { $0.modules ?? [] }.filter { $0.modname == "label" && $0.uservisible != false }.compactMap { m in
            text(m.description).map { t in
                Material(title: String(t.split(separator: "\n").first.map(String.init)?.prefix(80) ?? "Note"), kind: .notes, date: fallback, text: t)
            }
        }
        return summaries + labels + sections.flatMap { $0.modules ?? [] }
            // Everything except what has its own place (assignments, announcement forums, attendance) and labels (above).
            .filter { !["assign", "forum", "attendance", "label", "subsection"].contains($0.modname ?? "") && $0.uservisible != false }
            .map { m in
                let name = plainText(m.name ?? "Untitled") // "Library Guide &amp; Materials" → "&"
                let mimes = (m.contentsinfo?.mimetypes ?? []) + (m.contents ?? []).compactMap(\.mimetype)
                let modified = date(m.contentsinfo?.lastmodified ?? 0) ?? (m.contents ?? []).compactMap { date($0.timemodified ?? 0) }.max()
                let files = (m.contents ?? []).compactMap { c -> MaterialFile? in
                    guard c.type == "file", let fn = c.filename, let url = c.fileurl else { return nil }
                    return MaterialFile(name: fn, url: url, size: c.filesize ?? 0, modified: c.timemodified ?? 0)
                }
                // External link for "url" activities; for activities without files (SCORM, H5P, quiz, book…) the Moodle page.
                let link = m.modname == "url" ? (m.contents ?? []).first { $0.type == "url" }?.fileurl : (files.isEmpty ? m.url : nil)
                return Material(title: name, kind: materialKind(m.modname, name, mimes), date: modified ?? fallback,
                                files: files.isEmpty ? nil : files, link: link, text: text(m.description))
            }
            .sorted { $0.date > $1.date }
    }

    static func materialKind(_ modname: String?, _ name: String, _ mimes: [String]) -> Material.Kind {
        let n = name.lowercased()
        if mimes.contains(where: { $0.hasPrefix("video/") || $0.hasPrefix("audio/") }) || ["recording", "video", "panopto", "youtube"].contains(where: n.contains) { return .recording }
        if mimes.contains(where: { $0.contains("presentation") || $0.contains("powerpoint") }) || ["slide", "lecture"].contains(where: n.contains) { return .slides }
        if modname == "page" || modname == "folder" || n.contains("notes") { return .notes }
        return .reading
    }

    /// The course a message or notification is about: its code ("AI1115") or name ("linear algebra" also matches "Linear Algebraists").
    static func route(_ text: String, _ subjects: [Subject]) -> Int? {
        let t = text.lowercased()
        // GENERAL is the fallback, never a match: its code would catch any text saying "general" ("General Chemistry").
        let courses = subjects.indices.filter { subjects[$0].code != "GENERAL" }
        return courses.first { t.contains(subjects[$0].code.lowercased()) } ?? courses.first { t.contains(subjects[$0].name.lowercased()) }
    }

    static func announcement(_ d: Discussion) -> Announcement {
        Announcement(title: d.name ?? d.subject ?? "Announcement", source: .moodle, from: d.userfullname ?? "Moodle",
                     date: date(d.created ?? 0) ?? date(d.timemodified ?? 0) ?? .distantPast,
                     body: d.message.map(plainText).flatMap { $0.isEmpty ? nil : $0 }, modified: date(d.timemodified ?? 0))
    }
}

// MARK: - Cache (~/Library/Application Support/AcademicAssistant/moodle-cache.json; never holds the key)

enum MoodleCache {
    static var url: URL { .applicationSupportDirectory.appending(path: "AcademicAssistant/moodle-cache.json") }
    static func load() -> MoodleSync? { (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(MoodleSync.self, from: $0) } }
    static func save(_ sync: MoodleSync) throws { try writeOwnerOnly(JSONEncoder().encode(sync), to: url) } // grades: owner only
    static func delete() { try? FileManager.default.removeItem(at: url) }
}

/// Writes a cache file only the user can read: folder 0700 (re-applied every time, in case it was loosened), file 0600.
/// If only the folder's permissions can't be set, the data is still written, then the failure is thrown so it shows.
func writeOwnerOnly(_ data: Data, to url: URL) throws {
    let fm = FileManager.default, folder = url.deletingLastPathComponent()
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    let folderPrivate = (try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path(percentEncoded: false))) != nil
    try data.write(to: url, options: .atomic)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path(percentEncoded: false))
    guard folderPrivate else { throw CacheError.notPrivate }
}

enum CacheError: LocalizedError {
    case notPrivate
    var errorDescription: String? { "The app's data folder couldn't be made private to your account" }
}

// MARK: - `AcademicAssistant --moodle-check`: full sync with the stored key; prints counts and course codes only.

func runMoodleCheck() -> Never {
    guard let creds = MoodleAccount.credentials() else { print("no key stored"); exit(2) }
    Task.detached {
        do {
            let r = try await Moodle(site: creds.site, token: creds.token).sync()
            let a = r.subjects.flatMap(\.assessments)
            print([
                "courses: \(r.subjects.count) (\(r.subjects.map(\.code).joined(separator: ", ")))",
                "assessments: \(a.count) (\(a.filter { $0.raw != nil }.count) graded)",
                "deadlines next 7 days: \(deadlines(r.subjects).count)",
                "announcements: \(r.subjects.reduce(0) { $0 + $1.announcements.count })",
                "materials: \(r.subjects.reduce(0) { $0 + $1.materials.count })",
                "warnings: \(r.warnings.count)",
            ].joined(separator: " · "))
            r.warnings.forEach { print("  - \($0)") }
            exit(0)
        } catch {
            print("sync failed: \(error.localizedDescription)")
            exit(1)
        }
    }
    dispatchMain()
}
