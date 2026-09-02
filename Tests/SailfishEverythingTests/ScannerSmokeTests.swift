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
        TestCase(name: "冒烟.扫盘记住体积不另问盘", run: scanKeepsSizeSkipsDate),
        TestCase(name: "冒烟.同路径更新而不是跳过", run: replaceUpdatesEntry),
        TestCase(name: "冒烟.二十万条中文首字也要快", run: hugeCJKFirstKeystroke),
        TestCase(name: "冒烟.三十万条清空后再敲也要快", run: emptyThenType300k),
        TestCase(name: "冒烟.关键字在文件名中间也能中", run: containsInMiddle),
        TestCase(name: "冒烟.两个词同时满足也要快", run: andTwoWordsFast),
        TestCase(name: "冒烟.相邻文件名不会串匹配", run: noCrossNameMatch),
        TestCase(name: "冒烟.扫两万个文件也要快", run: scanTwentyThousand),
        TestCase(name: "冒烟.很多文件夹一起扫也要快", run: scanWideTree),
        TestCase(name: "冒烟.扫盘中途也能搜", run: searchDuringBulkLoad),
        TestCase(name: "冒烟.按路径搜大批量也要快", run: matchPathLargeIndex),
        TestCase(name: "冒烟.三十万条按路径首字也要快", run: matchPath300k),
        TestCase(name: "冒烟.大批量两个词或者也要快", run: orTwoWordsLargeIndex),
        TestCase(name: "冒烟.开头结尾精确大批量也要快", run: affixLargeIndex),
        TestCase(name: "冒烟.扩展名和只要文件也要快", run: extAndFileLargeIndex),
        TestCase(name: "冒烟.限定文件夹和通配符也要快", run: folderAndWildcardLargeIndex),
        TestCase(name: "冒烟.上级文件夹和排除词也要快", run: parentAndNotLargeIndex),
        TestCase(name: "冒烟.整词匹配大批量也要快", run: wholeWordLargeIndex),
        TestCase(name: "冒烟.问号通配和文件名长度也要快", run: questionAndLenLargeIndex),
        TestCase(name: "冒烟.先按名字再看体积也要快", run: sizeAfterTextLargeIndex),
        TestCase(name: "冒烟.星号加问号大批量也要快", run: globLargeIndex),
        TestCase(name: "冒烟.扫出来的路径能打开", run: scannedPathJoinsAndExists),
        TestCase(name: "冒烟.真实家目录扫盘与首字", run: realHomeScanIfEnabled),
        TestCase(name: "冒烟.收尾建路径表时也能搜", run: searchWhileBuildingPathIndex),
        TestCase(name: "冒烟.大批量路径更新也要快", run: pathIndexLargeReplace),
        TestCase(name: "冒烟.区分大小写大批量也要快", run: matchCaseLargeIndex),
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
        let hit = index.entries(at: index.search(query: "会议纪要")).first
        try expectEqual(hit?.name, "会议纪要.docx")
        try expectEqual(hit?.directory, "/Desktop")
        try expectEqual(hit?.path, "/Desktop/会议纪要.docx")
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

    private static func scanKeepsSizeSkipsDate() throws {
        FileMetadata.reset()
        let root = try FixtureHome.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let index = FileIndex()
        FileScanner(index: index, root: root, enableWatch: false, notifyOnMain: false).scanSynchronously()
        let photo = index.entries(at: index.search(query: "photo.jpg")).first
        try expect(photo != nil)
        try expectEqual(photo?.size, 1)
        try expect(photo?.modified != nil, "scan should remember modified time")
        try expect(photo?.created != nil, "scan should remember created time")
        try expectEqual(FileMetadata.cachedCount, 0)
        let big = index.entries(at: index.search(query: "big.bin")).first
        try expectEqual(big?.size, 1_500_000)
        try expect(index.totalBytes >= 1_500_000, "scanned bytes \(index.totalBytes)")
        try expectEqual(index.totalBytes(at: index.search(query: "big.bin")), 1_500_000)

        let sizeStart = DispatchTime.now()
        try expectEqual(index.names(matching: "size:>1mb"), ["big.bin"])
        let sizeMs = Double(DispatchTime.now().uptimeNanoseconds - sizeStart.uptimeNanoseconds) / 1_000_000
        bench("scanned size: only", sizeMs)
        try expectEqual(FileMetadata.cachedCount, 0)
        try expect(sizeMs < 20, "size-only after scan took \(sizeMs)ms")

        try expectEqual(index.names(matching: "ext:dat size:<1kb"), ["tiny.dat"])
        try expectEqual(FileMetadata.cachedCount, 0)
        try expect(index.names(matching: "dm:today").contains("photo.jpg"))
        try expectEqual(FileMetadata.cachedCount, 0)
        let bySize = index.names(matching: "", sort: SortState(column: .size, ascending: false))
        try expectEqual(bySize.first, "big.bin")
        try expectEqual(FileMetadata.cachedCount, 0)
        let narrowed = index.names(matching: "会议纪要 size:>0")
        try expect(Set(narrowed).isSuperset(of: ["会议纪要.docx", "Q3 会议纪要.docx"]))
        try expectEqual(FileMetadata.cachedCount, 0)
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
        let one = index.search(query: "会")
        let firstMs = Double(DispatchTime.now().uptimeNanoseconds - first.uptimeNanoseconds) / 1_000_000
        try expectEqual(index.entries(at: one).map(\.name), ["会议纪要.docx"])
        bench("CJK first keystroke", firstMs)
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
        bench("empty then type 300k", firstMs)
        try expect(firstMs < 15, "empty then type took \(firstMs)ms")

        let common = DispatchTime.now()
        let many = index.search(query: "item", previous: SearchCursor(query: "", indices: empty))
        let commonMs = Double(DispatchTime.now().uptimeNanoseconds - common.uptimeNanoseconds) / 1_000_000
        try expect(many.count >= 300_000)
        bench("common first keyword 300k", commonMs)
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
        bench("scan 20k files", elapsedMs)
        try expect(elapsedMs < 400, "scan 20k took \(elapsedMs)ms")
    }

    private static func scanWideTree() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sailfish-scan-wide-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        for folder in 0..<64 {
            let dir = root.appendingPathComponent(String(format: "d-%02d", folder))
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for i in 0..<500 {
                let path = dir.appendingPathComponent("f-\(i).txt").path
                _ = Darwin.close(Darwin.open(path, O_CREAT | O_WRONLY, 0o644))
            }
        }

        let index = FileIndex()
        let started = DispatchTime.now()
        FileScanner(index: index, root: root, enableWatch: false, notifyOnMain: false).scanSynchronously()
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        try expect(index.count >= 32_000, "indexed \(index.count)")
        try expectEqual(index.names(matching: "exact:f-42.txt").count, 64)
        bench("scan wide 32k", elapsedMs)
        try expect(elapsedMs < 500, "wide scan took \(elapsedMs)ms")
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

    private static func matchPathLargeIndex() throws {
        let index = FileIndex()
        var batch: [FileEntry] = []
        batch.reserveCapacity(80_001)
        for i in 0..<80_000 {
            batch.append(FileEntry(name: String(format: "item-%05d.txt", i), directory: "/pool"))
        }
        batch.append(FileEntry(name: "photo.jpg", directory: "/Desktop/Q3会议"))
        index.add(batch)

        var options = SearchOptions()
        options.matchPath = true
        let started = DispatchTime.now()
        let hits = index.search(query: "Q3会议", options: options)
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        try expectEqual(index.entries(at: hits).map(\.name), ["photo.jpg"])
        try expect(elapsedMs < 20, "path search took \(elapsedMs)ms")
        try expect(index.names(matching: "Q3会议").isEmpty)
    }

    private static func matchPath300k() throws {
        let index = FileIndex()
        var batch: [FileEntry] = []
        batch.reserveCapacity(300_001)
        for i in 0..<300_000 {
            batch.append(FileEntry(name: String(format: "item-%06d.txt", i), directory: "/pool"))
        }
        batch.append(FileEntry(name: "photo.jpg", directory: "/Desktop/会议纪要箱"))
        index.add(batch)

        var options = SearchOptions()
        options.matchPath = true
        let started = DispatchTime.now()
        let hits = index.search(query: "会议纪要箱", options: options)
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        try expectEqual(index.entries(at: hits).map(\.name), ["photo.jpg"])
        bench("match path 300k", elapsedMs)
        try expect(elapsedMs < 20, "match path 300k took \(elapsedMs)ms")
        try expect(index.search(query: "会议纪要箱").isEmpty)
    }

    private static func orTwoWordsLargeIndex() throws {
        let index = FileIndex()
        var batch: [FileEntry] = []
        batch.reserveCapacity(80_002)
        for i in 0..<80_000 {
            batch.append(FileEntry(name: String(format: "item-%05d.txt", i), directory: "/pool"))
        }
        batch.append(FileEntry(name: "会议纪要.docx", directory: "/Desktop"))
        batch.append(FileEntry(name: "notes.txt", directory: "/Desktop"))
        index.add(batch)

        let started = DispatchTime.now()
        let hits = index.search(query: "item | 会议")
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        try expect(hits.count >= 80_001, "OR hit \(hits.count)")
        bench("OR two words 80k", elapsedMs)
        try expect(elapsedMs < 30, "OR search took \(elapsedMs)ms")
        try expectEqual(index.search(query: "notes | 会议").count, 2)
    }

    private static func affixLargeIndex() throws {
        let index = FileIndex()
        var batch: [FileEntry] = []
        batch.reserveCapacity(80_002)
        for i in 0..<80_000 {
            batch.append(FileEntry(name: String(format: "item-%05d.txt", i), directory: "/pool"))
        }
        batch.append(FileEntry(name: "会议纪要.docx", directory: "/Desktop"))
        batch.append(FileEntry(name: "photo.jpg", directory: "/Downloads"))
        index.add(batch)

        let prefixStart = DispatchTime.now()
        let prefixed = Set(index.names(matching: "startwith:会议"))
        let prefixMs = Double(DispatchTime.now().uptimeNanoseconds - prefixStart.uptimeNanoseconds) / 1_000_000
        try expectEqual(prefixed, Set(["会议纪要.docx"]))
        try expect(prefixMs < 20, "startwith took \(prefixMs)ms")

        let suffixStart = DispatchTime.now()
        let suffixed = index.names(matching: "endwith:.jpg")
        let suffixMs = Double(DispatchTime.now().uptimeNanoseconds - suffixStart.uptimeNanoseconds) / 1_000_000
        try expectEqual(suffixed, ["photo.jpg"])
        try expect(suffixMs < 25, "endwith took \(suffixMs)ms")

        try expectEqual(index.names(matching: "exact:photo.jpg"), ["photo.jpg"])
        try expect(index.names(matching: "exact:photo").isEmpty)
        try expect(index.names(matching: "startwith:item").count >= 80_000)
    }

    private static func extAndFileLargeIndex() throws {
        let index = FileIndex()
        var batch: [FileEntry] = []
        batch.reserveCapacity(80_004)
        for i in 0..<80_000 {
            batch.append(FileEntry(name: String(format: "item-%05d.txt", i), directory: "/pool"))
        }
        batch.append(FileEntry(name: "photo.jpg", directory: "/Downloads"))
        batch.append(FileEntry(name: "clip.mp4", directory: "/Movies"))
        batch.append(FileEntry(name: "Notes", directory: "/Desktop", isDirectory: true))
        batch.append(FileEntry(name: "会议纪要.docx", directory: "/Desktop"))
        index.add(batch)

        let extStart = DispatchTime.now()
        let pictureHits = index.search(query: "ext:jpg;mp4")
        let extMs = Double(DispatchTime.now().uptimeNanoseconds - extStart.uptimeNanoseconds) / 1_000_000
        try expectEqual(Set(index.entries(at: pictureHits).map(\.name)), Set(["photo.jpg", "clip.mp4"]))
        try expect(extMs < 40, "ext search took \(extMs)ms")

        let fileStart = DispatchTime.now()
        let files = Set(index.names(matching: "file: 会议"))
        let fileMs = Double(DispatchTime.now().uptimeNanoseconds - fileStart.uptimeNanoseconds) / 1_000_000
        try expectEqual(files, Set(["会议纪要.docx"]))
        try expect(fileMs < 20, "file search took \(fileMs)ms")

        try expectEqual(index.names(matching: "folder: Notes"), ["Notes"])
        let pics = index.names(matching: "", filter: .picture)
        try expectEqual(pics, ["photo.jpg"])
        try expect(!index.names(matching: "folder:").contains("photo.jpg"))
    }

    private static func folderAndWildcardLargeIndex() throws {
        let index = FileIndex()
        var batch: [FileEntry] = []
        batch.reserveCapacity(80_003)
        for i in 0..<80_000 {
            batch.append(FileEntry(name: String(format: "item-%05d.txt", i), directory: "/pool"))
        }
        batch.append(FileEntry(name: "会议纪要.docx", directory: "/Desktop"))
        batch.append(FileEntry(name: "Q3 会议纪要.docx", directory: "/Desktop/Archive"))
        batch.append(FileEntry(name: "notes.txt", directory: "/Documents"))
        index.add(batch)

        var inDesktop = SearchOptions()
        inDesktop.inFolder = "/Desktop"
        let folderStart = DispatchTime.now()
        let scoped = Set(index.names(matching: "会议", options: inDesktop))
        let folderMs = Double(DispatchTime.now().uptimeNanoseconds - folderStart.uptimeNanoseconds) / 1_000_000
        try expectEqual(scoped, Set(["会议纪要.docx", "Q3 会议纪要.docx"]))
        try expect(folderMs < 40, "inFolder search took \(folderMs)ms")

        let wildStart = DispatchTime.now()
        let wild = index.search(query: "item-00042*")
        let wildMs = Double(DispatchTime.now().uptimeNanoseconds - wildStart.uptimeNanoseconds) / 1_000_000
        try expectEqual(index.entries(at: wild).map(\.name), ["item-00042.txt"])
        try expect(wildMs < 25, "wildcard search took \(wildMs)ms")

        try expectEqual(Set(index.names(matching: "*.docx")), Set(["会议纪要.docx", "Q3 会议纪要.docx"]))
        try expect(index.names(matching: "path:Documents").contains("notes.txt"))
        try expectEqual(index.names(matching: "name:notes"), ["notes.txt"])
    }

    private static func parentAndNotLargeIndex() throws {
        let index = FileIndex()
        var batch: [FileEntry] = []
        batch.reserveCapacity(80_003)
        for i in 0..<80_000 {
            batch.append(FileEntry(name: String(format: "item-%05d.txt", i), directory: "/pool"))
        }
        batch.append(FileEntry(name: "会议纪要.docx", directory: "/Desktop"))
        batch.append(FileEntry(name: "会议安排.pdf", directory: "/Documents"))
        batch.append(FileEntry(name: "notes.txt", directory: "/Desktop"))
        index.add(batch)

        let parentStart = DispatchTime.now()
        let parented = Set(index.names(matching: "parent:Desktop"))
        let parentMs = Double(DispatchTime.now().uptimeNanoseconds - parentStart.uptimeNanoseconds) / 1_000_000
        try expectEqual(parented, Set(["会议纪要.docx", "notes.txt"]))
        try expect(parentMs < 40, "parent search took \(parentMs)ms")
        let parentGlobStart = DispatchTime.now()
        let parentGlob = Set(index.names(matching: "parent:Desk*"))
        let parentGlobMs = Double(DispatchTime.now().uptimeNanoseconds - parentGlobStart.uptimeNanoseconds) / 1_000_000
        try expectEqual(parentGlob, Set(["会议纪要.docx", "notes.txt"]))
        bench("parent glob 80k", parentGlobMs)
        try expect(parentGlobMs < 40, "parent glob took \(parentGlobMs)ms")

        var regexOpt = SearchOptions()
        regexOpt.regex = true
        let regexOptStart = DispatchTime.now()
        let regexed = index.names(matching: "item-00042\\.txt", options: regexOpt)
        let regexOptMs = Double(DispatchTime.now().uptimeNanoseconds - regexOptStart.uptimeNanoseconds) / 1_000_000
        try expectEqual(regexed, ["item-00042.txt"])
        bench("regex option 80k", regexOptMs)
        try expect(regexOptMs < 20, "regex option took \(regexOptMs)ms")
        try expectEqual(
            Set(index.names(matching: "会议.+", options: regexOpt)),
            Set(["会议纪要.docx", "会议安排.pdf"])
        )

        let complexStart = DispatchTime.now()
        let digits = index.search(query: "regex:item-\\d{5}")
        let complexMs = Double(DispatchTime.now().uptimeNanoseconds - complexStart.uptimeNanoseconds) / 1_000_000
        try expect(digits.count >= 80_000, "digit regex hit \(digits.count)")
        bench("complex regex 80k", complexMs)
        try expect(complexMs < 80, "complex regex took \(complexMs)ms")
        try expectEqual(
            Set(index.search(query: "regex:会议.+").compactMap { index.entry(at: $0)?.name }),
            Set(["会议纪要.docx", "会议安排.pdf"])
        )

        let notStart = DispatchTime.now()
        let remaining = Set(index.names(matching: "会议 !pdf"))
        let notMs = Double(DispatchTime.now().uptimeNanoseconds - notStart.uptimeNanoseconds) / 1_000_000
        try expectEqual(remaining, Set(["会议纪要.docx"]))
        try expect(notMs < 25, "NOT search took \(notMs)ms")
    }

    private static func wholeWordLargeIndex() throws {
        let index = FileIndex()
        var batch: [FileEntry] = []
        batch.reserveCapacity(80_004)
        for i in 0..<80_000 {
            batch.append(FileEntry(name: String(format: "item-%05d.txt", i), directory: "/pool"))
        }
        batch.append(FileEntry(name: "doc", directory: "/a"))
        batch.append(FileEntry(name: "document.pdf", directory: "/a"))
        batch.append(FileEntry(name: "my-doc-v2.txt", directory: "/a"))
        batch.append(FileEntry(name: "会议纪要.docx", directory: "/Desktop"))
        index.add(batch)

        var whole = SearchOptions()
        whole.matchWholeWord = true
        let started = DispatchTime.now()
        let names = Set(index.names(matching: "doc", options: whole))
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        try expectEqual(names, Set(["doc", "my-doc-v2.txt"]))
        bench("whole word 80k", elapsedMs)
        try expect(elapsedMs < 25, "whole word search took \(elapsedMs)ms")
        try expect(index.names(matching: "会议", options: whole).isEmpty)
        try expectEqual(index.names(matching: "会议纪要", options: whole), ["会议纪要.docx"])
    }

    private static func questionAndLenLargeIndex() throws {
        let index = FileIndex()
        var batch: [FileEntry] = []
        batch.reserveCapacity(80_003)
        for i in 0..<80_000 {
            batch.append(FileEntry(name: String(format: "item-%05d.txt", i), directory: "/pool"))
        }
        batch.append(FileEntry(name: "report.pdf", directory: "/Documents"))
        batch.append(FileEntry(name: "会议纪要.docx", directory: "/Desktop"))
        batch.append(FileEntry(name: "photo.jpg", directory: "/Downloads"))
        index.add(batch)

        let questionStart = DispatchTime.now()
        let questioned = index.names(matching: "item-00042.???")
        let questionMs = Double(DispatchTime.now().uptimeNanoseconds - questionStart.uptimeNanoseconds) / 1_000_000
        try expectEqual(questioned, ["item-00042.txt"])
        bench("question wildcard 80k", questionMs)
        try expect(questionMs < 25, "question wildcard took \(questionMs)ms")
        try expectEqual(index.names(matching: "report.???"), ["report.pdf"])
        try expectEqual(index.names(matching: "?????.???"), ["photo.jpg"])

        let lenStart = DispatchTime.now()
        let fourteen = index.search(query: "len:14")
        let lenMs = Double(DispatchTime.now().uptimeNanoseconds - lenStart.uptimeNanoseconds) / 1_000_000
        try expect(fourteen.count >= 80_000, "len:14 hit \(fourteen.count)")
        bench("len: 80k", lenMs)
        try expect(lenMs < 20, "len search took \(lenMs)ms")
        try expectEqual(Set(index.names(matching: "len:9")), Set(["会议纪要.docx", "photo.jpg"]))
    }

    private static func sizeAfterTextLargeIndex() throws {
        let index = FileIndex()
        var batch: [FileEntry] = []
        batch.reserveCapacity(80_003)
        for i in 0..<80_000 {
            batch.append(FileEntry(name: String(format: "item-%05d.txt", i), directory: "/pool", size: 10))
        }
        batch.append(FileEntry(name: "会议纪要.docx", directory: "/Desktop", size: 20_000))
        batch.append(FileEntry(name: "tiny.dat", directory: "/a", size: 4))
        batch.append(FileEntry(name: "big.bin", directory: "/Downloads", size: 2_000_000))
        index.add(batch)

        FileMetadata.reset()
        let started = DispatchTime.now()
        let hits = index.search(query: "会议 size:>1kb")
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        try expectEqual(index.entries(at: hits).map(\.name), ["会议纪要.docx"])
        try expectEqual(FileMetadata.cachedCount, 0)
        bench("text then size 80k", elapsedMs)
        try expect(elapsedMs < 15, "text+size search took \(elapsedMs)ms")

        try expectEqual(index.names(matching: "会议 !size:>1mb"), ["会议纪要.docx"])
        try expectEqual(index.names(matching: "tiny empty:"), [])
        try expectEqual(index.names(matching: "size:>1mb"), ["big.bin"])

        let wideStart = DispatchTime.now()
        let wide = index.search(query: "item size:>0")
        let wideMs = Double(DispatchTime.now().uptimeNanoseconds - wideStart.uptimeNanoseconds) / 1_000_000
        try expect(wide.count >= 80_000, "item size hit \(wide.count)")
        bench("common name then size 80k", wideMs)
        try expect(wideMs < 50, "common text+size took \(wideMs)ms")
        try expectEqual(FileMetadata.cachedCount, 0)
    }

    private static func globLargeIndex() throws {
        let index = FileIndex()
        var batch: [FileEntry] = []
        batch.reserveCapacity(80_003)
        for i in 0..<80_000 {
            batch.append(FileEntry(name: String(format: "item-%05d.txt", i), directory: "/pool"))
        }
        batch.append(FileEntry(name: "report.pdf", directory: "/Documents"))
        batch.append(FileEntry(name: "会议纪要.docx", directory: "/Desktop"))
        batch.append(FileEntry(name: "photo.jpg", directory: "/Downloads"))
        index.add(batch)

        let started = DispatchTime.now()
        let names = index.names(matching: "*-00042.???")
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        try expectEqual(names, ["item-00042.txt"])
        bench("glob star+question 80k", elapsedMs)
        try expect(elapsedMs < 25, "glob search took \(elapsedMs)ms")
        try expectEqual(index.names(matching: "*port.???"), ["report.pdf"])
        try expect(index.names(matching: "*-99999.???").isEmpty)

        let multiStart = DispatchTime.now()
        let multi = index.names(matching: "i*e*00042*")
        let multiMs = Double(DispatchTime.now().uptimeNanoseconds - multiStart.uptimeNanoseconds) / 1_000_000
        try expectEqual(multi, ["item-00042.txt"])
        bench("multi-star glob 80k", multiMs)
        try expect(multiMs < 25, "multi-star search took \(multiMs)ms")

        let regexStart = DispatchTime.now()
        let regexed = index.names(matching: "regex:00042")
        let regexMs = Double(DispatchTime.now().uptimeNanoseconds - regexStart.uptimeNanoseconds) / 1_000_000
        try expectEqual(regexed, ["item-00042.txt"])
        bench("regex literal 80k", regexMs)
        try expect(regexMs < 20, "regex literal search took \(regexMs)ms")
        try expectEqual(index.names(matching: "regex:pdf$"), ["report.pdf"])
        try expectEqual(index.names(matching: "name:*.pdf"), ["report.pdf"])
    }

    private static func scannedPathJoinsAndExists() throws {
        let root = try FixtureHome.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let index = FileIndex()
        FileScanner(index: index, root: root, enableWatch: false, notifyOnMain: false).scanSynchronously()
        let photo = index.entries(at: index.search(query: "photo.jpg")).first
        try expect(photo != nil)
        try expectEqual(photo?.path, photo!.directory + "/" + photo!.name)
        try expect(photo!.path.hasSuffix("/Downloads/photo.jpg"))
        try expect(FileManager.default.fileExists(atPath: photo!.path))
        try expectEqual(index.names(matching: "path:Downloads photo"), ["photo.jpg"])
        let meeting = index.entries(at: index.search(query: "会议纪要")).first { $0.name == "会议纪要.docx" }
        try expectEqual(meeting?.name, "会议纪要.docx")
        try expect(meeting?.path.hasSuffix("/Desktop/会议纪要.docx") == true)
        try expect(FileManager.default.fileExists(atPath: meeting!.path))
    }

    private static func realHomeScanIfEnabled() throws {
        guard ProcessInfo.processInfo.environment["SAILFISH_REAL_HOME"] == "1" else { return }
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let index = FileIndex()
        let started = DispatchTime.now()
        FileScanner(index: index, root: home, enableWatch: false, notifyOnMain: false).scanSynchronously()
        let scanMs = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        bench("real home scan \(index.count)", scanMs)
        try expect(index.count > 1_000, "home indexed \(index.count)")

        let first = DispatchTime.now()
        let hits = index.search(query: "a")
        let searchMs = Double(DispatchTime.now().uptimeNanoseconds - first.uptimeNanoseconds) / 1_000_000
        bench("real home first keyword", searchMs)
        try expect(!hits.isEmpty, "home search for a was empty")
        try expect(searchMs < 80, "real home first keyword took \(searchMs)ms")

        _ = index.search(query: "")
        let afterEmpty = DispatchTime.now()
        let again = index.search(query: "会议")
        let afterEmptyMs = Double(DispatchTime.now().uptimeNanoseconds - afterEmpty.uptimeNanoseconds) / 1_000_000
        bench("real home empty then type", afterEmptyMs)
        _ = again
        try expect(afterEmptyMs < 40, "real home empty then type took \(afterEmptyMs)ms")
    }

    private static func searchWhileBuildingPathIndex() throws {
        let index = FileIndex()
        index.beginBulkLoad()
        var batch: [FileEntry] = []
        batch.reserveCapacity(80_002)
        for i in 0..<80_000 {
            batch.append(FileEntry(name: String(format: "item-%05d.txt", i), directory: "/pool"))
        }
        batch.append(FileEntry(name: "会议纪要.docx", directory: "/Desktop"))
        batch.append(FileEntry(name: "notes.txt", directory: "/tmp"))
        index.add(batch)
        index.endBulkLoad()

        try expectEqual(index.names(matching: "会议纪要"), ["会议纪要.docx"])
        try expectEqual(index.search(query: "").count, 80_002)

        var searchMs = 0.0
        var found: [String] = []
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInteractive).async {
            let started = DispatchTime.now()
            found = index.names(matching: "会议纪要")
            searchMs = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
            group.leave()
        }
        index.buildPathIndex()
        group.wait()
        try expectEqual(found, ["会议纪要.docx"])
        bench("search during path index 80k", searchMs)
        try expect(searchMs < 25, "search during path index took \(searchMs)ms")

        index.add([FileEntry(name: "notes.txt", directory: "/tmp", size: 4)], replace: true)
        try expectEqual(index.count, 80_002)
        try expectEqual(index.names(matching: "notes"), ["notes.txt"])
    }

    private static func pathIndexLargeReplace() throws {
        let index = FileIndex()
        index.beginBulkLoad()
        var batch: [FileEntry] = []
        let total = 200_000
        batch.reserveCapacity(total + 2)
        for i in 0..<total {
            batch.append(FileEntry(name: String(format: "f-%06d.txt", i), directory: "/pool/\(i % 200)"))
        }
        batch.append(FileEntry(name: "合同.pdf", directory: "/公司文件"))
        batch.append(FileEntry(name: "notes.txt", directory: "/tmp"))
        index.add(batch)
        index.endBulkLoad()
        try expectEqual(index.search(query: "").count, total + 2)

        let started = DispatchTime.now()
        index.buildPathIndex()
        let pathMs = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        bench("path index 200k", pathMs)
        try expect(pathMs < 250, "path index 200k took \(pathMs)ms")

        let target = FileEntry(name: "f-000042.txt", directory: "/pool/42", size: 99)
        index.add([target], replace: true)
        try expectEqual(index.count, total + 2)
        let updated = index.entries(at: index.search(query: "f-000042"))
        try expectEqual(updated.count, 1)
        try expectEqual(updated[0].size, 99)

        let chinese = FileEntry(name: "合同.pdf", directory: "/公司文件", size: 8)
        index.add([chinese], replace: true)
        try expectEqual(index.entries(at: index.search(query: "合同")).first?.size, 8)

        let openedPath = "/pool/42/f-000042.txt"
        let promoted = index.search(query: "f-00004", openedCounts: [openedPath: 5])
        try expectEqual(index.entries(at: [promoted[0]]).first?.path, openedPath)

        index.remove(paths: ["/tmp/notes.txt"])
        try expectEqual(index.count, total + 1)
        try expect(index.names(matching: "notes").isEmpty)
        try expectEqual(index.names(matching: "合同"), ["合同.pdf"])
        index.add([FileEntry(name: "fresh.txt", directory: "/tmp")], replace: true)
        try expectEqual(index.names(matching: "fresh"), ["fresh.txt"])
    }

    private static func matchCaseLargeIndex() throws {
        let index = FileIndex()
        var batch: [FileEntry] = []
        batch.reserveCapacity(80_003)
        for i in 0..<80_000 {
            batch.append(FileEntry(name: String(format: "item-%05d.txt", i), directory: "/pool"))
        }
        batch.append(FileEntry(name: "Report.PDF", directory: "/Desktop"))
        batch.append(FileEntry(name: "report.txt", directory: "/Downloads"))
        batch.append(FileEntry(name: "会议纪要.docx", directory: "/Desktop"))
        index.add(batch)

        var match = SearchOptions()
        match.matchCase = true
        let started = DispatchTime.now()
        let names = Set(index.names(matching: "Report", options: match))
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
        try expectEqual(names, Set(["Report.PDF"]))
        bench("match case 80k", elapsedMs)
        try expect(elapsedMs < 25, "match case search took \(elapsedMs)ms")
        try expectEqual(index.names(matching: "report", options: match), ["report.txt"])
        try expect(index.names(matching: "REPORT", options: match).isEmpty)
        try expectEqual(index.names(matching: "会议", options: match), ["会议纪要.docx"])
        try expectEqual(Set(index.names(matching: "report")), Set(["Report.PDF", "report.txt"]))
    }
}
