import SwiftUI

/// The Deadlines screen: one Mon–Sun week as a board of day columns, with per-day workload, a crunch warning and
/// the three most pressing items. Subviews live in WeekBoardParts.swift.
struct WeekView: View {
    let open: (String) -> Void
    @Local private var offset = 0 // weeks from this week
    @Local private var forward = true // direction of the last week change, for the slide
    @AppStorage("boardFilter") private var filterJSON = "" // a view preference: `BoardFilter` as JSON
    @EnvironmentObject private var store: Store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let now = Date.now
        let start = cal.date(byAdding: .weekOfYear, value: offset, to: weekStart(of: now))!
        let end = cal.date(byAdding: .day, value: 7, to: start)! // calendar days: DST-safe
        let f = filter, everything = store.items.between(start, end) // hidden ones too: "Show hidden" may want them
        let items = f.apply(everything)
        let days = boardDays(items, weekStart: start, now: now)
        // Do next and crunch follow only the course and unsure filters, and never show hidden items (§4).
        let ranked = f.forRanking.apply(store.items)
        // "Do next" = work to hand in and exams in the next 28 days, by priority (deadline-priority.md §1).
        let next = doNext(ranked, now: now)

        // Breakpoints come from the width the pane offers, never from the board's own size (see CLAUDE.md).
        GeometryReader { g in
            let width = g.size.width
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(start: start, items: items, everything: everything)
                    // Workload = work to hand in + exams, not talks or cancelled classes.
                    if let c = crunch(ranked.between(start, end).filter { $0.date >= now && ($0.toSubmit || $0.kind == .exam) }, now: now) {
                        CrunchBanner(crunch: c)
                    }
                    if !next.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel("Do next")
                            let chips = ForEach(Array(next.enumerated()), id: \.element.id) { i, d in
                                DoNextChip(deadline: d, now: now) { open(d.subject.id) }.stagger(i)
                            }
                            if width < 640 { VStack(spacing: 8) { chips } } else { HStack(spacing: 10) { chips } }
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Week")
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
        let range = Text("\(start.short()) – \(end.short())")
            .font(.title3).foregroundStyle(Palette.text2.color).monospacedDigit()
        let weight = knownWeight(items)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Deadlines").font(.largeTitle.bold()).foregroundStyle(Palette.text.color).accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                HStack { range; Spacer(minLength: 16); weekButtons }
                VStack(alignment: .leading, spacing: 8) { range; weekButtons }
            }
            HStack(spacing: 12) {
                Picker("Show", selection: binding(\.group)) {
                    // Each count is what that choice would show with the other filters kept.
                    ForEach(DeadlineGroup.allCases, id: \.self) { g in
                        Text("\(g.rawValue) \({ var x = filter; x.group = g; return x.apply(everything).count }())").tag(g)
                    }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                filterMenu
                Text("\(items.count) item\(items.count == 1 ? "" : "s") · \(weight)% of grades due")
                    .font(.callout).foregroundStyle(Palette.text2.color)
            }
            filterChips
        }
    }

    // MARK: Filter (deadline-priority.md §4)

    private var filter: BoardFilter { (try? JSONDecoder().decode(BoardFilter.self, from: Data(filterJSON.utf8))) ?? BoardFilter() }

    private func setFilter(_ f: BoardFilter) { filterJSON = (try? JSONEncoder().encode(f)).flatMap { String(data: $0, encoding: .utf8) } ?? "" }

    private func binding<T>(_ path: WritableKeyPath<BoardFilter, T>) -> Binding<T> {
        Binding(get: { filter[keyPath: path] }, set: { var f = filter; f[keyPath: path] = $0; setFilter(f) })
    }

    private func member<T: Hashable>(_ path: WritableKeyPath<BoardFilter, Set<T>>, _ value: T) -> Binding<Bool> {
        Binding(get: { filter[keyPath: path].contains(value) },
                set: { on in var f = filter; if on { f[keyPath: path].insert(value) } else { f[keyPath: path].remove(value) }; setFilter(f) })
    }

    private static let types: [ItemKind] = [.deadline, .exam, .classChange, .event]

    private func typeName(_ k: ItemKind) -> String { k.label.prefix(1) + k.label.dropFirst().lowercased() } // "Exam/quiz"
    private func originName(_ o: Origin) -> String { o.label.prefix(1).uppercased() + o.label.dropFirst() } // "PDF", "Announcement"

    private var filterMenu: some View {
        Menu {
            Menu("Courses") {
                ForEach(store.subjects) { s in
                    Toggle(isOn: member(\.courses, s.id)) { Label(s.name, systemImage: "circle.fill") }.tint(s.hue.palette.accent)
                }
            }
            Menu("Type") { ForEach(Self.types, id: \.self) { k in Toggle(typeName(k), isOn: member(\.types, k)) } }
            Menu("Source") { ForEach(Origin.allCases, id: \.self) { o in Toggle(originName(o), isOn: member(\.origins, o)) } }
            Divider()
            Toggle("Hide unsure", isOn: binding(\.hideUnsure))
            Toggle("Show hidden", isOn: binding(\.showHidden))
            if filter != BoardFilter(group: filter.group) {
                Divider()
                Button("Clear filters") { setFilter(BoardFilter(group: filter.group)) }
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
        .fixedSize()
        .help("Filter by course, type and source; hide unsure items or show hidden ones")
    }

    /// Each active filter as a chip; clicking it removes that filter.
    @ViewBuilder private var filterChips: some View {
        let f = filter
        let chips: [(String, () -> Void)] =
            store.subjects.filter { f.courses.contains($0.id) }.map { s in (s.name, { member(\.courses, s.id).wrappedValue = false }) }
            + Self.types.filter { f.types.contains($0) }.map { k in (typeName(k), { member(\.types, k).wrappedValue = false }) }
            + Origin.allCases.filter { f.origins.contains($0) }.map { o in (originName(o), { member(\.origins, o).wrappedValue = false }) }
            + (f.hideUnsure ? [("Hiding unsure", { binding(\.hideUnsure).wrappedValue = false })] : [])
            + (f.showHidden ? [("Showing hidden", { binding(\.showHidden).wrappedValue = false })] : [])
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chips.indices, id: \.self) { i in
                        Button(action: chips[i].1) {
                            HStack(spacing: 4) { Text(chips[i].0); Image(systemName: "xmark").font(.caption2.weight(.bold)) }
                                .font(.caption).foregroundStyle(Palette.accentInk.color)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Palette.accentSoft.color, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Remove this filter").accessibilityLabel("Remove filter \(chips[i].0)")
                    }
                }
            }
        }
    }

    private var weekButtons: some View {
        HStack(spacing: 8) {
            Button { go(toWeek: offset - 1) } label: { Image(systemName: "chevron.left") }
                .keyboardShortcut(.leftArrow, modifiers: .option)
                .help("Previous week (⌥←)").accessibilityLabel("Previous week")
            Button("This week") { go(toWeek: 0) }
                .keyboardShortcut("t", modifiers: [])
                .disabled(offset == 0)
                .help("Back to this week (T)")
            Button { go(toWeek: offset + 1) } label: { Image(systemName: "chevron.right") }
                .keyboardShortcut(.rightArrow, modifiers: .option)
                .help("Next week (⌥→)").accessibilityLabel("Next week")
        }
        .buttonStyle(.bordered) // secondary buttons (ui-redesign.md §2 A)
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
    var weight: Int { knownWeight(items) }
    var heavy: Bool { weight >= 20 || items.count >= 3 }
}

/// A run of deadlines falling inside one 48-hour window.
struct Crunch {
    let items: [Deadline] // soonest first, never empty
    var weight: Int { knownWeight(items) } // estimates and spares add 0, so guesses can't make a crunch; the count rule still sees them
}

/// Summed known weight (Moodle, syllabus, title), rounded: the board's "% of grade" figures (§1.4.1).
func knownWeight(_ items: [Deadline]) -> Int { Int(items.reduce(0) { $0 + $1.weighting.known }.rounded()) }

/// The worst 48-hour window holding ≥ 3 deadlines or ≥ 30% total weight (most weight, then most items, then earliest);
/// nil if none qualifies. Windows start at each deadline. Items past their cutoff (Moodle no longer takes them) don't count.
func crunch(_ items: [Deadline], now: Date = .now, window: TimeInterval = 48 * 3600) -> Crunch? {
    let sorted = items.filter { !$0.isClosed(now: now) }.sorted { $0.date < $1.date }
    return sorted.indices
        .map { i in Crunch(items: Array(sorted[i...].prefix { $0.date < sorted[i].date + window })) }
        .filter { $0.items.count >= 3 || $0.weight >= 30 }
        .max { ($0.weight, $0.items.count) < ($1.weight, $1.items.count) }
}
