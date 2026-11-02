import Foundation

/// An AI title for a dated item, with Jev's verdict on it (probabilities of "yes").
struct Summary: Codable, Sendable, Hashable {
    let title: String
    let parts: [String] // the sentences Jev picked as important, in their original order
    let mentionsDate: Double // "does the title say when?"
    let keepsPoint: Double // "does the title keep the main point?"
    let faithful: Double // "does it state only what the source says?" (no invented "material due")
    let specific: Double // "does it name the specific item, not something generic?"
    /// Shown only when Jev is fairly sure on all four (a 0.58 "keeps the point" let an invented title through).
    /// Jev's "invents?" answer is noisy (the same title scored 0.40 and 0.63), so it rejects only when invention is more likely than not.
    var accepted: Bool { !title.isEmpty && mentionsDate >= 0.6 && keepsPoint >= 0.7 && faithful >= 0.5 && specific >= 0.6 }
    static let skipped = Summary(title: "", parts: [], mentionsDate: 0, keepsPoint: 0, faithful: 0, specific: 0)
    /// What Jev found wrong, in words DeepSeek can act on.
    var failures: [String] {
        [mentionsDate < 0.6 ? "it doesn't say when (use the date given)" : nil,
         keepsPoint < 0.7 ? "it misses the main point" : nil,
         faithful < 0.5 ? "it adds or changes a fact that isn't in the parts" : nil,
         specific < 0.6 ? "it's too vague: name the specific item" : nil].compactMap { $0 }
    }
}

/// DeepSeek (OpenAI-compatible chat completions). The key is stored in the Keychain (account `api.deepseek.com`);
/// only the sentences Jev picked are sent.
enum DeepSeek {
    static let account = "api.deepseek.com"
    static let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!
    static let model = "deepseek-flash" // ponytail: DeepSeek's current fast model name; update if they rename it again

    static func body(parts: [String], date: String, course: String = "", kind: String = "", feedback: String? = nil) -> Data {
        let system = """
            You write titles for a student's list of deadlines and events. Condense the given parts into ONE title of at most \
            14 words. Name the specific item (which assignment, exam, session or class change) and, if the parts say so, what \
            the student must do and where; end with the date given. Don't name the course (the app shows it beside the title). \
            Use only facts stated in the parts: never invent, never guess a purpose. If the parts don't say what the item is, reply exactly SKIP. Plain text only: no quotes, no \
            emoji, no trailing period.
            """
        let user = "Course: \(course)\nType: \(kind)\nDate: \(date)\nParts:\n" + parts.map { "- \(scrubPersonal($0))" }.joined(separator: "\n")
            + (feedback.map { "\n\nYour previous title was rejected: \($0). Write a better one." } ?? "")
        let json: [String: Any] = [
            // Thinking off: by default the V4 models reason first, which used up max_tokens and left the title empty.
            "model": model, "temperature": 0.2, "max_tokens": 300, "stream": false, "thinking": ["type": "disabled"],
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
        ]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    static func parse(_ data: Data) throws -> String {
        struct Reply: Decodable { struct C: Decodable { struct M: Decodable { let content: String? }; let message: M }; let choices: [C] }
        let text = try JSONDecoder().decode(Reply.self, from: data).choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”.")))
        guard let text, !text.isEmpty else { throw SummaryError.emptyTitle }
        return String(text.prefix(140))
    }

    static func title(parts: [String], date: String, course: String = "", kind: String = "", feedback: String? = nil, key: String) async throws -> String {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body(parts: parts, date: date, course: course, kind: kind, feedback: feedback)
        req.timeoutInterval = 60
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw status == 401 || status == 403 ? SummaryError.badKey : SummaryError.http(status) }
        return try parse(data)
    }

    private static let session = URLSession(configuration: .ephemeral)
}

enum SummaryError: LocalizedError {
    case badKey, http(Int), emptyTitle
    var errorDescription: String? {
        switch self {
        case .badKey: "DeepSeek rejected the API key"
        case .http(let code): "DeepSeek answered HTTP \(code)"
        case .emptyTitle: "DeepSeek returned an empty title"
        }
    }
}

/// Jev picks the important parts → DeepSeek condenses them into a title → Jev checks the title.
enum Summarizer {
    /// Sentences of the source text, at most 20 (Jev scores each one).
    static func sentences(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: "\n!?")).flatMap { $0.components(separatedBy: ". ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.count > 3 }.prefix(20).map { $0 }
    }

    /// Parts Jev said "yes" to (≥ 0.5), at most the 4 most likely, in reading order; the item's own sentence is always kept.
    static func pick(_ sentences: [String], yes: [String: Double], own: String) -> [String] {
        let chosen = Set(sentences.indices.filter { (yes["p\($0)"] ?? 0) >= 0.5 }.sorted { (yes["p\($0)"] ?? 0) > (yes["p\($1)"] ?? 0) }.prefix(4))
        var parts = sentences.indices.filter(chosen.contains).map { sentences[$0] }
        if !parts.contains(where: { own.contains($0) || $0.contains(own) }) { parts.insert(own, at: 0) }
        return parts
    }

    static func summarize(_ e: CourseEvent, course: String, jevKey: String, deepSeekKey: String) async throws -> Summary {
        let date = Deadline.dateText(e.date)
        // Scrubbed as whole texts (a sign-off only drops its signature block in context); Summarizer.id keeps the raw origin.
        let own = scrubPersonal(e.detail ?? e.title)
        guard hasContent(e.title) else { return .skipped } // "Dec 8 — -": nothing to summarize, so nothing to invent
        let all = sentences(scrubPersonal(e.origin ?? e.detail ?? e.title))
        var parts = [own]
        if all.count > 1 {
            var questions: [String: String] = [:]
            for (i, s) in all.enumerated() {
                questions["p\(i)"] = "Is this part needed to understand what happens on \(date) and what the student must do? Part: «\(s)»"
            }
            parts = pick(all, yes: try await Jev.yesNo(state: e.origin ?? own, questions, key: jevKey), own: own)
        }
        // One retry: a rejected title goes back to DeepSeek with the checks it failed.
        var feedback: String?
        var best = Summary.skipped
        for _ in 0..<2 {
            let title = try await DeepSeek.title(parts: parts, date: date, course: course, kind: e.kind?.label ?? "unknown",
                                                 feedback: feedback, key: deepSeekKey)
            guard title != "SKIP" else { break }
            let s = try await check(title, parts: parts, date: date, course: course, kind: e.kind?.label ?? "", key: jevKey)
            if s.accepted || best.title.isEmpty { best = s }
            if s.accepted { break }
            feedback = "“\(title)” " + s.failures.joined(separator: "; ")
        }
        return best.title.isEmpty ? Summary(title: "", parts: parts, mentionsDate: 0, keepsPoint: 0, faithful: 0, specific: 0) : best
    }

    /// Jev's four yes/no checks on a title. The course and type are given too, so naming them doesn't count as "invented".
    static func check(_ title: String, parts: [String], date: String, course: String, kind: String, key: String) async throws -> Summary {
        let a = try await Jev.yesNo(state: ["course": course, "type": kind, "source": parts.joined(separator: "\n"), "date": date, "title": title], [
            "date": "Does the title say when this happens or is due (the date \(date), or an equivalent)?",
            "point": "Does the title keep the main point of the source: what is due or what is happening?",
            // Asked as "does it invent?" (yes = bad): asked positively, Jev also punished harmless rewording such as "Attend …".
            "invents": "Does the title add a fact that is not in the source (a name, place, time, task or purpose) or contradict it? Rewording, a verb like 'attend', the course name and the date format do not count.",
            "specific": "Does the title name the specific item (which assignment, exam, session or class change) rather than something generic or vague?",
        ], key: key)
        return Summary(title: title, parts: parts, mentionsDate: a["date"] ?? 0, keepsPoint: a["point"] ?? 0,
                       faithful: 1 - (a["invents"] ?? 1), specific: a["specific"] ?? 0)
    }

    /// The titles of items still in `subjects`. Run it on the published subjects (all sources), never on a partial set,
    /// or Outlook and mail titles (paid for) are dropped.
    /// The events to title this run: dated, in `window`, not titled yet, and with a card someone can see (P9). A member of a
    /// cluster a Moodle activity wins shows the Moodle title, and a marked cluster is hidden, so neither is sent. This is
    /// worked out from the current clusters every run, never cached: once the assignment leaves the board or the cluster
    /// splits, the post is titled on the next run. Prune still keeps titles of hidden members, so a re-split costs nothing.
    static func targets(_ subjects: [Subject], board: [BoardItem], titles: [String: Summary],
                        window: ClosedRange<Date>) -> [(course: String, event: CourseEvent)] {
        var hidden = Set<String>()
        for d in board {
            if d.hidden { hidden.insert(d.id) }
            if d.hidden || d.resolvedVia == .moodleActivity { hidden.formUnion(d.alsoIn.map(\.id)) }
        }
        var seen = Set<String>()
        return subjects.flatMap { s in (s.events ?? []).map { (s, $0) } }
            .filter { s, e in window.contains(e.date) && e.kind?.isDated != false && titles[id(e)] == nil
                && !hidden.contains(Deadline.eventID(s, e)) && seen.insert(id(e)).inserted }
            .map { (course: $0.0.name, event: $0.1) }
    }

    static func prune(_ titles: [String: Summary], to subjects: [Subject]) -> [String: Summary] {
        let live = Set(subjects.flatMap { $0.events ?? [] }.map(id))
        return titles.filter { live.contains($0.key) }
    }

    /// Cache key: same source, same sentence and same date → same title.
    static func id(_ e: CourseEvent) -> String { Jev.id("\(e.origin ?? "")|\(e.detail ?? e.title)|\(e.date.timeIntervalSince1970)") }
}

/// ~/Library/Application Support/AcademicAssistant/summaries.json (owner-only).
enum SummaryCache {
    static let url = MoodleCache.url.deletingLastPathComponent().appending(path: "summaries.json")
    static func load() -> [String: Summary] { (try? JSONDecoder().decode([String: Summary].self, from: Data(contentsOf: url))) ?? [:] }
    static func save(_ all: [String: Summary]) throws { try writeOwnerOnly(JSONEncoder().encode(all), to: url) }
}

/// Puts known titles on events (pure, like `labeled`).
func summarized(_ subjects: [Subject], _ known: [String: Summary]) -> [Subject] {
    subjects.map { s in
        var s = s
        s.events = s.events?.map { var e = $0; e.summary = known[Summarizer.id(e)]; return e }
        return s
    }
}
