import Darwin
import Foundation
import SailfishEverythingCore

enum ScannerSmokeTests {
    static var cases: [TestCase] {[
        TestCase(name: "冒烟.扫假家目录默认不含云盘", run: scanFixtureSkipsCloudKeepsLocal),
        TestCase(name: "冒烟.边建边搜", run: searchWhileIndexing),
        TestCase(name: "冒烟.大批量仍即时", run: largeIndexStaysInteractive),
        TestCase(name: "冒烟.边敲和清空都要快", run: typingAndClearStayFast),
        TestCase(name: "冒烟.增删后空查询缓存失效", run: emptyCacheInvalidates),
        TestCase(name: "冒烟.索引不取大小日期", run: scanSkipsSizeAndDate),
        TestCase(name: "冒烟.同路径更新而不是跳过", run: replaceUpdatesEntry),
        TestCase(name: "冒烟.二十万条中文首字也要快", run: hugeCJKFirstKeystroke),
        TestCase(name: "冒烟.三十万条清空后再敲也要快", run: emptyThenType300k),
        TestCase(name: "冒烟.关键字在文件名中间也能中", run: containsInMiddle),
        TestCase(name: "冒烟.两个词同时满足也要快", run: andTwoWordsFast),
        TestCase(name: "冒烟.相邻文件名不会串匹配", run: noCrossNameMatch),
        TestCase(name: "冒烟.扫两万个文件也要快", run: scanTwentyThousand),
        TestCase(name: "冒烟.扫盘中途也能搜", run: searchDuringBulkLoad),
    ]}

    private static func scanFixtureSkipsCloudKeepsLocal() throws {
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
        try expect(Set(index.names(matching: "会议纪要")).isSuperset(of: ["会议纪要.docx", "Q3 会议纪要.docx"]))
        try expectEqual(index.names(matching: "合同"), ["合同.pdf"])
        try expect(index.names(matching: "设计稿").isEmpty)
        try expect(index.names(matching: "path:OneDrive").isEmpty)

        let names = index.names(matching: "")
        try expect(!names.contains("should-not-index.txt"))
        try expect(!names.contains("dup-report.pdf"))
        try expect(!names.contains("secret.bin"))
        try expect(!names.contains("index.js"))
        try expect(!names.contains("data"))
        try expect(!names.contains("weights.bin"))
        try expect(!names.contains("config"))
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
        try expect(elapsedMs < 20, "search took \(elapsedMs)ms")
    }

    private static func typingAndClearStayFast() throws {
        let index = FileIndex()
        var batch: [FileEntry] = []
        batch.reserveCapacity(80_000)
        for i in 0..<80_000 {
            batch.append(FileEntry(name: String(format: "item-%05d.txt", i), directory: "/pool", size: 10))
        }
        batch.append(FileEntry(name: "会议纪要.docx", directory: "/Desktop", size: 20_000))
        index.add(batch)

        _ = index.search(query: "")
        let emptyStart = DispatchTime.now()
        let empty = index.search(query: "")
        let emptyMs = Double(DispatchTime.now().uptimeNanoseconds - emptyStart.uptimeNanoseconds) / 1_000_000
        try expectEqual(empty.count, 80_001)
        try expect(emptyMs < 8, "cached empty search took \(emptyMs)ms")

        let firstKey = DispatchTime.now()
        let first = index.names(matching: "会议纪要")
        let firstMs = Double(DispatchTime.now().uptimeNanoseconds - firstKey.uptimeNanoseconds) / 1_000_000
        try expectEqual(first, ["会议纪要.docx"])
        try expect(firstMs < 15, "first keyword after empty took \(firstMs)ms")

        var previous: SearchCursor?
        let typeStart = DispatchTime.now()
        for query in ["会", "会议", "会议纪"] {
            let indices = index.search(query: query, previous: previous)
            previous = SearchCursor(query: query, indices: indices)
        }
        let typeMs = Double(DispatchTime.now().uptimeNanoseconds - typeStart.uptimeNanoseconds) / 1_000_000
        try expectEqual(index.entries(at: previous!.indices).map(\.name), ["会议纪要.docx"])
        try expect(typeMs < 80, "typed search took \(typeMs)ms")

        let clearStart = DispatchTime.now()
        let cleared = index.search(query: "", previous: previous)
        let clearMs = Double(DispatchTime.now().uptimeNanoseconds - clearStart.uptimeNanoseconds) / 1_000_000
        try expectEqual(cleared.count, 80_001)
        try expect(clearMs < 8, "clear search took \(clearMs)ms")
        try expectEqual(index.totalBytes, 80_000 * 10 + 20_000)
    }

    private static func emptyCacheInvalidates() throws {
        let index = FileIndex()
        index.add([FileEntry(name: "a.txt", directory: "/a", size: 4)])
        try expectEqual(index.names(matching: ""), ["a.txt"])
        index.add([FileEntry(name: "b.txt", directory: "/a", size: 8)])
        try expectEqual(index.names(matching: ""), ["a.txt", "b.txt"])
        try expectEqual(index.totalBytes, 12)
        index.remove(paths: ["/a/a.txt"])
        try expectEqual(index.names(matching: ""), ["b.txt"])
        try expectEqual(index.totalBytes, 8)
    }

    private static func scanSkipsSizeAndDate() throws {
        FileMetadata.reset()
        let root = try FixtureHome.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let index = FileIndex()
        FileScanner(index: index, root: root, enableWatch: false, notifyOnMain: false).scanSynchronously()
        let photo = index.entries(at: index.search(query: "photo.jpg")).first
        try expect(photo != nil)
        try expect(photo?.size == nil)
        try expect(photo?.modified == nil)
        try expectEqual(FileMetadata.cachedCount, 0)
        try expectEqual(index.names(matching: "size:>1mb"), ["big.bin"])
        try expect(FileMetadata.size(of: photo!) != nil)
        try expectEqual(index.names(matching: "ext:dat size:<1kb"), ["tiny.dat"])
    }

    private static func replaceUpdatesEntry() throws {
        let index = FileIndex()
        index.add([FileEntry(name: "合同.pdf", directory: "/cloud", isCloudOnly: true)])
        try expect(index.entries(at: index.search(query: "合同")).first?.isCloudOnly == true)
        index.add([FileEntry(name: "合同.pdf", directory: "/cloud", isCloudOnly: false)])
        try expect(index.entries(at: index.search(query: "合同")).first?.isCloudOnly == true)
        index.add([FileEntry(name: "合同.pdf", directory: "/cloud", isCloudOnly: false)], replace: true)
        try expect(index.entries(at: index.search(query: "合同")).first?.isCloudOnly == false)
        try expectEqual(index.count, 1)
    }

    private static func hugeCJKFirstKeystroke() throws {
        let index = FileIndex()
        var batch: [FileEntry] = []
        batch.reserveCapacity(200_001)
        for i in 0..<200_000 {
            batch.append(FileEntry(name: String(format: "item-%06d.txt", i), directory: "/pool"))
        }
        batch.append(FileEntry(name: "会议纪要.docx", directory: "/Desktop"))
        index.add(batch)

        let first = DispatchTime.now()
        let one = index.names(matching: "会")
        let firstMs = Double(DispatchTime.now().uptimeNanoseconds - first.uptimeNanoseconds) / 1_000_000
        try expectEqual(one, ["会议纪要.docx"])
        try expect(firstMs < 20, "first CJK keystroke took \(firstMs)ms")

        var previous = SearchCursor(query: "会", indices: index.search(query: "会"))
        let typed = DispatchTime.now()
        for query in ["会议", "会议纪"] {
            let indices = index.search(query: query, previous: previous)
            previous = SearchCursor(query: query, indices: indices)
        }
        let typedMs = Double(DispatchTime.now().uptimeNanoseconds - typed.uptimeNanoseconds) / 1_000_000
        try expectEqual(index.entries(at: previous.indices).map(\.name), ["会议纪要.docx"])
        try expect(typedMs < 15, "typed CJK took \(typedMs)ms")
    }

    private static func emptyThenType300k() throws {
        let index = FileIndex()
        var batch: [FileEntry] = []
        batch.reserveCapacity(300_001)
        for i in 0..<300_000 {
            batch.append(FileEntry(name: String(format: "item-%06d.txt", i), directory: "/pool"))
        }
        batch.append(FileEntry(name: "会议纪要.docx", directory: "/Desktop"))
        index.add(batch)

        let empty = index.search(query: "")
        try expectEqual(empty.count, 300_001)

        let first = DispatchTime.now()
        let hits = index.search(query: "会议纪要", previous: SearchCursor(query: "", indices: empty))
        let firstMs = Double(DispatchTime.now().uptimeNanoseconds - first.uptimeNanoseconds) / 1_000_000
        try expectEqual(index.entries(at: hits).map(\.name), ["会议纪要.docx"])
        try expect(firstMs < 15, "empty then type took \(firstMs)ms")

        let common = DispatchTime.now()
        let many = index.search(query: "item", previous: SearchCursor(query: "", indices: empty))
        let commonMs = Double(DispatchTime.now().uptimeNanoseconds - common.uptimeNanoseconds) / 1_000_000
        try expect(many.count >= 300_000)
        try expect(commonMs < 20, "common first keyword took \(commonMs)ms")
    }

    private static func containsInMiddle() throws {
        let index = FileIndex()
        index.add([
            FileEntry(name: "early.txt", directory: "/tmp"),
            FileEntry(name: "later-early-draft.txt", directory: "/tmp"),
            FileEntry(name: "Q3 会议纪要.docx", directory: "/Desktop"),
        ])
        try expectEqual(Set(index.names(matching: "early")), Set(["early.txt", "later-early-draft.txt"]))
        try expectEqual(index.names(matching: "会议纪要"), ["Q3 会议纪要.docx"])
    }

    private static func andTwoWordsFast() throws {
        let index = FileIndex()
        var batch: [FileEntry] = []
        batch.reserveCapacity(80_002)
        for i in 0..<80_000 {
            batch.append(FileEntry(name: String(format: "item-%05d.txt", i), directory: "/pool"))
        }
        batch.append(FileEntry(name: "Q3 会议纪要.docx", directory: "/Desktop"))
        batch.append(FileEntry(name: "会议安排.pdf", directory: "/Documents"))
        index.add(batch)

        let started = DispatchTime.now()
        let names = Set(index.names(matching: "会议 纪要"))
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        try expectEqual(names, Set(["Q3 会议纪要.docx"]))
        try expect(elapsedMs < 20, "AND search took \(elapsedMs)ms")

        let orNames = Set(index.names(matching: "纪要 | 安排"))
        try expectEqual(orNames, Set(["Q3 会议纪要.docx", "会议安排.pdf"]))
    }

    private static func noCrossNameMatch() throws {
        let index = FileIndex()
        index.add([
            FileEntry(name: "ab", directory: "/a"),
            FileEntry(name: "cd", directory: "/a"),
        ])
        try expect(index.names(matching: "bc").isEmpty)
        try expectEqual(Set(index.names(matching: "ab")), Set(["ab"]))
    }

    private static func scanTwentyThousand() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sailfish-scan-20k-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        for folder in ["a", "b", "c", "d"] {
            let dir = root.appendingPathComponent(folder)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for i in 0..<5_000 {
                let path = dir.appendingPathComponent("f-\(i).txt").path
                _ = Darwin.close(Darwin.open(path, O_CREAT | O_WRONLY, 0o644))
            }
        }

        let index = FileIndex()
        let started = DispatchTime.now()
        FileScanner(index: index, root: root, enableWatch: false, notifyOnMain: false).scanSynchronously()
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        try expect(index.count >= 20_000, "indexed \(index.count)")
        try expect(!index.names(matching: "f-42").isEmpty)
        try expect(elapsedMs < 400, "scan 20k took \(elapsedMs)ms")
    }

    private static func searchDuringBulkLoad() throws {
        let index = FileIndex()
        index.beginBulkLoad()
        index.add([FileEntry(name: "early.txt", directory: "/tmp")])
        try expectEqual(index.names(matching: "early"), ["early.txt"])
        try expectEqual(index.search(query: "").count, 1)
        index.add([FileEntry(name: "later-early-draft.txt", directory: "/tmp")])
        try expectEqual(index.names(matching: "early").count, 2)
        index.endBulkLoad()
        try expectEqual(index.names(matching: "early").count, 2)
        try expectEqual(index.search(query: "").count, 2)
    }
}
