import AppKit
import SwiftUI
import EventKit
import Combine
import NaturalLanguage

/// The bar's state: what's typed, what's showing, and which row is picked.
@MainActor
final class Launcher: ObservableObject {
    static let shared = Launcher()
    enum Mode { case search, clipboard, settings, chat, welcome }

    @Published var query = "" { didSet { if query != oldValue { update() } } }
    @Published private(set) var hits: [Hit] = []
    @Published var selection = 0
    @Published var mode: Mode = .search
    @Published var visible = false
    @Published var notice: String?
    /// Bumped on every open so the field takes focus again.
    @Published var opened = 0
    /// ⌘ is held: rows show their other action.
    @Published var commandDown = false
    /// The search text, kept while the clipboard or settings show, so Back brings it back.
    private var savedSearch = ""
    /// The row under the pointer, if any: C copies it.
    @Published var hovered: Int?
    /// You picked a row yourself (arrow keys, or a pointer that really moved) since the text last changed.
    /// Until then every new list lands with the first row picked, scrolled into view.
    private(set) var picked = false
    /// Where the pointer was when the rows last changed under it. Rows sliding beneath a pointer that
    /// hasn't moved fire hover events; those mustn't pick anything.
    private var restingPointer: NSPoint?
    /// Bumped whenever the list should go back to its top (new text, a fresh list).
    @Published private(set) var scrollTop = 0
    /// A field inside Settings has the keyboard (an API key, a model name), so ⌫ belongs to it.
    var typingInSettings = false
    @Published var welcomeStep = 0
    /// Something is being worked out off the keystroke (the on-device model, the weather): Gus thinks.
    @Published var working = false
    private var askedCalendar = false

    var show: () -> Void = {}
    var close: () -> Void = {}
    /// Hides Gus, gives focus back to the app you were in, and types ⌘V there.
    var pasteIntoPrevious: () -> Void = {}
    var openNotes: (String?) -> Void = { _ in }

    private var ratesWatch: Any?

    init() {
        // When fresh rates land, redo a money answer that was waiting for them.
        ratesWatch = Rates.shared.$updated.dropFirst().sink { [weak self] _ in
            Task { @MainActor in
                guard let self, Currency.parse(self.query.trimmingCharacters(in: .whitespaces)) != nil else { return }
                self.refresh()
            }
        }
    }
    private var slow: Task<Void, Never>?
    private var slowHits: [Hit] = []
    /// The on-device model's answer for the current text, once it has one.
    private var localHits: [Hit] = []
    private var local: Task<Void, Never>?

    // MARK: Opening

    // MARK: Welcome

    func startWelcome() {
        welcomeStep = 0
        if mode == .search { savedSearch = query }
        mode = .welcome
        query = ""
    }

    func welcomeNext() {
        if welcomeStep >= WelcomePane.steps - 1 { finishWelcome(); return }
        withAnimation(Z.Motion.smooth) { welcomeStep += 1 }
    }

    func welcomeBack() {
        guard welcomeStep > 0 else { return }
        withAnimation(Z.Motion.smooth) { welcomeStep -= 1 }
    }

    func finishWelcome() {
        UserDefaults.standard.set(true, forKey: "didOnboard")
        withAnimation(Z.Motion.smooth) { mode = .search; query = savedSearch }
        opened += 1
    }

    func toggleClipboard() { switchTo(mode == .clipboard ? .search : .clipboard) }
    func toggleSettings() { switchTo(mode == .settings ? .search : .settings) }

    /// Clipboard and settings sit on top of search; leaving either brings the search text back.
    func switchTo(_ next: Mode) {
        guard next != mode else { return }
        if mode == .chat { Assistant.shared.clearAnswer() }
        withAnimation(Z.Motion.smooth) {
            if mode == .search { savedSearch = query }
            mode = next
            query = next == .search ? savedSearch : ""
            selection = 0
            hovered = nil
        }
        if mode == .search { update() }
    }

    func reset() {
        savedSearch = ""
        mode = .search
        query = ""
        selection = 0
        hovered = nil
        hits = []
        slowHits = []
        localHits = []
        Assistant.shared.clearAnswer()
    }

    /// "Creating…", then "Reminder set" (and the bar closes) or what went wrong (and it stays open).
    func createReminder(_ draft: Assistant.ReminderDraft) {
        guard !creatingReminder else { return }
        creatingReminder = true
        working = true
        say("Creating reminder…", for: 30)
        // If macOS has to ask for permission first, its prompt takes the bar away; bring it back after.
        let asking = Assistant.shared.remindersUndecided
        let show = { [weak self] in if asking, self?.visible == false { self?.show() } }
        Task { @MainActor in
            let outcome = await Assistant.shared.create(draft)
            if let log = ProcessInfo.processInfo.environment["GUS_TESTLOG"] {
                try? "\(outcome)\n".write(toFile: log, atomically: true, encoding: .utf8)
            }
            creatingReminder = false
            working = false
            switch outcome {
            case .created(let id):
                lastReminderID = id
                let when = draft.due.map { " · " + ReminderWhen.text($0) } ?? ""
                show()          // the permission prompt may have taken the bar away
                say("Reminder set: \(draft.title)\(when)", for: 2.5)
                query = ""
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                if query.isEmpty, mode == .search { close() }
            case .failed(let why, let openPrivacy):
                show()
                say(why, for: 8)
                if openPrivacy {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!)
                }
            }
        }
    }
    private var creatingReminder = false
    private(set) var lastReminderID: String?

    func say(_ text: String, for seconds: Double = 2.5) {
        withAnimation(Z.Motion.smooth) { notice = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            if self?.notice == text { withAnimation(Z.Motion.smooth) { self?.notice = nil } }
        }
    }

    // MARK: Searching

    /// Instant sources (maths, money, assistant, apps) answer on the keystroke. Contacts and files follow in
    /// one go 30 ms later, merged into a single update, so the list changes once per pause, not twice.
    private func update() {
        if mode == .chat { return }
        // Typing, new or more of it, puts the pick back on the first row.
        resetPick()
        // Editing the question (or erasing it) leaves Apple Intelligence.
        Assistant.shared.clearAnswer()
        let q = query.trimmingCharacters(in: .whitespaces)
        slow?.cancel()
        guard mode == .search, !q.isEmpty else {
            hits = []; selection = 0
            return
        }
        var fast: [Hit] = []
        fast += answers(q)
        fast += notesHits(q)
        fast += SettingsCommands.hits(q)
        fast += assistant(q)
        fast += AppIndex.shared.search(q)
        // Keep the last contacts/files on screen while the new ones are found, if they still match.
        let kept = slowHits.filter { $0.title.lowercased().contains(q.lowercased()) }
        localHits = []
        local?.cancel()
        working = false
        publish(fast + kept, q)

        // Reminders: what's open for today, tomorrow, or everything.
        if let span = Assistant.shared.reminderListAsk(q) {
            local = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled, let self else { return }
                let list = await Assistant.shared.openReminders(span)
                guard !Task.isCancelled, self.query.trimmingCharacters(in: .whitespaces) == q else { return }
                let label = span == .today ? "Today" : span == .tomorrow ? "By tomorrow" : "Open"
                if !Assistant.shared.remindersAllowed {
                    self.localHits = [Hit(id: "rem:allow", icon: .symbol("checklist"), title: "Show your reminders here",
                                          subtitle: "Allow Reminders for Gus in System Settings › Privacy", hint: "Open",
                                          group: .assistant, score: 90,
                                          run: { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!) })]
                } else if list.isEmpty {
                    self.localHits = [Hit(id: "rem:none", icon: .symbol("checkmark.circle"), title: "Nothing to do",
                                          subtitle: "\(label) · all clear", hint: "Open", group: .assistant, score: 90,
                                          run: { Launcher.openReminders() })]
                } else {
                    let now = Date()
                    self.localHits = list.prefix(8).enumerated().map { i, r in
                        let due = r.dueDateComponents?.date
                        var when = "No date"
                        if let due {
                            let hasTime = r.dueDateComponents?.hour != nil
                            when = (due < now && !Calendar.current.isDateInToday(due) ? "Overdue · " : "")
                                + due.formatted(Calendar.current.isDateInToday(due) && hasTime ? .dateTime.hour().minute()
                                                : .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        }
                        let list = r.calendar?.title ?? "Reminders"
                        return Hit(id: "rem:\(r.calendarItemIdentifier)", icon: .symbol("circle"), title: r.title ?? "Reminder",
                                   subtitle: "\(when) · \(list)", hint: "Open", group: .assistant, score: 90 - Double(i),
                                   run: { Launcher.openReminders() },
                                   alternate: { Assistant.shared.complete(r); Launcher.shared.say("Done: \(r.title ?? "reminder")"); Launcher.shared.refresh() },
                                   alternateName: "Mark done", copyText: r.title)
                    }
                }
                self.publish(fast + self.slowHits, q)
            }
            return
        }

        // Weather: where you are (or the place you name), fetched once typing pauses.
        if let ask = General.weatherAsk(q) {
            local = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled, let self else { return }
                self.localHits = [Hit(id: "local", icon: .symbol("cloud.sun"), title: "Checking the weather…",
                                    subtitle: ask.place.map { "In \($0.capitalized)" } ?? "Where you are",
                                    group: .answer, score: 100, big: true, run: {})]
                self.publish(fast + self.slowHits, q)
                self.working = true
                let found = await General.weather(ask)
                self.working = false
                guard !Task.isCancelled, self.query.trimmingCharacters(in: .whitespaces) == q else { return }
                self.localHits = found.map { [$0] } ?? []
                self.publish(fast + self.slowHits, q)
            }
            return
        }

        // Anything the instant parsers missed but sounds like a local question goes to the on-device model,
        // once typing pauses. While you're still typing it works quietly and only shows up if it has a
        // sensible answer; end with "?" and it says so up front ("Working it out…").
        if fast.allSatisfy({ $0.group != .answer && $0.group != .assistant || $0.id == "ask" }), Assistant.shared.modelAvailable,
           LocalAnswers.worthAsking(q) {
            let asked = q.hasSuffix("?")
            local = Task { [weak self] in
                try? await Task.sleep(nanoseconds: asked ? 150_000_000 : 450_000_000)   // wait for a pause in typing
                guard !Task.isCancelled, let self else { return }
                if asked {
                    self.localHits = [Hit(id: "local", icon: .symbol("apple.intelligence"), title: "Working it out…",
                                        subtitle: "On this Mac", group: .answer, score: 100, big: true, run: {})]
                    self.publish(fast + self.slowHits, q)
                }
                self.working = true
                let answer = await LocalAnswers.interpret(q)
                self.working = false
                guard !Task.isCancelled, self.query.trimmingCharacters(in: .whitespaces) == q else { return }
                if let answer {
                    self.localHits = [Hit(id: "local", icon: .symbol("apple.intelligence"), title: answer.title,
                                        subtitle: answer.subtitle, hint: "Copy", group: .answer, score: 100, big: true,
                                        run: { Pasteboard.copy(answer.copy); Launcher.shared.say("Copied \(answer.title)") },
                                        copyText: answer.copy)]
                } else {
                    self.localHits = []
                }
                self.publish(fast + self.slowHits, q)
            }
        }

        slow = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000)
            guard let self, !Task.isCancelled else { return }
            async let people = ContactSearch.shared.search(q)
            let filesOn = Settings.shared.searchFiles
            let files = filesOn ? await Task.detached(priority: .userInitiated) { FileHits.search(q) }.value : []
            var extra = await people
            let looksLikeName = q.count >= 3 && !q.contains(where: \.isNumber) && q.split(separator: " ").count <= 2
                && fast.allSatisfy { $0.group != .answer && $0.group != .assistant }
            if !ContactSearch.shared.allowed, ContactSearch.shared.status == .notDetermined, looksLikeName {
                extra.append(Hit(id: "contacts:allow", icon: .symbol("person.crop.circle.badge.plus"), title: "Search Contacts too",
                                 subtitle: "Let Gus look up people as you type", hint: "Allow", group: .web, score: -3,
                                 run: { ContactSearch.shared.requestAccess() }))
            }
            extra += files
            guard !Task.isCancelled, self.query.trimmingCharacters(in: .whitespaces) == q else { return }
            self.slowHits = extra
            self.publish(fast + extra, q)
        }
    }

    private func publish(_ list: [Hit], _ q: String) {
        var all = list
        all.insert(contentsOf: localHits, at: 0)
        all.append(Hit(id: "web", icon: .symbol("globe"), title: "Search the web for “\(q)”", hint: "Search", group: .web, score: -1,
                       run: {
            var c = URLComponents(string: "https://www.google.com/search")!
            c.queryItems = [URLQueryItem(name: "q", value: q)]
            if let url = c.url { NSWorkspace.shared.open(url) }
        }))
        if Assistant.shared.canAsk, !all.contains(where: { $0.id == "ask" }),
           all.allSatisfy({ $0.group != .answer }), looksLikeEnglish(q) {
            all.append(askHit(q, group: .web, score: -2))
        }
        let sorted = all.enumerated().sorted { a, b in
            a.element.group != b.element.group ? a.element.group < b.element.group
                : (a.element.score != b.element.score ? a.element.score > b.element.score : a.offset < b.offset)
        }.map(\.element)
        // Rows swap in place (no insert/remove animation, which is what made typing jitter); the card's
        // height is the one thing that glides.
        let keepID = hits.indices.contains(selection) ? hits[selection].id : nil
        hits = sorted
        // The rows just moved under the pointer; only a real move of it picks one now.
        restingPointer = NSEvent.mouseLocation
        selection = Selection.pick(after: sorted.map(\.id), keeping: keepID, picked: picked,
                                   answerOnTop: sorted.first?.group == .answer)
    }

    /// Back to the first row, scrolled to the top, and hover ignored until the pointer moves.
    private func resetPick() {
        picked = false
        hovered = nil
        selection = 0
        restingPointer = NSEvent.mouseLocation
        scrollTop &+= 1
    }

    /// A row reports the pointer over it. It picks the row only if the pointer has actually moved since
    /// the rows last changed, not when the list relaid out under a still pointer.
    func pointerOver(_ index: Int) {
        if let resting = restingPointer {
            guard NSEvent.mouseLocation != resting else { return }
            restingPointer = nil
        }
        picked = true
        hovered = index
        if selection != index { selection = index }
    }

    func pointerLeft(_ index: Int) {
        if hovered == index { hovered = nil }
    }

    // MARK: Answers: maths and money

    private func answers(_ q: String) -> [Hit] {
        let everyday = General.instant(q)
        if !everyday.isEmpty { return everyday }
        if let money = Currency.parse(q) {
            Rates.shared.refreshIfStale()
            let to = money.to ?? (money.from == Currency.local ? "USD" : Currency.local)
            if let value = Rates.shared.convert(money.amount, from: money.from, to: to) {
                let shown = Currency.format(value, to)
                let plain = String(format: "%.2f", value)
                let when = Rates.shared.updated.map { RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date()) } ?? ""
                return [Hit(id: "money", icon: .symbol("dollarsign.arrow.circlepath"), title: shown,
                            subtitle: "\(Currency.format(money.amount, money.from)) in \(to) · rates \(when)",
                            hint: "Copy", group: .answer, score: 100, big: true,
                            run: { Pasteboard.copy(plain); Launcher.shared.say("Copied \(shown)") },
                            alternate: { Pasteboard.copy(shown) }, copyText: plain)]
            }
            return [Hit(id: "money", icon: .symbol("dollarsign.arrow.circlepath"), title: "Getting rates…",
                        subtitle: "\(money.from) to \(to)", group: .answer, score: 100, big: true, run: {})]
        }
        if let value = Calculator.evaluate(q) {
            let shown = Calculator.format(value)
            return [Hit(id: "calc", icon: .symbol("equal.circle"), title: shown, subtitle: q,
                        hint: "Copy", group: .answer, score: 100, big: true,
                        run: { Pasteboard.copy(shown.replacingOccurrences(of: ",", with: "")); Launcher.shared.say("Copied \(shown)") },
                        copyText: shown.replacingOccurrences(of: ",", with: ""))]
        }
        // Maths in words ("what is ten times 12"), instantly, by the same calculator.
        if let expr = NumberWords.expression(q), let value = Calculator.evaluate(expr) {
            let shown = Calculator.format(value)
            return [Hit(id: "calc", icon: .symbol("equal.circle"), title: shown, subtitle: expr,
                        hint: "Copy", group: .answer, score: 100, big: true,
                        run: { Pasteboard.copy(shown.replacingOccurrences(of: ",", with: "")); Launcher.shared.say("Copied \(shown)") },
                        copyText: shown.replacingOccurrences(of: ",", with: ""))]
        }
        if let r = Units.parse(q) {
            let d = Units.describe(r)
            return [Hit(id: "calc", icon: .symbol("ruler"), title: d.title, subtitle: d.subtitle,
                        hint: "Copy", group: .answer, score: 100, big: true,
                        run: { Pasteboard.copy(d.plain); Launcher.shared.say("Copied \(d.title)") }, copyText: d.plain)]
        }
        return []
    }

    // MARK: Reminders, calendar, Apple Intelligence

    private func assistant(_ q: String) -> [Hit] {
        let a = Assistant.shared
        var out: [Hit] = []
        if let draft = a.reminderDraft(q) {
            let when = draft.due.map { ReminderWhen.text($0) } ?? "No date"
            out.append(Hit(id: "remind", icon: .symbol("checklist"), title: draft.title, subtitle: "New reminder · \(when)",
                           hint: "Create", group: .assistant, score: 90,
                           run: { Launcher.shared.createReminder(draft) }))
        }
        if let (from, to, label) = a.agendaRange(q) {
            if a.calendarAllowed {
                let events = a.events(from: from, to: to)
                if events.isEmpty {
                    out.append(Hit(id: "cal:none", icon: .symbol("calendar"), title: "Nothing on", subtitle: label,
                                   hint: "Open", group: .assistant, score: 80, run: { Launcher.openCalendar() }))
                }
                let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = label == "This week" ? .short : .none
                for (i, e) in events.prefix(6).enumerated() {
                    let time = e.isAllDay ? "All day" : "\(f.string(from: e.startDate)) – \(DateFormatter.localizedString(from: e.endDate, dateStyle: .none, timeStyle: .short))"
                    out.append(Hit(id: "cal:\(e.eventIdentifier ?? "\(i)")", icon: .symbol("calendar"), title: e.title ?? "Event",
                                   subtitle: "\(label) · \(time)" + (e.location.map { " · \($0)" } ?? ""),
                                   hint: "Open", group: .assistant, score: 80 - Double(i),
                                   run: { Launcher.openCalendar() }))
                }
            } else if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
                // First time you ask about your calendar: macOS asks now, and the events follow.
                if !askedCalendar {
                    askedCalendar = true
                    Assistant.shared.requestCalendar { Launcher.shared.refresh() }
                }
                out.append(Hit(id: "cal:allow", icon: .symbol("calendar"), title: "Allow Calendar to see your events",
                               subtitle: "macOS is asking now", hint: "Allow", group: .assistant, score: 80,
                               run: { Assistant.shared.requestCalendar { Launcher.shared.refresh() } }))
            } else {
                out.append(Hit(id: "cal:allow", icon: .symbol("calendar.badge.exclamationmark"), title: "Calendar is off for Gus",
                               subtitle: "Turn it on in System Settings › Privacy › Calendars", hint: "Open", group: .assistant, score: 80,
                               run: { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!) }))
            }
        }
        // A question ("…?" or "ask …") puts Apple Intelligence first; plain English text gets it as the last
        // row, under the web search (added in publish).
        if a.canAsk, q.count > 3, q.hasSuffix("?") || q.lowercased().hasPrefix("ask ") {
            out.append(askHit(q, group: .assistant, score: 95))
        }
        return out
    }

    private func askHit(_ q: String, group: Hit.Group, score: Double) -> Hit {
        let question = q.lowercased().hasPrefix("ask ") ? String(q.dropFirst(4)) : q
        let engine = Settings.shared.engine
        return Hit(id: "ask", icon: .symbol(engine.symbol), title: "Ask Gus",
                   subtitle: question, hint: "Ask", group: group, score: score,
                   run: { Assistant.shared.ask(question) })
    }

    /// Words, not maths, money or a path, and English when there's enough text to tell.
    private func looksLikeEnglish(_ q: String) -> Bool {
        guard q.count >= 3, q.contains(where: \.isLetter), !q.hasPrefix("/"), !q.hasPrefix("~") else { return false }
        let letters = q.filter { $0.isLetter }
        guard letters.allSatisfy({ $0.isASCII }) else { return false }
        guard q.split(separator: " ").count >= 3 else { return true }
        let r = NLLanguageRecognizer()
        r.processString(q)
        return r.dominantLanguage == .english
    }

    func refresh() { let q = query; query = ""; query = q }

    /// "notes" opens floating notes; "note buy milk" puts "buy milk" in a new one.
    private func notesHits(_ q: String) -> [Hit] {
        let l = q.lowercased()
        // "settings", "preferences", "gus settings": Gus's own settings, right here in the bar.
        if l.count >= 3, ["settings", "preferences", "gus settings", "gus preferences"].contains(where: { $0.hasPrefix(l) }) {
            return [Hit(id: "gus:settings", icon: .symbol("gearshape"), title: "Gus Settings", subtitle: "Shortcut, look, clipboard, files · ⌘S",
                        hint: "Open", group: .apps, score: 95, run: { Launcher.shared.switchTo(.settings) })]
        }
        let key = Settings.shared.notesHotkey.label
        if ["note", "notes", "floating notes", "sticky", "scratch"].contains(where: { $0.hasPrefix(l) }) && l.count >= 3 {
            return [Hit(id: "notes:open", icon: .symbol("note.text"), title: "Floating Notes", subtitle: "Opens anywhere with \(key)",
                        hint: "Open", group: .apps, score: 90, run: { Launcher.shared.openNotes(nil) })]
        }
        if l.hasPrefix("note "), q.count > 5 {
            let text = String(q.dropFirst(5))
            return [Hit(id: "notes:add", icon: .symbol("square.and.pencil"), title: "New note: \(text)",
                        subtitle: "Or press \(key) with any text in the bar", hint: "Add", group: .assistant, score: 85,
                        run: { Launcher.shared.openNotes(text) })]
        }
        return []
    }

    static func openReminders() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    static func openCalendar() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    // MARK: Keys

    var selectedHit: Hit? { hits.indices.contains(selection) ? hits[selection] : nil }

    var rowCount: Int { mode == .clipboard ? clipboardShown.count : hits.count }

    var clipboardShown: [ClipboardHistory.Clip] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let all = ClipboardHistory.shared.clips
        return q.isEmpty ? Array(all.prefix(60)) : all.filter { $0.text.lowercased().contains(q) }.prefix(60).map { $0 }
    }

    func move(_ delta: Int) {
        let n = rowCount
        guard n > 0 else { return }
        picked = true
        selection = (selection + delta + n) % n
    }

    /// C on a hovered contact or clip, and ⌘C on the picked one: copy it, stay open.
    func copy(at index: Int) {
        if mode == .clipboard {
            let clips = clipboardShown
            guard clips.indices.contains(index) else { return }
            ClipboardHistory.shared.use(clips[index])
            say("Copied")
        } else if hits.indices.contains(index), let text = hits[index].copyText {
            Pasteboard.copy(text)
            say("Copied \(text)")
        }
    }

    /// The copy key (⌥C by default): the row under the pointer, else the picked one.
    func copyPicked() {
        if mode == .chat, let text = Assistant.shared.answer { Pasteboard.copy(text); say("Copied the answer"); return }
        copy(at: hovered ?? selection)
    }

    /// ⇧↩ after an answer: keep talking. The question moves into the conversation and the field clears
    /// for the next one.
    func continueChat() {
        let a = Assistant.shared
        if mode == .chat { activate(); return }
        guard mode == .search, a.answer != nil || a.thinking else { return }
        withAnimation(Z.Motion.smooth) {
            savedSearch = ""
            mode = .chat
            query = ""
        }
    }

    func leaveChat() {
        withAnimation(Z.Motion.smooth) {
            mode = .search
            Assistant.shared.clearAnswer()
            query = ""
        }
    }

    /// Tab: call or message the picked contact; otherwise flip to the clipboard and back.
    func tab() {
        if mode == .search, let hit = selectedHit, let action = hit.tab {
            action(); close(); return
        }
        if mode == .settings { return }
        toggleClipboard()
    }

    func activate(alternate: Bool = false) {
        if mode == .settings { return }
        if mode == .chat {
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if q.isEmpty {
                if let text = Assistant.shared.answer { Pasteboard.copy(text); say("Copied the answer") }
            } else {
                Assistant.shared.ask(q, continuing: true)
                query = ""
            }
            return
        }
        if mode == .clipboard {
            let clips = clipboardShown
            guard clips.indices.contains(selection) else { return }
            ClipboardHistory.shared.use(clips[selection])
            if UserDefaults.standard.object(forKey: "pasteDirectly") as? Bool ?? true {
                if AXIsProcessTrusted() {
                    pasteIntoPrevious()
                } else {
                    Pasteboard.askForAccessibility()
                    say("Copied. Allow Accessibility and Gus pastes it for you")
                }
            } else {
                close()
            }
            return
        }
        if Assistant.shared.answer != nil, let text = Assistant.shared.answer {
            Pasteboard.copy(text); say("Copied the answer"); return
        }
        guard hits.indices.contains(selection) else { return }
        let hit = hits[selection]
        if alternate, let alt = hit.alternate {
            alt()
            if hit.id.hasPrefix("rem:") { return }
        } else { hit.run() }
        // Asking and allowing keep the bar open; everything else is done.
        if !["ask", "remind", "contacts:allow", "cal:allow", "gus:settings"].contains(hit.id) && !hit.id.hasPrefix("set:") && !hit.id.hasPrefix("money") && !hit.id.hasPrefix("calc") && hit.id != "local" {
            close()
        } else if hit.id == "money" || hit.id == "calc" || hit.id == "local" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { Launcher.shared.close() }
        }
    }
}
