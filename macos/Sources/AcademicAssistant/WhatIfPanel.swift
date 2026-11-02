import SwiftUI

/// Grade simulator: drag a slider per upcoming assessment to see the projected course grade, and what a target needs.
/// Hidden when nothing is upcoming.
struct WhatIfPanel: View {
    let subject: Subject
    @Binding var assumed: [String: Double]

    @Local private var target = 80.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let upcoming = subject.assessments.filter { $0.score == nil }
        if !upcoming.isEmpty {
            let base = subject.runningGrade ?? 0
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    SectionLabel(text: "What-if simulator")
                    Button("Reset") {
                        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.5, dampingFraction: 0.7)) { assumed = [:] }
                    }
                    .disabled(assumed.isEmpty)
                }

                ForEach(upcoming) { slider($0, base) }

                projection(base)

                HStack(spacing: 10) {
                    Text("Target").font(.caption).foregroundStyle(Palette.text2.color)
                    Picker("Target", selection: $target) {
                        ForEach([70.0, 80, 90], id: \.self) { Text("\(Int($0))%").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                if let need = subject.needed(for: target) {
                    Text(need > 100 ? "✕ Out of reach (needs avg \(fmt(need))%)"
                         : need <= 0 ? "✓ Already secured"
                         : "→ Need avg \(fmt(need))% on the remaining \(subject.stillToCome)%")
                        .font(.callout).foregroundStyle(Palette.text.color)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: target)
                }
            }
            .padding(16)
            .card()
        }
    }

    private func slider(_ a: Assessment, _ base: Double) -> some View {
        let value = assumed[a.id] ?? base
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(subject.hue.palette.shades[band(Int(a.share.rounded()))]).frame(width: 10, height: 10)
                Text(a.name).foregroundStyle(Palette.text.color).lineLimit(1)
                Text(a.weightText).foregroundStyle(Palette.text3.color)
                Spacer(minLength: 4)
                Text("\(Int(value.rounded()))%").foregroundStyle(assumed[a.id] == nil ? Palette.text2.color : Palette.text.color).monospacedDigit()
                    .contentTransition(.numericText(value: value))
            }
            .font(.caption)
            // No `step:` — on macOS that draws a tick mark per step (100 ticks). Round in the setter instead.
            Slider(value: Binding(get: { assumed[a.id] ?? base }, set: { assumed[a.id] = $0.rounded() }), in: 0...100)
                .controlSize(.small)
                .accessibilityLabel("\(a.name) assumed score")
                .accessibilityValue("\(Int(value.rounded()))%")
        }
    }

    private func projection(_ base: Double) -> some View {
        // Untouched sliders count at the value they display (the running grade), so the projection matches what's on screen.
        let shown = Dictionary(uniqueKeysWithValues: subject.assessments.filter { $0.score == nil }.map { ($0.id, assumed[$0.id] ?? base) })
        let p = subject.projected(shown) ?? base
        let delta = ((p - base) * 10).rounded() / 10
        let (glyph, tone): (String, Color) = delta > 0 ? ("▲ +", Palette.accentInk.color) : delta < 0 ? ("▼ −", Palette.text2.color) : ("= ±", Palette.text3.color)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Projected").font(.caption).foregroundStyle(Palette.text2.color)
            Text(fmt(p) + "%")
                .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Palette.text.color)
                .contentTransition(.numericText(value: p))
            Text(glyph + fmt(abs(delta))).font(.callout.bold()).foregroundStyle(tone)
                .contentTransition(.numericText(value: delta))
        }
        .animation(.snappy(duration: 0.25), value: p)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Projected grade \(fmt(p))%, \(delta >= 0 ? "up" : "down") \(fmt(abs(delta))) from the running grade")
    }

    private func fmt(_ x: Double) -> String { String(format: "%.1f", x) }
}
