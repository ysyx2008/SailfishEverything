import Foundation

struct FileEntry: Sendable {
    let name: String
    let nameLower: String
    let directory: String
    let path: String
    let pathLower: String
    let size: Int64?
    let modified: Date?
    let isDirectory: Bool
    let isCloudOnly: Bool
}

struct SearchOptions: Equatable, Sendable {
    var matchCase = false
    var matchWholeWord = false
    var matchPath = false
}

enum SortColumn: Int, Sendable {
    case name = 0
    case path = 1
    case size = 2
    case modified = 3
}

struct SortState: Equatable, Sendable {
    var column: SortColumn = .name
    var ascending = true
}

final class FileIndex: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [FileEntry] = []
    private var seen = Set<String>()

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    func reset() {
        lock.lock()
        entries.removeAll(keepingCapacity: true)
        seen.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    @discardableResult
    func add(_ batch: [FileEntry]) -> Int {
        lock.lock()
        defer { lock.unlock() }
        entries.reserveCapacity(entries.count + batch.count)
        for entry in batch {
            if seen.insert(entry.path).inserted {
                entries.append(entry)
            }
        }
        return entries.count
    }

    func remove(paths: [String]) {
        guard !paths.isEmpty else { return }
        lock.lock()
        let doomed = Set(paths)
        for path in doomed {
            seen.remove(path)
        }
        entries.removeAll { doomed.contains($0.path) }
        lock.unlock()
    }

    func search(
        query: String,
        options: SearchOptions,
        sort: SortState,
        previous: (query: String, options: SearchOptions, indices: [Int])?
    ) -> [Int] {
        let terms = Self.terms(from: query)
        lock.lock()
        let snapshotCount = entries.count
        lock.unlock()

        var candidates: [Int]
        if let previous,
           previous.options == options,
           Self.canNarrow(from: previous.query, to: query),
           !previous.indices.isEmpty
        {
            candidates = previous.indices.filter { $0 < snapshotCount }
        } else {
            candidates = Array(0..<snapshotCount)
        }

        if !terms.isEmpty {
            lock.lock()
            candidates = candidates.filter { index in
                Self.matches(entries[index], terms: terms, options: options)
            }
            lock.unlock()
        }

        lock.lock()
        let sorted = Self.sort(candidates, entries: entries, sort: sort)
        lock.unlock()
        return sorted
    }

    func entries(at indices: [Int]) -> [FileEntry] {
        lock.lock()
        defer { lock.unlock() }
        return indices.compactMap { $0 < entries.count ? entries[$0] : nil }
    }

    func entry(at index: Int) -> FileEntry? {
        lock.lock()
        defer { lock.unlock() }
        guard index >= 0, index < entries.count else { return nil }
        return entries[index]
    }

    private static func terms(from query: String) -> [String] {
        query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func canNarrow(from old: String, to new: String) -> Bool {
        guard new.count >= old.count else { return false }
        return new.hasPrefix(old)
    }

    private static func matches(_ entry: FileEntry, terms: [String], options: SearchOptions) -> Bool {
        let haystack: String
        if options.matchPath {
            haystack = options.matchCase ? entry.path : entry.pathLower
        } else {
            haystack = options.matchCase ? entry.name : entry.nameLower
        }
        for rawTerm in terms {
            let term = options.matchCase ? rawTerm : rawTerm.lowercased()
            if options.matchWholeWord {
                if !containsWholeWord(haystack, term: term) {
                    return false
                }
            } else if containsWildcard(term) {
                if !wildcardMatch(haystack, pattern: term) {
                    return false
                }
            } else if !haystack.contains(term) {
                return false
            }
        }
        return true
    }

    private static func containsWildcard(_ term: String) -> Bool {
        term.contains("*") || term.contains("?")
    }

    private static func wildcardMatch(_ text: String, pattern: String) -> Bool {
        let regexPattern = wildcardToRegex(pattern)
        return text.range(of: regexPattern, options: .regularExpression) != nil
    }

    private static func wildcardToRegex(_ pattern: String) -> String {
        var out = "^"
        for ch in pattern {
            switch ch {
            case "*": out += ".*"
            case "?": out += "."
            case ".", "[", "]", "(", ")", "{", "}", "+", "^", "$", "|", "\\":
                out += "\\\(ch)"
            default:
                out.append(ch)
            }
        }
        out += "$"
        return out
    }

    private static func containsWholeWord(_ text: String, term: String) -> Bool {
        guard !term.isEmpty else { return true }
        var searchStart = text.startIndex
        while let range = text.range(of: term, range: searchStart..<text.endIndex) {
            let beforeOK: Bool = {
                if range.lowerBound == text.startIndex { return true }
                let prev = text.index(before: range.lowerBound)
                return !text[prev].isLetter && !text[prev].isNumber
            }()
            let afterOK: Bool = {
                if range.upperBound == text.endIndex { return true }
                return !text[range.upperBound].isLetter && !text[range.upperBound].isNumber
            }()
            if beforeOK && afterOK { return true }
            searchStart = range.upperBound
        }
        return false
    }

    private static func sort(_ indices: [Int], entries: [FileEntry], sort: SortState) -> [Int] {
        indices.sorted { lhs, rhs in
            let a = entries[lhs]
            let b = entries[rhs]
            let result: ComparisonResult
            switch sort.column {
            case .name:
                result = a.nameLower.compare(b.nameLower)
            case .path:
                result = a.directory.localizedStandardCompare(b.directory)
            case .size:
                let asize = a.isDirectory ? -1 : (a.size ?? -1)
                let bsize = b.isDirectory ? -1 : (b.size ?? -1)
                result = asize == bsize ? .orderedSame : (asize < bsize ? .orderedAscending : .orderedDescending)
            case .modified:
                let ad = a.modified ?? .distantPast
                let bd = b.modified ?? .distantPast
                result = ad == bd ? .orderedSame : (ad < bd ? .orderedAscending : .orderedDescending)
            }
            if result == .orderedSame {
                return a.pathLower < b.pathLower
            }
            return sort.ascending ? result == .orderedAscending : result == .orderedDescending
        }
    }
}

enum PathDisplay {
    private static let home = NSHomeDirectory()
    private static let cloudDocs = NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs"
    private static let cloudStorage = NSHomeDirectory() + "/Library/CloudStorage"
    private static let mobileDocuments = NSHomeDirectory() + "/Library/Mobile Documents"

    static func pretty(_ directory: String) -> String {
        if directory.hasPrefix(cloudDocs) {
            return "iCloud Drive" + directory.dropFirst(cloudDocs.count)
        }
        if directory.hasPrefix(cloudStorage) {
            let rest = String(directory.dropFirst(cloudStorage.count))
            if rest.isEmpty { return "Cloud Storage" }
            var parts = rest.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            if parts.first == "" { parts.removeFirst() }
            if let first = parts.first {
                parts[0] = prettyCloudProvider(first)
            }
            return parts.joined(separator: "/")
        }
        if directory.hasPrefix(mobileDocuments) {
            return "iCloud" + directory.dropFirst(mobileDocuments.count)
        }
        if directory.hasPrefix(home) {
            return "~" + directory.dropFirst(home.count)
        }
        return directory
    }

    private static func prettyCloudProvider(_ name: String) -> String {
        if name.hasPrefix("OneDrive-") {
            return "OneDrive - " + name.dropFirst("OneDrive-".count)
        }
        if name.hasPrefix("OneDrive") {
            return name.replacingOccurrences(of: "-", with: " - ")
        }
        return name
    }

    static func formatSize(_ bytes: Int64?, isDirectory: Bool) -> String {
        if isDirectory { return "" }
        guard let bytes else { return "" }
        if bytes < 1024 { return "\(bytes) B" }
        let units = ["KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = -1
        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        if value >= 100 || unitIndex == 0 {
            return "\(Int(value.rounded())) \(units[unitIndex])"
        }
        return String(format: "%.1f %@", value, units[unitIndex])
    }

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }()

    static func formatDate(_ date: Date?) -> String {
        guard let date else { return "" }
        return dateFormatter.string(from: date)
    }
}
