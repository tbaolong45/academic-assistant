import SwiftUI

// Pieces of the week board (WeekView). Amber and red are status colours, never course colours, and always sit next to
// a text label ("HEAVY", "CRUNCH", "OVERDUE").

private let amber = Color(hex: "f5b544")
private let red = Color(hex: "ff6b6b")
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
        + (d.weight.map { ", \($0)% of grade" } ?? "")
}

// MARK: - Day column

struct DayColumn: View {
    let day: BoardDay, now: Date, open: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DayHeader(day: day)
            if day.items.isEmpty {
                Text("— free —").font(.caption).foregroundStyle(Tech.text3)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            ForEach(Array(day.items.enumerated()), id: \.element.id) { i, d in
                DeadlineCard(deadline: d, now: now) { open(d.subject.id) }
                    .stagger(day.index + i) // diagonal cascade across the week
            }
        }
        .padding(6)
        .background {
            if day.isToday {
                RoundedRectangle(cornerRadius: 12).fill(Tech.neon.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Tech.neon.opacity(0.45), lineWidth: 1))
            }
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
                Text(weekday(day.date).uppercased()).fontWeight(.bold).foregroundStyle(Tech.text)
                Text(day.date.formatted(.dateTime.day().locale(gb))).foregroundStyle(Tech.text2)
                Spacer(minLength: 4)
                Text("\(count) due").foregroundStyle(count == 0 ? Tech.text3 : Tech.text2)
            }
            .font(.caption).monospacedDigit()
            WorkloadBar(fraction: min(Double(day.weight), 40) / 40, heavy: day.heavy, delay: Double(day.index) * 0.05)
            HStack(spacing: 4) {
                if day.heavy { Tag(text: "HEAVY", edge: amber) }
                Spacer(minLength: 2)
                Text("\(day.weight)%").font(.caption2.weight(.semibold)).foregroundStyle(Tech.text2).monospacedDigit()
            }
            .frame(minHeight: 18)
        }
        .padding(10)
        .techPanel(radius: 8)
        .modifier(AmberGlow(active: day.heavy, radius: 8))
        .overlay(alignment: .top) {
            if day.isToday {
                Text("TODAY").font(.caption2.weight(.heavy)).tracking(1.2).foregroundStyle(Tech.bg)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Tech.neon, in: Capsule())
                    .shadow(color: Tech.neon.opacity(0.6), radius: 5)
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
        let color = heavy ? amber : Tech.neon
        Capsule().fill(Tech.line).frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { g in
                    Capsule().fill(color)
                        .frame(width: g.size.width * (shown ? fraction : 0))
                        .shadow(color: color.opacity(0.7), radius: 3)
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

    var body: some View {
        let d = deadline, p = d.subject.hue.palette
        let big = (d.weight ?? 0) >= 15
        let weight = d.weight.map { Tag(text: "\($0)%", fill: big ? p.tint : nil, edge: big ? p.accent : nil) } // events carry no grade
        let when = Group {
            if d.date < now && d.source != nil { Tag(text: "PAST") } // a mentioned/calendar/document date that has passed: info, not a missed task
            else if d.isClosed(now: now) { Tag(text: "CLOSED") } // past the cutoff: Moodle no longer takes it
            else if d.date < now { Tag(text: "OVERDUE", edge: red) { Circle().fill(red).frame(width: 5, height: 5) } }
            else { Text(dueText(d.date, now: now)).font(.caption2).foregroundStyle(Tech.text2).monospacedDigit() }
        }
        // From an announcement: open that post in its course. Otherwise (assignments, PDF dates): the preview.
        BoardButton(glow: p.accent, action: { if let a = d.announcement { nav.open(d.subject.id, announcement: a) } else { showing = true } }) {
            VStack(alignment: .leading, spacing: big ? 6 : 4) {
                HStack(spacing: 6) {
                    Text(d.subject.code).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(Tech.text3)
                        .lineLimit(1).fixedSize()
                    if let src = d.source { // not a Moodle activity: say where the date came from
                        Text(d.kind?.label ?? ([.calendar: "CALENDAR", .announcement: "MENTIONED", .outlook: "OUTLOOK"][src] ?? "DOCUMENT"))
                            .font(.system(size: 9, weight: .semibold)).tracking(0.8).foregroundStyle(Tech.text2)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Tech.line))
                            .fixedSize() // never wrap "MENTIONED"
                    }
                }
                Text(d.label)
                    .font(big ? .callout.weight(.bold) : .caption.weight(.medium)).foregroundStyle(Tech.text)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) { when; Spacer(minLength: 4); if let weight { weight } }
                    VStack(alignment: .leading, spacing: 4) { when; if let weight { weight } }
                }
            }
            .padding(.vertical, big ? 12 : 8).padding(.leading, big ? 13 : 12).padding(.trailing, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack(alignment: .leading) {
                    // Full-size base: without it the stack is only as wide as the stripe and gets centred in the card.
                    big ? p.tint.opacity(0.6) : Color.clear
                    p.accent.frame(width: big ? 4 : 3)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .help(d.announcement == nil ? "Show details" : "Open the announcement")
        .popover(isPresented: $showing, arrowEdge: .trailing) { DeadlinePreview(deadline: d, now: now) { showing = false; open() } }
        .accessibilityLabel(spoken(d, now: now))
    }
}

struct DoNextChip: View {
    let deadline: Deadline, now: Date, open: () -> Void
    @Local private var showing = false
    @EnvironmentObject private var nav: Nav

    var body: some View {
        let d = deadline, accent = d.subject.hue.palette.accent
        BoardButton(glow: accent, action: { if let a = d.announcement { nav.open(d.subject.id, announcement: a) } else { showing = true } }) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Circle().fill(accent).frame(width: 8, height: 8).shadow(color: accent, radius: 3)
                    Text(d.label).font(.caption.weight(.semibold)).foregroundStyle(Tech.text).lineLimit(1)
                }
                Text(d.reason(now: now)).font(.caption2).foregroundStyle(Tech.text2).lineLimit(1).truncationMode(.middle)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .popover(isPresented: $showing, arrowEdge: .bottom) { DeadlinePreview(deadline: d, now: now) { showing = false; open() } }
        .accessibilityLabel("Do next: " + spoken(d, now: now) + ". " + d.reason(now: now))
    }
}

/// What a deadline is about, shown when its card or chip is clicked: when, weight, where it came from and the full text.
struct DeadlinePreview: View {
    let deadline: Deadline, now: Date, openCourse: () -> Void
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
                Circle().fill(p.accent).frame(width: 8, height: 8).shadow(color: p.accent, radius: 3)
                Text("\(d.subject.code) · \(d.subject.name)").font(.caption.weight(.semibold)).foregroundStyle(Tech.text2).lineLimit(1)
            }
            Text(d.headline).font(.headline).foregroundStyle(Tech.text).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if let s = d.summary { // how the AI title was checked
                Text(String(format: "AI TITLE · JEV CHECK: says when %.0f%% · keeps the point %.0f%% · nothing invented %.0f%% · specific %.0f%%",
                            s.mentionsDate * 100, s.keepsPoint * 100, s.faithful * 100, s.specific * 100))
                    .font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(Tech.text3)
            }
            if d.headline != d.title { // the full sentence the date came from
                Text(d.title).font(.caption).foregroundStyle(Tech.text2).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            HStack(spacing: 6) {
                Tag(text: d.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                Tag(text: d.date < now ? "PAST" : "in " + timeLeft(d.date, now: now))
                if let w = d.weight { Tag(text: "\(w)% OF GRADE", fill: p.tint, edge: p.accent) }
            }
            if d.toSubmit || d.kind == .exam { // why it ranks where it does, and where the weight came from
                Text(d.reason(now: now)).font(.caption).foregroundStyle(Tech.text).fixedSize(horizontal: false, vertical: true)
                Text(d.weightNote).font(.caption2).foregroundStyle(Tech.text3)
            }
            Text(([d.kind?.label].compactMap { $0 } + [source.uppercased()]).joined(separator: " · "))
                .font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(Tech.text3)
            let news = related(d.title, in: d.subject.announcements)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let detail = d.detail, !detail.isEmpty {
                        Text(detail).font(.callout).foregroundStyle(Tech.text).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    } else if news.isEmpty && docs?.isEmpty != false {
                        Text(docs == nil ? "Searching course files…" : "Moodle has no description for this item.").font(.callout).foregroundStyle(Tech.text3)
                    }
                    if let docs, !docs.isEmpty {
                        SectionLabel(text: "in course documents")
                        ForEach(docs) { m in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(m.file).font(.caption2.weight(.semibold)).foregroundStyle(Tech.text3)
                                Text(m.text).font(.callout).foregroundStyle(Tech.text).textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if !news.isEmpty {
                        SectionLabel(text: "related announcements")
                        ForEach(news, id: \.self) { a in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(a.title).font(.callout.weight(.semibold)).foregroundStyle(Tech.text)
                                Text("\(a.from) · \(a.date.formatted(.dateTime.day().month(.abbreviated)))").font(.caption2).foregroundStyle(Tech.text3)
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
        .fontDesign(.monospaced)
        .background(Tech.panel)
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
            Circle().fill(amber).frame(width: 8, height: 8).pulse(color: amber)
            Text("\(Text("⚠ CRUNCH").fontWeight(.bold).tracking(1.2)) · \(days) · \(n) deadline\(n == 1 ? "" : "s") · \(crunch.weight)% of grade")
                .font(.callout).foregroundStyle(Tech.text)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .techPanel()
        .modifier(AmberGlow(active: true, radius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Warning: crunch, \(sameDay ? weekday(first, .wide) : "\(weekday(first, .wide)) to \(weekday(last, .wide))"), "
            + "\(n) deadlines, \(crunch.weight)% of grade")
    }
}

// MARK: - Shared bits

/// Plain button on a tech panel that lifts and glows in `glow` while hovered.
struct BoardButton<Label: View>: View {
    let glow: Color, action: () -> Void
    @ViewBuilder let label: () -> Label
    @Local private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            label()
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .techPanel(active: hovered, glow: glow, radius: 8)
        }
        .buttonStyle(.plain)
        .offset(y: hovered && !reduceMotion ? -2 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovered)
        .onHover { hovered = $0 }
    }
}

/// Amber edge with a soft breathing glow behind it (a steady glow under Reduce Motion).
private struct AmberGlow: ViewModifier {
    let active: Bool, radius: CGFloat
    @Local private var bright = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay { if active { RoundedRectangle(cornerRadius: radius).strokeBorder(amber.opacity(0.6)) } }
            .background {
                // The glow is its own layer so the repeating animation can't leak into the content.
                if active {
                    RoundedRectangle(cornerRadius: radius).fill(Tech.panel)
                        .shadow(color: amber.opacity(reduceMotion ? 0.3 : bright ? 0.5 : 0.12), radius: 10)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 1.8).repeatForever(), value: bright)
                }
            }
            .onAppear { bright = true }
    }
}

/// Small terminal-style tag; colour only tints the fill and edge, the text says what it means.
private struct Tag<Leading: View>: View {
    let text: String
    var fill: Color? = nil
    var edge: Color? = nil
    @ViewBuilder var leading: () -> Leading

    var body: some View {
        HStack(spacing: 4) {
            leading()
            Text(text).foregroundStyle(fill == nil ? Tech.text2 : Tech.text)
        }
        .font(.caption2.weight(.semibold)).tracking(0.8).monospacedDigit()
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(fill ?? .clear, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(edge ?? Tech.line))
        .fixedSize()
    }
}

extension Tag where Leading == EmptyView {
    init(text: String, fill: Color? = nil, edge: Color? = nil) { self.init(text: text, fill: fill, edge: edge) { EmptyView() } }
}
