import Foundation

public enum AppHotKey: String, CaseIterable, Sendable, Codable {
    case controlSpace
    case optionSpace
    case commandShiftSpace
    case controlOptionSpace

    public static func preferredDefault(language: AppLanguage = L10n.language) -> AppHotKey {
        language == .chinese ? .optionSpace : .controlSpace
    }
}

public enum AppHotKeyStore {
    public static let key = "toggleHotKey"

    public static func load(
        defaults: UserDefaults = .standard,
        language: AppLanguage = L10n.language
    ) -> AppHotKey {
        if let raw = defaults.string(forKey: key), let value = AppHotKey(rawValue: raw) {
            return value
        }
        return .preferredDefault(language: language)
    }

    public static func save(_ value: AppHotKey, defaults: UserDefaults = .standard) {
        defaults.set(value.rawValue, forKey: key)
    }
}
