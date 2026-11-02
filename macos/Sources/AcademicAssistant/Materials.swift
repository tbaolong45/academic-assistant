import Foundation
import Synchronization
import PDFKit

/// Local copies of Moodle course files: ~/Documents/Academic Assistant/<Course>/<file>.
/// A material with several files (a Moodle folder) gets its own sub-folder. Files already on disk with the same size
/// and a modification date no older than Moodle's are skipped, so each sync only fetches what's new or changed.
enum MaterialStore {
    static let root = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Documents/Academic Assistant", directoryHint: .isDirectory)
    static let maxBytes = 300 * 1024 * 1024 // ponytail: skip huge files (lecture videos); raise if needed

    static func localURL(_ subject: Subject, _ material: Material, _ file: MaterialFile) -> URL {
        var dir = root.appending(path: safe(subject.name), directoryHint: .isDirectory)
        let clash = subject.materials.contains { m in m != material && (m.files ?? []).contains { safe($0.name) == safe(file.name) } }
        if (material.files?.count ?? 0) > 1 || clash { dir.append(path: safe(material.title), directoryHint: .isDirectory) }
        return dir.appending(path: safe(file.name))
    }

    /// On disk and current (F1i #1): not empty, the size Moodle reports, and modified no earlier than Moodle's
    /// `timemodified`. A download is stamped with that time; a file saved before F1i carries its (later) download time,
    /// so it still counts, while a same-size update on Moodle is fetched again.
    static func isSaved(_ url: URL, _ file: MaterialFile) -> Bool {
        guard let local = attributes(url), local.size > 0 else { return false }
        return (file.size == 0 || local.size == file.size) && (file.modified <= 0 || local.modified >= file.modified)
    }

    /// The local file's size and modification time (whole seconds), or nil when it isn't there.
    static func attributes(_ url: URL) -> (size: Int, modified: Int)? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)), let size = a[.size] as? Int else { return nil }
        return (size, Int(((a[.modificationDate] as? Date) ?? .distantPast).timeIntervalSince1970))
    }

    /// Every file of every material that should be on disk, in course order.
    static func wanted(_ subjects: [Subject]) -> [(file: MaterialFile, to: URL)] {
        subjects.flatMap { s in s.materials.flatMap { m in (m.files ?? []).map { (file: $0, to: localURL(s, m, $0)) } } }
            .filter { $0.file.size <= maxBytes }
    }

    /// Downloads whatever is missing. Returns how many files were fetched and short (token-free) failure notes.
    static func downloadMissing(_ subjects: [Subject], token: String) async -> (fetched: Int, failed: [String]) {
        var fetched = 0, failed: [String] = []
        for (file, to) in wanted(subjects) where !isSaved(to, file) {
            do { try await download(file, to: to, token: token); fetched += 1 }
            catch { failed.append("\(file.name): \(Moodle.redact(error.localizedDescription))") }
        }
        return (fetched, failed)
    }

    static func download(_ file: MaterialFile, to: URL, token: String) async throws {
        // The key goes only to the connected Moodle host, over https; the file only lands inside `root`.
        guard var c = URLComponents(string: file.url), c.scheme?.lowercased() == "https",
              let site = MoodleAccount.site.flatMap(URL.init(string:))?.host()?.lowercased(), c.host?.lowercased() == site,
              to.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") else { throw MoodleError.insecureSite }
        c.queryItems = (c.queryItems ?? []) + [.init(name: "token", value: token)]
        let (tmp, response) = try await session.download(from: c.url!)
        let http = response as? HTTPURLResponse
        // Moodle answers a bad token with a JSON error instead of the file.
        guard http?.statusCode == 200, !(http?.mimeType ?? "").contains("json") else {
            try? FileManager.default.removeItem(at: tmp)
            throw URLError(.badServerResponse)
        }
        try FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: to)
        try FileManager.default.moveItem(at: tmp, to: to)
        if file.modified > 0 { // Moodle's time, so `isSaved` sees a later update even when the size stays the same
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(file.modified))],
                                                  ofItemAtPath: to.path(percentEncoded: false))
        }
    }

    /// The cache key of the file on disk (F1i #2), so whatever is there is what gets parsed.
    private static func key(_ url: URL) -> PDFCache.Key? {
        attributes(url).map { PDFCache.Key(path: url.path(percentEncoded: false), size: $0.size, modified: $0.modified) }
    }

    /// Dates written in every downloaded PDF (syllabus, schedules, briefs, slides…), per subject id, and how many PDFs gave
    /// no text (not downloaded, over 300 MB, or unreadable): their dates may be missing (F1h #5). Slow: off the main thread.
    static func documentEvents(_ subjects: [Subject]) -> (dates: [String: [CourseEvent]], skipped: Int) {
        var out: [String: [CourseEvent]] = [:], skipped = 0
        for s in subjects {
            for m in s.materials {
                for f in m.files ?? [] where f.name.lowercased().hasSuffix(".pdf") {
                    let url = localURL(s, m, f)
                    let posted = PDFCache.posted(f.modified)
                    guard isSaved(url, f), let k = key(url), let entry = PDFCache.entry(k, posted: posted, load: { PDFDocument(url: url)?.string })
                    else { skipped += 1; continue }
                    out[s.id, default: []] += entry.found
                        // skip Moodle's download stamp ("…203.0.113.7 on Wed, 09 Sep 2026 06:48 UTC") and repeats across pages
                        .filter { ($0.detail ?? "").range(of: #"\b\d{1,3}(\.\d{1,3}){3}\b"#, options: .regularExpression) == nil }
                        // within ~9 months of now: chart axes ("07 Sep 35") and cited years (1979, 2025) aren't this semester
                        .filter { abs($0.date.timeIntervalSinceNow) < 270 * 86_400 }
                        .map { CourseEvent(title: $0.title, date: $0.date, source: .document, // the dated line itself; the file is named in detail
                                           detail: "From “\(m.title)” (\(f.name)): \($0.detail ?? "")", via: .pdf, posted: posted, ref: f.url) }
                }
            }
        }
        return (out.mapValues { evs in var seen = Set<String>(); return evs.filter { seen.insert("\($0.date.timeIntervalSince1970)|\($0.title)").inserted } }, skipped)
    }

    /// Passages in a subject's downloaded PDFs that talk about a deadline (a line with one of its words, and at least two of them
    /// within two lines), e.g. "Where do my TED TALK marks come from? / Script (8%) DUE WEEK (Deadline tbc)". Slow: off the main thread.
    static func mentions(of title: String, in s: Subject) -> [DocumentMention] {
        let k = keywords(title)
        guard !k.isEmpty else { return [] }
        var out: [DocumentMention] = []
        for m in s.materials {
            for f in m.files ?? [] where f.name.lowercased().hasSuffix(".pdf") {
                let url = localURL(s, m, f)
                guard isSaved(url, f), let fileKey = key(url),
                      let text = PDFCache.entry(fileKey, posted: PDFCache.posted(f.modified), load: { PDFDocument(url: url)?.string })?.text else { continue }
                let lines = text.components(separatedBy: .newlines)
                var i = 0
                while i < lines.count {
                    let window = Array(lines[max(0, i - 2)...min(lines.count - 1, i + 2)])
                    if !k.isDisjoint(with: words(lines[i])), k.intersection(window.flatMap(words)).count >= min(2, k.count) {
                        out.append(DocumentMention(id: "\(f.url)#\(i)", file: m.title, text: window.joined(separator: "\n")))
                        i += 3
                    } else { i += 1 }
                }
            }
        }
        return Array(out.prefix(8)) // ponytail: first 8 passages; a slide deck that repeats the title on every page would flood it
    }

    private static let session = URLSession(configuration: .ephemeral) // URLs carry the token: never cached to disk

    /// File-system-safe name ("/" and ":" replaced, trimmed).
    static func safe(_ name: String) -> String {
        var s = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix(".") { s.removeFirst() } // ".." / ".zshrc" must not climb out of or hide in the folder
        return s.isEmpty ? "Untitled" : String(s.prefix(120))
    }
}

struct DocumentMention: Identifiable, Sendable { let id: String, file: String, text: String }

/// Each downloaded PDF's text and dates, read once per app run and again only when Moodle reports a new size or modified
/// time (B7, §5.4). In memory on purpose: course-PDF text on disk would be a new sensitive file for little gain.
enum PDFCache {
    struct Key: Hashable, Sendable { let path: String, size: Int, modified: Int }
    struct Entry: Sendable {
        let text: String
        let found: [CourseEvent] // `mentionedDates` of the text, before the per-run filters
    }
    /// The file's Moodle modified time, or now when Moodle gave none.
    static func posted(_ modified: Int) -> Date { modified > 0 ? Date(timeIntervalSince1970: Double(modified)) : .now }
    private static let entries = Mutex<[String: (key: Key, entry: Entry)]>([:]) // by path: a changed file replaces its entry
    // ponytail: one lock for every parse, so a second caller waits for the first instead of parsing the same PDF again
    // (F1i #4); parses of different files queue too. Per-key locks if the preview's wait ever shows.
    private static let parsing = Mutex(())

    /// The cached entry for `key`, else `load()` (the file read) parsed and stored; nil when the file has no text.
    /// `posted` dates the text's relative years (Moodle's modified time); by default the key's.
    static func entry(_ key: Key, posted when: Date? = nil, load: () -> String?) -> Entry? {
        func hit() -> Entry? { entries.withLock { $0[key.path] }.flatMap { $0.key == key ? $0.entry : nil } }
        if let e = hit() { return e }
        return parsing.withLock { _ in
            if let e = hit() { return e } // parsed by the caller we waited for
            guard let text = load() else { return nil }
            let entry = Entry(text: text, found: Moodle.mentionedDates(text, posted: when ?? posted(key.modified), source: .document, strict: true))
            entries.withLock { $0[key.path] = (key, entry) }
            return entry
        }
    }
}
