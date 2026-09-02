import Foundation

public struct IndexSettings: Codable, Equatable, Sendable {
    public var skipHiddenFolders: Bool
    public var extraExcludedRelatives: [String]
    public var disabledDefaultPrefixes: [String]
    public var disabledDefaultNames: [String]
    public var extraRoots: [String]
    public var disabledDefaultIncludes: [String]
    public var preferOpened: Bool

    public static let wechatChatFilesInclude = "wechatChatFiles"
    public static let defaultIncludeKeys = [wechatChatFilesInclude]

    public static let `default` = IndexSettings(
        skipHiddenFolders: true,
        extraExcludedRelatives: [],
        disabledDefaultPrefixes: [],
        disabledDefaultNames: [],
        extraRoots: [],
        disabledDefaultIncludes: [],
        preferOpened: true
    )

    public init(
        skipHiddenFolders: Bool = true,
        extraExcludedRelatives: [String] = [],
        disabledDefaultPrefixes: [String] = [],
        disabledDefaultNames: [String] = [],
        extraRoots: [String] = [],
        disabledDefaultIncludes: [String] = [],
        preferOpened: Bool = true
    ) {
        self.skipHiddenFolders = skipHiddenFolders
        self.extraExcludedRelatives = extraExcludedRelatives
        self.disabledDefaultPrefixes = disabledDefaultPrefixes
        self.disabledDefaultNames = disabledDefaultNames
        self.extraRoots = extraRoots
        self.disabledDefaultIncludes = disabledDefaultIncludes
        self.preferOpened = preferOpened
    }

    enum CodingKeys: String, CodingKey {
        case skipHiddenFolders, extraExcludedRelatives, disabledDefaultPrefixes, disabledDefaultNames, extraRoots, disabledDefaultIncludes, preferOpened
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        skipHiddenFolders = try container.decodeIfPresent(Bool.self, forKey: .skipHiddenFolders) ?? true
        extraExcludedRelatives = try container.decodeIfPresent([String].self, forKey: .extraExcludedRelatives) ?? []
        disabledDefaultPrefixes = try container.decodeIfPresent([String].self, forKey: .disabledDefaultPrefixes) ?? []
        disabledDefaultNames = try container.decodeIfPresent([String].self, forKey: .disabledDefaultNames) ?? []
        extraRoots = try container.decodeIfPresent([String].self, forKey: .extraRoots) ?? []
        disabledDefaultIncludes = try container.decodeIfPresent([String].self, forKey: .disabledDefaultIncludes) ?? []
        preferOpened = try container.decodeIfPresent(Bool.self, forKey: .preferOpened) ?? true
    }

    public func extraRootURLs(home: URL, fileManager: FileManager = .default) -> [URL] {
        let homePath = home.resolvingSymlinksInPath().path
        var seen = Set<String>()
        var urls: [URL] = []

        func append(_ url: URL) {
            let path = url.resolvingSymlinksInPath().path
            if !seen.insert(path).inserted { return }
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return }
            urls.append(URL(fileURLWithPath: path, isDirectory: true))
        }

        for url in resolvedDefaultIncludeURLs(home: home, fileManager: fileManager) {
            append(url)
        }
        for raw in extraRoots {
            let url = URL(fileURLWithPath: raw, isDirectory: true).resolvingSymlinksInPath()
            let path = url.path
            if path == homePath { continue }
            if path.hasPrefix(homePath + "/") {
                let relative = String(path.dropFirst(homePath.count + 1))
                if homeWalkCovers(relative) { continue }
            }
            append(url)
        }
        return urls
    }

    public func resolvedDefaultIncludeURLs(home: URL, fileManager: FileManager = .default) -> [URL] {
        var urls: [URL] = []
        if !disabledDefaultIncludes.contains(Self.wechatChatFilesInclude) {
            urls.append(contentsOf: Self.wechatChatFileURLs(home: home, fileManager: fileManager))
        }
        return urls
    }

    public func extraWalkTitle(for url: URL, home: URL, fileManager: FileManager = .default) -> String {
        let path = url.resolvingSymlinksInPath().path
        let wechat = resolvedDefaultIncludeURLs(home: home, fileManager: fileManager)
            .contains { $0.resolvingSymlinksInPath().path == path }
        if wechat {
            return L10n.t(.includeWeChatChatFiles)
        }
        return url.lastPathComponent
    }

    public func homeWalkCovers(_ relative: String) -> Bool {
        guard !relative.isEmpty else { return false }
        let policy = ScanPolicy.from(self)
        var current = ""
        for component in relative.split(separator: "/") {
            let name = String(component)
            current = current.isEmpty ? name : current + "/" + name
            if policy.shouldSkipDescending(relative: current, name: name) {
                return false
            }
        }
        return true
    }

    public static func wechatChatFileURLs(home: URL, fileManager: FileManager = .default) -> [URL] {
        let accounts = home
            .appendingPathComponent("Library/Containers/com.tencent.xinWeChat/Data/Documents/xwechat_files")
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: accounts.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }
        guard let names = try? fileManager.contentsOfDirectory(atPath: accounts.path) else {
            return []
        }
        var urls: [URL] = []
        for name in names {
            if name == "." || name == ".." { continue }
            let fileDir = accounts.appendingPathComponent(name).appendingPathComponent("msg/file")
            var fileIsDir: ObjCBool = false
            if fileManager.fileExists(atPath: fileDir.path, isDirectory: &fileIsDir), fileIsDir.boolValue {
                urls.append(fileDir.resolvingSymlinksInPath())
            }
        }
        return urls
    }

    public static func resolvedLookIn(_ relative: String, home: URL) -> String {
        if relative.isEmpty { return "" }
        if relative.hasPrefix("/") {
            return URL(fileURLWithPath: relative).resolvingSymlinksInPath().path
        }
        return home.appendingPathComponent(relative).resolvingSymlinksInPath().path
    }

    public static let defaultSkipNames: Set<String> = [
        "node_modules", "__pycache__", ".venv", "venv",
        ".npm", ".pnpm-store", ".build", ".gradle", ".swiftpm",
        "DerivedData", "CoreSimulator",
    ]

    public static let defaultSkipPrefixes: [String] = [
        "Library/Caches",
        "Library/Logs",
        "Library/Developer",
        "Library/Containers",
        "Library/Metadata",
        "Library/Mail",
        "Library/Safari",
        "Library/HTTPStorages",
        "Library/WebKit",
        "Library/CloudStorage",
        "Library/Mobile Documents",
    ]

    public var activeSkipNames: Set<String> {
        Self.defaultSkipNames.subtracting(disabledDefaultNames)
    }

    public var activeSkipPrefixes: [String] {
        Self.defaultSkipPrefixes.filter { !disabledDefaultPrefixes.contains($0) } + extraExcludedRelatives
    }

    public func displayExcludes() -> [String] {
        Self.defaultSkipPrefixes.filter { !disabledDefaultPrefixes.contains($0) }
            + Self.defaultSkipNames.subtracting(disabledDefaultNames).sorted()
            + extraExcludedRelatives
    }

    public func displayIncludes() -> [String] {
        Self.defaultIncludeKeys.filter { !disabledDefaultIncludes.contains($0) } + extraRoots
    }

    public var missingDefaultIncludes: [String] {
        Self.defaultIncludeKeys.filter { disabledDefaultIncludes.contains($0) }
    }

    public mutating func enableDefaultInclude(_ key: String) {
        guard Self.defaultIncludeKeys.contains(key) else { return }
        disabledDefaultIncludes.removeAll { $0 == key }
    }
}

public enum IndexSettingsStore {
    private static let key = "indexSettings"

    public static func load(defaults: UserDefaults = .standard) -> IndexSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(IndexSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    public static func save(_ settings: IndexSettings, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
    }
}
