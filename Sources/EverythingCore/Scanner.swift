import Foundation
import CoreServices

public protocol FileScannerDelegate: AnyObject {
    func scanner(_ scanner: FileScanner, didAdd batch: [FileEntry], total: Int)
    func scannerDidFinish(_ scanner: FileScanner, total: Int)
    func scannerDidFail(_ scanner: FileScanner, error: Error)
}

public final class FileScanner: @unchecked Sendable {
    public weak var delegate: FileScannerDelegate?

    private let index: FileIndex
    private let rootPath: String
    private let policy: ScanPolicy
    private let enableWatch: Bool
    private let notifyOnMain: Bool
    private let queue = DispatchQueue(label: "everything.scanner", qos: .utility)
    private var stopFlag = false
    private var eventStream: FSEventStreamRef?

    private static let resourceKeys: Set<URLResourceKey> = [
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

    public init(
        index: FileIndex,
        root: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        policy: ScanPolicy = .default,
        enableWatch: Bool = true,
        notifyOnMain: Bool = true
    ) {
        self.index = index
        self.rootPath = root.resolvingSymlinksInPath().path
        self.policy = policy
        self.enableWatch = enableWatch
        self.notifyOnMain = notifyOnMain
    }

    public func start() {
        queue.async { [weak self] in
            self?.scan()
        }
    }

    public func stop() {
        stopFlag = true
        stopEvents()
    }

    public func rebuild() {
        stopFlag = true
        queue.async { [weak self] in
            guard let self else { return }
            self.stopEvents()
            self.index.reset()
            self.stopFlag = false
            self.scan()
        }
    }

    public func scanSynchronously() {
        stopFlag = false
        scan()
    }

    private func scan() {
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(Self.resourceKeys),
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            notify { delegate in
                delegate.scannerDidFail(self, error: NSError(
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
            notify { delegate in
                delegate.scanner(self, didAdd: outgoing, total: total)
            }
        }

        if let rootEntry = makeEntry(for: root, keys: Self.resourceKeys) {
            batch.append(rootEntry)
        }

        while let item = enumerator.nextObject() as? URL {
            if stopFlag { break }

            let values = (try? item.resourceValues(forKeys: Self.resourceKeys)) ?? URLResourceValues()
            let isDirectory = values.isDirectory == true
            let isPackage = values.isPackage == true
            let name = item.lastPathComponent
            let relative = relativePath(item.path)

            if policy.shouldSkipDescending(relative: relative, name: name) || isPackage {
                if isDirectory {
                    enumerator.skipDescendants()
                }
            }

            if policy.shouldOmitEntry(name: name) {
                continue
            }

            if let entry = makeEntry(for: item, values: values) {
                batch.append(entry)
                flush(force: false)
            }
        }

        flush(force: true)

        let total = index.count
        notify { delegate in
            delegate.scannerDidFinish(self, total: total)
        }

        if !stopFlag, enableWatch {
            startEvents()
        }
    }

    public func relativePath(_ path: String) -> String {
        let normalized = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        if normalized == rootPath { return "" }
        if normalized.hasPrefix(rootPath + "/") {
            return String(normalized.dropFirst(rootPath.count + 1))
        }
        return normalized
    }

    public static func makeEntry(for url: URL, values: URLResourceValues) -> FileEntry? {
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

        let resolved = url.resolvingSymlinksInPath()
        let path = resolved.path
        let directory = resolved.deletingLastPathComponent().path
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

    private func makeEntry(for url: URL, keys: Set<URLResourceKey>) -> FileEntry? {
        let values = (try? url.resourceValues(forKeys: keys)) ?? URLResourceValues()
        return Self.makeEntry(for: url, values: values)
    }

    private func makeEntry(for url: URL, values: URLResourceValues) -> FileEntry? {
        Self.makeEntry(for: url, values: values)
    }

    private func notify(_ body: @escaping (FileScannerDelegate) -> Void) {
        guard let delegate else { return }
        if notifyOnMain {
            DispatchQueue.main.async { body(delegate) }
        } else {
            body(delegate)
        }
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
        let paths = [rootPath] as CFArray
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, count, pathsPointer, flagsPointer, _ in
                guard let info else { return }
                let scanner = Unmanaged<FileScanner>.fromOpaque(info).takeUnretainedValue()
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

        for path in paths {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
                let url = URL(fileURLWithPath: path, isDirectory: isDir.boolValue)
                let relative = relativePath(path)
                let name = url.lastPathComponent
                if policy.shouldSkipDescending(relative: relative, name: name) {
                    continue
                }
                if let entry = makeEntry(for: url, keys: Self.resourceKeys) {
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
        notify { delegate in
            delegate.scanner(self, didAdd: added, total: total)
        }
    }

    deinit {
        stopEvents()
    }
}
