import CryptoKit
import Foundation

/// What an LMS item is for the student. Raw values are the choice names sent to Jev.
enum ItemKind: String, Codable, Sendable, CaseIterable {
    case deadline, exam, classChange = "class_change", event, grades, info

    var label: String {
        switch self {
        case .deadline: "DEADLINE"
        case .exam: "EXAM/QUIZ"
        case .classChange: "CLASS CHANGE"
        case .event: "EVENT"
        case .grades: "GRADES OUT"
        case .info: "INFO"
        }
    }

    /// Criteria text Jev scores each choice against.
    var criterion: String {
        switch self {
        case .deadline: "The student must submit or hand in work (assignment, report, script, slides, paper, form) by a date"
        case .exam: "An exam, quiz, test or graded in-class assessment the student will sit"
        case .classChange: "A class or lab is cancelled, moved, rescheduled, combined or replaced, or there are no classes"
        case .event: "A session to attend that is not graded: talk, keynote, workshop, office hours, lab session, meeting"
        case .grades: "Marks, grades, results or feedback have been released or published"
        case .info: "General information, reminders, resources, policies or anything else with no action date"
        }
    }

    /// Kinds that belong on the deadline board; grades-out and general info are news, not deadlines.
    var isDated: Bool { self != .grades && self != .info }
}

/// TypeSafe's "System One" decision model (Jev): one choice question per item, answer = label + confidence.
/// The key is stored in the Keychain (account `api.typesafe.ai`). Item text is sent to TypeSafe.
enum Jev {
    static let account = "api.typesafe.ai"
    static let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!
    static let model = "jev-latest" // ponytail: floating alias; pin a version from GET /v1/models if answers drift

    static func body(_ text: String) -> Data {
        let question: [String: Any] = [
            "type": "choice",
            "instructions": "This text comes from a university course page (an announcement, or a sentence with a date from an announcement or course document). What kind of item is it for the student?",
            "criteria": Dictionary(uniqueKeysWithValues: ItemKind.allCases.map { ($0.rawValue, $0.criterion) }),
        ]
        let json: [String: Any] = ["model": model, "state": String(scrubPersonal(text).prefix(6000)), "questions": ["kind": question]]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    struct Answer: Codable, Sendable, Equatable { let kind: ItemKind, confidence: Double }

    static func parse(_ data: Data) throws -> Answer {
        struct Reply: Decodable {
            struct Choice: Decodable { let choice: String, confidence: Double? }
            let answers: [String: Choice]
        }
        guard let a = try JSONDecoder().decode(Reply.self, from: data).answers["kind"], let kind = ItemKind(rawValue: a.choice)
        else { throw JevError.unexpectedReply }
        return Answer(kind: kind, confidence: a.confidence ?? 0)
    }

    static func classify(_ text: String, key: String) async throws -> Answer { try parse(await post(body(text), key: key)) }

    /// Yes/no questions about one state: name → probability of "yes" (Jev's `noul` answer).
    static func yesNo(state: Any, _ questions: [String: String], key: String) async throws -> [String: Double] {
        // Questions are scrubbed too: Summarizer quotes each source sentence in one.
        let qs = questions.mapValues { ["type": "noul", "instructions": scrubPersonal($0)] }
        let scrubbed: Any = switch state {
        case let s as String: scrubPersonal(s)
        case let d as [String: Any]: d.mapValues { ($0 as? String).map(scrubPersonal) ?? $0 }
        default: state
        }
        let data = try await post(try JSONSerialization.data(withJSONObject: ["model": model, "state": scrubbed, "questions": qs]), key: key)
        return try parseYesNo(data)
    }

    static func parseYesNo(_ data: Data) throws -> [String: Double] {
        struct Reply: Decodable { struct A: Decodable { let noul: Double? }; let answers: [String: A] }
        let answers = try JSONDecoder().decode(Reply.self, from: data).answers.compactMapValues(\.noul)
        guard !answers.isEmpty else { throw JevError.unexpectedReply }
        return answers
    }

    private static func post(_ body: Data, key: String) async throws -> Data {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 30
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw status == 401 || status == 403 ? JevError.badKey : JevError.http(status) }
        return data
    }

    private static let session = URLSession(configuration: .ephemeral)

    /// Cache key: the same text is classified once, ever.
    static func id(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum JevError: LocalizedError {
    case badKey, http(Int), unexpectedReply
    var errorDescription: String? {
        switch self {
        case .badKey: "Jev rejected the API key"
        case .http(let code): "Jev answered HTTP \(code)"
        case .unexpectedReply: "Jev's reply wasn't a choice answer"
        }
    }
}

/// Answers already received, so each text costs one call: ~/Library/Application Support/AcademicAssistant/kinds.json (owner-only).
enum KindCache {
    static let url = MoodleCache.url.deletingLastPathComponent().appending(path: "kinds.json")
    static func load() -> [String: Jev.Answer] { (try? JSONDecoder().decode([String: Jev.Answer].self, from: Data(contentsOf: url))) ?? [:] }
    static func save(_ all: [String: Jev.Answer]) { try? writeOwnerOnly(JSONEncoder().encode(all), to: url) }
}

/// Removes personal details before text leaves the Mac (Jev, DeepSeek): email addresses, phone numbers and the
/// signature block. Dates, times, course codes, rooms and percentages stay. Cache keys still hash the original text.
func scrubPersonal(_ text: String) -> String {
    let signOffs: Set = ["best regards", "kind regards", "warm regards", "regards", "best", "many thanks", "thanks",
                         "thank you", "cheers", "sincerely"]
    var lines = text.components(separatedBy: "\n")
    if let cut = lines.firstIndex(where: { raw in
        let line = raw.trimmingCharacters(in: .whitespaces), lower = line.lowercased()
        let bare = lower.hasSuffix(",") || lower.hasSuffix("!") ? String(lower.dropLast()) : lower
        return signOffs.contains(bare) || line == "--" || line.hasPrefix("Sent from my") || line.hasPrefix("Get Outlook for")
    }) {
        lines.removeSubrange(cut...)
    }
    var out = lines.joined(separator: "\n")
    if lines.count < text.components(separatedBy: "\n").count {
        out = String(out.reversed().drop { $0.isWhitespace }.reversed())
    }
    out = out.replacingOccurrences(of: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#, with: "[email]", options: .regularExpression)
    // 9+ digits joined by spaces, "-", "." or "()" ("/" isn't a separator, so 23/10/2026 stays).
    out = out.replacingOccurrences(of: #"(?<!\w)\+?\(?\d(?:[ .\-()]{0,2}\d){8,}(?!\w)"#, with: "[phone]", options: .regularExpression)
    return out
}

extension Announcement { var classifyText: String { "\(title)\n\n\(body ?? "")" } }
extension CourseEvent { var classifyText: String { detail ?? title } }

/// Puts known answers on every announcement and event (pure, so sync results can be labelled instantly from the cache).
/// An unsure "info"/"grades" (< 0.6) is left unlabelled so the item stays on the board: an audit of 240 labels found 32% of
/// answers below 0.6 wrong (e.g. TA revision sessions called info) against under 2% above.
func labeled(_ subjects: [Subject], _ known: [String: Jev.Answer]) -> [Subject] {
    func kind(_ text: String) -> ItemKind? {
        guard let a = known[Jev.id(text)] else { return nil }
        return a.kind.isDated || a.confidence >= 0.6 ? a.kind : nil
    }
    return subjects.map { s in
        var s = s
        s.announcements = s.announcements.map { var a = $0; a.kind = kind(a.classifyText); return a }
        s.events = s.events?.map { var e = $0; e.kind = kind(e.classifyText); return e }
        return s
    }
}
