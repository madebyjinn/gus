import Foundation
import CoreServices

/// Gus's own index of the folders you pick (Desktop, Documents and Downloads to start): every file and
/// folder name, held in memory so a search is a scan of a few hundred thousand short strings, a few
/// milliseconds, with no Spotlight round trip. FSEvents marks a folder dirty and it's re-read shortly after.
final class FileIndex: @unchecked Sendable {
    static let shared = FileIndex()

    struct Entry: Sendable { let name: String; let lower: String; let path: String; let isFolder: Bool }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?
    private let queue = DispatchQueue(label: "gus.fileindex", qos: .utility)
    static let cap = 300_000
    private(set) var count = 0
    private(set) var building = false

    static let skipped: Set<String> = ["node_modules", ".git", "DerivedData", "Pods", ".build", "build", "__pycache__",
                                       ".venv", "venv", "Library", ".Trash", "Caches"]

    static var defaultRoots: [String] {
        let home = NSHomeDirectory()
        return ["Desktop", "Documents", "Downloads"].map { home + "/" + $0 }
    }

    func rebuild(_ roots: [String], then done: (@Sendable (Int) -> Void)? = nil) {
        queue.async { [self] in
            building = true
            var out: [Entry] = []
            out.reserveCapacity(20_000)
            let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
            for root in roots {
                guard out.count < Self.cap else { break }
                let url = URL(fileURLWithPath: root)
                guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys,
                                                                   options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                for case let item as URL in walker {
                    let name = item.lastPathComponent
                    let values = try? item.resourceValues(forKeys: Set(keys))
                    let isDir = values?.isDirectory == true && values?.isPackage != true
                    if isDir && Self.skipped.contains(name) { walker.skipDescendants(); continue }
                    out.append(Entry(name: name, lower: name.lowercased(), path: item.path, isFolder: isDir))
                    if out.count >= Self.cap { break }
                }
            }
            lock.lock(); entries = out; count = out.count; lock.unlock()
            building = false
            done?(out.count)
        }
        watch(roots)
    }

    /// Best matches first: whole name, prefix, a word's prefix, then anywhere. Folders win ties.
    func search(_ query: String, limit: Int = 6) -> [Entry] {
        let q = query.lowercased()
        guard q.count >= 2 else { return [] }
        lock.lock(); let snapshot = entries; lock.unlock()
        var best: [(Double, Entry)] = []
        best.reserveCapacity(64)
        for e in snapshot {
            guard let r = e.lower.range(of: q) else { continue }
            var score: Double
            if e.lower == q { score = 100 }
            else if r.lowerBound == e.lower.startIndex { score = 80 }
            else {
                let before = e.lower[e.lower.index(before: r.lowerBound)]
                score = before == " " || before == "-" || before == "_" || before == "." ? 60 : 30
            }
            if e.isFolder { score += 5 }
            score -= Double(e.lower.count) * 0.05
            score -= Double(e.path.filter { $0 == "/" }.count) * 0.3
            best.append((score, e))
            if best.count > 400 { best.sort { $0.0 > $1.0 }; best.removeLast(best.count - 100) }
        }
        return best.sorted { $0.0 > $1.0 }.prefix(limit).map(\.1)
    }

    private func watch(_ roots: [String]) {
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
        stream = nil
        guard !roots.isEmpty else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let index = Unmanaged<FileIndex>.fromOpaque(info).takeUnretainedValue()
            index.changed()
        }
        guard let s = FSEventStreamCreate(nil, callback, &context, roots as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 2.0,
                                          FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)) else { return }
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        stream = s
        watchedRoots = roots
    }

    private var watchedRoots: [String] = []

    /// Something under a root changed: re-read once things settle (cheap; names only).
    private func changed() {
        pending?.cancel()
        let roots = watchedRoots
        let work = DispatchWorkItem { [weak self] in self?.rebuildQuietly(roots) }
        pending = work
        queue.asyncAfter(deadline: .now() + 4, execute: work)
    }

    private func rebuildQuietly(_ roots: [String]) {
        guard !building else { changed(); return }
        // Same walk as rebuild, without touching the stream.
        var out: [Entry] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        for root in roots {
            guard let walker = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: keys,
                                                               options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let item as URL in walker {
                let name = item.lastPathComponent
                let values = try? item.resourceValues(forKeys: Set(keys))
                let isDir = values?.isDirectory == true && values?.isPackage != true
                if isDir && Self.skipped.contains(name) { walker.skipDescendants(); continue }
                out.append(Entry(name: name, lower: name.lowercased(), path: item.path, isFolder: isDir))
                if out.count >= Self.cap { break }
            }
        }
        lock.lock(); entries = out; count = out.count; lock.unlock()
    }
}
