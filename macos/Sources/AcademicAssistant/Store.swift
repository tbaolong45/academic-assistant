import Combine
import Foundation

/// Every source of one sync → the subjects the app shows (pure). Course pages first, then PDF dates, Outlook and mail
/// on top, then Jev's labels and the AI titles.
func normalize(moodle: [Subject], outlook: [OutlookCalendar.Item], mail: [SchoolMail.Message], docs: [String: [CourseEvent]],
               known: [String: Jev.Answer], titles: [String: Summary]) -> [Subject] {
    summarized(labeled(SchoolMail.merge(mail, into: OutlookCalendar.merge(outlook, into: withPDFDates(moodle, docs))), known), titles)
}

/// The app's data. Sample courses until Moodle is connected; then `publish()` builds `subjects` from the latest
/// Moodle sync, PDF dates, Outlook events and school mail, once per sync.
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
    private var syncTask: Task<Void, Never>? // a sync started with "Sync now"
    /// Bumped at every sync start, connect and disconnect: a result from an older generation is dropped, so a sync
    /// that finishes after Disconnect can't merge real mail into the sample data.
    private var generation = 0
    private var base: [Subject] = [] // the last Moodle sync (or its cache)
    private var docs: [String: [CourseEvent]] = [:] // dates in downloaded PDFs, by subject id
    @Published private(set) var hasJevKey = Keychain.read(host: Jev.account) != nil
    @Published private(set) var classifierNote: String? // progress or the last classifier error (never the key)
    private var known = KindCache.load() // Jev answers by text hash
    private var classifying = false
    private var classifyTask: Task<Void, Never>?, summarizeTask: Task<Void, Never>? // cancelled by disconnect
    private var mailFetch: Task<MailStore?, Never>? // the one mail fetch running: a second caller waits for it
    @Published private(set) var hasDeepSeekKey = Keychain.read(host: DeepSeek.account) != nil
    @Published private(set) var summaryNote: String?
    @Published private(set) var hasOutlookLink = Keychain.read(host: OutlookCalendar.account) != nil
    @Published private(set) var outlookNote: String?
    @Published private(set) var calendarItems: [OutlookCalendar.Item] = [] // everything in the Outlook calendar, for the Calendar page
    @Published private(set) var hasMail = Keychain.read(host: SchoolMail.account) != nil
    @Published private(set) var mailNote: String?
    @Published private(set) var cacheNote: String? // a local cache that couldn't be written or made private
    private var mail = MailCache.load() // forwarded school mail by Gmail UID, plus download progress
    private var titles = SummaryCache.load() // DeepSeek titles + Jev's checks, by source hash
    private var summarizing = false

    var lastSynced: Date? { if case .live(let d) = source { d } else { nil } }

    /// With a stored key: open on the last synced data (works offline), then sync now and every 15 minutes.
    init() {
        guard MoodleAccount.credentials() != nil else { return }
        Notifier.requestPermission()
        isConnected = true
        let cache = MoodleCache.load()
        if let cache { use(cache); publish() }
        board = boardItems(subjects) // didSet doesn't run for assignments made directly in init
        startAutoSync(scanFirst: cache != nil) // no cache = sample data on screen: nothing to scan or send to Jev
    }

    static func isCurrent(generation: Int, current: Int) -> Bool { generation == current }

    func subject(_ id: String) -> Subject? { subjects.first { $0.id == id } }

    /// Runs a cache write; a failure becomes `cacheNote` (shown in Connect) instead of disappearing.
    private func save(_ write: () throws -> Void) {
        do { try write(); cacheNote = nil } catch { cacheNote = "Local cache: \(error.localizedDescription)" }
    }

    private func use(_ s: MoodleSync) {
        base = s.subjects
        source = .live(synced: s.synced)
        syncError = nil
        warnings = s.warnings
        siteName = s.siteName
    }

    /// The one place `subjects` is rebuilt while connected.
    private func publish() {
        guard isConnected, lastSynced != nil else { return } // sample data stays sample
        subjects = normalize(moodle: base, outlook: calendarItems, mail: mail.messages, docs: docs, known: known, titles: titles)
    }

    private func startAutoSync(scanFirst: Bool = false) {
        autoSync?.cancel()
        let gen = generation
        autoSync = Task { [weak self] in
            if scanFirst { await self?.scanDocuments(gen) } // the cache's PDF dates, before the first sync bumps the generation
            while !Task.isCancelled {
                await self?.sync()
                try? await Task.sleep(for: .seconds(5 * 60)) // ponytail: 5-minute poll; Moodle has no push for students
            }
        }
    }

    func syncNow() { syncTask = Task { await sync() } }

    /// Moodle, Outlook and mail load side by side and are published once, when all are in. Downloads and the PDF scan
    /// that follow publish once more.
    func sync() async {
        guard !syncing, let creds = MoodleAccount.credentials() else { return }
        generation += 1
        let gen = generation
        syncing = true
        defer { if Self.isCurrent(generation: gen, current: generation) { syncing = false } } // disconnect already reset it
        async let outlook = fetchOutlook()
        async let newMail = fetchMail()
        let moodle: Result<MoodleSync, Error>
        do { moodle = .success(try await Moodle(site: creds.site, token: creds.token).sync()) } catch { moodle = .failure(error) }
        let (items, fetched) = await (outlook, newMail)
        guard Self.isCurrent(generation: gen, current: generation) else { return } // disconnected meanwhile
        if let items { calendarItems = items }
        if let fetched { mail = fetched }
        switch moodle {
        case .success(let result):
            let previous = lastSynced == nil ? nil : subjects // no "news" on the very first sync
            use(result)
            save { try MoodleCache.save(result) }
            publish()
            if let previous, result.warnings.isEmpty, !lastSyncPartial { Notifier.post(Notifier.changes(old: previous, new: result.subjects)) }
            lastSyncPartial = !result.warnings.isEmpty
            await downloadMaterials(token: creds.token)
            await scanDocuments(gen)
        case .failure(let error):
            publish() // Outlook or mail may still be new
            if !Task.isCancelled { syncError = error.localizedDescription }
        }
    }

    /// After each sync: fetch course files that aren't on disk yet into ~/Documents/Academic Assistant.
    private func downloadMaterials(token: String) async {
        downloading = true
        defer { downloading = false; filesVersion += 1 }
        let r = await MaterialStore.downloadMissing(subjects, token: token)
        downloadNote = r.failed.isEmpty ? (r.fetched > 0 ? "\(r.fetched) new file\(r.fetched == 1 ? "" : "s") saved" : nil)
                                        : "\(r.fetched) saved, \(r.failed.count) failed"
    }

    /// Dates found in the downloaded syllabus/schedule PDFs (replacing older ones), then Jev and DeepSeek on anything new.
    private func scanDocuments(_ gen: Int) async {
        let current = subjects
        let found = await Task.detached(priority: .utility) { MaterialStore.documentEvents(current) }.value
        guard Self.isCurrent(generation: gen, current: generation) else { return }
        docs = found
        publish()
        classify() // last steps of every sync: everything new is on hand now
        summarize()
    }

    /// Sends every announcement and dated item Jev hasn't seen yet (text only), then labels them.
    private func classify() {
        guard isConnected, lastSynced != nil, !classifying, hasJevKey, let key = Keychain.read(host: Jev.account) else { return } // never sample data
        let texts = Set(subjects.flatMap { s in s.announcements.map(\.classifyText) + (s.events ?? []).map(\.classifyText) })
            .filter { known[Jev.id($0)] == nil }
        guard !texts.isEmpty else { return }
        classifying = true
        let gen = generation
        classifyTask = Task {
            defer { classifying = false }
            var done = 0, failure: String?
            for text in texts.prefix(300) where !Task.isCancelled { // ponytail: one at a time, 300 per sync; parallelise if the first run feels slow
                classifierNote = "classifying \(done + 1) of \(min(texts.count, 300))…"
                do { known[Jev.id(text)] = try await Jev.classify(text, key: key); done += 1 }
                catch { failure = error.localizedDescription; break }
            }
            save { try KindCache.save(known) } // labels are keyed by text, so keeping them is always safe
            // A newer sync or a disconnect happened meanwhile: don't publish into it (the next publish picks the labels up).
            guard Self.isCurrent(generation: gen, current: generation), !Task.isCancelled else { return }
            publish()
            classifierNote = failure.map { "stopped after \(done): \($0)" } ?? "\(known.count) items classified"
            classifying = false // before summarize(), which won't start while this is set (the defer runs too late)
            summarize() // board items are known now
        }
    }

    /// Titles for dated items on the board from a week ago to 4 months ahead: Jev picks the parts, DeepSeek writes, Jev checks.
    private func summarize() {
        guard isConnected, lastSynced != nil, !summarizing, !classifying, let jev = Keychain.read(host: Jev.account), let ds = Keychain.read(host: DeepSeek.account) else { return }
        let window = Date.now.addingTimeInterval(-7 * 86_400)...Date.now.addingTimeInterval(120 * 86_400)
        var seen = Set<String>()
        let todo = subjects.flatMap { s in (s.events ?? []).map { (course: s.name, event: $0) } }
            .filter { window.contains($0.event.date) && $0.event.kind?.isDated != false && titles[Summarizer.id($0.event)] == nil
                && seen.insert(Summarizer.id($0.event)).inserted }
        guard !todo.isEmpty else { return }
        summarizing = true
        let gen = generation
        summarizeTask = Task {
            defer { summarizing = false }
            var done = 0, rejected = 0, failure: String?
            for (course, e) in todo.prefix(80) where !Task.isCancelled { // ponytail: 80 items (≈240 calls) per sync, one at a time
                summaryNote = "summarizing \(done + 1) of \(min(todo.count, 80))…"
                do {
                    let s = try await Summarizer.summarize(e, course: course, jevKey: jev, deepSeekKey: ds)
                    titles[Summarizer.id(e)] = s
                    if !s.accepted { rejected += 1 }
                    done += 1
                    if done % 10 == 0 { save { try SummaryCache.save(titles) } }
                } catch { failure = error.localizedDescription; break }
            }
            // Prune only against the subjects this run started from: after a disconnect `subjects` is sample data, and
            // pruning against it would delete every paid title. Unpruned titles are still saved.
            guard Self.isCurrent(generation: gen, current: generation), !Task.isCancelled else {
                save { try SummaryCache.save(titles) }
                return
            }
            titles = Summarizer.prune(titles, to: subjects) // `subjects` is always a full publish, never a partial one
            save { try SummaryCache.save(titles) }
            publish()
            summaryNote = failure.map { "stopped after \(done): \($0)" }
                ?? "\(titles.count) titles · \(rejected) of the new ones failed Jev's check and kept their plain headline"
        }
    }

    /// The Outlook calendar from its published ICS link; nil when no link is set or the fetch failed (the last items stay).
    private func fetchOutlook() async -> [OutlookCalendar.Item]? {
        guard let link = Keychain.read(host: OutlookCalendar.account) else { return nil }
        do {
            let items = try await OutlookCalendar.fetch(link)
            outlookNote = nil
            return items
        } catch {
            outlookNote = "Outlook calendar: \(error.localizedDescription)" // never the link itself
            return nil
        }
    }

    /// School mail forwarded to Gmail: new messages from the last 60 days are downloaded once (by UID) and notified.
    /// nil when no Gmail login is set or the session failed (the last mail stays).
    private func fetchMail() async -> MailStore? {
        // A set-mail check during a sync's fetch waits for it: one session only. A waiter's own cancellation doesn't reach
        // the shared fetch (a plain `.value`); only the owner below, or disconnect, cancels it.
        if let running = mailFetch { return await running.value }
        let task = Task { await fetchMailNow() }
        mailFetch = task
        defer { mailFetch = nil }
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    private func fetchMailNow() async -> MailStore? {
        guard let saved = Keychain.read(host: SchoolMail.account)?.split(separator: "\n", maxSplits: 1), saved.count == 2 else { return nil }
        let (address, password) = (String(saved[0]), String(saved[1]))
        let since = Date.now.addingTimeInterval(-60 * 86_400)
        do {
            let start = mail
            let (updated, writeError) = try await SchoolMail.session(address: address, password: password) { imap in // one login per sync
                var store = start, writeError: String?
                let uids = try await imap.search(since: since)
                store.prune(since: since, uids: Set(uids))
                let todo = SchoolMail.toFetch(uids: uids, have: Set(store.messages.map(\.uid)), seen: store.seen, failures: store.failures)
                // Saved after every message, so progress survives a stall or a quit (a write error shows after the loop).
                await SchoolMail.download(Array(todo.suffix(200)), into: &store, fetch: { try await imap.message(uid: $0) },
                                          save: { s in
                    do { try MailCache.save(s) } catch { writeError = writeError ?? error.localizedDescription } // the first one
                })
                return (store, writeError)
            }
            let known = Set(start.messages.map(\.uid))
            let fresh = updated.messages.filter { !known.contains($0.uid) }
            if !start.messages.isEmpty { Notifier.post(fresh.map { (title: "✉︎ \($0.from)", body: $0.subject) }) } // not on the first download
            save { try MailCache.save(updated) }
            if cacheNote == nil, let writeError { cacheNote = "Local cache: \(writeError)" }
            mailNote = updated.note
            return updated
        } catch {
            mailNote = error.localizedDescription // never the password
            return nil
        }
    }

    /// Checks the Gmail login (sign in + open All Mail) before keeping it.
    func setMail(address raw: String, password rawPassword: String) async throws {
        let address = raw.trimmingCharacters(in: .whitespacesAndNewlines), password = rawPassword.replacingOccurrences(of: " ", with: "")
        try await SchoolMail.session(address: address, password: password) { _ in }
        guard Keychain.save("\(address)\n\(password)", host: SchoolMail.account) else { throw MoodleError.keychain }
        hasMail = true
        if let fetched = await fetchMail() { mail = fetched }
        publish()
        classify()
    }

    func removeMail() {
        Keychain.delete(host: SchoolMail.account)
        hasMail = false
        mail = MailStore()
        save { try MailCache.save(MailStore()) }
        publish()
    }

    /// Checks the link returns a calendar before keeping it.
    func setOutlookLink(_ raw: String) async throws {
        let link = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = try await OutlookCalendar.fetch(link)
        guard Keychain.save(link, host: OutlookCalendar.account) else { throw MoodleError.keychain }
        hasOutlookLink = true
        calendarItems = items
        outlookNote = nil
        publish()
        classify()
    }

    func removeOutlookLink() {
        Keychain.delete(host: OutlookCalendar.account)
        hasOutlookLink = false
        calendarItems = []
        publish()
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
        generation += 1
        Notifier.requestPermission()
        startAutoSync()
    }

    /// Deletes the key and cache and goes back to sample data.
    func disconnect() {
        generation += 1 // a sync or PDF scan still running is dropped when it returns
        autoSync?.cancel()
        autoSync = nil
        syncTask?.cancel()
        syncTask = nil
        classifyTask?.cancel()
        summarizeTask?.cancel()
        mailFetch?.cancel()
        summaryNote = nil
        classifierNote = nil
        syncing = false // a cancelled sync can't leave "Syncing…" up or Sync now disabled
        downloading = false
        mailNote = nil
        outlookNote = nil
        downloadNote = nil
        base = []
        docs = [:]
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
