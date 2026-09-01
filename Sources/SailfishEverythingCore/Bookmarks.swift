import Foundation

public struct Bookmark: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var query: String
    public var matchCase: Bool
    public var matchWholeWord: Bool
    public var matchPath: Bool
    public var regex: Bool
    public var filter: ResultFilter
    public var inFolder: String

    public init(
        id: UUID = UUID(),
        name: String,
        query: String,
        options: SearchOptions = SearchOptions(),
        filter: ResultFilter = .all
    ) {
        self.id = id
        self.name = name
        self.query = query
        self.matchCase = options.matchCase
        self.matchWholeWord = options.matchWholeWord
        self.matchPath = options.matchPath
        self.regex = options.regex
        self.filter = filter
        self.inFolder = options.inFolder
    }

    public var options: SearchOptions {
        SearchOptions(
            matchCase: matchCase,
            matchWholeWord: matchWholeWord,
            matchPath: matchPath,
            regex: regex,
            inFolder: inFolder
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, name, query, matchCase, matchWholeWord, matchPath, regex, filter, inFolder
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        query = try container.decode(String.self, forKey: .query)
        matchCase = try container.decodeIfPresent(Bool.self, forKey: .matchCase) ?? false
        matchWholeWord = try container.decodeIfPresent(Bool.self, forKey: .matchWholeWord) ?? false
        matchPath = try container.decodeIfPresent(Bool.self, forKey: .matchPath) ?? false
        regex = try container.decodeIfPresent(Bool.self, forKey: .regex) ?? false
        filter = try container.decodeIfPresent(ResultFilter.self, forKey: .filter) ?? .all
        inFolder = try container.decodeIfPresent(String.self, forKey: .inFolder) ?? ""
    }
}

public enum BookmarkStore {
    private static let key = "bookmarks"

    public static func load(defaults: UserDefaults = .standard) -> [Bookmark] {
        guard let data = defaults.data(forKey: key),
              let items = try? JSONDecoder().decode([Bookmark].self, from: data) else {
            return []
        }
        return items
    }

    public static func save(_ items: [Bookmark], defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: key)
        }
    }
}

public enum ResultExport {
    public static func csv(_ entries: [FileEntry]) -> String {
        var lines = [[L10n.t(.columnName), L10n.t(.columnPath), L10n.t(.columnSize), L10n.t(.columnModified)].joined(separator: ",")]
        for entry in entries {
            let attrs = FileMetadata.resolved(entry)
            let size = entry.isDirectory ? "" : "\(attrs.size ?? 0)"
            let date = PathDisplay.formatDate(attrs.modified)
            lines.append([
                csvEscape(entry.name),
                csvEscape(entry.directory),
                csvEscape(size),
                csvEscape(date),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func txt(_ entries: [FileEntry]) -> String {
        entries.map(\.path).joined(separator: "\n") + "\n"
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
