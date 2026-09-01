import Foundation
import SailfishEverythingCore

enum IndexSettingsTests {
    static var cases: [TestCase] {[
        TestCase(name: "单元.默认跳过隐藏文件夹", run: defaultSkipsHidden),
        TestCase(name: "单元.关闭后隐藏文件夹可搜", run: canIndexHiddenWhenDisabled),
        TestCase(name: "单元.自定义排除路径", run: extraExclude),
        TestCase(name: "单元.一次扫完整个人文件夹", run: wholeHomeOnce),
        TestCase(name: "单元.恢复默认排除", run: restoreDefaultExcludes),
        TestCase(name: "单元.额外根目录能搜到", run: extraRootIsIndexed),
        TestCase(name: "单元.家目录里的额外根不会扫两遍", run: extraRootInsideHomeIgnored),
        TestCase(name: "单元.不存在的额外根不影响家目录", run: missingExtraRootOk),
        TestCase(name: "单元.旧设置没有额外根也能读", run: decodeLegacySettings),
        TestCase(name: "单元.中文默认快捷键避开输入法", run: chineseHotKeyDefault),
        TestCase(name: "单元.去掉云盘排除后能搜到", run: includeCloudWhenUnexcluded),
    ]}

    private static func defaultSkipsHidden() throws {
        let policy = ScanPolicy.from(.default)
        try expect(policy.skipHiddenFolders)
        try expect(policy.shouldSkipDescending(relative: ".cache", name: ".cache"))
        try expect(policy.shouldSkipDescending(relative: ".npm", name: ".npm"))
        try expect(policy.shouldOmitEntry(name: ".ssh"))
        try expect(!policy.shouldSkipDescending(relative: "Desktop", name: "Desktop"))
    }

    private static func canIndexHiddenWhenDisabled() throws {
        let settings = IndexSettings(skipHiddenFolders: false)
        let policy = ScanPolicy.from(settings)
        try expect(!policy.shouldSkipDescending(relative: ".ssh", name: ".ssh"))
        try expect(!policy.shouldOmitEntry(name: ".ssh"))
        try expect(policy.shouldSkipDescending(relative: "src/node_modules", name: "node_modules"))
    }

    private static func extraExclude() throws {
        let settings = IndexSettings(extraExcludedRelatives: ["ai", "models"])
        let policy = ScanPolicy.from(settings)
        try expect(policy.shouldSkipDescending(relative: "ai", name: "ai"))
        try expect(policy.shouldSkipDescending(relative: "ai/checkpoints", name: "checkpoints"))
        try expect(!policy.shouldSkipDescending(relative: "Source", name: "Source"))
    }

    private static func wholeHomeOnce() throws {
        let root = try FixtureHome.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let index = FileIndex()
        FileScanner(index: index, root: root, enableWatch: false, notifyOnMain: false).scanSynchronously()
        let names = Set(index.names(matching: ""))
        try expect(names.contains("会议纪要.docx"))
        try expect(names.contains("photo.jpg"))
        try expect(names.contains("合同.pdf"))
        try expect(!names.contains("设计稿.psd"))
        try expect(names.contains("main.swift"))
        try expect(!names.contains("secret.bin"))
        try expect(!names.contains("should-not-index.txt"))
        try expect(!names.contains("weights.bin"))
    }

    private static func restoreDefaultExcludes() throws {
        var settings = IndexSettings(skipHiddenFolders: false, extraExcludedRelatives: ["foo"])
        settings = .default
        try expect(settings.skipHiddenFolders)
        try expect(settings.extraExcludedRelatives.isEmpty)
        try expect(settings.displayExcludes().contains("Library/Caches"))
        try expect(settings.displayExcludes().contains("node_modules"))
    }

    private static func extraRootIsIndexed() throws {
        let home = try FixtureHome.make()
        let extra = FileManager.default.temporaryDirectory
            .appendingPathComponent("sailfish-extra-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
        try "outside".data(using: .utf8)!.write(to: extra.appendingPathComponent("外置盘合同.pdf"))
        defer {
            try? FileManager.default.removeItem(at: home)
            try? FileManager.default.removeItem(at: extra)
        }
        let settings = IndexSettings(extraRoots: [extra.path])
        let index = FileIndex()
        FileScanner(index: index, root: home, settings: settings, enableWatch: false, notifyOnMain: false).scanSynchronously()
        try expect(index.names(matching: "外置盘合同").contains("外置盘合同.pdf"))
        try expect(index.names(matching: "photo").contains("photo.jpg"))
        try expectEqual(settings.extraRootURLs(home: home).map(\.path), [extra.resolvingSymlinksInPath().path])
    }

    private static func extraRootInsideHomeIgnored() throws {
        let home = try FixtureHome.make()
        defer { try? FileManager.default.removeItem(at: home) }
        let downloads = home.appendingPathComponent("Downloads").resolvingSymlinksInPath()
        let settings = IndexSettings(extraRoots: [downloads.path])
        try expect(settings.extraRootURLs(home: home).isEmpty)
        let index = FileIndex()
        FileScanner(index: index, root: home, settings: settings, enableWatch: false, notifyOnMain: false).scanSynchronously()
        try expectEqual(index.names(matching: "photo").filter { $0 == "photo.jpg" }.count, 1)
    }

    private static func missingExtraRootOk() throws {
        let home = try FixtureHome.make()
        defer { try? FileManager.default.removeItem(at: home) }
        let settings = IndexSettings(extraRoots: ["/no/such/sailfish-volume"])
        let index = FileIndex()
        FileScanner(index: index, root: home, settings: settings, enableWatch: false, notifyOnMain: false).scanSynchronously()
        try expect(index.names(matching: "photo").contains("photo.jpg"))
        try expect(index.count > 0)
    }

    private static func decodeLegacySettings() throws {
        let json = #"{ "skipHiddenFolders": false, "extraExcludedRelatives": ["foo"] }"#.data(using: .utf8)!
        let settings = try JSONDecoder().decode(IndexSettings.self, from: json)
        try expect(!settings.skipHiddenFolders)
        try expectEqual(settings.extraExcludedRelatives, ["foo"])
        try expect(settings.extraRoots.isEmpty)
        try expectEqual(IndexSettings.resolvedLookIn("/Volumes/USB", home: URL(fileURLWithPath: "/Users/me")), "/Volumes/USB")
        try expectEqual(IndexSettings.resolvedLookIn("", home: URL(fileURLWithPath: "/Users/me")), "")
    }

    private static func includeCloudWhenUnexcluded() throws {
        let root = try FixtureHome.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = IndexSettings(
            disabledDefaultPrefixes: ["Library/CloudStorage", "Library/Mobile Documents"]
        )
        let index = FileIndex()
        FileScanner(index: index, root: root, settings: settings, enableWatch: false, notifyOnMain: false).scanSynchronously()
        try expect(index.names(matching: "设计稿").contains("设计稿.psd"))
        try expect(index.names(matching: "path:OneDrive 合同").contains("合同.pdf"))
        try expect(index.names(matching: "notes").contains("notes.txt"))
    }

    private static func chineseHotKeyDefault() throws {
        try expectEqual(AppHotKey.preferredDefault(language: .chinese), .optionSpace)
        try expectEqual(AppHotKey.preferredDefault(language: .english), .controlSpace)
        let suite = "sailfish.hotkey.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try expectEqual(AppHotKeyStore.load(defaults: defaults, language: .chinese), .optionSpace)
        AppHotKeyStore.save(.commandShiftSpace, defaults: defaults)
        try expectEqual(AppHotKeyStore.load(defaults: defaults, language: .chinese), .commandShiftSpace)
    }
}
