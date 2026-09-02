import Foundation
import SailfishEverythingCore

enum ShipFlowTests {
    static var cases: [TestCase] {[
        TestCase(name: "端到端.Look in只列出真实存在的位置", run: folderPlacesExist),
        TestCase(name: "端到端.家目录不存在时扫盘失败", run: missingHomeFails),
        TestCase(name: "端到端.云占位仍能定位文件", run: cloudPlaceholderHasPath),
        TestCase(name: "端到端.包装带图标和产品名", run: packagedBrand),
        TestCase(name: "端到端.只有安装盘和下载才问要不要挪位置", run: installOfferLocations),
        TestCase(name: "端到端.限定子目录只出该目录的文件", run: lookInNestedFolder),
        TestCase(name: "端到端.扫盘后按今天修改过的找", run: dateAfterScan),
        TestCase(name: "端到端.parent收窄到真实文件夹", run: parentAfterScan),
        TestCase(name: "端到端.文件信息含路径和云标记", run: fileInfoSummary),
        TestCase(name: "端到端.读不到受保护目录就判定缺权限", run: diskAccessDenied),
    ]}

    private static func folderPlacesExist() throws {
        let root = try FixtureHome.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let places = FolderPlaces.existing(in: root)
        try expect(places.contains(where: { $0.relative.isEmpty }))
        try expect(places.contains(where: { $0.relative == "Desktop" }))
        try expect(places.contains(where: { $0.relative == "Downloads" }))
        try expect(!places.contains(where: { $0.relative == "Pictures" }))
        let downloads = places.first { $0.relative == "Downloads" }!.resolvedPath(in: root)
        let index = FileIndex()
        FileScanner(index: index, root: root, enableWatch: false, notifyOnMain: false).scanSynchronously()
        try expectEqual(index.names(matching: "photo", options: SearchOptions(inFolder: downloads)), ["photo.jpg"])
        try expect(index.names(matching: "会议纪要", options: SearchOptions(inFolder: downloads)).isEmpty)
    }

    private static func missingHomeFails() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("sailfish-missing-\(UUID().uuidString)")
        let recorder = FailRecorder()
        let index = FileIndex()
        let scanner = FileScanner(index: index, root: missing, enableWatch: false, notifyOnMain: false)
        scanner.delegate = recorder
        scanner.scanSynchronously()
        try expect(recorder.failed, "scan should fail when home is missing")
        try expectEqual(index.count, 0)
    }

    private static func cloudPlaceholderHasPath() throws {
        let entry = FileEntry(
            name: "只在云上的合同.pdf",
            directory: "/Users/me/Library/CloudStorage/OneDrive-个人",
            size: 0,
            isCloudOnly: true
        )
        try expect(entry.isCloudOnly)
        try expect(entry.path.contains("合同.pdf"))
        let index = FileIndex()
        index.add([entry])
        try expectEqual(index.names(matching: "合同"), ["只在云上的合同.pdf"])
        try expectEqual(index.names(matching: "size:>1kb"), [])
    }

    private static func packagedBrand() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let icns = repo.appendingPathComponent("Resources/AppIcon.icns")
        try expect(FileManager.default.fileExists(atPath: icns.path), "missing AppIcon.icns")
        let attrs = try FileManager.default.attributesOfItem(atPath: icns.path)
        let size = attrs[.size] as? NSNumber
        try expect((size?.intValue ?? 0) > 1000, "icon too small")
        let plist = try String(contentsOf: repo.appendingPathComponent("Resources/Info.plist"), encoding: .utf8)
        try expect(plist.contains("AppIcon"))
        try expect(plist.contains("Sailfish Everything"))
        try expect(!plist.contains("Namelist"))
        try expect(plist.contains("CFBundleIconFile"))
        try expect(plist.contains("LSMinimumSystemVersion"))
        try expect(plist.contains("14.0"))
        try expect(plist.contains("ITSAppUsesNonExemptEncryption"))
        try expect(FileManager.default.fileExists(atPath: repo.appendingPathComponent("Resources/PrivacyInfo.xcprivacy").path))
        try expect(FileManager.default.fileExists(atPath: repo.appendingPathComponent("Resources/SailfishEverything.entitlements").path))
        let chinese = try String(contentsOf: repo.appendingPathComponent("Resources/zh-Hans.lproj/InfoPlist.strings"), encoding: .utf8)
        try expect(chinese.contains("旗鱼搜索"))
        try expect(!chinese.contains("Namelist"))
    }

    private static func installOfferLocations() throws {
        let home = "/Users/me"
        try expect(AppInstallPolicy.shouldOfferMove(
            bundlePath: "/Volumes/Sailfish Everything/Sailfish Everything.app",
            home: home,
            isE2E: false
        ))
        try expect(AppInstallPolicy.shouldOfferMove(
            bundlePath: home + "/Downloads/Sailfish Everything.app",
            home: home,
            isE2E: false
        ))
        try expect(AppInstallPolicy.shouldOfferMove(
            bundlePath: "/private/var/folders/xx/AppTranslocation/abc/Sailfish Everything.app",
            home: home,
            isE2E: false
        ))
        try expect(!AppInstallPolicy.shouldOfferMove(
            bundlePath: "/Applications/Sailfish Everything.app",
            home: home,
            isE2E: false
        ))
        try expect(!AppInstallPolicy.shouldOfferMove(
            bundlePath: home + "/Applications/Sailfish Everything.app",
            home: home,
            isE2E: false
        ))
        try expect(!AppInstallPolicy.shouldOfferMove(
            bundlePath: "/Users/me/Source/SailfishEverything/.build/release/Sailfish Everything.app",
            home: home,
            isE2E: false
        ))
        try expect(!AppInstallPolicy.shouldOfferMove(
            bundlePath: "/Volumes/Sailfish Everything/Sailfish Everything.app",
            home: home,
            isE2E: true
        ))
    }

    private static func lookInNestedFolder() throws {
        let root = try FixtureHome.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let index = FileIndex()
        FileScanner(index: index, root: root, enableWatch: false, notifyOnMain: false).scanSynchronously()
        let archive = root.appendingPathComponent("Desktop/Archive").resolvingSymlinksInPath().path
        try expectEqual(
            index.names(matching: "archived", options: SearchOptions(inFolder: archive)),
            ["archived.txt"]
        )
        try expect(index.names(matching: "photo", options: SearchOptions(inFolder: archive)).isEmpty)
        try expect(index.names(matching: "会议", options: SearchOptions(inFolder: archive)).isEmpty)
    }

    private static func dateAfterScan() throws {
        let root = try FixtureHome.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let photo = root.appendingPathComponent("Downloads/photo.jpg")
        let old = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: photo.path)
        let index = FileIndex()
        FileScanner(index: index, root: root, enableWatch: false, notifyOnMain: false).scanSynchronously()
        try expect(index.names(matching: "dm:today").contains("会议纪要.docx"))
        try expect(!index.names(matching: "dm:today").contains("photo.jpg"))
        try expect(index.names(matching: "dm:last7days").contains("photo.jpg"))
        try expect(index.names(matching: "dm:yesterday").isEmpty || !index.names(matching: "dm:yesterday").contains("会议纪要.docx"))
    }

    private static func parentAfterScan() throws {
        let root = try FixtureHome.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let index = FileIndex()
        FileScanner(index: index, root: root, enableWatch: false, notifyOnMain: false).scanSynchronously()
        try expectEqual(index.names(matching: "parent:Archive"), ["archived.txt"])
        try expectEqual(index.names(matching: "parent:公司文件"), ["合同.pdf"])
        try expect(!index.names(matching: "name:Projects").contains("设计稿.psd"))
        try expect(index.names(matching: "path:Projects", options: SearchOptions(matchPath: true)).isEmpty)
        try expect(index.names(matching: "path:Work", options: SearchOptions(matchPath: true)).contains("main.swift"))
    }

    private static func fileInfoSummary() throws {
        let cloud = FileEntry(
            name: "只在云上的合同.pdf",
            directory: "/Users/me/Library/CloudStorage/OneDrive-个人",
            size: 0,
            isCloudOnly: true
        )
        let text = FileInfo.summary(cloud)
        try expect(text.contains("只在云上的合同.pdf"))
        try expect(text.contains("OneDrive") || text.contains("CloudStorage"))
        try expect(text.contains("not downloaded"))
        try expect(!text.contains("Namelist"))
    }

    private static func diskAccessDenied() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sailfish-tcc-\(UUID().uuidString)", isDirectory: true)
        let safari = root.appendingPathComponent("Library/Safari")
        try FileManager.default.createDirectory(at: safari, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: safari.path)
            try? FileManager.default.removeItem(at: root)
        }
        try expect(DiskAccess.isFullyTrusted(home: root))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: safari.path)
        try expect(!DiskAccess.isFullyTrusted(home: root))
        let fixture = try FixtureHome.make()
        defer { try? FileManager.default.removeItem(at: fixture) }
        try expect(DiskAccess.isFullyTrusted(home: fixture))
    }
}

private final class FailRecorder: FileScannerDelegate {
    var failed = false
    func scanner(_ scanner: FileScanner, didAdd batch: [FileEntry], total: Int) {}
    func scannerDidFinish(_ scanner: FileScanner, total: Int) {}
    func scannerDidFail(_ scanner: FileScanner, error: Error) { failed = true }
}
