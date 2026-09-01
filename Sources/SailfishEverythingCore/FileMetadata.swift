import Foundation

public struct FileAttrs: Sendable, Equatable {
    public var size: Int64?
    public var modified: Date?
    public var created: Date?

    public init(size: Int64? = nil, modified: Date? = nil, created: Date? = nil) {
        self.size = size
        self.modified = modified
        self.created = created
    }
}

public enum FileMetadata {
    private static let lock = NSLock()
    private static var cache: [String: FileAttrs] = [:]
    private static let keys: Set<URLResourceKey> = [
        .fileSizeKey,
        .contentModificationDateKey,
        .creationDateKey,
        .isDirectoryKey,
    ]

    public static var cachedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return cache.count
    }

    public static func reset() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    public static func peek(_ path: String) -> FileAttrs? {
        lock.lock()
        defer { lock.unlock() }
        return cache[path]
    }

    public static func invalidate(_ path: String) {
        lock.lock()
        cache.removeValue(forKey: path)
        lock.unlock()
    }

    public static func invalidate<S: Sequence>(paths: S) where S.Element == String {
        lock.lock()
        for path in paths {
            cache.removeValue(forKey: path)
        }
        lock.unlock()
    }

    public static func load(_ path: String) -> FileAttrs {
        lock.lock()
        if let cached = cache[path] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let url = URL(fileURLWithPath: path)
        let values = (try? url.resourceValues(forKeys: keys)) ?? URLResourceValues()
        let attrs = FileAttrs(
            size: values.isDirectory == true ? nil : values.fileSize.map { Int64($0) },
            modified: values.contentModificationDate,
            created: values.creationDate
        )
        lock.lock()
        cache[path] = attrs
        lock.unlock()
        return attrs
    }

    public static func resolved(_ entry: FileEntry) -> FileAttrs {
        if entry.size != nil || entry.modified != nil || entry.created != nil {
            return FileAttrs(size: entry.size, modified: entry.modified, created: entry.created)
        }
        return load(entry.path)
    }

    public static func size(of entry: FileEntry) -> Int64? {
        if entry.isDirectory { return nil }
        return entry.size ?? load(entry.path).size
    }

    public static func modified(of entry: FileEntry) -> Date? {
        entry.modified ?? load(entry.path).modified
    }

    public static func created(of entry: FileEntry) -> Date? {
        entry.created ?? load(entry.path).created
    }

    public static func prefetch(entries: [FileEntry], indices: [Int]) {
        var paths: [String] = []
        paths.reserveCapacity(min(indices.count, 128))
        lock.lock()
        for index in indices {
            guard index >= 0, index < entries.count else { continue }
            let entry = entries[index]
            if entry.size != nil || entry.modified != nil { continue }
            if cache[entry.path] != nil { continue }
            paths.append(entry.path)
        }
        lock.unlock()
        guard !paths.isEmpty else { return }
        if paths.count < 24 {
            for path in paths {
                _ = load(path)
            }
            return
        }
        DispatchQueue.concurrentPerform(iterations: paths.count) { offset in
            _ = load(paths[offset])
        }
    }
}
