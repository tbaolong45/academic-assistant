import Foundation
import UserNotifications

/// macOS notifications for what's new since the previous sync: announcements, grades, assignments, files.
enum Notifier {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Everything in `new` that wasn't in `old`, as (title, body) pairs. Pure, so it can be self-checked.
    static func changes(old: [Subject], new: [Subject]) -> [(title: String, body: String)] {
        let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [(String, String)] = []
        for s in new {
            guard let o = before[s.id] else { continue } // a course seen for the first time is not "news"
            let oldNews = Set(o.announcements.map { "\($0.title)|\($0.date)" })
            for a in s.announcements where !oldNews.contains("\(a.title)|\(a.date)") {
                out.append(("📣 \(s.name): \(a.title)", String((a.body ?? a.from).prefix(180))))
            }
            let oldGraded = Set(o.assessments.filter { $0.raw != nil }.map(\.id))
            for a in s.assessments where a.raw != nil && !oldGraded.contains(a.id) {
                out.append(("🎯 \(s.name): new grade", a.name)) // no score: notifications show on the lock screen
            }
            let oldTasks = Set(o.assignments.map(\.title))
            for a in s.assignments where !oldTasks.contains(a.title) {
                out.append(("📝 \(s.name): new assignment", a.due == .distantFuture ? a.title : "\(a.title) · due \(a.due.short())"))
            }
            let oldMats = Set(o.materials.map(\.title))
            let newMats = s.materials.filter { !oldMats.contains($0.title) }
            if !newMats.isEmpty {
                out.append(("📚 \(s.name): \(newMats.count) new file\(newMats.count == 1 ? "" : "s")", newMats.prefix(3).map(\.title).joined(separator: ", ")))
            }
        }
        return out
    }

    static func post(_ items: [(title: String, body: String)]) {
        for (i, item) in items.prefix(10).enumerated() {
            let c = UNMutableNotificationContent()
            c.title = item.title
            c.body = item.body
            c.sound = .default
            let req = UNNotificationRequest(identifier: "aa-\(Date.now.timeIntervalSince1970)-\(i)", content: c, trigger: nil)
            UNUserNotificationCenter.current().add(req)
        }
    }
}
