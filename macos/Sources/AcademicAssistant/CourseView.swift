import AppKit
import QuickLook
import SwiftUI

struct CourseView: View {
    let subject: Subject

    enum Tab: Int, CaseIterable {
        case scores, assignments, materials, announcements
        var title: String { ["Scores", "Assignments", "Lectures & Material", "Announcements"][rawValue] }
        var short: String { ["Scores", "Tasks", "Material", "News"][rawValue] }
    }

    @Local private var tab: Tab = .scores
    @Local private var forward = true
    @Local private var hoveredTab: Tab?
    @Local private var query = ""
    @Local private var preview: URL? // file shown in the Quick Look panel
    @Local private var highlighted: String? // announcement opened from a deadline card
    @EnvironmentObject private var nav: Nav
    @FocusState private var filterFocused: Bool
    @Namespace private var underline
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var accent: Color { subject.hue.palette.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            tabBar
            ZStack(alignment: .top) {
                Group {
                    if tab == .scores { ScoreChart(subject: subject) } else { list }
                }
                .id(tab)
                // Insertion slides in from the side of travel; removal just fades, so its direction can never be stale.
                .transition(.asymmetric(
                    insertion: reduceMotion ? .opacity : .offset(x: forward ? 80 : -80).combined(with: .opacity),
                    removal: .opacity))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
        }
        .background { shortcuts }
        .navigationTitle(subject.name)
        .navigationSubtitle(subject.code)
        .quickLookPreview($preview)
        .onAppear { // opened from a deadline that came from an announcement: go to that post
            guard let f = nav.focus, subject.announcements.contains(where: { $0.key == f }) else { return }
            tab = .announcements
            highlighted = f
            nav.focus = nil
        }
    }

    private func select(_ t: Tab) {
        guard t != tab else { return }
        forward = t.rawValue > tab.rawValue
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { tab = t; query = "" }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                TypewriterTitle(text: subject.name)
                Text("[\(subject.code)]")
                    .font(.caption.weight(.semibold)).foregroundStyle(Tech.text2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Tech.line))
            }
            ShimmerBar(color: accent)
            Text(stats).font(.caption).foregroundStyle(Tech.text).lineLimit(2)
        }
        .padding(24)
    }

    private var stats: AttributedString {
        let next = subject.assessments.first { $0.score == nil && $0.date >= .now }
        let parts = [
            ("GRADE", subject.runningGrade.map { String(format: "%.1f%%", $0) } ?? "—"),
            ("DONE", subject.doneShare.map { "\($0)%" } ?? "—"),
            ("NEXT", next.map { a in let d = daysUntil(a.date); return "\(a.name) \(d == 0 ? "today" : "in \(d)d")" } ?? "—"),
        ]
        var out = AttributedString()
        for (i, (label, value)) in parts.enumerated() {
            var l = AttributedString((i > 0 ? "  ·  " : "") + label + " ")
            l.foregroundColor = Tech.text3
            out += l + AttributedString(value)
        }
        return out
    }

    // MARK: Tabs

    private var tabBar: some View {
        ViewThatFits(in: .horizontal) {
            tabButtons(short: false)
            tabButtons(short: true)
            Picker("Section", selection: Binding(get: { tab }, set: select)) {
                ForEach(Tab.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu).labelsHidden().fixedSize().padding(.vertical, 6)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Tech.line).frame(height: 1) }
    }

    private func tabButtons(short: Bool) -> some View {
        HStack(spacing: 20) {
            ForEach(Tab.allCases, id: \.self) { t in
                let selected = tab == t
                Button { select(t) } label: {
                    Text(short ? t.short : t.title)
                        .font(.callout.weight(selected ? .bold : .regular))
                        .foregroundStyle(selected || hoveredTab == t ? Tech.text : Tech.text2)
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            if selected {
                                Rectangle().fill(Tech.neon).frame(height: 2)
                                    .shadow(color: Tech.neon, radius: 5)
                                    .matchedGeometryEffect(id: "underline", in: underline)
                            } else if hoveredTab == t {
                                Rectangle().fill(Tech.neon.opacity(0.3)).frame(height: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .onHover { hoveredTab = $0 ? t : (hoveredTab == t ? nil : hoveredTab) }
                .animation(.easeOut(duration: 0.15), value: hoveredTab)
                .help("\(t.title) (⌥\(t.rawValue + 1))")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    /// Invisible buttons so ⌥1…⌥4 and ⌘F work whichever tab-bar layout is showing.
    private var shortcuts: some View {
        Group {
            ForEach(Tab.allCases, id: \.self) { t in
                Button("") { select(t) }.keyboardShortcut(KeyEquivalent(Character("\(t.rawValue + 1)")), modifiers: .option)
            }
            Button("") { filterFocused = true }.keyboardShortcut("f").disabled(tab == .scores)
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    // MARK: Lists

    private var list: some View {
        VStack(spacing: 0) {
            filterField.frame(maxWidth: 1000).frame(maxWidth: .infinity, alignment: .leading) // left edge lines up with the header
                .padding(.horizontal, 24).padding(.top, 16)
            ScrollViewReader { proxy in ScrollView {
                VStack(spacing: 10) {
                    rows
                    if matchCount == 0 {
                        Text("// no matches").font(.callout).foregroundStyle(Tech.text3).padding(.top, 24)
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: query)
                .frame(maxWidth: 1000)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .scrollContentBackground(.hidden)
            .task(id: highlighted) {
                guard let h = highlighted else { return }
                try? await Task.sleep(for: .milliseconds(450)) // after the tab's slide-in
                withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(h, anchor: .top) }
            } }
        }
    }

    private var filterField: some View {
        HStack(spacing: 8) {
            Text(">").bold().foregroundStyle(Tech.neon)
            TextField("filter", text: $query, prompt: Text("filter…").foregroundStyle(Tech.text3))
                .textFieldStyle(.plain).foregroundStyle(Tech.text).focused($filterFocused)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Tech.text3) }
                    .buttonStyle(.plain).accessibilityLabel("Clear filter")
            }
            Text("⌘F").font(.caption2).foregroundStyle(Tech.text3).accessibilityHidden(true)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .techPanel(active: filterFocused, radius: 8)
    }

    private func match(_ title: String) -> Bool { query.isEmpty || title.localizedCaseInsensitiveContains(query) }

    private var matchCount: Int {
        switch tab {
        case .scores: 1
        case .assignments: subject.assignments.filter { match($0.title) }.count + practice.count
        case .materials: lectures.count
        case .announcements: subject.announcements.filter { match($0.title) }.count
        }
    }

    /// Files to work through (exercises, labs, quizzes + solutions) go under Assignments; the rest under Lectures & Material.
    private var practice: [Material] { subject.materials.filter { $0.isPractice && match($0.title) } }
    private var lectures: [Material] { subject.materials.filter { !$0.isPractice && match($0.title) } }

    @ViewBuilder private var rows: some View {
        switch tab {
        case .scores: EmptyView()
        case .assignments:
            ForEach(Array(subject.assignments.filter { match($0.title) }.enumerated()), id: \.element) { i, x in
                let d = daysUntil(x.due), open = x.status == .open
                RowCard(index: i, accent: accent) { _ in
                    titled(x.title, x.due == .distantFuture ? "no due date" : "due \(x.due.short())", body: x.details)
                } chips: { _ in
                    if open && x.due != .distantFuture {
                        Chip(text: "OPEN", fill: subject.hue.palette.tint, edge: accent) {
                            Circle().fill(accent).frame(width: 6, height: 6).pulse(d >= 0 && d <= 3, color: accent)
                        }
                        Chip(text: d >= 0 ? "T-\(d)d" : "LATE \(-d)d", edge: d <= 3 ? Tech.neon.opacity(0.6) : nil)
                    } else {
                        Chip(text: "SUBMITTED") { Image(systemName: "checkmark").foregroundStyle(Tech.neon) }
                    }
                }
            }
            if !practice.isEmpty {
                SectionLabel("exercises · labs · quizzes").padding(.top, 8)
                ForEach(Array(practice.enumerated()), id: \.element) { i, x in
                    MaterialRow(index: i, subject: subject, material: x, accent: accent, preview: $preview)
                }
            }
        case .materials:
            ForEach(Array(lectures.enumerated()), id: \.element) { i, x in
                MaterialRow(index: i, subject: subject, material: x, accent: accent, preview: $preview)
            }
        case .announcements:
            ForEach(Array(subject.announcements.filter { match($0.title) }.enumerated()), id: \.element) { i, x in
                RowCard(index: i, accent: accent) { _ in
                    titled(x.title, "\(x.from) · \(x.date.short())", body: x.body, open: x.key == highlighted)
                } chips: { _ in
                    if x.date > .now.addingTimeInterval(-2 * 86_400) { NewChip() }
                    if let k = x.kind { Chip(text: k.label, edge: k.isDated ? accent : nil) { EmptyView() } }
                    Chip(text: x.source.rawValue.uppercased()) {
                        Image(systemName: [.moodle: "graduationcap", .message: "bubble.left", .notification: "bell", .outlook: "envelope", .teams: "bubble.left.and.bubble.right"][x.source] ?? "bell")
                            .foregroundStyle(Tech.text2)
                    }
                }
                .id(x.key)
                .overlay { // the post a deadline card was opened from
                    if x.key == highlighted { RoundedRectangle(cornerRadius: 10).strokeBorder(accent, lineWidth: 2).shadow(color: accent, radius: 6) }
                }
            }
        }
    }

    private func titled(_ title: String, _ meta: String, body: String? = nil, open: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).foregroundStyle(Tech.text)
            Text(meta).font(.caption).foregroundStyle(Tech.text2)
            if let body { ExpandableText(text: body, startOpen: open) }
        }
    }
}

/// Whole calendar days from today to `date` (negative = past).
private func daysUntil(_ date: Date) -> Int {
    let cal = Calendar.current
    return cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: date)).day ?? 0
}

/// Card row: accent glow and nudge on hover, staggered entrance; chips drop under the title when the row is too narrow.
private struct RowCard<Main: View, Chips: View>: View {
    let index: Int, accent: Color
    @ViewBuilder let main: (Bool) -> Main
    @ViewBuilder let chips: (Bool) -> Chips
    @Local private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                main(hovered)
                Spacer(minLength: 12)
                HStack(spacing: 8) { chips(hovered) }
            }
            VStack(alignment: .leading, spacing: 10) {
                main(hovered)
                HStack(spacing: 8) { chips(hovered) }
            }
        }
        .padding(.vertical, 14).padding(.leading, 18).padding(.trailing, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Capsule().fill(accent).frame(width: 3).padding(.vertical, 12).padding(.leading, 6)
                .shadow(color: accent.opacity(hovered ? 0.9 : 0), radius: 4)
        }
        .techPanel(active: hovered, glow: accent)
        .offset(x: hovered && !reduceMotion ? 4 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovered)
        .onHover { hovered = $0 }
        .stagger(index)
        .accessibilityElement(children: .contain) // keep row buttons (Preview, Show in Finder…) individually reachable
    }
}

/// Small terminal-style tag. Text is always present; colour only tints the fill and edge.
/// A course file: click to preview (downloads first if needed); Open / Show in Finder / Copy path; shows where it lives.
/// ponytail: a multi-file Moodle folder previews its first file; "Show in Finder" reveals the rest.
private struct MaterialRow: View {
    let index: Int, subject: Subject, material: Material, accent: Color
    @Binding var preview: URL?
    @EnvironmentObject private var store: Store
    @Local private var busy = false
    @Local private var failure: String?

    var body: some View {
        let file = material.files?.first
        let local = file.map { MaterialStore.localURL(subject, material, $0) }
        let saved = store.filesVersion >= 0 && file.map { MaterialStore.isSaved(local!, $0) } == true // filesVersion: re-check after downloads
        RowCard(index: index, accent: accent) { hovered in
            Button { file != nil ? fetch { preview = $0 } : openLink() } label: {
                HStack(spacing: 12) {
                    Image(systemName: material.isPractice ? "pencil.and.list.clipboard"
                          : [.slides: "doc.richtext", .recording: "play.rectangle", .notes: "note.text", .reading: "book"][material.kind] ?? "doc")
                        .font(.title3).foregroundStyle(accent).frame(width: 26)
                        .symbolEffect(.bounce, value: hovered)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(material.title).foregroundStyle(Tech.text)
                        Text(meta).font(.caption).foregroundStyle(Tech.text2)
                        if let local {
                            Text(local.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .font(.caption2).foregroundStyle(Tech.text3).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        }
                        if let failure { Text(failure).font(.caption2).foregroundStyle(Color(hex: "ff6b6b")) }
                        if let t = material.text, t != material.title { ExpandableText(text: t) } // label / description text
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(file != nil ? "Preview \(file!.name)" : material.link != nil ? "Open link" : material.title)
        } chips: { _ in
            if file != nil {
                if busy { ProgressView().controlSize(.small) }
                else if saved { Chip(text: "SAVED") { Image(systemName: "checkmark").foregroundStyle(Tech.neon) } }
                else { Chip(text: "ONLINE") { Image(systemName: "icloud.and.arrow.down").foregroundStyle(Tech.text2) } }
                action("eye", "Preview") { fetch { preview = $0 } }
                action("arrow.up.forward.app", "Open in its app") { fetch { NSWorkspace.shared.open($0) } }
                action("folder", "Show in Finder") { fetch { NSWorkspace.shared.activateFileViewerSelecting([$0]) } }
                action("doc.on.doc", "Copy file path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(local!.path(percentEncoded: false), forType: .string)
                }
            } else if material.link != nil {
                action("safari", "Open link") { openLink() }
            }
            Chip(text: material.isPractice ? material.practiceLabel : material.kind.rawValue.uppercased())
        }
    }

    private var meta: String {
        let n = material.files?.count ?? 0
        let size = (material.files ?? []).reduce(0) { $0 + $1.size }
        let parts = [material.date.short(), n > 1 ? "\(n) files" : nil,
                     size > 0 ? ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file) : nil, material.link != nil ? "link" : nil]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    private func action(_ symbol: String, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) { Image(systemName: symbol).frame(width: 22, height: 22) }
            .buttonStyle(.plain).foregroundStyle(Tech.text2)
            .help(label).accessibilityLabel(label)
            .disabled(busy)
    }

    /// Downloads the file if it isn't on disk yet, then hands its local URL to `then`.
    private func fetch(_ then: @escaping (URL) -> Void) {
        guard let file = material.files?.first, !busy else { return }
        busy = true
        failure = nil
        Task {
            do { then(try await store.localFile(subject, material, file)) }
            catch { failure = "Couldn't download: \(Moodle.redact(error.localizedDescription))" }
            busy = false
        }
    }

    private func openLink() {
        if let s = material.link, let u = URL(string: s), ["https", "http"].contains(u.scheme ?? "") { NSWorkspace.shared.open(u) }
    }
}

/// Full announcement / instructions text: 3 lines, click "more" to read it all.
struct ExpandableText: View {
    let text: String
    @Local private var open: Bool
    init(text: String, startOpen: Bool = false) { self.text = text; _open = Local(initialValue: startOpen) }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text).font(.callout).foregroundStyle(Tech.text2).lineLimit(open ? nil : 3)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if text.count > 160 || text.contains("\n") {
                Button(open ? "less" : "more") { withAnimation(.easeOut(duration: 0.2)) { open.toggle() } }
                    .buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(Tech.neon)
            }
        }
        .padding(.top, 2)
    }
}

private struct Chip<Leading: View>: View {
    let text: String
    var fill: Color? = nil
    var edge: Color? = nil
    @ViewBuilder var leading: () -> Leading

    var body: some View {
        HStack(spacing: 5) {
            leading()
            Text(text).foregroundStyle(fill == nil ? Tech.text2 : Tech.text)
        }
        .font(.caption2.weight(.semibold)).tracking(1).monospacedDigit()
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(fill ?? .clear, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(edge ?? Tech.line))
        .fixedSize()
    }
}

extension Chip where Leading == EmptyView {
    init(text: String, fill: Color? = nil, edge: Color? = nil) {
        self.init(text: text, fill: fill, edge: edge) { EmptyView() }
    }
}

/// "NEW" tag that blinks a few times when it appears, then stays lit.
private struct NewChip: View {
    @Local private var lit = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Chip(text: "NEW", edge: Tech.neon) { Circle().fill(Tech.neon).frame(width: 5, height: 5) }
            .shadow(color: Tech.neon.opacity(lit ? 0.6 : 0), radius: 6)
            .opacity(lit ? 1 : 0.25)
            .task {
                guard !reduceMotion else { return }
                for _ in 0..<6 {
                    try? await Task.sleep(for: .milliseconds(160))
                    lit.toggle()
                }
                lit = true
            }
    }
}

/// 3pt course-accent bar with a light sweep looping across it (static under Reduce Motion).
private struct ShimmerBar: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            GeometryReader { g in
                let p = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.6) / 2.6
                let w = g.size.width * 0.22
                Capsule().fill(color)
                    .overlay(alignment: .leading) {
                        if !reduceMotion {
                            LinearGradient(colors: [.clear, .white.opacity(0.75), .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: w)
                                .offset(x: p * (g.size.width + w) - w)
                        }
                    }
                    .clipShape(Capsule())
            }
        }
        .frame(height: 3)
        .shadow(color: color.opacity(0.7), radius: 6)
        .accessibilityHidden(true)
    }
}
