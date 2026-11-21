import AppKit
import EventKit
import FoundationModels

/// Reminders and calendar right in the bar ("remind me to call mum tomorrow at 5", "today", "calendar
/// friday"), and "Ask Gus" for a question, answered by the on-device model. Siri itself
/// can't take typed text from another app, so Gus talks to the same system services directly and
/// exposes its own actions to Siri and Shortcuts through App Intents (Intents.swift).
@MainActor
final class Assistant: ObservableObject {
    static let shared = Assistant()
    private(set) var store = EKEventStore()
    @Published var answer: String?
    @Published var thinking = false
    private var answering: Task<Void, Never>?

    // MARK: Reminders

    typealias ReminderDraft = ReminderParser.Draft

    func reminderDraft(_ text: String) -> ReminderDraft? { ReminderParser.draft(text) }

    enum ReminderOutcome { case created(String), failed(String, openPrivacy: Bool) }

    /// Saves the reminder and says what happened. Asks for access first if macOS hasn't been asked yet.
    func create(_ draft: ReminderDraft) async -> ReminderOutcome {
        var status = EKEventStore.authorizationStatus(for: .reminder)
        if status == .notDetermined {
            _ = try? await store.requestFullAccessToReminders()
            status = EKEventStore.authorizationStatus(for: .reminder)
            // The store that asked was made without access; a new one sees the lists.
            if status == .fullAccess { store = EKEventStore() }
        }
        guard status == .fullAccess else {
            return .failed("Gus isn't allowed to use Reminders. Turn it on in System Settings › Privacy › Reminders.", openPrivacy: true)
        }
        // A store made before access was granted can't see any lists: start a fresh one if so.
        var store = self.store
        if store.defaultCalendarForNewReminders() == nil, store.calendars(for: .reminder).isEmpty {
            store = EKEventStore()
            self.store = store
        }
        let list = store.defaultCalendarForNewReminders()
            ?? store.calendars(for: .reminder).first { $0.allowsContentModifications }
        guard let list else { return .failed("There's no Reminders list to add to. Open Reminders once and try again.", openPrivacy: false) }
        let r = EKReminder(eventStore: store)
        r.title = draft.title
        r.calendar = list
        if let due = draft.due {
            r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            r.addAlarm(EKAlarm(absoluteDate: due))
        }
        do {
            try store.save(r, commit: true)
        } catch {
            return .failed("Couldn't save the reminder: \(error.localizedDescription)", openPrivacy: false)
        }
        // Read it back: only say it's set once Reminders really has it.
        guard store.calendarItem(withIdentifier: r.calendarItemIdentifier) != nil else {
            return .failed("Reminders didn't keep that one. Try again.", openPrivacy: false)
        }
        return .created(r.calendarItemIdentifier)
    }

    func removeReminder(_ id: String) {
        if let r = store.calendarItem(withIdentifier: id) as? EKReminder { try? store.remove(r, commit: true) }
    }

    // MARK: Calendar

    // MARK: Reminders list

    enum ReminderSpan { case today, tomorrow, all }

    /// "reminders", "my reminders", "reminders for today", "what are my reminders", "todo", "to-dos tomorrow".
    func reminderListAsk(_ text: String) -> ReminderSpan? {
        let l = text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " ?.!"))
        let keys = ["reminders", "my reminders", "reminder list", "todos", "to-dos", "to dos", "todo list", "to do list",
                    "my tasks", "tasks"]
        guard keys.contains(where: { l == $0 || l.contains($0) }), reminderDraft(text) == nil else { return nil }
        if l.contains("tomorrow") { return .tomorrow }
        if l.contains("today") { return .today }
        return .all
    }

    var remindersUndecided: Bool { EKEventStore.authorizationStatus(for: .reminder) == .notDetermined }
    var remindersAllowed: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }

    /// Open reminders: due by the end of the day asked for (overdue included), or everything open.
    func openReminders(_ span: ReminderSpan) async -> [EKReminder] {
        if !remindersAllowed { _ = try? await store.requestFullAccessToReminders() }
        guard remindersAllowed else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end: Date? = {
            switch span {
            case .today: return cal.date(byAdding: .day, value: 1, to: start)
            case .tomorrow: return cal.date(byAdding: .day, value: 2, to: start)
            case .all: return nil
            }
        }()
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil)
        let store = self.store
        let found: [EKReminder] = await withCheckedContinuation { c in
            store.fetchReminders(matching: predicate) { c.resume(returning: $0 ?? []) }
        }
        return found.sorted {
            let a = $0.dueDateComponents?.date ?? .distantFuture, b = $1.dueDateComponents?.date ?? .distantFuture
            return a != b ? a < b : ($0.title ?? "") < ($1.title ?? "")
        }
    }

    func complete(_ reminder: EKReminder) {
        reminder.isCompleted = true
        try? store.save(reminder, commit: true)
    }

    /// "today", "tomorrow", "calendar", "agenda", "this week", "calendar friday".
    func agendaRange(_ text: String) -> (Date, Date, String)? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        let triggers = ["today", "tomorrow", "calendar", "agenda", "schedule", "events", "meetings", "this week", "what's on", "whats on"]
        guard triggers.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") }) else { return nil }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        if lower == "today" { return (Date(), cal.date(byAdding: .day, value: 1, to: start)!, "Today") }
        if lower.contains("week") { return (Date(), cal.date(byAdding: .day, value: 7, to: start)!, "This week") }
        if lower.hasPrefix("tomorrow") {
            let t = cal.date(byAdding: .day, value: 1, to: start)!
            return (t, cal.date(byAdding: .day, value: 1, to: t)!, "Tomorrow")
        }
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
           let date = detector.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower))?.date {
            let d = cal.startOfDay(for: date)
            let f = DateFormatter(); f.dateFormat = "EEEE d MMM"
            return (d, cal.date(byAdding: .day, value: 1, to: d)!, f.string(from: d))
        }
        return (Date(), cal.date(byAdding: .day, value: 1, to: start)!, "Today")
    }

    var calendarAllowed: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func events(from: Date, to: Date) -> [EKEvent] {
        guard calendarAllowed else { return [] }
        let p = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        return store.events(matching: p).sorted { $0.startDate < $1.startDate }
    }

    func requestCalendar(_ then: @escaping () -> Void) {
        Task {
            _ = try? await store.requestFullAccessToEvents()
            then()
        }
    }

    // MARK: Questions

    var modelAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Whether the engine picked in Settings › Advanced can take a question right now.
    var canAsk: Bool {
        switch Settings.shared.engine {
        case .apple: return modelAvailable
        case .openai: return !Settings.shared.openAIKey.isEmpty
        case .claude: return !Settings.shared.claudeKey.isEmpty
        case .codex, .claudeCode: return RemoteChat.tool(Settings.shared.engine) != nil
        }
    }

    struct Turn: Identifiable { let id = UUID(); let question: String; var answer: String? }
    /// The conversation so far; the last turn's answer is `answer`.
    @Published var turns: [Turn] = []
    private var session: LanguageModelSession?
    private var remote: RemoteChat?
    private var talkingTo: Engine?

    /// A new question starts a new conversation unless `continuing`, which keeps the same one so whoever
    /// is answering remembers what was said.
    func ask(_ question: String, continuing: Bool = false) {
        answering?.cancel()
        let s = Settings.shared
        let engine = s.engine
        if !continuing || talkingTo != engine || (session == nil && remote == nil) {
            session = nil; remote = nil; turns = []
            talkingTo = engine
            if engine == .apple {
                session = LanguageModelSession(instructions: Engine.instructions)
            } else {
                remote = RemoteChat()
            }
        }
        turns.append(Turn(question: question, answer: nil))
        thinking = true
        answer = nil
        let session = self.session, remote = self.remote
        let key = engine == .openai ? s.openAIKey : s.claudeKey
        let model = engine == .openai ? s.openAIModel : s.claudeModel
        answering = Task {
            let text: String
            do {
                if let session {
                    text = try await session.respond(to: question).content.trimmingCharacters(in: .whitespacesAndNewlines)
                } else if let remote {
                    text = try await remote.reply(to: question, engine: engine, key: key, model: model)
                } else { return }
            } catch {
                guard !Task.isCancelled else { return }
                text = (error as? EngineError)?.message ?? "Gus couldn't answer that."
            }
            guard !Task.isCancelled else { return }
            thinking = false
            answer = text
            if !turns.isEmpty { turns[turns.count - 1].answer = text }
        }
    }

    var active: Bool { thinking || answer != nil || !turns.isEmpty }

    func clearAnswer() { answering?.cancel(); answer = nil; thinking = false; turns = []; session = nil; remote = nil }
}
