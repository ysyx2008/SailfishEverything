import Foundation

public final class FileIndex: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [FileEntry] = []
    private var seen = Set<String>()

    public init() {}

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    public func reset() {
        lock.lock()
        entries.removeAll(keepingCapacity: true)
        seen.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    @discardableResult
    public func add(_ batch: [FileEntry]) -> Int {
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

    public func remove(paths: [String]) {
        guard !paths.isEmpty else { return }
        lock.lock()
        let doomed = Set(paths)
        for path in doomed {
            seen.remove(path)
        }
        entries.removeAll { doomed.contains($0.path) }
        lock.unlock()
    }

    public func search(
        query: String,
        options: SearchOptions = SearchOptions(),
        sort: SortState = SortState(),
        previous: (query: String, options: SearchOptions, indices: [Int])? = nil
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

    public func entries(at indices: [Int]) -> [FileEntry] {
        lock.lock()
        defer { lock.unlock() }
        return indices.compactMap { $0 < entries.count ? entries[$0] : nil }
    }

    public func entry(at index: Int) -> FileEntry? {
        lock.lock()
        defer { lock.unlock() }
        guard index >= 0, index < entries.count else { return nil }
        return entries[index]
    }

    public func names(
        matching query: String,
        options: SearchOptions = SearchOptions(),
        sort: SortState = SortState(),
        previous: (query: String, options: SearchOptions, indices: [Int])? = nil
    ) -> [String] {
        entries(at: search(query: query, options: options, sort: sort, previous: previous)).map(\.name)
    }

    public static func canNarrow(from old: String, to new: String) -> Bool {
        guard new.count >= old.count else { return false }
        return new.hasPrefix(old)
    }

    public static func terms(from query: String) -> [String] {
        query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
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
