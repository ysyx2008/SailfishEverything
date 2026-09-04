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

private struct FileRowExtras: Sendable {
    var size: Int64?
    var modified: Date?
    var created: Date?
    var isCloudOnly: Bool
}

struct IndexFragment: Sendable {
    var namePack = NamePack()
    var pathPack = NamePack()
    var origNamePack = NamePack(recordsCharCounts: true)
    var origPathPack = NamePack()
    var dirBits = DirBits()
    fileprivate var extras: [Int: FileRowExtras] = [:]
    var sizes: [Int64] = []
    var modifieds: [Int64] = []
    var createds: [Int64] = []
    var byteTotal: Int64 = 0

    static func pack(_ batch: [FileEntry]) -> IndexFragment {
        var fragment = IndexFragment()
        let count = batch.count
        fragment.namePack.reserve(count)
        fragment.pathPack.reserve(count, bytesHint: count * 80)
        fragment.origNamePack.reserve(count)
        fragment.origPathPack.reserve(count, bytesHint: count * 80)
        fragment.dirBits.reserve(count)
        fragment.sizes.reserveCapacity(count)
        fragment.modifieds.reserveCapacity(count)
        fragment.createds.reserveCapacity(count)
        for (index, entry) in batch.enumerated() {
            FileIndex.append(entry, into: &fragment)
            if entry.size != nil || entry.modified != nil || entry.created != nil || entry.isCloudOnly {
                fragment.extras[index] = FileRowExtras(
                    size: entry.size,
                    modified: entry.modified,
                    created: entry.created,
                    isCloudOnly: entry.isCloudOnly
                )
            }
        }
        return fragment
    }
}

public final class FileIndex: @unchecked Sendable {
    private let lock = NSLock()
    private var pathIndex = PathLookup()
    private var identity: [Int] = []
    private var postings = NamePostings()
    private var namePack = NamePack()
    private var pathPack = NamePack()
    private var origNamePack = NamePack(recordsCharCounts: true)
    private var origPathPack = NamePack()
    private var dirBits = DirBits()
    private var extras: [Int: FileRowExtras] = [:]
    private var sizes: [Int64] = []
    private var modifieds: [Int64] = []
    private var createds: [Int64] = []
    private var bulkLoad = false
    private var byteTotal: Int64 = 0
    private var sortedAll: (sort: SortState, indices: [Int])?

    public init() {}

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return origNamePack.count
    }

    public var totalBytes: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return byteTotal
    }

    public func reset() {
        lock.lock()
        pathIndex.removeAll(keepingCapacity: true)
        identity.removeAll(keepingCapacity: true)
        postings.reset()
        namePack.reset()
        pathPack.reset()
        origNamePack.reset()
        origPathPack.reset()
        dirBits.reset()
        extras.removeAll(keepingCapacity: true)
        sizes.removeAll(keepingCapacity: true)
        modifieds.removeAll(keepingCapacity: true)
        createds.removeAll(keepingCapacity: true)
        bulkLoad = false
        byteTotal = 0
        sortedAll = nil
        lock.unlock()
    }

    private static func appendColumn(_ dest: inout [Int64], _ source: [Int64], count: Int) {
        if source.count == count {
            dest.append(contentsOf: source)
        } else {
            dest.append(contentsOf: repeatElement(Int64(-1), count: count))
        }
    }

    private static func unixStamp(_ date: Date?) -> Int64 {
        guard let date else { return -1 }
        let value = Int64(date.timeIntervalSince1970)
        return value >= 0 ? value : -1
    }

    private static func date(fromUnix value: Int64) -> Date? {
        value >= 0 ? Date(timeIntervalSince1970: TimeInterval(value)) : nil
    }

    public func beginBulkLoad() {
        lock.lock()
        bulkLoad = true
        lock.unlock()
    }

    public func endBulkLoad() {
        lock.lock()
        bulkLoad = false
        let total = origNamePack.count
        if identity.count != total {
            identity = Array(0..<total)
        }
        lock.unlock()
    }

    public func buildPathIndex() {
        lock.lock()
        let paths = origPathPack
        let expected = origNamePack.count
        lock.unlock()
        var lookup = PathLookup()
        lookup.fill(from: paths)
        lock.lock()
        if origNamePack.count == expected {
            pathIndex = lookup
        }
        lock.unlock()
    }

    @discardableResult
    public func add(_ batch: [FileEntry], replace: Bool = false) -> Int {
        lock.lock()
        identity.reserveCapacity(identity.count + batch.count)
        let room = origNamePack.count + batch.count
        namePack.reserve(room)
        pathPack.reserve(room, bytesHint: room * 80)
        origNamePack.reserve(room)
        origPathPack.reserve(room, bytesHint: room * 80)
        dirBits.reserve(room)
        sizes.reserveCapacity(room)
        modifieds.reserveCapacity(room)
        createds.reserveCapacity(room)
        var changed = false
        var replacements: [Int: FileEntry] = [:]
        for entry in batch {
            if !bulkLoad, let existing = pathIndex[entry.path] {
                if replace, let old = replacements[existing] ?? makeEntryLocked(existing), old != entry {
                    if !old.isDirectory {
                        byteTotal -= old.size ?? 0
                    }
                    if !entry.isDirectory {
                        byteTotal += entry.size ?? 0
                    }
                    postings.markDirty()
                    let structural = old.name != entry.name
                        || old.directory != entry.directory
                        || old.isDirectory != entry.isDirectory
                    if structural {
                        replacements[existing] = entry
                    } else {
                        writeExtras(existing, entry)
                    }
                    changed = true
                }
                continue
            }
            let index = origNamePack.count
            if !bulkLoad {
                pathIndex[entry.path] = index
            }
            identity.append(index)
            appendPacks(entry)
            if hasExtras(entry) {
                writeExtras(index, entry)
            }
            if !entry.isDirectory {
                byteTotal += entry.size ?? 0
            }
            if postings.isReady {
                postings.markDirty()
            }
            changed = true
        }
        if replacements.isEmpty {
            if changed { sortedAll = nil }
            let total = origNamePack.count
            lock.unlock()
            return total
        }
        let snap = snapshotColumnsLocked()
        lock.unlock()
        var rows = Self.materialize(snap)
        for (index, entry) in replacements {
            guard index >= 0, index < rows.count else { continue }
            rows[index] = entry
        }
        return installRows(rows)
    }

    func add(_ fragment: IndexFragment) -> Int {
        lock.lock()
        defer { lock.unlock() }
        let base = origNamePack.count
        let incoming = fragment.origNamePack.count
        guard incoming > 0 else { return base }
        let room = base + incoming
        let padded = room < 8_192 ? room : max(room, base + incoming * 4)
        namePack.reserve(padded)
        pathPack.reserve(padded, bytesHint: padded * 80)
        origNamePack.reserve(padded)
        origPathPack.reserve(padded, bytesHint: padded * 80)
        dirBits.reserve(padded)
        sizes.reserveCapacity(padded)
        modifieds.reserveCapacity(padded)
        createds.reserveCapacity(padded)
        namePack.append(contentsOf: fragment.namePack)
        pathPack.append(contentsOf: fragment.pathPack)
        origNamePack.append(contentsOf: fragment.origNamePack)
        origPathPack.append(contentsOf: fragment.origPathPack)
        dirBits.append(contentsOf: fragment.dirBits)
        Self.appendColumn(&sizes, fragment.sizes, count: incoming)
        Self.appendColumn(&modifieds, fragment.modifieds, count: incoming)
        Self.appendColumn(&createds, fragment.createds, count: incoming)
        if !fragment.extras.isEmpty {
            extras.reserveCapacity(extras.count + fragment.extras.count)
            for (index, extra) in fragment.extras {
                extras[base + index] = extra
            }
        }
        byteTotal += fragment.byteTotal
        identity.reserveCapacity(identity.count + incoming)
        identity.append(contentsOf: base..<(base + incoming))
        if !bulkLoad {
            for index in 0..<incoming {
                if let path = fragment.origPathPack.string(at: index) {
                    pathIndex[path] = base + index
                }
            }
        }
        if postings.isReady {
            postings.markDirty()
        }
        sortedAll = nil
        return origNamePack.count
    }

    public func contains(path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return pathIndex[path] != nil
    }

    public func paths(under folder: String) -> [String] {
        lock.lock()
        let pack = origPathPack
        lock.unlock()
        return pack.paths(under: folder)
    }

    @discardableResult
    func addReplacingWalk(
        root: String,
        rootPath: String,
        policy: ScanPolicy,
        stop: () -> Bool
    ) -> [FileEntry] {
        var all: [FileEntry] = []
        FastWalk.walk(root: root, rootPath: rootPath, policy: policy, stop: stop) { fragment in
            let entries = Self.entries(from: fragment)
            guard !entries.isEmpty else { return }
            _ = self.add(entries, replace: true)
            all.append(contentsOf: entries)
        }
        return all
    }

    private static func entries(from fragment: IndexFragment) -> [FileEntry] {
        (0..<fragment.origNamePack.count).compactMap { index in
            makeEntry(
                index,
                names: fragment.origNamePack,
                paths: fragment.origPathPack,
                dirs: fragment.dirBits,
                extras: fragment.extras,
                sizes: fragment.sizes,
                modifieds: fragment.modifieds,
                createds: fragment.createds
            )
        }
    }

    public func remove(paths: [String]) {
        guard !paths.isEmpty else { return }
        lock.lock()
        let snap = snapshotColumnsLocked()
        lock.unlock()
        let doomed = Set(paths)
        let kept = Self.materialize(snap).filter { !doomed.contains($0.path) }
        guard kept.count != snap.total else { return }
        installRows(kept)
    }

    public func search(
        query: String,
        options: SearchOptions = SearchOptions(),
        filter: ResultFilter = .all,
        sort: SortState = SortState(),
        previous: SearchCursor? = nil,
        allowFullSort: Bool = true,
        openedCounts: [String: Int] = [:],
        shouldContinue: () -> Bool = { true }
    ) -> [Int] {
        func done(_ hits: [Int]) -> [Int] {
            promoteOpened(hits, openedCounts: openedCounts)
        }
        let parsed = Query.parse(query)
        let queryEmpty = parsed.isEmpty && !options.regex
        let unrestricted = filter == .all && options.inFolder.isEmpty
        let folderFree = options.inFolder.isEmpty

        lock.lock()
        let identitySnap = identity
        let cached = sortedAll
        let pack = namePack
        let paths = pathPack
        let rawNames = origNamePack
        let rawPaths = origPathPack
        let bits = dirBits
        let extraSnap = extras
        let sizeSnap = sizes
        let modifiedSnap = modifieds
        let createdSnap = createds
        let total = origNamePack.count
        lock.unlock()

        if queryEmpty && !options.regex && !options.inFolder.isEmpty {
            let all = identitySnap.count == total ? identitySnap : Array(0..<total)
            var hits = paths.inFolder(options.inFolder, candidates: all)
            if filter != .all {
                hits = Self.applyFilter(hits, filter: filter, pack: pack, dirs: bits)
            }
            return done(finishPackedHits(hits, names: pack, paths: paths, sort: sort, allowFullSort: allowFullSort))
        }

        if queryEmpty && folderFree && filter != .all {
            let all = identitySnap.count == total ? identitySnap : Array(0..<total)
            let hits = Self.applyFilter(all, filter: filter, pack: pack, dirs: bits)
            return done(finishPackedHits(hits, names: pack, paths: paths, sort: sort, allowFullSort: allowFullSort))
        }

        if queryEmpty && unrestricted {
            if let cached, cached.sort == sort, cached.indices.count == total {
                return done(cached.indices)
            }
            let all = identitySnap.count == total ? identitySnap : Array(0..<total)
            let cheap = total <= Self.fullSortCheapLimit
            if allowFullSort, cheap || sort.column != .name || !sort.ascending {
                let indices = Self.sortPacked(
                    all,
                    names: pack,
                    paths: paths,
                    dirs: bits,
                    extras: extraSnap,
                    sizes: sizeSnap,
                    modifieds: modifiedSnap,
                    sort: sort
                )
                lock.lock()
                if origNamePack.count == total {
                    sortedAll = (sort, indices)
                }
                lock.unlock()
                return done(indices)
            }
            return done(all)
        }

        if !shouldContinue() { return [] }

        if options.regex {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let hay = options.matchPath
                ? (options.matchCase ? rawPaths : paths)
                : (options.matchCase ? rawNames : pack)
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
            var hits: [Int]
            if trimmed.isEmpty {
                hits = identitySnap.count == total ? identitySnap : Array(0..<total)
            } else if !options.matchWholeWord, let atom = PackedAtom.fromRegex(trimmed) {
                hits = hay.hits(atom: atom, candidates: seed, matchCase: options.matchCase)
            } else if let regex = Query.makeRegex(trimmed, matchCase: options.matchCase) {
                var pool = seed
                if let hint = PackedAtom.regexLiteralHint(trimmed), hint.count >= 2 {
                    pool = hay.hits(atom: .contains(hint), candidates: seed, matchCase: options.matchCase)
                }
                hits = hay.scanRegex(regex, candidates: pool)
            } else {
                return []
            }
            if !options.inFolder.isEmpty {
                hits = paths.inFolder(options.inFolder, candidates: hits)
            }
            if filter != .all {
                hits = Self.applyFilter(hits, filter: filter, pack: pack, dirs: bits)
            }
            return done(finishPackedHits(hits, names: pack, paths: paths, sort: sort, allowFullSort: allowFullSort))
        }

        if let groups = parsed.packedAtoms,
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
            var hits = Self.packedGroupHits(
                groups,
                names: options.matchCase ? rawNames : pack,
                paths: options.matchCase ? rawPaths : paths,
                suffixNames: pack,
                folderPack: paths,
                inFolder: options.inFolder,
                extras: extraSnap,
                sizes: sizeSnap,
                modifieds: modifiedSnap,
                createds: createdSnap,
                origNames: rawNames,
                origPaths: rawPaths,
                matchPath: options.matchPath,
                dirs: bits,
                total: total,
                seed: seed,
                wholeWord: options.matchWholeWord,
                matchCase: options.matchCase
            )
            if filter != .all {
                hits = Self.applyFilter(hits, filter: filter, pack: pack, dirs: bits)
            }
            return done(finishPackedHits(hits, names: pack, paths: paths, sort: sort, allowFullSort: allowFullSort))
        }

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
        } else if unrestricted, let cached, cached.sort == sort, cached.indices.count == total {
            pool = cached.indices
            alreadySorted = true
        } else if identitySnap.count == total {
            pool = identitySnap
        } else {
            pool = Array(0..<total)
        }

        let hits = Self.filter(
            pool,
            names: rawNames,
            paths: rawPaths,
            dirs: bits,
            extras: extraSnap,
            query: query,
            parsed: parsed,
            options: options,
            filter: filter,
            shouldContinue: shouldContinue
        )
        if alreadySorted { return done(hits) }
        return done(finishPackedHits(hits, names: pack, paths: paths, sort: sort, allowFullSort: allowFullSort))
    }

    private func promoteOpened(_ hits: [Int], openedCounts: [String: Int]) -> [Int] {
        guard !openedCounts.isEmpty, !hits.isEmpty else { return hits }
        lock.lock()
        var wanted: [Int: Int] = [:]
        wanted.reserveCapacity(min(openedCounts.count, 64))
        for (path, count) in openedCounts where count > 0 {
            if let index = pathIndex[path] {
                wanted[index] = count
            }
        }
        lock.unlock()
        guard !wanted.isEmpty else { return hits }
        var found: [(Int, Int, Int)] = []
        found.reserveCapacity(min(wanted.count, 32))
        for (order, index) in hits.enumerated() {
            if let count = wanted[index] {
                found.append((index, count, order))
            }
        }
        guard !found.isEmpty else { return hits }
        found.sort { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.2 < rhs.2
        }
        let front = found.map(\.0)
        let drop = Set(front)
        var out: [Int] = []
        out.reserveCapacity(hits.count)
        out.append(contentsOf: front)
        for index in hits where !drop.contains(index) {
            out.append(index)
        }
        return out
    }

    private func finishPackedHits(
        _ hits: [Int],
        names: NamePack,
        paths: NamePack,
        sort: SortState,
        allowFullSort: Bool
    ) -> [Int] {
        if hits.count > 2_048 || !allowFullSort {
            return hits
        }
        switch sort.column {
        case .name:
            return names.ordered(hits, ties: paths, ascending: sort.ascending)
        case .path:
            return paths.ordered(hits, ascending: sort.ascending)
        case .size, .modified:
            break
        }
        lock.lock()
        let rawNames = origNamePack
        let rawPaths = origPathPack
        let bits = dirBits
        let extraSnap = extras
        let sizeSnap = sizes
        let modifiedSnap = modifieds
        let createdSnap = createds
        lock.unlock()
        var subset: [FileEntry] = []
        subset.reserveCapacity(hits.count)
        for index in hits {
            guard let entry = Self.makeEntry(
                index,
                names: rawNames,
                paths: rawPaths,
                dirs: bits,
                extras: extraSnap,
                sizes: sizeSnap,
                modifieds: modifiedSnap,
                createds: createdSnap
            ) else { return hits }
            subset.append(entry)
        }
        let ordered = Self.sort(Array(subset.indices), entries: subset, sort: sort)
        return ordered.map { hits[$0] }
    }

    public func warmCaches(sort: SortState = SortState(), shouldContinue: () -> Bool = { true }) {
        lock.lock()
        let names = namePack
        let paths = pathPack
        let bits = dirBits
        let extraSnap = extras
        let sizeSnap = sizes
        let modifiedSnap = modifieds
        let total = origNamePack.count
        let small = total <= Self.fullSortCheapLimit
        let needSort = small && (sortedAll == nil || sortedAll?.sort != sort || sortedAll?.indices.count != total)
        lock.unlock()
        guard needSort, shouldContinue() else { return }
        let indices = Self.sortPacked(
            Array(0..<total),
            names: names,
            paths: paths,
            dirs: bits,
            extras: extraSnap,
            sizes: sizeSnap,
            modifieds: modifiedSnap,
            sort: sort
        )
        guard shouldContinue() else { return }
        lock.lock()
        if origNamePack.count == total {
            sortedAll = (sort, indices)
        }
        lock.unlock()
    }

    public func totalBytes(at indices: [Int]) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        var sum: Int64 = 0
        for index in indices {
            guard !dirBits.isDirectory(index) else { continue }
            let recorded = index >= 0 && index < sizes.count ? sizes[index] : -1
            if recorded >= 0 {
                sum += recorded
            } else {
                sum += extras[index]?.size ?? 0
            }
        }
        return sum
    }

    public func entries(at indices: [Int]) -> [FileEntry] {
        lock.lock()
        defer { lock.unlock() }
        return indices.compactMap { makeEntryLocked($0) }
    }

    public func entry(at index: Int) -> FileEntry? {
        lock.lock()
        defer { lock.unlock() }
        return makeEntryLocked(index)
    }

    public func directories() -> [FileEntry] {
        lock.lock()
        defer { lock.unlock() }
        return (0..<origNamePack.count).compactMap { index in
            guard dirBits.isDirectory(index) else { return nil }
            return makeEntryLocked(index)
        }
    }

    public func names(
        matching query: String,
        options: SearchOptions = SearchOptions(),
        filter: ResultFilter = .all,
        sort: SortState = SortState(),
        previous: SearchCursor? = nil,
        openedCounts: [String: Int] = [:]
    ) -> [String] {
        entries(at: search(
            query: query,
            options: options,
            filter: filter,
            sort: sort,
            previous: previous,
            openedCounts: openedCounts
        )).map(\.name)
    }

    public static let fullSortCheapLimit = 4_096

    public static func presentsUnsortedIdentity(
        query: String,
        options: SearchOptions = SearchOptions(),
        filter: ResultFilter = .all,
        sort: SortState = SortState(),
        total: Int,
        allowFullSort: Bool = true
    ) -> Bool {
        let parsed = Query.parse(query)
        guard parsed.isEmpty, !options.regex, options.inFolder.isEmpty, filter == .all else { return false }
        guard sort.column == .name, sort.ascending else { return false }
        return !allowFullSort || total > fullSortCheapLimit
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

    private func makeEntryLocked(_ index: Int) -> FileEntry? {
        Self.makeEntry(index, names: origNamePack, paths: origPathPack, dirs: dirBits, extras: extras, sizes: sizes, modifieds: modifieds, createds: createds)
    }

    private struct ColumnSnap {
        var names: NamePack
        var paths: NamePack
        var bits: DirBits
        var extras: [Int: FileRowExtras]
        var sizes: [Int64]
        var modifieds: [Int64]
        var createds: [Int64]
        var total: Int
    }

    private func snapshotColumnsLocked() -> ColumnSnap {
        ColumnSnap(
            names: origNamePack,
            paths: origPathPack,
            bits: dirBits,
            extras: extras,
            sizes: sizes,
            modifieds: modifieds,
            createds: createds,
            total: origNamePack.count
        )
    }

    private static func materialize(_ snap: ColumnSnap) -> [FileEntry] {
        var rows: [FileEntry] = []
        rows.reserveCapacity(snap.total)
        for index in 0..<snap.total {
            if let entry = makeEntry(
                index,
                names: snap.names,
                paths: snap.paths,
                dirs: snap.bits,
                extras: snap.extras,
                sizes: snap.sizes,
                modifieds: snap.modifieds,
                createds: snap.createds
            ) {
                rows.append(entry)
            }
        }
        return rows
    }

    @discardableResult
    private func installRows(_ rows: [FileEntry]) -> Int {
        let fragment = IndexFragment.pack(rows)
        var lookup = PathLookup()
        lookup.fill(from: fragment.origPathPack)
        lock.lock()
        namePack = fragment.namePack
        pathPack = fragment.pathPack
        origNamePack = fragment.origNamePack
        origPathPack = fragment.origPathPack
        dirBits = fragment.dirBits
        extras = fragment.extras
        sizes = fragment.sizes
        modifieds = fragment.modifieds
        createds = fragment.createds
        byteTotal = fragment.byteTotal
        identity = Array(0..<fragment.origNamePack.count)
        pathIndex = lookup
        postings.markDirty()
        sortedAll = nil
        let total = origNamePack.count
        lock.unlock()
        return total
    }

    private func appendPacks(_ entry: FileEntry) {
        let wrote = entry.name.utf8.withContiguousStorageIfAvailable { buf in
            namePack.appendLowercasing(utf8: buf)
            origNamePack.appendRaw(utf8: buf)
            pathPack.appendJoined(directory: entry.directory, nameUTF8: buf, lowercaseName: true)
            origPathPack.appendJoined(directory: entry.directory, nameUTF8: buf, lowercaseName: false)
            return true
        }
        if wrote != true {
            namePack.appendLowercasing(entry.name)
            origNamePack.appendRaw(entry.name)
            pathPack.appendJoined(directory: entry.directory, name: entry.name)
            origPathPack.appendJoinedRaw(directory: entry.directory, name: entry.name)
        }
        dirBits.append(entry.isDirectory)
        sizes.append(entry.isDirectory ? -1 : (entry.size ?? -1))
        modifieds.append(Self.unixStamp(entry.modified))
        createds.append(Self.unixStamp(entry.created))
    }

    static func append(
        directory: String,
        nameUTF8: UnsafeBufferPointer<UInt8>,
        isDirectory: Bool,
        size: Int64 = -1,
        modified: Int64 = -1,
        created: Int64 = -1,
        into fragment: inout IndexFragment
    ) {
        fragment.namePack.appendLowercasing(utf8: nameUTF8)
        fragment.origNamePack.appendRaw(utf8: nameUTF8)
        fragment.pathPack.appendJoined(directory: directory, nameUTF8: nameUTF8, lowercaseName: true)
        fragment.origPathPack.appendJoined(directory: directory, nameUTF8: nameUTF8, lowercaseName: false)
        fragment.dirBits.append(isDirectory)
        let recorded = isDirectory ? -1 : (size >= 0 ? size : -1)
        fragment.sizes.append(recorded)
        fragment.modifieds.append(modified)
        fragment.createds.append(created)
        if recorded > 0, recorded < 1_000_000_000_000 {
            fragment.byteTotal += recorded
        }
    }

    static func append(_ entry: FileEntry, into fragment: inout IndexFragment) {
        let wrote = entry.name.utf8.withContiguousStorageIfAvailable { buf -> Bool in
            fragment.namePack.appendLowercasing(utf8: buf)
            fragment.origNamePack.appendRaw(utf8: buf)
            fragment.pathPack.appendJoined(directory: entry.directory, nameUTF8: buf, lowercaseName: true)
            fragment.origPathPack.appendJoined(directory: entry.directory, nameUTF8: buf, lowercaseName: false)
            return true
        }
        if wrote != true {
            fragment.namePack.appendLowercasing(entry.name)
            fragment.origNamePack.appendRaw(entry.name)
            fragment.pathPack.appendJoined(directory: entry.directory, name: entry.name)
            fragment.origPathPack.appendJoinedRaw(directory: entry.directory, name: entry.name)
        }
        fragment.dirBits.append(entry.isDirectory)
        let recorded = entry.isDirectory ? -1 : (entry.size ?? -1)
        fragment.sizes.append(recorded)
        fragment.modifieds.append(unixStamp(entry.modified))
        fragment.createds.append(unixStamp(entry.created))
        if recorded > 0, recorded < 1_000_000_000_000 {
            fragment.byteTotal += recorded
        }
    }

    private func hasExtras(_ entry: FileEntry) -> Bool {
        entry.size != nil || entry.modified != nil || entry.created != nil || entry.isCloudOnly
    }

    private func writeExtras(_ index: Int, _ entry: FileEntry) {
        if index >= 0, index < sizes.count {
            sizes[index] = entry.isDirectory ? -1 : (entry.size ?? -1)
        }
        if index >= 0, index < modifieds.count {
            modifieds[index] = Self.unixStamp(entry.modified)
        }
        if index >= 0, index < createds.count {
            createds[index] = Self.unixStamp(entry.created)
        }
        if hasExtras(entry) {
            extras[index] = FileRowExtras(
                size: entry.size,
                modified: entry.modified,
                created: entry.created,
                isCloudOnly: entry.isCloudOnly
            )
        } else {
            extras.removeValue(forKey: index)
        }
    }

    private static func makeEntry(
        _ index: Int,
        names: NamePack,
        paths: NamePack,
        dirs: DirBits,
        extras: [Int: FileRowExtras],
        sizes: [Int64] = [],
        modifieds: [Int64] = [],
        createds: [Int64] = []
    ) -> FileEntry? {
        guard let name = names.string(at: index), let path = paths.string(at: index) else { return nil }
        let extra = extras[index]
        let recorded = index >= 0 && index < sizes.count ? sizes[index] : -1
        return FileEntry(
            name: name,
            directory: FileEntry.parentDirectory(fromPath: path, name: name),
            size: recorded >= 0 ? recorded : extra?.size,
            modified: date(fromUnix: recordedSize(index, modifieds)) ?? extra?.modified,
            created: date(fromUnix: recordedSize(index, createds)) ?? extra?.created,
            isDirectory: dirs.isDirectory(index),
            isCloudOnly: extra?.isCloudOnly ?? false
        )
    }

    private static func sortPacked(
        _ indices: [Int],
        names: NamePack,
        paths: NamePack,
        dirs: DirBits,
        extras: [Int: FileRowExtras],
        sizes: [Int64],
        modifieds: [Int64],
        sort: SortState
    ) -> [Int] {
        switch sort.column {
        case .name:
            return names.ordered(indices, ties: paths, ascending: sort.ascending)
        case .path:
            return paths.ordered(indices, ascending: sort.ascending)
        case .size:
            return indices.sorted { lhs, rhs in
                let asize = packedSize(lhs, dirs: dirs, extras: extras, sizes: sizes)
                let bsize = packedSize(rhs, dirs: dirs, extras: extras, sizes: sizes)
                if asize != bsize {
                    return sort.ascending ? asize < bsize : asize > bsize
                }
                return paths.compare(lhs, rhs) < 0
            }
        case .modified:
            return indices.sorted { lhs, rhs in
                let ad = packedTime(lhs, extras: extras, times: modifieds)
                let bd = packedTime(rhs, extras: extras, times: modifieds)
                if ad != bd {
                    return sort.ascending ? ad < bd : ad > bd
                }
                return paths.compare(lhs, rhs) < 0
            }
        }
    }

    private static func packedSize(
        _ index: Int,
        dirs: DirBits,
        extras: [Int: FileRowExtras],
        sizes: [Int64]
    ) -> Int64 {
        if dirs.isDirectory(index) { return Int64.min }
        let recorded = recordedSize(index, sizes)
        if recorded >= 0 { return recorded }
        return extras[index]?.size ?? -1
    }

    private static func packedTime(
        _ index: Int,
        extras: [Int: FileRowExtras],
        times: [Int64]
    ) -> Int64 {
        let recorded = recordedSize(index, times)
        if recorded >= 0 { return recorded }
        return unixStamp(extras[index]?.modified)
    }

    private static func packedGroupHits(
        _ groups: [[PackedAtom]],
        names: NamePack,
        paths: NamePack,
        suffixNames: NamePack,
        folderPack: NamePack,
        inFolder: String,
        extras: [Int: FileRowExtras],
        sizes: [Int64],
        modifieds: [Int64],
        createds: [Int64],
        origNames: NamePack,
        origPaths: NamePack,
        matchPath: Bool,
        dirs: DirBits,
        total: Int,
        seed: [Int]?,
        wholeWord: Bool,
        matchCase: Bool
    ) -> [Int] {
        var combined: [Int] = []
        var seen: Set<Int> = []
        for group in groups {
            let hits = packedOneGroup(
                group,
                names: names,
                paths: paths,
                suffixNames: suffixNames,
                folderPack: folderPack,
                inFolder: inFolder,
                extras: extras,
                sizes: sizes,
                modifieds: modifieds,
                createds: createds,
                origNames: origNames,
                origPaths: origPaths,
                matchPath: matchPath,
                dirs: dirs,
                total: total,
                seed: seed,
                wholeWord: wholeWord,
                matchCase: matchCase
            )
            if groups.count == 1 { return hits }
            for index in hits where seen.insert(index).inserted {
                combined.append(index)
            }
        }
        return combined
    }

    private static func packedOneGroup(
        _ group: [PackedAtom],
        names: NamePack,
        paths: NamePack,
        suffixNames: NamePack,
        folderPack: NamePack,
        inFolder: String,
        extras: [Int: FileRowExtras],
        sizes: [Int64],
        modifieds: [Int64],
        createds: [Int64],
        origNames: NamePack,
        origPaths: NamePack,
        matchPath: Bool,
        dirs: DirBits,
        total: Int,
        seed: [Int]?,
        wholeWord: Bool,
        matchCase: Bool
    ) -> [Int] {
        var texts: [PackedAtom] = []
        var suffixes: [String] = []
        var nots: [PackedAtom] = []
        var meta: [PackedAtom] = []
        var filesOnly = false
        var foldersOnly = false
        for atom in group {
            switch atom {
            case .files:
                filesOnly = true
            case .folders:
                foldersOnly = true
            case .anySuffix(let list):
                suffixes.append(contentsOf: list)
            case .not(let inner):
                nots.append(inner)
            case .fileSize, .modified, .created, .emptyFile:
                meta.append(atom)
            default:
                texts.append(atom)
            }
        }

        let pack = matchPath ? paths : names
        var hits = seed
        if !suffixes.isEmpty {
            var union: [Int] = []
            var seen = Set<Int>()
            for suffix in suffixes {
                for index in suffixNames.hits(atom: .suffix(suffix), candidates: hits) where seen.insert(index).inserted {
                    union.append(index)
                }
            }
            hits = union
        }
        let ordered = texts.sorted { lhs, rhs in
            Self.atomSelectivity(lhs) > Self.atomSelectivity(rhs)
        }
        for atom in ordered {
            let target: NamePack
            let query: PackedAtom
            if case .pathContains(let text) = atom {
                target = paths
                query = .contains(text)
            } else if case .nameContains(let text) = atom {
                target = names
                query = .contains(text)
            } else if case .parentContains = atom {
                target = paths
                query = atom
            } else if case .parentGlob = atom {
                target = paths
                query = atom
            } else if case .nameLength = atom {
                target = origNames
                query = atom
            } else if case .nameGlob(let pattern) = atom {
                target = names
                query = .glob(pattern)
            } else if case .pathGlob(let pattern) = atom {
                target = paths
                query = .glob(pattern)
            } else {
                target = pack
                query = atom
            }
            hits = target.hits(atom: query, candidates: hits, wholeWord: wholeWord, matchCase: matchCase)
            if hits?.isEmpty == true { return [] }
        }
        if hits == nil {
            hits = Array(0..<total)
        }
        guard var hits else { return [] }
        if filesOnly {
            hits = hits.filter { !dirs.isDirectory($0) }
        }
        if foldersOnly {
            hits = hits.filter { dirs.isDirectory($0) }
        }
        for banned in nots {
            let inner = packedOneGroup(
                [banned],
                names: names,
                paths: paths,
                suffixNames: suffixNames,
                folderPack: folderPack,
                inFolder: "",
                extras: extras,
                sizes: sizes,
                modifieds: modifieds,
                createds: createds,
                origNames: origNames,
                origPaths: origPaths,
                matchPath: matchPath,
                dirs: dirs,
                total: total,
                seed: hits,
                wholeWord: wholeWord,
                matchCase: matchCase
            )
            if !inner.isEmpty {
                let drop = Set(inner)
                hits = hits.filter { !drop.contains($0) }
            }
        }
        if !inFolder.isEmpty {
            hits = folderPack.inFolder(inFolder, candidates: hits)
        }
        if !meta.isEmpty {
            hits = applyMeta(meta, hits, extras: extras, sizes: sizes, modifieds: modifieds, createds: createds, origPaths: origPaths, dirs: dirs)
        }
        return hits
    }

    private static func applyMeta(
        _ meta: [PackedAtom],
        _ hits: [Int],
        extras: [Int: FileRowExtras],
        sizes: [Int64],
        modifieds: [Int64],
        createds: [Int64],
        origPaths: NamePack,
        dirs: DirBits
    ) -> [Int] {
        let sizeOnly = meta.allSatisfy { atom in
            switch atom {
            case .fileSize, .emptyFile: return true
            default: return false
            }
        }
        if !extras.isEmpty {
            var missing: [Int] = []
            missing.reserveCapacity(min(hits.count, 64))
            for index in hits {
                if sizeOnly, dirs.isDirectory(index) { continue }
                if !hasCachedMeta(
                    meta,
                    extras[index],
                    size: recordedSize(index, sizes),
                    modified: recordedSize(index, modifieds),
                    created: recordedSize(index, createds)
                ) {
                    missing.append(index)
                }
            }
            if missing.count >= 24 {
                var paths: [String] = []
                paths.reserveCapacity(missing.count)
                for index in missing {
                    if let path = origPaths.string(at: index) {
                        paths.append(path)
                    }
                }
                FileMetadata.prefetch(paths: paths)
            }
        }
        if sizeOnly {
            return filterBySize(meta, hits, extras: extras, sizes: sizes, origPaths: origPaths, dirs: dirs)
        }
        var remaining: [Int] = []
        remaining.reserveCapacity(hits.count)
        for index in hits {
            var ok = true
            for atom in meta {
                if !matchesMeta(atom, index: index, extras: extras, sizes: sizes, modifieds: modifieds, createds: createds, origPaths: origPaths, dirs: dirs) {
                    ok = false
                    break
                }
            }
            if ok { remaining.append(index) }
        }
        return remaining
    }

    private static func filterBySize(
        _ meta: [PackedAtom],
        _ hits: [Int],
        extras: [Int: FileRowExtras],
        sizes: [Int64],
        origPaths: NamePack,
        dirs: DirBits
    ) -> [Int] {
        var remaining: [Int] = []
        remaining.reserveCapacity(hits.count)
        let columnsOnly = extras.isEmpty
        for index in hits {
            if dirs.isDirectory(index) { continue }
            let size: Int64
            if columnsOnly {
                let recorded = recordedSize(index, sizes)
                if recorded < 0 { continue }
                size = recorded
            } else {
                guard let value = sizeOf(index, extras: extras, sizes: sizes, origPaths: origPaths) else { continue }
                size = value
            }
            var ok = true
            for atom in meta {
                switch atom {
                case .emptyFile:
                    if size != 0 { ok = false }
                case .fileSize(let pred):
                    if !compareSize(size, pred) { ok = false }
                default:
                    break
                }
                if !ok { break }
            }
            if ok { remaining.append(index) }
        }
        return remaining
    }

    private static func recordedSize(_ index: Int, _ sizes: [Int64]) -> Int64 {
        guard index >= 0, index < sizes.count else { return -1 }
        return sizes[index]
    }

    private static func dateOf(
        _ index: Int,
        column: [Int64],
        extra: Date?,
        origPaths: NamePack,
        load: (String) -> Date?
    ) -> Date? {
        if let date = date(fromUnix: recordedSize(index, column)) { return date }
        if let extra { return extra }
        return origPaths.string(at: index).flatMap(load)
    }

    private static func sizeOf(
        _ index: Int,
        extras: [Int: FileRowExtras],
        sizes: [Int64],
        origPaths: NamePack
    ) -> Int64? {
        let recorded = recordedSize(index, sizes)
        if recorded >= 0 { return recorded }
        if let extra = extras[index]?.size { return extra }
        return origPaths.string(at: index).flatMap { FileMetadata.load($0).size }
    }

    private static func hasCachedMeta(
        _ meta: [PackedAtom],
        _ extra: FileRowExtras?,
        size: Int64,
        modified: Int64,
        created: Int64
    ) -> Bool {
        for atom in meta {
            switch atom {
            case .fileSize, .emptyFile:
                if size < 0, extra?.size == nil { return false }
            case .modified:
                if modified < 0, extra?.modified == nil { return false }
            case .created:
                if created < 0, extra?.created == nil { return false }
            default:
                break
            }
        }
        return true
    }

    private static func matchesMeta(
        _ atom: PackedAtom,
        index: Int,
        extras: [Int: FileRowExtras],
        sizes: [Int64],
        modifieds: [Int64],
        createds: [Int64],
        origPaths: NamePack,
        dirs: DirBits
    ) -> Bool {
        switch atom {
        case .emptyFile:
            if dirs.isDirectory(index) { return false }
            return sizeOf(index, extras: extras, sizes: sizes, origPaths: origPaths) == 0
        case .fileSize(let pred):
            if dirs.isDirectory(index) { return false }
            guard let size = sizeOf(index, extras: extras, sizes: sizes, origPaths: origPaths) else { return false }
            return compareSize(size, pred)
        case .modified(let pred):
            return dateMatches(dateOf(index, column: modifieds, extra: extras[index]?.modified, origPaths: origPaths, load: { FileMetadata.load($0).modified }), pred)
        case .created(let pred):
            return dateMatches(dateOf(index, column: createds, extra: extras[index]?.created, origPaths: origPaths, load: { FileMetadata.load($0).created }), pred)
        default:
            return true
        }
    }

    private static func compareSize(_ size: Int64, _ pred: SizeCompare) -> Bool {
        switch pred {
        case .greater(let n): return size > n
        case .less(let n): return size < n
        case .equal(let n): return size == n
        }
    }

    private static func dateMatches(_ date: Date?, _ pred: DateCompare) -> Bool {
        guard let date else { return false }
        switch pred {
        case .range(let start, let end):
            return date >= start && date < end
        case .after(let bound):
            return date >= bound
        case .before(let bound):
            return date < bound
        }
    }

    private static func applyFilter(_ hits: [Int], filter: ResultFilter, pack: NamePack, dirs: DirBits) -> [Int] {
        switch filter {
        case .all:
            return hits
        case .folder:
            return hits.filter { dirs.isDirectory($0) }
        default:
            let suffixes = filter.extensions.map { "." + $0 }
            var union: [Int] = []
            var seen = Set<Int>()
            let pool = hits.filter { !dirs.isDirectory($0) }
            for suffix in suffixes {
                for index in pack.hits(atom: .suffix(suffix), candidates: pool) where seen.insert(index).inserted {
                    union.append(index)
                }
            }
            if filter == .executable {
                let apps = pack.hits(atom: .suffix(".app"), candidates: hits).filter { dirs.isDirectory($0) }
                for index in apps where seen.insert(index).inserted {
                    union.append(index)
                }
            }
            return union
        }
    }

    private static func atomSelectivity(_ atom: PackedAtom) -> Int {
        switch atom {
        case .exact(let text): return 1_000 + text.count
        case .prefix(let text), .suffix(let text), .contains(let text):
            return text.count
        case .anySuffix(let list):
            return 80 + (list.map(\.count).min() ?? 0)
        case .pathContains(let text), .nameContains(let text), .parentContains(let text), .parentGlob(let text):
            return text.count
        case .prefixAndSuffix(let a, let b):
            return a.count + b.count
        case .question(let text):
            return 400 + text.count
        case .glob(let text), .nameGlob(let text), .pathGlob(let text):
            return 350 + text.count
        case .nameLength:
            return 200
        case .regexPattern:
            return 50
        case .fileSize, .modified, .created, .emptyFile:
            return -1
        case .files, .folders, .not:
            return 0
        }
    }

    private static func filter(
        _ pool: [Int],
        names: NamePack,
        paths: NamePack,
        dirs: DirBits,
        extras: [Int: FileRowExtras],
        query: String,
        parsed: Query,
        options: SearchOptions,
        filter: ResultFilter,
        shouldContinue: () -> Bool
    ) -> [Int] {
        var hits: [Int] = []
        hits.reserveCapacity(min(pool.count, 64))

        func entry(at index: Int) -> FileEntry? {
            makeEntry(index, names: names, paths: paths, dirs: dirs, extras: extras)
        }

        if options.regex {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return pool.filter { index in
                    guard let entry = entry(at: index) else { return false }
                    return filter.matches(entry) && matchesFolder(entry, folder: options.inFolder)
                }
            }
            guard let regex = Query.makeRegex(trimmed, matchCase: options.matchCase) else {
                return []
            }
            for (offset, index) in pool.enumerated() {
                if offset & 0x1FFF == 0, !shouldContinue() { return [] }
                guard let entry = entry(at: index) else { continue }
                guard filter.matches(entry), matchesFolder(entry, folder: options.inFolder) else { continue }
                if Query.matchesRegex(entry, regex: regex, options: options) {
                    hits.append(index)
                }
            }
            return hits
        }

        for (offset, index) in pool.enumerated() {
            if offset & 0x1FFF == 0, !shouldContinue() { return [] }
            guard let entry = entry(at: index) else { continue }
            guard filter.matches(entry), matchesFolder(entry, folder: options.inFolder) else { continue }
            if parsed.matches(entry, options: options) {
                hits.append(index)
            }
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

struct DirBits: Sendable {
    private var words: [UInt64] = []
    private(set) var count = 0

    mutating func reset() {
        words.removeAll(keepingCapacity: true)
        count = 0
    }

    mutating func reserve(_ names: Int) {
        words.reserveCapacity((names + 63) / 64)
    }

    mutating func append(_ isDirectory: Bool) {
        let word = count / 64
        let bit = count % 64
        if word == words.count { words.append(0) }
        if isDirectory {
            words[word] |= 1 << bit
        }
        count += 1
    }

    mutating func append(contentsOf other: DirBits) {
        for index in 0..<other.count {
            append(other.isDirectory(index))
        }
    }

    func isDirectory(_ index: Int) -> Bool {
        guard index >= 0, index < count else { return false }
        return words[index / 64] & (1 << (index % 64)) != 0
    }
}

/// Maps a full path to its row without allocating a String per file.
/// Unique hashes stay as integers; only rare collisions keep a path string.
struct PathLookup {
    private var unique: [UInt64: Int] = [:]
    private var clashes: [String: Int] = [:]
    private var clashHashes: Set<UInt64> = []

    mutating func removeAll(keepingCapacity: Bool) {
        unique.removeAll(keepingCapacity: keepingCapacity)
        clashes.removeAll(keepingCapacity: keepingCapacity)
        clashHashes.removeAll(keepingCapacity: keepingCapacity)
    }

    mutating func reserveCapacity(_ minimumCapacity: Int) {
        unique.reserveCapacity(minimumCapacity)
    }

    subscript(path: String) -> Int? {
        get { lookup(path) }
        set {
            if let value = newValue {
                insert(path, at: value)
            }
        }
    }

    mutating func fill(from paths: NamePack) {
        removeAll(keepingCapacity: true)
        let total = paths.count
        guard total > 0 else { return }
        reserveCapacity(total)
        let offsets = paths.offsets
        paths.bytes.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            var index = 0
            while index < total {
                let start = offsets[index]
                let length = offsets[index + 1] - start - 1
                if length >= 0 {
                    insert(base + start, count: length, index: index, paths: paths, base: base)
                }
                index += 1
            }
        }
    }

    private mutating func insert(
        _ bytes: UnsafePointer<UInt8>,
        count: Int,
        index: Int,
        paths: NamePack,
        base: UnsafePointer<UInt8>
    ) {
        let hash = Self.hash(bytes, count: count)
        if clashHashes.contains(hash) {
            clashes[Self.decode(bytes, count: count)] = index
            return
        }
        if let existing = unique[hash] {
            clashHashes.insert(hash)
            unique[hash] = nil
            let oldStart = paths.offsets[existing]
            let oldLen = paths.offsets[existing + 1] - oldStart - 1
            if oldLen >= 0 {
                clashes[Self.decode(base + oldStart, count: oldLen)] = existing
            }
            clashes[Self.decode(bytes, count: count)] = index
            return
        }
        unique[hash] = index
    }

    private func lookup(_ path: String) -> Int? {
        let hash = Self.hash(path)
        if clashHashes.contains(hash) {
            if let hit = clashes[path] { return hit }
            return unique[hash]
        }
        return unique[hash]
    }

    private mutating func insert(_ path: String, at index: Int) {
        let hash = Self.hash(path)
        if clashHashes.contains(hash) {
            clashes[path] = index
            return
        }
        if let existing = unique[hash], existing != index {
            clashHashes.insert(hash)
            clashes[path] = index
            return
        }
        unique[hash] = index
    }

    private static func hash(_ ptr: UnsafePointer<UInt8>, count: Int) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_6037
        var offset = 0
        let stride = MemoryLayout<UInt64>.size
        while offset + stride <= count {
            var word: UInt64 = 0
            memcpy(&word, ptr + offset, stride)
            hash ^= word
            hash &*= 1_099_511_628_211
            offset += stride
        }
        while offset < count {
            hash ^= UInt64(ptr[offset])
            hash &*= 1_099_511_628_211
            offset += 1
        }
        return hash
    }

    private static func hash(_ path: String) -> UInt64 {
        var copy = path
        return copy.withUTF8 { buf in
            guard let ptr = buf.baseAddress else { return 0 }
            return hash(ptr, count: buf.count)
        }
    }

    private static func decode(_ ptr: UnsafePointer<UInt8>, count: Int) -> String {
        String(decoding: UnsafeBufferPointer(start: ptr, count: count), as: UTF8.self)
    }
}
