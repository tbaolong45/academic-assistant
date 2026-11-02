import SwiftUI

// Shared look-and-motion toolkit for the "terminal" theme. Every continuous animation stops under Reduce Motion.

/// Animated backdrop: faint green grid, a slow scanline sweep and a corner glow.
struct TechBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                var grid = Path()
                let step: CGFloat = 28
                for x in stride(from: 0, through: size.width, by: step) { grid.move(to: .init(x: x, y: 0)); grid.addLine(to: .init(x: x, y: size.height)) }
                for y in stride(from: 0, through: size.height, by: step) { grid.move(to: .init(x: 0, y: y)); grid.addLine(to: .init(x: size.width, y: y)) }
                ctx.stroke(grid, with: .color(Tech.neon.opacity(0.045)), lineWidth: 1)

                ctx.fill(Path(ellipseIn: CGRect(x: size.width - 420, y: -260, width: 640, height: 520)),
                         with: .radialGradient(Gradient(colors: [Tech.neon.opacity(0.10), .clear]),
                                               center: .init(x: size.width - 100, y: 0), startRadius: 0, endRadius: 360))

                if !reduceMotion {
                    let band: CGFloat = 140
                    let y = CGFloat(t.truncatingRemainder(dividingBy: 9) / 9) * (size.height + band) - band
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: band)),
                             with: .linearGradient(Gradient(colors: [.clear, Tech.neon.opacity(0.045), .clear]),
                                                   startPoint: .init(x: 0, y: y), endPoint: .init(x: 0, y: y + band)))
                }
            }
        }
        .background(Tech.bg)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    /// Card surface: panel fill + hairline border; when `active`, it lifts to `panelHi` with a glow border in `glow`.
    func techPanel(active: Bool = false, glow: Color = Tech.neon, radius: CGFloat = 10) -> some View {
        modifier(TechPanel(active: active, glow: glow, radius: radius))
    }

    /// Entrance animation: fades, rises and un-blurs into place, delayed by `index` for a cascade.
    func stagger(_ index: Int) -> some View { modifier(Stagger(index: index)) }

    /// Repeating glow pulse, e.g. for a deadline that is close.
    func pulse(_ active: Bool = true, color: Color = Tech.neon) -> some View { modifier(Pulse(active: active, color: color)) }
}

private struct TechPanel: ViewModifier {
    let active: Bool, glow: Color, radius: CGFloat
    func body(content: Content) -> some View {
        content
            .background(active ? Tech.panelHi : Tech.panel, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(active ? glow.opacity(0.8) : Tech.line, lineWidth: 1))
            .shadow(color: glow.opacity(active ? 0.35 : 0), radius: 14)
            .animation(.easeOut(duration: 0.18), value: active)
    }
}

private struct Stagger: ViewModifier {
    let index: Int
    @Local private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .blur(radius: shown || reduceMotion ? 0 : 6)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.06)) { shown = true }
            }
    }
}

private struct Pulse: ViewModifier {
    let active: Bool, color: Color
    @Local private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background {
                if active && !reduceMotion {
                    Circle().stroke(color, lineWidth: 2)
                        .scaleEffect(on ? 2.6 : 1).opacity(on ? 0 : 0.8)
                        .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: on)
                }
            }
            .onAppear { on = true }
    }
}

/// "// THIS WEEK ─────" terminal-style section heading.
struct SectionLabel: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Text("//").foregroundStyle(Tech.neon)
            Text(text.uppercased()).foregroundStyle(Tech.text2).tracking(1.6)
            Rectangle().fill(Tech.line).frame(height: 1)
        }
        .font(.caption.weight(.semibold))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isHeader)
    }
}

extension SectionLabel {
    init(_ text: String) { self.init(text: text) }
}

/// Types its text out once on appear, followed by a blinking block cursor.
struct TypewriterTitle: View {
    let text: String
    @Local private var count = 0
    @Local private var cursorOn = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            Text(String(text.prefix(count))).foregroundStyle(Tech.text)
            Rectangle().fill(Tech.neon).frame(width: 10, height: 22).opacity(cursorOn ? 1 : 0)
        }
        .font(.system(size: 22, weight: .bold, design: .monospaced))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isHeader)
        .task(id: text) {
            if reduceMotion { count = text.count; return }
            count = 0
            for i in 1...max(text.count, 1) {
                try? await Task.sleep(for: .milliseconds(38))
                count = i
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(530))
                cursorOn.toggle()
            }
        }
    }
}
