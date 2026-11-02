import Foundation

/// Outlook Calendar through its published ICS link (Outlook ▸ Settings ▸ Calendar ▸ Shared calendars ▸ Publish). MBZUAI
/// doesn't let students register apps, so Microsoft Graph isn't available. The link works like a password: Keychain only
/// (account `outlook.ics`), never logged.
enum OutlookCalendar {
    static let account = "outlook.ics"

    struct Item: Equatable, Sendable {
        let title: String, start: Date, location: String, notes: String, recurring: Bool
        var uid = "", end: Date? = nil, rrule: String? = nil, exdates: [Date] = [], recurrenceID: Date? = nil
    }

    /// One concrete session or event on the calendar.
    struct Occurrence: Identifiable, Sendable {
        let title: String, start: Date, end: Date, location: String, notes: String
        var id: String { "\(title)|\(start.timeIntervalSince1970)" }
    }

    static func fetch(_ link: String) async throws -> [Item] {
        guard let url = URL(string: link), url.scheme?.lowercased() == "https" else { throw MoodleError.insecureSite }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200, let text = String(data: data, encoding: .utf8),
              text.contains("BEGIN:VCALENDAR") else { throw OutlookError.notACalendar }
        return parse(text)
    }

    /// VEVENTs from an ICS file: unfolded lines, escaped text decoded, times in UTC ("…Z"), as an all-day DATE (end of that
    /// day), or with a TZID (read as this Mac's time zone).
    static func parse(_ ics: String) -> [Item] {
        let unfolded = ics.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n ", with: "").replacingOccurrences(of: "\n\t", with: "")
        return unfolded.components(separatedBy: "BEGIN:VEVENT").dropFirst().compactMap { block in
            var fields: [String: (params: String, value: String)] = [:]
            var exdates: [Date] = []
            for line in block.components(separatedBy: "\n") {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let head = line[..<colon], name = String(head.split(separator: ";").first ?? ""), value = String(line[line.index(after: colon)...])
                if name == "EXDATE" { exdates += value.split(separator: ",").compactMap { date(String($0), params: String(head)) } } // may repeat
                if fields[name] == nil { fields[name] = (String(head), value) }
            }
            guard let start = fields["DTSTART"].flatMap({ date($0.value, params: $0.params) }) else { return nil }
            return Item(title: unescape(fields["SUMMARY"]?.value ?? "Event"), start: start, location: unescape(fields["LOCATION"]?.value ?? ""),
                        notes: unescape(fields["DESCRIPTION"]?.value ?? ""), recurring: fields["RRULE"] != nil,
                        uid: fields["UID"]?.value ?? "", end: fields["DTEND"].flatMap { date($0.value, params: $0.params) },
                        rrule: fields["RRULE"]?.value, exdates: exdates,
                        recurrenceID: fields["RECURRENCE-ID"].flatMap { date($0.value, params: $0.params) })
        }
    }

    static func date(_ value: String, params: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        if params.contains("VALUE=DATE") || value.count == 8 { // all day: "by the end of that day", like other dated items
            f.dateFormat = "yyyyMMdd"
            return f.date(from: value).flatMap { Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: $0) }
        }
        f.dateFormat = "yyyyMMdd'T'HHmmss"
        if value.hasSuffix("Z") { f.timeZone = TimeZone(identifier: "UTC"); return f.date(from: String(value.dropLast())) }
        f.timeZone = .current // ponytail: TZID is a Windows zone name ("Arabian Standard Time"); fine while the Mac is in the same zone
        return f.date(from: value)
    }

    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\;", with: ";").replacingOccurrences(of: "\\\\", with: "\\")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One-off events (talks, keynotes, exams, changes) join the courses they name, or General. Recurring class sessions are
    /// the timetable, not news, so they stay off the board.
    static func merge(_ items: [Item], into subjects: [Subject], now: Date = .now) -> [Subject] {
        var out = subjects.map { s -> Subject in var s = s; s.events = s.events?.filter { $0.source != .outlook }; return s }
        let window = now.addingTimeInterval(-30 * 86_400)...now.addingTimeInterval(200 * 86_400)
        var general: [CourseEvent] = []
        for i in items where !i.recurring && i.recurrenceID == nil && window.contains(i.start) { // a moved class session isn't news
            let text = [i.title, i.location.isEmpty ? nil : "Where: \(i.location)", i.notes.isEmpty ? nil : i.notes].compactMap { $0 }.joined(separator: "\n")
            let e = CourseEvent(title: i.title, date: i.start, source: .outlook, detail: text, origin: text,
                                via: .outlookCalendar, ref: i.uid.isEmpty ? nil : i.uid)
            if let n = Moodle.route(i.title, out) { out[n].events = ((out[n].events ?? []) + [e]).sorted { $0.date < $1.date } } else { general.append(e) }
        }
        guard !general.isEmpty else { return out }
        if let g = out.firstIndex(where: { $0.code == "GENERAL" }) {
            out[g].events = ((out[g].events ?? []) + general).sorted { $0.date < $1.date }
        } else {
            out.append(Subject(id: "general", name: "MBZUAI · General", code: "GENERAL", hue: .slate, assessments: [], assignments: [],
                               materials: [], announcements: [], events: general.sorted { $0.date < $1.date }))
        }
        return out
    }

    /// Every session and event in [from, to): weekly/daily RRULEs expanded (INTERVAL, BYDAY, UNTIL, COUNT), EXDATEs skipped,
    /// and a moved session (RECURRENCE-ID) shown at its new time instead of the original.
    static func occurrences(_ items: [Item], from: Date, to: Date) -> [Occurrence] {
        let moved = Set(items.compactMap { i in i.recurrenceID.map { "\(i.uid)|\($0.timeIntervalSince1970)" } })
        let cal = Calendar.current
        var out: [Occurrence] = []
        func add(_ i: Item, at start: Date) {
            guard start >= from, start < to else { return }
            out.append(Occurrence(title: i.title, start: start, end: start.addingTimeInterval((i.end ?? i.start).timeIntervalSince(i.start)),
                                  location: i.location, notes: i.notes))
        }
        for i in items {
            guard let rule = i.rrule else { add(i, at: i.start); continue }
            var r: [String: String] = [:]
            for p in rule.split(separator: ";") { let kv = p.split(separator: "=", maxSplits: 1); if kv.count == 2 { r[String(kv[0])] = String(kv[1]) } }
            let interval = max(1, Int(r["INTERVAL"] ?? "1") ?? 1), count = r["COUNT"].flatMap(Int.init)
            let until = r["UNTIL"].flatMap { date($0, params: "") } ?? .distantFuture
            let skip = Set(i.exdates.map { Int($0.timeIntervalSince1970 / 60) })
            let codes = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
            let days = (r["BYDAY"] ?? "").split(separator: ",").compactMap { codes.firstIndex(of: String($0.suffix(2))).map { $0 + 1 } }
            var made = 0, step = 0
            stepping: while true {
                var candidates: [Date] = []
                if r["FREQ"] == "WEEKLY" {
                    guard let week = cal.date(byAdding: .weekOfYear, value: step * interval, to: i.start) else { break }
                    let weekday = cal.component(.weekday, from: week)
                    candidates = (days.isEmpty ? [weekday] : days).sorted().compactMap { cal.date(byAdding: .day, value: $0 - weekday, to: week) }
                } else if r["FREQ"] == "DAILY" {
                    candidates = cal.date(byAdding: .day, value: step * interval, to: i.start).map { [$0] } ?? []
                } else { add(i, at: i.start); break } // ponytail: monthly/yearly series show their first date only
                for d in candidates.sorted() where d >= i.start {
                    if d > until || d >= to || (count.map { made >= $0 } ?? false) { break stepping }
                    made += 1
                    if skip.contains(Int(d.timeIntervalSince1970 / 60)) || moved.contains("\(i.uid)|\(d.timeIntervalSince1970)") { continue }
                    add(i, at: d)
                }
                step += 1
                if step > 600 { break } // safety: ~11 years of weeks
            }
        }
        return out.sorted { $0.start < $1.start }
    }

    private static let session = URLSession(configuration: .ephemeral) // the link is a secret: never disk-cached
}

enum OutlookError: LocalizedError {
    case notACalendar
    var errorDescription: String? { "That link didn't return a calendar (use the ICS link, not the HTML one)" }
}
