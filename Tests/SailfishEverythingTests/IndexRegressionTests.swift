import Foundation
import SailfishEverythingCore

enum IndexRegressionTests {
    static var cases: [TestCase] {[
        TestCase(name: "回归.边敲边出不必回车", run: noEnterRequired),
        TestCase(name: "回归.只认文件名不认正文", run: filenameOnlyNotContent),
        TestCase(name: "回归.排序", run: sorts),
        TestCase(name: "回归.按名称再按路径", run: nameThenPath),
        TestCase(name: "回归.打开过的排前面", run: openedFirst),
        TestCase(name: "回归.重建名单", run: resetClears),
        TestCase(name: "回归.源码不接Spotlight", run: sourcesDoNotUseSpotlight),
    ]}

    private static func noEnterRequired() throws {
        let index = FileIndex()
        index.add([
            FileEntry(name: "会议纪要-Q1.docx", directory: "/Desktop"),
            FileEntry(name: "会议纪要-Q2.docx", directory: "/Desktop"),
            FileEntry(name: "会务手册.pdf", directory: "/Documents"),
            FileEntry(name: "预算.xlsx", directory: "/Documents"),
        ])

        var previous: SearchCursor?
        var lastCount = Int.max
        for query in ["", "会", "会议", "会议纪"] {
            let indices = index.search(query: query, previous: previous)
            try expect(indices.count <= lastCount)
            if !query.isEmpty {
                try expect(!indices.isEmpty)
            }
            lastCount = indices.count
            previous = SearchCursor(query: query, indices: indices)
        }
        try expectEqual(lastCount, 2)
    }

    private static func filenameOnlyNotContent() throws {
        let index = FileIndex()
        index.add([
            FileEntry(name: "vacation-photos.zip", directory: "/Downloads"),
            FileEntry(name: "readme.md", directory: "/src"),
        ])
        try expect(index.names(matching: "会议纪要").isEmpty)
        try expectEqual(index.names(matching: "vacation"), ["vacation-photos.zip"])
    }

    private static func sorts() throws {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        let index = FileIndex()
        index.add([
            FileEntry(name: "b.txt", directory: "/z", size: 100, modified: older),
            FileEntry(name: "a.txt", directory: "/a", size: 500, modified: newer),
        ])
        try expectEqual(index.names(matching: "", sort: SortState(column: .name, ascending: true)), ["a.txt", "b.txt"])
        try expectEqual(index.names(matching: "", sort: SortState(column: .size, ascending: false)), ["a.txt", "b.txt"])
        try expectEqual(index.names(matching: "", sort: SortState(column: .modified, ascending: false)), ["a.txt", "b.txt"])
        try expectEqual(index.names(matching: "", sort: SortState(column: .path, ascending: true)), ["a.txt", "b.txt"])
    }

    private static func nameThenPath() throws {
        let index = FileIndex()
        index.add([
            FileEntry(name: "report.pdf", directory: "/z"),
            FileEntry(name: "my-report.txt", directory: "/a"),
            FileEntry(name: "report-final.docx", directory: "/m"),
        ])
        try expectEqual(
            index.names(matching: "report"),
            ["my-report.txt", "report-final.docx", "report.pdf"]
        )
        try expectEqual(
            index.names(matching: "report", sort: SortState(column: .path, ascending: true)),
            ["my-report.txt", "report-final.docx", "report.pdf"]
        )
        let sameName = FileIndex()
        sameName.add([
            FileEntry(name: "notes.txt", directory: "/z"),
            FileEntry(name: "notes.txt", directory: "/a"),
        ])
        try expectEqual(
            sameName.search(query: "notes").map { sameName.entries(at: [$0])[0].directory },
            ["/a", "/z"]
        )
    }

    private static func openedFirst() throws {
        let index = FileIndex()
        index.add([
            FileEntry(name: "aaa.txt", directory: "/a"),
            FileEntry(name: "zzz.txt", directory: "/a"),
            FileEntry(name: "mmm.txt", directory: "/a"),
        ])
        try expectEqual(index.names(matching: "txt"), ["aaa.txt", "mmm.txt", "zzz.txt"])
        try expectEqual(
            index.names(matching: "txt", openedCounts: ["/a/zzz.txt": 1]),
            ["zzz.txt", "aaa.txt", "mmm.txt"]
        )
        try expectEqual(
            index.names(matching: "txt", openedCounts: ["/a/zzz.txt": 3, "/a/mmm.txt": 1]),
            ["zzz.txt", "mmm.txt", "aaa.txt"]
        )
        try expectEqual(
            index.names(matching: "txt", openedCounts: ["/no/such.txt": 9, "/a/aaa.txt": 1]),
            ["aaa.txt", "mmm.txt", "zzz.txt"]
        )
        try expectEqual(
            index.names(matching: "txt", openedCounts: ["/a/zzz.txt": 2, "/a/aaa.txt": 2]),
            ["aaa.txt", "zzz.txt", "mmm.txt"]
        )
    }

    private static func resetClears() throws {
        let index = FileIndex()
        index.add([FileEntry(name: "old.txt", directory: "/tmp")])
        index.reset()
        try expectEqual(index.count, 0)
        index.add([FileEntry(name: "new.txt", directory: "/tmp")])
        try expect(index.names(matching: "old").isEmpty)
        try expectEqual(index.names(matching: "new"), ["new.txt"])
    }

    private static func sourcesDoNotUseSpotlight() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoot = root.appendingPathComponent("Sources")
        let forbidden = ["mdfind", "NSMetadataQuery", "MDQuery", "NSMetadata"]
        var hits: [String] = []
        let fm = FileManager.default
        try expect(fm.fileExists(atPath: sourceRoot.path), "missing Sources")
        guard let enumerator = fm.enumerator(at: sourceRoot, includingPropertiesForKeys: nil) else {
            throw Expectation.failed("cannot enumerate Sources", #fileID, #line)
        }
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            for word in forbidden where text.contains(word) {
                hits.append("\(url.lastPathComponent): \(word)")
            }
        }
        try expect(hits.isEmpty, "found Spotlight usage: \(hits)")
    }
}
