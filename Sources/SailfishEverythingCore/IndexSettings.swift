import Foundation

public struct IndexSettings: Codable, Equatable, Sendable {
    public var skipHiddenFolders: Bool
    public var extraExcludedRelatives: [String]
    public var disabledDefaultPrefixes: [String]
    public var disabledDefaultNames: [String]
    public var extraRoots: [String]
    public var preferOpened: Bool

    public static let `default` = IndexSettings(
        skipHiddenFolders: true,
        extraExcludedRelatives: [],
        disabledDefaultPrefixes: [],
        disabledDefaultNames: [],
        extraRoots: [],
        preferOpened: true
    )

    public init(
        skipHiddenFolders: Bool = true,
        extraExcludedRelatives: [String] = [],
        disabledDefaultPrefixes: [String] = [],
        disabledDefaultNames: [String] = [],
        extraRoots: [String] = [],
        preferOpened: Bool = true
    ) {
        self.skipHiddenFolders = skipHiddenFolders
        self.extraExcludedRelatives = extraExcludedRelatives
        self.disabledDefaultPrefixes = disabledDefaultPrefixes
        self.disabledDefaultNames = disabledDefaultNames
        self.extraRoots = extraRoots
        self.preferOpened = preferOpened
    }

    enum CodingKeys: String, CodingKey {
        case skipHiddenFolders, extraExcludedRelatives, disabledDefaultPrefixes, disabledDefaultNames, extraRoots, preferOpened
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        skipHiddenFolders = try container.decodeIfPresent(Bool.self, forKey: .skipHiddenFolders) ?? true
        extraExcludedRelatives = try container.decodeIfPresent([String].self, forKey: .extraExcludedRelatives) ?? []
        disabledDefaultPrefixes = try container.decodeIfPresent([String].self, forKey: .disabledDefaultPrefixes) ?? []
        disabledDefaultNames = try container.decodeIfPresent([String].self, forKey: .disabledDefaultNames) ?? []
        extraRoots = try container.decodeIfPresent([String].self, forKey: .extraRoots) ?? []
        preferOpened = try container.decodeIfPresent(Bool.self, forKey: .preferOpened) ?? true
    }

    public func extraRootURLs(home: URL, fileManager: FileManager = .default) -> [URL] {
        let homePath = home.resolvingSymlinksInPath().path
        var seen = Set<String>()
        var urls: [URL] = []
        for raw in extraRoots {
            let url = URL(fileURLWithPath: raw, isDirectory: true).resolvingSymlinksInPath()
            let path = url.path
            if path == homePath || path.hasPrefix(homePath + "/") { continue }
            if !seen.insert(path).inserted { continue }
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
            urls.append(url)
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
