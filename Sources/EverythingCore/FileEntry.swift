import Foundation

public struct FileEntry: Sendable, Equatable {
    public let name: String
    public let nameLower: String
    public let directory: String
    public let path: String
    public let pathLower: String
    public let size: Int64?
    public let modified: Date?
    public let isDirectory: Bool
    public let isCloudOnly: Bool

    public init(
        name: String,
        directory: String,
        size: Int64? = nil,
        modified: Date? = nil,
        isDirectory: Bool = false,
        isCloudOnly: Bool = false
    ) {
        let path = directory.hasSuffix("/") || directory.isEmpty
            ? directory + name
            : directory + "/" + name
        self.name = name
        self.nameLower = name.lowercased()
        self.directory = directory
        self.path = path
        self.pathLower = path.lowercased()
        self.size = size
        self.modified = modified
        self.isDirectory = isDirectory
        self.isCloudOnly = isCloudOnly
    }

    public init(
        name: String,
        nameLower: String,
        directory: String,
        path: String,
        pathLower: String,
        size: Int64?,
        modified: Date?,
        isDirectory: Bool,
        isCloudOnly: Bool
    ) {
        self.name = name
        self.nameLower = nameLower
        self.directory = directory
        self.path = path
        self.pathLower = pathLower
        self.size = size
        self.modified = modified
        self.isDirectory = isDirectory
        self.isCloudOnly = isCloudOnly
    }
}

public struct SearchOptions: Equatable, Sendable {
    public var matchCase: Bool
    public var matchWholeWord: Bool
    public var matchPath: Bool

    public init(matchCase: Bool = false, matchWholeWord: Bool = false, matchPath: Bool = false) {
        self.matchCase = matchCase
        self.matchWholeWord = matchWholeWord
        self.matchPath = matchPath
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
