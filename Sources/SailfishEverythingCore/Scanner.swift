import Foundation
import CoreServices

public protocol FileScannerDelegate: AnyObject {
    func scanner(_ scanner: FileScanner, didAdd batch: [FileEntry], total: Int)
    func scannerDidFinish(_ scanner: FileScanner, total: Int)
    func scannerDidFail(_ scanner: FileScanner, error: Error)
    func scanner(_ scanner: FileScanner, didBeginPhase title: String)
}

public extension FileScannerDelegate {
    func scanner(_ scanner: FileScanner, didBeginPhase title: String) {}
}

public final class FileScanner: @unchecked Sendable {
    public weak var delegate: FileScannerDelegate?

    private let index: FileIndex
    private let rootPath: String
    private var settings: IndexSettings
    private var policy: ScanPolicy
    private let enableWatch: Bool
    private let notifyOnMain: Bool
    private let queue = DispatchQueue(label: "everything.scanner", qos: .utility)
    private let addQueue = DispatchQueue(label: "sailfish.index-add", qos: .utility)
    private let addInflight = DispatchSemaphore(value: 12)
    private var stopFlag = false
    private var eventStream: FSEventStreamRef?
    private var watchApplyReady = false
    private var pendingWatch: [(path: String, flags: FSEventStreamEventFlags)] = []

    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isPackageKey,
        .isUbiquitousItemKey,
        .ubiquitousItemDownloadingStatusKey,
        .nameKey,
    ]

    public init(
        index: FileIndex,
        root: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        settings: IndexSettings = .default,
        policy: ScanPolicy? = nil,
        enableWatch: Bool = true,
        notifyOnMain: Bool = true
    ) {
        self.index = index
        self.rootPath = root.resolvingSymlinksInPath().path
        self.settings = settings
        self.policy = policy ?? ScanPolicy.from(settings)
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
        DiagnosticLog.shared.event("scan", "rebuild")
        queue.async { [weak self] in
            guard let self else { return }
            self.stopEvents()
            self.index.reset()
            self.stopFlag = false
            self.scan()
        }
    }

    public func apply(_ settings: IndexSettings) {
        stopFlag = true
        DiagnosticLog.shared.event("scan", "apply settings")
        queue.async { [weak self] in
            guard let self else { return }
            self.stopEvents()
            self.settings = settings
            self.policy = ScanPolicy.from(settings)
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
        let home = URL(fileURLWithPath: rootPath, isDirectory: true)
        var homeIsDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: rootPath, isDirectory: &homeIsDir) || !homeIsDir.boolValue {
            DiagnosticLog.shared.event("scan", "fail \(L10n.t(.homeMissing))")
            notify { delegate in
                delegate.scannerDidFail(self, error: NSError(
                    domain: "SailfishEverything",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: L10n.t(.homeMissing)]
                ))
            }
            return
        }
        policy = ScanPolicy.from(settings)
        lastProgressNs = 0
        lastDiagNs = 0
        watchApplyReady = false
        pendingWatch.removeAll(keepingCapacity: true)
        DiagnosticLog.shared.event("scan", "begin")
        index.beginBulkLoad()
        if enableWatch {
            startEvents()
        }

        notify { delegate in
            delegate.scanner(self, didBeginPhase: L10n.t(.homeFolder))
        }
        DiagnosticLog.shared.event("scan", "phase \(L10n.t(.homeFolder))")
        let walkStart = DispatchTime.now()
        walkPublishing(rootPath)

        for extra in settings.extraRootURLs(home: home) {
            if stopFlag { break }
            let title = settings.extraWalkTitle(for: extra, home: home)
            notify { delegate in
                delegate.scanner(self, didBeginPhase: title)
            }
            DiagnosticLog.shared.event("scan", "phase \(title)")
            walkPublishing(extra.path)
        }
        let walkMs = DiagnosticLog.elapsedMilliseconds(since: walkStart)
        DiagnosticLog.shared.event("scan", "walk done \(DiagnosticLog.formatDuration(walkMs))")

        DiagnosticLog.shared.event("scan", "merge begin")
        let mergeStart = DispatchTime.now()
        index.endBulkLoad()
        let total = index.count
        DiagnosticLog.shared.event(
            "scan",
            "merge done total=\(total) \(DiagnosticLog.formatDuration(DiagnosticLog.elapsedMilliseconds(since: mergeStart)))"
        )
        notify { delegate in
            delegate.scannerDidFinish(self, total: total)
        }

        if !stopFlag {
            DiagnosticLog.shared.event("scan", "path index begin")
            let pathStart = DispatchTime.now()
            index.buildPathIndex()
            let pathMs = DiagnosticLog.elapsedMilliseconds(since: pathStart)
            DiagnosticLog.shared.event("scan", "path index done \(DiagnosticLog.formatDuration(pathMs))")
            benchScan(walkMs: walkMs, pathMs: pathMs, total: total)
            DispatchQueue.global(qos: .utility).async { [weak self] in
                DiagnosticLog.shared.event("scan", "warm begin")
                let warmStart = DispatchTime.now()
                self?.index.warmCaches()
                DiagnosticLog.shared.event(
                    "scan",
                    "warm done \(DiagnosticLog.formatDuration(DiagnosticLog.elapsedMilliseconds(since: warmStart)))"
                )
            }
        }
        DiagnosticLog.shared.event("scan", "finish total=\(total)")
        if !stopFlag {
            watchApplyReady = true
            flushPendingWatch()
        }
    }

    public func ingestWatchPaths(_ paths: [String], mustScanSubdirs: Bool = false) {
        let flags = FSEventStreamEventFlags(
            mustScanSubdirs ? UInt32(kFSEventStreamEventFlagMustScanSubDirs) : 0
        )
        let items = paths.map { (path: $0, flags: flags) }
        if notifyOnMain {
            queue.async { [weak self] in
                self?.applyWatchEvents(items)
            }
        } else {
            applyWatchEvents(items)
        }
    }

    private func publish(_ batch: [FileEntry], notifyEntries: Bool) {
        guard !batch.isEmpty else { return }
        let total = index.add(batch)
        notify { delegate in
            delegate.scanner(self, didAdd: notifyEntries ? batch : [], total: total)
        }
    }

    private func walkPublishing(_ root: String) {
        let pending = DispatchGroup()
        FastWalk.walk(
            root: root,
            rootPath: rootPath,
            policy: policy,
            stop: { self.stopFlag }
        ) { fragment in
            guard fragment.origNamePack.count > 0 else { return }
            self.addInflight.wait()
            pending.enter()
            self.addQueue.async {
                let total = self.index.add(fragment)
                self.publishProgress(total)
                self.addInflight.signal()
                pending.leave()
            }
        }
        pending.wait()
        publishProgress(index.count, force: true)
    }

    private var lastProgressNs: UInt64 = 0
    private var lastDiagNs: UInt64 = 0

    private func publishProgress(_ total: Int, force: Bool = false) {
        let now = DispatchTime.now().uptimeNanoseconds
        if !force, now &- lastProgressNs < 80_000_000 { return }
        lastProgressNs = now
        if force || lastDiagNs == 0 || now &- lastDiagNs >= 2_000_000_000 {
            lastDiagNs = now
            DiagnosticLog.shared.event("scan", "progress \(total)")
        }
        notify { delegate in
            delegate.scanner(self, didAdd: [], total: total)
        }
    }

    private func benchScan(walkMs: Double, pathMs: Double, total: Int) {
        guard ProcessInfo.processInfo.environment["SAILFISH_BENCH"] == "1", total >= 1_000 else { return }
        print(String(format: "bench %6.2fms  scan walk+merge %d", walkMs, total))
        print(String(format: "bench %6.2fms  scan path index", pathMs))
    }

    private func scanTree(_ root: URL, reportFailure: Bool = true, append: (FileEntry) -> Void) {
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if policy.skipHiddenFolders {
            options.insert(.skipsHiddenFiles)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(Self.resourceKeys),
            options: options,
            errorHandler: { _, _ in true }
        ) else {
            if reportFailure {
                DiagnosticLog.shared.event("scan", "fail \(L10n.t(.scanFailed))")
                notify { delegate in
                    delegate.scannerDidFail(self, error: NSError(
                        domain: "SailfishEverything",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: L10n.t(.scanFailed)]
                    ))
                }
            }
            return
        }

        if let rootEntry = makeEntry(for: root, keys: Self.resourceKeys) {
            append(rootEntry)
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
                append(entry)
            }
        }
    }

    public func relativePath(_ path: String) -> String {
        if path == rootPath { return "" }
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        let normalized = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        if normalized == rootPath { return "" }
        if normalized.hasPrefix(rootPath + "/") {
            return String(normalized.dropFirst(rootPath.count + 1))
        }
        return normalized
    }

    public static func makeEntry(for url: URL, values: URLResourceValues, rootPath: String? = nil) -> FileEntry? {
        let name = values.name ?? url.lastPathComponent
        guard !name.isEmpty else { return nil }
        let isDirectory = values.isDirectory == true
        let isUbiquitous = values.isUbiquitousItem == true
        let downloadStatus = values.ubiquitousItemDownloadingStatus
        let cloudOnly = isUbiquitous && downloadStatus != nil && downloadStatus != .current
        let (_, directory) = alignedPaths(for: url, rootPath: rootPath)
        return FileEntry(
            name: name,
            directory: directory,
            isDirectory: isDirectory,
            isCloudOnly: cloudOnly
        )
    }

    private static func alignedPaths(for url: URL, rootPath: String?) -> (String, String) {
        let raw = url.path
        if let rootPath, raw == rootPath || raw.hasPrefix(rootPath + "/") {
            return (raw, url.deletingLastPathComponent().path)
        }
        if rootPath != nil {
            let resolved = url.resolvingSymlinksInPath()
            return (resolved.path, resolved.deletingLastPathComponent().path)
        }
        return (raw, url.deletingLastPathComponent().path)
    }

    private func makeEntry(for url: URL, keys: Set<URLResourceKey>) -> FileEntry? {
        let values = (try? url.resourceValues(forKeys: keys)) ?? URLResourceValues()
        return Self.makeEntry(for: url, values: values, rootPath: rootPath)
    }

    private func makeEntry(for url: URL, values: URLResourceValues) -> FileEntry? {
        Self.makeEntry(for: url, values: values, rootPath: rootPath)
    }

    private func immediateEntries(in directory: URL) -> [FileEntry] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(Self.resourceKeys),
            options: []
        )) ?? []
        return items.compactMap { item in
            let name = item.lastPathComponent
            let relative = relativePath(item.path)
            if policy.shouldSkipDescending(relative: relative, name: name) { return nil }
            if policy.shouldOmitEntry(name: name) { return nil }
            return makeEntry(for: item, keys: Self.resourceKeys)
        }
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
        let home = URL(fileURLWithPath: rootPath, isDirectory: true)
        let paths = ([rootPath] + settings.extraRootURLs(home: home).map(\.path)) as CFArray
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
                var changed: [(path: String, flags: FSEventStreamEventFlags)] = []
                changed.reserveCapacity(count)
                for i in 0..<count {
                    changed.append((String(cString: paths[i]), flags[i]))
                }
                scanner.handleFSEvents(changed)
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
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

    private func handleFSEvents(_ events: [(path: String, flags: FSEventStreamEventFlags)]) {
        if stopFlag { return }
        if !watchApplyReady {
            pendingWatch.append(contentsOf: events)
            return
        }
        applyWatchEvents(events)
    }

    private func flushPendingWatch() {
        guard !pendingWatch.isEmpty else { return }
        let events = pendingWatch
        pendingWatch.removeAll(keepingCapacity: true)
        applyWatchEvents(events)
    }

    private func applyWatchEvents(_ events: [(path: String, flags: FSEventStreamEventFlags)]) {
        if stopFlag || events.isEmpty { return }
        var added: [FileEntry] = []
        var removed: [String] = []
        var walked = Set<String>()
        let extras = extraWatchRoots()

        for event in events {
            if stopFlag { return }
            let raw = event.path
            let flags = event.flags
            let needsTree = Self.needsSubtreeScan(flags)
            let path = alignWatchPath(raw, extras: extras)

            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
                || FileManager.default.fileExists(atPath: raw, isDirectory: &isDir)

            if exists {
                if shouldIgnoreWatch(path, extras: extras) { continue }
                if needsTree, isDir.boolValue, path != rootPath, walked.insert(path).inserted {
                    added.append(contentsOf: collectTree(at: path))
                    removed.append(contentsOf: missingKnown(under: path))
                    continue
                }
                let url = URL(fileURLWithPath: path, isDirectory: isDir.boolValue)
                if let entry = makeEntry(for: url, keys: Self.resourceKeys) {
                    added.append(entry)
                    if isDir.boolValue, !knownPath(path), path != rootPath, walked.insert(path).inserted {
                        added.append(contentsOf: collectTree(at: path))
                    } else if isDir.boolValue {
                        added.append(contentsOf: immediateEntries(in: url))
                        removed.append(contentsOf: missingKnown(under: path))
                    }
                }
            } else {
                if shouldIgnoreWatch(path, extras: extras), shouldIgnoreWatch(raw, extras: extras) {
                    continue
                }
                let resolved = preferRootStyle(URL(fileURLWithPath: raw).resolvingSymlinksInPath().path)
                let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
                let resolvedParent = preferRootStyle(
                    URL(fileURLWithPath: raw).deletingLastPathComponent().resolvingSymlinksInPath().path
                )
                let name = URL(fileURLWithPath: path).lastPathComponent
                for candidate in pathAliases(raw) + pathAliases(path) + pathAliases(resolved) {
                    removed.append(candidate)
                    removed.append(contentsOf: index.paths(under: candidate))
                }
                for folder in Set(pathAliases(parent) + pathAliases(resolvedParent)) {
                    removed.append(contentsOf: index.paths(under: folder).filter {
                        URL(fileURLWithPath: $0).lastPathComponent == name
                    })
                }
            }
        }

        added = added.filter { FileManager.default.fileExists(atPath: $0.path) }

        let watchStart = DispatchTime.now()
        if !removed.isEmpty {
            FileMetadata.invalidate(paths: removed)
            index.remove(paths: removed)
        }
        if !added.isEmpty {
            FileMetadata.invalidate(paths: added.map(\.path))
        }
        let total: Int
        if !added.isEmpty {
            total = index.add(added, replace: true)
        } else {
            total = index.count
        }
        let watchMs = DiagnosticLog.elapsedMilliseconds(since: watchStart)
        if watchMs >= 50 {
            DiagnosticLog.shared.event(
                "scan",
                "watch \(DiagnosticLog.formatDuration(watchMs)) added=\(added.count) removed=\(removed.count)"
            )
        }
        notify { delegate in
            delegate.scanner(self, didAdd: added, total: total)
        }
    }

    private static func needsSubtreeScan(_ flags: FSEventStreamEventFlags) -> Bool {
        let mask = FSEventStreamEventFlags(
            UInt32(kFSEventStreamEventFlagMustScanSubDirs)
                | UInt32(kFSEventStreamEventFlagUserDropped)
                | UInt32(kFSEventStreamEventFlagKernelDropped)
        )
        return flags & mask != 0
    }

    private func extraWatchRoots() -> [String] {
        let home = URL(fileURLWithPath: rootPath, isDirectory: true)
        return settings.extraRootURLs(home: home).map(\.path)
    }

    private func alignWatchPath(_ raw: String, extras: [String]) -> String {
        let localized = localizeWatchPath(raw, extras: extras)
        if keepsLocalDesktopForm(localized) { return preferRootStyle(localized) }
        let resolved = URL(fileURLWithPath: localized).resolvingSymlinksInPath().path
        if isUnderAnyRoot(resolved, extras: extras) { return preferRootStyle(resolved) }
        return preferRootStyle(localized)
    }

    private func preferRootStyle(_ path: String) -> String {
        if path.hasPrefix("/var/"), rootPath.hasPrefix("/private/var/") {
            return "/private" + path
        }
        if path.hasPrefix("/private/var/"), rootPath.hasPrefix("/var/") {
            return String(path.dropFirst("/private".count))
        }
        return path
    }

    private func pathAliases(_ path: String) -> [String] {
        var aliases = [path]
        if path.hasPrefix("/private/") {
            aliases.append(String(path.dropFirst("/private".count)))
        } else if path.hasPrefix("/") {
            aliases.append("/private" + path)
        }
        return aliases
    }

    private func localizeWatchPath(_ raw: String, extras: [String]) -> String {
        if let mapped = mapICloudMirror(raw) { return mapped }
        if isUnderAnyRoot(raw, extras: extras) { return raw }
        let resolved = URL(fileURLWithPath: raw).resolvingSymlinksInPath().path
        if let mapped = mapICloudMirror(resolved) { return mapped }
        if isUnderAnyRoot(resolved, extras: extras) { return resolved }
        return raw
    }

    private func keepsLocalDesktopForm(_ path: String) -> Bool {
        let relative = relativeWithoutResolve(path)
        for (cloud, local) in Self.icloudMirrors {
            guard relative == local || relative.hasPrefix(local + "/") else { continue }
            let localRoot = rootPath + "/" + local
            let cloudRoot = rootPath + "/" + cloud
            let localResolved = URL(fileURLWithPath: localRoot).resolvingSymlinksInPath().path
            let cloudResolved = URL(fileURLWithPath: cloudRoot).resolvingSymlinksInPath().path
            return localResolved == cloudResolved
        }
        return false
    }

    private func mapICloudMirror(_ path: String) -> String? {
        let relative = relativeWithoutResolve(path)
        for (cloud, local) in Self.icloudMirrors {
            guard relative == cloud || relative.hasPrefix(cloud + "/") else { continue }
            let localRoot = rootPath + "/" + local
            let cloudRoot = rootPath + "/" + cloud
            let localResolved = URL(fileURLWithPath: localRoot).resolvingSymlinksInPath().path
            let cloudResolved = URL(fileURLWithPath: cloudRoot).resolvingSymlinksInPath().path
            guard localResolved == cloudResolved else { continue }
            if relative == cloud { return localRoot }
            return localRoot + String(relative.dropFirst(cloud.count))
        }
        return nil
    }

    private static let icloudMirrors: [(String, String)] = [
        ("Library/Mobile Documents/com~apple~CloudDocs/Desktop", "Desktop"),
        ("Library/Mobile Documents/com~apple~CloudDocs/Documents", "Documents"),
        ("Library/Mobile Documents/com~apple~CloudDocs/Downloads", "Downloads"),
    ]

    private func isUnderAnyRoot(_ path: String, extras: [String]) -> Bool {
        if path == rootPath || path.hasPrefix(rootPath + "/") { return true }
        return extras.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    private func shouldIgnoreWatch(_ path: String, extras: [String]) -> Bool {
        let name = URL(fileURLWithPath: path).lastPathComponent
        if policy.shouldOmitEntry(name: name) { return true }
        for extra in extras {
            if path == extra { return false }
            if path.hasPrefix(extra + "/") {
                let relative = String(path.dropFirst(extra.count + 1))
                return policy.shouldSkipDescending(relative: relative, name: name)
            }
        }
        if path == rootPath { return false }
        if path.hasPrefix(rootPath + "/") {
            let relative = String(path.dropFirst(rootPath.count + 1))
            return policy.shouldSkipDescending(relative: relative, name: name)
        }
        return true
    }

    private func relativeWithoutResolve(_ path: String) -> String {
        if path == rootPath { return "" }
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        return path
    }

    private func collectTree(at path: String) -> [FileEntry] {
        index.addReplacingWalk(root: path, rootPath: rootPath, policy: policy, stop: { self.stopFlag })
    }

    private func knownPath(_ path: String) -> Bool {
        pathAliases(path).contains { index.contains(path: $0) }
    }

    private func missingKnown(under folder: String) -> [String] {
        var missing: [String] = []
        for alias in pathAliases(folder) {
            for known in index.paths(under: alias) where !FileManager.default.fileExists(atPath: known) {
                missing.append(known)
            }
        }
        return missing
    }

    deinit {
        stopEvents()
    }
}
