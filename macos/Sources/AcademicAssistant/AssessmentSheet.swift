import SwiftUI

/// Detail for one assessment, presented as a sheet from ScoreChart. Esc closes it.
struct AssessmentSheet: View {
    let assessment: Assessment
    let hue: Hue

    @Local private var progress = 0.0 // score ring fill, animates up on appear
    @Local private var spin = false // upcoming ring rotation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let a = assessment
        let shade = hue.palette.shades[band(Int(a.share.rounded()))]

        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(a.name).font(.title2.bold()).foregroundStyle(Tech.text)
                    Text(a.type.rawValue.uppercased())
                        .font(.caption2.bold()).tracking(1.4).foregroundStyle(Tech.text)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .overlay(Capsule().strokeBorder(Tech.neon.opacity(0.7), lineWidth: 1))
                }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }

            HStack(alignment: .center, spacing: 22) {
                ring(a, shade)
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                    row("Type", a.type.rawValue)
                    row("Date", a.date.short(year: true))
                    row("Raw score", a.raw.map { "\($0.got) / \($0.max)" } ?? "—")
                    row("Score", a.score.map { "\($0)%" } ?? "—")
                    GridRow {
                        Text("Weight").foregroundStyle(Tech.text2)
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(shade).frame(width: 12, height: 12)
                            Text(a.weightText).foregroundStyle(Tech.text)
                            Text("· \(bandLabels[band(Int(a.share.rounded()))]) band").foregroundStyle(Tech.text2)
                        }
                    }
                }
                .font(.callout)
            }

            if let fb = a.feedback {
                SectionLabel(text: "teacher feedback")
                Text(fb).font(.callout).foregroundStyle(Tech.text).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SectionLabel(text: "topics covered")
            // Chips in one row when they fit, stacked otherwise.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { chips(a.topics, shade) }
                VStack(alignment: .leading, spacing: 6) { chips(a.topics, shade) }
            }
        }
        .padding(22)
        .frame(width: 480, alignment: .leading)
        .background(Tech.panel)
        .overlay(Rectangle().strokeBorder(Tech.neon.opacity(0.5), lineWidth: 1))
        .onAppear {
            guard let s = a.score else {
                if !reduceMotion { withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) { spin = true } }
                return
            }
            if reduceMotion { progress = Double(s) / 100 }
            else { withAnimation(.spring(response: 1.1, dampingFraction: 0.8).delay(0.15)) { progress = Double(s) / 100 } }
        }
    }

    /// Score ring filling to the score; for upcoming items a dashed, slowly rotating ring.
    private func ring(_ a: Assessment, _ shade: Color) -> some View {
        ZStack {
            Circle().stroke(Tech.line, lineWidth: 8)
            if a.score != nil {
                Circle().trim(from: 0, to: progress)
                    .stroke(shade, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: shade.opacity(0.7), radius: 8)
            } else {
                Circle().stroke(shade, style: StrokeStyle(lineWidth: 3, dash: [6, 6]))
                    .rotationEffect(.degrees(spin ? 360 : 0))
            }
            VStack(spacing: 2) {
                Text(a.score.map { "\($0)%" } ?? "—").font(.title2.bold()).foregroundStyle(Tech.text).monospacedDigit()
                Text(a.score == nil ? "upcoming" : "score").font(.caption2).foregroundStyle(Tech.text3)
            }
        }
        .frame(width: 112, height: 112)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a.score.map { "Score \($0)%" } ?? "Upcoming, not graded yet")
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(Tech.text2)
            Text(value).foregroundStyle(Tech.text)
        }
    }

    private func chips(_ topics: [String], _ edge: Color) -> some View {
        ForEach(Array(topics.enumerated()), id: \.offset) { i, t in
            Text(t).font(.callout).foregroundStyle(Tech.text)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Tech.panelHi, in: Capsule())
                .overlay(Capsule().strokeBorder(edge.opacity(0.6), lineWidth: 1))
                .stagger(i + 2)
        }
    }
}
