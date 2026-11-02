import SwiftUI

/// The Deadlines screen: one Mon–Sun week as a board of day columns, with per-day workload, a crunch warning and
/// the three most pressing items. Subviews live in WeekBoardParts.swift.
struct WeekView: View {
    let open: (String) -> Void
    @Local private var offset = 0 // weeks from this week
    @Local private var forward = true // direction of the last week change, for the slide
    @Local private var group: DeadlineGroup = .all
    @EnvironmentObject private var store: Store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let now = Date.now
        let start = cal.date(byAdding: .weekOfYear, value: offset, to: weekStart(of: now))!
        let everything = store.board.between(start, cal.date(byAdding: .day, value: 7, to: start)!) // calendar days: DST-safe
        let items = everything.filter { $0.isIn(group) }
        let days = boardDays(items, weekStart: start, now: now)
        // "Do next" = work to hand in in the next 7 days, most pressing first.
        let next = store.board.between(now, now.addingTimeInterval(7 * 86_400)).filter(\.toSubmit).sorted { $0.priority(now: now) > $1.priority(now: now) }.prefix(3)

        // Breakpoints come from the width the pane offers, never from the board's own size (see CLAUDE.md).
        GeometryReader { g in
            let width = g.size.width
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(start: start, items: items, everything: everything)
                    // Workload = work to hand in + exams, not talks or cancelled classes.
                    if let c = crunch(items.filter { $0.date >= now && ($0.toSubmit || $0.kind == .exam) }) { CrunchBanner(crunch: c) }
                    if !next.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel("do next")
                            let chips = ForEach(Array(next.enumerated()), id: \.element.id) { i, d in
                                DoNextChip(deadline: d, now: now) { open(d.subject.id) }.stagger(i)
                            }
                            if width < 640 { VStack(spacing: 8) { chips } } else { HStack(spacing: 10) { chips } }
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("week")
                        // Insertion slides in from the side of travel; removal just fades, so its direction can't be stale.
                        board(days, width: width, now: now)
                            .id(offset)
                            .transition(.asymmetric(
                                insertion: reduceMotion ? .opacity : .offset(x: forward ? 80 : -80).combined(with: .opacity),
                                removal: .opacity))
                    }
                }
                .frame(maxWidth: 1400, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Deadlines")
    }

    private func go(toWeek n: Int) {
        guard n != offset else { return }
        forward = n > offset
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { offset = n }
    }

    // MARK: Header

    private func header(start: Date, items: [Deadline], everything: [Deadline]) -> some View {
        let end = cal.date(byAdding: .day, value: 6, to: start)!
        let range = Text("\(start.short().uppercased()) – \(end.short().uppercased())")
            .font(.callout.weight(.semibold)).foregroundStyle(Tech.text2).monospacedDigit()
        let weight = items.reduce(0) { $0 + ($1.weight ?? 0) }
        return VStack(alignment: .leading, spacing: 10) {
            TypewriterTitle(text: "> deadlines")
            ViewThatFits(in: .horizontal) {
                HStack { range; Spacer(minLength: 16); weekButtons }
                VStack(alignment: .leading, spacing: 8) { range; weekButtons }
            }
            HStack(spacing: 12) {
                Picker("Show", selection: $group) {
                    ForEach(DeadlineGroup.allCases, id: \.self) { g in Text("\(g.rawValue) \(everything.filter { $0.isIn(g) }.count)").tag(g) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Text("\(items.count) item\(items.count == 1 ? "" : "s") · \(weight)% of grades due")
                    .font(.caption).foregroundStyle(Tech.text)
            }
        }
    }

    private var weekButtons: some View {
        HStack(spacing: 8) {
            BoardButton(glow: Tech.neon) { go(toWeek: offset - 1) } label: { buttonLabel(Image(systemName: "chevron.left")) }
                .keyboardShortcut(.leftArrow, modifiers: .option)
                .help("Previous week (⌥←)").accessibilityLabel("Previous week")
            BoardButton(glow: Tech.neon) { go(toWeek: 0) } label: { buttonLabel(Text("This week")) }
                .keyboardShortcut("t", modifiers: [])
                .opacity(offset == 0 ? 0.5 : 1)
                .help("Back to this week (T)")
            BoardButton(glow: Tech.neon) { go(toWeek: offset + 1) } label: { buttonLabel(Image(systemName: "chevron.right")) }
                .keyboardShortcut(.rightArrow, modifiers: .option)
                .help("Next week (⌥→)").accessibilityLabel("Next week")
        }
    }

    private func buttonLabel(_ content: some View) -> some View {
        content.font(.caption.weight(.semibold)).foregroundStyle(Tech.text)
            .padding(.horizontal, 10).padding(.vertical, 6)
    }

    // MARK: Board

    @ViewBuilder private func board(_ days: [BoardDay], width: CGFloat, now: Date) -> some View {
        let columns = ForEach(days) { DayColumn(day: $0, now: now, open: open) }
        if width >= 1000 {
            HStack(alignment: .top, spacing: 10) { columns.frame(maxWidth: .infinity) }
        } else if width >= 640 {
            // Columns at least 150pt wide; the scroll view runs edge to edge so cards never clip at the padding.
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) { columns.frame(width: max(150, (width - 48 - 60) / 7)) }
                    .padding(.horizontal, 24).padding(.vertical, 12)
            }
            .padding(.horizontal, -24)
        } else {
            VStack(spacing: 14) { columns }
        }
    }
}

// MARK: - Pure helpers

/// Weeks start on Monday, whatever the system setting.
private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.firstWeekday = 2
    return c
}()

/// Monday 00:00 of `date`'s week. Shared with the sidebar badge so both count the same Mon–Sun week.
func weekStart(of date: Date) -> Date { cal.dateInterval(of: .weekOfYear, for: date)!.start }

/// The week's 7 days, each with its deadlines sorted by priority (highest first).
private func boardDays(_ items: [Deadline], weekStart: Date, now: Date) -> [BoardDay] {
    let today = cal.startOfDay(for: now)
    return (0..<7).map { i in
        let day = cal.date(byAdding: .day, value: i, to: weekStart)!
        let mine = items.filter { cal.isDate($0.date, inSameDayAs: day) }.sorted { $0.priority(now: now) > $1.priority(now: now) }
        return BoardDay(index: i, date: day, items: mine, isToday: day == today, isPast: day < today)
    }
}

struct BoardDay: Identifiable {
    let index: Int, date: Date, items: [Deadline], isToday: Bool, isPast: Bool
    var id: Date { date }
    var weight: Int { items.reduce(0) { $0 + ($1.weight ?? 0) } }
    var heavy: Bool { weight >= 20 || items.count >= 3 }
}

/// A run of deadlines falling inside one 48-hour window.
struct Crunch {
    let items: [Deadline] // soonest first, never empty
    var weight: Int { items.reduce(0) { $0 + ($1.weight ?? 0) } }
}

/// The worst 48-hour window holding ≥ 3 deadlines or ≥ 30% total weight (most weight, then most items, then earliest);
/// nil if none qualifies. Windows start at each deadline.
func crunch(_ items: [Deadline], window: TimeInterval = 48 * 3600) -> Crunch? {
    let sorted = items.sorted { $0.date < $1.date }
    return sorted.indices
        .map { i in Crunch(items: Array(sorted[i...].prefix { $0.date < sorted[i].date + window })) }
        .filter { $0.items.count >= 3 || $0.weight >= 30 }
        .max { ($0.weight, $0.items.count) < ($1.weight, $1.items.count) }
}
