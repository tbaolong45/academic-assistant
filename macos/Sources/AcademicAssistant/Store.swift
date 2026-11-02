import Combine
import Foundation

/// The app's data. Sample courses until a source (Moodle, then Microsoft) is connected; connectors call `setLive`.
@MainActor final class Store: ObservableObject {
    enum Source: Equatable { case sample, live(synced: Date) }

    @Published private(set) var subjects: [Subject] = Subject.all { didSet { board = boardItems(subjects) } }
    /// Every deadline, computed once per change of `subjects` (views slice it by date instead of rebuilding it per redraw).
    @Published private(set) var board: [BoardItem] = boardItems(Subject.all)
    @Published private(set) var source: Source = .sample
    @Published var syncError: String?
    private var lastSyncPartial = false // a sync with warnings may have missed items: don't diff against it
    @Published private(set) var warnings: [String] = [] // non-fatal sync notes (a course part skipped, >5 courses)
    @Published private(set) var syncing = false
    @Published private(set) var isConnected = false
    @Published private(set) var siteName: String?
    @Published private(set) var downloading = false
    @Published private(set) var downloadNote: String? // e.g. "3 new files" / failures
    @Published private(set) var filesVersion = 0 // bumps after downloads so file rows re-check what's on disk
    private var autoSync: Task<Void, Never>?
    @Published private(set) var hasJevKey = Keychain.read(host: Jev.account) != nil
    @Published private(set) var classifierNote: String? // progress or the last classifier error (never the key)
    private var known = KindCache.load() // Jev answers by text hash
    private var classifying = false
    @Published private(set) var hasDeepSeekKey = Keychain.read(host: DeepSeek.account) != nil
    @Published private(set) var summaryNote: String?
    @Published private(set) var hasOutlookLink = Keychain.read(host: OutlookCalendar.account) != nil
    @Published private(set) var outlookNote: String?
    @Published private(set) var calendarItems: [OutlookCalendar.Item] = [] // everything in the Outlook calendar, for the Calendar page
    @Published private(set) var hasMail = Keychain.read(host: SchoolMail.account) != nil
    @Published private(set) var mailNote: String?
    private var mail = MailCache.load() // forwarded school mail, by Gmail UID
    private var titles = SummaryCache.load() // DeepSeek titles + Jev's checks, by source hash
    private var summarizing = false

    var lastSynced: Date? { if case .live(let d) = source { d } else { nil } }

    /// With a stored key: open on the last synced data (works offline), then sync now and every 15 minutes.
    init() {
        guard MoodleAccount.credentials() != nil else { return }
        Notifier.requestPermission()
        isConnected = true
        if let cache = MoodleCache.load() { apply(cache); subjects = SchoolMail.merge(mail, into: subjects); addDocumentDates() }
        board = boardItems(subjects) // didSet doesn't run for assignments made directly in init
        startAutoSync()
    }

    func subject(_ id: String) -> Subject? { subjects.first { $0.id == id } }

    func setLive(_ subjects: [Subject], synced: Date = .now) {
        self.subjects = subjects
        source = .live(synced: synced)
        syncError = nil
    }

    private func apply(_ s: MoodleSync) {
        let docs = Dictionary(subjects.map { ($0.id, ($0.events ?? []).filter { $0.source == .document }) }, uniquingKeysWith: { a, _ in a })
        setLive(labeled(s.subjects.map { n in
            var n = n
            n.events = ((n.events ?? []) + (docs[n.id] ?? [])).sorted { $0.date < $1.date }
            return n
        }, known), synced: s.synced)
        subjects = summarized(subjects, titles)
        warnings = s.warnings
        siteName = s.siteName
    }

    private func startAutoSync() {
        autoSync?.cancel()
        autoSync = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sync()
                try? await Task.sleep(for: .seconds(5 * 60)) // ponytail: 5-minute poll; Moodle has no push for students
            }
        }
    }

    func syncNow() { Task { await sync() } }

    func sync() async {
        guard !syncing, let creds = MoodleAccount.credentials() else { return }
        syncing = true
        defer { syncing = false }
        do {
            let result = try await Moodle(site: creds.site, token: creds.token).sync()
            guard isConnected else { return } // disconnected meanwhile
            let previous = lastSynced == nil ? nil : subjects // no "news" on the very first sync
            apply(result)
            MoodleCache.save(result)
            await addOutlookCalendar()
            await addSchoolMail()
            if let previous, result.warnings.isEmpty, !lastSyncPartial { Notifier.post(Notifier.changes(old: previous, new: result.subjects)) }
            lastSyncPartial = !result.warnings.isEmpty
            await downloadMaterials(token: creds.token)
        } catch {
            if isConnected && !Task.isCancelled { syncError = error.localizedDescription }
        }
    }

    /// After each sync: fetch course files that aren't on disk yet into ~/Documents/Academic Assistant.
    private func downloadMaterials(token: String) async {
        downloading = true
        defer { downloading = false; filesVersion += 1 }
        let r = await MaterialStore.downloadMissing(subjects, token: token)
        downloadNote = r.failed.isEmpty ? (r.fetched > 0 ? "\(r.fetched) new file\(r.fetched == 1 ? "" : "s") saved" : nil)
                                        : "\(r.fetched) saved, \(r.failed.count) failed"
        addDocumentDates()
    }

    /// Adds dates found in the downloaded syllabus/schedule PDFs to each subject's events (replacing older ones).
    private func addDocumentDates() {
        let current = subjects
        Task {
            let found = await Task.detached(priority: .utility) { MaterialStore.documentEvents(current) }.value
            applyDocumentDates(found)
        }
    }

    private func applyDocumentDates(_ found: [String: [CourseEvent]]) {
        subjects = subjects.map { s in
            var s = s
            s.events = ((s.events ?? []).filter { $0.source != .document } + (found[s.id] ?? [])).sorted { $0.date < $1.date }
            return s
        }
        subjects = summarized(labeled(subjects, known), titles)
        classify() // last steps of every sync: everything new is on hand now
        summarize()
    }

    /// Sends every announcement and dated item Jev hasn't seen yet (text only), then labels them.
    private func classify() {
        guard !classifying, hasJevKey, let key = Keychain.read(host: Jev.account) else { return }
        let texts = Set(subjects.flatMap { s in s.announcements.map(\.classifyText) + (s.events ?? []).map(\.classifyText) })
            .filter { known[Jev.id($0)] == nil }
        guard !texts.isEmpty else { return }
        classifying = true
        Task {
            defer { classifying = false }
            var done = 0, failure: String?
            for text in texts.prefix(300) { // ponytail: one at a time, 300 per sync; parallelise if the first run feels slow
                classifierNote = "classifying \(done + 1) of \(min(texts.count, 300))…"
                do { known[Jev.id(text)] = try await Jev.classify(text, key: key); done += 1 }
                catch { failure = error.localizedDescription; break }
            }
            KindCache.save(known)
            subjects = summarized(labeled(subjects, known), titles)
            classifierNote = failure.map { "stopped after \(done): \($0)" } ?? "\(known.count) items classified"
            summarize() // board items are known now
        }
    }

    /// Titles for dated items on the board from a week ago to 4 months ahead: Jev picks the parts, DeepSeek writes, Jev checks.
    private func summarize() {
        guard !summarizing, !classifying, let jev = Keychain.read(host: Jev.account), let ds = Keychain.read(host: DeepSeek.account) else { return }
        let window = Date.now.addingTimeInterval(-7 * 86_400)...Date.now.addingTimeInterval(120 * 86_400)
        var seen = Set<String>()
        let todo = subjects.flatMap { s in (s.events ?? []).map { (course: s.name, event: $0) } }
            .filter { window.contains($0.event.date) && $0.event.kind?.isDated != false && titles[Summarizer.id($0.event)] == nil
                && seen.insert(Summarizer.id($0.event)).inserted }
        guard !todo.isEmpty else { return }
        summarizing = true
        Task {
            defer { summarizing = false }
            var done = 0, rejected = 0, failure: String?
            for (course, e) in todo.prefix(80) { // ponytail: 80 items (≈240 calls) per sync, one at a time
                summaryNote = "summarizing \(done + 1) of \(min(todo.count, 80))…"
                do {
                    let s = try await Summarizer.summarize(e, course: course, jevKey: jev, deepSeekKey: ds)
                    titles[Summarizer.id(e)] = s
                    if !s.accepted { rejected += 1 }
                    done += 1
                    if done % 10 == 0 { SummaryCache.save(titles) }
                } catch { failure = error.localizedDescription; break }
            }
            let live = Set(subjects.flatMap { $0.events ?? [] }.map(Summarizer.id))
            titles = titles.filter { live.contains($0.key) } // drop titles of items that no longer exist
            SummaryCache.save(titles)
            subjects = summarized(subjects, titles)
            summaryNote = failure.map { "stopped after \(done): \($0)" }
                ?? "\(titles.count) titles · \(rejected) of the new ones failed Jev's check and kept their plain headline"
        }
    }

    /// One-off Outlook Calendar events (talks, keynotes, changes) from the published ICS link, labelled from the caches.
    private func addOutlookCalendar() async {
        guard let link = Keychain.read(host: OutlookCalendar.account) else { return }
        do {
            calendarItems = try await OutlookCalendar.fetch(link)
            subjects = summarized(labeled(OutlookCalendar.merge(calendarItems, into: subjects), known), titles)
            outlookNote = nil
        }
        catch { outlookNote = "Outlook calendar: \(error.localizedDescription)" } // never the link itself
    }

    /// School mail forwarded to Gmail: new messages from the last 60 days are downloaded once (by UID) and notified.
    private func addSchoolMail() async {
        guard let saved = Keychain.read(host: SchoolMail.account)?.split(separator: "\n", maxSplits: 1), saved.count == 2 else { return }
        let (address, password) = (String(saved[0]), String(saved[1]))
        let since = Date.now.addingTimeInterval(-60 * 86_400)
        do {
            let have = Set(mail.map(\.uid))
            let fresh = try await SchoolMail.session(address: address, password: password) { imap in // one login per sync
                var out: [SchoolMail.Message] = []
                for uid in try await imap.search(since: since).filter({ !have.contains($0) }).suffix(200) {
                    if let m = try await imap.message(uid: uid) { out.append(m) }
                }
                return out
            }
            if !have.isEmpty { Notifier.post(fresh.map { (title: "✉︎ \($0.from)", body: $0.subject) }) } // not on the first download
            mail = (mail + fresh).filter { $0.date > since }
            MailCache.save(mail)
            mailNote = "\(mail.count) school emails"
        } catch { mailNote = error.localizedDescription } // never the password
        subjects = summarized(labeled(SchoolMail.merge(mail, into: subjects), known), titles)
    }

    /// Checks the Gmail login (sign in + open All Mail) before keeping it.
    func setMail(address raw: String, password rawPassword: String) async throws {
        let address = raw.trimmingCharacters(in: .whitespacesAndNewlines), password = rawPassword.replacingOccurrences(of: " ", with: "")
        try await SchoolMail.session(address: address, password: password) { _ in }
        guard Keychain.save("\(address)\n\(password)", host: SchoolMail.account) else { throw MoodleError.keychain }
        hasMail = true
        await addSchoolMail()
        classify()
    }

    func removeMail() {
        Keychain.delete(host: SchoolMail.account)
        hasMail = false
        mail = []
        MailCache.save([])
        subjects = SchoolMail.merge([], into: subjects)
    }

    /// Checks the link returns a calendar before keeping it.
    func setOutlookLink(_ raw: String) async throws {
        let link = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await OutlookCalendar.fetch(link)
        guard Keychain.save(link, host: OutlookCalendar.account) else { throw MoodleError.keychain }
        hasOutlookLink = true
        await addOutlookCalendar()
        classify()
    }

    func removeOutlookLink() {
        Keychain.delete(host: OutlookCalendar.account)
        hasOutlookLink = false
        calendarItems = []
        subjects = OutlookCalendar.merge([], into: subjects)
    }

    /// Checks the DeepSeek key with one real call before keeping it.
    func setDeepSeekKey(_ raw: String) async throws {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await DeepSeek.title(parts: ["Quiz 2 is next Tuesday in class."], date: "Tue 3 Nov", key: key)
        guard Keychain.save(key, host: DeepSeek.account) else { throw MoodleError.keychain }
        hasDeepSeekKey = true
        summarize()
    }

    func removeDeepSeekKey() {
        Keychain.delete(host: DeepSeek.account)
        hasDeepSeekKey = false
        summaryNote = nil
    }

    /// Checks the key with one real call before keeping it.
    func setJevKey(_ raw: String) async throws {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await Jev.classify("Quiz 2 is next Tuesday in class.", key: key)
        guard Keychain.save(key, host: Jev.account) else { throw MoodleError.keychain }
        hasJevKey = true
        classifierNote = nil
        classify()
    }

    func removeJevKey() {
        Keychain.delete(host: Jev.account)
        hasJevKey = false
        classifierNote = nil
    }

    /// Makes sure one file is on disk (downloads it now if needed) and returns where it is.
    func localFile(_ subject: Subject, _ material: Material, _ file: MaterialFile) async throws -> URL {
        let to = MaterialStore.localURL(subject, material, file)
        if MaterialStore.isSaved(to, file) { return to }
        guard let creds = MoodleAccount.credentials() else { throw MoodleError.keychain }
        try await MaterialStore.download(file, to: to, token: creds.token)
        filesVersion += 1
        return to
    }

    /// Tests the key with core_webservice_get_site_info, stores it in the Keychain, then starts syncing.
    func connect(site text: String, key: String) async throws {
        let site = try Moodle.siteURL(text)
        let token = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let info = try await Moodle(site: site, token: token).siteInfo()
        guard let host = site.host(), Keychain.save(token, host: host) else { throw MoodleError.keychain }
        MoodleAccount.site = site.absoluteString
        siteName = info.sitename ?? host
        syncError = nil
        isConnected = true
        Notifier.requestPermission()
        startAutoSync()
    }

    /// Deletes the key and cache and goes back to sample data.
    func disconnect() {
        autoSync?.cancel()
        autoSync = nil
        if let s = MoodleAccount.site, let host = try? Moodle.siteURL(s).host() { Keychain.delete(host: host) }
        MoodleCache.delete()
        isConnected = false
        siteName = nil
        warnings = []
        syncError = nil
        subjects = Subject.all
        source = .sample
    }
}
