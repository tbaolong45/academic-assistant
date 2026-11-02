# Design: UI redesign proposal (T5)

Status: approved, 2026-11-02: direction A "Campus" (decisions in §7, build queue in §8). T7 (the researcher's macOS design notes) may refine details.

## 1. What goes, what every direction shares

**Removed in every direction:**
- The always-dark neon green (`Tech.neon`).
- `.fontDesign(.monospaced)` on the whole window (`App.swift:39`).
- `TypewriterTitle` ("> academic_assistant" with a blinking cursor).
- `TechBackground` (grid, scanline, corner glow).
- `SectionLabel`'s `// THIS WEEK ───`.
- Glow borders and shadows in `techPanel`.
- Uppercase tracked labels ("SYNCED").
- The pulse rings.

**Shared by all three:**
- **System font (SF Pro).** Numbers use `.monospacedDigit()`, so countdowns don't jitter. Sentence-case headings ("This week", "Do next").
- **Follows the system appearance (recommended).** Drop `.preferredColorScheme(.dark)` (`App.swift:38`). Every token has a light and a dark value, both validated (§4). Students mostly use the default Light or Auto, and a dark-only app is part of the "for IT people" feel. An in-app Light/Dark override is skipped; add it if asked.
- **Semantic tokens** replace `Tech.*` (same roles, new names):

  | Token | Use |
  |---|---|
  | `bg` | window background |
  | `surface` | cards, sheets |
  | `raised` | hovered or selected rows, inputs |
  | `line` | hairlines |
  | `text`, `text2`, `text3` | ink levels; `text3` still passes 4.5:1 |
  | `accent` | blue fills: primary button, selection bar, today marker |
  | `onAccent` | text on `accent` |
  | `accentInk` | blue text and icons (links, selected labels) |
  | `accentSoft` | blue wash behind a selected row or chip |

- **Status colours** (good, warning, critical) come from the dataviz reference set. They only ever appear with an icon and a label: overdue gets ⚠ plus "Overdue", never red alone.
- **Motion:** keep `stagger`, but rise only (no blur), and do nothing under Reduce Motion. Keep the week slide. Nothing loops forever.
- **CLAUDE.md constraints:**
  - `@Local`, no `#Preview`.
  - Breakpoints from the `GeometryReader` width.
  - `Slider` rounding done in the binding.
  - Reduce Motion respected.
  - The `WindowGroup` stays the first scene.
- **Sidebar selection:** the `List(selection:)` gotcha (it forces the system-blue highlight) stops mattering once the brand is blue. Still keep the button sidebar. The system highlight follows the user's *system* accent colour (it could be purple or graphite), and the brand blue must not.

## 2. Three directions

All three use blue as the primary colour. Hex values are the validated ones from §4. Every number in the mock-ups (grades, percentages, times) is made up.

### A. "Campus" — native Mac, light and calm (recommended)

Looks like Apple's own Calendar and Reminders with a confident blue: white cards on a soft blue-grey canvas, a translucent system sidebar, big friendly numbers, and blue only where something is selected or actionable.

- Medium density. Shadows only in light mode (y 1, blur 6, 6% black); dark mode separates cards by fill.
- On macOS 26 the system sidebar and toolbar become Liquid Glass automatically, with no custom glass anywhere else.
- Least risky. It reads as a "normal app" to a non-technical student.

```
┌──────────────┬──────────────────────────────────────────────────────────────┐
│ ◉ Overview   │  Good morning                              ● Synced 09:41    │
│   Deadlines 7│  Monday 2 November                                           │
│   Calendar   │ ┌──────────────┐ ┌──────────────┐ ┌───────────────────────┐  │
│ COURSES      │ │ Running grade│ │ Still to come│ │ Next deadline         │  │
│ ● Calculus   │ │   86.4 %     │ │   58 %       │ │ 2d 14h                │  │
│ ● Lin. Alg.  │ │ across 5     │ │ 3 courses    │ │ Final Paper · Comm.   │  │
│ ● Python     │ └──────────────┘ └──────────────┘ └───────────────────────┘  │
│ ● Comm.      │  This week                                                    │
│ ● Intro AI   │ ┌────────────────────────────────────────────────────────────┐│
│ ○ HR training│ │▍Quiz 4          Calculus        Tue 10 Nov   7.5%   [ Open ]││
│              │ │▍Final Paper     Communication   Fri 13 Nov   14%           ││
│ [⟳ Sync]     │ └────────────────────────────────────────────────────────────┘│
└──────────────┴──────────────────────────────────────────────────────────────┘
 ◉ = blue selection pill (accentSoft + accentInk)   ▍ = 3 pt course-colour edge

Deadlines
  Week of 2 Nov   ‹ ›  [ To submit | Events | All ]  [ Filter ▾ ]
  Do next
  ╭─────────────────────────────╮ ╭─────────────────────────────╮
  │● Final Paper        14%     │ │● Quiz 4             7.5%    │
  │  due in 11 days · ~7 h →    │ │  in 8 days · ~3 h prep →    │
  │  start by Tue 10 Nov        │ │  start by Mon 9 Nov         │
  ╰─────────────────────────────╯ ╰─────────────────────────────╯
  Mon 2     Tue 3     Wed 4     Thu 5     Fri 6     Sat 7    Sun 8
  ┃today┃   ┌──────┐            ┌──────┐
            │▍Lab 5│            │▍Read.│
            └──────┘            └──────┘
```

| Part | Style |
|---|---|
| Card | `surface`, 12 pt radius, 1 px `line`; hover lifts to `raised`. The course colour is a 3 pt leading edge, never a fill behind text. |
| Chip / tag | Capsule, `accentSoft` fill, `accentInk` text, `.caption.weight(.semibold)`. Weight tags are neutral (`raised` + `text2`). |
| Sidebar | Native `NavigationSplitView` sidebar material. Selected row is an `accentSoft` pill with `accentInk` icon and text. Course rows get a 8 pt course-colour dot. |
| Buttons | Primary `.borderedProminent` tinted `accent` (white text, 5.2:1). Secondary `.bordered`. Toolbar icons plain. |
| Type | `.largeTitle.bold()` page title, `.title3.semibold` section headings, `.body` rows, 34 pt `.rounded` bold numbers in the KPI tiles. |

### B. "Glass" — Liquid Glass, deep blue

The most modern and striking. A deep-blue gradient canvas in dark mode and a pale sky gradient in light mode, with every card, chip and toolbar a Liquid Glass pane. Glass panes morph when they change (`glassEffectID`). Headings in SF Pro Rounded.

- Needs macOS 26 (§5).
- Costs more GPU and battery than A, because of the always-composited glass. Contrast depends on what's behind the glass, so the opaque fallback (Reduce Transparency) is the version that was checked.
- Easiest to overdo: keep glass to cards and chips, never stack glass on glass.

```
╔══════════════════════════════════════════════════════════════════════════╗
║ (glass sidebar)  ░  Good morning, Monday 2 Nov            ◌ Synced 09:41 ║
║  ◉ Overview      ░ ╭─ glass ──────╮ ╭─ glass ──────╮ ╭─ glass ──────────╮ ║
║    Deadlines 7   ░ │ 86.4 %       │ │ 58 %         │ │ 2d 14h           │ ║
║    Calendar      ░ │ running grade│ │ still to come│ │ Final Paper      │ ║
║  Courses         ░ ╰──────────────╯ ╰──────────────╯ ╰──────────────────╯ ║
║   ● Calculus     ░ ╭─ glass ───────────────────────────────────────────╮  ║
║   ● Lin. Alg.    ░ │ ● Quiz 4 · Calculus · Tue 10 Nov          7.5%    │  ║
║                  ░ │ ● Final Paper · Communication · Fri 13 Nov 14%    │  ║
║  deep-blue gradient behind everything (#081226 → #0e2a5c)              ║
╚══════════════════════════════════════════════════════════════════════════╝

Deadlines: same layout as A. Do next chips are glass capsules in a GlassEffectContainer.
Day columns are faint glass strips; today's strip is tinted accent.
```

| Part | Style |
|---|---|
| Card | `.glassEffect(.regular.tint(surface.opacity(0.35)), in: .rect(cornerRadius: 18))`. Under Reduce Transparency, opaque `surface`. |
| Chip | Glass capsule, `.glassEffect(.regular.interactive())`; selected = tinted `accent`. |
| Sidebar | System glass sidebar, `accentSoft` selection pill. |
| Buttons | `.buttonStyle(.glassProminent)` tinted `accent` for primary, `.glass` for secondary. |
| Type | `.fontDesign(.rounded)` for titles and numbers, SF Pro for body. |

### C. "Planner" — paper and ink

An editorial study planner: warm off-white paper, ink-navy text, deep "fountain-pen" blue for today, links and the primary action.

- No cards: content sits on the page, separated by hairlines. Each row carries a thin course-colour rule.
- Page titles in New York serif (`.fontDesign(.serif)`), everything else SF Pro.
- The densest and quietest of the three. Feels like a paper diary.
- Dark mode is "ink": near-black warm grey, with no blue tint in the surfaces.

```
  Overview                                                  Synced 09:41
  Monday, 2 November                                         (serif title)
  ─────────────────────────────────────────────────────────────────────
  86.4 %                 58 %                    2d 14h
  running grade          still to come           Final Paper, Comm.
  ─────────────────────────────────────────────────────────────────────
  This week
  │ Tue 10   Quiz 4 ............................ Calculus       7.5 %
  │ Fri 13   Final Paper ....................... Communication  14 %
  ─────────────────────────────────────────────────────────────────────

  Deadlines                     ‹ Week of 2 Nov ›   To submit · Events · All
  Do next   1. Final Paper — 14 %, start by Tue 10 Nov
            2. Quiz 4 — 7.5 %, start by Mon 9 Nov
  Mon 2 │ Tue 3 │ Wed 4 │ Thu 5 │ Fri 6 │ Sat 7 │ Sun 8      (hairline columns,
  ══════│       │       │       │       │       │             today underlined
  Lab 5 │       │ Read. │       │       │       │             in accent blue)
```

| Part | Style |
|---|---|
| "Card" | None. A row is a `line`-divided list item with a 2 pt course-colour rule on the left; hover = `raised` background. |
| Chip | Text-only with a dotted `accentInk` underline; weight shown as plain `text2`. |
| Sidebar | Flat `bg` (no material), `accentInk` text plus a 2 pt `accent` rule for the selected row. |
| Buttons | Primary filled `accent`, 6 pt radius. Secondary plain `accentInk` text buttons. |
| Type | `.fontDesign(.serif)` for page titles, SF Pro elsewhere, generous line spacing. |

### Quick comparison

| | A Campus | B Glass | C Planner |
|---|---|---|---|
| Feels like | Calendar, Reminders | macOS 26 showcase | a paper planner |
| Friendliness for non-technical students | high | high, but busier | high for list people |
| macOS target | 15 ok (26 adds glass to the sidebar and toolbar for free) | **26 required** | 15 ok |
| Build effort | low-medium | medium-high | medium (cards become rows) |
| GPU and battery | lowest | highest | lowest |
| Risk | low | contrast over busy backdrops; easy to overdo | density can feel plain |

## 3. The clash with the blue course colour

`Hue.blue` is the first course colour, handed out to the first credit course, so a blue UI would blur selection, buttons and links with that course.

**Fix: blue is reserved for the UI, and course colours become green, orange, yellow, magenta, violet**, in that fixed order and never cycled. Trainings and GENERAL stay slate.

- I searched 5-hue sets from 8 candidates (with OKLCH lightness steps) for the best worst-case separation, *including the brand blue as a sixth colour*. This set won in both modes. Teal, a closer neighbour of blue, failed in dark mode (normal-vision ΔE 11.3).
- Keep the `case blue` value so old `moodle-cache.json` files still decode. Remove it from `courseHues` and add `violet`. Colours are reassigned on the next sync.

Validator: dataviz `validate_palette.js`, OKLab ΔE×100. Light surface `#ffffff`, dark surface `#161d2e`.

| Mode | Course accents (band 2): green, orange, yellow, magenta, violet | Courses, adjacent | **Brand + courses, all pairs** | Contrast vs surface |
|---|---|---|---|---|
| light | `#047554` `#9a4901` `#c39806` `#c0558d` `#ad87ed`, brand `#2a78d6` | PASS | PASS (normal ΔE ≥ 16.2, CVD ≥ 8.5) | yellow 2.69, violet 2.81: below 3:1, so **relief needed** |
| dark | `#057c59` `#a24e04` `#b48c05` `#d4679f` `#7750b1`, brand `#3987e5` | PASS | PASS (normal ΔE ≥ 15.7, CVD ≥ 9.0) | orange 2.90, violet 2.85: relief needed |

The relief is already there and stays a rule: course colour only marks things (dots, edges, swatches), and the course name or code is always written next to it. Text never uses course colours.

Weight ramps (band 0→3, `validateOrdinal`, all **PASS**: monotone lightness, ΔL ≥ 0.06, light end ≥ 2:1, single hue). Light mode runs light→dark and dark mode dark→bright, so heavier weight is stronger in both:

| Hue | Light (band 0, 1, 2, 3) | Dark (band 0, 1, 2, 3) |
|---|---|---|
| green | `#77c4a3` `#24ab7e` `#078661` `#015f43` | `#076246` `#078661` `#05ac7d` `#69d6aa` |
| orange | `#dfa17c` `#d07940` `#af5504` `#7d3a01` | `#79421e` `#ab5819` `#d8732b` `#fba773` |
| yellow | `#c9ae6d` `#b38c15` `#8d6d01` `#644c00` | `#674f00` `#8d6d01` `#b48c05` `#deb95c` |
| magenta | `#dd9ab9` `#cc6f9d` `#af467e` `#7e2e59` | `#773c59` `#a84e7c` `#d4679f` `#f89dc9` |
| violet | `#baa4e2` `#9f7ed6` `#8059bb` `#5b3d87` | `#5a467d` `#7e5db1` `#a17adf` `#c9acff` |
| slate (trainings, GENERAL; chosen in U1) | `#a3acb9` `#7f8a9a` `#5e6a7b` `#3e4857` | `#4f5a6a` `#6c7889` `#939fb0` `#c3cbd7` |

- The categorical accents above are a separate step (band 2 ≈ accent), chosen for separation. The builder uses the accent row for dots and edges, and the ramp for weight shading.
- Today yellow, magenta and slate are dark-only (`Theme.swift` uses the same hex for light and dark). Following the system makes real light values necessary; slate gets a neutral ramp in the same way.
- Slate's ramp passes `validateOrdinal` against the Campus surfaces (`#ffffff`, `#171d27`); re-checked by the architect. Its mark colour is band 2 (`#5e6a7b` light, `#939fb0` dark).
- **Card washes** (`HuePalette.wash`, chosen by the builder in U1, re-checked by the architect): a faint course tint behind a card. Body `text` and `text3` stay ≥ 4.5:1 on every wash; the worst is text3 at 4.67 (light orange) and 4.68 (dark yellow).

  | Hue | Wash light | Wash dark |
  |---|---|---|
  | green | `#e6f1ee` | `#142c2f` |
  | orange | `#f5ede6` | `#2d2521` |
  | yellow | `#f9f5e6` | `#302f22` |
  | magenta | `#f9eef4` | `#35293a` |
  | violet | `#f7f3fd` | `#26253d` |
  | slate | `#eff0f2` | `#262d37` |

- `.blue` keeps its old ramp only so old caches decode. It isn't handed out any more.

## 4. Theme tokens and contrast

All text pairs were checked with the validator's WCAG `contrast()` (target ≥ 4.5:1). The worst pair per theme is listed.

| Token | A light | A dark | B light (fallback) | B dark (fallback) | C light | C dark |
|---|---|---|---|---|---|---|
| bg | `#f4f6fa` | `#0f141c` | `#e9f1fe` | `#081226` | `#faf9f6` | `#121316` |
| surface | `#ffffff` | `#171d27` | `#f7faff` | `#11203d` | `#ffffff` | `#1a1c20` |
| raised | `#eef2f8` | `#1f2733` | `#ffffff` | `#18294a` | `#f3f1ec` | `#22252a` |
| line | `#d9e0ea` | `#2b3442` | `#cfdcf2` | `#273a5e` | `#e3dfd6` | `#30333a` |
| text | `#0f172a` | `#e8edf5` | `#0b1a33` | `#eef3ff` | `#1a2332` | `#eceae4` |
| text2 | `#475569` | `#a9b4c4` | `#3d4d69` | `#b4c1dc` | `#4f5866` | `#aeaaa1` |
| text3 | `#5f6b7d` | `#8d99ab` | `#566582` | `#93a3c4` | `#636b78` | `#928e86` |
| accent (fill) | `#2563eb` | `#2f6fe4` | `#0a5fd8` | `#2a6ae0` | `#1d4ed8` | `#2f63e0` |
| onAccent | `#ffffff` | `#ffffff` | `#ffffff` | `#ffffff` | `#ffffff` | `#ffffff` |
| accentInk | `#1d4fc4` | `#7eaaff` | `#0a55c2` | `#8db6ff` | `#1d4ed8` | `#86a9ff` |
| accentSoft | `#e6eefd` | `#1a2a47` | `#dbe8ff` | `#163061` | `#e7edfb` | `#1d2944` |
| **worst text pair** | text3/raised 4.81 | onAccent/accent 4.65 | text3/bg 5.16 | onAccent/accent 4.96 | text3/raised 4.76 | text3/raised 4.71 |

- Pairs checked: text on bg, surface, raised and accentSoft; text2 on surface and raised; text3 on bg, surface and raised; accentInk on surface, bg and accentSoft; onAccent on accent.
- All ≥ 4.5. B dark's accent was first `#3b7cf0` (3.94 with white) and was darkened to `#2a6ae0`.
- `line` is about 1.3:1 against `surface`. That's fine for decorative hairlines, but no control may rely on a line alone to be seen. Inputs and toggles use system controls, which carry their own contrast.
- B's numbers are for the opaque fallback. Over a busy backdrop real glass varies. A shows glass only in the system sidebar and toolbar, which Apple tunes itself.

## 5. Platform: macOS target

- **Recommendation: raise the target to macOS 26.**
  - It's only the user's Mac, which is on macOS 26.7 with SDK 27.
  - It removes every `if #available` branch and lets B (or a later touch of glass in A or C) use `glassEffect`, `GlassEffectContainer`, `.glass` / `.glassProminent` button styles and `glassEffectID` directly.
  - To do it: `swift-tools-version: 6.2` and `platforms: [.macOS(.v26)]` in `macos/Package.swift`. `.v26` needs tools version 6.2; the installed Swift is 6.4, so that's fine.
  - The glass APIs are ordinary modifiers, not macros, so they work with the Command Line Tools (no SwiftUI macro plugin needed).
- **If the user wants to keep macOS 15:** A and C need no 26-only API. B would need `if #available(macOS 26, *)` around every glass call, with a `.regularMaterial` fallback. That doubles B's styling code, which is one more reason B goes with raising the target.

## 6. Implementation plan (for the chosen direction)

Steps 1–3 are the same for every direction. Step 4 onwards depends on the pick. Each step is one reviewable diff, and `./macos/build-app.sh` passes after each.

| # | Builder step | Files | Notes |
|---|---|---|---|
| U1 | Tokens | `Theme.swift` | `struct Token { let light, dark: String; var color: Color }` and `enum Palette` with the §4 roles for the chosen direction. Course hues get light and dark ramps (§3) plus `violet`, and `courseHues = [.green, .orange, .yellow, .magenta, .violet]`. Status colours. For one step, `Tech` stays as a thin alias (`Tech.text = Palette.text.color`, `Tech.neon = Palette.accentInk.color`: most neon uses are text and icons, which need accentInk's 4.5:1; the fill uses get `accent`/`accentSoft` in U2–U4) so the app still compiles and immediately looks blue. |
| U2 | Effects | `Effects.swift` | Delete `TechBackground`, `TypewriterTitle` and `Pulse`. `techPanel` → `card(active:)` in the chosen style. `SectionLabel` → a plain sentence-case `.title3.semibold` header (keep the `.isHeader` trait). `stagger` loses its blur. |
| U3 | App shell | `App.swift` | Remove `.preferredColorScheme(.dark)` and `.fontDesign(.monospaced)`, set `.tint(Palette.accent)`, restyle the sidebar rows (keep the button sidebar), use `Palette.bg` as the window background. The sidebar column can narrow (`min 220`) once names aren't monospaced. If raising the target: also `Package.swift`. |
| U4 | Overview + Deadlines | `HomeView.swift`, `WeekView.swift`, `WeekBoardParts.swift` | Header ("Good morning" + date, sync status as a small dot + text), KPI tiles, rows, Do next chips, board columns and the today marker. Coordinate with T3's B3 (reason line) and B6 (filter menu), which touch the same views; do U4 before or after those, never in parallel. **Motion (after U2):** nothing loops forever on screen. A loop may run only while work is in progress (a sync). Decorative motion becomes static or a one-shot transition. Check: idle CPU stays under 5 % with that screen open. Remove: the `repeatForever` glow at `WeekBoardParts.swift:349` (make it a static highlight). Slow down: the 1 s `TimelineView`s at `HomeView.swift:55` and `:82` go to 60 s, since countdowns show minutes at most. |
| U5 | Other screens | `CourseView.swift`, `CalendarView.swift`, `AssessmentSheet.swift`, `ConnectView.swift`, `WhatIfPanel.swift`, `ScoreChart.swift` | The chart keeps the dataviz mark specs; re-check its colours against the new surfaces. **Motion (after U2):** nothing loops forever on screen. A loop may run only while work is in progress (a sync). Decorative motion becomes static or a one-shot transition. Check: idle CPU stays under 5 % with that screen open. Remove:<ul><li>`CourseView.swift:466`, the 60 fps `TimelineView(.animation)` while a course is open. It's the largest one left, so do it first, even if the rest of U5 waits.</li><li>`ScoreChart.swift:78`, the marching ants (`repeatForever` plus the 35 ms sleep loop): a static dashed line.</li><li>`AssessmentSheet.swift:68`, the 12 s decorative spin: static.</li></ul>Keep the 30 s `TimelineView` at `ConnectView.swift:290`. |
| U6 | Clean-up | all | Remove the `Tech` alias, rename the remaining uses to `Palette` (mechanical), and update the CLAUDE.md "Look" bullet (architect). |

**Test writer (SelfCheck.swift), pure numbers, no UI:**
1. A Swift WCAG `contrast(hexA, hexB)` with the reference value contrast(`#ffffff`, `#2563eb`) = 5.17 ± 0.01.
2. For both appearances: each pair listed in §4 is ≥ 4.5, read from the `Palette` token hexes, so changing a token breaks the check.
3. Each course ramp (light and dark) is monotone in relative luminance (light: decreasing; dark: increasing). Its lightest-on-surface step is ≥ 2:1 against `surface` (light) and its darkest is ≥ 2:1 against `surface` (dark).
4. `Hue.courseHues` doesn't contain `.blue`, and `courseHues.count == 5` with no repeats.
5. An old cache whose subject has `"hue":"blue"` still decodes.

### 6.1 U1c: brighter dark appearance (approved by the user 2026-11-03 as previewed, dark `onAccent` labels included; built after B5)

The user asked for more energy and contrast in dark mode. This step changes **dark values only** in `Theme.swift`; light stays as approved. The architect checked every value with the dataviz validator (`validate`, `validateOrdinal`, WCAG contrast).

**At a glance (dark):**

| Token | Before | After | What changes |
|---|---|---|---|
| bg | `#0f141c` | `#060c18` | deeper navy page |
| surface (cards) | `#171d27` | `#141b2c` | lightness steps between bg, surface and raised nearly double (OKLCH ΔL 0.04 → 0.07), so cards stand off the page |
| raised | `#1f2733` | `#222c41` | |
| line | `#2b3442` | `#394459` | hairlines visible (1.35 → 1.75:1, still decorative) |
| text | `#e8edf5` | `#f4f7fc` | 14.4 → 16.0:1 on cards |
| text2 | `#a9b4c4` | `#cad3e4` | 8.1 → 11.4:1 |
| text3 | `#8d99ab` | `#a6b0c3` | 5.9 → 7.9:1 |
| accent (fills) | `#2f6fe4` | `#3d89ff` | brighter blue. **Labels on it become dark** (`onAccent`), see below |
| onAccent | `#ffffff` | `#081123` | 4.65 → 5.58:1 |
| accentInk (blue text) | `#7eaaff` | `#7db3ff` | lighter at about the same saturation (sRGB has no more chroma at that lightness) |
| accentSoft | `#1a2a47` | `#1a3467` | bluer selection wash |
| good / warning / critical | `#0ca30c` / `#fab219` / `#d03b3b` | `#49df6e` / `#ffc347` / `#fe726e` | all ≥ 5.2:1 on surface and raised (critical was 3.5, good 4.5 on raised) |
| course marks | `#057c59` `#a24e04` `#b48c05` `#d4679f` `#7750b1` | `#009068` `#c14802` `#b48c05` `#e4569e` `#914ad0` | more saturated; yellow was already at the top of the band |

**Why labels on blue go dark:** white text needs a blue at or below the current lightness. A brighter fill with white labels would fall to 3.4:1. Dark labels on a bright fill are the usual dark-mode pattern (Material 3 does the same).
- No view draws text on `accent` yet, and there are no `.borderedProminent` buttons.
- Rule for U4/U5: a prominent button uses a custom style with `onAccent`. A system prominent button would draw white on the tint.

**Course colours (dark):**

| Hue | Ramp, band 0 → 3 | Mark | Wash |
|---|---|---|---|
| green | `#047554` `#089e72` `#05c992` `#77efbf` | `#009068` | `#063223` |
| orange | `#9a4825` `#d55c27` `#ff8350` `#fec5b0` | `#c14802` | `#412013` |
| yellow | `#7b5f01` `#a58108` `#d2a402` `#f8cf68` | `#b48c05` | `#352803` |
| magenta | `#95426a` `#cd5590` `#ff72b7` `#ffbfda` | `#e4569e` | `#3e1e2d` |
| violet | `#734f99` `#9e68d5` `#c48cfe` `#e0c8fe` | `#914ad0` | `#302340` |
| slate | `#596475` `#7b8799` `#9facbe` `#c8d5e8` | `#9facbe` | `#242c38` |

Ramps run OKLCH L 0.50 / 0.62 / 0.74 / 0.87 (they were about 0.44–0.80), with chroma up to 0.185.

**Validation (dark, against the new surface `#141b2c`):**
- **Text:** every text pair ≥ 4.5:1. The worst is onAccent on accent at 5.58 (it was 4.65).
- **Ramps:** all six pass `validateOrdinal`; band 0 is ≥ 2.67:1 on surface.
- **Washes:** text3 is ≥ 6.45:1 on every wash.
- **Marks:** the five course marks pass `validate` (adjacent pairs).
- **Blue against the marks:** `accent` plus the five marks pass `validate` with `pairs: "all"`. This fixes an old miss: violet `#7750b1` and the old accent were ΔE 12.7, below the 15 floor.
- **Not checked as series:** `accentInk` and the status colours are UI colours, not data series, so the categorical lightness band doesn't apply to them.
- **Status, red vs green:** good and critical can't be told apart under red-green colour blindness (deutan ΔE 3.8; it was 4.1). That's why status always ships with an icon and a label (rule in `Theme.swift`).
- **Light mode:** unchanged, so its checks still hold.

**Builder (Theme.swift only):** replace the dark half of each `Palette` token and each `Hue.palette` entry with the values above. Leave `.blue`'s legacy ramp as it is.

**Test writer (SelfCheck.swift, palette block):**
- (a) Add these dark text pairs to `textPairs`: `accentInk on raised`, `good on surface`, `warning on surface`, `critical on surface`, `good on raised`, `critical on raised`. All ≥ 4.5 in dark; light stays as it is.
- (b) Dark surface separation: `contrast(surface, bg) ≥ 1.12` and `contrast(raised, surface) ≥ 1.2` (new 1.14 and 1.23; old 1.09 and 1.13, so this fails on the old values).
- (c) Non-text: `contrast(accent, surface) ≥ 3` in both appearances (dark 5.09).
- (d) Each wash: `text3` on `wash` ≥ 4.5 in both appearances.
- (e) The existing ramp checks (monotone, band 0 ≥ 2:1) stay as they are.

## 7. Decisions (accepted by the user on 2026-11-02, relayed by the coordinator)

- **D1:** direction **A "Campus"**. Use the A columns of §4. B and C are dropped.
- **D2:** follow the system Light/Dark appearance.
- **D3:** raise the target to **macOS 26** (`swift-tools-version: 6.2`, `.macOS(.v26)`). Part of U3.
- **D4:** course colours are green, orange, yellow, magenta, violet (§3). Blue is reserved for the UI.

## 8. Merged build queue (T3 B1–B7, T5 U1–U6, approved T6 proposals P1–P8)

The builder takes these one at a time, top to bottom. After each step the test writer adds that step's checks, and `./macos/build-app.sh` must pass before the next step starts. Checks for the B steps are in `deadline-priority.md` §7, for the U steps in §6 above. Checks for the P steps, and the extra checks for merged items, are in §8.1 below.

| # | Step | Files | Overlaps with an earlier step (why it comes here) |
|---|---|---|---|
| 1 | **B1** board computed once + static regexes (in progress) | Model, Store, WeekView, HomeView, App, Moodle | — |
| 2 | **P1** Gmail: `BODY.PEEK[]` with a 256 KB partial fetch (proposal 1) | SchoolMail | none; first, because it changes the user's real mail now |
| 3 | **P4** mail progress: save per message, remember failed and unparseable UIDs (proposal 4) | Store (`addSchoolMail`), SchoolMail (`MailCache`) | SchoolMail with P1, Store with B1 |
| 4 | **P2** one publish per sync (proposal 2): sources fetched concurrently, a pure `normalize` assembles the subjects, `Store` publishes once | Store, Model | Store with B1 and P4; extends B1 |
| 4a | **U1c** brighter dark appearance (§6.1), approved 2026-11-03; build after B5 | Theme, SelfCheck | none (the builder is past Theme.swift) |
| 5 | **U1** Campus tokens, new course hues, `Tech` alias | Theme | none |
| 6 | **U2** Effects, **including proposal 5**: `TechBackground` deleted, no endless animation left | Effects | none |
| 7 | **U3** App shell, system appearance, macOS 26 target | App, Package.swift | App with B1 |
| 8 | **B2** origin, identity, optional fields, **including proposal 7**: announcement `modified` (`timemodified`), `posted` = max(created, modified) | Model, Moodle, Outlook, SchoolMail, Materials | Model with B1 and P2; Moodle with B1; SchoolMail with P1 and P4 |
| 9 | **B3** ranking + reason line, exams in Do next, 28-day Do next horizon, effective due date and cutoff (T4) | Model, Moodle, WeekBoardParts, WeekView | Model and Moodle with B2; WeekView with B1 |
| 10 | **U4** Overview + Deadlines restyle | HomeView, WeekView, WeekBoardParts | after B3, so the reason line is styled once; before B5 and B6, so their buttons and menu are built in the new style |
| 11 | **B4** cluster + supersede + move cue | Model, Moodle | Model and Moodle with B2 |
| 12 | **B5** done / dismiss / snooze | new BoardState, Model, Store, WeekBoardParts | WeekBoardParts with U4; Store with P2 |
| 13 | **B6** filters | Model, WeekView | WeekView with U4 |
| 14 | **U5** other screens restyle | CourseView, CalendarView, AssessmentSheet, ConnectView, WhatIfPanel, ScoreChart | none; can move earlier if the builder is blocked |
| 15 | **B7** PDF cache + bounded parallel sync (**= proposal 3**), plus a call counter printed by `--moodle-check` | Materials, Moodle, Store | Moodle with B2 and B4; Store with B5 |
| 16 | **P6** tiered cadence + status only for live assignments (proposal 6) | Store, Moodle | after B7, because both reshape `Moodle.sync` |
| 17 | ~~P8 incremental sync~~: **not built** (T4 shows it can't replace any refetch, see §8.1) | — | — |
| 18 | **U6** remove the `Tech` alias, rename to `Palette` | every view file | touches everything, so it goes last |

The project CLAUDE.md "Look" bullet (always dark, terminal theme, `Tech.*`) goes stale at U1. I'll draft the new text then, and the user approves the edit directly.

### 8.1 Check cases for the P steps and the merged items

Wherever a check needs network or a mail server, the step stays pure and the live part is a manual check the builder reports with numbers.

**P1: Gmail `BODY.PEEK[]` partial fetch**
- **Revised 2026-11-02, after the builder's finding:** with `-X`, `/usr/bin/curl` 8.7.1 writes only the untagged `*` line to stdout and drops the literal, so the curl route can't work.
- Rejected alternative: curl `FLAGS` → fetch → `STORE -FLAGS (\Seen)`, which is smaller (~20 lines).
  - The mail is still marked read on Gmail's server for about a second, which can clear its notification on the user's phone.
  - A mail the user opens during that second gets marked unread again.
  - It costs 3 logins per new mail.
  - The IMAP client makes "never marks read" structural (EXAMINE is read-only) and uses 1 login per sync instead of 1 + N.
- Decision (architect): replace curl for mail with a minimal in-process IMAP client on Network.framework in `SchoolMail.swift`. The rules:
  - TLS to `imap.gmail.com:993` with the system's default certificate and host checks; no custom verify block.
  - `AUTHENTICATE PLAIN` with the base64 initial response. That means no IMAP quoting of the password, and the password never appears as text on the wire log or in an error.
  - `EXAMINE "[Gmail]/All Mail"`. The mailbox is read-only, so nothing can set `\Seen`.
  - `UID SEARCH`, then `UID FETCH n BODY.PEEK[]<0.262144>` per new UID, then `LOGOUT`, all on **one** connection per sync.
  - A per-command timeout (30 s) and Task cancellation close the connection.
  - Errors carry only a short reason (e.g. "NO from server", "timeout"), never server text after `AUTHENTICATE` and never the credential.
  - The parser stays pure: `literal(_:)` plus a response reader.
- New checks:
  - (f) A pure response reader fed the same reply split into chunks at every byte offset (literal spanning chunks) returns the identical literal.
  - (g) A tagged `A3 NO [AUTHENTICATIONFAILED] Invalid credentials` gives `MailError.badLogin`, and its description contains neither the address nor the password from the fixture.
  - (h) The `AUTHENTICATE` line built for `a@x.com` / `p"w\` is `A2 AUTHENTICATE PLAIN ` + base64("\0a@x.com\0p\"w\\"), and the password doesn't appear in the line as plain text.
  - (i) **Manual, live:** a `--mail-check` mode (counts only) fetches the new UIDs, then reads `UID FETCH n FLAGS` for them on the same EXAMINE connection and prints `fetched N · newly seen 0`. Run it with at least one unread school mail and report the line.
- Implementation notes for the builder:
  - Fetch with a custom command on the mailbox URL (`-X "UID FETCH <uid> BODY.PEEK[]<0.262144>"`). The reply comes back as an untagged `* n FETCH (UID … BODY[]<0> {len}` line, then `len` **bytes**, then `)`.
  - The literal length counts bytes, so for this path `curl()` must hand back `Data` (or the byte slice), not a decoded `String`.
- Checks:
  - (a) `SchoolMail.fetchCommand(uid: 7)` == `"UID FETCH 7 BODY.PEEK[]<0.262144>"`.
  - (b) `SchoolMail.literal(Data("* 1 FETCH (UID 7 BODY[]<0> {23}\r\nSubject: hi\r\n\r\nhello\r\n)\r\n".utf8))` returns exactly the 23 bytes `Subject: hi\r\n\r\nhello\r\n`.
  - (c) Same as (b), but with a 2-byte UTF-8 character ("é") in the body and `{24}`: the result is 24 bytes, so the parser counts bytes, not characters.
  - (d) A literal cut at 262,144 bytes mid-part still parses: `parse` returns the subject and a non-empty body, with no crash.
  - (e) Dropped: it used a fake curl server, and curl is no longer used for mail (see "Revised" above).

**P4: mail progress**
- Checks:
  - (a) An old `mail.json` (a JSON **array** of messages) still decodes into the new format, so the 60 days of mail aren't downloaded again.
  - (b) Pure `SchoolMail.toFetch(uids: [1,2,3,4,5], have: [1], seen: [2], failures: [3: 3, 4: 1])` == `[4, 5]`. UID 3 is skipped after 3 failures; UID 2 is seen but unparseable.
  - (c) With an injected fetch closure where UID 3 of [1…5] throws: messages 1 and 2 are kept and saved, `failures[3]` == 1, and 4 and 5 are still tried.
  - (d) A message whose `parse` returns nil goes into `seen`, so the next run doesn't fetch it again.
  - (e) (R2 #10) `mailNote` reports how many messages were skipped as unreadable, e.g. "49 school emails · 1 skipped (unreadable date)".

**P2: one publish per sync**
- Also covers R2 #2 and #4 (`backend-review.md` §2.4). `Store` keeps a sync `generation`:
  - It's bumped at the start of every sync and by `connect` and `disconnect`.
  - The one publish, and the PDF-scan result, only apply when their generation still matches.
  - `disconnect()` cancels the running sync task.
- Checks:
  - (a) Pure `normalize(moodle:outlook:mail:docs:known:titles:)` on a fixture (the sample subjects, 1 one-off Outlook item, 1 mail with a date) equals today's chain `apply` → `OutlookCalendar.merge` → `SchoolMail.merge` → `labeled` → `summarized`. Compare by event ids.
  - (b) The summarizer's prune keeps the title of an Outlook event and of a mail event when it runs against `normalize`'s output. This is the M1 regression.
  - (c) **Manual:** add a temporary counter on `subjects`' `didSet`, run one sync, and report the count (must be 1 for the sync itself; downloads and AI runs publish separately). Remove the counter.
  - (d) The pure gate `Store.isCurrent(generation:current:)` (or whatever the builder names it): a result from generation 3 is dropped when the current one is 4 (a disconnect or a newer sync happened), and kept when it is 3.
  - (e) **Manual (R2 #2):** connect with mail set up, start a sync, press Disconnect while it runs. The sample dashboard must show no mail or Outlook item. Report what you saw.

**U2 + proposal 5: no endless animation**
- Checks:
  - (a) **Manual:** rebuild, open Overview, wait 10 s with Reduce Motion off, then take `ps -o %cpu= -p <pid>` three times, 2 s apart. Report the numbers. Before: 35–45 %; target under 5 %.
  - (b) Code review (reviewer): no `TimelineView(.animation` and no `repeatForever` left in `Effects.swift`.

**B2 + proposal 7: announcement modified date**
- Checks:
  - (a) A `Discussion` fixture with `created` 1 Oct and `timemodified` 5 Oct → `modified` 5 Oct, `posted` 5 Oct; `date` stays 1 Oct (what the list shows).
  - (b) With `timemodified` missing, `posted` == `created`.
  - (c) An announcement in an old cache, without `modified`, still decodes.

**B7 + proposal 3: call counter and parallel fetch**
- Checks, in addition to B7's in `deadline-priority.md`:
  - (d) `--moodle-check` prints `calls: N`.
  - (e) **Manual:** report the wall time and N from two runs before B7 (baseline 16.8 s and 27.9 s) and two runs after. The counts line (courses, assessments, announcements, materials) must be identical.

**P6: tiered cadence**
- Checks:
  - (a) Pure `Tier.next(now:lastSlow:manual:cameForward:)`:
    - `.slow` when 60 min or more have passed since `lastSlow`, or when manual or cameForward is true.
    - `.fast` at 59 min with neither flag.
  - (b) Pure `needsStatus(dueDate:cutoff:graded:now:)`. The status call also carries the student's extension (T4), so it must keep running while late work is still accepted:
    - ungraded, due tomorrow → true
    - ungraded, due 13 days ago → true
    - ungraded, due 15 days ago, no cutoff → false
    - ungraded, due 15 days ago, cutoff 3 days ahead → true
    - graded, due tomorrow → false
    - no due date (`.distantFuture`) → true
  - (c) Pure `merge(fast:previous:)`: a fast result leaves the previous subjects' assessments (grades) and materials unchanged and replaces assignments' status, announcements, messages and events.
  - (d) **Manual:** `--moodle-check` for a fast run and a slow run, reporting `calls: N` for each. Target for fast: under 40.

**P8: incremental sync: no-go (architect, 2026-11-02, after T4/Q3)**
- `core_course_get_updates_since` is callable with a student token, but T4 (§3.3) shows it is blind to:
  - manual gradebook items, which MBZUAI uses for most marks
  - weight edits
  - extensions and overrides
  - section summaries
  - deleted or hidden modules
  - plugins without the callback (attendance)
- So it can't replace the slow tier's refetches, only *add* calls: about 13 per fast sync, one per course member.
- The one gain would be new files and forum threads showing within 5 minutes instead of up to 60, and the user already accepted the 60-minute delay (Q2).
- Revisit only if the user wants faster files and discussions.
