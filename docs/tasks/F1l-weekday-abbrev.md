# F1l: abbreviated weekdays (F1j review)

Source: `docs/reviews/F1j.md`.

| # | From | Fix | File |
|---|------|-----|------|
| 1 | F1j #1 Medium | `Moodle.relativeWord` matches only full weekday names, while `moveCue` also accepts mon/tue/wed/thu/fri/sat/sun. So "The lab shifts to Thu", "moved to Tue" and "next Mon" match the cue but give no new date. Accept the same abbreviations, also with a trailing dot ("Thu."), matched as whole words. | Moodle.swift |

## Test writer
- F1j #1, posted Mon 5 Oct: "The lab shifts to Thu" → 8 Oct, moved. "Quiz on 20 Oct moved to Tue" → 6 Oct, moved. "next Mon" → 12 Oct.
- F1j #2: a news post with a compact range ("Dec 1-2") and `ranges: false` → {1 Dec} only, which proves the range restriction.

*As built (approved by the coordinator):* abbreviations count only when capitalised or in capitals (Thu, THU); full names stay case-insensitive. Lowercase "sat" and "sun" are ordinary words.
