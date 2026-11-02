import Foundation

/// A done / dismissed / snoozed mark on a board item (deadline-priority.md §3). It's stored under the SHA-256 of every
/// member key of the item's cluster, so it survives a date change, and a member that joins later (a "moved to" post)
/// is covered by the keys already there.
struct Mark: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable { case done, dismissed, snoozed }
    var state: State
    var until: Date? = nil // snoozed: back at this time
    var itemDate: Date // the item's date when marked: a move of more than 12 h brings a dismissed or snoozed item back (D4)
    var at: Date
}

typealias Marks = [String: Mark]

/// `board-state.json`, owner-only like the other caches. Keys are hashed, so the file holds no titles.
enum BoardState {
    static let url = MoodleCache.url.deletingLastPathComponent().appending(path: "board-state.json")
    static func load() -> Marks { (try? JSONDecoder().decode(Marks.self, from: Data(contentsOf: url))) ?? [:] }
    static func save(_ marks: Marks) throws { try writeOwnerOnly(JSONEncoder().encode(marks), to: url) }
    static func key(_ memberKey: String) -> String { Jev.id(memberKey) }
}

extension Deadline {
    /// The member keys of the whole cluster: a mark on any of them is a mark on the item.
    var clusterKeys: [String] { ([memberKey] + alsoIn.map(\.memberKey)).filter { !$0.isEmpty } }
}

/// The items with their marks (§3.3): done stays hidden; dismissed and snoozed (until `until`) stay hidden unless the
/// date moved more than 12 h since the mark, in which case the item comes back with `dateChanged`.
func applyMarks(_ items: [Deadline], _ marks: Marks, now: Date) -> [Deadline] {
    guard !marks.isEmpty else { return items }
    return items.map { d in
        var d = d
        guard let m = d.clusterKeys.compactMap({ marks[BoardState.key($0)] }).max(by: { $0.at < $1.at }) else { return d }
        let moved = abs(d.date.timeIntervalSince(m.itemDate)) > 12 * 3600
        d.mark = m
        switch m.state {
        case .done: d.hidden = true
        case .dismissed: d.hidden = !moved; d.dateChanged = moved
        case .snoozed: d.hidden = !moved && now < (m.until ?? .distantFuture); d.dateChanged = moved
        }
        return d
    }
}

/// After a sync: drops marks whose item is gone from every source (`live` = hashed keys) and was dated over 30 days ago.
func pruneMarks(_ marks: Marks, live: Set<String>, now: Date) -> Marks {
    marks.filter { live.contains($0.key) || $0.value.itemDate > now.addingTimeInterval(-30 * 86_400) }
}

/// The snooze menu: tomorrow 08:00, Monday 08:00, and 2 days before it's due (while that's still ahead).
func snoozeOptions(_ d: Deadline, now: Date, calendar: Calendar = .current) -> [(label: String, until: Date)] {
    var out: [(label: String, until: Date)] = []
    if let t = calendar.date(byAdding: .day, value: 1, to: now), let at8 = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: t) {
        out.append(("Tomorrow 08:00", at8))
    }
    if let mon = calendar.nextDate(after: now, matching: DateComponents(hour: 8, minute: 0, weekday: 2), matchingPolicy: .nextTime) {
        out.append(("Monday 08:00", mon))
    }
    let before = d.date.addingTimeInterval(-2 * 86_400)
    if before > now { out.append(("2 days before it's due", before)) }
    return out
}
