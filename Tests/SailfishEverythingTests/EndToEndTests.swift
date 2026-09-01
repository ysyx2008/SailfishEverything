import Foundation
import SailfishEverythingCore

enum EndToEndTests {
    static var cases: [TestCase] {[
        TestCase(name: "端到端.边敲边出带路径", run: typeFilenameSeePaths),
        TestCase(name: "端到端.按文件夹名收窄", run: matchPathFindsFolder),
        TestCase(name: "端到端.增删后名单跟着变", run: addAndRemoveLikeFilesystem),
        TestCase(name: "端到端.云上未下载也能搜", run: cloudOnlyStillSearchable),
        TestCase(name: "端到端.整份个人文件夹一次扫完", run: scansWholeHomeOnce),
        TestCase(name: "端到端.隐藏缓存默认搜不到", run: hiddenCacheNotIndexed),
    ]}

    private static func typeFilenameSeePaths() throws {
        let root = try FixtureHome.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let index = FileIndex()
        FileScanner(index: index, root: root, enableWatch: false, notifyOnMain: false).scanSynchronously()

        var previous: SearchCursor?
        var last: [FileEntry] = []
        for query in ["", "合", "合同"] {
            let indices = index.search(query: query, previous: previous)
            last = index.entries(at: indices)
            previous = SearchCursor(query: query, indices: indices)
        }

        try expectEqual(last.map(\.name), ["合同.pdf"])
        let pretty = PathDisplay.pretty(last[0].directory, home: root.path)
        try expect(pretty.contains("公司文件"), pretty)
        try expect(!pretty.contains("OneDrive"), pretty)
    }

    private static func matchPathFindsFolder() throws {
        let root = try FixtureHome.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let index = FileIndex()
        FileScanner(index: index, root: root, enableWatch: false, notifyOnMain: false).scanSynchronously()

        try expect(!index.names(matching: "Projects").contains("设计稿.psd"))
        try expect(index.names(matching: "Projects", options: SearchOptions(matchPath: true)).isEmpty)
        try expect(index.names(matching: "Work", options: SearchOptions(matchPath: true)).contains("main.swift"))
    }

    private static func addAndRemoveLikeFilesystem() throws {
        let root = try FixtureHome.make()
        defer { try? FileManager.default.removeItem(at: root) }

        let index = FileIndex()
        let scanner = FileScanner(index: index, root: root, enableWatch: false, notifyOnMain: false)
        scanner.scanSynchronously()
        try expectEqual(index.names(matching: "photo"), ["photo.jpg"])

        let photo = root.appendingPathComponent("Downloads/photo.jpg").resolvingSymlinksInPath()
        try FileManager.default.removeItem(at: photo)
        index.remove(paths: [photo.path])
        try expect(index.names(matching: "photo").isEmpty)

        let newborn = root.appendingPathComponent("Desktop/新会议.txt")
        try "hello".data(using: .utf8)!.write(to: newborn)
        index.reset()
        scanner.scanSynchronously()
        try expectEqual(index.names(matching: "新会议"), ["新会议.txt"])
        try expect(index.names(matching: "photo").isEmpty)
    }

    private static func cloudOnlyStillSearchable() throws {
        let index = FileIndex()
        index.add([
            FileEntry(
                name: "只在云上的合同.pdf",
                directory: "/Users/me/Library/CloudStorage/OneDrive-个人",
                size: 0,
                isCloudOnly: true
            ),
        ])
        try expectEqual(index.names(matching: "合同"), ["只在云上的合同.pdf"])
        try expect(index.entry(at: 0)?.isCloudOnly == true)
    }

    private static func scansWholeHomeOnce() throws {
        let root = try FixtureHome.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = PhaseRecorder()
        let index = FileIndex()
        let scanner = FileScanner(index: index, root: root, enableWatch: false, notifyOnMain: false)
        scanner.delegate = recorder
        scanner.scanSynchronously()
        try expectEqual(recorder.phases, [L10n.t(.homeFolder)])
        try expect(index.names(matching: "会议纪要").contains("会议纪要.docx"))
        try expect(index.names(matching: "合同").contains("合同.pdf"))
        try expect(index.names(matching: "main").contains("main.swift"))
        try expect(index.names(matching: "secret").isEmpty)
    }

    private static func hiddenCacheNotIndexed() throws {
        let root = try FixtureHome.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let index = FileIndex()
        FileScanner(index: index, root: root, enableWatch: false, notifyOnMain: false).scanSynchronously()
        try expect(index.names(matching: "weights").isEmpty)
        try expect(Set(index.names(matching: "会议纪要")).isSuperset(of: ["会议纪要.docx", "Q3 会议纪要.docx"]))

        let included = FileIndex()
        FileScanner(
            index: included,
            root: root,
            settings: IndexSettings(skipHiddenFolders: false),
            enableWatch: false,
            notifyOnMain: false
        ).scanSynchronously()
        try expect(included.names(matching: "weights") == ["weights.bin"])
    }
}

private final class PhaseRecorder: FileScannerDelegate {
    var phases: [String] = []

    func scanner(_ scanner: FileScanner, didAdd batch: [FileEntry], total: Int) {}
    func scannerDidFinish(_ scanner: FileScanner, total: Int) {}
    func scannerDidFail(_ scanner: FileScanner, error: Error) {}
    func scanner(_ scanner: FileScanner, didBeginPhase title: String) {
        phases.append(title)
    }
}
