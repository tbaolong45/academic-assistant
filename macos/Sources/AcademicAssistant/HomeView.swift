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
                        Text("nothing due. enjoy it.").foregroundStyle(Tech.text3)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            TypewriterTitle(text: "> academic_assistant")
            HStack(spacing: 14) {
                TimelineView(.periodic(from: .now, by: 1)) { t in
                    Text(clock(t.date)).foregroundStyle(Tech.text2).monospacedDigit()
                }
                HStack(spacing: 6) {
                    let live = store.isConnected
                    Circle().fill(live ? Tech.neon : Tech.text3).frame(width: 6, height: 6).pulse(color: live ? Tech.neon : .clear)
                    Text(live ? "SYNCED" : "SAMPLE DATA").foregroundStyle(live ? Tech.neon : Tech.text3).tracking(1.2)
                }
                .accessibilityElement(children: .combine)
            }
            .font(.caption)
        }
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
                TimelineView(.periodic(from: .now, by: 1)) { t in
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
            Text(label.uppercased()).font(.caption2.weight(.semibold)).tracking(1.4).foregroundStyle(Tech.text3)
            value()
                .font(.system(size: 26, weight: .bold, design: .monospaced)).monospacedDigit()
                .foregroundStyle(Tech.text)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(caption).font(.caption).foregroundStyle(Tech.text2).lineLimit(1).truncationMode(.tail)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .techPanel()
        .stagger(index)
        .accessibilityElement(children: .combine)
    }

    // MARK: This week

    private func row(_ item: Deadline, _ i: Int) -> some View {
        let (s, p) = (item.subject, item.subject.hue.palette)
        let type = item.source.map { [.calendar: " · calendar", .announcement: " · mentioned", .outlook: " · outlook"][$0] ?? " · document" } ?? ""
        let n = daysUntil(item.date)
        let when = "\(n <= 0 ? "today" : n == 1 ? "tomorrow" : "in \(n) days") · \(item.date.short())"
        let on = hovered == item.id
        let text = VStack(alignment: .leading, spacing: 2) {
            Text(s.name).font(.caption).foregroundStyle(Tech.text2)
            Text(item.label).fontWeight(.semibold).foregroundStyle(Tech.text) + Text(type).foregroundStyle(Tech.text2)
            Text(when).font(.caption).foregroundStyle(Tech.text3)
        }
        // Only graded work shows a weight; events (talks, office hours, class changes) just say what they are.
        let weight = HStack(spacing: 8) {
            if let w = item.weight {
                Capsule().fill(Tech.line).frame(width: 48, height: 4)
                    .overlay(alignment: .leading) { Capsule().fill(p.accent).frame(width: 48 * min(Double(w), 40) / 40) }
                Text("\(w)% of grade").fontWeight(.semibold).foregroundStyle(Tech.text).monospacedDigit()
            } else if let k = item.kind {
                Text(k.label).font(.caption.weight(.semibold)).tracking(1).foregroundStyle(Tech.text2)
            }
        }
        return Button { nav.open(s.id, announcement: item.announcement) } label: { // a post's date opens that post
            HStack(alignment: .top, spacing: 12) {
                Circle().fill(p.accent).frame(width: 9, height: 9)
                    .shadow(color: p.accent, radius: 3)
                    .pulse(n <= 3, color: p.accent)
                    .padding(.top, 4)
                // Wide: weight on the right. Narrow: weight drops under the text.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center) { text; Spacer(minLength: 16); weight }
                    VStack(alignment: .leading, spacing: 8) { text; weight }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .techPanel(active: on, glow: p.accent)
            .offset(x: on && !reduceMotion ? 4 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: on)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? item.id : (hovered == item.id ? nil : hovered) }
        .stagger(i + 3)
        .accessibilityLabel("\(s.name), \(item.label)\(type), \(when)\(item.weight.map { ", \($0)% of grade" } ?? "")")
    }

    // MARK: Formatting

    /// "WED 28 OCT 2026 · 14:03:27"
    private func clock(_ d: Date) -> String {
        let time = d.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)
            .locale(Locale(identifier: "en_GB")))
        return "\(d.short(year: true).uppercased()) · \(time)"
    }

    /// "02d 14h 03m 11s"
    private func countdown(to date: Date?, from now: Date) -> String {
        guard let date else { return "--" }
        let s = max(0, Int(date.timeIntervalSince(now)))
        return String(format: "%02dd %02dh %02dm %02ds", s / 86_400, s / 3600 % 24, s / 60 % 60, s % 60)
    }

    private func daysUntil(_ date: Date) -> Int { // calendar days: 9:00 tomorrow seen at 22:00 is "in 1d", not "today"
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: date)).day ?? 0
    }
}

// MARK: - Course card

private struct CourseCard: View {
    let subject: Subject, index: Int, open: () -> Void
    @Local private var hover = false
    @Local private var tilt = CGSize.zero // cursor offset from centre, -0.5...0.5
    @Local private var size = CGSize(width: 1, height: 1)
    @Local private var shown = false // drives the count-up and meter fill
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
                        Text(subject.name).font(.headline).foregroundStyle(Tech.text)
                        Text(subject.code).font(.caption).foregroundStyle(Tech.text3).fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(grade.map { String(format: "%.1f%%", shown ? $0 : 0) } ?? "—")
                            .font(.system(size: 34, weight: .bold, design: .monospaced)).monospacedDigit()
                            .foregroundStyle(Tech.text)
                            .contentTransition(.numericText(value: shown ? grade ?? 0 : 0))
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text("RUNNING GRADE").font(.caption2.weight(.semibold)).tracking(1.4).foregroundStyle(Tech.text3)
                    }
                    Capsule().fill(Tech.line).frame(height: 5)
                        .overlay(alignment: .leading) {
                            GeometryReader { g in
                                Capsule().fill(p.accent)
                                    .frame(width: g.size.width * Double(shown ? done : 0) / 100)
                                    .shadow(color: p.accent.opacity(0.7), radius: 4)
                            }
                        }
                        .padding(.top, 2)
                    Text(progress).font(.caption).foregroundStyle(Tech.text2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(hover ? Tech.neon : Tech.text3)
                    .offset(x: hover && !reduceMotion ? 3 : 0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: hover)
            }
            .padding(16)
            .padding(.leading, 3)
            .background {
                ZStack(alignment: .leading) {
                    p.tint.opacity(0.6)
                    p.accent.frame(width: 3)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .techPanel(active: hover, glow: p.accent)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(Press())
        .rotation3DEffect(.degrees(-tilt.height * 12), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
        .rotation3DEffect(.degrees(tilt.width * 12), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .onContinuousHover { phase in
            switch phase {
            case .active(let pt):
                hover = true
                guard !reduceMotion else { return }
                withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.8)) {
                    tilt = CGSize(width: pt.x / max(size.width, 1) - 0.5, height: pt.y / max(size.height, 1) - 0.5)
                }
            case .ended:
                hover = false
                withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { tilt = .zero }
            }
        }
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
