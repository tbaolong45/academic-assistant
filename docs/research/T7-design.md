# Task T7 Research Report: macOS 26 Design Guidance, Student-App Patterns & Accessible Blues (Focused on Direction A "Campus")

Scope: supports [`docs/design/ui-redesign.md`](../design/ui-redesign.md) after the user selected **Direction A "Campus"** (`D1`), **system Light/Dark appearance** (`D2`), **macOS 26 deployment target** (`D3`: `swift-tools-version: 6.2`, `.macOS(.v26)`), and **blue reserved for UI with green/orange/yellow/magenta/violet course hues** (`D4`).

Verification legend:
- **`[Verified]`** — checked directly against Apple's Human Interface Guidelines / SwiftUI documentation, the installed macOS 26.7.2 / Swift 6.4 Command Line Tools SDK (`MacOSX27.0.sdk` `.swiftinterface` files), WCAG 2.1 / OKLab ΔE×100 / Viénot (1999) CVD calculations run locally, or current Swift files in `macos/Sources/AcademicAssistant/`.
- **`[Inferred]`** — design recommendations and implementation guidance derived from those verified facts for Campus build steps `U2`–`U6`.

---

## 1. Apple macOS 26 Design Guidance (HIG) & SwiftUI APIs for "Campus"

### 1.1 How macOS 26 ("Tahoe") Liquid Glass Fits Direction A "Campus"

Apple's macOS 26 Human Interface Guidelines establish a strict two-layer rule that aligns directly with **Campus** ([Materials](https://developer.apple.com/design/human-interface-guidelines/materials), [Layout](https://developer.apple.com/design/human-interface-guidelines/layout), [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)):

1. **Navigation & chrome float in Liquid Glass; content stays on opaque/semantic surfaces (`[Verified]` HIG):**
   - Apple's guidance explicitly restricts Liquid Glass to the **functional navigation and control layer** floating above content (sidebars, toolbars, segmented/capsule toolbar groups, menus, popovers).
   - **Content views** — cards, tables, multi-column boards, KPI tiles, and reading panes — belong on solid background and surface hierarchy (`Palette.bg` → `Palette.surface` → `Palette.raised`), **never** glass-on-glass. When compiled against the macOS 26 SDK (`platforms: [.macOS(.v26)]`), `NavigationSplitView`, window toolbars, menus, and popovers adopt Liquid Glass automatically without custom `.glassEffect(...)` calls on content cards.
2. **Sidebars ([HIG: Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)) (`[Verified]`):**
   - In macOS 26, a `NavigationSplitView` sidebar floats as an inset translucent Liquid Glass pane with concentric corner radii matching the window frame; detail content can extend beneath it (`backgroundExtensionEffect()`) or sit beside it on `Palette.bg`.
   - Section headers in sidebars use **sentence case or subtle subheadline/caption weight** without terminal tracking (`"Courses"` rather than `"COURSES"` tracked `+1.6pt`), and row icons use **SF Symbols** (`.medium` scale, consistent width) tinted either by selection (`Palette.accentInk`) or semantic secondary ink (`Palette.text2`), while course rows use an `8pt` flat colour dot (no neon drop-shadow).
3. **Toolbars ([HIG: Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)) (`[Verified]`):**
   - macOS 26 groups related toolbar controls into floating capsule clusters and introduces `ToolbarSpacer` (`.fixed` / `.flexible`) to separate logical groups (e.g., week navigation `‹ Today ›` vs. `[To submit | Events | All]` segmented picker vs. `Filter` menu).
   - Avoid duplicating a window title inside both the toolbar and an oversized custom header if `.navigationTitle(_:)` / `.navigationSubtitle(_:)` is visible; for Campus's editorial `"Good morning · Monday 2 November"` Overview header, keep the toolbar clean (actions/filters only, or `.toolbarTitleDisplayMode(.inline)` where appropriate).
4. **Typography ([HIG: Typography](https://developer.apple.com/design/human-interface-guidelines/typography)) (`[Verified]`):**
   - **SF Pro** (default system design once `.fontDesign(.monospaced)` is removed) provides automatic optical sizing and legibility across Light and Dark appearances.
   - Use **sentence case** for headings, buttons, badges, and empty states; reserve `.monospacedDigit()` strictly for live numbers, grades, dates, and countdowns (`86.4%`, `2d 14h`, `Tue 10 Nov`) so columns align and timers never jitter horizontally.
   - `.fontDesign(.rounded)` on large KPI numerals (`34pt` bold) softens statistical figures without hurting scan speed (`[Inferred]`, consistent with Apple Fitness/Reminders summary tiles).

### 1.2 SwiftUI APIs & Minimum macOS Versions (`[Verified]` in `MacOSX27.0.sdk`)

All declarations below were verified in `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/{SwiftUI,SwiftUICore}.framework/.../arm64e-apple-macos.swiftinterface`. None of these APIs use Swift macros, so **all compile cleanly under Command Line Tools without Xcode** (`@Local` = `SwiftUICore.State` remains required for view state).

| Area | SwiftUI API (verified SDK signature) | Min macOS | Role in Direction A "Campus" (`U2`–`U5`) |
|---|---|---|---|
| **Package target** | `// swift-tools-version: 6.2` + `platforms: [.macOS(.v26)]` | **26.0** (Swift ≥ 6.2; host has 6.4) | Enables automatic macOS 26 Liquid Glass window/sidebar/toolbar metrics and removes `#available` guards (`U3`). |
| **Split shell** | `NavigationSplitView(sidebar:detail:)` + `.navigationSplitViewColumnWidth(min:ideal:max:)` | **13.0** | Automatic floating Liquid Glass sidebar on macOS 26 (`min: 210–220, ideal: 240, max: 300` once proportional SF Pro replaces monospaced). |
| **Sidebar scroll edge** | `.scrollEdgeEffectStyle(_ style: ScrollEdgeEffectStyle?, for edges: Edge.Set)` (`.automatic`, `.soft`, `.hard`) & `.scrollEdgeEffectHidden(_:for:)` | **26.0** | Softens scrolled list/board content passing under a toolbar or pinned sidebar footer (`SyncFooter` in `.safeAreaInset(edge: .bottom)`). |
| **Under-sidebar bleed** | `.backgroundExtensionEffect()` / `.backgroundExtensionEffect(isEnabled: Bool)` | **26.0** | Optional: extends a detail background/banner smoothly under the translucent sidebar; omit on standard `Palette.bg` scroll views where default split framing is cleaner. |
| **Toolbar grouping** | `ToolbarSpacer(_ sizing: SpacerSizing = .flexible, placement: ToolbarItemPlacement = .automatic)` (`.fixed`, `.flexible`) | **26.0** | Separates Deadlines toolbar clusters (week stepper, scope picker, filter menu, sync button) into native macOS 26 toolbar groups. |
| **Toolbar capsule split** | `ToolbarContent.sharedBackgroundVisibility(_ visibility: Visibility)` | **26.0** | Pass `.hidden` on a standalone toolbar item (e.g. a subtle sync status indicator) so it doesn't merge into an adjacent control's glass capsule. |
| **Toolbar bar chrome** | `.toolbarBackgroundVisibility(_ visibility: Visibility, for bars: ToolbarPlacement...)` | **15.0** | Controls window toolbar background visibility when scrolling `HomeView` / `WeekView`. |
| **Window subtitle** | `.navigationSubtitle(_ subtitle: Text)` | **11.0** | Native macOS subtitle under `.navigationTitle` (e.g., `"Week of 2 Nov"` or `"5 courses · Synced 09:41"`). |
| **Container radii** | `ConcentricRectangle` (`Shape`) | **26.0** | Aligns inner card/banner corner curvature concentrically with outer macOS 26 window/sheet containers where nested. |
| **Window/sheet bg** | `.containerBackground(_ style: S, for: ContainerBackgroundPlacement)` (`.window`) | **14.0** | Sets `Palette.bg.color` as the window canvas without breaking sidebar translucency. |
| **Standard materials** | `Material.ultraThinMaterial`, `.thinMaterial`, `.regularMaterial`, `.thickMaterial`, `.bar` | **12.0** | Fallback/popover/header blur materials where opaque `Palette.surface` is not used. |
| **Liquid Glass primitives** *(optional in Campus)* | `.glassEffect(_ glass: Glass = .regular, in shape: some Shape)` (`Glass.regular`, `.clear`, `.identity`, `.tint(_:)`, `.interactive(_:)`), `GlassEffectContainer(spacing:)`, `.glassEffectID(_:in:)`, `.buttonStyle(.glass)` / `.glassProminent` | **26.0** | Available without `#available` once targeting `.v26`, **but Campus intentionally avoids custom glass on cards/chips** (`ui-redesign.md` §2A), using `.borderedProminent` + `.tint(Palette.accent.color)` for primary buttons. |
| **Typography** | `.fontDesign(_ design: Font.Design?)` (`.default`, `.rounded`, `.serif`, `.monospaced`) | **13.0** | Remove root `.fontDesign(.monospaced)`; apply `.fontDesign(.rounded)` selectively to 34pt KPI values. |
| **Tabular numbers** | `.monospacedDigit()` | **10.15** (`Font`), **12.0** (`Text`) | Prevents horizontal jitter in grades, percentages, badge counts, and countdowns. |
| **Numeric transitions** | `.contentTransition(.numericText(value: Double))` | **14.0** (`value:`) | Smoothly rolls KPI/hero numbers on data updates; gate animation on `!reduceMotion`. |
| **Empty states** | `ContentUnavailableView(label:description:actions:)` | **14.0** | Standard native empty/zero-result layout with SF Symbol, calm sentence-case explanation, and action button. |
| **Accessibility env** | `@Environment(\.accessibilityReduceMotion)` (`10.15`), `\.accessibilityReduceTransparency` (`10.15`), `\.accessibilityDifferentiateWithoutColor` (`10.15`), `\.colorSchemeContrast` (`10.15`), `\.pixelLength` (`10.15`) | **10.15** | Required for non-colour status cues, motion gating, and crisp 1-physical-pixel hairlines (`1 * pixelLength` or `1pt` stroke). |

 Apple references:
- [HIG: Materials](https://developer.apple.com/design/human-interface-guidelines/materials) · [HIG: Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars) · [HIG: Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) · [HIG: Typography](https://developer.apple.com/design/human-interface-guidelines/typography) · [HIG: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass) · [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)

### 1.3 Four Codebase-Specific macOS 26 Gotchas for Campus (`U2`–`U5`)

1. **Sidebar opaque override kills macOS 26 Liquid Glass (`[Verified]` in [`App.swift:127-128`](../../macos/Sources/AcademicAssistant/App.swift#L127-L128)):**
   - `RootView` currently applies `.scrollContentBackground(.hidden)` and `.background(Tech.panel)` to the sidebar `List`. Because `Tech.panel` now aliases `Palette.surface.color`, keeping `.background(...)` in `U3` will paint a flat opaque white/navy rectangle over the sidebar and **prevent macOS 26's native translucent sidebar material from appearing**.
   - **Fix for `U3` (`[Inferred]`):** Remove both `.scrollContentBackground(.hidden)` and `.background(Tech.panel)` from the sidebar `List` (let `.listStyle(.sidebar)` supply the system glass material), keep the custom `Button` rows so selection always uses `Palette.accentSoft` + `Palette.accentInk` regardless of the user's macOS accent setting, add `.listRowBackground(Color.clear)` / `.listRowSeparator(.hidden)` if default row chrome interferes, and apply `Palette.bg.color` only to the `detail:` pane.
2. **Popover monospaced override (`[Verified]` in [`WeekBoardParts.swift:284`](../../macos/Sources/AcademicAssistant/WeekBoardParts.swift#L284)):**
   - `DeadlinePreview` sets `.fontDesign(.monospaced)` directly on the popover root at line 284. Removing `.fontDesign(.monospaced)` in `App.swift:39` (`U3`) will **not** fix the deadline preview popover unless `U4` also deletes `WeekBoardParts.swift:284`.
3. **Hidden endless / 1 Hz animations outside `Effects.swift` (`[Verified]`):**
   - [`ScoreChart.swift:78`](../../macos/Sources/AcademicAssistant/ScoreChart.swift#L78) runs `withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) { ants = -10 }` (marching-ants outline on upcoming assessments). Delete this in `U5` so upcoming bars use a static dashed border, honouring `ui-redesign.md` §1 (*"Nothing loops forever"*).
   - [`HomeView.swift:55`](../../macos/Sources/AcademicAssistant/HomeView.swift#L55) and [`:82`](../../macos/Sources/AcademicAssistant/HomeView.swift#L82) run two `TimelineView(.periodic(from: .now, by: 1))` timers. Dropping the live seconds clock (`U4`) and stepping the `"2d 14h"` KPI countdown every `60` seconds (`by: 60`) eliminates 120 SwiftUI redraws per minute while idle (`[Inferred]`).
4. **Light-only card shadow (`[Inferred]` from HIG & `ui-redesign.md` §2A):**
   - In `Effects.swift` (`U2`), read `@Environment(\.colorScheme) private var scheme` inside the `card(active:)` modifier and apply `.shadow(color: .black.opacity(scheme == .light ? 0.06 : 0), radius: 6, x: 0, y: 1)` so Dark Mode cards rely strictly on surface luminance (`#0f141c` → `#171d27` → `#1f2733`) + `1pt` `Palette.line` border without muddy dark halos.

---

## 2. Student-Friendly Study & Planner App Patterns (Applied to Campus)

Across well-regarded Mac/iPad planners popular with non-technical university students — **Things 3** (Cultured Code; Apple Design Award winner), **Subjects / iStudiez Pro** (dedicated academic timetable, assignment, and weighted-grade trackers), and **Apple Reminders + Calendar** — four design patterns consistently separate approachable everyday tools from "developer dashboards" (`[Verified]` product patterns, `[Inferred]` Campus mapping; patterns only, nothing copied):

### 2.1 Triage-First Layout ("What do I touch today?" above the full horizon)
- **Pattern:** Friendly student apps never greet the user with an undifferentiated wall of 30 dated rows. They pair a **small, bounded triage zone** (2–3 items needing action *now*, with plain-language start guidance) above a **structured spatial horizon** (this week's Mon–Sun columns or chronological list), keeping full syllabus tables one click deeper inside each course.
- **Campus application (`U4`):** Keep `"Do next"` capped at 3 high-signal cards with a human reason line (`"14% · due in 11 days · start by Tue 10 Nov"`), visually distinct from the compact Mon–Sun `WeekView` cards below. Give KPI tiles breathing room (`16–20pt` internal padding, `20–24pt` section rhythm) so numbers scan in one glance.

### 2.2 Restraint in Colour Budget (~90% neutral · ~7% UI blue · ~3% course marks)
- **Pattern:** Both Things 3 and Apple Calendar/Reminders keep ~90% of pixels neutral (soft cool-white canvas + crisp white cards in light mode; calm slate-charcoal in dark mode). **One** signature blue means *"interactive, selected, or Today"*, while category/course colours appear **only as small geometric anchors** (dots, thin leading bars, or whisper-faint tint washes), never glowing borders or saturated full-card fills.
- **Campus application (`U3`–`U5`):**
  - Sidebar icons should **not** all be bright blue at rest (`App.swift:95, 99, 105` currently colours every sidebar icon `Tech.neon`); tint only the **selected** row's pill (`Palette.accentSoft`) and label/icon (`Palette.accentInk`), leaving unselected nav icons in `Palette.text2`.
  - Remove the `.shadow(color: s.hue.palette.accent, radius: 4)` glow on sidebar course dots (`App.swift:116`) — a crisp flat `8pt` circle reads like Apple Calendar/Reminders rather than an LED indicator.

### 2.3 Calm Density & Plain-Language Microcopy
- **Pattern:** Non-technical students read `ALL-CAPS TRACKED MONOSPACE`, `// SECTION`, `[PAST]`, and `[CRUNCH]` as system warnings or compiler output. Approachable planners use conversational sentence case, maximum **3 data points per compact card** (title, course dot + short name, time/weight), and progressive disclosure (click for popover/sheet with instructions, PDF excerpts, and related announcements).
- **Campus application (`U4`):**
  - Replace `"nothing due. enjoy it."` / `"— free —"` / `"SYNCED"` / `"SAMPLE DATA"` with calm sentence case (`"Synced 09:41"`, `"Sample courses"`, quiet blank day columns or a subtle `"No deadlines"` dash without em-dash ASCII framing).
  - **Avoid dimming past day columns with `.opacity(0.55)`** ([`WeekBoardParts.swift:59`](../../macos/Sources/AcademicAssistant/WeekBoardParts.swift#L59)): multiplying an entire card stack by `0.55` alpha drops `Palette.text3` below `2.5:1` contrast and makes completed/earlier-week items muddy in Light Mode. Instead, keep card surfaces opaque and render past items with `Palette.text2` titles and neutral tags (`[Inferred]`).

### 2.4 Reassuring, Actionable Empty States
- **Pattern:** For students, an empty deadline list triggers *"Did sync break, or am I actually free?"* Good student apps always answer that question in the empty state itself by distinguishing **three distinct zero states**:
  1. **Genuinely clear week:** calm positive confirmation + last sync timestamp (`"No deadlines this week"` · `"Synced with Moodle at 09:41"`), using `ContentUnavailableView` or a quiet centred card.
  2. **Filtered to zero (`To submit` / course / type filter active):** `"No matching items"` + a one-click `"Show all"` / `"Reset filters"` button so students never think deadlines vanished.
  3. **Disconnected / first launch:** clear setup prompt (`"Connect Moodle to load your courses and deadlines"`) with a primary `.borderedProminent` `"Connect…"` button.

---

## 3. Accessible Blue Palettes, Course-Colour Separation & Campus Audit

### 3.1 WCAG 2.1 Contrast of Common Blue Primaries (`[Verified]`)

Computed via exact WCAG 2.1 relative luminance in sRGB (including macOS 26.7.2's live `NSColor.systemBlue` resolved under `.aqua` and `.darkAqua`) against pure white, Campus light tokens (`bg #F4F6FA`, `accentSoft #E6EEFD`), near-black / Campus dark tokens (`bg #0F141C`, `surface #171D27`, `accentSoft #1A2A47`), and white button labels (`#FFFFFF` on blue fill):

| Blue candidate | Hex | On `#FFFFFF` (`surface` L) | On `#F4F6FA` (`bg` L) | On `#E6EEFD` (`accentSoft` L) | On `#0F141C` (`bg` D) | On `#171D27` (`surface` D) | On `#1A2A47` (`accentSoft` D) | `#FFFFFF` on blue fill |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| macOS 26 `NSColor.systemBlue` (light) | `#0088FF` | 3.52 ❌ | 3.25 ❌ | 3.02 ❌ | 5.25 ✅ | 4.81 ✅ | 4.07 ❌ | 3.52 ❌ |
| macOS 26 `NSColor.systemBlue` (dark) | `#0091FF` | 3.23 ❌ | 2.99 ❌ | 2.77 ❌ | 5.71 ✅ | 5.23 ✅ | 4.43 ❌ | 3.23 ❌ |
| Tailwind `blue-700` | `#1D4ED8` | **6.70 ✅** | **6.19 ✅** | **5.75 ✅** | 2.76 ❌ | 2.52 ❌ | 2.14 ❌ | **6.70 ✅** |
| **Campus `accentInk` (light)** | **`#1D4FC4`** | **7.08 ✅** | **6.54 ✅** | **6.07 ✅** | 2.61 ❌ | 2.39 ❌ | 2.02 ❌ | 7.08 ✅ |
| **Campus `accent` (light)** / Tailwind `blue-600` | **`#2563EB`** | **5.17 ✅** | **4.78 ✅** | **4.43 ❌** | 3.57 ❌ | 3.27 ❌ | 2.77 ❌ | **5.17 ✅** |
| **Campus `accent` (dark)** | **`#2F6FE4`** | 4.65 ✅ | 4.30 ❌ | 3.99 ❌ | 3.97 ❌ | 3.64 ❌ | 3.08 ❌ | **4.65 ✅** |
| GitHub Primer `fg.accent` | `#0969DA` | **5.19 ✅** | **4.80 ✅** | 4.45 ❌ | 3.56 ❌ | 3.26 ❌ | 2.76 ❌ | **5.19 ✅** |
| Tailwind `blue-500` | `#3B82F6` | 3.68 ❌ | 3.40 ❌ | 3.15 ❌ | 5.02 ✅ | 4.60 ✅ | 3.89 ❌ | 3.68 ❌ |
| Tailwind `blue-400` | `#60A5FA` | 2.54 ❌ | 2.35 ❌ | 2.18 ❌ | **7.26 ✅** | **6.65 ✅** | **5.63 ✅** | 2.54 ❌ |
| **Campus `accentInk` (dark)** | **`#7EAAFF`** | 2.31 ❌ | 2.14 ❌ | 1.98 ❌ | **7.99 ✅** | **7.31 ✅** | **6.19 ✅** | 2.31 ❌ |
| Tailwind `blue-300` | `#93C5FD` | 1.80 ❌ | 1.67 ❌ | 1.55 ❌ | **10.24 ✅** | **9.38 ✅** | **7.94 ✅** | 1.80 ❌ |

*(✅ = meets WCAG AA `4.5:1` for normal body/caption text; `3.0:1` suffices only for large ≥18pt/14pt-bold text or non-text UI indicators accompanied by text.)*

**Key takeaway (`[Verified]`):**
- **No single blue hex passes WCAG AA for both white-label button fills and dark-mode text**, and macOS 26's built-in `Color.blue` / `NSColor.systemBlue` (`#0088FF`) **fails 4.5:1 on white (`3.52:1`) and with white button text (`3.52:1`)**.
- Campus's split in [`Theme.swift:20-23`](../../macos/Sources/AcademicAssistant/Theme.swift#L20-L23) — `accent` (`#2563EB` / `#2F6FE4`) for **solid fills** with `onAccent` (`#FFFFFF`: `5.17:1` L / `4.65:1` D) and `accentInk` (`#1D4FC4` / `#7EAAFF`) for **blue text & icons** (`≥ 6.07:1` L / `≥ 6.19:1` D across `bg`, `surface`, `raised`, and `accentSoft`) — solves this cleanly.
- **`accentInk` on course card washes (`[Verified]`):** `Palette.accentInk` also passes **`6.11:1–6.48:1` (light)** and **`5.84:1–6.49:1` (dark)** across all six `HuePalette.wash` card tints in [`Theme.swift:67-72`](../../macos/Sources/AcademicAssistant/Theme.swift#L67-L72), so blue links/actions remain AA-compliant inside washed cards.

### 3.2 What to Avoid: Four Concrete Colour Traps in Campus (`U3`–`U6`)

#### 1. Blue-on-blue role inversions (`accent` on `accentSoft`, or `onAccent` on `accentInk`) (`[Verified]`)
- **Trap A:** Putting `Palette.accent` (`#2563EB`) text inside a `Palette.accentSoft` (`#E6EEFD`) chip/sidebar pill in Light Mode yields **`4.43:1`** (below `4.5:1`), and in Dark Mode `#2F6FE4` on `#1A2A47` collapses to **`3.08:1`**. **Rule:** text/icons on `accentSoft` must **always** use `Palette.accentInk` (`6.07:1` L / `6.19:1` D).
- **Trap B:** Putting white (`Palette.onAccent`) or dark `bg` text on `Palette.accentInk` (`#7EAAFF` dark has only **`2.31:1`** against white). Watch [`WeekBoardParts.swift:89-91`](../../macos/Sources/AcademicAssistant/WeekBoardParts.swift#L89-L91) (`"TODAY"` capsule): because `Tech.neon` temporarily aliases `Palette.accentInk`, `U4` must explicitly switch solid badges/pills to `Palette.onAccent` on `Palette.accent`.

#### 2. Blue next to Purple/Violet and Green/Teal course colours (`[Verified]` OKLab ΔE×100 + CVD)
Measured perceptual distances (`OKLab ΔE × 100`) under normal vision and Viénot (1999) protanopia, deuteranopia, and tritanopia simulations explain what works and what must be avoided:

| UI Blue vs. Neighbour Hue | Normal OKLab ΔE | Protan ΔE | Deutan ΔE | Tritan ΔE | Verdict |
|---|---:|---:|---:|---:|---|
| Campus `accent` L `#2563EB` vs. **Campus `violet` mark L `#AD87ED`** | **20.3** | **12.5** | **17.3** | **16.3** | **PASS** (lightness separation carries protan/deutan) |
| Campus `accentInk` D `#7EAAFF` vs. **Campus `violet[2]` D `#A17ADF`** | **12.3** | **11.5** | **8.0** | **14.2** | **PASS** (keep non-adjacent; never touch edges) |
| Campus `accent` L `#2563EB` vs. *Indigo-600 `#4F46E5`* | 6.7 ❌ | 4.0 ❌ | **2.8 ❌** | 6.1 ❌ | **AVOID** — indigo/blue-violet merges with UI blue under deuteranopia |
| Campus `accent` L `#2563EB` vs. **Campus `green` mark L `#047554`** | **25.6** | **24.6** | **23.8** | **8.2** | **PASS** (emerald hue + luminance separation survives tritanopia) |
| Campus `accent` D `#2F6FE4` vs. **Campus `green` mark D `#057C59`** | **23.3** | **22.6** | **22.0** | **7.4** | **PASS** |
| Campus `accent` L `#2563EB` vs. *Teal-600 `#0D9488`* | 22.6 | 21.4 | 20.7 | **6.4 ❌** | **AVOID** — cyan/teal collapses toward blue in tritanopia & dark mode |

- **Adjacency & relief rule (`[Inferred]`):** Even with passing ΔE, **never place a `3pt` UI-blue selection border directly flush against a `3pt` `violet` or `green` course leading bar** (Bezold chromatic assimilation makes adjacent thin strips of blue and violet/green look muddied). Use the card/row **surface fill** (`Palette.raised` or `Palette.accentSoft`) or column header pill for selection/"Today", keep the `3pt` leading edge exclusively for the course's `HuePalette.accent`, and always print the course name/code alongside the mark.

#### 3. Status colours in Light Mode (`Theme.swift:25-27` & `WeekBoardParts.swift:6-7`) (`[Verified]`)
Auditing the current single-hex status tokens against Campus surfaces reveals a Light/Dark asymmetry that `U4`/`U5` must handle carefully:

| Current status colour | On light `surface` `#FFFFFF` | On light `raised` `#EEF2F8` | On dark `surface` `#171D27` | Safe usage / fix |
|---|---:|---:|---:|---|
| `Palette.good` (`#0CA30C`, [`Theme.swift:25`](../../macos/Sources/AcademicAssistant/Theme.swift#L25)) | 3.35:1 (mark ok, **text ❌**) | 2.91:1 ❌ | 5.04:1 ✅ | Dot/icon mark only; **never** body/caption text in Light Mode. |
| `Palette.warning` (`#FAB219`, [`Theme.swift:26`](../../macos/Sources/AcademicAssistant/Theme.swift#L26)) | **1.83:1 ❌** | **1.60:1 ❌** | 9.22:1 ✅ | **Fails 3:1 even for dots/bars on white.** Needs darker light-mode value or border relief. |
| `Palette.critical` (`#D03B3B`, [`Theme.swift:27`](../../macos/Sources/AcademicAssistant/Theme.swift#L27)) | 4.80:1 ✅ | 4.17:1 ❌ | **3.52:1** (mark ok, **text ❌**) | Fails `4.5:1` as text on light `bg`/`raised` and on all dark surfaces. |
| `WeekBoardParts` `amber` (`#F5B544`, [`:6`](../../macos/Sources/AcademicAssistant/WeekBoardParts.swift#L6)) | **1.79:1 ❌** | **1.61:1 ❌** | 8.29:1 ✅ | Remove hardcoded dark-only `amber`/`red` in `U4`. |
| `WeekBoardParts` `red` (`#FF6B6B`, [`:7`](../../macos/Sources/AcademicAssistant/WeekBoardParts.swift#L7)) | **2.75:1 ❌** | **2.47:1 ❌** | 5.42:1 ✅ | Remove hardcoded dark-only `amber`/`red` in `U4`. |

- **Recommendation for `U4`/`U5` (`[Inferred]`):**
  - Keep status text (`"Synced 09:41"`, `"Crunch · Thu–Fri"`, `"Overdue"`) in `Palette.text` / `Palette.text2` with a symbol prefix (`⚠`), **or** if coloured status labels/icons/strokes are desired (e.g., `OVERDUE` tag, `HEAVY` workload bar, `CrunchBanner`), use light/dark appearance-aware status ink pairs pre-verified at **≥ 5.4:1** across `bg`, `surface`, and `raised` in both modes:
    - `goodInk`: light `#166534` (worst `6.35:1` on `raised`) / dark `#4ADE80` (worst `8.63:1` on `raised`)
    - `warningInk`: light `#92400E` (worst `6.31:1` on `raised`) / dark `#FACC15` (worst `9.82:1` on `raised`)
    - `criticalInk`: light `#B91C1C` (worst `5.76:1` on `raised`) / dark `#F87171` (worst `5.44:1` on `raised`)

#### 4. Decorative `Palette.line` (`~1.3:1`) as a sole control boundary (`[Verified]`)
- `Palette.line` (`#D9E0EA` light / `#2B3442` dark) is intentionally subtle (`~1.33:1` against `surface`) so cards feel calm. Per WCAG 1.4.11 (Non-text Contrast), never rely on `Palette.line` alone to delineate interactive text fields, checkboxes, or segmented buttons — use native SwiftUI controls (`.bordered`, `.borderedProminent`, `Picker` `.segmented`, `Menu`, `TextFieldStyle.roundedBorder`), which automatically draw high-contrast system borders under macOS Light, Dark, and **Increase Contrast** (`colorSchemeContrast == .increased`).
