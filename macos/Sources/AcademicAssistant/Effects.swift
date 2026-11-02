import SwiftUI

// Shared look-and-motion toolkit, "Campus" style (docs/design/ui-redesign.md §2 A). Nothing here animates forever:
// the old grid/scanline backdrop, typewriter and pulse rings kept the app at 35–45 % CPU while idle.

extension View {
    /// Card surface: `surface` fill and a hairline; when `active` (hovered/selected) it lifts to `raised` with a blue edge.
    /// A soft shadow only in light mode; dark mode separates cards by fill.
    func card(active: Bool = false, radius: CGFloat = 12) -> some View { modifier(Card(active: active, radius: radius)) }

    /// Entrance animation: fades and rises into place, delayed by `index` for a cascade. Nothing under Reduce Motion.
    func stagger(_ index: Int) -> some View { modifier(Stagger(index: index)) }
}

private struct Card: ViewModifier {
    let active: Bool, radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(active ? Palette.raised.color : Palette.surface.color, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(active ? Palette.accent.color : Palette.line.color, lineWidth: 1))
            .shadow(color: .black.opacity(scheme == .light ? 0.06 : 0), radius: 3, y: 1) // blur 6 ≈ radius 3
            .animation(.easeOut(duration: 0.18), value: active)
    }
}

private struct Stagger: ViewModifier {
    let index: Int
    @Local private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85).delay(Double(index) * 0.05)) { shown = true }
            }
    }
}

/// Sentence-case section heading ("This week"), marked as a header for VoiceOver.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.prefix(1).uppercased() + text.dropFirst())
            .font(.title3.weight(.semibold))
            .foregroundStyle(Palette.text.color)
            .accessibilityAddTraits(.isHeader)
    }
}

extension SectionLabel {
    init(_ text: String) { self.init(text: text) }
}
