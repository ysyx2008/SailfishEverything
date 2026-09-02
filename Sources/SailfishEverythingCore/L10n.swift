import Foundation

public enum AppLanguage: String, Sendable, Equatable {
    case english
    case chinese

    public static func resolve(preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        for lang in preferred {
            let lower = lang.lowercased()
            if lower.hasPrefix("zh") { return .chinese }
            if lower.hasPrefix("en") { return .english }
        }
        return .english
    }
}

public enum L10n {
    public static var language: AppLanguage = .resolve()

    public static let productNameEnglish = "Sailfish Everything"
    public static let productNameChinese = "旗鱼搜索"

    public static var productName: String {
        language == .chinese ? productNameChinese : productNameEnglish
    }

    public static var statusItemTitle: String {
        language == .chinese ? "旗" : "SE"
    }

    public static func bootstrap(environment: [String: String] = ProcessInfo.processInfo.environment) {
        if environment["SAILFISH_E2E"] == "1" {
            language = .english
            return
        }
        switch environment["SAILFISH_LANG"]?.lowercased() {
        case "zh", "zh-hans", "zh_cn", "chinese":
            language = .chinese
        case "en", "english":
            language = .english
        default:
            language = .resolve()
        }
    }

    public static func t(_ key: Key) -> String {
        language == .chinese ? key.zh : key.en
    }

    public static func format(_ key: Key, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }

    public static func statusLine(objects: Int, selected: Int, bytes: Int64) -> String {
        let count = ResultStats.formatCount(selected > 0 ? selected : objects)
        let total = ResultStats.formatCount(objects)
        var text: String
        if language == .chinese {
            text = selected > 0 ? "已选 \(count) / \(total) 个对象" : "\(count) 个对象"
        } else {
            text = selected > 0 ? "\(count) of \(total) objects selected" : "\(count) objects"
        }
        if bytes > 0 {
            text += " (\(PathDisplay.formatSize(bytes, isDirectory: false)))"
        }
        return text
    }

    public static func filterMenu(_ filter: ResultFilter) -> String {
        switch filter {
        case .all: return t(.filterAll)
        case .audio: return t(.filterAudio)
        case .compressed: return t(.filterCompressed)
        case .document: return t(.filterDocument)
        case .executable: return t(.filterExecutable)
        case .folder: return t(.filterFolder)
        case .picture: return t(.filterPicture)
        case .video: return t(.filterVideo)
        }
    }

    public static func folderPlace(_ relative: String) -> String {
        switch relative {
        case "": return t(.placeAll)
        case "Desktop": return t(.placeDesktop)
        case "Documents": return t(.placeDocuments)
        case "Downloads": return t(.placeDownloads)
        case "Pictures": return t(.placePictures)
        case "Movies": return t(.placeMovies)
        case "Music": return t(.placeMusic)
        case "Library/Mobile Documents/com~apple~CloudDocs": return t(.placeICloud)
        case "Library/CloudStorage": return t(.placeOneDrive)
        default: return relative
        }
    }

    public static func excludeLabel(_ relative: String) -> String {
        switch relative {
        case "Library/Caches": return t(.excludeCaches)
        case "Library/Logs": return t(.excludeLogs)
        case "Library/Developer": return t(.excludeDeveloper)
        case "Library/Containers": return t(.excludeContainers)
        case "Library/Metadata": return t(.excludeMetadata)
        case "Library/Mail": return t(.excludeMail)
        case "Library/Safari": return t(.excludeSafari)
        case "Library/HTTPStorages": return t(.excludeHTTP)
        case "Library/WebKit": return t(.excludeWebKit)
        case "Library/CloudStorage": return t(.excludeCloudStorage)
        case "Library/Mobile Documents": return t(.excludeICloudDrive)
        case "Library/Mobile Documents/com~apple~CloudDocs/Desktop": return t(.excludeICloudDesktop)
        case "Library/Mobile Documents/com~apple~CloudDocs/Documents": return t(.excludeICloudDocuments)
        case "Library/Mobile Documents/com~apple~CloudDocs/Downloads": return t(.excludeICloudDownloads)
        default: return relative
        }
    }

    public static func includeLabel(_ item: String) -> String {
        switch item {
        case IndexSettings.wechatChatFilesInclude: return t(.includeWeChatChatFiles)
        default: return item
        }
    }

    public enum Key: String, CaseIterable, Sendable {
        case showApp
        case quitApp
        case aboutApp
        case settings
        case helpApp
        case fileMenu
        case editMenu
        case viewMenu
        case searchMenu
        case bookmarksMenu
        case toolsMenu
        case indexMenu
        case helpMenu
        case open
        case openPath
        case quickLook
        case getInfo
        case export
        case close
        case exit
        case copy
        case copyFullName
        case copyPath
        case selectAll
        case refresh
        case sortName
        case sortPath
        case sortSize
        case sortDate
        case matchCase
        case matchWholeWord
        case matchPath
        case enableRegex
        case lookIn
        case addBookmark
        case addBookmarkTitle
        case removeBookmark
        case searchPlaceholder
        case indexedCount
        case options
        case rebuildIndex
        case fullDiskAccess
        case searchSyntax
        case rename
        case moveToTrash
        case ok
        case cancel
        case untitled
        case columnName
        case columnPath
        case columnSize
        case columnModified
        case indexing
        case searching
        case openDiagnosticLog
        case invalidRegex
        case homeFolder
        case aboutBody
        case syntaxTitle
        case syntaxBody
        case settingsTitle
        case skipHidden
        case preferOpened
        case launchAtLogin
        case openFullDiskAccess
        case diskAccessOK
        case diskAccessNeeded
        case scanHint
        case excludedFolders
        case add
        case remove
        case restoreDefaults
        case done
        case excludePrompt
        case excludeMessage
        case extraFolders
        case extraFolderPrompt
        case extraFolderMessage
        case chooseFolder
        case includeWeChatChatFiles
        case hotKey
        case hotKeyControlSpace
        case hotKeyOptionSpace
        case hotKeyCommandShiftSpace
        case hotKeyControlOptionSpace
        case onboardingBody
        case onboardingFDA
        case filterAll
        case filterAudio
        case filterCompressed
        case filterDocument
        case filterExecutable
        case filterFolder
        case filterPicture
        case filterVideo
        case placeAll
        case placeDesktop
        case placeDocuments
        case placeDownloads
        case placePictures
        case placeMovies
        case placeMusic
        case placeICloud
        case placeOneDrive
        case excludeCaches
        case excludeLogs
        case excludeDeveloper
        case excludeContainers
        case excludeMetadata
        case excludeMail
        case excludeSafari
        case excludeHTTP
        case excludeWebKit
        case excludeCloudStorage
        case excludeICloudDrive
        case excludeICloudDesktop
        case excludeICloudDocuments
        case excludeICloudDownloads
        case infoName
        case infoPath
        case infoFolder
        case infoType
        case infoTypeFolder
        case infoSize
        case infoModified
        case infoCreated
        case infoCloud
        case infoItems
        case homeMissing
        case scanFailed
        case exportFilename
        case needFullDiskAccess
        case cloudSuffix

        var en: String { Self.english[self] ?? rawValue }
        var zh: String { Self.chinese[self] ?? en }

        private static let english: [Key: String] = [
            .showApp: "Show \(L10n.productNameEnglish)",
            .quitApp: "Quit \(L10n.productNameEnglish)",
            .aboutApp: "About \(L10n.productNameEnglish)",
            .settings: "Settings…",
            .helpApp: "\(L10n.productNameEnglish) Help",
            .fileMenu: "File",
            .editMenu: "Edit",
            .viewMenu: "View",
            .searchMenu: "Search",
            .bookmarksMenu: "Bookmarks",
            .toolsMenu: "Tools",
            .indexMenu: "Index",
            .helpMenu: "Help",
            .open: "Open",
            .openPath: "Open Path",
            .quickLook: "Quick Look",
            .getInfo: "Get Info",
            .export: "Export…",
            .close: "Close",
            .exit: "Exit",
            .copy: "Copy",
            .copyFullName: "Copy Full Name to Clipboard",
            .copyPath: "Copy Path to Clipboard",
            .selectAll: "Select All",
            .refresh: "Refresh",
            .sortName: "Sort by Name",
            .sortPath: "Sort by Path",
            .sortSize: "Sort by Size",
            .sortDate: "Sort by Date Modified",
            .matchCase: "Match Case",
            .matchWholeWord: "Match Whole Word",
            .matchPath: "Match Path",
            .enableRegex: "Enable Regex",
            .lookIn: "Look in",
            .addBookmark: "Add to Bookmarks…",
            .addBookmarkTitle: "Add Bookmark",
            .removeBookmark: "Remove Bookmark",
            .searchPlaceholder: "Type a filename",
            .indexedCount: "%@ indexed · ",
            .options: "Options…",
            .rebuildIndex: "Rebuild Index",
            .fullDiskAccess: "Full Disk Access…",
            .searchSyntax: "Search Syntax",
            .rename: "Rename",
            .moveToTrash: "Move to Trash",
            .ok: "OK",
            .cancel: "Cancel",
            .untitled: "Untitled",
            .columnName: "Name",
            .columnPath: "Path",
            .columnSize: "Size",
            .columnModified: "Date Modified",
            .indexing: "Indexing %@… ",
            .searching: "Searching… ",
            .openDiagnosticLog: "Open Diagnostic Log",
            .invalidRegex: "Invalid regex · ",
            .homeFolder: "Home folder",
            .aboutBody: "Filename search for Mac.\nType to filter. The toggle hotkey is in Settings.\nIndexes your home folder. Cloud drives such as iCloud and OneDrive are skipped by default — they are too slow. Extra disks can be added in Settings.\n© 2026 Sailfish",
            .syntaxTitle: "Search Syntax",
            .syntaxBody: """
            space / AND = AND    | / OR = OR    ! / NOT = NOT
            "exact phrase"    ext:pdf;docx    exact:readme.md
            startwith:Q3    endwith:.pdf    len:>12    empty:
            size:>10mb    dm:today    dc:last7days
            path:Downloads    parent:Archive    name:合同
            file:    folder:    regex:会议.+    wildcards * ?
            Enable Regex in the Search menu to treat the whole query as a regular expression.
            """,
            .settingsTitle: "Settings",
            .skipHidden: "Skip hidden folders (.cache, .npm, …)",
            .preferOpened: "Show opened files first",
            .launchAtLogin: "Open \(L10n.productNameEnglish) at login",
            .openFullDiskAccess: "Open Full Disk Access…",
            .diskAccessOK: "Protected folders are readable.",
            .diskAccessNeeded: "Without Full Disk Access, Library and some system locations will be incomplete.",
            .scanHint: "Indexes your home folder. Cloud drives such as iCloud and OneDrive are skipped by default — they are too slow. Remove them from the exclude list if you want them searched. WeChat chat files are included by default. If you remove that item, add it back from the same list — you do not need to find the folder yourself. Other folders can be added even if they sit inside an excluded area.",
            .excludedFolders: "Excluded folders",
            .add: "Add…",
            .remove: "Remove",
            .restoreDefaults: "Restore Defaults",
            .done: "Done",
            .excludePrompt: "Exclude",
            .excludeMessage: "Choose a folder to exclude from the index",
            .extraFolders: "Also index these folders",
            .extraFolderPrompt: "Index",
            .extraFolderMessage: "Choose a folder or disk to include. Folders inside an excluded area are allowed.",
            .chooseFolder: "Choose Folder…",
            .includeWeChatChatFiles: "WeChat chat files",
            .hotKey: "Toggle window",
            .hotKeyControlSpace: "Control-Space",
            .hotKeyOptionSpace: "Option-Space",
            .hotKeyCommandShiftSpace: "Command-Shift-Space",
            .hotKeyControlOptionSpace: "Control-Option-Space",
            .onboardingBody: "Indexes your home folder so you can find files by name as you type.\nClosing or minimizing the window hides it to the icon at the top-right of the screen — the app keeps running. Click that icon to bring it back. Chinese input often uses Control-Space, so the default toggle is Option-Space. Change it in Settings.\nWithout Full Disk Access, some protected folders will be missing.",
            .onboardingFDA: "Open Full Disk Access…",
            .filterAll: "All",
            .filterAudio: "Audio",
            .filterCompressed: "Compressed",
            .filterDocument: "Document",
            .filterExecutable: "Executable",
            .filterFolder: "Folder",
            .filterPicture: "Picture",
            .filterVideo: "Video",
            .placeAll: "All",
            .placeDesktop: "Desktop",
            .placeDocuments: "Documents",
            .placeDownloads: "Downloads",
            .placePictures: "Pictures",
            .placeMovies: "Movies",
            .placeMusic: "Music",
            .placeICloud: "iCloud Drive",
            .placeOneDrive: "OneDrive",
            .excludeCaches: "Library / Caches",
            .excludeLogs: "Library / Logs",
            .excludeDeveloper: "Library / Developer",
            .excludeContainers: "Library / Containers",
            .excludeMetadata: "Library / Metadata",
            .excludeMail: "Library / Mail",
            .excludeSafari: "Library / Safari",
            .excludeHTTP: "Library / Network caches",
            .excludeWebKit: "Library / WebKit",
            .excludeCloudStorage: "Cloud storage (OneDrive, …)",
            .excludeICloudDrive: "iCloud Drive",
            .excludeICloudDesktop: "iCloud copy of Desktop",
            .excludeICloudDocuments: "iCloud copy of Documents",
            .excludeICloudDownloads: "iCloud copy of Downloads",
            .infoName: "Name: %@",
            .infoPath: "Path: %@",
            .infoFolder: "Folder: %@",
            .infoType: "Type: %@",
            .infoTypeFolder: "Folder",
            .infoSize: "Size: %@",
            .infoModified: "Modified: %@",
            .infoCreated: "Created: %@",
            .infoCloud: "Cloud: not downloaded",
            .infoItems: "%d items",
            .homeMissing: "Home folder is missing or unreadable",
            .scanFailed: "Could not start scan",
            .exportFilename: "results",
            .needFullDiskAccess: "Full Disk Access needed",
            .cloudSuffix: "  · cloud",
        ]

        private static let chinese: [Key: String] = [
            .showApp: "显示\(L10n.productNameChinese)",
            .quitApp: "退出\(L10n.productNameChinese)",
            .aboutApp: "关于\(L10n.productNameChinese)",
            .settings: "设置…",
            .helpApp: "\(L10n.productNameChinese)帮助",
            .fileMenu: "文件",
            .editMenu: "编辑",
            .viewMenu: "显示",
            .searchMenu: "搜索",
            .bookmarksMenu: "书签",
            .toolsMenu: "工具",
            .indexMenu: "索引",
            .helpMenu: "帮助",
            .open: "打开",
            .openPath: "打开所在位置",
            .quickLook: "快速查看",
            .getInfo: "显示简介",
            .export: "导出…",
            .close: "关闭",
            .exit: "退出",
            .copy: "拷贝",
            .copyFullName: "拷贝完整路径",
            .copyPath: "拷贝所在文件夹",
            .selectAll: "全选",
            .refresh: "刷新",
            .sortName: "按名称排序",
            .sortPath: "按路径排序",
            .sortSize: "按大小排序",
            .sortDate: "按修改日期排序",
            .matchCase: "区分大小写",
            .matchWholeWord: "全字匹配",
            .matchPath: "匹配路径",
            .enableRegex: "启用正则",
            .lookIn: "搜索位置",
            .addBookmark: "加入书签…",
            .addBookmarkTitle: "加入书签",
            .removeBookmark: "删除书签",
            .searchPlaceholder: "输入文件名",
            .indexedCount: "已收录 %@ · ",
            .options: "选项…",
            .rebuildIndex: "重建索引",
            .fullDiskAccess: "完全磁盘访问…",
            .searchSyntax: "搜索语法",
            .rename: "重新命名",
            .moveToTrash: "移到废纸篓",
            .ok: "好",
            .cancel: "取消",
            .untitled: "未命名",
            .columnName: "名称",
            .columnPath: "路径",
            .columnSize: "大小",
            .columnModified: "修改日期",
            .indexing: "正在索引%@… ",
            .searching: "正在搜索… ",
            .openDiagnosticLog: "打开诊断日志",
            .invalidRegex: "正则无效 · ",
            .homeFolder: "个人文件夹",
            .aboutBody: "Mac 上的文件名搜索。\n边敲边出。唤出窗口的快捷键在设置里改。\n索引个人文件夹。iCloud、OneDrive 这类云盘默认不扫，太慢。外置盘可在设置里另外添加。\n© 2026 旗鱼",
            .syntaxTitle: "搜索语法",
            .syntaxBody: """
            空格 / AND = 并且    | / OR = 或者    ! / NOT = 排除
            "精确短语"    ext:pdf;docx    exact:readme.md
            startwith:Q3    endwith:.pdf    len:>12    empty:
            size:>10mb    dm:today    dc:last7days
            path:Downloads    parent:Archive    name:合同
            file:    folder:    regex:会议.+    通配符 * ?
            在搜索菜单里打开正则后，整句按正则处理。
            """,
            .settingsTitle: "设置",
            .skipHidden: "跳过隐藏文件夹（.cache、.npm 等）",
            .preferOpened: "打开过的排前面",
            .launchAtLogin: "登录时打开\(L10n.productNameChinese)",
            .openFullDiskAccess: "打开「完全磁盘访问」…",
            .diskAccessOK: "已能读取受保护的文件夹。",
            .diskAccessNeeded: "没开完全磁盘访问时，资源库和部分系统位置会搜不全。",
            .scanHint: "只扫个人文件夹。iCloud、OneDrive 这类云盘默认不扫，太慢；要搜的话从排除列表里去掉。缓存和开发目录默认也跳过。微信聊天文件默认会搜；去掉之后从纳入列表的添加里加回来即可，不必自己去翻。排除范围内的文件夹也可以单独加进来。",
            .excludedFolders: "排除的文件夹",
            .add: "添加…",
            .remove: "移除",
            .restoreDefaults: "恢复默认",
            .done: "完成",
            .excludePrompt: "排除",
            .excludeMessage: "选择要从索引里排除的文件夹",
            .extraFolders: "也索引这些文件夹",
            .extraFolderPrompt: "索引",
            .extraFolderMessage: "选择要加入索引的文件夹或磁盘。落在排除范围内的也可以。",
            .chooseFolder: "选择文件夹…",
            .includeWeChatChatFiles: "微信聊天文件",
            .hotKey: "显示或隐藏窗口",
            .hotKeyControlSpace: "Control-Space",
            .hotKeyOptionSpace: "Option-Space",
            .hotKeyCommandShiftSpace: "Command-Shift-Space",
            .hotKeyControlOptionSpace: "Control-Option-Space",
            .onboardingBody: "会索引个人文件夹，边敲边出按文件名查找。\n关掉或最小化窗口会收到屏幕右上角，图标一直在，程序继续跑。点那个图标就能回来。中文输入法常用 Control-Space，所以默认快捷键是 Option-Space，可在设置里改。\n没开完全磁盘访问时，部分受保护的文件夹会搜不到。",
            .onboardingFDA: "打开「完全磁盘访问」…",
            .filterAll: "全部",
            .filterAudio: "音频",
            .filterCompressed: "压缩包",
            .filterDocument: "文档",
            .filterExecutable: "可执行文件",
            .filterFolder: "文件夹",
            .filterPicture: "图片",
            .filterVideo: "视频",
            .placeAll: "全部",
            .placeDesktop: "桌面",
            .placeDocuments: "文稿",
            .placeDownloads: "下载",
            .placePictures: "图片",
            .placeMovies: "影片",
            .placeMusic: "音乐",
            .placeICloud: "iCloud 云盘",
            .placeOneDrive: "OneDrive",
            .excludeCaches: "资源库 / 缓存",
            .excludeLogs: "资源库 / 日志",
            .excludeDeveloper: "资源库 / 开发者文件",
            .excludeContainers: "资源库 / 容器",
            .excludeMetadata: "资源库 / 元数据",
            .excludeMail: "资源库 / 邮件底层",
            .excludeSafari: "资源库 / Safari",
            .excludeHTTP: "资源库 / 网络缓存",
            .excludeWebKit: "资源库 / WebKit",
            .excludeCloudStorage: "云盘（OneDrive 等）",
            .excludeICloudDrive: "iCloud 云盘",
            .excludeICloudDesktop: "iCloud 里与桌面重复的一份",
            .excludeICloudDocuments: "iCloud 里与文稿重复的一份",
            .excludeICloudDownloads: "iCloud 里与下载重复的一份",
            .infoName: "名称：%@",
            .infoPath: "路径：%@",
            .infoFolder: "文件夹：%@",
            .infoType: "类型：%@",
            .infoTypeFolder: "文件夹",
            .infoSize: "大小：%@",
            .infoModified: "修改：%@",
            .infoCreated: "创建：%@",
            .infoCloud: "云端：未下载",
            .infoItems: "%d 项",
            .homeMissing: "找不到个人文件夹，或无法读取",
            .scanFailed: "无法开始扫描",
            .exportFilename: "结果",
            .needFullDiskAccess: "需要完全磁盘访问",
            .cloudSuffix: "  · 云端",
        ]
    }
}
