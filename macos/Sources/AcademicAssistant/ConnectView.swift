import AppKit
import SwiftUI

/// An error line: the critical colour with its icon, never colour alone.
private struct ErrorLine: View {
    let text: String
    var body: some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "exclamationmark.triangle.fill") }
            .font(.callout).foregroundStyle(Palette.critical.color)
    }
}

/// "Key saved in Keychain" with a check, plus the step's latest note.
private func saved(_ text: String, note: String?) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
        Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.good.color).accessibilityHidden(true)
        Text(text).foregroundStyle(Palette.text.color)
        if let note { Text("· \(note)").foregroundStyle(Palette.text2.color).lineLimit(2) }
    }
}

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
                Text("Accounts").font(.title.bold()).foregroundStyle(Palette.text.color).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if store.isConnected { connected } else { form }
            classifier
        }
        .padding(24)
        .frame(width: 520)
        .background(Palette.surface.color)
    }

    @ViewBuilder private var form: some View {
        SectionLabel("Moodle site")
        HStack(spacing: 8) {
            TextField("site", text: $site, prompt: Text("https://…").foregroundStyle(Palette.text3.color))
                .textFieldStyle(.roundedBorder)
            Button("Open Security keys page") { openKeysPage() }
        }

        SectionLabel("Sign in")
        Text("Opens a private sign-in window. Log in with your university account; the app receives its key automatically.")
            .font(.callout).foregroundStyle(Palette.text2.color)
        HStack {
            Button(busy ? "Waiting for sign-in…" : "Sign in with university SSO", action: signInSSO)
                .keyboardShortcut(.defaultAction).disabled(busy)
            if busy { ProgressView().controlSize(.small) }
        }

        SectionLabel("Or paste a key")
        VStack(alignment: .leading, spacing: 6) {
            step(1, "Open the Security keys page (button above)")
            step(2, "Copy the key in the “Moodle mobile web service” row")
            step(3, "Paste it here and press Connect")
        }

        SectionLabel("Key")
        SecureField("key", text: $key, prompt: Text("paste key").foregroundStyle(Palette.text3.color))
            .textFieldStyle(.roundedBorder)
            .onSubmit(connect)

        if let message { ErrorLine(text: message) }

        HStack {
            Spacer()
            if busy { ProgressView().controlSize(.small) }
            Button(busy ? "Connecting…" : "Connect", action: connect)
                .disabled(busy || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder private var connected: some View {
        SectionLabel("Moodle")
        VStack(alignment: .leading, spacing: 6) {
            saved("Connected to \(store.siteName ?? site)", note: nil)
            if store.syncing && store.lastSynced == nil {
                Text("First sync running…").foregroundStyle(Palette.text2.color)
            } else if store.lastSynced != nil {
                Text("\(store.subjects.count) courses found: \(store.subjects.map(\.code).joined(separator: ", "))")
                    .foregroundStyle(Palette.text.color)
                Text(store.syncing ? "Syncing…" : "Synced \(store.lastSynced.map(ago) ?? "")").foregroundStyle(Palette.text2.color)
            }
            if let e = store.syncError { ErrorLine(text: e) }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .card()

        if let note = store.cacheNote { Text("· \(note)").font(.caption).foregroundStyle(Palette.text2.color) }
        if !store.warnings.isEmpty {
            SectionLabel("Skipped")
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.warnings, id: \.self) { Text("· \($0)").font(.caption).foregroundStyle(Palette.text2.color) }
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
            Text("\(n).").foregroundStyle(Palette.accentInk.color).monospacedDigit()
            Text(text).foregroundStyle(Palette.text.color)
        }
        .font(.callout)
    }

    /// Jev (TypeSafe "System One") sorts announcements and dated items into deadline / exam / class change / event / grades / info.
    @ViewBuilder private var classifier: some View {
        SectionLabel("AI classifier (Jev)")
        if store.hasJevKey {
            HStack {
                saved("Key saved in Keychain", note: store.classifierNote)
                Spacer()
                Button("Remove key") { store.removeJevKey() }
            }
            .font(.callout)
        } else {
            Text("Paste your TypeSafe API key. Announcement and course-document text is sent to api.typesafe.ai to be classified; grades and files are not.")
                .font(.callout).foregroundStyle(Palette.text2.color).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                SecureField("TypeSafe API key", text: $jevKey).textFieldStyle(.roundedBorder)
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
            if let e = jevError { ErrorLine(text: e) }
        }

        // Outlook Calendar: MBZUAI blocks app registrations for students, so the published ICS link is the way in.
        SectionLabel("Outlook calendar")
        if store.hasOutlookLink {
            HStack {
                saved("Link saved in Keychain", note: nil)
                Spacer()
                Button("Remove link") { store.removeOutlookLink() }
            }
            .font(.callout)
            if let note = store.outlookNote { ErrorLine(text: note) } // only set when the calendar couldn't be read
        } else {
            Text("In Outlook: Settings ▸ Calendar ▸ Shared calendars ▸ Publish a calendar, then paste the ICS link. It works like a password and is kept in the Keychain.")
                .font(.callout).foregroundStyle(Palette.text2.color).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                SecureField("ICS link (…/calendar.ics)", text: $icsLink).textFieldStyle(.roundedBorder)
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
            if let e = icsError { ErrorLine(text: e) }
        }

        // School mail: an Outlook forwarding rule sends it to Gmail; the app reads only mail addressed to @mbzuai.ac.ae.
        SectionLabel("School mail via Gmail")
        if store.hasMail {
            HStack {
                saved("App password saved in Keychain", note: store.mailNote)
                Spacer()
                Button("Remove") { store.removeMail() }
            }
            .font(.callout)
        } else {
            Text("Outlook forwards school mail to Gmail. Create a Gmail app password (myaccount.google.com/apppasswords) and paste it here; only mail sent to @mbzuai.ac.ae is read.")
                .font(.callout).foregroundStyle(Palette.text2.color).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                TextField("Gmail address", text: $gmail).textFieldStyle(.roundedBorder).frame(width: 200)
                SecureField("app password (16 letters)", text: $appPassword).textFieldStyle(.roundedBorder)
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
            if let e = mailError { ErrorLine(text: e) }
        }

        // Titles: Jev picks the important sentences, DeepSeek condenses them into one title, Jev checks it.
        SectionLabel("AI titles (DeepSeek)")
        if store.hasDeepSeekKey {
            HStack {
                saved("Key saved in Keychain", note: store.summaryNote)
                Spacer()
                Button("Remove key") { store.removeDeepSeekKey() }
            }
            .font(.callout)
        } else {
            Text("Paste your DeepSeek API key. Only the sentences Jev marks as important are sent to api.deepseek.com; it needs the Jev key too.")
                .font(.callout).foregroundStyle(Palette.text2.color).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                SecureField("DeepSeek API key", text: $dsKey).textFieldStyle(.roundedBorder)
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
            if let e = dsError { ErrorLine(text: e) }
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
        TimelineView(.periodic(from: .now, by: 30)) { context in // "2m ago": a 30 s tick is enough
            HStack(spacing: 8) {
                // A spinner only while a sync runs (work in progress); otherwise a static icon with the text.
                if store.syncing { ProgressView().controlSize(.mini) }
                else if store.syncError != nil { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.critical.color) }
                else if store.lastSynced != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.good.color) }
                else { Image(systemName: "circle.dashed").foregroundStyle(Palette.text3.color) }
                Text(label(context.date))
                    .font(.caption)
                    .foregroundStyle(store.syncError != nil ? Palette.critical.color : Palette.text2.color)
                    .lineLimit(2)
                    .help(store.syncError ?? "")
                Spacer(minLength: 4)
                Button(store.isConnected ? "Sync" : "Connect…", action: open).controlSize(.small)
            }
            .padding(10)
            .card(radius: 8)
            .padding(8)
        }
    }

    private func label(_ now: Date) -> String {
        if store.syncing { return "Syncing…" }
        if let e = store.syncError { return "Sync failed · \(e)" }
        if let d = store.lastSynced { return "Synced \(ago(d, now: now))" }
        return store.isConnected ? "Connected" : "Sample data"
    }
}

/// "just now", "2m ago", "3h ago", "4d ago".
private func ago(_ date: Date) -> String { ago(date, now: .now) }
private func ago(_ date: Date, now: Date) -> String {
    let m = Int(now.timeIntervalSince(date) / 60)
    return m < 1 ? "just now" : m < 60 ? "\(m)m ago" : m < 1440 ? "\(m / 60)h ago" : "\(m / 1440)d ago"
}
