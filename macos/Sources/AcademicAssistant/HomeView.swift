import SwiftUI

struct HomeView: View {
    let open: (String) -> Void
    @Local private var hovered: String?
    @Local private var shown = false // drives the KPI count-up
    @Local private var gridWidth: CGFloat = 800
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var nav: Nav
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Same sources as the Deadlines board (assignments, calendar, announcements, documents), from now on.
        let now = Date.now
        let items = Array(store.board.between(now, now.addingTimeInterval(7 * 86_400)).prefix(5))
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                kpis(next: store.board.between(now, now.addingTimeInterval(60 * 86_400)).first(where: \.toSubmit)) // next thing to hand in
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "this week")
                    if items.isEmpty {
                        Text("Nothing due this week.").foregroundStyle(Palette.text3.color)
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in row(item, i) }
                }
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "courses")
                    // As many ≥240pt columns as fit, but never more than there are courses, so cards always fill the row.
                    let cols = max(1, min(store.subjects.count, Int((gridWidth + 16) / 256)))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: cols), spacing: 16) {
                        ForEach(Array(store.subjects.enumerated()), id: \.element.id) { i, s in
                            CourseCard(subject: s, index: i) { open(s.id) }
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
                }
            }
            .frame(maxWidth: 1100, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Overview")
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 1).delay(0.3)) { shown = true }
        }
    }

    // MARK: Header

    /// "Good morning" + the date, and the sync status as a small dot and text. Redrawn once a minute, never faster.
    private var header: some View {
        TimelineView(.periodic(from: .now, by: 60)) { t in
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { greeting(t.date); Spacer(minLength: 16); syncStatus }
                VStack(alignment: .leading, spacing: 8) { greeting(t.date); syncStatus }
            }
        }
    }

    private func greeting(_ now: Date) -> some View {
        let hour = Calendar.current.component(.hour, from: now)
        return VStack(alignment: .leading, spacing: 2) {
            Text(hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening")
                .font(.largeTitle.bold()).foregroundStyle(Palette.text.color).accessibilityAddTraits(.isHeader)
            Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "en_GB")))) // "Monday 2 November"
                .font(.title3).foregroundStyle(Palette.text2.color)
        }
    }

    private var syncStatus: some View {
        let (color, text): (Color, String) =
            !store.isConnected ? (Palette.text3.color, "Sample data")
            : store.syncing ? (Palette.accent.color, "Syncing…")
            : store.syncError != nil ? (Palette.critical.color, "Sync failed")
            : (Palette.good.color, store.lastSynced.map { "Synced \($0.formatted(date: .omitted, time: .shortened))" } ?? "Not synced yet")
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(text).font(.callout).foregroundStyle(Palette.text2.color)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: KPI strip

    private func kpis(next: Deadline?) -> some View {
        let grades = store.subjects.compactMap(\.runningGrade)
        let avg = grades.isEmpty ? 0 : grades.reduce(0, +) / Double(grades.count)
        let shares = store.subjects.compactMap(\.doneShare) // only courses whose Moodle weights add up
        let toCome = shares.isEmpty ? 0 : Double(shares.reduce(0) { $0 + 100 - $1 }) / Double(shares.count)
        let tiles = Group {
            tile("avg running grade", caption: "across \(grades.count) courses", index: 0) { counter(avg) }
            tile("grade still to come", caption: shares.isEmpty ? "no reliable weights on Moodle" : "average of \(shares.count) courses", index: 1) {
                if shares.isEmpty { Text("—") } else { counter(toCome) }
            }
            tile("next deadline", caption: next.map { "\($0.label) · \($0.subject.name)" } ?? "nothing due", index: 2) {
                TimelineView(.periodic(from: .now, by: 60)) { t in // minutes at most, so once a minute
                    Text(countdown(to: next?.date, from: t.date))
                }
            }
        }
        // All three in a row when they fit, otherwise one per row — never a stranded 2 + 1.
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) { tiles }
            VStack(spacing: 12) { tiles }
        }
    }

    private func counter(_ value: Double) -> some View {
        Text(String(format: "%.1f%%", shown ? value : 0))
            .contentTransition(.numericText(value: shown ? value : 0))
    }

    private func tile(_ label: String, caption: String, index: Int, @ViewBuilder value: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.prefix(1).uppercased() + label.dropFirst()).font(.subheadline).foregroundStyle(Palette.text2.color)
            value()
                .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(Palette.text.color)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(caption).font(.caption).foregroundStyle(Palette.text2.color).lineLimit(1).truncationMode(.tail)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .stagger(index)
        .accessibilityElement(children: .combine)
    }

    // MARK: This week

    private func row(_ item: Deadline, _ i: Int) -> some View {
        let (s, p) = (item.subject, item.subject.hue.palette)
        let type = item.source.map { [.calendar: " · calendar", .announcement: " · mentioned", .outlook: " · Outlook"][$0] ?? " · document" } ?? ""
        let n = daysUntil(item.date)
        let when = "\(n <= 0 ? "Today" : n == 1 ? "Tomorrow" : "In \(n) days") · \(item.date.short())"
        let on = hovered == item.id
        let text = VStack(alignment: .leading, spacing: 2) {
            Text(item.label).font(.body.weight(.semibold)).foregroundStyle(Palette.text.color).lineLimit(2)
            Text(s.name + type).font(.callout).foregroundStyle(Palette.text2.color).lineLimit(1)
        }
        // Only graded work shows a weight (a neutral tag); events (talks, office hours, class changes) say what they are.
        let trailing = HStack(spacing: 10) {
            Text(when).font(.callout).foregroundStyle(Palette.text2.color).monospacedDigit()
            if let w = item.weight {
                Text("\(w)%").font(.caption.weight(.semibold)).foregroundStyle(Palette.text2.color).monospacedDigit()
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Palette.raised.color, in: Capsule())
            } else if let k = item.kind {
                Text(k.label.prefix(1) + k.label.dropFirst().lowercased()).font(.caption).foregroundStyle(Palette.text3.color)
            }
        }
        return Button { nav.open(s.id, announcement: item.announcement) } label: { // a post's date opens that post
            // Wide: date and weight on the right. Narrow: they drop under the text.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center) { text; Spacer(minLength: 16); trailing }
                VStack(alignment: .leading, spacing: 6) { text; trailing }
            }
            .padding(.horizontal, 14).padding(.leading, 3)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .leading) { p.accent.frame(width: 3) } // the course colour is an edge, never a fill
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .card(active: on)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? item.id : (hovered == item.id ? nil : hovered) }
        .stagger(i + 3)
        .accessibilityLabel("\(s.name), \(item.label)\(type), \(when)\(item.weight.map { ", \($0)% of grade" } ?? "")")
    }

    // MARK: Formatting

    /// "2d 14h" / "5h 12m" / "40m"
    private func countdown(to date: Date?, from now: Date) -> String {
        guard let date else { return "—" }
        let m = max(0, Int(date.timeIntervalSince(now) / 60))
        return m >= 1440 ? "\(m / 1440)d \(m / 60 % 24)h" : m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }

    private func daysUntil(_ date: Date) -> Int { // calendar days: 9:00 tomorrow seen at 22:00 is "in 1d", not "today"
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: date)).day ?? 0
    }
}

// MARK: - Course card

private struct CourseCard: View {
    let subject: Subject, index: Int, open: () -> Void
    @Local private var hover = false
    @Local private var shown = false // drives the one-shot count-up and meter fill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let p = subject.hue.palette
        let done = subject.doneShare ?? 0
        let progress = subject.doneShare.map { "\($0)% done · \(100 - $0)% still to come" } ?? "no weights on Moodle"
        let grade = subject.runningGrade
        let gradeText = grade.map { String(format: "%.1f%%", $0) } ?? "no grades yet"

        Button(action: open) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(subject.name).font(.headline).foregroundStyle(Palette.text.color)
                        Text(subject.code).font(.caption).foregroundStyle(Palette.text3.color).fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(grade.map { String(format: "%.1f%%", shown ? $0 : 0) } ?? "—")
                            .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(Palette.text.color)
                            .contentTransition(.numericText(value: shown ? grade ?? 0 : 0))
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text("Running grade").font(.caption).foregroundStyle(Palette.text3.color)
                    }
                    Capsule().fill(Palette.line.color).frame(height: 5)
                        .overlay(alignment: .leading) {
                            GeometryReader { g in
                                Capsule().fill(p.accent).frame(width: g.size.width * Double(shown ? done : 0) / 100)
                            }
                        }
                        .padding(.top, 2)
                    Text(progress).font(.caption).foregroundStyle(Palette.text2.color)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(hover ? Palette.accentInk.color : Palette.text3.color)
            }
            .padding(16)
            .padding(.leading, 3)
            .background(alignment: .leading) { p.accent.frame(width: 3) } // the course colour is an edge, never a fill
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .card(active: hover)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(Press())
        .onHover { hover = $0 }
        .help("Open \(subject.name): \(gradeText), \(progress)")
        .accessibilityLabel("\(subject.name) \(subject.code), running grade \(gradeText), \(progress)")
        .stagger(index + 6)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 1.1).delay(0.35 + Double(index) * 0.1)) { shown = true }
        }
    }
}

/// Press feedback: the card dips to 98%.
private struct Press: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
