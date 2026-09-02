import Foundation
import SailfishEverythingCore

enum SearchUnitTests {
    static var cases: [TestCase] {[
        TestCase(name: "单元.空查询列出全部", run: emptyQueryListsAll),
        TestCase(name: "单元.默认只搜文件名", run: defaultMatchesNameNotPath),
        TestCase(name: "单元.空格是AND", run: spaceIsAND),
        TestCase(name: "单元.默认忽略大小写", run: caseInsensitiveByDefault),
        TestCase(name: "单元.Match Case", run: matchCase),
        TestCase(name: "单元.Match Path", run: matchPath),
        TestCase(name: "单元.Match Whole Word", run: matchWholeWord),
        TestCase(name: "单元.通配符", run: wildcards),
        TestCase(name: "单元.加字收窄", run: typingNarrows),
        TestCase(name: "单元.改选项不沿用上一轮", run: optionChangeDropsPrevious),
        TestCase(name: "单元.同路径去重", run: dedupesSamePath),
        TestCase(name: "单元.删除后搜不到", run: removeDropsEntry),
        TestCase(name: "单元.路径由目录和文件名拼出", run: pathJoinsDirectoryAndName),
        TestCase(name: "单元.大名单空着不必搬下标", run: largeEmptyUsesIdentity),
        TestCase(name: "单元.名单拼回原样", run: reconstructsOriginalFields),
        TestCase(name: "单元.删一条时搜索不被挡住", run: removeDoesNotBlockSearch),
    ]}

    private static func makeIndex(_ names: [(name: String, directory: String)]) -> FileIndex {
        let index = FileIndex()
        index.add(names.map { FileEntry(name: $0.name, directory: $0.directory, size: 10) })
        return index
    }

    private static func emptyQueryListsAll() throws {
        let index = makeIndex([
            ("会议纪要.docx", "/Users/me/Desktop"),
            ("report.pdf", "/Users/me/Documents"),
        ])
        try expectEqual(index.names(matching: "").count, 2)
        try expectEqual(index.names(matching: "   ").count, 2)
    }

    private static func defaultMatchesNameNotPath() throws {
        let index = makeIndex([
            ("notes.txt", "/Users/me/会议纪要"),
            ("会议纪要.docx", "/Users/me/Desktop"),
        ])
        try expectEqual(index.names(matching: "会议纪要"), ["会议纪要.docx"])
    }

    private static func spaceIsAND() throws {
        let index = makeIndex([
            ("Q3会议纪要.docx", "/a"),
            ("会议安排.xlsx", "/a"),
            ("Q3预算.xlsx", "/a"),
        ])
        try expectEqual(index.names(matching: "Q3 会议"), ["Q3会议纪要.docx"])
    }

    private static func caseInsensitiveByDefault() throws {
        let index = makeIndex([("Report.PDF", "/a")])
        try expectEqual(index.names(matching: "report"), ["Report.PDF"])
        try expectEqual(index.names(matching: "PDF"), ["Report.PDF"])
    }

    private static func matchCase() throws {
        let index = makeIndex([("Report.PDF", "/a"), ("report.txt", "/a")])
        let options = SearchOptions(matchCase: true)
        try expectEqual(index.names(matching: "Report", options: options), ["Report.PDF"])
        try expectEqual(index.names(matching: "report", options: options), ["report.txt"])
        try expectEqual(index.names(matching: "PDF", options: options), ["Report.PDF"])
        try expect(index.names(matching: "pdf", options: options).isEmpty)
    }

    private static func matchPath() throws {
        let index = makeIndex([
            ("notes.txt", "/Users/me/OneDrive/合同"),
            ("合同.pdf", "/Users/me/Desktop"),
        ])
        try expectEqual(
            Set(index.names(matching: "合同", options: SearchOptions(matchPath: true))),
            Set(["notes.txt", "合同.pdf"])
        )
    }

    private static func matchWholeWord() throws {
        let index = makeIndex([
            ("doc", "/a"),
            ("document.pdf", "/a"),
            ("my-doc-v2.txt", "/a"),
            ("会议纪要.docx", "/a"),
            ("会议", "/a"),
            ("hello😀world.txt", "/a"),
            ("notes.txt", "/Desktop"),
        ])
        let whole = SearchOptions(matchWholeWord: true)
        try expectEqual(
            Set(index.names(matching: "doc", options: whole)),
            Set(["doc", "my-doc-v2.txt"])
        )
        try expectEqual(index.names(matching: "会议", options: whole), ["会议"])
        try expectEqual(index.names(matching: "hello", options: whole), ["hello😀world.txt"])
        try expectEqual(index.names(matching: "parent:Desktop", options: whole), ["notes.txt"])
        try expect(index.names(matching: "parent:Desk", options: whole).isEmpty)
    }

    private static func wildcards() throws {
        let index = makeIndex([
            ("report-final.docx", "/a"),
            ("report.pdf", "/a"),
            ("notes.txt", "/a"),
        ])
        try expectEqual(Set(index.names(matching: "*.pdf")), Set(["report.pdf"]))
        try expectEqual(Set(index.names(matching: "report*")), Set(["report-final.docx", "report.pdf"]))
        try expectEqual(Set(index.names(matching: "report.???")), Set(["report.pdf"]))
        try expectEqual(index.names(matching: "??????-final.????"), ["report-final.docx"])
        try expectEqual(Set(index.names(matching: "*port.???")), Set(["report.pdf"]))
        try expectEqual(index.names(matching: "*final.????"), ["report-final.docx"])
        try expectEqual(Set(index.names(matching: "report-?????.????")), Set(["report-final.docx"]))
        try expectEqual(index.names(matching: "r*t*l*x"), ["report-final.docx"])
        try expectEqual(index.names(matching: "name:*.pdf"), ["report.pdf"])
        try expectEqual(index.names(matching: "name:*final*"), ["report-final.docx"])
        try expectEqual(
            Set(index.names(matching: "path:*/a/*", options: SearchOptions(matchPath: false))),
            Set(["report-final.docx", "report.pdf", "notes.txt"])
        )
        try expectEqual(index.names(matching: "regex:pdf$"), ["report.pdf"])
        try expectEqual(index.names(matching: "regex:^report\\."), ["report.pdf"])
        try expectEqual(Set(index.names(matching: "regex:report")), Set(["report-final.docx", "report.pdf"]))
        try expectEqual(
            index.names(matching: "name:*.pdf", options: SearchOptions(matchPath: true)),
            ["report.pdf"]
        )
    }

    private static func typingNarrows() throws {
        let index = makeIndex([
            ("会务手册.pdf", "/a"),
            ("会议纪要.docx", "/a"),
            ("预算.xlsx", "/a"),
        ])
        let first = index.search(query: "会")
        let second = index.search(query: "会议", previous: SearchCursor(query: "会", indices: first))
        try expectEqual(first.count, 2)
        try expectEqual(second.count, 1)
        try expect(Set(second).isSubset(of: Set(first)))
        try expect(FileIndex.canNarrow(from: "会", to: "会议"))
        try expect(!FileIndex.canNarrow(from: "会议", to: "会"))
    }

    private static func optionChangeDropsPrevious() throws {
        let index = makeIndex([
            ("notes.txt", "/Users/me/会议"),
            ("会议.docx", "/Users/me/Desktop"),
        ])
        let previous = index.search(query: "会议")
        try expectEqual(index.names(matching: "会议"), ["会议.docx"])
        let withPath = index.names(
            matching: "会议",
            options: SearchOptions(matchPath: true),
            previous: SearchCursor(query: "会议", indices: previous)
        )
        try expectEqual(Set(withPath), Set(["notes.txt", "会议.docx"]))
    }

    private static func dedupesSamePath() throws {
        let index = FileIndex()
        let entry = FileEntry(name: "a.txt", directory: "/tmp")
        index.add([entry, entry])
        try expectEqual(index.count, 1)
    }

    private static func removeDropsEntry() throws {
        let index = FileIndex()
        let entry = FileEntry(name: "gone.txt", directory: "/tmp")
        index.add([entry])
        index.remove(paths: [entry.path])
        try expect(index.names(matching: "gone").isEmpty)
        try expectEqual(index.count, 0)
    }

    private static func pathJoinsDirectoryAndName() throws {
        try expectEqual(FileEntry(name: "photo.jpg", directory: "/Downloads").path, "/Downloads/photo.jpg")
        try expectEqual(FileEntry(name: "file", directory: "/tmp/").path, "/tmp/file")
        try expectEqual(FileEntry(name: "rootish", directory: "").path, "rootish")
        try expectEqual(FileEntry.parentDirectory(fromPath: "/Downloads/photo.jpg", name: "photo.jpg"), "/Downloads")
        try expectEqual(FileEntry.parentDirectory(fromPath: "/tmp/file", name: "file"), "/tmp")
        try expectEqual(FileEntry.parentDirectory(fromPath: "rootish", name: "rootish"), "")
        let index = makeIndex([("notes.txt", "/Users/me/会议")])
        try expectEqual(index.names(matching: "会议", options: SearchOptions(matchPath: true)), ["notes.txt"])
    }

    private static func largeEmptyUsesIdentity() throws {
        try expect(FileIndex.presentsUnsortedIdentity(query: "", total: 5_000))
        try expect(FileIndex.presentsUnsortedIdentity(query: "   ", total: 5_000))
        try expect(!FileIndex.presentsUnsortedIdentity(query: "", total: 100))
        try expect(!FileIndex.presentsUnsortedIdentity(query: "会", total: 5_000))
        try expect(!FileIndex.presentsUnsortedIdentity(query: "", sort: SortState(column: .size, ascending: false), total: 5_000))
        try expect(!FileIndex.presentsUnsortedIdentity(query: "", options: SearchOptions(inFolder: "/Desktop"), total: 5_000))
        try expect(FileIndex.presentsUnsortedIdentity(query: "", total: 10, allowFullSort: false))
        try expect(!FileIndex.presentsUnsortedIdentity(query: "", options: SearchOptions(regex: true), total: 5_000))
    }

    private static func reconstructsOriginalFields() throws {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let index = FileIndex()
        index.add([
            FileEntry(
                name: "会议纪要.docx",
                directory: "/Users/me/桌面",
                size: 42,
                modified: when,
                isCloudOnly: true
            ),
            FileEntry(name: "Photos", directory: "/Users/me/", isDirectory: true),
            FileEntry(name: "file", directory: "/tmp/", size: 8),
        ])

        let meeting = index.entries(at: index.search(query: "会议纪要")).first
        try expectEqual(meeting?.name, "会议纪要.docx")
        try expectEqual(meeting?.directory, "/Users/me/桌面")
        try expectEqual(meeting?.path, "/Users/me/桌面/会议纪要.docx")
        try expectEqual(meeting?.size, 42)
        try expectEqual(meeting?.modified, when)
        try expectEqual(meeting?.isCloudOnly, true)

        let folder = index.directories().first { $0.name == "Photos" }
        try expectEqual(folder?.path, "/Users/me/Photos")
        try expectEqual(folder?.isDirectory, true)

        let slashed = index.entries(at: index.search(query: "file")).first
        try expectEqual(slashed?.path, "/tmp/file")
        try expectEqual(slashed?.size, 8)
        try expectEqual(index.paths(under: "/Users/me/桌面"), ["/Users/me/桌面/会议纪要.docx"])
        try expectEqual(index.totalBytes, 50)

        index.add([
            FileEntry(name: "会议纪要.docx", directory: "/Users/me/桌面", size: 99, modified: when)
        ], replace: true)
        try expectEqual(index.entries(at: index.search(query: "会议纪要")).first?.size, 99)
        try expectEqual(index.entries(at: index.search(query: "会议纪要")).first?.isCloudOnly, false)
        try expectEqual(index.count, 3)
        try expectEqual(index.totalBytes, 107)
    }

    private static func removeDoesNotBlockSearch() throws {
        let index = FileIndex()
        var rows: [FileEntry] = (0..<8_000).map { FileEntry(name: "item-\($0).txt", directory: "/tmp/bulk") }
        rows.append(FileEntry(name: "keep-me.txt", directory: "/tmp/bulk"))
        index.add(rows)
        let doomed = "/tmp/bulk/item-1.txt"
        let group = DispatchGroup()
        var searchMs = 0.0
        var hits = 0
        group.enter()
        DispatchQueue.global(qos: .userInteractive).async {
            let start = DispatchTime.now()
            hits = index.search(query: "keep-me").count
            searchMs = Double(DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds) / 1_000_000
            group.leave()
        }
        index.remove(paths: [doomed])
        group.wait()
        try expectEqual(hits, 1)
        try expect(searchMs < 80, "search during remove took \(searchMs)ms")
        try expectEqual(index.count, 8_000)
        try expect(index.names(matching: "item-1.txt").isEmpty)
        try expectEqual(index.names(matching: "keep-me"), ["keep-me.txt"])
        try expectEqual(index.paths(under: "/tmp/bulk").count, 8_000)
    }
}
