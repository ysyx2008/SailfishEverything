import Foundation
import SailfishEverythingCore

enum QueryTests {
    static var cases: [TestCase] {[
        TestCase(name: "单元.OR语法", run: orSyntax),
        TestCase(name: "单元.NOT语法", run: notSyntax),
        TestCase(name: "单元.引号保留空格", run: quotedPhrase),
        TestCase(name: "单元.ext过滤扩展名", run: extSyntax),
        TestCase(name: "单元.size比较大小", run: sizeSyntax),
        TestCase(name: "单元.file和folder", run: fileFolderSyntax),
        TestCase(name: "单元.正则匹配文件名", run: regexName),
        TestCase(name: "单元.过滤器只留图片文档", run: filters),
        TestCase(name: "单元.导出CSV和TXT", run: exportFormats),
        TestCase(name: "单元.书签存取", run: bookmarkRoundTrip),
        TestCase(name: "单元.坏正则不崩且搜不到", run: invalidRegexSafe),
        TestCase(name: "单元.空path和坏size不误匹配", run: emptyPathAndBadSize),
        TestCase(name: "单元.未闭合引号仍能搜", run: unclosedQuote),
        TestCase(name: "单元.dm今天和昨天", run: dateModifiedSyntax),
        TestCase(name: "单元.dm绝对日期和坏日期", run: dateAbsoluteAndInvalid),
        TestCase(name: "单元.parent和name语法", run: parentAndNameSyntax),
        TestCase(name: "单元.AND和OR和NOT单词", run: wordOperators),
        TestCase(name: "单元.startwith和endwith和exact", run: prefixSuffixExact),
        TestCase(name: "单元.len和empty和regex词", run: lengthEmptyRegex),
        TestCase(name: "单元.dc创建日期", run: dateCreatedSyntax),
        TestCase(name: "单元.语法空值和坏值不误匹配", run: newSyntaxEdges),
        TestCase(name: "单元.状态栏体积", run: resultStatsLine),
        TestCase(name: "单元.只有大小日期查询才读磁盘属性", run: metadataFlag),
    ]}

    private static func sampleIndex() -> FileIndex {
        let index = FileIndex()
        index.add([
            FileEntry(name: "会议纪要.docx", directory: "/Desktop", size: 20_000),
            FileEntry(name: "会议安排.pdf", directory: "/Documents", size: 8_000),
            FileEntry(name: "budget.xlsx", directory: "/Documents", size: 2_000_000),
            FileEntry(name: "photo.jpg", directory: "/Downloads", size: 400_000),
            FileEntry(name: "song.mp3", directory: "/Music", size: 5_000_000),
            FileEntry(name: "clip.mp4", directory: "/Movies", size: 80_000_000),
            FileEntry(name: "archive.zip", directory: "/Downloads", size: 12_000_000),
            FileEntry(name: "Notes", directory: "/Desktop", isDirectory: true),
        ])
        return index
    }

    private static func orSyntax() throws {
        let names = Set(sampleIndex().names(matching: "会议 | budget"))
        try expectEqual(names, Set(["会议纪要.docx", "会议安排.pdf", "budget.xlsx"]))
    }

    private static func notSyntax() throws {
        let names = Set(sampleIndex().names(matching: "会议 !pdf"))
        try expectEqual(names, Set(["会议纪要.docx"]))
    }

    private static func quotedPhrase() throws {
        let index = FileIndex()
        index.add([
            FileEntry(name: "Q3 会议纪要.docx", directory: "/a"),
            FileEntry(name: "Q3会议纪要.docx", directory: "/a"),
        ])
        try expectEqual(index.names(matching: "\"Q3 会议\""), ["Q3 会议纪要.docx"])
    }

    private static func extSyntax() throws {
        let names = Set(sampleIndex().names(matching: "ext:jpg;mp3"))
        try expectEqual(names, Set(["photo.jpg", "song.mp3"]))
    }

    private static func sizeSyntax() throws {
        let big = Set(sampleIndex().names(matching: "size:>10mb"))
        try expect(big.contains("clip.mp4"))
        try expect(big.contains("archive.zip"))
        try expect(!big.contains("photo.jpg"))
        let small = Set(sampleIndex().names(matching: "size:<10kb"))
        try expectEqual(small, Set(["会议安排.pdf"]))
    }

    private static func fileFolderSyntax() throws {
        try expect(sampleIndex().names(matching: "folder:").contains("Notes"))
        try expect(!sampleIndex().names(matching: "file: 会议").contains("Notes"))
        try expect(sampleIndex().names(matching: "file: 会议").contains("会议纪要.docx"))
    }

    private static func regexName() throws {
        let options = SearchOptions(regex: true)
        let names = Set(sampleIndex().names(matching: #"会议.+\.docx"#, options: options))
        try expectEqual(names, Set(["会议纪要.docx"]))
    }

    private static func filters() throws {
        let index = sampleIndex()
        try expectEqual(Set(index.names(matching: "", filter: .picture)), Set(["photo.jpg"]))
        try expectEqual(Set(index.names(matching: "", filter: .audio)), Set(["song.mp3"]))
        try expectEqual(Set(index.names(matching: "", filter: .video)), Set(["clip.mp4"]))
        try expectEqual(Set(index.names(matching: "", filter: .compressed)), Set(["archive.zip"]))
        try expect(index.names(matching: "", filter: .document).contains("会议纪要.docx"))
        try expectEqual(index.names(matching: "", filter: .folder), ["Notes"])
    }

    private static func exportFormats() throws {
        let index = sampleIndex()
        let entries = index.entries(at: index.search(query: "photo"))
        let csv = ResultExport.csv(entries)
        try expect(csv.contains("Name,Path,Size,Date Modified"))
        try expect(csv.contains("photo.jpg"))
        let txt = ResultExport.txt(entries)
        try expect(txt.contains("/Downloads/photo.jpg"))
    }

    private static func bookmarkRoundTrip() throws {
        let suite = "sailfish.bookmark.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let bookmark = Bookmark(
            name: "纪要",
            query: "会议 ext:docx",
            options: SearchOptions(matchPath: true),
            filter: .document
        )
        BookmarkStore.save([bookmark], defaults: defaults)
        let loaded = BookmarkStore.load(defaults: defaults)
        try expectEqual(loaded.count, 1)
        try expectEqual(loaded[0].name, "纪要")
        try expectEqual(loaded[0].query, "会议 ext:docx")
        try expectEqual(loaded[0].filter, .document)
        try expect(loaded[0].options.matchPath)
        try expectEqual(loaded[0].inFolder, "")

        let located = Bookmark(
            name: "下载",
            query: "photo",
            options: SearchOptions(inFolder: "/Downloads"),
            filter: .picture
        )
        BookmarkStore.save([located], defaults: defaults)
        try expectEqual(BookmarkStore.load(defaults: defaults)[0].inFolder, "/Downloads")
        try expectEqual(BookmarkStore.load(defaults: defaults)[0].options.inFolder, "/Downloads")
    }

    private static func invalidRegexSafe() throws {
        try expect(!Query.isValidRegex("("))
        try expect(Query.isValidRegex("会议.+\\.docx"))
        let names = sampleIndex().names(matching: "(", options: SearchOptions(regex: true))
        try expect(names.isEmpty)
    }

    private static func emptyPathAndBadSize() throws {
        try expect(sampleIndex().names(matching: "path:").isEmpty)
        try expect(sampleIndex().names(matching: "size:nope").isEmpty)
        try expect(sampleIndex().names(matching: "ext:").isEmpty)
    }

    private static func unclosedQuote() throws {
        let index = FileIndex()
        index.add([
            FileEntry(name: "Q3 会议纪要.docx", directory: "/a"),
            FileEntry(name: "other.txt", directory: "/a"),
        ])
        try expectEqual(index.names(matching: "\"Q3 会议"), ["Q3 会议纪要.docx"])
    }

    private static func dateModifiedSyntax() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 15))!
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: today)!
        let index = FileIndex()
        index.add([
            FileEntry(name: "today.txt", directory: "/a", modified: now),
            FileEntry(name: "yesterday.txt", directory: "/a", modified: yesterday.addingTimeInterval(3600)),
            FileEntry(name: "old.txt", directory: "/a", modified: lastMonth),
        ])
        let todayHits = index.entries(at: index.search(query: "")).filter {
            Query.parse("dm:today", now: now, calendar: calendar).matches($0, options: SearchOptions())
        }.map(\.name)
        try expectEqual(Set(todayHits), Set(["today.txt"]))

        let yesterdayHits = index.entries(at: index.search(query: "")).filter {
            Query.parse("dm:yesterday", now: now, calendar: calendar).matches($0, options: SearchOptions())
        }.map(\.name)
        try expectEqual(yesterdayHits, ["yesterday.txt"])

        let weekHits = index.entries(at: index.search(query: "")).filter {
            Query.parse("dm:last30days", now: now, calendar: calendar).matches($0, options: SearchOptions())
        }.map(\.name)
        try expect(weekHits.contains("today.txt"))
        try expect(weekHits.contains("yesterday.txt"))
    }

    private static func dateAbsoluteAndInvalid() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 12))!
        let day = calendar.date(from: DateComponents(year: 2024, month: 1, day: 15, hour: 8))!
        let later = calendar.date(from: DateComponents(year: 2025, month: 6, day: 1, hour: 8))!
        let index = FileIndex()
        index.add([
            FileEntry(name: "old-contract.pdf", directory: "/a", modified: day),
            FileEntry(name: "new-contract.pdf", directory: "/a", modified: later),
        ])
        let exact = index.entries(at: index.search(query: "")).filter {
            Query.parse("dm:2024-01-15", now: now, calendar: calendar).matches($0, options: SearchOptions())
        }.map(\.name)
        try expectEqual(exact, ["old-contract.pdf"])
        let after = index.entries(at: index.search(query: "")).filter {
            Query.parse("dm:>2024-01-15", now: now, calendar: calendar).matches($0, options: SearchOptions())
        }.map(\.name)
        try expectEqual(after, ["new-contract.pdf"])
        let bad = index.entries(at: index.search(query: "")).filter {
            Query.parse("dm:not-a-date", now: now, calendar: calendar).matches($0, options: SearchOptions())
        }
        try expect(bad.isEmpty)
    }

    private static func parentAndNameSyntax() throws {
        let index = FileIndex()
        index.add([
            FileEntry(name: "合同.pdf", directory: "/Users/me/OneDrive/公司文件"),
            FileEntry(name: "notes.txt", directory: "/Users/me/Downloads"),
            FileEntry(name: "公司文件", directory: "/Users/me"),
        ])
        try expectEqual(index.names(matching: "parent:公司文件"), ["合同.pdf"])
        try expectEqual(index.names(matching: "parent:Downloads"), ["notes.txt"])
        try expect(index.names(matching: "parent:").isEmpty)
        try expectEqual(index.names(matching: "name:合同"), ["合同.pdf"])
        try expect(index.names(matching: "name:OneDrive", options: SearchOptions(matchPath: true)).isEmpty)
        try expect(index.names(matching: "path:OneDrive").contains("合同.pdf"))
    }

    private static func wordOperators() throws {
        let names = Set(sampleIndex().names(matching: "会议 OR budget"))
        try expectEqual(names, Set(["会议纪要.docx", "会议安排.pdf", "budget.xlsx"]))
        try expectEqual(Set(sampleIndex().names(matching: "会议 AND pdf")), Set(["会议安排.pdf"]))
        try expectEqual(Set(sampleIndex().names(matching: "会议 NOT pdf")), Set(["会议纪要.docx"]))
        try expectEqual(Set(sampleIndex().names(matching: "NOT pdf 会议")), Set(["会议纪要.docx"]))
        try expectEqual(Set(sampleIndex().names(matching: "会议 NOT NOT pdf")), Set(["会议安排.pdf"]))
        let index = FileIndex()
        index.add([FileEntry(name: "OR", directory: "/a"), FileEntry(name: "other.txt", directory: "/a")])
        try expectEqual(index.names(matching: "\"OR\""), ["OR"])
        try expectEqual(index.names(matching: "OR other"), ["other.txt"])
    }

    private static func prefixSuffixExact() throws {
        try expectEqual(Set(sampleIndex().names(matching: "startwith:会议")), Set(["会议纪要.docx", "会议安排.pdf"]))
        try expectEqual(Set(sampleIndex().names(matching: "endwith:.jpg")), Set(["photo.jpg"]))
        try expectEqual(sampleIndex().names(matching: "exact:photo.jpg"), ["photo.jpg"])
        try expect(sampleIndex().names(matching: "exact:photo").isEmpty)
        try expect(sampleIndex().names(matching: "startswith:Photo", options: SearchOptions(matchCase: true)).isEmpty)
        try expectEqual(sampleIndex().names(matching: "startswith:photo", options: SearchOptions(matchCase: true)), ["photo.jpg"])
    }

    private static func lengthEmptyRegex() throws {
        try expect(sampleIndex().names(matching: "len:>8").contains("会议纪要.docx"))
        try expect(!sampleIndex().names(matching: "len:<6").contains("会议纪要.docx"))
        try expectEqual(Set(sampleIndex().names(matching: "len:9")), Set(["会议纪要.docx", "photo.jpg"]))
        let index = FileIndex()
        index.add([
            FileEntry(name: "zero.dat", directory: "/a", size: 0),
            FileEntry(name: "tiny.dat", directory: "/a", size: 4),
            FileEntry(name: "empty-folder", directory: "/a", isDirectory: true),
        ])
        try expectEqual(index.names(matching: "empty:"), ["zero.dat"])
        try expectEqual(sampleIndex().names(matching: "regex:photo\\.jpg"), ["photo.jpg"])
        try expect(sampleIndex().names(matching: "regex:(").isEmpty)
        try expect(sampleIndex().names(matching: "会议 regex:docx$").contains("会议纪要.docx"))
    }

    private static func dateCreatedSyntax() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 15))!
        let today = calendar.startOfDay(for: now)
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: today)!
        let index = FileIndex()
        index.add([
            FileEntry(name: "newborn.txt", directory: "/a", modified: lastMonth, created: now),
            FileEntry(name: "oldborn.txt", directory: "/a", modified: now, created: lastMonth),
        ])
        let createdToday = index.entries(at: index.search(query: "")).filter {
            Query.parse("dc:today", now: now, calendar: calendar).matches($0, options: SearchOptions())
        }.map(\.name)
        try expectEqual(createdToday, ["newborn.txt"])
        let modifiedToday = index.entries(at: index.search(query: "")).filter {
            Query.parse("dm:today", now: now, calendar: calendar).matches($0, options: SearchOptions())
        }.map(\.name)
        try expectEqual(modifiedToday, ["oldborn.txt"])
        let missing = FileEntry(name: "nodate.txt", directory: "/a")
        try expect(!Query.parse("dc:today", now: now, calendar: calendar).matches(missing, options: SearchOptions()))
    }

    private static func newSyntaxEdges() throws {
        try expect(sampleIndex().names(matching: "startwith:").isEmpty)
        try expect(sampleIndex().names(matching: "endwith:").isEmpty)
        try expect(sampleIndex().names(matching: "exact:").isEmpty)
        try expect(sampleIndex().names(matching: "len:").isEmpty)
        try expect(sampleIndex().names(matching: "len:nope").isEmpty)
        try expect(sampleIndex().names(matching: "regex:").isEmpty)
        try expect(sampleIndex().names(matching: "dc:not-a-date").isEmpty)
        try expect(!Query.canNarrow(from: "", to: "会"))
        try expect(Query.canNarrow(from: "foo", to: "foo bar"))
        try expect(!Query.canNarrow(from: "foo", to: "foo OR bar"))
        try expect(!Query.canNarrow(from: "foo", to: "foo|bar"))
    }

    private static func resultStatsLine() throws {
        let entries = [
            FileEntry(name: "a.bin", directory: "/a", size: 1_500),
            FileEntry(name: "b.bin", directory: "/a", size: 500),
            FileEntry(name: "dir", directory: "/a", isDirectory: true),
        ]
        try expectEqual(ResultStats.totalBytes(entries), 2_000)
        let all = ResultStats.line(objects: 3, selected: 0, bytes: 2_000)
        try expect(all.hasPrefix("3 objects ("))
        try expect(all.contains("KB") || all.contains("B"))
        let selected = ResultStats.line(objects: 12, selected: 2, bytes: 500)
        try expect(selected.contains("2 of 12 objects selected"))
        try expectEqual(ResultStats.line(objects: 0, selected: 0, bytes: 0), "0 objects")
    }

    private static func metadataFlag() throws {
        try expect(!Query.parse("会议").needsMetadata)
        try expect(!Query.parse("path:Downloads").needsMetadata)
        try expect(Query.parse("size:>10mb").needsMetadata)
        try expect(Query.parse("dm:today").needsMetadata)
        try expect(Query.parse("dc:last7days").needsMetadata)
        try expect(Query.parse("empty:").needsMetadata)
        try expect(Query.parse("会议 NOT size:<1kb").needsMetadata)
    }
}
