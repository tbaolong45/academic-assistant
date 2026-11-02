# T5 UI redesign · T6 backend audit and pipelines · T7 design research · R2 fault hunt

The user's request (2026-11-02): the app looks like a tool "for IT people only". Make **blue the main colour** and give it a
modern look. On the backend, the architect researches and explores, finds faults worth fixing, and suggests several new
pipelines and algorithms. Every optimisation is a **proposal the user approves first**, with the reason, judged on
latency, flexibility, efficiency and speed.

Nothing in this file is built until the user has picked a direction or approved a proposal.

## T5: Architect, UI redesign proposal: `docs/design/ui-redesign.md`

The current look (`Theme.swift`, `Effects.swift`; CLAUDE.md "Look") is always dark, neon green, monospaced labels, a typewriter
title, `> deadlines` prompts and terminal effects. All of that is to go.

Deliver:

1. **Three distinct visual directions**, each with blue as the primary colour. For each: one paragraph, an ASCII mock-up of the
   Overview and the Deadlines board, the colour tokens, typography, and the main component styles (card, chip, sidebar,
   buttons). The user picks one.
2. **Light and dark.** Recommend whether to follow the system appearance (the current app is dark-only). Every text and
   background pair must have a contrast ratio, at least 4.5:1 for text, checked with the dataviz skill's palette validator as
   before.
3. **The clash with the blue course colour.** `Hue.blue` is the first course's colour, so a blue brand would blur with it.
   Propose a fix (for example, reorder or replace the course hue, or keep the UI accent neutral-blue and separate) and
   re-validate the course palette.
4. **Platform.**
   - The Mac runs macOS 26.7 with SDK 27, so Liquid Glass (`glassEffect`, the new materials) is available. The package
     targets `.macOS(.v15)`.
   - Say whether to raise the target to 26 (it's only the user's Mac) or keep `if #available` branches.
   - CLAUDE.md constraints still hold: `@Local`, no `#Preview`, breakpoints from `GeometryReader`, Reduce Motion, plus the
     macOS gotchas (Slider ticks, the `List` selection highlight).
5. **Implementation plan for the chosen direction:**
   - Which tokens and views change, in an order the builder can do in reviewable steps, starting with `Theme.swift` and
     `Effects.swift`.
   - What the test writer can check: `Theme` token contrast as pure numbers in `SelfCheck.swift`.

## T6: Architect, backend audit and new pipelines: `docs/design/backend-review.md`

Explore the macOS backend: `Moodle.swift`, `Store.swift`, `SchoolMail.swift`, `Outlook.swift`, `Materials.swift`,
`Classifier.swift`, `Summarizer.swift`, `Notifier.swift`, plus the `deadlines()` / `crunch()` path in `Model.swift`.
Research where useful; you can hand the researcher a sourced question through the coordinator.

Deliver:

1. **Faults worth fixing.** For each one: file:line, a concrete failure scenario, its severity, and a proposed fix. Include
   R2's findings once the coordinator forwards them, and mark which ones you confirmed.
2. **Several new pipeline and algorithm options (at least three)** for how data flows from sources to the board. Examples to
   consider, not to accept as given:
   - Incremental sync (only what changed since the last sync, using `timemodified`).
   - An event-normalisation stage that merges and supersedes items across sources before the board.
   - Confidence scoring per item.
   - Batching Jev questions into fewer calls.
   - A local first pass that only calls the AI when the rules are unsure.
   - Background PDF indexing.
   For each option: what it changes, and its expected effect on **latency** (time until fresh data shows), **flexibility**
   (how easy it is to add a source or rule), **efficiency** (API calls, cost, CPU, battery) and **speed** (UI
   responsiveness). Give numbers where you can measure them: time a sync with `--moodle-check` from inside the app bundle
   (see CLAUDE.md Keychain note) and count calls.
3. **Optimisation proposals, ranked:**
   - For each: why it's worth doing, the measured or estimated gain, the risk, and its effort.
   - Mark each as **needs user approval**. The coordinator brings them to the user. Nothing is built until approved.
4. **Fit with T3.** T3's priority, dedupe and filter design should slot into the pipeline you recommend; merge or
   cross-reference the two docs rather than duplicate them.

Order of work for the architect: finish the T3 draft first, then T5 (the builder needs a direction soon), then T6.

## T7: Researcher, modern macOS design notes, after T4 (report in your terminal, no repo edits)

1. **Apple's current macOS design guidance** (HIG for macOS 26: Liquid Glass, materials, sidebars, toolbars, typography). Say
   which SwiftUI APIs implement it and which macOS version each needs. Cite the Apple pages.
2. **Two or three well-regarded study, planner or deadline apps** and what makes them read as friendly to non-technical
   students: layout, colour, density, empty states. Describe the patterns only; don't copy any app.
3. **Accessible blue palettes:** the contrast of common blue primaries on white and on near-black, and what to avoid
   (blue-on-blue text, blue next to the purple and green course colours).

## R2: Reviewer, read-only fault hunt, after R1

Read the same backend files as T6. Look for correctness bugs, swallowed errors, race conditions (`Store` is `@MainActor` and
runs several `Task`s: `classify`, `summarize`, `addDocumentDates`), unbounded growth (caches, `titles`, `known`), and
edge cases in date parsing (`mentionedDates`, `OutlookCalendar.date`, `rfc2822`). Report each as file:line, scenario and
severity. The coordinator forwards your list to the architect for T6.
