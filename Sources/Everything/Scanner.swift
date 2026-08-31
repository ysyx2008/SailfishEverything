import Foundation
import CoreServices

protocol ScannerDelegate: AnyObject {
    func scanner(_ scanner: Scanner, didAdd batch: [FileEntry], total: Int)
    func scannerDidFinish(_ scanner: Scanner, total: Int)
    func scannerDidFail(_ scanner: Scanner, error: Error)
}

final class Scanner: @unchecked Sendable {
    weak var delegate: ScannerDelegate?

    private let index: FileIndex
    private let queue = DispatchQueue(label: "everything.scanner", qos: .utility)
    private var stopFlag = false
    private var eventStream: FSEventStreamRef?
    private let home = NSHomeDirectory()

    private let skipNames: Set<String> = [
        ".Trash", ".Trashes", "node_modules", ".git", "__pycache__",
        ".venv", "venv", ".npm", ".pnpm-store", ".build", ".gradle",
        ".swiftpm", "DerivedData", "CoreSimulator",
    ]

    private let skipRelativePrefixes = [
        "Library/Caches",
        "Library/Logs",
        "Library/Developer",
        "Library/Containers",
        "Library/Metadata",
        "Library/Mail",
        "Library/Safari",
        "Library/Mobile Documents/com~apple~CloudDocs/Desktop",
        "Library/Mobile Documents/com~apple~CloudDocs/Documents",
        "Library/Mobile Documents/com~apple~CloudDocs/Downloads",
    ]

    init(index: FileIndex) {
        self.index = index
    }

    func start() {
        queue.async { [weak self] in
            self?.scan()
        }
    }

    func stop() {
        stopFlag = true
        stopEvents()
    }

    func rebuild() {
        stopFlag = true
        queue.async { [weak self] in
            guard let self else { return }
            self.stopEvents()
            self.index.reset()
            self.stopFlag = false
            self.scan()
        }
    }

    private func scan() {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isPackageKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .contentModificationDateKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .nameKey,
        ]

        let root = URL(fileURLWithPath: home, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.scannerDidFail(self, error: NSError(
                    domain: "Everything",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Could not start scan"]
                ))
            }
            return
        }

        var batch: [FileEntry] = []
        batch.reserveCapacity(2_000)
        var lastFlush = Date()

        func flush(force: Bool) {
            guard !batch.isEmpty else { return }
            if !force, Date().timeIntervalSince(lastFlush) < 0.2, batch.count < 2_000 {
                return
            }
            let outgoing = batch
            batch.removeAll(keepingCapacity: true)
            lastFlush = Date()
            let total = index.add(outgoing)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.scanner(self, didAdd: outgoing, total: total)
            }
        }

        if let homeEntry = makeEntry(for: root, keys: keys) {
            batch.append(homeEntry)
        }

        while let item = enumerator.nextObject() as? URL {
            if stopFlag { break }

            let values = (try? item.resourceValues(forKeys: keys)) ?? URLResourceValues()
            let isDirectory = values.isDirectory == true
            let isPackage = values.isPackage == true
            let name = item.lastPathComponent
            let relative = relativePath(item.path)

            if shouldSkipDescending(relative: relative, name: name) || isPackage {
                if isDirectory {
                    enumerator.skipDescendants()
                }
            }

            if skipNames.contains(name), name.hasPrefix(".") {
                continue
            }

            if let entry = makeEntry(for: item, values: values) {
                batch.append(entry)
                flush(force: false)
            }
        }

        flush(force: true)

        let total = index.count
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.scannerDidFinish(self, total: total)
        }

        if !stopFlag {
            startEvents()
        }
    }

    private func relativePath(_ path: String) -> String {
        if path == home { return "" }
        if path.hasPrefix(home + "/") {
            return String(path.dropFirst(home.count + 1))
        }
        return path
    }

    private func shouldSkipDescending(relative: String, name: String) -> Bool {
        if skipNames.contains(name) { return true }
        for prefix in skipRelativePrefixes {
            if relative == prefix || relative.hasPrefix(prefix + "/") {
                return true
            }
        }
        return false
    }

    private func makeEntry(for url: URL, keys: Set<URLResourceKey>) -> FileEntry? {
        let values = (try? url.resourceValues(forKeys: keys)) ?? URLResourceValues()
        return makeEntry(for: url, values: values)
    }

    private func makeEntry(for url: URL, values: URLResourceValues) -> FileEntry? {
        let name = values.name ?? url.lastPathComponent
        guard !name.isEmpty else { return nil }
        let isDirectory = values.isDirectory == true
        let size = values.fileSize.map { Int64($0) }
        let allocated = values.totalFileAllocatedSize.map { Int64($0) }
        let isUbiquitous = values.isUbiquitousItem == true
        let downloadStatus = values.ubiquitousItemDownloadingStatus
        let cloudOnly: Bool = {
            if isUbiquitous, let downloadStatus, downloadStatus != .current {
                return true
            }
            if let size, let allocated, size > 0, allocated == 0 {
                return true
            }
            return false
        }()

        let path = url.path
        let directory = url.deletingLastPathComponent().path
        return FileEntry(
            name: name,
            nameLower: name.lowercased(),
            directory: directory,
            path: path,
            pathLower: path.lowercased(),
            size: isDirectory ? nil : size,
            modified: values.contentModificationDate,
            isDirectory: isDirectory,
            isCloudOnly: cloudOnly
        )
    }

    private func startEvents() {
        stopEvents()
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let paths = [home] as CFArray
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, count, pathsPointer, flagsPointer, _ in
                guard let info else { return }
                let scanner = Unmanaged<Scanner>.fromOpaque(info).takeUnretainedValue()
                let paths = UnsafeBufferPointer(
                    start: pathsPointer.assumingMemoryBound(to: UnsafePointer<CChar>.self),
                    count: count
                )
                let flags = UnsafeBufferPointer(start: flagsPointer, count: count)
                var changed: [String] = []
                changed.reserveCapacity(count)
                for i in 0..<count {
                    changed.append(String(cString: paths[i]))
                    _ = flags[i]
                }
                scanner.handleFSEvents(changed)
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.8,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
            )
        ) else { return }

        eventStream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    private func stopEvents() {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }
    }

    private func handleFSEvents(_ paths: [String]) {
        if stopFlag { return }
        var added: [FileEntry] = []
        var removed: [String] = []
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isPackageKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .contentModificationDateKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .nameKey,
        ]

        for path in paths {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
                let url = URL(fileURLWithPath: path, isDirectory: isDir.boolValue)
                let relative = relativePath(path)
                let name = url.lastPathComponent
                if shouldSkipDescending(relative: relative, name: name) {
                    continue
                }
                if let entry = makeEntry(for: url, keys: keys) {
                    added.append(entry)
                }
            } else {
                removed.append(path)
            }
        }

        if !removed.isEmpty {
            index.remove(paths: removed)
        }
        let total: Int
        if !added.isEmpty {
            total = index.add(added)
        } else {
            total = index.count
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.scanner(self, didAdd: added, total: total)
        }
    }

    deinit {
        stopEvents()
    }
}
