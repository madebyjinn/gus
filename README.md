# Gus

A small, fast launcher for the Mac by madebyjinn. One field; everything else shows up only when you type.

- **⌥Space** opens it (Settings: ⌃Space, ⌥⌘Space, or ⌘Space once Spotlight's shortcut is off).
- **Search**: apps (in memory, instant, learns what you open), files (the Spotlight index, home folder),
  contacts (after you allow it), the web as the last row.
- **Maths**: `12*(3+4)`, `2^10`, `50 * 20%`, `sqrt(2)`. Return copies.
- **Money**: `$5`, `5 usd`, `€20 in inr`, `10k yen to gbp`. Converts to your currency (from your region, or
  set in Settings). Rates from open.er-api.com, cached, refreshed every 6 h.
- **Clipboard**: Tab in the bar. Text, links, files and images; skips password-manager copies; on this Mac only.
  Return copies (or pastes into the app you were in, with Accessibility).
- **Reminders and calendar**: `remind me to call mum tomorrow at 5`, `today`, `tomorrow`, `calendar friday`.
- **Ask Gus**: end a question with `?` and press Return. Apple Intelligence answers on the Mac by default; Settings › Advanced
  can switch to your own OpenAI or Claude API key, or to Codex or Claude Code if you have them installed.
- **Siri and Shortcuts**: App Intents for Open Gus, Show Clipboard History, Search with Gus, Convert Currency.
  (Siri can't take typed text from another app, so Gus talks to Reminders, Calendar and the on-device model
  directly.)

Design: Zest tokens (`Shared/Zest.swift`), Solid or Liquid Glass, accent dots.
The window is made once and never resizes; the card measures itself and animates its height.

## Build and test

```
scripts/build.sh      # Release build at build/Gus.app (needs Xcode 26 and XcodeGen)
scripts/test.sh       # unit tests: sums, word sums, units, money, reminder sentences
scripts/selftest.sh   # every feature, driven inside the real app
```

`Gus.xcodeproj` is generated: run `scripts/generate.sh` to make it. Set your own signing team in
`project.yml`. The full list of test cases, including the by-hand ones, is in `Tests/TEST-CASES.md`.

## Looks

Solid, Liquid Glass (Apple-native) and Gus: the otter beside a speech bubble (`Sources/GusTheme.swift`,
`Sources/OtterStage.swift`, poses in `Resources/Otter`).

Settings can be flipped by typing ("dark mode", "liquid glass", "open at login").

## Get it

- **Buy it** at [madebyjinn.com/gus](https://madebyjinn.com/gus): the signed app, ready to run, with
  automatic updates. One price, once.
- **Build it yourself** from this repository, free: see above.

## Licence

GPL-3.0 for the code. The name and Gus the otter are not included in that: see `NOTICE.md`.
