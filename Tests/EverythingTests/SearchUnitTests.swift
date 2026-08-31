import Foundation
import EverythingCore

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
        ])
        try expectEqual(
            Set(index.names(matching: "doc", options: SearchOptions(matchWholeWord: true))),
            Set(["doc", "my-doc-v2.txt"])
        )
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
    }

    private static func typingNarrows() throws {
        let index = makeIndex([
            ("会务手册.pdf", "/a"),
            ("会议纪要.docx", "/a"),
            ("预算.xlsx", "/a"),
        ])
        let first = index.search(query: "会")
        let second = index.search(query: "会议", previous: ("会", SearchOptions(), first))
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
            previous: ("会议", SearchOptions(), previous)
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
}
