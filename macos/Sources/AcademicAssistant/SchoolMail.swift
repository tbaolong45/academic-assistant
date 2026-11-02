import Foundation
import Network

/// School mail (Outlook, incl. Teams notifications), forwarded by an Outlook rule to the user's Gmail and read over IMAP:
/// MBZUAI blocks app registrations, so Microsoft Graph isn't available. Only mail addressed to @mbzuai.ac.ae is read.
/// The Gmail app password is kept in the Keychain (account `imap.gmail.com`, value "address\npassword"). The app talks
/// IMAP itself (`IMAPConnection`): one TLS connection per sync, All Mail opened read-only, so it never marks mail read.
enum SchoolMail {
    static let account = "imap.gmail.com"
    static let domain = "mbzuai.ac.ae"

    struct Message: Codable, Sendable, Equatable { let uid: Int, subject: String, from: String, date: Date, body: String }

    /// Signs in, opens All Mail read-only, runs `body` on that one connection, then logs out (also after an error).
    static func session<T: Sendable>(address: String, password: String, host: String = "imap.gmail.com",
                                     _ body: @Sendable (IMAPConnection) async throws -> T) async throws -> T {
        // AUTHENTICATE PLAIN separates its fields with NUL, so a control character could move the password field.
        guard isSafeCredential(address) && isSafeCredential(password) else { throw MailError.badCredential }
        let imap = IMAPConnection(host: host)
        do {
            try await imap.open(address: address, password: password)
            let result = try await body(imap)
            await imap.close()
            return result
        } catch {
            imap.cancel() // no LOGOUT on a failed session: the stream may be stuck mid-command
            throw error
        }
    }

    /// Non-empty and free of control characters (`\0`, `\n`, `\r`, `\t`, …).
    static func isSafeCredential(_ s: String) -> Bool {
        !s.isEmpty && s.rangeOfCharacter(from: .controlCharacters) == nil
    }

    /// UIDs still to download: not stored, not seen-but-unparseable, and fewer than 3 failed fetches.
    static func toFetch(uids: [Int], have: Set<Int>, seen: Set<Int>, failures: [Int: Int]) -> [Int] {
        uids.filter { !have.contains($0) && !seen.contains($0) && failures[$0, default: 0] < 3 }
    }

    /// Downloads `uids` one by one and saves after each, so one slow or broken mail can't stall the rest or lose what
    /// came before it. A lost connection (timeout or close) counts one failure for the mail in flight, so a mail that always
    /// kills the connection is skipped after 3 syncs instead of blocking later mail, then stops the run. A cancelled task
    /// stops it without counting anything.
    static func download(_ uids: [Int], into store: inout MailStore, fetch: (Int) async throws -> Message?,
                         save: (MailStore) -> Void) async {
        for uid in uids {
            do {
                if let m = try await fetch(uid) { store.messages.append(m) } else { store.seen.insert(uid) }
                store.failures[uid] = nil
            } catch {
                if Task.isCancelled { break }
                store.failures[uid, default: 0] += 1
                if let e = error as? MailError, e == .timeout || e == .closed { save(store); break } // the rest stay uncounted
            }
            save(store)
        }
    }

    /// SASL PLAIN with the initial response: base64, so the password needs no IMAP quoting and never travels as plain text.
    static func authenticateLine(tag: String, address: String, password: String) -> String {
        "\(tag) AUTHENTICATE PLAIN " + Data("\0\(address)\0\(password)".utf8).base64EncodedString()
    }

    /// PEEK leaves the mail unread (EXAMINE already makes the mailbox read-only). Only the first 256 KB: the text part
    /// comes first, and one big attachment can't push a fetch past the 30 s command limit.
    static func fetchCommand(uid: Int) -> String { "UID FETCH \(uid) BODY.PEEK[]<0.262144>" }

    /// Throws unless the line tagged `tag` says OK. The error never carries server text (it could echo the credential).
    static func status(_ response: Data, tag: String, login: Bool = false) throws {
        let b = [UInt8](response)
        var end = b.count
        if end >= 2, b[end - 2] == 13, b[end - 1] == 10 { end -= 2 }
        var start = end
        while start > 0, b[start - 1] != 10 { start -= 1 }
        let line = String(decoding: b[start..<end], as: UTF8.self)
        guard line.hasPrefix(tag + " ") else { throw MailError.server("no reply") }
        let word = line.dropFirst(tag.count + 1).prefix { $0 != " " }.uppercased()
        guard word != "OK" else { return }
        throw login ? MailError.badLogin : MailError.server(word == "NO" || word == "BAD" ? word : "error")
    }

    /// The message bytes in an untagged `* n FETCH (UID … BODY[]<0> {len}` reply: exactly `len` bytes after the line
    /// (fewer if the reply was cut short). nil without a literal.
    static func literal(_ reply: Data) -> Data? {
        let bytes = [UInt8](reply)
        guard let open = bytes.firstIndex(of: UInt8(ascii: "{")) else { return nil }
        var i = open + 1, length = 0
        while i < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[i]) { length = length * 10 + Int(bytes[i] - UInt8(ascii: "0")); i += 1 }
        guard i > open + 1, i + 2 < bytes.count, bytes[i] == UInt8(ascii: "}"), bytes[i + 1] == 13, bytes[i + 2] == 10 else { return nil }
        let start = i + 3
        return Data(bytes[start..<min(start + length, bytes.count)])
    }

    // MARK: MIME (enough for school mail: headers, multipart, base64 / quoted-printable, encoded-word subjects)

    static func parse(_ raw: String, uid: Int) -> Message? {
        let (headers, body) = split(raw)
        guard let date = headers["date"].flatMap(rfc2822) else { return nil }
        let from = decodeWords(headers["from"] ?? "").replacingOccurrences(of: #"\s*<[^>]*>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        return Message(uid: uid, subject: decodeWords(headers["subject"] ?? "(no subject)"), from: from.isEmpty ? "Outlook" : from,
                       date: date, body: text(headers: headers, body: body))
    }

    /// Headers (lowercased names, unfolded) and the body.
    static func split(_ part: String) -> ([String: String], String) {
        let s = part.replacingOccurrences(of: "\r\n", with: "\n")
        let cut = s.range(of: "\n\n")
        let head = cut.map { String(s[..<$0.lowerBound]) } ?? s, body = cut.map { String(s[$0.upperBound...]) } ?? ""
        var headers: [String: String] = [:], last: String?
        for line in head.components(separatedBy: "\n") {
            if line.first == " " || line.first == "\t", let l = last { headers[l, default: ""] += " " + line.trimmingCharacters(in: .whitespaces); continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].lowercased()
            if headers[name] == nil { headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces) }
            last = name
        }
        return (headers, body)
    }

    /// Plain text of a (possibly multipart) body: text/plain preferred, else text/html stripped.
    static func text(headers: [String: String], body: String) -> String {
        let type = headers["content-type"]?.lowercased() ?? "text/plain"
        if type.hasPrefix("multipart/"), let b = param("boundary", in: headers["content-type"] ?? "") {
            let parts = body.components(separatedBy: "--\(b)").dropFirst().filter { !$0.hasPrefix("--") }.map(split)
            let plain = parts.first { ($0.0["content-type"] ?? "text/plain").lowercased().hasPrefix("text/plain") }
            let html = parts.first { ($0.0["content-type"] ?? "").lowercased().hasPrefix("text/html") }
            let nested = parts.first { ($0.0["content-type"] ?? "").lowercased().hasPrefix("multipart/") }
            if let p = plain ?? html ?? nested { return text(headers: p.0, body: p.1) }
            return ""
        }
        let decoded = decode(body, encoding: headers["content-transfer-encoding"] ?? "", charset: param("charset", in: headers["content-type"] ?? ""))
        return (type.hasPrefix("text/html") ? Moodle.plainText(decoded) : decoded).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decode(_ body: String, encoding: String, charset: String? = nil) -> String {
        switch encoding.lowercased().trimmingCharacters(in: .whitespaces) {
        case "base64":
            // Whole 4-character groups only: a fetch cut at 256 KB can end mid-group.
            let b64 = body.components(separatedBy: .whitespacesAndNewlines).joined()
            return Data(base64Encoded: String(b64.prefix(b64.count / 4 * 4))).map { text($0, charset: charset) } ?? body
        case "quoted-printable":
            return quotedPrintable(body.replacingOccurrences(of: "=\n", with: ""), charset: charset)
        default: return body
        }
    }

    /// Bytes in the message's own charset (school mail is often windows-1252: "–" was shown as "�" when read as UTF-8).
    static func text(_ data: Data, charset: String?) -> String {
        if let c = charset, !c.lowercased().contains("utf") {
            let cf = CFStringConvertIANACharSetNameToEncoding(c as CFString)
            if cf != kCFStringEncodingInvalidId, let s = String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))) { return s }
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func quotedPrintable(_ s: String, charset: String? = nil) -> String {
        var bytes: [UInt8] = [], i = s.startIndex
        while i < s.endIndex {
            if s[i] == "=", let end = s.index(i, offsetBy: 3, limitedBy: s.endIndex), let b = UInt8(s[s.index(after: i)..<end], radix: 16) {
                bytes.append(b); i = end
            } else { bytes += Array(String(s[i]).utf8); i = s.index(after: i) }
        }
        return text(Data(bytes), charset: charset)
    }

    /// "=?UTF-8?B?…?=" / "=?utf-8?Q?…?=" encoded words in headers.
    static func decodeWords(_ s: String) -> String {
        let joined = s.replacingOccurrences(of: #"\?=\s+=\?"#, with: "?==?", options: .regularExpression) // adjacent words join without the space
        let re = try! NSRegularExpression(pattern: #"=\?([^?]+)\?([BbQq])\?([^?]*)\?="#)
        var out = "", last = joined.startIndex
        for m in re.matches(in: joined, range: NSRange(joined.startIndex..., in: joined)) {
            guard let r = Range(m.range, in: joined), let cs = Range(m.range(at: 1), in: joined), let mode = Range(m.range(at: 2), in: joined),
                  let payload = Range(m.range(at: 3), in: joined) else { continue }
            out += joined[last..<r.lowerBound]
            let p = String(joined[payload]), charset = String(joined[cs])
            out += joined[mode].uppercased() == "B"
                ? Data(base64Encoded: p).map { text($0, charset: charset) } ?? p
                : quotedPrintable(p.replacingOccurrences(of: "_", with: " "), charset: charset)
            last = r.upperBound
        }
        return out + joined[last...]
    }

    static func param(_ name: String, in header: String) -> String? {
        guard let r = header.range(of: #"(?i)\b"# + name + #"\s*=\s*"?([^";]+)"?"#, options: .regularExpression) else { return nil }
        return header[r].components(separatedBy: "=").dropFirst().joined(separator: "=").trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
    }

    static func rfc2822(_ s: String) -> Date? {
        let clean = s.replacingOccurrences(of: #"\s*\([^)]*\)\s*$"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        for format in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z"] {
            f.dateFormat = format
            if let d = f.date(from: clean) { return d }
        }
        return nil
    }

    // MARK: Into the app

    /// Mail becomes announcements (source .outlook) on the course it names, else General; dates in it go on the board,
    /// linked back to the email.
    static func merge(_ messages: [Message], into subjects: [Subject]) -> [Subject] {
        var out = subjects.map { s -> Subject in
            var s = s
            s.announcements.removeAll { $0.source == .outlook }
            s.events = s.events?.filter { !($0.origin?.hasPrefix("✉︎") ?? false) }
            return s
        }
        var general: [Announcement] = [], generalEvents: [CourseEvent] = []
        for m in messages {
            let a = Announcement(title: m.subject, source: .outlook, from: m.from, date: m.date, body: String(m.body.prefix(4000)))
            let events = Moodle.mentionedDates(String(m.body.prefix(4000)), posted: m.date, source: .announcement, via: .mail).map { e -> CourseEvent in
                var e = e; e.origin = "✉︎ \(m.subject)\n\n\(m.body.prefix(3000))"; e.announcement = a.key; return e
            }
            if let i = Moodle.route("\(m.subject) \(m.body.prefix(600))", out) {
                out[i].announcements.append(a)
                out[i].events = ((out[i].events ?? []) + events).sorted { $0.date < $1.date }
            } else { general.append(a); generalEvents += events }
        }
        if !general.isEmpty || !generalEvents.isEmpty {
            if out.firstIndex(where: { $0.code == "GENERAL" }) == nil {
                out.append(Subject(id: "general", name: "MBZUAI · General", code: "GENERAL", hue: .slate, assessments: [], assignments: [],
                                   materials: [], announcements: [], events: []))
            }
            let g = out.firstIndex { $0.code == "GENERAL" }!
            out[g].announcements += general
            out[g].events = ((out[g].events ?? []) + generalEvents).sorted { $0.date < $1.date }
        }
        for i in out.indices { out[i].announcements.sort { $0.date > $1.date } }
        return out
    }
}

/// Mail progress, so each email is downloaded once: parsed messages, UIDs fetched but unparseable, and failed fetches.
struct MailStore: Codable, Sendable, Equatable {
    var messages: [SchoolMail.Message] = []
    var seen: Set<Int> = [] // fetched, but `parse` couldn't read it (no readable Date:): not fetched again
    var failures: [Int: Int] = [:] // UID → failed fetches; skipped from the 3rd on

    /// "49 school emails · 1 skipped (unreadable date)": the Connect sheet's mail line.
    var note: String { "\(messages.count) school emails" + (seen.isEmpty ? "" : " · \(seen.count) skipped (unreadable date)") }

    /// Keeps only what still matters: messages since `since`, and progress for UIDs the last search still returned.
    mutating func prune(since: Date, uids: Set<Int>) {
        messages = messages.filter { $0.date > since }
        seen.formIntersection(uids)
        failures = failures.filter { uids.contains($0.key) }
    }
}

extension MailStore {
    /// Before P4 mail.json was a plain array of messages; it still decodes, so 60 days of mail aren't downloaded again.
    init(from decoder: Decoder) throws {
        if let old = try? [SchoolMail.Message](from: decoder) { self.init(messages: old); return }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(messages: try c.decode([SchoolMail.Message].self, forKey: .messages),
                  seen: try c.decodeIfPresent(Set<Int>.self, forKey: .seen) ?? [],
                  failures: try c.decodeIfPresent([Int: Int].self, forKey: .failures) ?? [:])
    }
}

/// ~/Library/Application Support/AcademicAssistant/mail.json (owner-only).
enum MailCache {
    static let url = MoodleCache.url.deletingLastPathComponent().appending(path: "mail.json")
    static func load() -> MailStore { (try? JSONDecoder().decode(MailStore.self, from: Data(contentsOf: url))) ?? MailStore() }
    static func save(_ store: MailStore) throws { try writeOwnerOnly(JSONEncoder().encode(store), to: url) }
}

enum MailError: LocalizedError, Equatable {
    case badCredential, badLogin, server(String), timeout, closed, busy
    var errorDescription: String? {
        switch self {
        case .badCredential: "The address or app password is empty or contains a control character"
        case .badLogin: "Gmail rejected the sign-in (check the address and app password)"
        case .server(let word): "Gmail refused a request (\(word))"
        case .timeout: "Gmail didn't answer within 30 seconds"
        case .closed: "Gmail closed the connection"
        case .busy: "The mail connection was already running a command"
        }
    }
}

// MARK: - IMAP over TLS (in-process: /usr/bin/curl drops the message bytes of a custom FETCH reply)

/// Collects reply bytes and hands back one complete response: everything up to and including the line tagged `tag`
/// (`nil`: the first line, for the greeting). A literal (`{n}` then n bytes) is skipped by byte count, so a line inside
/// a mail body can't end the response early. Pure, so it can be fed any chunking.
struct IMAPReader {
    private var buffer: [UInt8] = []

    mutating func feed(_ chunk: Data) { buffer += chunk }

    mutating func response(tag: String?) -> Data? {
        let b = buffer, prefix = Array(((tag ?? "") + " ").utf8)
        var i = 0, afterLiteral = false
        while true {
            var eol = i
            while eol + 1 < b.count, !(b[eol] == 13 && b[eol + 1] == 10) { eol += 1 }
            guard eol + 1 < b.count else { return nil } // no complete line yet
            if eol > i, b[eol - 1] == UInt8(ascii: "}"), let open = b[i..<eol].lastIndex(of: UInt8(ascii: "{")),
               let n = Int(String(decoding: b[(open + 1)..<(eol - 1)], as: UTF8.self)) {
                i = eol + 2 + n // the literal, then the rest of this response line
                guard i <= b.count else { return nil }
                afterLiteral = true
                continue
            }
            if tag == nil || (!afterLiteral && b[i...].starts(with: prefix)) {
                buffer = Array(b[(eol + 2)...])
                return Data(b[..<(eol + 2)])
            }
            i = eol + 2
            afterLiteral = false
        }
    }
}

/// One IMAP connection to Gmail. Each command gets 30 s; cancelling the calling task closes the connection.
actor IMAPConnection {
    private let connection: NWConnection
    private var reader = IMAPReader(), count = 0
    private var busy = false // one command at a time: the actor is re-entrant at every await, replies would interleave
    private var dead = false // after a timeout or transport error the stream can't be trusted: further commands throw .closed

    init(host: String) { connection = NWConnection(host: NWEndpoint.Host(host), port: 993, using: .tls) } // system trust checks

    func open(address: String, password: String) async throws {
        guard SchoolMail.isSafeCredential(address) && SchoolMail.isSafeCredential(password) else { throw MailError.badCredential }
        guard !busy else { throw MailError.busy }
        busy = true
        defer { busy = false }
        connection.start(queue: .global())
        let greeting = try await deadline { try await self.read(tag: nil) }
        guard String(decoding: greeting.prefix(4), as: UTF8.self) == "* OK" else { throw MailError.server("greeting") }
        count += 1
        let tag = "A\(count)"
        let reply = try await deadline {
            try await self.send(SchoolMail.authenticateLine(tag: tag, address: address, password: password))
            return try await self.read(tag: tag)
        }
        try SchoolMail.status(reply, tag: tag, login: true)
        busy = false
        try await command("EXAMINE \"[Gmail]/All Mail\"") // read-only: nothing in it can be marked read
    }

    @discardableResult func command(_ text: String) async throws -> Data {
        guard !dead else { throw MailError.closed }
        guard !busy else { throw MailError.busy }
        busy = true
        defer { busy = false }
        count += 1
        let tag = "A\(count)"
        let reply = try await deadline {
            try await self.send("\(tag) \(text)")
            return try await self.read(tag: tag)
        }
        try SchoolMail.status(reply, tag: tag)
        return reply
    }

    /// UIDs of school mail since a date.
    func search(since: Date) async throws -> [Int] {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "d-MMM-yyyy"
        let reply = try await command("UID SEARCH SINCE \(f.string(from: since)) TO \"\(SchoolMail.domain)\"")
        return String(decoding: reply, as: UTF8.self).components(separatedBy: "\r\n").filter { $0.hasPrefix("* SEARCH") }
            .flatMap { $0.split(separator: " ").compactMap { Int($0) } }
    }

    func message(uid: Int) async throws -> SchoolMail.Message? {
        SchoolMail.literal(try await command(SchoolMail.fetchCommand(uid: uid))).flatMap { SchoolMail.parse(String(decoding: $0, as: UTF8.self), uid: uid) }
    }

    /// Read state of the UIDs the server reported (UID → has \Seen), for `--mail-check`.
    func seenFlags(_ uids: [Int]) async throws -> [Int: Bool] {
        guard !uids.isEmpty else { return [:] }
        let reply = try await command("UID FETCH \(uids.map(String.init).joined(separator: ",")) FLAGS")
        var out: [Int: Bool] = [:]
        for line in String(decoding: reply, as: UTF8.self).components(separatedBy: "\r\n") where line.hasPrefix("* ") {
            if let m = line.firstMatch(of: /UID (\d+)/), let uid = Int(m.1) { out[uid] = line.contains("\\Seen") }
        }
        return out
    }

    func close() async {
        _ = try? await command("LOGOUT")
        connection.cancel()
    }

    /// Closes the socket at once; any pending send or receive then fails.
    nonisolated func cancel() { connection.cancel() }

    private func read(tag: String?) async throws -> Data {
        while true {
            if let r = reader.response(tag: tag) { return r }
            reader.feed(try await receive())
        }
    }

    private nonisolated func send(_ line: String) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                connection.send(content: Data((line + "\r\n").utf8), completion: .contentProcessed { error in
                    if let error { c.resume(throwing: error) } else { c.resume() }
                })
            }
        } onCancel: { connection.cancel() } // a send stuck on a dead socket would otherwise never return
    }

    private nonisolated func receive() async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data, Error>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { data, _, _, error in
                    if let data, !data.isEmpty { c.resume(returning: data) }
                    else { c.resume(throwing: error ?? MailError.closed) }
                }
            }
        } onCancel: { connection.cancel() }
    }

    /// Runs `work` with a 30 s limit; on timeout the work is cancelled, which closes the connection.
    private func deadline<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async throws -> T {
        do {
            return try await deadlineGroup(work)
        } catch {
            dead = true
            throw error is MailError ? error : MailError.closed // a transport error is a lost connection too
        }
    }

    private func deadlineGroup<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask(operation: work)
            group.addTask { [connection] in
                try await Task.sleep(for: .seconds(30))
                connection.cancel() // unblocks the work child even if it ignores cancellation
                throw MailError.timeout
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}

// MARK: - `AcademicAssistant --mail-check`: live, counts only (run from the app bundle, which can read the Keychain item)

func runMailCheck() -> Never {
    guard let saved = Keychain.read(host: SchoolMail.account)?.split(separator: "\n", maxSplits: 1), saved.count == 2 else {
        print("no mail login stored"); exit(2)
    }
    let (address, password) = (String(saved[0]), String(saved[1]))
    Task.detached {
        do {
            let line = try await SchoolMail.session(address: address, password: password) { imap in
                let uids = try await imap.search(since: .now.addingTimeInterval(-60 * 86_400))
                let unreadBefore = Set(try await imap.seenFlags(uids).filter { !$0.value }.keys)
                let have = Set(MailCache.load().messages.map(\.uid))
                // Fetch everything not cached yet, plus up to 10 unread mails, so the check proves PEEK leaves them unread.
                let targets = Array(Set(uids.filter { !have.contains($0) }).union(unreadBefore.sorted().suffix(10))).sorted()
                var parsed = 0
                for uid in targets where try await imap.message(uid: uid) != nil { parsed += 1 }
                let after = try await imap.seenFlags(targets) // only UIDs the server reported again count
                let newlySeen = unreadBefore.intersection(targets).filter { after[$0] == true }.count
                // Re-fetch the 5 newest cached mails: the in-process reader must give what the old full fetch stored.
                let cached = MailCache.load().messages.sorted { $0.uid > $1.uid }.prefix(5)
                var same = 0
                for m in cached where try await imap.message(uid: m.uid) == m { same += 1 }
                return "searched \(uids.count) · unread \(unreadBefore.count) · fetched \(targets.count) (parsed \(parsed)) · newly seen \(newlySeen)"
                    + " · re-fetched \(cached.count) cached, identical \(same)"
            }
            print(line)
            exit(0)
        } catch {
            print("mail check failed: \(error.localizedDescription)")
            exit(1)
        }
    }
    dispatchMain()
}
