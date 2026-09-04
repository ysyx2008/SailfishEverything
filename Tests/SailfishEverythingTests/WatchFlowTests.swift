import Foundation
import SailfishEverythingCore

enum WatchFlowTests {
    static var cases: [TestCase] {[
        TestCase(name: "端到端.磁盘变动后名单跟着变", run: watchAddsAndRemoves),
        TestCase(name: "端到端.搜索后复制普通文件进当前结果", run: copyAppearsInCurrentSearch),
        TestCase(name: "单元.云盘桌面路径按本机那份收录", run: icloudDesktopMapsToLocal),
        TestCase(name: "单元.纳入根里的新文件也能跟上", run: extraRootWatchKeepsFile),
        TestCase(name: "单元.系统说漏了就补扫这一块", run: mustScanSubdirsPicksNestedFile),
        TestCase(name: "单元.家目录可被环境变量改掉", run: runtimeHomeOverride),
    ]}

    private static func watchAddsAndRemoves() throws {
        let root = try FixtureHome.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let index = FileIndex()
        let scanner = FileScanner(index: index, root: root, enableWatch: true, notifyOnMain: false)
        scanner.scanSynchronously()
        try expect(index.names(matching: "live-note").isEmpty)

        let live = root.appendingPathComponent("Desktop/live-note.txt")
        try "hello".data(using: .utf8)!.write(to: live)
        try expect(waitUntil(timeout: 6) {
            index.names(matching: "live-note").contains("live-note.txt")
        }, "new file never appeared in the index")

        try FileManager.default.removeItem(at: live)
        let gone = waitUntil(timeout: 6) {
            index.names(matching: "live-note").isEmpty
        }
        if !gone {
            let leftover = index.names(matching: "live-note")
            throw Expectation.failed("deleted file stayed in the index: \(leftover)", #fileID, #line)
        }
        scanner.stop()
    }

    private static func copyAppearsInCurrentSearch() throws {
        let root = try FixtureHome.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let index = FileIndex()
        let scanner = FileScanner(index: index, root: root, enableWatch: false, notifyOnMain: false)
        scanner.scanSynchronously()
        try expect(index.names(matching: "copied-report").isEmpty)
        try expect(index.search(query: "copied-report").isEmpty)

        let copy = root.appendingPathComponent("Documents/copied-report.pdf")
        try "body".data(using: .utf8)!.write(to: copy)
        scanner.ingestWatchPaths([copy.path])

        try expect(index.names(matching: "copied-report").contains("copied-report.pdf"))
        try expect(!index.search(query: "copied-report").isEmpty)

        try FileManager.default.removeItem(at: copy)
        scanner.ingestWatchPaths([copy.path])
        try expect(index.names(matching: "copied-report").isEmpty)
        scanner.stop()
    }

    private static func icloudDesktopMapsToLocal() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("everything-icloud-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let cloudDesktop = root.appendingPathComponent(
            "Library/Mobile Documents/com~apple~CloudDocs/Desktop",
            isDirectory: true
        )
        try fm.createDirectory(at: cloudDesktop, withIntermediateDirectories: true)
        let localDesktop = root.appendingPathComponent("Desktop", isDirectory: false)
        try fm.createSymbolicLink(at: localDesktop, withDestinationURL: cloudDesktop)
        try "seed".data(using: .utf8)!.write(to: cloudDesktop.appendingPathComponent("seed.txt"))

        let index = FileIndex()
        let scanner = FileScanner(index: index, root: root, enableWatch: false, notifyOnMain: false)
        scanner.scanSynchronously()

        let cloudFile = cloudDesktop.appendingPathComponent("icloud-copy.txt")
        try "hello".data(using: .utf8)!.write(to: cloudFile)
        scanner.ingestWatchPaths([cloudFile.path])

        try expect(index.names(matching: "icloud-copy").contains("icloud-copy.txt"))
        let hits = index.search(query: "icloud-copy")
        try expectEqual(hits.count, 1)
        if let first = hits.first, let entry = index.entry(at: first) {
            try expect(entry.path.contains("/Desktop/icloud-copy.txt"))
            try expect(!entry.path.contains("Mobile Documents"))
        }
        scanner.stop()
    }

    private static func extraRootWatchKeepsFile() throws {
        let root = try FixtureHome.make()
        defer { try? FileManager.default.removeItem(at: root) }
        try FixtureHome.addWeChatChatFiles(root)
        let index = FileIndex()
        let scanner = FileScanner(index: index, root: root, enableWatch: false, notifyOnMain: false)
        scanner.scanSynchronously()
        try expect(index.names(matching: "周报").isEmpty)

        let fresh = root.appendingPathComponent(
            "Library/Containers/com.tencent.xinWeChat/Data/Documents/xwechat_files/acct1/msg/file/2024-09/周报.docx"
        )
        try FileManager.default.createDirectory(at: fresh.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "wx".data(using: .utf8)!.write(to: fresh)
        scanner.ingestWatchPaths([fresh.path])

        try expect(index.names(matching: "周报").contains("周报.docx"))
        scanner.stop()
    }

    private static func mustScanSubdirsPicksNestedFile() throws {
        let root = try FixtureHome.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let index = FileIndex()
        let scanner = FileScanner(index: index, root: root, enableWatch: false, notifyOnMain: false)
        scanner.scanSynchronously()

        let nested = root.appendingPathComponent("Desktop/Archive/nested/deep-copy.txt")
        try FileManager.default.createDirectory(at: nested.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "deep".data(using: .utf8)!.write(to: nested)
        try expect(index.names(matching: "deep-copy").isEmpty)

        scanner.ingestWatchPaths(
            [root.appendingPathComponent("Desktop/Archive").path],
            mustScanSubdirs: true
        )
        try expect(index.names(matching: "deep-copy").contains("deep-copy.txt"))
        scanner.stop()
    }

    private static func runtimeHomeOverride() throws {
        let url = RuntimeHome.url(environment: ["SAILFISH_HOME": "/tmp/sailfish-e2e-home"])
        try expect(url.path.contains("sailfish-e2e-home"))
        let fallback = RuntimeHome.url(environment: [:])
        try expect(fallback.path == URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path)
    }

    private static func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            Thread.sleep(forTimeInterval: 0.05)
        }
        return condition()
    }
}
