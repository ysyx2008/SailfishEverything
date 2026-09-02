import Foundation
import SailfishEverythingCore

enum L10nTests {
    static var cases: [TestCase] {[
        TestCase(name: "单元.语言跟系统走", run: resolvePreferred),
        TestCase(name: "单元.自动化固定英文", run: bootstrapE2EEnglish),
        TestCase(name: "单元.可强制中文", run: bootstrapOverride),
        TestCase(name: "单元.中英文案都齐", run: bothLanguagesFilled),
        TestCase(name: "单元.状态栏中英不同", run: statusLineLocalized),
        TestCase(name: "单元.扫盘时收录数不跟同样的对象数", run: indexingStatusOmitsDuplicateCount),
    ]}

    private static func resolvePreferred() throws {
        try expectEqual(AppLanguage.resolve(preferred: ["en-US", "zh-Hans"]), .english)
        try expectEqual(AppLanguage.resolve(preferred: ["zh-Hans-CN"]), .chinese)
        try expectEqual(AppLanguage.resolve(preferred: ["zh-Hant-TW", "en"]), .chinese)
        try expectEqual(AppLanguage.resolve(preferred: ["ja-JP"]), .english)
    }

    private static func bootstrapE2EEnglish() throws {
        let previous = L10n.language
        defer { L10n.language = previous }
        L10n.bootstrap(environment: ["SAILFISH_E2E": "1", "SAILFISH_LANG": "zh"])
        try expectEqual(L10n.language, .english)
        try expectEqual(L10n.productName, "Sailfish Everything")
        try expectEqual(L10n.statusItemTitle, "SE")
    }

    private static func bootstrapOverride() throws {
        let previous = L10n.language
        defer { L10n.language = previous }
        L10n.bootstrap(environment: ["SAILFISH_LANG": "zh"])
        try expectEqual(L10n.language, .chinese)
        try expectEqual(L10n.productName, "旗鱼搜索")
        try expectEqual(L10n.statusItemTitle, "旗")
        L10n.bootstrap(environment: ["SAILFISH_LANG": "en"])
        try expectEqual(L10n.productName, "Sailfish Everything")
    }

    private static func bothLanguagesFilled() throws {
        let previous = L10n.language
        defer { L10n.language = previous }
        for key in L10n.Key.allCases {
            L10n.language = .english
            let en = L10n.t(key)
            try expect(!en.isEmpty, "empty English copy for \(key)")
            try expect(!en.contains("Namelist"), key.rawValue)
            L10n.language = .chinese
            let zh = L10n.t(key)
            try expect(!zh.isEmpty, "empty Chinese copy for \(key)")
            try expect(!zh.contains("Namelist"), key.rawValue)
        }
        L10n.language = .english
        try expectEqual(L10n.filterMenu(.all), "All")
        try expectEqual(L10n.folderPlace(""), "All")
        L10n.language = .chinese
        try expectEqual(L10n.filterMenu(.all), "全部")
        try expectEqual(L10n.folderPlace("Desktop"), "桌面")
        try expectEqual(L10n.excludeLabel("Library/Caches"), "资源库 / 缓存")
        try expectEqual(L10n.includeLabel(IndexSettings.wechatChatFilesInclude), "微信聊天文件")
        try expect(!L10n.t(.aboutApp).contains("About Everything"))
    }

    private static func statusLineLocalized() throws {
        let previous = L10n.language
        defer { L10n.language = previous }
        L10n.language = .english
        try expect(L10n.statusLine(objects: 3, selected: 0, bytes: 0).contains("objects"))
        L10n.language = .chinese
        try expect(L10n.statusLine(objects: 3, selected: 0, bytes: 0).contains("个对象"))
        try expect(L10n.statusLine(objects: 12, selected: 2, bytes: 0).contains("已选"))
    }

    private static func indexingStatusOmitsDuplicateCount() throws {
        let previous = L10n.language
        defer { L10n.language = previous }
        L10n.language = .chinese
        let same = L10n.statusLeft(
            objects: 100,
            selected: 0,
            bytes: 0,
            isSearching: false,
            indexingPhase: "个人文件夹",
            indexed: 100
        )
        try expect(same.contains("已收录"))
        try expect(same.contains("个对象"), same)
        try expectEqual(same.components(separatedBy: ResultStats.formatCount(100)).count - 1, 1)
        try expectEqual(same.components(separatedBy: "个对象").count - 1, 1)

        let filtered = L10n.statusLeft(
            objects: 12,
            selected: 0,
            bytes: 0,
            isSearching: false,
            indexingPhase: "个人文件夹",
            indexed: 100
        )
        try expect(filtered.contains("已收录"))
        try expect(filtered.contains("12 个对象"))

        let done = L10n.statusLeft(
            objects: 12,
            selected: 0,
            bytes: 0,
            isSearching: false,
            indexingPhase: nil,
            indexed: 100
        )
        try expectEqual(done, "12 个对象")
    }
}
