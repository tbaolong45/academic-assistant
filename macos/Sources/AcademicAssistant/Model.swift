import Foundation

// ponytail: sample data, a Swift port of lib/dashboard.ts (the website/Expo copy). Real data comes later from the connectors.

/// Course colours in fixed assignment order (never cycled — a 6th course needs a new validated hue).
enum Hue: String, Sendable, CaseIterable {
    case blue, green, orange, yellow, magenta, violet // blue: legacy only (old caches, sample data); the UI owns blue
    case slate // neutral: trainings (HR, peer tutoring) and the General entry — identity by name, never a reused course colour
    /// The validated course colours, handed out in this order to credit courses (never cycled).
    static let courseHues: [Hue] = [.green, .orange, .yellow, .magenta, .violet]
}

enum AssessmentType: String, Sendable {
    case quiz = "Quiz", assignment = "Assignment", midterm = "Midterm", final = "Final"
    case lab = "Lab", project = "Project", miniExam = "Mini-exam"
}

struct Assessment: Identifiable, Hashable, Sendable {
    struct Raw: Hashable, Sendable { let got: Int, max: Int }
    let id: String
    let name: String
    let type: AssessmentType
    let date: Date
    let weight: Int // % of the course grade
    let raw: Raw? // nil = upcoming
    let topics: [String]
    var feedback: String? = nil // the teacher's comment on this grade
    var exactWeight: Double? = nil // from a syllabus rule (7.5 = one of the best 4 quizzes; 0 = currently dropped); math uses `share`

    /// Weight used in all grade math.
    var share: Double { exactWeight ?? Double(weight) }
    var hasWeight: Bool { exactWeight != nil || weight > 0 }
    var weightText: String {
        guard let w = exactWeight else { return "\(weight)%" }
        if w == 0 { return raw == nil ? "spare · counts if it beats your lowest" : "dropped · not in your best" }
        return w == w.rounded() ? "\(Int(w))%" : String(format: "%.1f%%", w)
    }

    /// Score in %, nil while upcoming.
    var score: Int? { exactScore.map { Int($0.rounded()) } }
    /// Unrounded % ("87.5/100" stays 87.5); all grade math uses this, `score` is for display.
    var exactScore: Double? { raw.map { Double($0.got) / Double($0.max) * 100 } }
}

struct AssignmentItem: Hashable, Sendable {
    enum Status: String, Sendable { case submitted = "Submitted", open = "Open" }
    let title: String, due: Date, status: Status
    var details: String? = nil // the teacher's instructions (assignment description), plain text
    var moodleID: Int? = nil // Assign.id: a stable identity (nil in caches from before B2)
    var cutoff: Date? = nil // late submissions close then (Moodle cutoffdate, extension applied); nil = late work stays open
    var extended: Bool? = nil // `due` is the student's extension, later than the assignment's own due date
}

/// "TED-Talk Script (8%)" / "Critical Writing - Final Paper - 14%" → 8 / 14; nil if the title names no percentage.
func percentInTitle(_ title: String) -> Int? {
    guard let m = title.firstMatch(of: /(\d{1,2}(?:\.\d+)?)\s?%/) else { return nil }
    return Double(m.1).map { Int($0.rounded()) }
}

/// Something dated that isn't a Moodle activity: a calendar event a teacher added (exam, session, deadline),
/// or a date mentioned in an announcement or the syllabus/schedule.
struct CourseEvent: Hashable, Sendable, Codable {
    enum Source: String, Sendable, Codable { case calendar = "Calendar", announcement = "Announcement", document = "Document", outlook = "Outlook" }
    let title: String, date: Date, source: Source
    var detail: String? = nil // the sentence it came from / event description
    var kind: ItemKind? = nil // Jev's label, once classified
    var origin: String? = nil // the whole text the date was found in (announcement, message, course-page note): summarizer input
    var summary: Summary? = nil // AI title, once made and checked
    var announcement: String? = nil // `Announcement.key` of the post the date was found in
    var via: Origin? = nil // where it was found (nil in caches from before B2: read `resolvedVia`)
    var posted: Date? = nil // when the post, mail or file it came from was written
    var moved: Bool? = nil // the text says the date moved ("postponed to 1 Nov"): set by B4
    var ref: String? = nil // stable source id: Moodle calendar event id, ICS UID, file url or material title

    var resolvedVia: Origin { via ?? Origin.inferred(source: source, detail: detail, text: origin) }
}

/// Where a dated item came from, finer than `CourseEvent.Source`. Ranking, identity keys, filters and `isPDFDate`
/// read `resolvedVia`, never `via` itself, so a nil never reaches them.
enum Origin: String, Codable, Sendable, CaseIterable {
    case moodleActivity, moodleCalendar, outlookCalendar, news, message, mail, coursePage, syllabus, pdf

    /// High wins (1 = highest): Moodle is where work is submitted; PDFs are the least specific.
    var rank: Int {
        switch self {
        case .moodleActivity: 1
        case .moodleCalendar: 2
        case .outlookCalendar: 3
        case .news, .message, .mail: 4 // one tier: the newest post wins inside it
        case .coursePage: 5
        case .syllabus: 6
        case .pdf: 7
        }
    }

    /// The source in a sentence: "Also mentioned in: announcement (Thu 29 Oct), PDF".
    var label: String {
        switch self {
        case .moodleActivity: "Moodle"
        case .moodleCalendar: "Moodle calendar"
        case .outlookCalendar: "Outlook calendar"
        case .news: "announcement"
        case .message: "message"
        case .mail: "email"
        case .coursePage: "course page"
        case .syllabus: "syllabus"
        case .pdf: "PDF"
        }
    }

    /// For items saved before B2 (no `via`): nil source = a Moodle activity.
    static func inferred(source: CourseEvent.Source?, detail: String?, text: String?) -> Origin {
        switch source {
        case nil: .moodleActivity
        case .calendar: .moodleCalendar
        case .outlook: .outlookCalendar
        case .announcement: (text ?? "").hasPrefix("✉︎") ? .mail : .news
        case .document: (detail ?? "").hasPrefix("On the course page") ? .coursePage : .pdf
        }
    }
}

/// Stable identity of each event (deadline-priority.md §3.1), parallel to `events`. It never contains the date, so it
/// survives a date change; `n` counts same-keyword dates in one source by date order, over all of a subject's events
/// (never just the board window) that have content, so a bare "Dec 8 — -" line can't shift it (those get "/-").
func memberKeys(_ events: [CourseEvent], subject: String) -> [String] {
    let skip: Set = ["deadline", "submit", "submitted"]
    var count: [String: Int] = [:], out = Array(repeating: "", count: events.count)
    for i in events.indices.sorted(by: { (events[$0].date, $0) < (events[$1].date, $1) }) {
        let e = events[i], via = e.resolvedVia
        if via == .moodleCalendar, let ref = e.ref { out[i] = "c:\(ref)"; continue }
        if via == .outlookCalendar, let ref = e.ref { out[i] = "o:\(ref)"; continue }
        let words = keywords(mainPoint(e.title)).subtracting(skip).sorted().joined(separator: ",")
        let base = "t:\(subject)/\(via.rawValue)/\(e.ref ?? e.announcement ?? "-")/\(words)"
        guard hasContent(e.title) else { out[i] = "\(base)/-"; continue } // never on the board
        out[i] = "\(base)/\(count[base, default: 0])"
        count[base, default: 0] += 1
    }
    return out
}

struct Material: Hashable, Sendable {
    enum Kind: String, Sendable { case slides = "Slides", recording = "Recording", notes = "Notes", reading = "Reading" }
    let title: String, kind: Kind, date: Date
    var files: [MaterialFile]? = nil // downloadable files (Moodle resource/folder); nil for sample data and old caches
    var link: String? = nil // external link (Moodle "url" activity)
    var text: String? = nil // teacher-written text: a label, a section summary or an activity's description
}

extension Material {
    /// Title + file names, with "_" as a separator so "Lab#4_Answers" matches \banswers\b.
    private var matchText: String {
        ([title] + (files ?? []).map(\.name)).joined(separator: " ").replacingOccurrences(of: "_", with: " ")
    }

    /// Something to work through (exercises, worksheets, labs, quizzes, practice, sample exams — and their solutions)
    /// rather than something that teaches (slides, notes, readings). Decided from the title and file names.
    var isPractice: Bool {
        let text = matchText
        return text.range(of: #"\b(exercises?|worksheets?|problem\s*sets?|ps\s*\d+|homework|hw\s*\d*|assignments?|labs?|lab\s*#?\d+|quiz(zes)?|practice|tutorials?|solutions?|answers?|answer\s*keys?|answerkey|sample\s*exams?|past\s*(exam|paper)s?|mock|drills?|tasks?|questions?)\b"#,
                          options: [.regularExpression, .caseInsensitive]) != nil
    }
}

extension Material {
    /// Label for a practice file: what kind of work it is.
    var practiceLabel: String {
        let t = matchText
        func has(_ p: String) -> Bool { t.range(of: p, options: [.regularExpression, .caseInsensitive]) != nil }
        if has(#"\b(solutions?|answers?|answer\s*keys?|answerkey)\b"#) { return "SOLUTION" }
        if has(#"\b(sample\s*exams?|past\s*(exam|paper)s?|mock)\b"#) { return "SAMPLE EXAM" }
        if has(#"\bquiz"#) { return "QUIZ" }
        if has(#"\blabs?\b|\blab\s*#?\d"#) { return "LAB" }
        if has(#"\bassignments?\b"#) { return "ASSIGNMENT" }
        return "EXERCISE"
    }
}

struct MaterialFile: Hashable, Sendable, Codable {
    let name: String, url: String, size: Int, modified: Int // url = Moodle webservice/pluginfile.php URL (needs the token)
}

struct Announcement: Hashable, Sendable {
    enum Source: String, Sendable { case moodle = "Moodle", message = "Message", notification = "Notification", outlook = "Outlook", teams = "Teams" }
    let title: String, source: Source, from: String, date: Date
    var body: String? = nil // full message text
    var kind: ItemKind? = nil // Jev's label, once classified
    var modified: Date? = nil // last edit (Moodle `timemodified`); nil when unknown
    /// When it was last written: an edited post counts from its edit. `date` (shown in the list) stays the creation date.
    var posted: Date { max(date, modified ?? date) }
    /// Identifies the post, so a deadline found in it can open it.
    var key: String { "\(title)|\(date.timeIntervalSince1970)" }
}

struct Subject: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let code: String
    let hue: Hue
    let assessments: [Assessment] // ordered by date
    let assignments: [AssignmentItem]
    let materials: [Material]
    var announcements: [Announcement]
    var events: [CourseEvent]? = nil // calendar events + dates mentioned in announcements/documents

    /// Weighted average of completed assessments only, rounded to 1 decimal; nil if nothing graded yet.
    var runningGrade: Double? {
        let done = assessments.filter { $0.score != nil }
        guard !done.isEmpty else { return nil }
        // MBZUAI's gradebook often weights items 0: unless every result has a weight, every result counts equally.
        let weighted = done.allSatisfy(\.hasWeight) && done.contains { $0.share > 0 }
        let w = weighted ? done.reduce(0) { $0 + $1.share } : Double(done.count)
        let sum = done.reduce(0.0) { $0 + (weighted ? $1.share : 1) * $1.exactScore! }
        return (sum / w * 10).rounded() / 10
    }

    /// % of the course's weight already graded, nil when Moodle gives no weights; clamped because weights can be category-relative.
    var doneShare: Int? {
        let total = assessments.reduce(0) { $0 + $1.share }
        // Only when the weights describe the course: all set and adding up to ~100% (Communication's add up to 154%).
        guard assessments.allSatisfy(\.hasWeight), (95...105).contains(total) else { return nil }
        return min(100, max(0, Int(((total - stillToComeShare) / total * 100).rounded())))
    }

    /// % of the course grade not yet assessed.
    var stillToCome: Int { Int(stillToComeShare.rounded()) }
    var stillToComeShare: Double { assessments.filter { $0.score == nil }.reduce(0) { $0 + $1.share } }
}

// Codable for the Moodle cache (moodle-cache.json).
extension Hue: Codable {}
extension AssessmentType: Codable {}
extension Assessment: Codable {}
extension Assessment.Raw: Codable {}
extension AssignmentItem: Codable {}
extension AssignmentItem.Status: Codable {}
extension Material: Codable {}
extension Material.Kind: Codable {}
extension Announcement: Codable {}
extension Announcement.Source: Codable {}
extension Subject: Codable {}

// MARK: - What-if

extension Subject {
    /// Course grade if each upcoming assessment scores `assumed[id]` (upcoming ones without a value are left out). 1 decimal.
    func projected(_ assumed: [String: Double]) -> Double? {
        var w = 0.0, sum = 0.0
        for a in assessments {
            guard let s = a.exactScore ?? assumed[a.id] else { continue }
            w += a.share
            sum += a.share * s
        }
        return w > 0 ? (sum / w * 10).rounded() / 10 : nil
    }

    /// Average % needed across all upcoming assessments to finish the course at `target`; nil if nothing is upcoming.
    func needed(for target: Double) -> Double? {
        guard stillToComeShare > 0 else { return nil }
        let earned = assessments.reduce(0.0) { $0 + $1.share * ($1.exactScore ?? 0) }
        return ((target * 100 - earned) / stillToComeShare * 10).rounded() / 10
    }
}

/// Shade band by weight: 0 = <5%, 1 = 5–15%, 2 = 15–30%, 3 = >30%. Higher = darker.
func band(_ weight: Int) -> Int { weight < 5 ? 0 : weight <= 15 ? 1 : weight <= 30 ? 2 : 3 }
let bandLabels = ["<5%", "5–15%", "15–30%", ">30%"]

struct Upcoming: Identifiable, Sendable {
    let subject: Subject, assessment: Assessment
    var id: String { subject.id + "/" + assessment.id }
}

/// Next upcoming deadlines/exams across all subjects, soonest first.
func thisWeek(_ subjects: [Subject] = Subject.all, count: Int = 3, now: Date = .now) -> [Upcoming] {
    subjects
        .flatMap { s in s.assessments.filter { $0.score == nil && $0.date >= now }.map { Upcoming(subject: s, assessment: $0) } }
        .sorted { $0.assessment.date < $1.assessment.date }
        .prefix(count)
        .map { $0 }
}

// MARK: - Deadlines (week board)

/// Anything due: an upcoming graded assessment (with its weight) or an open assignment that isn't one.
struct Deadline: Identifiable, Sendable {
    let id: String
    let subject: Subject
    let title: String
    var date: Date // a cluster's date can come from a "moved to" member (`cluster`)
    let weight: Int? // % of the course grade; nil = ungraded or unknown
    var source: CourseEvent.Source? = nil // nil = a Moodle activity (assignment/quiz); else calendar event or mentioned date
    var detail: String? = nil // instructions or the sentence the date came from
    var kind: ItemKind? = nil // deadline/exam for Moodle activities; Jev's label for everything else
    var summary: Summary? = nil // DeepSeek's title, if Jev accepted it
    var announcement: String? = nil // the post it came from: clicking opens it in the course's Announcements tab
    var headlineCache: String? = nil // set by `boardItems`, so mainPoint's regexes run once per data change, not per redraw
    var memberKey = "" // stable identity (`memberKeys`), set by `deadlines()`; unlike `id` it has no date in it
    var via: Origin? = nil
    var posted: Date? = nil

    var type: AssessmentType? = nil // for weight and effort defaults; nil = "other" (a text item naming no type)
    var givenWeight: Weighting? = nil // set by `deadlines()`; read `weighting`
    var cutoff: Date? = nil
    var extended: Bool? = nil
    var moved: Bool? = nil // its text says the date moved (`CourseEvent.moved`)
    var conflict: String? = nil // "Post on Thu 29 Oct says moved to Wed 4 Nov": a Moodle date a newer post disagrees with (D3)
    var alsoIn: [Deadline] = [] // the cluster's other members (`cluster`)
    var ref: String? = nil // `CourseEvent.ref`: the file or note a dated text item came from

    var resolvedVia: Origin { via ?? Origin.inferred(source: source, detail: detail, text: nil) }
    /// A move cue in the text, or Jev's "class change" label (it catches wording the regex misses).
    var isMoved: Bool { moved == true || kind == .classChange }
    /// "announcement (Thu 29 Oct), PDF": where else this item was found, for the preview.
    var alsoMentioned: String? {
        var seen = Set<String>()
        let parts = alsoIn.map { m in m.resolvedVia.label + (m.posted.map { " (\($0.short()))" } ?? "") }.filter { seen.insert($0).inserted }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

// MARK: - Ranking (deadline-priority.md §1, §6; the tables are D1's approved starting values)

/// An item's share of the course grade and where it came from. First match wins: Moodle, syllabus, title, typical.
struct Weighting: Equatable, Sendable {
    enum From: Sendable { case moodle, syllabus, title, typical }
    let value: Double, from: From
    var spare = false // a syllabus item that may end up dropped ("7.5% if it counts")
    var estimate: Bool { from == .typical }
    private var number: String { value == value.rounded() ? "\(Int(value))%" : String(format: "%.1f%%", value) }
    /// The reason line's wording: "12%", "7.5% if it counts", "~5% est."
    var text: String { estimate ? "~\(number) est." : spare ? "\(number) if it counts" : number }
    /// Card tags (§1.4.1): "12%", "≤ 7.5%" for a spare, "~5%" for an estimate. Never a misleading "0%".
    var tag: String { estimate ? "~\(number)" : spare ? "≤ \(number)" : number }
    /// What counts toward crunch's 30% rule: known weights only; a spare or a typical guess adds 0.
    var known: Double { estimate || spare ? 0 : value }
}

enum Ranking {
    static let hoursPerDay = 3.0 // H: focused hours a day on one item
    static let horizonDays = 28.0 // Do next ranks what's due this far ahead (T4), not just the board's week
    /// Overdue work with no cutoff stays in Do next this long past due (§1.4). P6's `needsStatus` stops checking the
    /// submission status at the same point, after which the app can't know the work is still open.
    static let overdueDays = 14.0

    static func typicalWeight(_ t: AssessmentType?) -> Double {
        switch t {
        case .final: 30
        case .midterm: 25
        case .miniExam, .project: 10
        case .quiz, .assignment: 5
        case .lab, nil: 2
        }
    }

    static func effortHours(_ t: AssessmentType?, weight w: Double) -> Double {
        switch t {
        case .final: 15
        case .midterm: 10
        case .miniExam: 5
        case .quiz: 3
        case .project: max(6, w)
        case .assignment: min(max(0.5 * w, 2), 12)
        case .lab, nil: 2
        }
    }

    static func weighting(moodle: Int?, syllabus: Double?, spare: Double?, title: String, type: AssessmentType?) -> Weighting {
        if let m = moodle, m > 0 { return Weighting(value: Double(m), from: .moodle) }
        if let s = syllabus, s > 0 { return Weighting(value: s, from: .syllabus) }
        if let s = spare, s > 0 { return Weighting(value: s, from: .syllabus, spare: true) } // can't know yet which one is dropped
        if let t = percentInTitle(title) { return Weighting(value: Double(t), from: .title) }
        return Weighting(value: typicalWeight(type), from: .typical)
    }

    /// A text item's type, only when its title names one; one Jev calls an exam with no type word counts as a quiz.
    static func textType(_ title: String, kind: ItemKind?) -> AssessmentType? {
        let k = Moodle.kind(nil, title)
        return k != .assignment ? k : kind == .exam ? .quiz : nil
    }
}

/// Per-item weight of the syllabus part `name` belongs to (Calculus quizzes: 30 / best 4 = 7.5).
func syllabusPerItem(_ code: String, _ name: String) -> Double? {
    syllabusRules[code]?.first { name.range(of: $0.pattern, options: .regularExpression) != nil }.map { $0.total / Double($0.best) }
}

extension Deadline {
    /// `deadlines()` always sets `givenWeight`; a Deadline made by hand with only `weight` treats it as known.
    var weighting: Weighting { givenWeight ?? Ranking.weighting(moodle: weight, syllabus: nil, spare: nil, title: title, type: type) }
    /// Graded work and exams carry a weight tag; talks, class changes and other events don't.
    var showsWeight: Bool { toSubmit || kind == .exam }
    var effortHours: Double { Ranking.effortHours(type, weight: weighting.value) }
    /// Days you can still wait before starting: time left minus the work, at H focused hours a day.
    func slack(now: Date) -> Double { date.timeIntervalSince(now) / 86_400 - effortHours / Ranking.hoursPerDay }
    /// Higher = do sooner: weight ÷ slack. The 0.25 floor puts every "start now" item in one band, ordered by weight.
    func priority(now: Date = .now) -> Double { weighting.value / max(slack(now: now), 0.25) }
    var startBy: Date { date.addingTimeInterval(-effortHours / Ranking.hoursPerDay * 86_400) }
    /// Past the cutoff: Moodle no longer takes it.
    func isClosed(now: Date) -> Bool { cutoff.map { now > $0 } ?? false }

    /// "12% · due in 2 days · ~6 h of work → start today" (Do next's second line; the preview shows it in full).
    func reason(now: Date, calendar: Calendar = .current) -> String {
        let exam = kind == .exam
        let day = { (d: Date) in
            d.formatted(Date.VerbatimFormatStyle(format: "\(weekday: .abbreviated) \(day: .defaultDigits) \(month: .abbreviated)",
                                                 locale: Locale(identifier: "en_US_POSIX"), timeZone: calendar.timeZone, calendar: calendar))
        }
        let closed = isClosed(now: now), undated = date == .distantFuture
        let when: String
        if closed { when = "closed" }
        else if undated { when = "no due date" }
        else if date < now { when = cutoff.map { "late until \(day($0))" } ?? "overdue" }
        else {
            let n = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
            let noun = exam ? "exam" : "due"
            when = (n <= 0 ? "\(noun) today" : n == 1 ? "\(noun) tomorrow" : "\(noun) in \(n) days") + (extended == true ? " (extended)" : "")
        }
        let h = effortHours
        let line = "\(weighting.text) · \(when) · ~\(h == h.rounded() ? "\(Int(h))" : String(format: "%.1f", h)) h \(exam ? "prep" : "of work")"
        if closed || undated { return line }
        let s = slack(now: now)
        if s < 0 {
            let n = max(1, Int((-s).rounded()))
            return line + ", behind by ~\(n) day\(n == 1 ? "" : "s")"
        }
        return line + (startBy < now || calendar.isDate(startBy, inSameDayAs: now) ? " → start today" : " → start by \(day(startBy))")
    }

    /// Where the weight came from, for the preview.
    var weightNote: String {
        switch weighting.from {
        case .moodle: return "Weight from Moodle"
        case .syllabus: return weighting.spare ? "From the syllabus; counts only if it isn't the one dropped" : "Weight from the syllabus"
        case .title: return "Weight from the title"
        case .typical:
            let what = switch type {
            case .assignment: "an assignment"
            case .miniExam: "a mini-exam"
            case let t?: "a \(t.rawValue.lowercased())"
            case nil: "this kind of item"
            }
            return "No weight on Moodle; typical for \(what)"
        }
    }
}

/// Do next (§1.4, D2): the top items by priority among work to hand in and exams due within 28 days. An open Moodle
/// assignment past its due date stays, as overdue, until its cutoff closes it, or with no cutoff for 14 days past due
/// (then it stays on the board only). Ties go to the earlier date.
func doNext(_ items: [Deadline], now: Date, limit: Int = 3) -> [Deadline] {
    let end = now.addingTimeInterval(Ranking.horizonDays * 86_400)
    return Array(items.filter { d in
        guard d.toSubmit || d.kind == .exam, d.date < end, !d.isClosed(now: now) else { return false }
        return d.date >= now || (d.toSubmit && d.resolvedVia == .moodleActivity
            && (d.cutoff != nil || now.timeIntervalSince(d.date) <= Ranking.overdueDays * 86_400))
    }
    .sorted { a, b in
        let (pa, pb) = (a.priority(now: now), b.priority(now: now))
        return pa != pb ? pa > pb : a.date < b.date
    }
    .prefix(limit))
}

/// Every deadline in [start, start + days), soonest first. An open assignment whose title starts with an upcoming
/// assessment's name ("Assignment 2: Eigenvalues" vs "Assignment 2") is the same deadline and is not listed twice.
func deadlines(_ subjects: [Subject], from start: Date = .now, days: Int = 7) -> [Deadline] {
    deadlines(subjects, in: start..<start.addingTimeInterval(Double(days) * 86_400))
}

/// The board's items: deadlines at every date, headlines worked out once. `Store.board` holds them; views slice by date.
typealias BoardItem = Deadline

func boardItems(_ subjects: [Subject]) -> [BoardItem] {
    var ids = Set<String>() // SwiftUI's ForEach needs unique ids: keep the first (`cluster` merges true duplicates already)
    return deadlines(subjects, in: Date.distantPast..<Date.distantFuture).filter { ids.insert($0.id).inserted }
        .map { var d = $0; d.headlineCache = d.headline; return d }
}

/// A date read from a downloaded PDF (MaterialStore.documentEvents), as opposed to course-page text, which every Moodle
/// sync brings again.
func isPDFDate(_ e: CourseEvent) -> Bool { e.resolvedVia == .pdf }

/// `subjects` with their PDF dates replaced by `found` (by subject id). Course-page dates stay, so this is idempotent.
func withPDFDates(_ subjects: [Subject], _ found: [String: [CourseEvent]]) -> [Subject] {
    subjects.map { s in
        var s = s
        s.events = ((s.events ?? []).filter { !isPDFDate($0) } + (found[s.id] ?? [])).sorted { $0.date < $1.date }
        return s
    }
}

extension [Deadline] {
    /// The items dated in [start, end), still soonest first.
    func between(_ start: Date, _ end: Date) -> [Deadline] { filter { $0.date >= start && $0.date < end } }
}

/// Builds every item at every date, merges each real-world item's mentions into one (`cluster`), then keeps the window:
/// a "moved to" post can carry an item into or out of it.
private func deadlines(_ subjects: [Subject], in window: Range<Date>) -> [Deadline] {
    cluster(subjects.flatMap { s in
        let handedIn = s.assignments.filter { $0.status != .open }.map(\.title)
        let graded = s.assessments.filter { a in a.score == nil && !handedIn.contains { sameItem($0, a.name) }
                && !(a.id.hasPrefix("syllabus/") && a.date < .now) } // a syllabus quiz that already happened is awaiting its mark, not overdue
            .map { a -> Deadline in
                let task = s.assignments.first { sameItem($0.title, a.name) } // its Moodle assignment: cutoff and extension
                return Deadline(id: "\(s.id)/\(a.id)", subject: s, title: a.name, date: a.date,
                                weight: a.exactWeight == 0 ? nil : Int(a.share.rounded()), // 0 = the quiz currently dropped from "best 4"
                                kind: [.quiz, .midterm, .final, .miniExam].contains(a.type) ? .exam : .deadline,
                                memberKey: "g:\(s.id)/\(a.id)", via: a.id.hasPrefix("syllabus/") ? .syllabus : .moodleActivity, type: a.type,
                                givenWeight: Ranking.weighting(moodle: a.weight, syllabus: a.exactWeight,
                                                               spare: a.exactWeight == 0 ? syllabusPerItem(s.code, a.name) : nil, title: a.name, type: a.type),
                                cutoff: task?.cutoff, extended: task?.extended)
            }
        let other = s.assignments
            .filter { a in a.status == .open && !s.assessments.contains { sameItem(a.title, $0.name) } }
            .map { Deadline(id: "\(s.id)/task/\($0.title)", subject: s, title: $0.title, date: $0.due, weight: percentInTitle($0.title),
                            detail: $0.details, kind: .deadline,
                            memberKey: "a:" + ($0.moodleID.map(String.init) ?? "\(s.id)/\($0.title)"), via: .moodleActivity,
                            type: Moodle.kind(nil, $0.title),
                            givenWeight: Ranking.weighting(moodle: nil, syllabus: nil, spare: nil, title: $0.title, type: Moodle.kind(nil, $0.title)),
                            cutoff: $0.cutoff, extended: $0.extended) }
        let all = s.events ?? []
        let events = zip(all, memberKeys(all, subject: s.id))
            // Jev's "grades out" / "info" are news, not deadlines (unclassified items stay, so nothing is lost without a key).
            .filter { e, _ in e.kind?.isDated != false && hasContent(e.title) } // not a bare "Dec 8 — -"
            .map { e, key in
                let type = Ranking.textType(e.title, kind: e.kind)
                return Deadline(id: "\(s.id)/event/\(e.source.rawValue)/\(e.date.timeIntervalSince1970)/\(e.title)", subject: s, title: e.title,
                                date: e.date, weight: percentInTitle(e.title), source: e.source, detail: e.detail, kind: e.kind,
                                summary: e.summary?.accepted == true ? e.summary : nil, announcement: e.announcement,
                                memberKey: key, via: e.resolvedVia, posted: e.posted, type: type,
                                givenWeight: Ranking.weighting(moodle: nil, syllabus: nil, spare: nil, title: e.title, type: type), moved: e.moved,
                                ref: e.ref)
            }
        return graded + other + events
    })
    .filter { window.contains($0.date) }
    .sorted { $0.date < $1.date }
}

// MARK: - Clusters (deadline-priority.md §2.2–2.4)

/// Words that say nothing about which item it is: move cues, weekdays and function words ("has been moved to Tuesday").
private let clusterSkip: Set = ["deadline", "submit", "submitted", "moved", "postponed", "pushed", "back", "extended", "rescheduled",
    "delayed", "shifted", "changed", "until", "till", "today", "tomorrow", "tonight", "monday", "tuesday", "wednesday", "thursday",
    "friday", "saturday", "sunday", "week", "next", "has", "have", "had", "been", "will", "would", "with", "from", "this", "that",
    "these", "those", "are", "was", "were", "our", "your", "you", "all", "not", "now", "there", "their", "its", "into", "than",
    "then", "also", "only", "just", "please", "note", "reminder"]

/// The words two mentions of one item share: `keywords` of its main point, minus `clusterSkip`.
func clusterWords(_ title: String) -> Set<String> { keywords(mainPoint(title)).subtracting(clusterSkip) }

/// The item numbers in a title ("Quiz 3", "Assignment 10"), without dates, percentages ("(8%)") and clock times.
func titleNumbers(_ title: String) -> Set<String> {
    let t = mainPoint(title).replacingOccurrences(of: #"\d+(?:\.\d+)?\s?%|\b\d{1,2}[:.]\d{2}\b"#, with: " ", options: .regularExpression)
    return Set(t.matches(of: /\b\d+\b/).map { String(Int($0.output) ?? 0) }) // "03" = "3"
}

/// One card per real-world item: merges the mentions of an item across sources (§2.2), then shows the best member (§2.4).
/// Union-find over all pairs; n is a few hundred, so O(n²) is fine. Output follows each cluster's first member.
func cluster(_ items: [Deadline]) -> [Deadline] {
    let words = items.map { clusterWords($0.title) }, numbers = items.map { titleNumbers($0.title) }
    let titles = items.map { $0.title.lowercased() }
    var parent = Array(items.indices)
    var nums = numbers, activity = items.map { $0.resolvedVia == .moodleActivity } // per cluster root
    func root(_ i: Int) -> Int {
        var i = i
        while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
        return i
    }
    // A moved item joins one posted before it, up to 30 days away (§2.2 rule 4). No `posted` (Moodle) counts as older.
    // Only a stated move ("postponed to") reaches that far: Jev labels every "no classes" holiday a class change.
    func movedAfter(_ m: Int, _ o: Int) -> Bool {
        items[m].moved == true && (items[o].posted ?? .distantPast) < (items[m].posted ?? .distantFuture)
    }
    func same(_ i: Int, _ j: Int) -> Bool {
        let (a, b) = (items[i], items[j])
        let shared = words[i].intersection(words[j]).count
        let general = a.subject.code == "GENERAL" || b.subject.code == "GENERAL"
        guard a.subject.id == b.subject.id || (general && shared >= 2) else { return false }
        // Rows of one schedule ("Dec 8 — Presentation", "Dec 10 — Presentation") are separate dates, not repeated mentions.
        if let r = a.ref, r == b.ref, a.date != b.date { return false }
        let gap = abs(a.date.timeIntervalSince(b.date))
        guard gap <= 3 * 86_400 || (gap <= 30 * 86_400 && (movedAfter(i, j) || movedAfter(j, i))) else { return false }
        if titles[i] == titles[j] || sameItem(titles[i], titles[j]) || sameItem(titles[j], titles[i]) { return true } // fast path
        return shared >= max(1, min(2, words[i].count, words[j].count))
            && (numbers[i].isEmpty || numbers[j].isEmpty || numbers[i] == numbers[j]) // "Quiz 3" ≠ "Quiz 4"
    }
    for i in items.indices {
        for j in items.indices where j > i && same(i, j) {
            let (a, b) = (root(i), root(j))
            guard a != b,
                  !(activity[a] && activity[b]), // two Moodle activities are two submissions, never one item
                  nums[a].isEmpty || nums[b].isEmpty || nums[a] == nums[b] // a numberless post can't chain Quiz 3 to Quiz 4
            else { continue }
            parent[b] = a
            nums[a].formUnion(nums[b])
            activity[a] = activity[a] || activity[b]
        }
    }
    var order: [Int] = [], members: [Int: [Int]] = [:]
    for i in items.indices {
        let r = root(i)
        if members[r] == nil { order.append(r) }
        members[r, default: []].append(i)
    }
    return order.map { merge(members[$0]!.map { items[$0] }) }
}

/// §2.4: the winner gives title, kind and click target (highest source rank, then newest post); the date is Moodle's for a
/// Moodle activity (a disagreeing newer "moved" post becomes `conflict`, D3), else the newest moved member's, else the
/// winner's; the weight is the best one any member has (Moodle, syllabus, spare, title, typical).
private func merge(_ ms: [Deadline]) -> Deadline {
    guard ms.count > 1 else { return ms[0] }
    let w = ms.indices.min { a, b in
        (ms[a].resolvedVia.rank, -(ms[a].posted ?? .distantPast).timeIntervalSinceReferenceDate)
            < (ms[b].resolvedVia.rank, -(ms[b].posted ?? .distantPast).timeIntervalSinceReferenceDate)
    }!
    var d = ms[w]
    d.alsoIn = ms.indices.filter { $0 != w }.map { var m = ms[$0]; m.alsoIn = []; return m }
    let moved = ms.filter(\.isMoved).max { ($0.posted ?? .distantPast) < ($1.posted ?? .distantPast) }
    if d.resolvedVia == .moodleActivity {
        if let m = moved, abs(m.date.timeIntervalSince(d.date)) > 12 * 3600 {
            d.conflict = (m.posted.map { "Post on \($0.short())" } ?? "A post") + " says moved to \(m.date.short())"
        }
    } else if let m = moved {
        d.date = m.date
    }
    func order(_ x: Weighting) -> Int {
        switch x.from { case .moodle: 0; case .syllabus: x.spare ? 2 : 1; case .title: 3; case .typical: 4 }
    }
    d.givenWeight = ([d] + d.alsoIn).map(\.weighting).min { order($0) < order($1) } // ties: the winner's
    return d
}

// MARK: - Sample data (dates relative to launch so "this week" stays current)

private func days(_ n: Int) -> Date { Date.now.addingTimeInterval(Double(n) * 86_400) }

private func a(_ id: String, _ name: String, _ type: AssessmentType, _ d: Int, _ weight: Int, _ topics: [String], _ raw: (Int, Int)? = nil) -> Assessment {
    Assessment(id: id, name: name, type: type, date: days(d), weight: weight, raw: raw.map { .init(got: $0.0, max: $0.1) }, topics: topics)
}

extension Subject {
    static func find(_ id: String) -> Subject? { all.first { $0.id == id } }

    static let all: [Subject] = [
        Subject(
            id: "linear-algebra", name: "Linear Algebra", code: "MATH210", hue: .green,
            assessments: [
                a("q1", "Quiz 1", .quiz, -49, 4, ["Vectors", "Linear combinations"], (17, 20)),
                a("q2", "Quiz 2", .quiz, -35, 4, ["Matrix operations", "Inverses"], (18, 25)),
                a("a1", "Assignment 1", .assignment, -28, 10, ["Systems of equations", "Gaussian elimination"], (45, 50)),
                a("mid", "Midterm", .midterm, -10, 30, ["Vector spaces", "Determinants", "Rank"], (78, 100)),
                a("a2", "Assignment 2", .assignment, 2, 12, ["Eigenvalues", "Diagonalisation"]),
                a("final", "Final", .final, 48, 40, ["All topics", "Emphasis on eigen-decomposition and orthogonality"]),
            ],
            assignments: [
                .init(title: "Assignment 2: Eigenvalues", due: days(2), status: .open),
                .init(title: "Assignment 1: Gaussian elimination", due: days(-28), status: .submitted),
                .init(title: "Problem sheet 7", due: days(1), status: .open),
                .init(title: "Reading: Strang §6.1", due: days(3), status: .open),
            ],
            materials: [
                .init(title: "Lecture 9: Eigenvalues.pdf", kind: .slides, date: days(-2)),
                .init(title: "Lecture 9 recording", kind: .recording, date: days(-2)),
                .init(title: "Determinants worked examples", kind: .notes, date: days(-12)),
            ],
            announcements: [
                .init(title: "Thursday lecture moved to room B204", source: .moodle, from: "Dr. Nguyen", date: days(-1)),
                .init(title: "Midterm results and solutions posted", source: .outlook, from: "Dr. Nguyen", date: days(-4)),
                .init(title: "Extra office hour before Assignment 2", source: .teams, from: "TA Linh", date: days(-5)),
            ]
        ),
        Subject(
            id: "intro-to-ai", name: "Intro to AI", code: "CS240", hue: .orange,
            assessments: [
                a("q1", "Quiz 1", .quiz, -45, 5, ["Intelligent agents", "Search problems"], (23, 25)),
                a("me1", "Mini-exam 1", .miniExam, -30, 15, ["Uninformed search", "A* and heuristics"], (81, 100)),
                a("proj", "Project", .project, -12, 20, ["Constraint satisfaction", "Game playing"], (44, 50)),
                a("mid", "Midterm", .midterm, 4, 25, ["Probability", "Bayesian networks"]),
                a("final", "Final", .final, 50, 35, ["All topics", "Emphasis on learning and planning"]),
            ],
            assignments: [
                .init(title: "Project report: Connect-4 agent", due: days(-12), status: .submitted),
                .init(title: "Problem set 4: Bayes nets", due: days(9), status: .open),
                .init(title: "Lab 3: Bayes net sampling", due: days(3), status: .open),
                .init(title: "Paper summary", due: days(5), status: .open),
            ],
            materials: [
                .init(title: "Week 8: Bayesian networks.pdf", kind: .slides, date: days(-3)),
                .init(title: "Russell & Norvig ch. 13", kind: .reading, date: days(-3)),
            ],
            announcements: [
                .init(title: "Midterm covers weeks 5–8 only", source: .moodle, from: "Prof. Tran", date: days(-2)),
                .init(title: "Project grades released", source: .teams, from: "Prof. Tran", date: days(-6)),
            ]
        ),
        Subject(
            id: "advanced-python", name: "Advanced Python", code: "CS310", hue: .yellow,
            assessments: [
                a("lab1", "Lab 1", .lab, -40, 3, ["Virtual environments", "Packaging"], (10, 10)),
                a("q1", "Quiz 1", .quiz, -33, 5, ["Iterators", "Generators"], (14, 20)),
                a("me", "Mini-exam", .miniExam, -18, 15, ["Decorators", "Context managers"], (42, 50)),
                a("a2", "Assignment 2", .assignment, 6, 12, ["asyncio", "Async I/O"]),
                a("mid", "Midterm", .midterm, 20, 25, ["Typing", "Concurrency", "Metaclasses"]),
                a("final", "Final", .final, 52, 40, ["All topics"]),
            ],
            assignments: [
                .init(title: "Assignment 2: async web scraper", due: days(6), status: .open),
                .init(title: "Assignment 1: CLI with decorators", due: days(-21), status: .submitted),
                .init(title: "Lab 2: profiling", due: days(11), status: .open),
                .init(title: "Lab 3: asyncio drills", due: days(2), status: .open),
                .init(title: "Code review: PR #12", due: days(4), status: .open),
            ],
            materials: [
                .init(title: "Lecture 7: asyncio.pdf", kind: .slides, date: days(-1)),
                .init(title: "Lecture 7 recording", kind: .recording, date: days(-1)),
                .init(title: "Fluent Python ch. 21", kind: .reading, date: days(-6)),
            ],
            announcements: [
                .init(title: "Assignment 2 starter code updated", source: .moodle, from: "Dr. Le", date: days(-1)),
                .init(title: "Lab room change this week", source: .outlook, from: "CS Department", date: days(-3)),
            ]
        ),
    ]
}

/// The words that identify a deadline: "TED-Talk Script (8%)" → ted, talk, script.
func keywords(_ title: String) -> Set<String> {
    let skip: Set = ["the", "and", "for", "due", "final", "submission", "assignment"]
    return Set(words(title).filter { $0.count >= 3 && !skip.contains($0) })
}
func words(_ text: String) -> [String] { text.lowercased().split { !$0.isLetter }.map(String.init) }

/// Announcements that talk about a deadline: they contain its title's words (up to three of them). Moodle assignments are
/// often posted with an empty description; a loose match would pull in classmates' posts ("my favourite TED talk").
func related(_ title: String, in news: [Announcement]) -> [Announcement] {
    let k = keywords(title)
    guard !k.isEmpty else { return [] }
    return news.filter { k.intersection(words("\($0.title) \($0.body ?? "")")).count >= min(3, k.count) }
}

/// "Quiz 3 closes" is the same item as "Quiz 3", but "Assignment 10" is not "Assignment 1".
func sameItem(_ title: String, _ name: String) -> Bool {
    guard title.hasPrefix(name) else { return false }
    let rest = title.dropFirst(name.count)
    return rest.first.map { !$0.isLetter && !$0.isNumber } ?? true
}

// MARK: - Syllabus grading rules

/// One graded part of a course, typed in from its syllabus. MBZUAI's Moodle weights these items 0 and doesn't list future
/// ones, so Moodle results are matched by name, missing items become upcoming placeholders, and only the best `best` count.
struct GradingPart: Sendable {
    let name: String, pattern: String, type: AssessmentType, total: Double, best: Int
    let dates: [Date] // one per item; "Quiz" with 5 dates = Quiz 1…Quiz 5
}

private func day(_ m: Int, _ d: Int) -> Date { // no time in the syllabus: 23:59 = "that day", never a made-up hour
    Calendar.current.date(from: DateComponents(year: 2026, month: m, day: d, hour: 23, minute: 59))!
}

/// AI1110 syllabus (v1.0, published 2026-08-20): quizzes 30% (best 4 of 5), midterm 30%, final 35%, project report 5%,
/// attendance 0%. Dates from AI1110_Calculus_Fall_2026_Tentative_Schedule.pdf.
let syllabusRules: [String: [GradingPart]] = [
    "AI1110": [
        GradingPart(name: "Quiz", pattern: #"(?i)^quiz\s*\d"#, type: .quiz, total: 30, best: 4,
                    dates: [day(9, 15), day(9, 29), day(10, 6), day(11, 10), day(11, 24)]),
        GradingPart(name: "Midterm Exam", pattern: #"(?i)mid-?term\s+exam"#, type: .midterm, total: 30, best: 1, dates: [day(10, 20)]),
        GradingPart(name: "Final Exam", pattern: #"(?i)final\s+exam"#, type: .final, total: 35, best: 1, dates: [day(12, 12)]),
        GradingPart(name: "Final Project Report", pattern: #"(?i)project"#, type: .project, total: 5, best: 1, dates: [day(12, 10)]),
    ],
]

/// Applies a course's syllabus rule: per-item weight = total / best; graded items beyond the best `best` get 0 (dropped);
/// upcoming items fill the slots still open, soonest first ("needed" then assumes the rest will be the dropped ones).
func withSyllabus(_ code: String, _ assessments: [Assessment]) -> [Assessment] {
    guard let parts = syllabusRules[code] else { return assessments }
    var out = assessments
    for p in parts {
        let matches = { (a: Assessment) in a.name.range(of: p.pattern, options: .regularExpression) != nil }
        let names = Set(out.filter(matches).map { $0.name.lowercased() })
        for (i, date) in p.dates.enumerated() {
            let name = p.dates.count > 1 ? "\(p.name) \(i + 1)" : p.name
            if !names.contains(name.lowercased()) && out.filter(matches).count < p.dates.count {
                out.append(Assessment(id: "syllabus/\(code)/\(name)", name: name, type: p.type, date: date, weight: 0, raw: nil, topics: []))
            }
        }
        let per = p.total / Double(p.best)
        let graded = out.indices.filter { matches(out[$0]) && out[$0].raw != nil }.sorted { out[$0].score! > out[$1].score! }
        let upcoming = out.indices.filter { matches(out[$0]) && out[$0].raw == nil }.sorted { out[$0].date < out[$1].date }
        for (rank, i) in graded.enumerated() { out[i].exactWeight = rank < p.best ? per : 0 }
        let open = max(0, p.best - graded.count)
        for (rank, i) in upcoming.enumerated() { out[i].exactWeight = rank < open ? per : 0 }
    }
    return out.sorted { $0.date < $1.date }
}

/// The board's split: real deadlines (work you hand in: Moodle assignments and items Jev labels "deadline") vs events
/// (exams/quizzes, class changes, sessions, and dated items not classified yet). Grades-out and info never reach the board.
enum DeadlineGroup: String, CaseIterable, Sendable { case submit = "To submit", events = "Events", all = "All" }
extension Deadline {
    var toSubmit: Bool { kind == .deadline }
    func isIn(_ g: DeadlineGroup) -> Bool { g == .all || (g == .submit) == toSubmit }
}

// MARK: - Headlines

/// The main point of a dated sentence, without date words, bullets and filler, because the date is shown beside it:
/// "• Final Research Submission (14%) DUE WEEK (Deadline 13th November)" → "Final Research Submission (14%)".
func mainPoint(_ text: String) -> String {
    let mon = "(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\\.?"
    let weekday = "(?:mon|tue|wed|thu|fri|sat|sun)[a-z]*"
    let edges = #"^[\s•·\-–—:,;]+|[\s•·\-–—:,;.]+$"#
    func drop(_ s: String, _ pattern: String, _ with: String = "") -> String { s.replacingOccurrences(of: pattern, with: with, options: .regularExpression) }
    var s = text
    s = drop(s, #"(?i)\([^)]*\b(?:deadline|done|due|tbc)\b[^)]*\)"#)              // "(Deadline 13th November)", "(Done in Lab…)"
    s = drop(s, #"(?i)\bdue\s+week\s*\d*"#)                                        // "DUE WEEK 6"
    s = drop(s, "(?i)\\b\\d{1,2}(?:st|nd|rd|th)?\\s+(?:of\\s+)?" + mon + "(?:,?\\s*\\d{4})?")  // "13th November"
    s = drop(s, "(?i)\\b" + mon + "\\s+\\d{1,2}(?:st|nd|rd|th)?(?:,?\\s*\\d{4})?")               // "Oct 29", "OCTOBER 28th"
    s = drop(s, #"\b\d{1,2}/\d{1,2}(?:/\d{2,4})?\b"#)                               // "23/10/2026"
    s = drop(s, edges)
    s = drop(s, "(?i)^" + weekday + "\\s*[-–:,]\\s*")                                 // "Thu - …", "Tuesday: …"
    s = drop(s, #"(?i)^(?:dear|hi|hello|hey)\b[^,]{0,40},\s*"#)                       // "Dear Linear Algebraists, …"
    s = drop(s, #"(?i)^(?:unfortunately|please note that|just a reminder(?: that)?|reminder:|note:)\s*,?\s*"#)
    s = drop(s, #"(?i)\bthere will be no\b"#, "No")
    s = drop(s, #"(?i)\s*\bon this day\b"#)
    s = drop(drop(s, #"\s{2,}"#, " "), edges)
    guard !s.isEmpty else { return text }
    guard s.count > 70 else { return s }
    let cut = s.prefix(70)
    return String(cut[..<(cut.lastIndex(of: " ") ?? cut.endIndex)]) + "…"
}

extension Deadline {
    /// Moodle activities keep their own name; dates found in text get the AI title (already says when) or their main point.
    var headline: String { headlineCache ?? (source == nil ? title : summary?.title ?? mainPoint(title)) }
    var dateText: String { Self.dateText(date) }
    /// "Fri 13 Nov" (+ ", 18:30" when a time was given; 23:59 = "by the end of the day").
    static func dateText(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        guard !(c.hour == 23 && c.minute == 59) else { return date.short() }
        return date.short() + ", " + String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
    var label: String { summary != nil ? headline : "\(headline) · \(dateText)" }
}

/// Whether a dated line says anything besides its date: "Dec 8 — -" doesn't, "Dec 8 — Final Project Presentation" does.
func hasContent(_ text: String) -> Bool {
    let dateWords: Set = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec", "january", "february",
                          "march", "april", "june", "july", "august", "september", "october", "november", "december",
                          "mon", "tue", "wed", "thu", "fri", "sat", "sun", "st", "nd", "rd", "th"]
    return words(mainPoint(text)).contains { $0.count > 1 && !dateWords.contains($0) } // one real word ("Keynote") is enough
}
