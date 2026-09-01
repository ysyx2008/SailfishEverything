import Foundation
import SailfishEverythingCore

enum ScanPolicyTests {
    static let policy = ScanPolicy.default

    static var cases: [TestCase] {[
        TestCase(name: "单元.跳过缓存", run: skipsCaches),
        TestCase(name: "单元.跳过开发噪音", run: skipsDevNoise),
        TestCase(name: "单元.默认不扫云盘", run: skipsCloudDrives),
        TestCase(name: "单元.本机桌面文稿仍扫", run: keepsLocalFolders),
        TestCase(name: "单元.扫描相对路径不受/var别名影响", run: relativePathResolvesSymlinks),
        TestCase(name: "单元.默认策略来自设置", run: defaultFromSettings),
    ]}

    private static func skipsCaches() throws {
        try expect(policy.shouldSkipDescending(relative: "Library/Caches", name: "Caches"))
        try expect(policy.shouldSkipDescending(relative: "Library/Caches/foo", name: "foo"))
        try expect(policy.shouldSkipDescending(relative: "Library/Containers", name: "Containers"))
    }

    private static func skipsDevNoise() throws {
        try expect(policy.shouldSkipDescending(relative: "src/node_modules", name: "node_modules"))
        try expect(policy.shouldSkipDescending(relative: "proj/.git", name: ".git"))
        try expect(policy.shouldOmitEntry(name: ".git"))
        try expect(!policy.shouldOmitEntry(name: "node_modules"))
    }

    private static func skipsCloudDrives() throws {
        try expect(policy.shouldSkipDescending(
            relative: "Library/CloudStorage",
            name: "CloudStorage"
        ))
        try expect(policy.shouldSkipDescending(
            relative: "Library/CloudStorage/OneDrive-个人",
            name: "OneDrive-个人"
        ))
        try expect(policy.shouldSkipDescending(
            relative: "Library/Mobile Documents",
            name: "Mobile Documents"
        ))
        try expect(policy.shouldSkipDescending(
            relative: "Library/Mobile Documents/com~apple~CloudDocs/Projects",
            name: "Projects"
        ))
    }

    private static func keepsLocalFolders() throws {
        try expect(!policy.shouldSkipDescending(relative: "Desktop", name: "Desktop"))
        try expect(!policy.shouldSkipDescending(relative: "Documents", name: "Documents"))
        try expect(!policy.shouldSkipDescending(relative: "Documents/公司文件", name: "公司文件"))
    }

    private static func relativePathResolvesSymlinks() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("everything-rel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let index = FileIndex()
        let scanner = FileScanner(index: index, root: tmp, enableWatch: false, notifyOnMain: false)
        let nested = tmp.appendingPathComponent("Library/Caches/x").path
        try expectEqual(scanner.relativePath(nested), "Library/Caches/x")
    }

    private static func defaultFromSettings() throws {
        try expectEqual(ScanPolicy.default.skipHiddenFolders, IndexSettings.default.skipHiddenFolders)
        try expect(ScanPolicy.default.skipRelativePrefixes.contains("Library/Caches"))
    }
}
