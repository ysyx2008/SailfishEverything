import Foundation

public enum SearchHistoryStore {
    public static let maxCount = 30
    private static let key = "searchHistory"

    public static func load(defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    public static func save(_ items: [String], defaults: UserDefaults = .standard) {
        defaults.set(Array(items.prefix(maxCount)), forKey: key)
    }

    @discardableResult
    public static func record(_ query: String, defaults: UserDefaults = .standard) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return load(defaults: defaults) }
        var items = load(defaults: defaults)
        items.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        items.insert(trimmed, at: 0)
        if items.count > maxCount {
            items = Array(items.prefix(maxCount))
        }
        save(items, defaults: defaults)
        return items
    }
}
