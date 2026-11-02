# T1 (Builder) + T2 (Test writer): security fixes in the macOS app

Both tasks run at the same time against the interface below. Builder edits only the files listed for T1; test writer edits only
`macos/Sources/AcademicAssistant/SelfCheck.swift`. Read `CLAUDE.md` first (no `@State`, no `@Test`, checks live in SelfCheck.swift).

## Interface (both sides code against exactly these names)

| Name | Where | Contract |
|------|-------|----------|
| `func scrubPersonal(_ text: String) -> String` | Classifier.swift (global) | Removes personal details before text leaves the Mac (rules below). Pure. |
| `SchoolMail.isSafeCredential(_ s: String) -> Bool` | SchoolMail.swift | `false` if `s` is empty or contains any character from `CharacterSet.controlCharacters` (`\n`, `\r`, `\t`, …); else `true`. |
| `func writeOwnerOnly(_ data: Data, to url: URL) throws` | Moodle.swift, next to `MoodleCache` | Creates the parent folder if needed, sets the folder to 0700 **every time** (not only on creation), writes atomically, sets the file to 0600. |
| `Notifier.changes` grade entry | Notifier.swift | Title stays `"🎯 <course>: new grade"`; body becomes exactly the assessment name (no score, no %). |

## T1: Builder

- **S1, grade alerts.** In `Notifier.changes`, the new-grade body is `a.name` only. The user decided the score must not appear on the lock screen.
- **S2, personal details out of AI calls.** Add `scrubPersonal` and apply it at the point of sending only:
  - `Jev.body`: the `state` text.
  - `Jev.yesNo`: a `String` state, and every `String` value of a dictionary state.
  - `DeepSeek.body`: every entry of `parts`.
  - Don't change cache keys. `Jev.id(...)` and `Summarizer.id(...)` keep hashing the original text, so the existing `kinds.json` and `summaries.json` stay valid and nothing is paid for twice.
  - Rules:
    - Email addresses become `[email]`.
    - Phone numbers become `[phone]`: an optional `+`, then digits separated by spaces, `-`, `.` or `()`, 9 or more digits in total. `/` is **not** a phone separator, so dates like `23/10/2026` are untouched.
    - Signatures: when a line is just a sign-off, drop that line and everything after it. Sign-offs, case-insensitive, optional trailing `,` or `!`: best regards, kind regards, warm regards, regards, best, many thanks, thanks, thank you, cheers, sincerely. Also drop from a line that is exactly `--`, or that starts with `Sent from my` or `Get Outlook for`.
    - Must stay unchanged: dates (`Oct 20`, `12/11/2026`), times (`10:00`), course codes (`AI1110`), rooms (`B204`), percentages (`8%`), and a sign-off word inside a sentence (`Thanks, the quiz is Monday`).
- **S3, folder permissions.** Add `writeOwnerOnly` and use it in the four cache saves: `MoodleCache.save`, `KindCache.save`, `SummaryCache.save` and `MailCache.save`. Remove the duplicated permission code they replace.
- **S4, curl config injection.** In `SchoolMail.curl`, before writing the config, `guard isSafeCredential(address) && isSafeCredential(password)`; otherwise throw a new `MailError.badCredential` ("The address or app password contains a line break or other control character"). Every IMAP call goes through `curl`, so this one guard covers them all.
- Leave out: `CLAUDE.md` (the architect updates it after review), the views, and S5–S7.
- Done when: `./macos/build-app.sh` succeeds, which runs `--self-check` including the T2 checks, and `ls -ld ~/Library/Application\ Support/AcademicAssistant` shows `drwx------` after one launch of the built app. Report the self-check summary line and that `ls` output.

## T2: Test writer

Add a `// MARK: - Security (T1)` block to `SelfCheck.swift` with at least these checks:

1. `scrubPersonal("Contact jane.doe@mbzuai.ac.ae today")` contains `[email]` and no `@`.
2. `+971 50 123 4567` and `050-123-4567` each become `[phone]`.
3. `"Quiz 2 is on 12/11/2026 at 10:00 in B204 (AI1110), worth 8%"` is returned unchanged.
4. `"Submit by Oct 20.\n\nBest regards,\nDr. Jane Doe\nAssistant Professor"` keeps `Submit by Oct 20` and contains no `Jane`.
5. `"Thanks, the quiz is Monday"` is unchanged.
6. `SchoolMail.isSafeCredential`: `"abcdabcdabcdabcd"` → true; `""`, `"pass\nurl = x"` and `"a\rb"` → false.
7. `Notifier.changes`: an old subject where an assessment is ungraded and a new one where it is graded (e.g. 45/50) give a grade entry whose body equals the assessment name and contains neither `%` nor `90`.
8. `writeOwnerOnly` into a fresh folder under `FileManager.default.temporaryDirectory`: the folder is 0700 and the file is 0600. Then chmod the folder to 0755, write again, and the folder is back to 0700. Remove the temp folder afterwards.

- Run with `cd macos && swift build && .build/debug/AcademicAssistant --self-check`. That's a debug build, so it doesn't collide with the builder's release build. Until T1 lands, failures or a compile error on the new names are expected; re-run once the builder reports done.
- Done when: all checks, old and new, pass on the builder's code. Report the summary line.

## R1: Reviewer, after both report done

Review the diff in the T1 files and SelfCheck.swift for: correctness of the scrub rules (over- or under-matching), any path where text reaches Jev or DeepSeek without `scrubPersonal`, any secret or grade reaching logs, notifications, errors or stdout, and departures from CLAUDE.md. Report file:line, a failure scenario and severity for each finding.
