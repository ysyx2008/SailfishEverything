import Foundation
import EverythingCore

enum ScannerSmokeTests {
    static var cases: [TestCase] {[
        TestCase(name: "冒烟.扫假家目录含云盘", run: scanFixtureFindsCloudAndLocal),
        TestCase(name: "冒烟.边建边搜", run: searchWhileIndexing),
        TestCase(name: "冒烟.大批量仍即时", run: largeIndexStaysInteractive),
    ]}

    private static func scanFixtureFindsCloudAndLocal() throws {
        let root = try FixtureHome.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let index = FileIndex()
        let scanner = FileScanner(
            index: index,
            root: root,
            enableWatch: false,
            notifyOnMain: false
        )
        scanner.scanSynchronously()

        try expect(index.count > 8, "indexed \(index.count)")
        try expectEqual(index.names(matching: "会议纪要"), ["会议纪要.docx"])
        try expectEqual(index.names(matching: "合同"), ["合同.pdf"])
        try expectEqual(index.names(matching: "设计稿"), ["设计稿.psd"])

        let names = index.names(matching: "")
        try expect(!names.contains("should-not-index.txt"))
        try expect(!names.contains("dup-report.pdf"))
        try expect(!names.contains("secret.bin"))
        try expect(!names.contains("index.js"))
        try expect(!names.contains("data"))
        try expect(names.contains("main.swift"))
    }

    private static func searchWhileIndexing() throws {
        let index = FileIndex()
        index.add([FileEntry(name: "early.txt", directory: "/tmp")])
        try expectEqual(index.names(matching: "early"), ["early.txt"])
        index.add([FileEntry(name: "later-early-draft.txt", directory: "/tmp")])
        try expectEqual(index.names(matching: "early").count, 2)
    }

    private static func largeIndexStaysInteractive() throws {
        let index = FileIndex()
        var batch: [FileEntry] = []
        batch.reserveCapacity(50_000)
        for i in 0..<50_000 {
            batch.append(FileEntry(name: String(format: "file-%05d.txt", i), directory: "/pool"))
        }
        batch.append(FileEntry(name: "会议纪要.docx", directory: "/Desktop"))
        index.add(batch)

        let started = DispatchTime.now()
        let names = index.names(matching: "会议纪要")
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        try expectEqual(names, ["会议纪要.docx"])
        try expect(elapsedMs < 200, "search took \(elapsedMs)ms")
    }
}
