import Foundation
import EverythingCore

enum ScanPolicyTests {
    static let policy = ScanPolicy.default

    static var cases: [TestCase] {[
        TestCase(name: "单元.跳过缓存", run: skipsCaches),
        TestCase(name: "单元.跳过开发噪音", run: skipsDevNoise),
        TestCase(name: "单元.iCloud桌面不重复扫", run: skipsICloudDesktopDupes),
        TestCase(name: "单元.保留云盘根", run: keepsCloudRoots),
        TestCase(name: "单元.扫描相对路径不受/var别名影响", run: relativePathResolvesSymlinks),
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

    private static func skipsICloudDesktopDupes() throws {
        try expect(policy.shouldSkipDescending(
            relative: "Library/Mobile Documents/com~apple~CloudDocs/Desktop",
            name: "Desktop"
        ))
        try expect(policy.shouldSkipDescending(
            relative: "Library/Mobile Documents/com~apple~CloudDocs/Documents/foo",
            name: "foo"
        ))
        try expect(policy.shouldSkipDescending(
            relative: "Library/Mobile Documents/com~apple~CloudDocs/Downloads",
            name: "Downloads"
        ))
    }

    private static func keepsCloudRoots() throws {
        try expect(!policy.shouldSkipDescending(
            relative: "Library/CloudStorage/OneDrive-个人",
            name: "OneDrive-个人"
        ))
        try expect(!policy.shouldSkipDescending(
            relative: "Library/Mobile Documents/com~apple~CloudDocs/Projects",
            name: "Projects"
        ))
        try expect(!policy.shouldSkipDescending(relative: "Desktop", name: "Desktop"))
        try expect(!policy.shouldSkipDescending(relative: "Documents", name: "Documents"))
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
}
