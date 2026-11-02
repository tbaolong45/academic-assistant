import SwiftUI

private let cal = Calendar.current

/// The Outlook calendar as a Mon–Sun week: class sessions (recurring events expanded) and one-off events, with time and
/// room, coloured by the course they name.
struct CalendarView: View {
    @EnvironmentObject private var store: Store
    @Local private var offset = 0 // weeks from this week

    var body: some View {
        let start = cal.date(byAdding: .weekOfYear, value: offset, to: weekStart(of: .now))!
        let end = cal.date(byAdding: .day, value: 7, to: start)!
        let items = OutlookCalendar.occurrences(store.calendarItems, from: start, to: end)
        let days = (0..<7).map { cal.date(byAdding: .day, value: $0, to: start)! }

        // Breakpoint from the width the pane offers (see CLAUDE.md), never from the content's own size.
        GeometryReader { g in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(start: start, end: end, count: items.count)
                    if store.calendarItems.isEmpty {
                        Text("No Outlook calendar yet: click Sync (bottom left) and add your calendar's ICS link under OUTLOOK CALENDAR.")
                            .font(.callout).foregroundStyle(Tech.text3)
                    } else if g.size.width >= 900 {
                        HStack(alignment: .top, spacing: 8) {
                            ForEach(days, id: \.self) { d in column(d, items: items.filter { cal.isDate($0.start, inSameDayAs: d) }) }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(days, id: \.self) { d in column(d, items: items.filter { cal.isDate($0.start, inSameDayAs: d) }) }
                        }
                    }
                }
                .frame(maxWidth: 1400, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Calendar")
    }

    private func header(start: Date, end: Date, count: Int) -> some View {
        let last = cal.date(byAdding: .day, value: -1, to: end)!
        return VStack(alignment: .leading, spacing: 10) {
            TypewriterTitle(text: "> calendar")
            HStack {
                Text("\(start.short().uppercased()) – \(last.short().uppercased())").font(.callout.weight(.semibold)).foregroundStyle(Tech.text2)
                Spacer(minLength: 16)
                HStack(spacing: 8) {
                    BoardButton(glow: Tech.neon) { offset -= 1 } label: { label(Image(systemName: "chevron.left")) }
                        .accessibilityLabel("Previous week")
                    BoardButton(glow: Tech.neon) { offset = 0 } label: { label(Text("This week")) }.opacity(offset == 0 ? 0.5 : 1)
                    BoardButton(glow: Tech.neon) { offset += 1 } label: { label(Image(systemName: "chevron.right")) }
                        .accessibilityLabel("Next week")
                }
            }
            Text("\(count) item\(count == 1 ? "" : "s") from Outlook").font(.caption).foregroundStyle(Tech.text)
        }
    }

    private func label(_ content: some View) -> some View {
        content.font(.caption.weight(.semibold)).foregroundStyle(Tech.text).padding(.horizontal, 10).padding(.vertical, 6)
    }

    private func column(_ day: Date, items: [OutlookCalendar.Occurrence]) -> some View {
        let today = cal.isDateInToday(day)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased()).font(.caption.weight(.bold)).foregroundStyle(today ? Tech.neon : Tech.text)
                Text(day.formatted(.dateTime.day())).font(.caption).foregroundStyle(Tech.text2)
                if today { Text("TODAY").font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(Tech.neon) }
            }
            if items.isEmpty { Text("— free —").font(.caption2).foregroundStyle(Tech.text3).padding(.vertical, 6) }
            ForEach(items) { card($0) }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(8)
        .techPanel(radius: 8)
        .overlay { if today { RoundedRectangle(cornerRadius: 8).strokeBorder(Tech.neon.opacity(0.6)) } }
    }

    private func card(_ o: OutlookCalendar.Occurrence) -> some View {
        let course = Moodle.route(o.title, store.subjects).map { store.subjects[$0] }
        let accent = course?.hue.palette.accent ?? Tech.text3
        let time = "\(hm(o.start))–\(hm(o.end))"
        return HStack(alignment: .top, spacing: 6) {
            accent.frame(width: 3).clipShape(Capsule())
            VStack(alignment: .leading, spacing: 2) {
                Text(time).font(.caption2).foregroundStyle(Tech.text2).monospacedDigit()
                Text(o.title).font(.caption.weight(.semibold)).foregroundStyle(Tech.text).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                if !o.location.isEmpty { Text(o.location).font(.caption2).foregroundStyle(Tech.text3).lineLimit(1) }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(String([o.title, o.location, o.notes].filter { !$0.isEmpty }.joined(separator: "\n").prefix(600)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(o.title), \(time)\(o.location.isEmpty ? "" : ", \(o.location)")")
    }

    private func hm(_ d: Date) -> String {
        let c = cal.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
