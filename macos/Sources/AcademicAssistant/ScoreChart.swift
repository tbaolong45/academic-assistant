import SwiftUI

/// Running grade + what-if simulator + one column per assessment (completed = filled to score, upcoming = dashed full-height outline).
/// Drawn with plain shapes rather than Swift Charts: outlined bars and multi-line labels under columns are simpler this way.
struct ScoreChart: View {
    let subject: Subject

    @Local private var selected: Assessment?
    @Local private var hovered: String?
    @Local private var focus = 0 // keyboard-highlighted column
    @Local private var assumed: [String: Double] = [:] // what-if scores for upcoming assessments
    @Local private var grown = false // bars rise from the baseline once on appear
    @Local private var shown = 0.0 // running grade as it counts up
    @FocusState private var chartFocused: Bool
    @Environment(\.pixelLength) private var hairline
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let ticks = [0, 25, 50, 75, 100]
    private let plot: CGFloat = 220 // bar track height
    private let head: CGFloat = 22 // room for the value label above a 100% bar
    private let gap: CGFloat = 4

    var body: some View {
        // GeometryReader reports the width the pane is *offered*, independent of our content — so the wide
        // layout can never prop the pane open (measuring our own size did, overflowing narrow windows).
        GeometryReader { geo in
            let width = geo.size.width
            let palette = subject.hue.palette
            let wide = width >= 900
            // Free width for columns: page padding 48, card padding 32, y axis 40 + 8.
            let perColumn = (width - 128) / CGFloat(max(subject.assessments.count, 1)) - gap
            let header = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 16)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header {
                        hero.frame(maxWidth: .infinity, alignment: .leading)
                        WhatIfPanel(subject: subject, assumed: $assumed).frame(maxWidth: wide ? 440 : .infinity)
                    }
                    chart(palette, columnWidth: min(max(perColumn, 64), 200), scrolls: perColumn < 64)
                    table
                }
                .padding(24)
                .frame(width: width, alignment: .leading)
                .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85), value: wide)
            }
        }
        .sheet(item: $selected) { AssessmentSheet(assessment: $0, hue: subject.hue) }
        .task(id: subject.id) { await intro() }
    }

    // MARK: - Hero

    private var hero: some View {
        let toCome = subject.stillToCome
        let done = Int((subject.assessments.reduce(0) { $0 + $1.share } - subject.stillToComeShare).rounded())
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Running grade")
            Text(subject.runningGrade == nil ? "—" : String(format: "%.1f%%", shown))
                .font(.system(size: 52, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(Palette.text.color)
                .contentTransition(.numericText(value: shown))
            ProgressView(value: Double(done), total: 100).tint(Palette.accent.color).accessibilityLabel("\(done)% of the course graded")
            Text("from \(done)% of the grade so far · \(toCome)% still to come").font(.callout).foregroundStyle(Palette.text2.color)
        }
        .padding(16)
        .card()
        .accessibilityElement(children: .combine)
    }

    /// Bars grow and the hero counts up once (instant under Reduce Motion). Nothing loops: the upcoming outlines are
    /// static dashes (the marching ants and the 35 ms count-up loop are gone).
    private func intro() async {
        let target = subject.runningGrade ?? 0
        grown = true
        if reduceMotion { shown = target; return }
        withAnimation(.easeOut(duration: 0.8)) { shown = target }
    }

    // MARK: - Chart

    private var activeIndex: Int? {
        if let h = hovered { return subject.assessments.firstIndex { $0.id == h } }
        return chartFocused ? focus : nil
    }

    /// Value the crosshair marks: the active column's score, or its what-if value.
    private var activeValue: Double? {
        guard let i = activeIndex, subject.assessments.indices.contains(i) else { return nil }
        let a = subject.assessments[i]
        return a.score.map(Double.init) ?? assumed[a.id]
    }

    private func chart(_ palette: HuePalette, columnWidth: CGFloat, scrolls: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                SectionLabel(text: "Assessments")
                Text("←/→ select · ⏎ open").font(.caption2).foregroundStyle(Palette.text3.color).fixedSize()
            }

            HStack(alignment: .top, spacing: 8) {
                // Y axis: each label's centre sits on its gridline; the crosshair chip rides over it.
                ZStack(alignment: .topTrailing) {
                    Color.clear // anchors the stack's top at 0; without it the topmost label shifts everything up
                    ForEach(ticks, id: \.self) { t in
                        Text("\(t)%").font(.caption2).foregroundStyle(Palette.text3.color).monospacedDigit()
                            .alignmentGuide(.top) { $0[VerticalAlignment.center] - y(Double(t)) }
                    }
                    if let v = activeValue {
                        Text("\(Int(v))%").font(.caption2.bold()).foregroundStyle(Palette.text.color).monospacedDigit()
                            .padding(.horizontal, 3).padding(.vertical, 1)
                            .background(Palette.raised.color, in: RoundedRectangle(cornerRadius: 3))
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Palette.accent.color, lineWidth: 1))
                            .alignmentGuide(.top) { $0[VerticalAlignment.center] - y(v) }
                            .transition(.opacity)
                    }
                }
                .frame(width: 40, height: head + plot, alignment: .topTrailing)
                .accessibilityHidden(true)

                plotArea(palette, columnWidth: columnWidth, scrolls: scrolls)
                    .background(alignment: .top) {
                        ZStack(alignment: .top) {
                            Color.clear.frame(height: head + plot) // same anchor as the y axis
                            ForEach(ticks, id: \.self) { t in
                                let dy = y(Double(t))
                                Rectangle().fill(Palette.line.color).frame(height: hairline).alignmentGuide(.top) { _ in -dy }
                            }
                        }
                        .accessibilityHidden(true)
                    }
            }
            .animation(.easeOut(duration: 0.18), value: activeValue)

            legend(palette)
        }
        .padding(16)
        .card(active: chartFocused)
        .focusable()
        .focused($chartFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { move(-1) }
        .onKeyPress(.rightArrow) { move(1) }
        .onKeyPress(.return) { open() }
        .onKeyPress(.space) { open() }
    }

    private func move(_ by: Int) -> KeyPress.Result {
        hovered = nil
        guard !subject.assessments.isEmpty else { return .ignored }
        focus = min(max(focus + by, 0), subject.assessments.count - 1)
        return .handled
    }

    private func open() -> KeyPress.Result {
        guard subject.assessments.indices.contains(focus) else { return .ignored }
        selected = subject.assessments[focus]
        return .handled
    }

    @ViewBuilder
    private func plotArea(_ palette: HuePalette, columnWidth: CGFloat, scrolls: Bool) -> some View {
        let columns = HStack(alignment: .top, spacing: gap) {
            ForEach(Array(subject.assessments.enumerated()), id: \.element.id) { i, a in
                column(a, i, palette, width: columnWidth)
            }
        }
        .overlay(alignment: .top) { crosshair }

        if scrolls {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) { columns }
                    .onChange(of: focus) { _, f in withAnimation { proxy.scrollTo(subject.assessments[f].id) } }
            }
        } else {
            columns
        }
    }

    /// Dashed line across the plot at the active column's value.
    private var crosshair: some View {
        ZStack(alignment: .top) {
            Color.clear.frame(height: head + plot)
            if let v = activeValue {
                HLine().stroke(Palette.accent.color, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(height: 1)
                    .alignmentGuide(.top) { _ in -y(v) }
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Distance from the top of the column to the gridline for `t`%.
    nonisolated private func y(_ t: Double) -> CGFloat { head + plot * (1 - CGFloat(t) / 100) }

    private func column(_ a: Assessment, _ i: Int, _ palette: HuePalette, width: CGFloat) -> some View {
        let shade = palette.shades[band(Int(a.share.rounded()))]
        let bar = UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4)
        let active = activeIndex == i
        let ghost = a.score == nil ? assumed[a.id] : nil
        let value = a.score.map { "\($0)%" } ?? ghost.map { "~\(Int($0))%" } ?? "upcoming"
        let status = a.score.map { "scored \($0)%" } ?? ghost.map { "upcoming, assuming \(Int($0))%" } ?? "upcoming"

        return Button { focus = i; selected = a } label: {
            VStack(spacing: 6) {
                VStack(spacing: 4) {
                    Spacer(minLength: 0)
                    Text(value).font(.caption).foregroundStyle(active ? Palette.text.color : Palette.text2.color).monospacedDigit()
                        .contentTransition(.numericText())
                    Group {
                        if let score = a.score {
                            bar.fill(shade).frame(height: grown ? plot * CGFloat(score) / 100 : 0)
                        } else {
                            bar.strokeBorder(shade, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                                .background(alignment: .bottom) {
                                    bar.fill(shade.opacity(0.35))
                                        .frame(height: plot * CGFloat(ghost ?? 0) / 100)
                                        .opacity(ghost == nil ? 0 : 1)
                                        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.7), value: ghost)
                                }
                                .frame(height: grown ? plot : 0)
                        }
                    }
                    .frame(width: 28)
                }
                .frame(height: head + plot)
                .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.72).delay(Double(i) * 0.08), value: grown)

                VStack(spacing: 2) {
                    Text(a.name).font(.caption).foregroundStyle(Palette.text.color).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                    Text(a.weightText).font(.caption2).foregroundStyle(Palette.text3.color)
                }
                .frame(height: 44, alignment: .top) // room for a 2-line name; weight stays right under it
            }
            .frame(width: width)
            .padding(.bottom, 8)
            .contentShape(Rectangle())
            .background(active ? Palette.raised.color : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if chartFocused && focus == i { RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.accent.color, lineWidth: 1.5) }
            }
            .animation(.easeOut(duration: 0.15), value: active)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? a.id : (hovered == a.id ? nil : hovered) }
        .help("\(a.name): \(value), \(a.weightText) of course grade")
        .accessibilityLabel("\(a.name): \(status), \(a.weightText) of course grade")
    }

    private func legend(_ palette: HuePalette) -> some View {
        let title = Text("Shade = share of course grade").foregroundStyle(Palette.text2.color)
        let swatches = HStack(spacing: 12) {
            ForEach(bandLabels.indices, id: \.self) { i in
                Label { Text(bandLabels[i]).foregroundStyle(Palette.text2.color) } icon: {
                    RoundedRectangle(cornerRadius: 2).fill(palette.shades[i]).frame(width: 12, height: 12)
                }
            }
            Label { Text("Upcoming").foregroundStyle(Palette.text2.color) } icon: {
                RoundedRectangle(cornerRadius: 2).strokeBorder(Palette.text2.color, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])).frame(width: 12, height: 12)
            }
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { title; swatches }
            VStack(alignment: .leading, spacing: 8) { title; swatches }
        }
        .font(.caption)
        .labelStyle(.titleAndIcon)
    }

    private var table: some View {
        DisclosureGroup("Show as table") {
            Table(subject.assessments) {
                TableColumn("Assessment", value: \.name)
                TableColumn("Date") { Text($0.date.short(year: true)) }
                TableColumn("Score") { Text($0.score.map { "\($0)%" } ?? "—").monospacedDigit() }
                TableColumn("Weight") { Text($0.weightText).monospacedDigit() }
                TableColumn("Status") { Text($0.score == nil ? "Upcoming" : "Graded") }
            }
            .scrollContentBackground(.hidden)
            .frame(height: 200)
            .card()
            .padding(.top, 8)
        }
        .foregroundStyle(Palette.text.color)
    }
}

/// Horizontal line through the middle of its frame (for dashed strokes).
private struct HLine: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.midY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        }
    }
}
