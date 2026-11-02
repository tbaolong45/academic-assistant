# F1c: fixes from reviews P2 and F1b (builder + test writer)

Queued right after B2. Sources: `docs/reviews/P2.md`, `docs/reviews/F1b.md`.

## Builder

| # | From | Fix | File |
|---|------|-----|------|
| 1 | P2 #1 + #4 **Medium** | Pressing Disconnect while `summarize` runs prunes the paid titles against the sample subjects and saves the empty result. Keep the AI task handles and cancel them in `disconnect`. Pass the generation into `classify`/`summarize` and skip prune, save and publish when it changed. | Store.swift |
| 2 | P2 #2 **Medium** | With no cache, the init scan runs `classify()` on the sample data, which is a paid Jev call. Skip the init scan and AI work unless there is real data (a cache or `lastSynced`). | Store.swift |
| 3 | P2 #5 | `disconnect` also clears `mailNote`, `outlookNote`, `downloadNote`, `syncing` and `downloading`, so a cancelled sync can't leave "syncing" up or Sync now disabled. Leave `mail` and `calendarItems` alone (separate accounts). | Store.swift |
| 4 | F1b #1/#2 | Only one `fetchMail` at a time. A set-mail check while a sync is fetching mail waits for that fetch or reuses its result, so one blip can't double-count a UID. | Store.swift (+ ConnectView.swift if a button must disable) |
| 5 | F1b #3 | A cancellation must never count as a failure. Map `CancellationError` to a distinct error, or check `Task.isCancelled` after the error too. | SchoolMail.swift |

| 6 | U3 review #2 | `macos/Resources/Info.plist` `LSMinimumSystemVersion` 15.0 → 26.0, to match `Package.swift` `.macOS(.v26)`. | Resources/Info.plist |

U3 review #3–#5 (TechBackground wrapper, light-mode leftovers, sidebar header style) go to U4/U5.

P2 #3 (the init PDF scan delays the first sync) stays as built for now; the architect may revisit it with B7's parallelism.

## Test writer (SelfCheck.swift)
- F1c #1: a pure check if the builder exposes one, e.g. "prune with a changed generation leaves titles unchanged". Otherwise say it's manual.
- F1c #5: a cancelled download counts no failure.
- F1b review #4: `23.10.26` and `23.10.26 10.00` are unchanged by `scrubPersonal`.
- Silence the "will never be executed" warning at `SelfCheck.swift:699`.
