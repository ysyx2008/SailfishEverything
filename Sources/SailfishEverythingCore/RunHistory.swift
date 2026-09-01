import Foundation

public enum RunHistoryStore {
    public static let maxCount = 2_000
    private static let key = "runHistory"

    public static func load(defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    public static func save(_ items: [String], defaults: UserDefaults = .standard) {
        defaults.set(Array(items.prefix(maxCount)), forKey: key)
    }

    @discardableResult
    public static func record(_ path: String, defaults: UserDefaults = .standard) -> [String] {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return load(defaults: defaults) }
        var items = load(defaults: defaults)
        items.removeAll { $0 == trimmed }
        items.insert(trimmed, at: 0)
        if items.count > maxCount {
            items = Array(items.prefix(maxCount))
        }
        save(items, defaults: defaults)
        return items
    }
}
