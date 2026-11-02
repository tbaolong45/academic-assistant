import AppKit
import SwiftUI

private let alarm = Color(hex: "ff6b6b") // sync errors only

/// Connect / manage the Moodle link. The key is typed into a SecureField, sent once to test it, then lives in the Keychain.
struct ConnectView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @Local private var site = MoodleAccount.site ?? MoodleAccount.defaultSite
    @Local private var key = ""
    @Local private var busy = false
    @Local private var message: String?
    @Local private var sso = MoodleSSO()
    @Local private var jevKey = ""
    @Local private var jevBusy = false
    @Local private var jevError: String?
    @Local private var dsKey = ""
    @Local private var dsBusy = false
    @Local private var dsError: String?
    @Local private var icsLink = ""
    @Local private var icsBusy = false
    @Local private var icsError: String?
    @Local private var gmail = ""
    @Local private var appPassword = ""
    @Local private var mailBusy = false
    @Local private var mailError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                TypewriterTitle(text: "moodle link")
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if store.isConnected { connected } else { form }
            classifier
        }
        .padding(24)
        .frame(width: 520)
        .background(Tech.panel)
    }

    @ViewBuilder private var form: some View {
        SectionLabel("site")
        HStack(spacing: 8) {
            TextField("site", text: $site, prompt: Text("https://…").foregroundStyle(Tech.text3))
                .textFieldStyle(.plain).padding(8).techPanel(radius: 6)
            Button("Open Security keys page") { openKeysPage() }
        }

        SectionLabel("sign in")
        Text("Opens a private sign-in window. Log in with your university account; the app receives its key automatically.")
            .font(.callout).foregroundStyle(Tech.text2)
        HStack {
            Button(busy ? "Waiting for sign-in…" : "Sign in with university SSO", action: signInSSO)
                .keyboardShortcut(.defaultAction).disabled(busy)
            if busy { ProgressView().controlSize(.small) }
        }

        SectionLabel("or paste a key")
        VStack(alignment: .leading, spacing: 6) {
            step(1, "Open the Security keys page (button above)")
            step(2, "Copy the key in the “Moodle mobile web service” row")
            step(3, "Paste it here and press Connect")
        }

        SectionLabel("key")
        SecureField("key", text: $key, prompt: Text("paste key").foregroundStyle(Tech.text3))
            .textFieldStyle(.plain).padding(8).techPanel(active: !key.isEmpty, radius: 6)
            .onSubmit(connect)

        if let message { Text(message).font(.caption).foregroundStyle(alarm) }

        HStack {
            Spacer()
            if busy { ProgressView().controlSize(.small) }
            Button(busy ? "Connecting…" : "Connect", action: connect)
                .disabled(busy || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder private var connected: some View {
        SectionLabel("status")
        VStack(alignment: .leading, spacing: 6) {
            Text("● CONNECTED · \(store.siteName ?? site)").foregroundStyle(Tech.neon)
            if store.syncing && store.lastSynced == nil {
                Text("first sync running…").foregroundStyle(Tech.text2)
            } else if store.lastSynced != nil {
                Text("\(store.subjects.count) courses found: \(store.subjects.map(\.code).joined(separator: ", "))")
                    .foregroundStyle(Tech.text)
                Text(store.syncing ? "syncing…" : "synced \(store.lastSynced.map(ago) ?? "")").foregroundStyle(Tech.text2)
            }
            if let e = store.syncError { Text(e).foregroundStyle(alarm) }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .techPanel()

        if let note = store.cacheNote { Text("· \(note)").font(.caption).foregroundStyle(Tech.text2) }
        if !store.warnings.isEmpty {
            SectionLabel("skipped")
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.warnings, id: \.self) { Text("· \($0)").font(.caption).foregroundStyle(Tech.text2) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
        }

        HStack {
            Button("Disconnect", role: .destructive) { store.disconnect() }
            Spacer()
            Button("Sync now") { store.syncNow() }.keyboardShortcut("r").disabled(store.syncing)
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n).").foregroundStyle(Tech.neon)
            Text(text).foregroundStyle(Tech.text)
        }
        .font(.callout)
    }

    /// Jev (TypeSafe "System One") sorts announcements and dated items into deadline / exam / class change / event / grades / info.
    @ViewBuilder private var classifier: some View {
        SectionLabel("ai classifier · jev")
        if store.hasJevKey {
            HStack {
                Text("● KEY SAVED IN KEYCHAIN").foregroundStyle(Tech.neon)
                if let note = store.classifierNote { Text("· \(note)").foregroundStyle(Tech.text2) }
                Spacer()
                Button("Remove key") { store.removeJevKey() }
            }
            .font(.callout)
        } else {
            Text("Paste your TypeSafe API key. Announcement and course-document text is sent to api.typesafe.ai to be classified; grades and files are not.")
                .font(.callout).foregroundStyle(Tech.text2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                SecureField("TypeSafe API key", text: $jevKey).textFieldStyle(.plain).padding(8).techPanel(radius: 6)
                Button(jevBusy ? "Checking…" : "Save key") {
                    jevBusy = true
                    jevError = nil
                    Task {
                        do { try await store.setJevKey(jevKey); jevKey = "" }
                        catch { jevError = Moodle.redact(error.localizedDescription) }
                        jevBusy = false
                    }
                }
                .disabled(jevBusy || jevKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let e = jevError { Text(e).font(.callout).foregroundStyle(alarm) }
        }

        // Outlook Calendar: MBZUAI blocks app registrations for students, so the published ICS link is the way in.
        SectionLabel("outlook calendar")
        if store.hasOutlookLink {
            HStack {
                Text("● LINK SAVED IN KEYCHAIN").foregroundStyle(Tech.neon)
                if let note = store.outlookNote { Text("· \(note)").foregroundStyle(alarm).lineLimit(2) }
                Spacer()
                Button("Remove link") { store.removeOutlookLink() }
            }
            .font(.callout)
        } else {
            Text("In Outlook: Settings ▸ Calendar ▸ Shared calendars ▸ Publish a calendar, then paste the ICS link. It works like a password and is kept in the Keychain.")
                .font(.callout).foregroundStyle(Tech.text2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                SecureField("ICS link (…/calendar.ics)", text: $icsLink).textFieldStyle(.plain).padding(8).techPanel(radius: 6)
                Button(icsBusy ? "Checking…" : "Save link") {
                    icsBusy = true
                    icsError = nil
                    Task {
                        do { try await store.setOutlookLink(icsLink); icsLink = "" }
                        catch { icsError = error.localizedDescription }
                        icsBusy = false
                    }
                }
                .disabled(icsBusy || icsLink.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let e = icsError { Text(e).font(.callout).foregroundStyle(alarm) }
        }

        // School mail: an Outlook forwarding rule sends it to Gmail; the app reads only mail addressed to @mbzuai.ac.ae.
        SectionLabel("school mail · via gmail")
        if store.hasMail {
            HStack {
                Text("● APP PASSWORD SAVED IN KEYCHAIN").foregroundStyle(Tech.neon)
                if let note = store.mailNote { Text("· \(note)").foregroundStyle(Tech.text2).lineLimit(2) }
                Spacer()
                Button("Remove") { store.removeMail() }
            }
            .font(.callout)
        } else {
            Text("Outlook forwards school mail to Gmail. Create a Gmail app password (myaccount.google.com/apppasswords) and paste it here; only mail sent to @mbzuai.ac.ae is read.")
                .font(.callout).foregroundStyle(Tech.text2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                TextField("Gmail address", text: $gmail).textFieldStyle(.plain).padding(8).techPanel(radius: 6).frame(width: 200)
                SecureField("app password (16 letters)", text: $appPassword).textFieldStyle(.plain).padding(8).techPanel(radius: 6)
                Button(mailBusy ? "Checking…" : "Save") {
                    mailBusy = true
                    mailError = nil
                    Task {
                        do { try await store.setMail(address: gmail, password: appPassword); appPassword = "" }
                        catch { mailError = error.localizedDescription }
                        mailBusy = false
                    }
                }
                .disabled(mailBusy || appPassword.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let e = mailError { Text(e).font(.callout).foregroundStyle(alarm) }
        }

        // Titles: Jev picks the important sentences, DeepSeek condenses them into one title, Jev checks it.
        SectionLabel("ai titles · deepseek")
        if store.hasDeepSeekKey {
            HStack {
                Text("● KEY SAVED IN KEYCHAIN").foregroundStyle(Tech.neon)
                if let note = store.summaryNote { Text("· \(note)").foregroundStyle(Tech.text2).lineLimit(2) }
                Spacer()
                Button("Remove key") { store.removeDeepSeekKey() }
            }
            .font(.callout)
        } else {
            Text("Paste your DeepSeek API key. Only the sentences Jev marks as important are sent to api.deepseek.com; it needs the Jev key too.")
                .font(.callout).foregroundStyle(Tech.text2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                SecureField("DeepSeek API key", text: $dsKey).textFieldStyle(.plain).padding(8).techPanel(radius: 6)
                Button(dsBusy ? "Checking…" : "Save key") {
                    dsBusy = true
                    dsError = nil
                    Task {
                        do { try await store.setDeepSeekKey(dsKey); dsKey = "" }
                        catch { dsError = Moodle.redact(error.localizedDescription) }
                        dsBusy = false
                    }
                }
                .disabled(dsBusy || dsKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let e = dsError { Text(e).font(.callout).foregroundStyle(alarm) }
        }
    }

    private func openKeysPage() {
        guard let url = try? Moodle.siteURL(site) else { message = MoodleError.insecureSite.localizedDescription; return }
        NSWorkspace.shared.open(url.appending(path: "user/managetoken.php"))
    }

    private func signInSSO() {
        guard !busy else { return }
        guard let url = try? Moodle.siteURL(site) else { message = MoodleError.insecureSite.localizedDescription; return }
        busy = true
        message = nil
        Task {
            do {
                let token = try await sso.signIn(site: url)
                try await store.connect(site: site, key: token)
            } catch MoodleSSOError.cancelled {
            } catch {
                message = error.localizedDescription
            }
            busy = false
        }
    }

    private func connect() {
        guard !busy, !key.isEmpty else { return }
        busy = true
        message = nil
        Task {
            do {
                try await store.connect(site: site, key: key)
                key = ""
            } catch {
                message = error.localizedDescription
            }
            busy = false
        }
    }
}

/// Sidebar footer: connection state + a button that opens ConnectView.
struct SyncFooter: View {
    @EnvironmentObject private var store: Store
    let open: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let color = store.syncError != nil ? alarm : store.lastSynced != nil ? Tech.neon : Tech.text3
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 7, height: 7).shadow(color: color, radius: 4)
                    .pulse(store.syncing, color: color)
                    .id(store.syncing) // restart the pulse each time a sync starts
                Text(label(context.date))
                    .font(.caption2.weight(.semibold)).tracking(1.2)
                    .foregroundStyle(store.syncError != nil ? alarm : Tech.text2)
                    .lineLimit(2)
                    .help(store.syncError ?? "")
                Spacer(minLength: 4)
                Button(store.isConnected ? "Sync" : "Connect…", action: open).controlSize(.small)
            }
            .padding(10)
            .techPanel(radius: 8)
            .padding(8)
        }
    }

    private func label(_ now: Date) -> String {
        if store.syncing { return "SYNCING…" }
        if let e = store.syncError { return "SYNC FAILED · \(e)" }
        if let d = store.lastSynced { return "LIVE · synced \(ago(d, now: now))" }
        return store.isConnected ? "CONNECTED" : "SAMPLE DATA"
    }
}

/// "just now", "2m ago", "3h ago", "4d ago".
private func ago(_ date: Date) -> String { ago(date, now: .now) }
private func ago(_ date: Date, now: Date) -> String {
    let m = Int(now.timeIntervalSince(date) / 60)
    return m < 1 ? "just now" : m < 60 ? "\(m)m ago" : m < 1440 ? "\(m / 60)h ago" : "\(m / 1440)d ago"
}
