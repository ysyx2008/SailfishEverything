import Foundation

public struct FileEntry: Sendable, Equatable {
    public let name: String
    public var nameLower: String { name.fastLowercased() }
    public let directory: String
    public var path: String { Self.joinedPath(directory: directory, name: name) }
    public var pathLower: String { path.fastLowercased() }
    public let size: Int64?
    public let modified: Date?
    public let created: Date?
    public let isDirectory: Bool
    public let isCloudOnly: Bool

    public init(
        name: String,
        directory: String,
        size: Int64? = nil,
        modified: Date? = nil,
        created: Date? = nil,
        isDirectory: Bool = false,
        isCloudOnly: Bool = false
    ) {
        self.name = name
        self.directory = directory
        self.size = size
        self.modified = modified
        self.created = created
        self.isDirectory = isDirectory
        self.isCloudOnly = isCloudOnly
    }

    static func joinedPath(directory: String, name: String) -> String {
        if directory.isEmpty || directory.hasSuffix("/") {
            return directory + name
        }
        return directory + "/" + name
    }

    public static func parentDirectory(fromPath path: String, name: String) -> String {
        if path.count == name.count { return "" }
        guard path.hasSuffix(name) else {
            if let slash = path.lastIndex(of: "/") {
                return String(path[..<slash])
            }
            return ""
        }
        let prefixCount = path.count - name.count
        if prefixCount == 0 { return "" }
        let slash = path.index(path.startIndex, offsetBy: prefixCount - 1)
        if path[slash] == "/" {
            return String(path[..<slash])
        }
        return String(path.dropLast(name.count))
    }
}

public struct SearchOptions: Equatable, Sendable, Codable {
    public var matchCase: Bool
    public var matchWholeWord: Bool
    public var matchPath: Bool
    public var regex: Bool
    public var inFolder: String

    public init(
        matchCase: Bool = false,
        matchWholeWord: Bool = false,
        matchPath: Bool = false,
        regex: Bool = false,
        inFolder: String = ""
    ) {
        self.matchCase = matchCase
        self.matchWholeWord = matchWholeWord
        self.matchPath = matchPath
        self.regex = regex
        self.inFolder = inFolder
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        matchCase = try container.decodeIfPresent(Bool.self, forKey: .matchCase) ?? false
        matchWholeWord = try container.decodeIfPresent(Bool.self, forKey: .matchWholeWord) ?? false
        matchPath = try container.decodeIfPresent(Bool.self, forKey: .matchPath) ?? false
        regex = try container.decodeIfPresent(Bool.self, forKey: .regex) ?? false
        inFolder = try container.decodeIfPresent(String.self, forKey: .inFolder) ?? ""
    }
}

public enum SortColumn: Int, Sendable {
    case name = 0
    case path = 1
    case size = 2
    case modified = 3
}

public struct SortState: Equatable, Sendable {
    public var column: SortColumn
    public var ascending: Bool

    public init(column: SortColumn = .name, ascending: Bool = true) {
        self.column = column
        self.ascending = ascending
    }
}
