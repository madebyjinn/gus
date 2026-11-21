import AppKit
import Contacts

/// One row in the results.
struct Hit: Identifiable {
    enum Icon { case app(String), symbol(String), file(String), image(NSImage) }
    enum Group: Int, Comparable { case answer, assistant, apps, contacts, files, web
        static func < (a: Group, b: Group) -> Bool { a.rawValue < b.rawValue }
        var title: String? {
            switch self {
            case .answer, .assistant: return nil
            case .apps: return "Applications"
            case .contacts: return "Contacts"
            case .files: return "Files"
            case .web: return nil
            }
        }
    }
    let id: String
    var icon: Icon
    var title: String
    var subtitle: String? = nil
    var hint: String? = nil          // right-hand label: "Open", "Copy", "Create"
    var group: Group
    var score: Double = 0
    var big = false                   // answers (maths, money) get the large layout
    var run: @MainActor () -> Void
    var alternate: (@MainActor () -> Void)? = nil   // ⌘Return
    var alternateName: String? = nil
    /// What C (on a hovered row) and ⌘C copy.
    var copyText: String? = nil
    /// Tab on a contact: call or message.
    var tab: (@MainActor () -> Void)? = nil
    var tabName: String? = nil
}

// MARK: - Applications

/// Every app in the usual folders, read once at launch and again when the folders change. Matching is
/// in memory, so it answers as you type.
@MainActor
final class AppIndex {
    static let shared = AppIndex()
    struct App { let name: String; let path: String; let words: [String] }
    private(set) var apps: [App] = []
    private var launches: [String: Int] = UserDefaults.standard.dictionary(forKey: "launches") as? [String: Int] ?? [:]
    private var stamp = Date.distantPast

    func refreshIfNeeded() {
        guard Date().timeIntervalSince(stamp) > 60 else { return }
        stamp = Date()
        Task.detached(priority: .utility) {
            let found = AppIndex.scan()
            await MainActor.run { AppIndex.shared.apps = found }
        }
    }

    nonisolated static func scan() -> [App] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let roots = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                     home + "/Applications", "/System/Library/CoreServices/Applications"]
        var seen = Set<String>()
        var out: [App] = []
        func add(_ path: String) {
            let name = fm.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
            guard seen.insert(name.lowercased()).inserted else { return }
            let words = name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            out.append(App(name: name, path: path, words: words))
        }
        for root in roots {
            guard let items = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for item in items {
                let path = root + "/" + item
                if item.hasSuffix(".app") { add(path) }
                else if !item.hasPrefix("."), (try? fm.attributesOfItem(atPath: path)[.type] as? FileAttributeType) == .typeDirectory,
                        let inner = try? fm.contentsOfDirectory(atPath: path) {
                    for sub in inner where sub.hasSuffix(".app") { add(path + "/" + sub) }
                }
            }
        }
        add("/System/Library/CoreServices/Finder.app")
        return out
    }

    func search(_ query: String) -> [Hit] {
        let q = query.lowercased()
        guard !q.isEmpty else { return [] }
        var hits: [Hit] = []
        for app in apps {
            let name = app.name.lowercased()
            var score: Double
            if name == q { score = 100 }
            else if name.hasPrefix(q) { score = 80 - Double(name.count - q.count) * 0.2 }
            else if app.words.contains(where: { $0.hasPrefix(q) }) { score = 60 }
            else if Self.initials(app.words) .hasPrefix(q) && q.count >= 2 { score = 55 }
            else if name.contains(q) { score = 40 }
            else if q.count >= 3, Self.subsequence(q, of: name) { score = 20 }
            else { continue }
            score += min(Double(launches[app.path] ?? 0), 30) * 0.8
            let path = app.path
            hits.append(Hit(id: "app:" + path, icon: .app(path), title: app.name, subtitle: nil, hint: "Open",
                            group: .apps, score: score,
                            run: { AppIndex.shared.open(path) },
                            alternate: { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) },
                            alternateName: "Show in Finder"))
        }
        return hits.sorted { $0.score > $1.score }.prefix(6).map { $0 }
    }

    func open(_ path: String) {
        launches[path, default: 0] += 1
        UserDefaults.standard.set(launches, forKey: "launches")
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init())
    }

    private static func initials(_ words: [String]) -> String { String(words.compactMap(\.first)) }

    private static func subsequence(_ q: String, of s: String) -> Bool {
        var j = s.startIndex
        for ch in q {
            guard let k = s[j...].firstIndex(of: ch) else { return false }
            j = s.index(after: k)
        }
        return true
    }
}

// MARK: - Files and folders (Gus's own index; see FileIndex.swift)

enum FileHits {
    static func search(_ q: String) -> [Hit] {
        FileIndex.shared.search(q).map { e in
            let folder = (e.path as NSString).deletingLastPathComponent.replacingOccurrences(of: NSHomeDirectory(), with: "~")
            let path = e.path
            return Hit(id: "file:" + path, icon: .file(path), title: e.name, subtitle: folder, hint: "Open",
                       group: .files, score: 0,
                       run: { NSWorkspace.shared.open(URL(fileURLWithPath: path)) },
                       alternate: { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) },
                       alternateName: "Show in Finder", copyText: path)
        }
    }
}

// MARK: - Contacts

@MainActor
final class ContactSearch: ObservableObject {
    static let shared = ContactSearch()
    private let store = CNContactStore()
    @Published var status = CNContactStore.authorizationStatus(for: .contacts)

    var allowed: Bool { status == .authorized }

    func requestAccess() {
        store.requestAccess(for: .contacts) { _, _ in
            Task { @MainActor in ContactSearch.shared.status = CNContactStore.authorizationStatus(for: .contacts) }
        }
    }

    func search(_ text: String) async -> [Hit] {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard allowed, q.count >= 2 else { return [] }
        let store = self.store
        let found: [CNContact] = await Task.detached(priority: .userInitiated) {
            let keys: [CNKeyDescriptor] = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactOrganizationNameKey,
                                           CNContactEmailAddressesKey, CNContactPhoneNumbersKey, CNContactIdentifierKey,
                                           CNContactThumbnailImageDataKey] as [CNKeyDescriptor]
            let predicate = CNContact.predicateForContacts(matchingName: q)
            return (try? store.unifiedContacts(matching: predicate, keysToFetch: keys)) ?? []
        }.value
        return found.prefix(4).map { c in
            let name = [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            let email = c.emailAddresses.first.map { $0.value as String }
            let phone = c.phoneNumbers.first?.value.stringValue
            let detail = [phone, email, c.organizationName.isEmpty ? nil : c.organizationName].compactMap { $0 }.joined(separator: " · ")
            let icon: Hit.Icon = c.thumbnailImageData.flatMap(NSImage.init(data:)).map { .image($0) } ?? .symbol("person.crop.circle")
            let id = c.identifier
            let copyable = phone ?? email ?? name
            let message = UserDefaults.standard.string(forKey: "contactTab") == "message"
            let digits = phone.map { $0.filter { $0.isNumber || $0 == "+" } }
            let tab: (@MainActor () -> Void)? = {
                if message, let target = digits ?? email {
                    return { NSWorkspace.shared.open(URL(string: "sms:\(target)")!) }
                }
                if !message, let digits {
                    return { NSWorkspace.shared.open(URL(string: "tel:\(digits)")!) }
                }
                return nil
            }()
            return Hit(id: "contact:" + id, icon: icon, title: name.isEmpty ? c.organizationName : name,
                       subtitle: detail.isEmpty ? nil : detail, hint: "Open", group: .contacts, score: 50,
                       run: { NSWorkspace.shared.open(URL(string: "addressbook://\(id)")!) },
                       copyText: copyable, tab: tab, tabName: tab == nil ? nil : (message ? "Message" : "Call"))
        }
    }
}
