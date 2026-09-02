import Foundation

public enum RunHistoryStore {
    public static let maxCount = 2_000
    private static let key = "runHistory"
    private static let countsKey = "runHistoryCounts"

    public static func load(defaults: UserDefaults = .standard) -> [String: Int] {
        if let data = defaults.data(forKey: countsKey),
           let counts = try? JSONDecoder().decode([String: Int].self, from: data)
        {
            return counts
        }
        let legacy = defaults.stringArray(forKey: key) ?? []
        guard !legacy.isEmpty else { return [:] }
        var counts: [String: Int] = [:]
        counts.reserveCapacity(legacy.count)
        for path in legacy {
            counts[path] = 1
        }
        save(counts, defaults: defaults)
        defaults.removeObject(forKey: key)
        return counts
    }

    public static func save(_ counts: [String: Int], defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(trimmed(counts)) {
            defaults.set(data, forKey: countsKey)
        }
    }

    @discardableResult
    public static func record(_ path: String, defaults: UserDefaults = .standard) -> [String: Int] {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return load(defaults: defaults) }
        var counts = load(defaults: defaults)
        counts[trimmedPath, default: 0] += 1
        save(counts, defaults: defaults)
        return counts
    }

    private static func trimmed(_ counts: [String: Int]) -> [String: Int] {
        guard counts.count > maxCount else { return counts }
        let kept = counts.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key < rhs.key
        }.prefix(maxCount)
        return Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
    }
}
