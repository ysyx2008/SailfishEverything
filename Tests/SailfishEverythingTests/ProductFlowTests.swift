import Foundation
import SailfishEverythingCore

enum ProductFlowTests {
    static var cases: [TestCase] {[
        TestCase(name: "端到端.扫盘后用语法边敲边出", run: typeWithSyntaxAfterScan),
        TestCase(name: "端到端.过滤器收窄真实文件", run: filterRealTree),
        TestCase(name: "端到端.导出当前结果", run: exportAfterSearch),
        TestCase(name: "端到端.书签还原查询", run: bookmarkRestoresSearch),
        TestCase(name: "端到端.删除文件后名单更新", run: deleteThenGone),
        TestCase(name: "端到端.重命名后能搜到新名", run: renameThenFind),
        TestCase(name: "端到端.产品名不单独叫Everything", run: productNameIsSailfishEverything),
        TestCase(name: "端到端.中文名叫旗鱼搜索", run: chineseProductNameIsQiyu),
        TestCase(name: "端到端.一次坐下从扫盘用到改文件", run: fullSitting),
        TestCase(name: "端到端.改排除后重扫", run: excludeThenRescan),
        TestCase(name: "端到端.默认能搜到微信聊天文件", run: wechatChatFilesIncluded),
        TestCase(name: "端到端.限定文件夹", run: lookInFolder),
        TestCase(name: "端到端.退格后结果重新变宽", run: backspaceWidens),
        TestCase(name: "端到端.扫盘后size和path语法", run: sizeAndPathAfterScan),
        TestCase(name: "端到端.导出带逗号的文件名", run: exportCommaName),
        TestCase(name: "端到端.搜索历史可还原", run: historyRestores),
        TestCase(name: "端到端.单词OR和startwith", run: wordOrAndStartwith),
        TestCase(name: "端到端.主窗口必须自己拿住窗口", run: windowIsDesignatedInit),
    ]}

    private static func indexedFixture() throws -> (URL, FileIndex) {
        let root = try FixtureHome.make()
        let index = FileIndex()
        FileScanner(index: index, root: root, enableWatch: false, notifyOnMain: false).scanSynchronously()
        return (root, index)
    }

    private static func typeWithSyntaxAfterScan() throws {
        let (root, index) = try indexedFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        var previous: SearchCursor?
        for query in ["", "会", "会议", "会议 | photo"] {
            let indices = index.search(query: query, previous: previous)
            previous = SearchCursor(query: query, indices: indices)
        }
        let last = Set(index.entries(at: previous!.indices).map(\.name))
        try expect(last.contains("会议纪要.docx"))
        try expect(last.contains("photo.jpg"))

        let noPdf = Set(index.names(matching: "会议 !pdf"))
        try expect(noPdf.contains("会议纪要.docx"))
        try expect(noPdf.contains("Q3 会议纪要.docx"))
        try expect(!noPdf.contains(where: { $0.hasSuffix(".pdf") }))
        try expectEqual(Set(index.names(matching: "ext:mp3")), Set(["song.mp3"]))
    }

    private static func filterRealTree() throws {
        let (root, index) = try indexedFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try expectEqual(index.names(matching: "", filter: .picture), ["photo.jpg"])
        try expectEqual(index.names(matching: "", filter: .audio), ["song.mp3"])
        try expectEqual(index.names(matching: "", filter: .video), ["clip.mp4"])
        try expectEqual(index.names(matching: "", filter: .compressed), ["archive.zip"])
        try expect(index.names(matching: "", filter: .document).contains("会议纪要.docx"))
        try expect(index.names(matching: "photo", filter: .audio).isEmpty)
        try expectEqual(index.names(matching: "photo", filter: .picture), ["photo.jpg"])
    }

    private static func exportAfterSearch() throws {
        let (root, index) = try indexedFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let entries = index.entries(at: index.search(query: "合同"))
        try expectEqual(entries.map(\.name), ["合同.pdf"])
        let csv = ResultExport.csv(entries)
        try expect(csv.contains("合同.pdf"))
        try expect(csv.contains("公司文件") || csv.contains("Documents") || csv.contains(entries[0].directory))
        let txt = ResultExport.txt(entries)
        try expect(txt.contains(entries[0].path))
        let out = root.appendingPathComponent("export.csv")
        try csv.data(using: .utf8)!.write(to: out)
        let disk = try String(contentsOf: out, encoding: .utf8)
        try expect(disk.contains("合同.pdf"))
    }

    private static func bookmarkRestoresSearch() throws {
        let (root, index) = try indexedFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "sailfish.flow.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let bookmark = Bookmark(name: "照片", query: "photo", filter: .picture)
        BookmarkStore.save([bookmark], defaults: defaults)
        let restored = BookmarkStore.load(defaults: defaults)[0]
        try expectEqual(
            index.names(matching: restored.query, options: restored.options, filter: restored.filter),
            ["photo.jpg"]
        )
    }

    private static func deleteThenGone() throws {
        let (root, index) = try indexedFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let photo = root.appendingPathComponent("Downloads/photo.jpg").resolvingSymlinksInPath()
        try expectEqual(index.names(matching: "photo"), ["photo.jpg"])
        try FileManager.default.removeItem(at: photo)
        index.remove(paths: [photo.path])
        try expect(index.names(matching: "photo").isEmpty)
        try expect(index.names(matching: "", filter: .picture).isEmpty)
    }

    private static func renameThenFind() throws {
        let (root, index) = try indexedFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let photo = root.appendingPathComponent("Downloads/photo.jpg").resolvingSymlinksInPath()
        let renamed = photo.deletingLastPathComponent().appendingPathComponent("假期照片.jpg")
        try FileManager.default.moveItem(at: photo, to: renamed)
        index.remove(paths: [photo.path])
        index.reset()
        FileScanner(index: index, root: root, enableWatch: false, notifyOnMain: false).scanSynchronously()
        try expectEqual(index.names(matching: "假期照片"), ["假期照片.jpg"])
        try expect(index.names(matching: "photo.jpg").isEmpty)
    }

    private static func productNameIsSailfishEverything() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let previous = L10n.language
        L10n.language = .english
        defer { L10n.language = previous }
        try expectEqual(L10n.productName, "Sailfish Everything")
        try expectEqual(L10n.t(.aboutApp), "About Sailfish Everything")
        try expect(!L10n.t(.aboutApp).contains("About Everything"))
        try expect(!L10n.t(.aboutBody).contains("Namelist"))
        try expect(L10n.t(.aboutBody).contains("© 2026 Sailfish"))
        let plist = try String(contentsOf: root.appendingPathComponent("Resources/Info.plist"), encoding: .utf8)
        try expect(plist.contains("Sailfish Everything"))
        try expect(plist.contains("SailfishEverything"))
        try expect(plist.contains("NSHumanReadableCopyright"))
        try expect(plist.contains("© 2026 Sailfish"))
        let app = try String(contentsOf: root.appendingPathComponent("Sources/SailfishEverything/App.swift"), encoding: .utf8)
        try expect(app.contains("L10n.productName") || app.contains("L10n.t(.aboutApp)"))
        try expect(!app.contains("About Everything\""))
        try expect(!app.contains("Namelist"))
        let window = try String(contentsOf: root.appendingPathComponent("Sources/SailfishEverything/MainWindowController.swift"), encoding: .utf8)
        try expect(window.contains("L10n.productName"))
        try expect(window.contains("previewSelected"))
        try expect(window.contains("showInfo"))
        try expect(app.contains("showSearchHelp"))
        let settings = try String(contentsOf: root.appendingPathComponent("Sources/SailfishEverything/SettingsWindowController.swift"), encoding: .utf8)
        try expect(settings.contains("L10n.t(.launchAtLogin)") || settings.contains("L10n.t"))
        try expect(!settings.contains("Namelist"))
        let english = try String(contentsOf: root.appendingPathComponent("Resources/en.lproj/InfoPlist.strings"), encoding: .utf8)
        try expect(english.contains("Sailfish Everything"))
        try expect(!english.contains("Namelist"))
    }

    private static func chineseProductNameIsQiyu() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let previous = L10n.language
        L10n.language = .chinese
        defer { L10n.language = previous }
        try expectEqual(L10n.productName, "旗鱼搜索")
        try expectEqual(L10n.t(.aboutApp), "关于旗鱼搜索")
        try expect(L10n.t(.quitApp).contains("旗鱼搜索"))
        try expect(!L10n.productName.contains("Everything"))
        try expect(!L10n.t(.aboutBody).contains("Namelist"))
        let chinese = try String(contentsOf: root.appendingPathComponent("Resources/zh-Hans.lproj/InfoPlist.strings"), encoding: .utf8)
        try expect(chinese.contains("旗鱼搜索"))
        try expect(!chinese.contains("Sailfish Everything"))
        try expect(!chinese.contains("Namelist"))
    }

    private static func fullSitting() throws {
        let (root, index) = try indexedFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        var previous: SearchCursor?
        for query in ["", "会", "会议", "会议纪"] {
            let indices = index.search(query: query, previous: previous)
            previous = SearchCursor(query: query, indices: indices)
            try expect(!indices.isEmpty)
        }
        try expect(Set(index.entries(at: previous!.indices).map(\.name)).isSuperset(of: ["会议纪要.docx", "Q3 会议纪要.docx"]))

        let quoted = index.names(matching: "\"Q3 会议\"")
        try expectEqual(quoted, ["Q3 会议纪要.docx"])
        try expectEqual(index.names(matching: "file: run"), ["run.sh"])
        try expect(index.names(matching: "", filter: .executable).contains("run.sh"))
        try expectEqual(
            index.names(matching: "readme", options: SearchOptions(matchCase: true)),
            []
        )
        try expectEqual(index.names(matching: "README", options: SearchOptions(matchCase: true)), ["README.md"])

        let sorted = index.names(matching: "会议", sort: SortState(column: .name, ascending: true))
        try expect(sorted.first == "Q3 会议纪要.docx" || sorted.contains("Q3 会议纪要.docx"))

        let suite = "sailfish.sit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        BookmarkStore.save([Bookmark(name: "图", query: "photo", filter: .picture)], defaults: defaults)
        let bookmark = BookmarkStore.load(defaults: defaults)[0]
        try expectEqual(index.names(matching: bookmark.query, filter: bookmark.filter), ["photo.jpg"])

        let csv = ResultExport.csv(index.entries(at: index.search(query: "Q1")))
        try expect(csv.contains("\"Q1, 备份.txt\"") || csv.contains("Q1, 备份.txt"))

        let photo = root.appendingPathComponent("Downloads/photo.jpg").resolvingSymlinksInPath()
        let renamed = photo.deletingLastPathComponent().appendingPathComponent("海边.jpg")
        try FileManager.default.moveItem(at: photo, to: renamed)
        index.remove(paths: [photo.path])
        index.reset()
        FileScanner(index: index, root: root, enableWatch: false, notifyOnMain: false).scanSynchronously()
        try expectEqual(index.names(matching: "海边"), ["海边.jpg"])
        try expect(index.names(matching: "photo.jpg").isEmpty)
    }

    private static func excludeThenRescan() throws {
        let root = try FixtureHome.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = IndexSettings(extraExcludedRelatives: ["Work"])
        let index = FileIndex()
        FileScanner(index: index, root: root, settings: settings, enableWatch: false, notifyOnMain: false).scanSynchronously()
        try expect(index.names(matching: "main.swift").isEmpty)
        try expectEqual(index.names(matching: "photo"), ["photo.jpg"])
        try expectEqual(index.names(matching: "合同"), ["合同.pdf"])
    }

    private static func wechatChatFilesIncluded() throws {
        let root = try FixtureHome.make()
        try FixtureHome.addWeChatChatFiles(root)
        defer { try? FileManager.default.removeItem(at: root) }
        let index = FileIndex()
        FileScanner(index: index, root: root, enableWatch: false, notifyOnMain: false).scanSynchronously()
        try expect(index.names(matching: "花名册").contains("花名册.xlsx"))
        try expect(index.names(matching: "半年报").contains("半年报.pdf"))
        try expect(index.names(matching: "hash").isEmpty)
        try expectEqual(index.names(matching: "合同"), ["合同.pdf"])
    }

    private static func lookInFolder() throws {
        let (root, index) = try indexedFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let downloads = root.appendingPathComponent("Downloads").resolvingSymlinksInPath().path
        let desktop = root.appendingPathComponent("Desktop").resolvingSymlinksInPath().path
        try expectEqual(index.names(matching: "photo", options: SearchOptions(inFolder: downloads)), ["photo.jpg"])
        try expect(index.names(matching: "photo", options: SearchOptions(inFolder: desktop)).isEmpty)
        try expect(index.names(matching: "会议", options: SearchOptions(inFolder: desktop)).contains("会议纪要.docx"))
        try expect(!index.names(matching: "会议", options: SearchOptions(inFolder: downloads)).contains("会议纪要.docx"))
    }

    private static func backspaceWidens() throws {
        let (root, index) = try indexedFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var previous: SearchCursor?
        let narrow = index.search(query: "会议纪要")
        previous = SearchCursor(query: "会议纪要", indices: narrow)
        try expectEqual(Set(index.entries(at: narrow).map(\.name)), Set(["会议纪要.docx", "Q3 会议纪要.docx"]))
        try expect(!Query.canNarrow(from: "会议纪要", to: "会议"))
        let wide = index.search(query: "会议", previous: previous)
        try expect(wide.count >= narrow.count)
        try expect(index.entries(at: wide).map(\.name).contains("会议纪要.docx"))
    }

    private static func sizeAndPathAfterScan() throws {
        let (root, index) = try indexedFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try expectEqual(index.names(matching: "ext:dat size:<1kb"), ["tiny.dat"])
        try expect(index.names(matching: "size:>1mb").contains("big.bin"))
        try expect(!index.names(matching: "size:>1mb").contains("tiny.dat"))
        try expectEqual(index.names(matching: "path:公司文件 合同"), ["合同.pdf"])
        try expect(index.names(matching: "path:OneDrive").isEmpty)
        try expect(index.names(matching: "folder:").contains("Downloads") || index.names(matching: "folder:").contains("Desktop"))
    }

    private static func exportCommaName() throws {
        let (root, index) = try indexedFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let entries = index.entries(at: index.search(query: "Q1"))
        try expectEqual(entries.map(\.name), ["Q1, 备份.txt"])
        let csv = ResultExport.csv(entries)
        try expect(csv.contains("\"Q1, 备份.txt\""))
        let out = root.appendingPathComponent("comma.csv")
        try csv.data(using: .utf8)!.write(to: out)
        let disk = try String(contentsOf: out, encoding: .utf8)
        try expect(disk.contains("\"Q1, 备份.txt\""))
    }

    private static func historyRestores() throws {
        let (root, index) = try indexedFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "sailfish.hist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        SearchHistoryStore.record("会", defaults: defaults)
        SearchHistoryStore.record("会议", defaults: defaults)
        SearchHistoryStore.record("会议", defaults: defaults)
        let items = SearchHistoryStore.load(defaults: defaults)
        try expectEqual(items.first, "会议")
        try expectEqual(items, ["会议", "会"])
        try expect(index.names(matching: items[0]).contains("会议纪要.docx"))
    }

    private static func wordOrAndStartwith() throws {
        let (root, index) = try indexedFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let orNames = Set(index.names(matching: "会议 OR photo"))
        try expect(orNames.contains("会议纪要.docx"))
        try expect(orNames.contains("photo.jpg"))
        try expectEqual(Set(index.names(matching: "startwith:photo")), Set(["photo.jpg"]))
        try expect(index.names(matching: "endwith:.mp3").contains("song.mp3"))
        let photo = index.entries(at: index.search(query: "photo.jpg")).first
        try expectEqual(photo?.size, 1)
        try expect(photo?.modified != nil)
        try expect(photo?.created != nil)
    }

    private static func windowIsDesignatedInit() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let window = try String(contentsOf: root.appendingPathComponent("Sources/SailfishEverything/MainWindowController.swift"), encoding: .utf8)
        try expect(window.contains("super.init(window:"))
        try expect(window.contains("isReleasedWhenClosed = false"))
        try expect(window.contains("func hideMainWindow()"))
        try expect(window.contains("setActivationPolicy(.accessory)"))
        try expect(!window.contains("convenience init(home:"))
        let app = try String(contentsOf: root.appendingPathComponent("Sources/SailfishEverything/App.swift"), encoding: .utf8)
        try expect(app.contains("AppDelegate.shared"))
        try expect(app.contains("showMainWindow()"))
        try expect(app.contains("installStatusItem()"))
        try expect(app.contains("AppInstall.offerMoveIfNeeded()"))
        try expect(app.contains("applicationShouldTerminateAfterLastWindowClosed"))
        try expect(app.contains("StandardEditingActions.undo"))
        try expect(app.contains("StandardEditingActions.redo"))
        try expect(app.contains("StandardEditingActions.cut"))
        try expect(app.contains("StandardEditingActions.paste"))
        try expect(app.contains("NSApplication.hide"))
        try expect(app.contains("performMiniaturize"))
        try expect(app.contains("focusSearchFromMenu"))
        try expect(window.contains("allowsUndo = true"))
        try expect(window.contains("hasMarkedText"))
    }
}
