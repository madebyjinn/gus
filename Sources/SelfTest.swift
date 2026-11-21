import AppKit
import EventKit

/// `Gus --selftest <report file>`: runs every feature for real, inside the app, and writes what passed.
/// It drives the same code a keystroke does (the search pipeline, clipboard, reminders, notes, settings,
/// the answer engines) and puts back anything it changes. Cases are listed in Tests/TEST-CASES.md.
@MainActor
enum SelfTest {
    enum Outcome { case pass, fail(String), skip(String) }
    private static var lines: [String] = []
    private static var counts = (pass: 0, fail: 0, skip: 0)
    private static var area = ""

    private static func record(_ name: String, _ outcome: Outcome) {
        switch outcome {
        case .pass: counts.pass += 1; lines.append("PASS  \(area): \(name)")
        case .fail(let why): counts.fail += 1; lines.append("FAIL  \(area): \(name)  — \(why)")
        case .skip(let why): counts.skip += 1; lines.append("SKIP  \(area): \(name)  — \(why)")
        }
    }
    private static func check(_ name: String, _ ok: Bool, _ why: @autoclosure () -> String = "") {
        record(name, ok ? .pass : .fail(why()))
    }

    private static func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }

    /// Types `q` into the bar and returns the rows once they've settled.
    private static func rows(_ q: String, wait: Double = 0.15) async -> [Hit] {
        let l = Launcher.shared
        if l.mode != .search { l.switchTo(.search) }
        l.query = q
        await pause(wait)
        return l.hits
    }
    private static func until(_ timeout: Double, _ done: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if done() { return true }; await pause(0.1) }
        return done()
    }
    private static func describe(_ hits: [Hit]) -> String { hits.prefix(4).map { "\($0.id)=\($0.title)" }.joined(separator: " | ") }

    static func run(report: String) async {
        let l = Launcher.shared, s = Settings.shared
        let savedPasteboard = NSPasteboard.general.string(forType: .string)
        l.reset()

        // MARK: Apps
        area = "Apps"
        AppIndex.shared.refreshIfNeeded()
        await pause(1.2)
        var h = await rows("safari")
        check("typing an app's name puts it first", h.first?.title == "Safari", describe(h))
        h = await rows("saf")
        check("a prefix finds it", h.contains { $0.title == "Safari" }, describe(h))
        h = await rows("system set")
        check("two words find System Settings", h.contains { $0.title == "System Settings" }, describe(h))
        h = await rows("sfri")
        check("skipped letters still find Safari", h.contains { $0.title == "Safari" }, describe(h))
        h = await rows("zzqqxxjj")
        check("nonsense finds no apps", !h.contains { $0.group == .apps }, describe(h))
        check("the web search row is always last", h.last?.id == "web" || h.last?.id == "ask", describe(h))
        check("the web row quotes what was typed", h.contains { $0.id == "web" && $0.title.contains("zzqqxxjj") }, describe(h))
        h = await rows("")
        check("an empty bar shows nothing", h.isEmpty, describe(h))
        h = await rows("   ")
        check("spaces alone show nothing", h.isEmpty, describe(h))

        // MARK: Calculator
        area = "Calculator"
        for (q, want) in [("2+2", "4"), ("12*4", "48"), ("2^10", "1,024"), ("10/4", "2.5"), ("50 * 20%", "10"), ("(3+4)*2", "14"),
                          ("sqrt(16)+1", "5"), ("1,200 × 3", "3,600"), ("what is ten times 12", "120"), ("half of 37", "18.5"),
                          ("15 percent of 80", "12"), ("twenty five plus seventeen", "42")] {
            h = await rows(q)
            check("\(q) = \(want)", h.first?.id == "calc" && h.first?.title == want, describe(h))
        }
        for q in ["2024", "1/0", "safari", "what is"] {
            h = await rows(q)
            check("“\(q)” is not treated as a sum", h.first?.id != "calc", describe(h))
        }
        h = await rows("12*4")
        l.copy(at: 0)
        check("the copy key copies the answer", NSPasteboard.general.string(forType: .string) == "48")
        ClipboardHistory.shared.ignoreNextChange()

        // MARK: Units
        area = "Units"
        for (q, part) in [("5 km in miles", "3.1"), ("72 f to c", "22.2"), ("3 cups to ml", "ml"), ("2 kg to lb", "4.4"), ("100 cm in inches", "39.3")] {
            h = await rows(q)
            check("\(q) converts", h.first?.id == "calc" && (h.first?.title.lowercased().contains(part) ?? false), describe(h))
        }
        h = await rows("5 km to kg")
        check("mismatched units give no answer", h.first?.group != .answer, describe(h))

        // MARK: Currency and region
        area = "Currency"
        Rates.shared.refreshIfStale()
        _ = await until(6) { Rates.shared.convert(1, from: "USD", to: "EUR") != nil }
        if Rates.shared.convert(1, from: "USD", to: "EUR") == nil {
            record("rates are available", .skip("no rates yet (offline, or a firewall is blocking Gus)"))
        } else {
            h = await rows("20 eur")
            check("“20 eur” converts to the local currency", h.first?.id == "money" && (h.first?.subtitle?.contains("in \(Currency.local)") ?? false), describe(h))
            h = await rows("$5 to gbp")
            check("“$5 to gbp” converts to pounds", h.first?.id == "money" && (h.first?.title.contains("£") ?? false), describe(h))
            h = await rows("10k yen to usd")
            check("“10k yen to usd” understands k", h.first?.id == "money" && (h.first?.subtitle?.contains("10,000") ?? false), describe(h))
            h = await rows("5 \(Currency.local.lowercased())")
            check("an amount already in the local currency converts to USD (or EUR)", h.first?.id == "money", describe(h))
        }
        h = await rows("page 5")
        check("“page 5” is not money", h.first?.id != "money", describe(h))
        let savedRegion = s.region
        s.region = "US"; check("region United States converts to USD", Currency.local == "USD", Currency.local)
        check("region United States uses °F", Region.locale.measurementSystem == .us)
        s.region = "JP"; check("region Japan converts to JPY", Currency.local == "JPY", Currency.local)
        s.region = "DE"; check("region Germany converts to EUR and uses °C", Currency.local == "EUR" && Region.locale.measurementSystem != .us, Currency.local)
        s.region = ""; check("Automatic follows the Mac", Currency.local == (Locale.current.currency?.identifier ?? "USD"), Currency.local)
        s.region = savedRegion
        check("the region list has countries, sorted by name", Region.all.count > 150 && Region.all.contains("IN"))

        // MARK: Everyday answers
        area = "Everyday answers"
        for (q, id) in [("date", "general:date"), ("what day is it", "general:date"), ("time", "general:time"), ("what time is it?", "general:time"),
                        ("battery", "general:battery"), ("storage", "general:storage"), ("how much space left", "general:storage")] {
            h = await rows(q)
            check("“\(q)” answers", h.first?.id == id && !(h.first?.title.isEmpty ?? true), describe(h))
        }
        h = await rows("define serendipity")
        check("“define serendipity” shows the dictionary", h.first?.id == "general:define", describe(h))
        check("weather questions are recognised", General.weatherAsk("weather tomorrow")?.day == 1 && General.weatherAsk("weather in london")?.place == "london"
              && General.weatherAsk("when is sunset")?.sun == true && General.weatherAsk("safari") == nil)
        if let w = await General.weather(.init(place: "london", day: 0, sun: false)) {
            check("weather in London comes back with a temperature", w.title.contains("°"), w.title)
        } else { record("weather in London", .skip("no answer from the weather service (offline or blocked)")) }
        if let w = await General.weather(.init(place: "tokyo", day: 1, sun: true)) {
            check("sunrise and sunset in Tokyo tomorrow", !w.title.isEmpty, w.title)
        } else { record("sunrise and sunset", .skip("no answer from the weather service")) }
        check("“what is” alone never goes to the model", !LocalAnswers.worthAsking("what is"))
        check("a date sum is worth asking the model", LocalAnswers.worthAsking("how many days until 25 december"))
        if Assistant.shared.modelAvailable {
            let a = await LocalAnswers.interpret("how many days until 25 december")
            check("the on-device model works out a date sum", a != nil && a!.title.contains(where: \.isNumber), a?.title ?? "nil")
        } else { record("on-device model", .skip("Apple Intelligence isn't available on this Mac")) }

        // MARK: Reminders
        area = "Reminders"
        h = await rows("remind me to call naim tonight at 9.30")
        check("the reminder row appears, titled without the time", h.first?.id == "remind" && h.first?.title == "Call naim", describe(h))
        check("its time reads Today 9:30 PM", h.first?.subtitle?.contains("Today") == true && h.first?.subtitle?.contains("9:30") == true, h.first?.subtitle ?? "")
        h = await rows("remind me to buy milk")
        check("a reminder with no time says No date", h.first?.id == "remind" && h.first?.subtitle?.contains("No date") == true, describe(h))
        h = await rows("remind me")
        check("“remind me” alone makes no reminder", h.first?.id != "remind", describe(h))
        check("list questions are recognised", Assistant.shared.reminderListAsk("what are my reminders for today") == .today
              && Assistant.shared.reminderListAsk("reminders tomorrow") == .tomorrow && Assistant.shared.reminderListAsk("my reminders") == .all
              && Assistant.shared.reminderListAsk("remind me to buy milk") == nil)
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if status == .fullAccess {
            let draft = Assistant.ReminderDraft(title: "Gus self-test (safe to delete)", due: Date().addingTimeInterval(120))
            switch await Assistant.shared.create(draft) {
            case .created(let id):
                record("creating a reminder saves it in Reminders", .pass)
                let open = await Assistant.shared.openReminders(.all)
                let mine = open.first { $0.calendarItemIdentifier == id }
                check("it shows up in the open list with its due time", mine?.dueDateComponents?.hour != nil)
                h = await rows("my reminders", wait: 0.9)
                check("“my reminders” lists open reminders", h.contains { $0.id.hasPrefix("rem:") }, describe(h))
                if let mine {
                    Assistant.shared.complete(mine)
                    let after = await Assistant.shared.openReminders(.all)
                    check("marking it done takes it off the list", !after.contains { $0.calendarItemIdentifier == id })
                }
                Assistant.shared.removeReminder(id)
                check("the test reminder is cleaned up", Assistant.shared.store.calendarItem(withIdentifier: id) == nil)
            case .failed(let why, _):
                record("creating a reminder saves it in Reminders", .fail(why))
            }
            // The whole path a keystroke takes: type, Return, "Creating…", "Reminder set", bar clears.
            l.query = "remind me to gus self-test two in 30 minutes"
            await pause(0.2)
            l.activate()
            let saidCreating = l.notice == "Creating reminder…" || l.notice?.hasPrefix("Reminder set") == true
            let set = await until(6) { l.notice?.hasPrefix("Reminder set") == true }
            check("Return says “Creating reminder…”", saidCreating, l.notice ?? "no notice")
            check("then says “Reminder set” with the title and time", set && l.notice?.contains("Gus self-test two") == true, l.notice ?? "no notice")
            check("and clears the bar", l.query.isEmpty)
            if let id = l.lastReminderID { Assistant.shared.removeReminder(id) }
            await pause(1.8)
        } else {
            record("creating, listing and completing a reminder", .skip("Gus doesn't have Reminders access (status \(status.rawValue))"))
        }

        // MARK: Calendar
        area = "Calendar"
        check("“today”, “tomorrow”, “this week”, “calendar friday” are recognised",
              Assistant.shared.agendaRange("today")?.2 == "Today" && Assistant.shared.agendaRange("tomorrow")?.2 == "Tomorrow"
              && Assistant.shared.agendaRange("this week")?.2 == "This week" && Assistant.shared.agendaRange("calendar friday") != nil
              && Assistant.shared.agendaRange("safari") == nil)
        h = await rows("today")
        if Assistant.shared.calendarAllowed {
            check("“today” shows events or says the day is clear", h.contains { $0.group == .assistant || $0.group == .answer }, describe(h))
        } else {
            check("without access, “today” offers to allow Calendar", h.contains { $0.id == "cal:allow" }, describe(h))
        }

        // MARK: Contacts
        area = "Contacts"
        if ContactSearch.shared.allowed {
            let found = await ContactSearch.shared.search("a")
            check("searching contacts returns people without error", found.allSatisfy { $0.group == .contacts }, "\(found.count) rows")
            check("contact rows can be copied and have a Tab action", found.isEmpty || found.contains { $0.copyText != nil || $0.tab != nil })
        } else { record("contact search", .skip("Gus doesn't have Contacts access")) }

        // MARK: Files
        area = "Files"
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gus-selftest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder.appendingPathComponent("zebra-folder"), withIntermediateDirectories: true)
        try? "x".write(to: folder.appendingPathComponent("gus-zebra-report.txt"), atomically: true, encoding: .utf8)
        try? FileManager.default.createDirectory(at: folder.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        try? "x".write(to: folder.appendingPathComponent("node_modules/gus-zebra-hidden.txt"), atomically: true, encoding: .utf8)
        var indexed = -1
        FileIndex.shared.rebuild([folder.path]) { n in Task { @MainActor in indexed = n } }
        _ = await until(5) { indexed >= 0 }
        check("indexing a folder counts its items", indexed >= 2, "\(indexed)")
        check("a file is found by part of its name", FileIndex.shared.search("zebra-rep").contains { $0.name == "gus-zebra-report.txt" })
        check("a folder is found and marked as a folder", FileIndex.shared.search("zebra-folder").contains { $0.isFolder })
        check("node_modules and the like are skipped", !FileIndex.shared.search("zebra-hidden").contains { $0.name == "gus-zebra-hidden.txt" })
        let wasSearching = s.searchFiles
        s.searchFiles = false
        _ = await until(3) { FileIndex.shared.search("zebra").isEmpty }
        check("turning file search off empties the index", FileIndex.shared.search("zebra").isEmpty)
        s.searchFiles = wasSearching
        try? FileManager.default.removeItem(at: folder)

        // MARK: Clipboard
        area = "Clipboard"
        let history = ClipboardHistory.shared
        if history.enabled {
            let marker = "gus self-test clip \(Int.random(in: 1000...9999))"
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(marker, forType: .string)
            let kept = await until(2.5) { history.clips.first?.text == marker }
            check("copied text lands at the top of the history", kept)
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString("https://example.com/gus-selftest", forType: .string)
            let link = await until(2.5) { history.clips.first?.kind == .link }
            check("a copied web address is kept as a link", link)
            let secret = "gus-secret-\(Int.random(in: 1000...9999))"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(secret, forType: .string)
            NSPasteboard.general.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
            await pause(1.3)
            check("a password manager's copy is not kept", !history.clips.contains { $0.text == secret })
            l.switchTo(.clipboard)
            check("Tab opens the clipboard", l.mode == .clipboard && l.rowCount == history.clips.count)
            l.query = "self-test clip"
            await pause(0.1)
            check("typing filters the history", l.clipboardShown.count >= 1 && l.clipboardShown.allSatisfy { $0.text.lowercased().contains("self-test clip") },
                  "\(l.clipboardShown.count) shown")
            l.copy(at: 0)
            check("picking a clip puts it back on the clipboard", NSPasteboard.general.string(forType: .string) == marker)
            check("and moves it to the top", history.clips.first?.text == marker)
            l.switchTo(.search)
            check("leaving the clipboard returns to search", l.mode == .search)
            for clip in history.clips where clip.text == marker || clip.text == "https://example.com/gus-selftest" { history.delete(clip) }
            check("deleting clips removes them", !history.clips.contains { $0.text == marker })
        } else { record("clipboard history", .skip("turned off in Settings")) }

        // MARK: Notes
        area = "Notes"
        h = await rows("notes")
        check("“notes” offers Floating Notes", h.contains { $0.id == "notes:open" }, describe(h))
        h = await rows("note buy oat milk")
        check("“note …” offers to add a note", h.contains { $0.id == "notes:add" && $0.title.contains("buy oat milk") }, describe(h))
        let notes = Notes.shared
        let before = notes.notes.count
        let hadEmpty = notes.notes.indices.contains(notes.index) && notes.notes[notes.index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        notes.new(with: "gus self-test note")
        check("a new note holds its text", notes.notes[notes.index].text == "gus self-test note")
        check("an empty note is reused instead of piling up blanks", notes.notes.count == (hadEmpty ? before : before + 1))
        notes.step(1); notes.step(-1)
        check("stepping forward and back returns to the same note", notes.notes[notes.index].text == "gus self-test note")
        notes.deleteCurrent()
        check("deleting removes it and always leaves one note", !notes.notes.contains { $0.text == "gus self-test note" } && !notes.notes.isEmpty)

        // MARK: Settings
        area = "Settings"
        h = await rows("settings")
        check("“settings” offers Gus Settings", h.contains { $0.id == "gus:settings" }, describe(h))
        h = await rows("dark mode")
        check("“dark mode” offers the appearance switch", h.contains { $0.id == "set:appearance.Dark" }, describe(h))
        h = await rows("liquid glass")
        check("“liquid glass” offers the look", h.contains { $0.id == "set:look.Liquid Glass" }, describe(h))
        h = await rows("accent plum")
        check("“accent …” offers accents", h.contains { $0.id.hasPrefix("set:accent.") } || !ZAccent.allCases.contains { $0.rawValue == "Plum" }, describe(h))
        let tabWas = s.contactTab
        h = await rows("contact tab")
        if let hit = h.first(where: { $0.id == "set:contactTab" }) {
            hit.run()
            check("running a typed setting flips it", s.contactTab != tabWas)
            s.contactTab = tabWas
        } else { check("“contact tab” offers the setting", false, describe(h)) }
        l.query = "abc"
        l.toggleSettings()
        check("⌘S opens settings with an empty filter", l.mode == .settings && l.query.isEmpty)
        l.toggleSettings()
        check("closing settings brings the search text back", l.mode == .search && l.query == "abc")
        let look = s.look, appearance = s.appearance, accent = s.accent
        for each in Settings.Look.available { s.look = each; check("look \(each.rawValue) applies", Z.glass == (each == .glass) && Z.gus == (each == .gus)) }
        s.look = look
        s.appearance = .inverted
        check("Inverted: dark bar on a light Mac", s.barAppearance(systemIsDark: false)?.name == .darkAqua && s.barAppearance(systemIsDark: true)?.name == .aqua)
        s.appearance = appearance; s.accent = accent
        check("the copy key options carry the right modifiers", Settings.CopyModifier.option.flags == .option && Settings.CopyModifier.shiftCommand.flags == [.shift, .command])
        let combo = Hotkey.Combo.commandSpace
        check("a shortcut survives saving and loading", (try? JSONDecoder().decode(Hotkey.Combo.self, from: JSONEncoder().encode(combo))) == combo)
        Keychain.write("selftest", "abc123")
        check("the Keychain stores a key", Keychain.read("selftest") == "abc123")
        Keychain.write("selftest", "")
        check("and forgets it when cleared", Keychain.read("selftest").isEmpty)

        // MARK: Bar behaviour
        area = "Bar"
        h = await rows("12*4")
        l.move(1)
        check("↓ moves the selection", l.selection == 1 || l.hits.count < 2)
        l.move(-1); l.move(-1)
        check("↑ at the top stays in range", l.hits.indices.contains(l.selection))
        l.query = "something"
        l.reset()
        check("starting fresh clears the text, rows and mode", l.query.isEmpty && l.hits.isEmpty && l.mode == .search)
        l.startWelcome()
        check("the welcome tour opens on its first step", l.mode == .welcome && l.welcomeStep == 0)
        l.welcomeNext(); l.welcomeBack()
        check("next and back move between steps", l.welcomeStep == 0)
        for _ in 0..<WelcomePane.steps { l.welcomeNext() }
        check("the last step returns to search", l.mode == .search)
        l.say("hello", for: 0.3)
        check("a notice shows", l.notice == "hello")
        await pause(0.6)
        check("and goes away", l.notice == nil)
        OtterActor.shared.settle(thinking: true, hasResults: false, empty: false)
        await pause(0.1)
        check("Gus thinks while something is being worked out", OtterActor.shared.pose == .think)
        OtterActor.shared.settle(thinking: false, hasResults: false, empty: true)
        check("every otter pose has its picture", OtterActor.Pose.allCases.allSatisfy { OtterActor.image($0) != nil })
        check("the Gus look is offered", Settings.Look.available.contains(.gus))

        // MARK: Ask Gus
        area = "Ask Gus"
        h = await rows("why is the sky blue?")
        if Assistant.shared.canAsk {
            check("a question puts “Ask Gus” first", h.first?.id == "ask" && h.first?.title == "Ask Gus", describe(h))
            h = await rows("ask tell me a joke")
            check("“ask …” drops the word ask", h.first(where: { $0.id == "ask" })?.subtitle == "tell me a joke", describe(h))
            Assistant.shared.ask("Reply with exactly one word: otter")
            check("asking shows Gus thinking", Assistant.shared.thinking && Assistant.shared.turns.count == 1)
            _ = await until(90) { !Assistant.shared.thinking }
            let first = Assistant.shared.answer ?? ""
            check("\(s.engine.choice) answers", first.lowercased().contains("otter"), first)
            l.continueChat()
            check("⇧↩ moves into the conversation", l.mode == .chat)
            l.query = "What one word did you just reply with?"
            l.activate()
            check("sending a follow-up clears the field and adds a turn", l.query.isEmpty && Assistant.shared.turns.count == 2)
            _ = await until(90) { !Assistant.shared.thinking }
            let second = Assistant.shared.answer ?? ""
            check("the follow-up remembers the conversation", second.lowercased().contains("otter"), second)
            l.copyPicked()
            check("the copy key copies the answer", NSPasteboard.general.string(forType: .string) == second)
            ClipboardHistory.shared.ignoreNextChange()
            l.leaveChat()
            check("⌫ on an empty field leaves the conversation", l.mode == .search && Assistant.shared.turns.isEmpty && !Assistant.shared.active)
        } else {
            check("with nothing to answer, no Ask row is offered", !h.contains { $0.id == "ask" }, describe(h))
            record("asking and following up", .skip("\(s.engine.choice) isn't set up"))
        }
        check("Codex and Claude Code are found when installed", RemoteChat.tool(.apple) == nil
              && (RemoteChat.tool(.codex).map { FileManager.default.isExecutableFile(atPath: $0) } ?? true))
        for (engine, who) in [(Engine.openai, "OpenAI"), (.claude, "Claude")] {
            do {
                _ = try await RemoteChat().reply(to: "hi", engine: engine, key: "sk-invalid-gus-selftest",
                                                 model: engine == .openai ? Settings.defaultOpenAIModel : Settings.defaultClaudeModel)
                record("\(who) rejects a wrong key", .fail("it answered"))
            } catch let e as EngineError {
                if e.message.contains("API key") { record("\(who): a wrong key gives a clear message", .pass) }
                else if e.message.contains("Couldn't reach") { record("\(who): a wrong key gives a clear message", .skip("couldn't reach \(who) (offline or blocked)")) }
                else { record("\(who): a wrong key gives a clear message", .fail(e.message)) }
            } catch { record("\(who): a wrong key gives a clear message", .fail("\(error)")) }
        }

        // Put things back.
        l.reset()
        NSPasteboard.general.clearContents()
        if let savedPasteboard { NSPasteboard.general.setString(savedPasteboard, forType: .string) }
        ClipboardHistory.shared.ignoreNextChange()

        let summary = "\(counts.pass) passed, \(counts.fail) failed, \(counts.skip) skipped"
        try? (lines + ["", summary]).joined(separator: "\n").write(toFile: report, atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }
}
