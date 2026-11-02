import AppKit
import SwiftUI

/// One colour in both appearances (hex without "#"). `color` follows the window's light/dark appearance.
struct Token: Sendable {
    let light, dark: String
    var color: Color { Color(light: light, dark: dark) }
}

/// Direction A "Campus" (docs/design/ui-redesign.md §4): every text pair ≥ 4.5:1 in both appearances (dataviz validator;
/// worst: text3 on raised 4.81 light, onAccent on accent 5.58 dark; dark retuned in U1c, §6.1). Blue belongs to the UI only, never to a course.
enum Palette {
    static let bg = Token(light: "f4f6fa", dark: "060c18") // window background
    static let surface = Token(light: "ffffff", dark: "141b2c") // cards, sheets
    static let raised = Token(light: "eef2f8", dark: "222c41") // hovered or selected rows, inputs
    static let line = Token(light: "d9e0ea", dark: "394459") // decorative hairlines only (~1.3:1): never a control's only edge
    static let text = Token(light: "0f172a", dark: "f4f7fc")
    static let text2 = Token(light: "475569", dark: "cad3e4")
    static let text3 = Token(light: "5f6b7d", dark: "a6b0c3")
    static let accent = Token(light: "2563eb", dark: "3d89ff") // blue fills: primary button, selection bar, today marker
    static let onAccent = Token(light: "ffffff", dark: "081123") // text on `accent`
    static let accentInk = Token(light: "1d4fc4", dark: "7db3ff") // blue text and icons
    static let accentSoft = Token(light: "e6eefd", dark: "1a3467") // blue wash behind a selected row or chip
    // Status (dataviz reference set, the same in both appearances). Always with an icon and a label, never colour alone.
    static let good = Token(light: "0ca30c", dark: "49df6e")
    static let warning = Token(light: "fab219", dark: "ffc347")
    static let critical = Token(light: "d03b3b", dark: "fe726e")
}

/// Old names kept for one step so every view compiles on the new palette; U6 renames the uses and deletes this.
enum Tech {
    static var bg: Color { Palette.bg.color }
    static var panel: Color { Palette.surface.color }
    static var panelHi: Color { Palette.raised.color }
    static var line: Color { Palette.line.color }
    static var text: Color { Palette.text.color }
    static var text2: Color { Palette.text2.color }
    static var text3: Color { Palette.text3.color }
    static var neon: Color { Palette.accentInk.color } // mostly text and icons, which need accentInk's 4.5:1
}

extension Color {
    init(hex: String) {
        let v = UInt32(hex, radix: 16) ?? 0
        self.init(.sRGB, red: Double(v >> 16 & 0xff) / 255, green: Double(v >> 8 & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

// Course colours (ui-redesign.md §3). Ramps by weight band 0...3 (<5, 5–15, 15–30, >30%): light runs light→dark, dark runs
// dark→bright, so heavier weight is stronger in both (validateOrdinal PASS against Palette.surface in each appearance).
// `mark` is the categorical accent for dots, edges and swatches. Text never uses these; the course name sits beside them.
struct HuePalette {
    let ramp: [Token]
    let mark: Token
    let wash: Token // card background wash (body text and text3 stay ≥ 4.5:1 on it)
    var shades: [Color] { ramp.map(\.color) }
    var accent: Color { mark.color }
    var tint: Color { wash.color }
}

extension Hue {
    var palette: HuePalette {
        func p(_ light: [String], _ dark: [String], mark: (String, String), wash: (String, String)) -> HuePalette {
            HuePalette(ramp: zip(light, dark).map(Token.init), mark: Token(light: mark.0, dark: mark.1), wash: Token(light: wash.0, dark: wash.1))
        }
        return switch self {
        case .green: p(["77c4a3", "24ab7e", "078661", "015f43"], ["047554", "089e72", "05c992", "77efbf"], mark: ("047554", "009068"), wash: ("e6f1ee", "063223"))
        case .orange: p(["dfa17c", "d07940", "af5504", "7d3a01"], ["9a4825", "d55c27", "ff8350", "fec5b0"], mark: ("9a4901", "c14802"), wash: ("f5ede6", "412013"))
        case .yellow: p(["c9ae6d", "b38c15", "8d6d01", "644c00"], ["7b5f01", "a58108", "d2a402", "f8cf68"], mark: ("c39806", "b48c05"), wash: ("f9f5e6", "352803"))
        case .magenta: p(["dd9ab9", "cc6f9d", "af467e", "7e2e59"], ["95426a", "cd5590", "ff72b7", "ffbfda"], mark: ("c0558d", "e4569e"), wash: ("f9eef4", "3e1e2d"))
        case .violet: p(["baa4e2", "9f7ed6", "8059bb", "5b3d87"], ["734f99", "9e68d5", "c48cfe", "e0c8fe"], mark: ("ad87ed", "914ad0"), wash: ("f7f3fd", "302340"))
        case .slate: p(["a3acb9", "7f8a9a", "5e6a7b", "3e4857"], ["596475", "7b8799", "9facbe", "c8d5e8"], mark: ("5e6a7b", "9facbe"), wash: ("eff0f2", "242c38"))
        // Legacy: old caches and the sample data still say "blue". Not handed out any more (it would read as UI blue).
        case .blue: p(["85b4f0", "5591dd", "2d6fbe", "154d8c"], ["2d4e78", "3d73b6", "5b9df0", "9eceff"], mark: ("2d6fbe", "5b9df0"), wash: ("e9f3ff", "142234"))
        }
    }
}

extension Color {
    /// A colour that follows the window's light/dark appearance.
    init(light: String, dark: String) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            NSColor(hex: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(hex: String) {
        let v = UInt32(hex, radix: 16) ?? 0
        self.init(srgbRed: CGFloat(v >> 16 & 0xff) / 255, green: CGFloat(v >> 8 & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
}

extension Date {
    /// "Sat 10 Oct 2026" / "Fri 30 Oct"
    func short(year: Bool = false) -> String {
        formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year(year ? .defaultDigits : .omitted).locale(Locale(identifier: "en_GB")))
            .replacingOccurrences(of: ",", with: "")
    }
}

// The Command Line Tools ship SwiftUI without its macro plugin, so `@State` (a macro in this SDK) fails to compile.
// `@Local` names the plain State property wrapper instead. Use `@Local` everywhere; switch back to `@State` if Xcode is installed.
typealias Local = SwiftUICore.State
