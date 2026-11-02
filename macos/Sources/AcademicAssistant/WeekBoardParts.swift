import SwiftUI

// Pieces of the week board (WeekView). Warning and critical are status colours, never course colours, and always sit
// next to a text label ("Heavy", "Crunch", "Overdue"). Nothing here animates forever (ui-redesign.md U4).

private var amber: Color { Palette.warning.color }
private var red: Color { Palette.critical.color }

/// "EXAM/QUIZ" → "Exam/quiz" (labels are upper case for older views).
private func sentence(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst().lowercased() }
private let gb = Locale(identifier: "en_GB")

private func hhmm(_ d: Date) -> String { d.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(gb)) }
private func weekday(_ d: Date, _ style: Date.FormatStyle.Symbol.Weekday = .abbreviated) -> String {
    d.formatted(.dateTime.weekday(style).locale(gb))
}

/// "due in 5h" / "due in 40m" inside the next 24 hours, otherwise the clock time ("23:59").
private func dueText(_ date: Date, now: Date) -> String {
    let s = date.timeIntervalSince(now)
    guard s > 0, s < 86_400 else { return hhmm(date) }
    return s < 3600 ? "due in \(Int(s / 60))m" : "due in \(Int(s / 3600))h"
}

/// "2d 4h" / "5h" / "40m"
private func timeLeft(_ date: Date, now: Date) -> String {
    let m = max(0, Int(date.timeIntervalSince(now) / 60))
    return m >= 1440 ? "\(m / 1440)d \(m / 60 % 24)h" : m >= 60 ? "\(m / 60)h" : "\(m)m"
}

/// "Linear Algebra, Assignment 2, due Friday 23:59, 12% of grade"
private func spoken(_ d: Deadline, now: Date) -> String {
    let late = d.date < now ? "overdue, " : ""
    return "\(d.subject.name), \(d.headline), \(late)due \(weekday(d.date, .wide)) \(hhmm(d.date))"
        + (d.showsWeight ? ", \(d.weighting.tag) of grade" : "") + (d.conflict.map { ", warning: \($0)" } ?? "")
        + (d.dateChanged ? ", date changed" : "") + (d.hidden ? d.mark.map { ", hidden: \(markText($0))" } ?? "" : "")
}

// MARK: - Day column

struct DayColumn: View {
    let day: BoardDay, now: Date, open: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DayHeader(day: day)
            if day.items.isEmpty {
                Text("Free").font(.caption).foregroundStyle(Palette.text3.color)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            ForEach(Array(day.items.enumerated()), id: \.element.id) { i, d in
                DeadlineCard(deadline: d, now: now) { open(d.subject.id) }
                    .stagger(day.index + i) // diagonal cascade across the week
            }
        }
        .padding(6)
        .background {
            if day.isToday { RoundedRectangle(cornerRadius: 12).fill(Palette.accentSoft.color) } // today marker: a soft blue column
        }
        .opacity(day.isPast ? 0.55 : 1)
    }
}

private struct DayHeader: View {
    let day: BoardDay

    var body: some View {
        let count = day.items.count
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(weekday(day.date)).fontWeight(.semibold).foregroundStyle(Palette.text.color)
                Text(day.date.formatted(.dateTime.day().locale(gb))).foregroundStyle(Palette.text2.color)
                Spacer(minLength: 4)
                Text("\(count) due").foregroundStyle(count == 0 ? Palette.text3.color : Palette.text2.color)
            }
            .font(.caption).monospacedDigit()
            WorkloadBar(fraction: min(Double(day.weight), 40) / 40, heavy: day.heavy, delay: Double(day.index) * 0.05)
            HStack(spacing: 4) {
                if day.heavy { Tag(text: "Heavy", edge: amber) { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(amber) } }
                Spacer(minLength: 2)
                Text("\(day.weight)%").font(.caption2.weight(.semibold)).foregroundStyle(Palette.text2.color).monospacedDigit()
            }
            .frame(minHeight: 18)
        }
        .padding(10)
        .card(radius: 8)
        .modifier(WarningEdge(active: day.heavy, radius: 8))
        .overlay(alignment: .top) {
            if day.isToday {
                Text("Today").font(.caption2.weight(.semibold)).foregroundStyle(Palette.onAccent.color)
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(Palette.accent.color, in: Capsule())
                    .offset(y: -8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day.isToday ? "Today, " : "")\(day.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(gb))), "
            + "\(count) deadline\(count == 1 ? "" : "s"), \(day.weight)% of grade\(day.heavy ? ", heavy" : "")")
        .accessibilityAddTraits(.isHeader)
    }
}

/// Day's summed weight on a 0–40% scale; fills from 0 each time it appears (so again on every week change).
private struct WorkloadBar: View {
    let fraction: Double, heavy: Bool, delay: Double
    @Local private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let color = heavy ? amber : Palette.accent.color
        Capsule().fill(Palette.line.color).frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { g in
                    Capsule().fill(color).frame(width: g.size.width * (shown ? fraction : 0))
                }
            }
            .animation(.easeOut(duration: 0.4), value: fraction)
            .onAppear {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.9).delay(0.25 + delay)) { shown = true }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Cards

private struct DeadlineCard: View {
    let deadline: Deadline, now: Date, open: () -> Void
    @Local private var showing = false
    @EnvironmentObject private var nav: Nav
    @EnvironmentObject private var store: Store

    var body: some View {
        let d = deadline, p = d.subject.hue.palette
        let big = d.weighting.known >= 15
        let weight = d.showsWeight ? Tag(text: d.weighting.tag) : nil // neutral; events carry no grade
        let when = Group {
            if d.date < now && d.source != nil { Tag(text: "Past") } // a mentioned/calendar/document date that has passed: info, not a missed task
            else if d.isClosed(now: now) { Tag(text: "Closed") } // past the cutoff: Moodle no longer takes it
            else if d.date < now { Tag(text: "Overdue", edge: red) { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(red) } }
            else { Text(dueText(d.date, now: now)).font(.caption2).foregroundStyle(Palette.text2.color).monospacedDigit() }
        }
        // From an announcement: open that post in its course. Otherwise (assignments, PDF dates): the preview.
        BoardButton(glow: p.accent, action: { if let a = d.announcement { nav.open(d.subject.id, announcement: a) } else { showing = true } }) {
            VStack(alignment: .leading, spacing: big ? 6 : 4) {
                HStack(spacing: 6) {
                    Text(d.subject.code).font(.caption2.weight(.semibold)).foregroundStyle(Palette.text3.color)
                        .lineLimit(1).fixedSize()
                    if let src = d.source { // not a Moodle activity: say where the date came from
                        Text(sentence(d.kind?.label ?? ([.calendar: "Calendar", .announcement: "Mentioned", .outlook: "Outlook"][src] ?? "Document")))
                            .font(.caption2).foregroundStyle(Palette.text2.color)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Palette.raised.color, in: Capsule())
                            .fixedSize() // never wrap "Mentioned"
                    }
                }
                Text(d.label)
                    .font(big ? .callout.weight(.bold) : .caption.weight(.medium)).foregroundStyle(Palette.text.color)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if let c = d.conflict { ConflictNote(text: c) } // Moodle's date kept; a newer post disagrees (D3)
                if d.dateChanged { DateChangedTag() } // dismissed or snoozed, then moved (D4)
                if d.hidden, let m = d.mark { Tag(text: markText(m)) } // shown by "Show hidden"
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) { when; Spacer(minLength: 4); if let weight { weight } }
                    VStack(alignment: .leading, spacing: 4) { when; if let weight { weight } }
                }
            }
            .padding(.vertical, big ? 12 : 8).padding(.leading, big ? 13 : 12).padding(.trailing, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .leading) { p.accent.frame(width: 3) } // the course colour is an edge, never a fill
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .help(d.announcement == nil ? "Show details" : "Open the announcement")
        .popover(isPresented: $showing, arrowEdge: .trailing) {
            DeadlinePreview(deadline: d, now: now, openCourse: { showing = false; open() },
                            mark: store.canMark ? { showing = false; store.mark(d, $0, until: $1) } : nil)
        }
        .contextMenu { if store.canMark { MarkActions(deadline: d, now: now) { store.mark(d, $0, until: $1) } } }
        .opacity(d.hidden ? 0.5 : 1) // done / dismissed / snoozed, shown by "Show hidden"
        .accessibilityLabel(spoken(d, now: now))
    }
}

struct DoNextChip: View {
    let deadline: Deadline, now: Date, open: () -> Void
    @Local private var showing = false
    @EnvironmentObject private var nav: Nav
    @EnvironmentObject private var store: Store

    var body: some View {
        let d = deadline, accent = d.subject.hue.palette.accent
        BoardButton(glow: accent, action: { if let a = d.announcement { nav.open(d.subject.id, announcement: a) } else { showing = true } }) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Circle().fill(accent).frame(width: 8, height: 8)
                    Text(d.label).font(.callout.weight(.semibold)).foregroundStyle(Palette.text.color).lineLimit(1)
                }
                Text(d.reason(now: now)).font(.caption).foregroundStyle(Palette.text2.color).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if d.dateChanged { DateChangedTag() }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            DeadlinePreview(deadline: d, now: now, openCourse: { showing = false; open() },
                            mark: store.canMark ? { showing = false; store.mark(d, $0, until: $1) } : nil)
        }
        .contextMenu { if store.canMark { MarkActions(deadline: d, now: now) { store.mark(d, $0, until: $1) } } }
        .accessibilityLabel("Do next: " + spoken(d, now: now) + ". " + d.reason(now: now))
    }
}

/// What a deadline is about, shown when its card or chip is clicked: when, weight, where it came from and the full text.
struct DeadlinePreview: View {
    let deadline: Deadline, now: Date, openCourse: () -> Void
    var mark: ((Mark.State?, Date?) -> Void)? = nil // nil on sample data; nil state = restore
    @Local private var docs: [DocumentMention]? = nil

    var body: some View {
        let d = deadline, p = d.subject.hue.palette
        let source = switch d.source {
        case nil: "Moodle activity"
        case .calendar: "Moodle calendar event"
        case .outlook: "Outlook Calendar event"
        case .announcement: "Date mentioned in an announcement"
        case .document: "Date found in a course document"
        }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(p.accent).frame(width: 8, height: 8)
                Text("\(d.subject.code) · \(d.subject.name)").font(.caption.weight(.semibold)).foregroundStyle(Palette.text2.color).lineLimit(1)
            }
            Text(d.headline).font(.headline).foregroundStyle(Palette.text.color).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if let s = d.summary { // how the AI title was checked
                Text(String(format: "AI title, checked by Jev: says when %.0f%% · keeps the point %.0f%% · nothing invented %.0f%% · specific %.0f%%",
                            s.mentionsDate * 100, s.keepsPoint * 100, s.faithful * 100, s.specific * 100))
                    .font(.caption2).foregroundStyle(Palette.text3.color)
            }
            if d.headline != d.title { // the full sentence the date came from
                Text(d.title).font(.caption).foregroundStyle(Palette.text2.color).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            HStack(spacing: 6) {
                Tag(text: d.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                Tag(text: d.date < now ? "Past" : "in " + timeLeft(d.date, now: now))
                if d.showsWeight { Tag(text: "\(d.weighting.tag) of grade") }
            }
            if d.toSubmit || d.kind == .exam { // why it ranks where it does, and where the weight came from
                Text(d.reason(now: now)).font(.caption).foregroundStyle(Palette.text.color).fixedSize(horizontal: false, vertical: true)
                Text(d.weightNote).font(.caption2).foregroundStyle(Palette.text3.color)
            }
            if let c = d.conflict { ConflictNote(text: c + "; Moodle's date is shown") }
            if d.dateChanged { DateChangedTag() }
            if let m = d.mark, d.hidden { Text(markText(m)).font(.caption2).foregroundStyle(Palette.text3.color) }
            if let mark { HStack(spacing: 8) { MarkActions(deadline: d, now: now, act: mark) }.buttonStyle(.bordered).controlSize(.small).fixedSize() }
            if let also = d.alsoMentioned {
                Text("Also mentioned in: \(also)").font(.caption2).foregroundStyle(Palette.text3.color).fixedSize(horizontal: false, vertical: true)
            }
            Text(([d.kind.map { sentence($0.label) }].compactMap { $0 } + [source]).joined(separator: " · "))
                .font(.caption2).foregroundStyle(Palette.text3.color)
            let news = related(d.title, in: d.subject.announcements)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let detail = d.detail, !detail.isEmpty {
                        Text(detail).font(.callout).foregroundStyle(Palette.text.color).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    } else if news.isEmpty && docs?.isEmpty != false {
                        Text(docs == nil ? "Searching course files…" : "Moodle has no description for this item.").font(.callout).foregroundStyle(Palette.text3.color)
                    }
                    if let docs, !docs.isEmpty {
                        SectionLabel(text: "in course documents")
                        ForEach(docs) { m in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(m.file).font(.caption2.weight(.semibold)).foregroundStyle(Palette.text3.color)
                                Text(m.text).font(.callout).foregroundStyle(Palette.text.color).textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if !news.isEmpty {
                        SectionLabel(text: "related announcements")
                        ForEach(news, id: \.self) { a in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(a.title).font(.callout.weight(.semibold)).foregroundStyle(Palette.text.color)
                                Text("\(a.from) · \(a.date.formatted(.dateTime.day().month(.abbreviated)))").font(.caption2).foregroundStyle(Palette.text3.color)
                                if let body = a.body { ExpandableText(text: body) }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // A popover sizes itself once; a ScrollView's ideal height is ~0, so give it room when there's something to read.
            .frame(height: news.isEmpty && (docs ?? []).isEmpty && (d.detail ?? "").count < 200 ? 60 : 360)
            HStack {
                Spacer()
                Button("Open \(d.subject.name)", action: openCourse).keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 400)
        .task {
            let d = deadline
            docs = await Task.detached(priority: .userInitiated) { MaterialStore.mentions(of: d.title, in: d.subject) }.value
        }
        .background(Palette.surface.color)
    }
}

struct CrunchBanner: View {
    let crunch: Crunch

    var body: some View {
        let first = crunch.items.first!.date, last = crunch.items.last!.date
        let sameDay = Calendar.current.isDate(first, inSameDayAs: last)
        let days = sameDay ? weekday(first) : "\(weekday(first))–\(weekday(last))"
        let n = crunch.items.count
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(amber)
            Text("\(Text("Crunch").fontWeight(.semibold)) · \(days) · \(n) deadline\(n == 1 ? "" : "s") · \(crunch.weight)% of grade")
                .font(.callout).foregroundStyle(Palette.text.color)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .background(amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .modifier(WarningEdge(active: true, radius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Warning: crunch, \(sameDay ? weekday(first, .wide) : "\(weekday(first, .wide)) to \(weekday(last, .wide))"), "
            + "\(n) deadlines, \(crunch.weight)% of grade")
    }
}

// MARK: - Shared bits

/// A card-styled plain button: lifts to `raised` with a blue edge while hovered. `glow` is the old name's leftover, unused.
struct BoardButton<Label: View>: View {
    let glow: Color, action: () -> Void
    @ViewBuilder let label: () -> Label
    @Local private var hovered = false

    var body: some View {
        Button(action: action) {
            label()
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .card(active: hovered, radius: 8)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// Done / Dismiss / Snooze ▸ (§3.4): the preview's buttons and the right-click menu of cards and Do next chips.
private struct MarkActions: View {
    let deadline: Deadline, now: Date, act: (Mark.State?, Date?) -> Void
    var body: some View {
        if deadline.mark != nil { Button("Restore") { act(nil, nil) } } // B6: undo, from "Show hidden" or a returned item
        Button("Done") { act(.done, nil) }
        Button("Dismiss") { act(.dismissed, nil) }
        Menu("Snooze") {
            ForEach(snoozeOptions(deadline, now: now), id: \.label) { o in Button(o.label) { act(.snoozed, o.until) } }
        }
    }
}

/// "Date changed" with its icon (status is never colour alone): a dismissed or snoozed item whose date moved (D4).
private struct DateChangedTag: View {
    var body: some View {
        Tag(text: "Date changed", edge: amber) { Image(systemName: "calendar.badge.exclamationmark").foregroundStyle(amber) }
    }
}

/// "Done", "Dismissed", "Snoozed until Mon 9 Nov".
private func markText(_ m: Mark) -> String {
    switch m.state {
    case .done: "Done"
    case .dismissed: "Dismissed"
    case .snoozed: "Snoozed" + (m.until.map { " until \($0.short())" } ?? "")
    }
}

/// "⚠ Post on Thu 29 Oct says moved to Wed 4 Nov": warning icon + text, never colour alone.
private struct ConflictNote: View {
    let text: String
    var body: some View {
        Label { Text(text).foregroundStyle(Palette.text2.color) } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(amber)
        }
        .font(.caption2).fixedSize(horizontal: false, vertical: true)
    }
}

/// A static warning edge (it used to breathe forever; ui-redesign.md U4).
private struct WarningEdge: ViewModifier {
    let active: Bool, radius: CGFloat
    func body(content: Content) -> some View {
        content.overlay { if active { RoundedRectangle(cornerRadius: radius).strokeBorder(amber, lineWidth: 1.5) } }
    }
}

/// Small neutral capsule tag (`raised` + `text2`); a status colour only tints the edge, the text says what it means.
private struct Tag<Leading: View>: View {
    let text: String
    var fill: Color? = nil
    var edge: Color? = nil
    @ViewBuilder var leading: () -> Leading

    var body: some View {
        HStack(spacing: 4) {
            leading()
            Text(text).foregroundStyle(fill == nil ? Palette.text2.color : Palette.text.color)
        }
        .font(.caption2.weight(.semibold)).monospacedDigit()
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(fill ?? Palette.raised.color, in: Capsule())
        .overlay { if let edge { Capsule().strokeBorder(edge) } }
        .fixedSize()
    }
}

extension Tag where Leading == EmptyView {
    init(text: String, fill: Color? = nil, edge: Color? = nil) { self.init(text: text, fill: fill, edge: edge) { EmptyView() } }
}
