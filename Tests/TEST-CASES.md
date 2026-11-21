# Gus test cases

Three layers. Run the first two after any change; walk the third before a release.

| Layer | What it covers | Run |
|---|---|---|
| Unit tests | The pure text work: sums, word sums, units, money parsing, reminder sentences | `scripts/test.sh` |
| In-app self-test | Every feature driven for real inside the app: search, answers, reminders, clipboard, notes, settings, Ask Gus | `scripts/selftest.sh` |
| By hand | What a script can't press or see: shortcuts, pasting, permission prompts, motion | the list at the end |

The self-test quits Gus, starts it with `--selftest`, and puts back what it touches (clipboard, settings,
its two test reminders, its test note). It asks the engine picked in Settings two short questions.

## Unit tests (`Tests/main.swift`)

- **Calculator**: + − × ÷, precedence, brackets, powers, percent, modulo, square root, grouped thousands, the × and ÷ signs; not maths: a lone number, a word, a lone negative, division by zero, an unfinished sum; number formatting.
- **Word sums**: "ten times 12", "15 percent of 80", "half of 37", "three thousand two hundred divided by 4", "9 squared", "square root of 144", "ten minus three", "twenty-five plus 5", "two hundred and five minus 5"; not sums: "best pasta recipe", "ten", "what is".
- **Units**: km↔miles, °F↔°C, cups→ml; mismatched kinds give nothing; plain words give nothing.
- **Money parsing**: "$5", "5 usd", "€20 in inr", "10k yen to gbp", "2m usd in inr", "1,250.50 gbp", "₹500 to usd", "£12.50", "5 dollars to euros"; not money: "page 5", "5 cats", "5", "5 km".
- **Reminder sentences**: "remind me to call naim tonight at 9.30" → "Call naim", today 21:30; "9:30" the same; "tomorrow at 5" → 5 pm tomorrow; no time → no date; "in 20 minutes", "in 2 hours", "in an hour", "in 3 days"; "at 9" asked at noon → 9 pm today; "at 7" asked at 10 pm → 7 am tomorrow; "reminder …" and "todo …"; "remind me", "remind me to", "remind" → no reminder; text without a trigger word → no reminder; capitals kept; "Today/Tomorrow/date" wording.

## In-app self-test (`Sources/SelfTest.swift`)

### Apps

- typing an app's name puts it first
- a prefix finds it
- two words find System Settings
- skipped letters still find Safari
- nonsense finds no apps
- the web search row is always last
- the web row quotes what was typed
- an empty bar shows nothing
- spaces alone show nothing

### Calculator

- 2+2 = 4
- 12*4 = 48
- 2^10 = 1,024
- 10/4 = 2.5
- 50 * 20% = 10
- (3+4)*2 = 14
- sqrt(16)+1 = 5
- 1,200 × 3 = 3,600
- what is ten times 12 = 120
- half of 37 = 18.5
- 15 percent of 80 = 12
- twenty five plus seventeen = 42
- “2024” is not treated as a sum
- “1/0” is not treated as a sum
- “safari” is not treated as a sum
- “what is” is not treated as a sum
- the copy key copies the answer

### Units

- 5 km in miles converts
- 72 f to c converts
- 3 cups to ml converts
- 2 kg to lb converts
- 100 cm in inches converts
- mismatched units give no answer

### Currency

- “20 eur” converts to the local currency
- “$5 to gbp” converts to pounds
- “10k yen to usd” understands k
- an amount already in the local currency converts to USD (or EUR)
- “page 5” is not money
- region United States converts to USD
- region United States uses °F
- region Japan converts to JPY
- region Germany converts to EUR and uses °C
- Automatic follows the Mac
- the region list has countries, sorted by name

### Everyday answers

- “date” answers
- “what day is it” answers
- “time” answers
- “what time is it?” answers
- “battery” answers
- “storage” answers
- “how much space left” answers
- “define serendipity” shows the dictionary
- weather questions are recognised
- weather in London comes back with a temperature
- sunrise and sunset in Tokyo tomorrow
- “what is” alone never goes to the model
- a date sum is worth asking the model
- the on-device model works out a date sum

### Reminders

- the reminder row appears, titled without the time
- its time reads Today 9:30 PM
- a reminder with no time says No date
- “remind me” alone makes no reminder
- list questions are recognised
- creating a reminder saves it in Reminders
- it shows up in the open list with its due time
- “my reminders” lists open reminders
- marking it done takes it off the list
- the test reminder is cleaned up
- Return says “Creating reminder…”
- then says “Reminder set” with the title and time
- and clears the bar

### Calendar

- “today”, “tomorrow”, “this week”, “calendar friday” are recognised
- “today” shows events or says the day is clear

### Contacts

- searching contacts returns people without error
- contact rows can be copied and have a Tab action

### Files

- indexing a folder counts its items
- a file is found by part of its name
- a folder is found and marked as a folder
- node_modules and the like are skipped
- turning file search off empties the index

### Clipboard

- copied text lands at the top of the history
- a copied web address is kept as a link
- a password manager's copy is not kept
- Tab opens the clipboard
- typing filters the history
- picking a clip puts it back on the clipboard
- and moves it to the top
- leaving the clipboard returns to search
- deleting clips removes them

### Notes

- “notes” offers Floating Notes
- “note …” offers to add a note
- a new note holds its text
- an empty note is reused instead of piling up blanks
- stepping forward and back returns to the same note
- deleting removes it and always leaves one note

### Settings

- “settings” offers Gus Settings
- “dark mode” offers the appearance switch
- “liquid glass” offers the look
- “accent …” offers accents
- running a typed setting flips it
- ⌘S opens settings with an empty filter
- closing settings brings the search text back
- look Solid applies
- look Liquid Glass applies
- look Gus applies
- Inverted: dark bar on a light Mac
- the copy key options carry the right modifiers
- a shortcut survives saving and loading
- the Keychain stores a key
- and forgets it when cleared

### Bar

- ↓ moves the selection
- ↑ at the top stays in range
- starting fresh clears the text, rows and mode
- the welcome tour opens on its first step
- next and back move between steps
- the last step returns to search
- a notice shows
- and goes away
- Gus thinks while something is being worked out
- every otter pose has its picture

### Ask Gus

- a question puts “Ask Gus” first
- “ask …” drops the word ask
- asking shows Gus thinking
- Codex on this Mac answers
- ⇧↩ moves into the conversation
- sending a follow-up clears the field and adds a turn
- the follow-up remembers the conversation
- the copy key copies the answer
- ⌫ on an empty field leaves the conversation
- Codex and Claude Code are found when installed
- OpenAI: a wrong key gives a clear message
- Claude: a wrong key gives a clear message

## By hand

Each line is: do this → expect this.

### Opening and closing
1. Press the shortcut (Settings › Shortcut) from another app → the bar appears a fifth of the way down the screen with the pointer, field focused.
2. Press the shortcut again, or Esc, or click outside → it hides.
3. Type something, hide, reopen within the "Start fresh" time → the text is still there. Reopen after it → the bar is empty.
4. With ⌘Space chosen and Spotlight's ⌘Space still on → Settings shows the note about turning Spotlight's off.

### Keys in the bar
5. ↑ ↓ move the selection; Return runs the row; ⌘Return runs the alternate (e.g. mark a reminder done).
6. ⌘A, ⌘C, ⌘V, ⌘X, ⌘Z, ⇧⌘Z work in the field; ⌘W and ⌘H hide the bar.
7. Hover a row and press the copy key (⌥C by default) → "Copied …" and Gus's menu-bar otter winks.
8. Tab on a contact → calls or messages (per Settings); Tab elsewhere → clipboard; Tab or ⌫ on an empty field → back.
9. ⌘S or ⌘, → settings; ⌫ on an empty filter → back. In an API key or model field, ⌫ deletes text and does not leave settings.

### Reminders
10. First ever "remind me to …" + Return → macOS asks for Reminders; Allow → "Reminder set: …" and the reminder is in Reminders.
11. With Reminders turned off for Gus in System Settings → the bar stays open and says Gus isn't allowed, and the Privacy pane opens.
12. Reminder with a time → Reminders shows the same time and alerts then.

### Clipboard
13. Copy text, a link, a file in Finder and an image → each appears with the right kind and source app.
14. Return on a clip with "Return pastes" on and Accessibility allowed → pasted into the app you were in. Without Accessibility → copied, with a note.
15. Copy from a password manager → not kept.

### Floating notes
16. Notes shortcut → the panel floats over other apps; again → hides. Text typed in the bar first moves into a note.
17. Quit and reopen Gus → notes are still there.

### Looks
18. Solid, Liquid Glass and Gus each in light and dark: text readable, selection visible, no clipped rows.
19. Gus look: bubble sits beside Gus from the start; it turns into a thought cloud while something is being worked out; height changes glide.
20. Each accent colours the pill, switches and selection.

### Ask Gus
21. For each engine in Settings › Advanced: ask a question ending in "?", Return, then ⇧↩ and a follow-up → answers, and the follow-up knows the first.
22. OpenAI and Claude with a real key → answers; with the model field changed to a wrong name → a clear message.
23. Wi-Fi off → a clear "couldn't reach" message, not a hang.

### System
24. Open at Login on, log out and in → Gus is running.
25. Menu-bar otter: eyes follow the pointer, blinks, dozes after two quiet minutes, hops when the bar opens.
26. Shortcuts app → Gus's actions (open Gus, show clipboard, search, convert currency) are listed and run.
27. Welcome tour (Settings › General) → four steps, the try-it step answers a sum live, the chosen look applies.
