import Foundation
import SailfishEverythingCore

enum PathDisplayTests {
    static let home = "/Users/tester"

    static var cases: [TestCase] {[
        TestCase(name: "单元.家目录收成~", run: homeTilde),
        TestCase(name: "单元.iCloud Drive路径", run: iCloudDrive),
        TestCase(name: "单元.OneDrive路径", run: oneDrive),
        TestCase(name: "单元.其他iCloud容器", run: otherICloudContainer),
        TestCase(name: "单元.大小格式", run: folderSizeEmpty),
        TestCase(name: "单元.日期空值", run: emptyDate),
    ]}

    private static func homeTilde() throws {
        try expectEqual(PathDisplay.pretty("/Users/tester/Desktop", home: home), "~/Desktop")
        try expectEqual(PathDisplay.pretty("/Users/tester", home: home), "~")
    }

    private static func iCloudDrive() throws {
        let dir = home + "/Library/Mobile Documents/com~apple~CloudDocs/Projects"
        try expectEqual(PathDisplay.pretty(dir, home: home), "iCloud Drive/Projects")
    }

    private static func oneDrive() throws {
        let dir = home + "/Library/CloudStorage/OneDrive-个人/公司文件"
        try expectEqual(PathDisplay.pretty(dir, home: home), "OneDrive - 个人/公司文件")
    }

    private static func otherICloudContainer() throws {
        let dir = home + "/Library/Mobile Documents/com~apple~Pages"
        try expectEqual(PathDisplay.pretty(dir, home: home), "iCloud/com~apple~Pages")
    }

    private static func folderSizeEmpty() throws {
        try expectEqual(PathDisplay.formatSize(4096, isDirectory: true), "")
        try expectEqual(PathDisplay.formatSize(nil, isDirectory: false), "")
        try expectEqual(PathDisplay.formatSize(800, isDirectory: false), "800 B")
        try expectEqual(PathDisplay.formatSize(2048, isDirectory: false), "2 KB")
        try expectEqual(PathDisplay.formatSize(1_572_864, isDirectory: false), "1.5 MB")
    }

    private static func emptyDate() throws {
        try expectEqual(PathDisplay.formatDate(nil), "")
        let date = Date(timeIntervalSince1970: 1_704_067_200)
        try expect(!PathDisplay.formatDate(date).isEmpty)
    }
}
