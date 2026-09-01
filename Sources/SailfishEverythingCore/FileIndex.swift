import Foundation

public struct SearchCursor: Sendable, Equatable {
    public var query: String
    public var options: SearchOptions
    public var filter: ResultFilter
    public var sort: SortState
    public var indices: [Int]

    public init(
        query: String,
        options: SearchOptions = SearchOptions(),
        filter: ResultFilter = .all,
        sort: SortState = SortState(),
        indices: [Int]
    ) {
        self.query = query
        self.options = options
        self.filter = filter
        self.sort = sort
        self.indices = indices
    }
}

public final class FileIndex: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [FileEntry] = []
    private var pathIndex: [String: Int] = [:]
    private var identity: [Int] = []
    private var postings = NamePostings()
    private var namePack = NamePack()
    private var bulkLoad = false
    private var byteTotal: Int64 = 0
    private var sortedAll: (sort: SortState, indices: [Int])?

    public init() {}

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    public var totalBytes: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return byteTotal
    }

    public func reset() {
        lock.lock()
        entries.removeAll(keepingCapacity: true)
        pathIndex.removeAll(keepingCapacity: true)
        identity.removeAll(keepingCapacity: true)
        postings.reset()
        namePack.reset()
        bulkLoad = false
        byteTotal = 0
        sortedAll = nil
        lock.unlock()
    }

    public func beginBulkLoad() {
        lock.lock()
        bulkLoad = true
        lock.unlock()
    }

    public func endBulkLoad() {
        lock.lock()
        bulkLoad = false
        identity = Array(entries.indices)
        rebuildPathIndexLocked()
        lock.unlock()
    }

    @discardableResult
    public func add(_ batch: [FileEntry], replace: Bool = false) -> Int {
        lock.lock()
        defer { lock.unlock() }
        entries.reserveCapacity(entries.count + batch.count)
        identity.reserveCapacity(identity.count + batch.count)
        namePack.reserve(entries.count + batch.count)
        var changed = false
        var packStale = false
        for entry in batch {
            if !bulkLoad, let existing = pathIndex[entry.path] {
                if replace, entries[existing] != entry {
                    if !entries[existing].isDirectory {
                        byteTotal -= entries[existing].size ?? 0
                    }
                    let nameChanged = entries[existing].nameLower != entry.nameLower
                    entries[existing] = entry
                    if !entry.isDirectory {
                        byteTotal += entry.size ?? 0
                    }
                    postings.markDirty()
                    if nameChanged { packStale = true }
                    changed = true
                }
                continue
            }
            if !bulkLoad {
                pathIndex[entry.path] = entries.count
                identity.append(entries.count)
            }
            entries.append(entry)
            namePack.append(entry.nameLower)
            if !entry.isDirectory {
                byteTotal += entry.size ?? 0
            }
            if postings.isReady {
                postings.markDirty()
            }
            changed = true
        }
        if packStale {
            rebuildNamePackLocked()
        }
        if changed { sortedAll = nil }
        return entries.count
    }

    public func paths(under folder: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let prefix = folder.hasSuffix("/") ? folder : folder + "/"
        return entries.compactMap { entry in
            if entry.path == folder || entry.path.hasPrefix(prefix) { return entry.path }
            return nil
        }
    }

    public func remove(paths: [String]) {
        guard !paths.isEmpty else { return }
        lock.lock()
        let doomed = Set(paths)
        for entry in entries where doomed.contains(entry.path) {
            if !entry.isDirectory {
                byteTotal -= entry.size ?? 0
            }
        }
        entries.removeAll { doomed.contains($0.path) }
        identity = Array(entries.indices)
        rebuildPathIndexLocked()
        rebuildNamePackLocked()
        postings.markDirty()
        sortedAll = nil
        lock.unlock()
    }

    public func search(
        query: String,
        options: SearchOptions = SearchOptions(),
        filter: ResultFilter = .all,
        sort: SortState = SortState(),
        previous: SearchCursor? = nil,
        allowFullSort: Bool = true,
        shouldContinue: () -> Bool = { true }
    ) -> [Int] {
        let parsed = Query.parse(query)
        let queryEmpty = parsed.isEmpty && !options.regex
        let unrestricted = filter == .all && options.inFolder.isEmpty

        lock.lock()
        let identitySnap = identity
        let cached = sortedAll
        let pack = namePack
        let total = entries.count
        lock.unlock()

        if queryEmpty && unrestricted {
            if let cached, cached.sort == sort, cached.indices.count == total {
                return cached.indices
            }
            let all = identitySnap.count == total ? identitySnap : Array(0..<total)
            let cheap = total <= 4_096
            if allowFullSort, cheap || sort.column != .name || !sort.ascending {
                lock.lock()
                let snapshot = entries
                lock.unlock()
                let indices = Self.sort(all, entries: snapshot, sort: sort)
                lock.lock()
                if entries.count == snapshot.count {
                    sortedAll = (sort, indices)
                }
                lock.unlock()
                return indices
            }
            return all
        }

        if !shouldContinue() { return [] }

        if let groups = parsed.packedTextGroups,
           unrestricted,
           !options.matchCase,
           !options.matchWholeWord,
           !options.matchPath,
           !options.regex
        {
            var seed: [Int]?
            if let previous,
               previous.options == options,
               previous.filter == filter,
               Query.canNarrow(from: previous.query, to: query),
               !previous.indices.isEmpty,
               previous.indices.count <= 8_192
            {
                seed = previous.indices
            }
            let hits = Self.packedGroupHits(groups, pack: pack, seed: seed)
            return finishPackedHits(hits, sort: sort, cached: cached, allowFullSort: allowFullSort)
        }

        lock.lock()
        let snapshot = entries
        lock.unlock()

        let pool: [Int]
        var alreadySorted = false
        if let previous,
           previous.options == options,
           previous.filter == filter,
           previous.sort == sort,
           !options.regex,
           Query.canNarrow(from: previous.query, to: query),
           !previous.indices.isEmpty
        {
            pool = previous.indices
            alreadySorted = true
        } else if unrestricted, let cached, cached.sort == sort, cached.indices.count == snapshot.count {
            pool = cached.indices
            alreadySorted = true
        } else if identitySnap.count == snapshot.count {
            pool = identitySnap
        } else {
            pool = Array(snapshot.indices)
        }

        let hits = Self.filter(
            pool,
            entries: snapshot,
            query: query,
            parsed: parsed,
            options: options,
            filter: filter,
            shouldContinue: shouldContinue
        )
        if alreadySorted { return hits }
        return Self.finishHits(hits, entries: snapshot, sort: sort, cached: cached, allowFullSort: allowFullSort)
    }

    private func finishPackedHits(
        _ hits: [Int],
        sort: SortState,
        cached: (sort: SortState, indices: [Int])?,
        allowFullSort: Bool
    ) -> [Int] {
        if hits.count > 2_048 || !allowFullSort {
            return hits
        }
        lock.lock()
        let snapshot = entries
        lock.unlock()
        return Self.finishHits(hits, entries: snapshot, sort: sort, cached: cached, allowFullSort: allowFullSort)
    }

    public func warmCaches(sort: SortState = SortState(), shouldContinue: () -> Bool = { true }) {
        lock.lock()
        let snapshot = entries
        let small = snapshot.count <= 4_096
        let needSort = small && (sortedAll == nil || sortedAll?.sort != sort || sortedAll?.indices.count != snapshot.count)
        lock.unlock()
        guard needSort, shouldContinue() else { return }
        let indices = Self.sort(Array(snapshot.indices), entries: snapshot, sort: sort)
        guard shouldContinue() else { return }
        lock.lock()
        if entries.count == snapshot.count {
            sortedAll = (sort, indices)
        }
        lock.unlock()
    }

    public func totalBytes(at indices: [Int]) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        var sum: Int64 = 0
        for index in indices {
            guard index >= 0, index < entries.count else { continue }
            let entry = entries[index]
            if !entry.isDirectory {
                sum += entry.size ?? 0
            }
        }
        return sum
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

    public func directories() -> [FileEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries.filter(\.isDirectory)
    }

    public func names(
        matching query: String,
        options: SearchOptions = SearchOptions(),
        filter: ResultFilter = .all,
        sort: SortState = SortState(),
        previous: SearchCursor? = nil
    ) -> [String] {
        entries(at: search(query: query, options: options, filter: filter, sort: sort, previous: previous)).map(\.name)
    }

    public static func canNarrow(from old: String, to new: String) -> Bool {
        Query.canNarrow(from: old, to: new)
    }

    public static func matchesFolder(_ entry: FileEntry, folder: String) -> Bool {
        guard !folder.isEmpty else { return true }
        if entry.path == folder { return true }
        let prefix = folder.hasSuffix("/") ? folder : folder + "/"
        return entry.path.hasPrefix(prefix)
    }

    private func rebuildPathIndexLocked() {
        pathIndex.removeAll(keepingCapacity: true)
        pathIndex.reserveCapacity(entries.count)
        for (index, entry) in entries.enumerated() {
            pathIndex[entry.path] = index
        }
    }

    private func rebuildNamePackLocked() {
        namePack.rebuild(entries.map(\.nameLower))
    }

    private static func packedGroupHits(_ groups: [[String]], pack: NamePack, seed: [Int]?) -> [Int] {
        var combined: [Int] = []
        var seen: Set<Int> = []
        for group in groups {
            let ordered = group.sorted { $0.count > $1.count }
            var hits = seed
            for term in ordered {
                hits = pack.hits(needle: term.fastLowercased(), candidates: hits)
                if hits?.isEmpty == true { break }
            }
            guard let hits else { continue }
            if groups.count == 1 { return hits }
            for index in hits where seen.insert(index).inserted {
                combined.append(index)
            }
        }
        return combined
    }

    private static func simpleHits(
        _ candidates: [Int]?,
        entries: [FileEntry],
        pack: NamePack,
        needle: String,
        options: SearchOptions
    ) -> [Int] {
        if !options.matchCase, !options.matchPath, pack.count == entries.count {
            return pack.hits(needle: needle.fastLowercased(), candidates: candidates)
        }
        let pool = candidates ?? Array(entries.indices)
        let term = options.matchCase ? needle : needle.fastLowercased()
        var hits: [Int] = []
        hits.reserveCapacity(min(pool.count, 64))
        for index in pool {
            guard index >= 0, index < entries.count else { continue }
            let entry = entries[index]
            let matched: Bool
            if options.matchPath {
                matched = options.matchCase
                    ? FastContains.contains(entry.path, needle)
                    : FastContains.contains(entry.pathLower, term)
            } else {
                matched = options.matchCase
                    ? FastContains.contains(entry.name, needle)
                    : FastContains.contains(entry.nameLower, term)
            }
            if matched { hits.append(index) }
        }
        return hits
    }

    private static func filter(
        _ pool: [Int],
        entries: [FileEntry],
        query: String,
        parsed: Query,
        options: SearchOptions,
        filter: ResultFilter,
        shouldContinue: () -> Bool
    ) -> [Int] {
        var hits: [Int] = []
        hits.reserveCapacity(min(pool.count, 64))

        if options.regex {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return pool.filter { index in
                    let entry = entries[index]
                    return filter.matches(entry) && matchesFolder(entry, folder: options.inFolder)
                }
            }
            guard let regex = Query.makeRegex(trimmed, matchCase: options.matchCase) else {
                return []
            }
            for (offset, index) in pool.enumerated() {
                if offset & 0x1FFF == 0, !shouldContinue() { return [] }
                let entry = entries[index]
                guard filter.matches(entry), matchesFolder(entry, folder: options.inFolder) else { continue }
                if Query.matchesRegex(entry, regex: regex, options: options) {
                    hits.append(index)
                }
            }
            return hits
        }

        if let needle = parsed.simpleText, filter == .all, options.inFolder.isEmpty, !options.matchWholeWord {
            return simpleHits(pool, entries: entries, pack: NamePack(), needle: needle, options: options)
        }

        for (offset, index) in pool.enumerated() {
            if offset & 0x1FFF == 0, !shouldContinue() { return [] }
            let entry = entries[index]
            guard filter.matches(entry), matchesFolder(entry, folder: options.inFolder) else { continue }
            if parsed.matches(entry, options: options) {
                hits.append(index)
            }
        }
        return hits
    }

    private static func finishHits(
        _ hits: [Int],
        entries: [FileEntry],
        sort: SortState,
        cached: (sort: SortState, indices: [Int])?,
        allowFullSort: Bool
    ) -> [Int] {
        if hits.count <= 2_048, allowFullSort {
            return Self.sort(hits, entries: entries, sort: sort)
        }
        if allowFullSort, let cached, cached.sort == sort, hits.count < entries.count / 4 {
            let allowed = Set(hits)
            return cached.indices.filter { allowed.contains($0) }
        }
        return hits
    }

    private static func sort(_ indices: [Int], entries: [FileEntry], sort: SortState) -> [Int] {
        switch sort.column {
        case .name:
            return indices.sorted { lhs, rhs in
                let a = entries[lhs]
                let b = entries[rhs]
                if a.nameLower != b.nameLower {
                    return sort.ascending ? a.nameLower < b.nameLower : a.nameLower > b.nameLower
                }
                return a.pathLower < b.pathLower
            }
        case .path:
            return indices.sorted { lhs, rhs in
                let a = entries[lhs]
                let b = entries[rhs]
                if a.directory != b.directory {
                    return sort.ascending ? a.directory < b.directory : a.directory > b.directory
                }
                return a.pathLower < b.pathLower
            }
        case .size:
            FileMetadata.prefetch(entries: entries, indices: indices)
            return indices.sorted { lhs, rhs in
                let a = entries[lhs]
                let b = entries[rhs]
                let asize = a.isDirectory ? Int64.min : (FileMetadata.size(of: a) ?? -1)
                let bsize = b.isDirectory ? Int64.min : (FileMetadata.size(of: b) ?? -1)
                if asize != bsize {
                    return sort.ascending ? asize < bsize : asize > bsize
                }
                return a.pathLower < b.pathLower
            }
        case .modified:
            FileMetadata.prefetch(entries: entries, indices: indices)
            return indices.sorted { lhs, rhs in
                let a = entries[lhs]
                let b = entries[rhs]
                let ad = FileMetadata.modified(of: a) ?? .distantPast
                let bd = FileMetadata.modified(of: b) ?? .distantPast
                if ad != bd {
                    return sort.ascending ? ad < bd : ad > bd
                }
                return a.pathLower < b.pathLower
            }
        }
    }
}
