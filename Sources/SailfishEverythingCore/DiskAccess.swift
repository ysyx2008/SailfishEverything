import Foundation

public enum DiskAccess {
    public static let probeRelatives = [
        "Library/Safari",
        "Library/Mail",
        "Library/Application Support/AddressBook",
    ]

    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")

    public static func isFullyTrusted(home: URL, fileManager: FileManager = .default) -> Bool {
        let existing = probeRelatives
            .map { home.appendingPathComponent($0) }
            .filter { fileManager.fileExists(atPath: $0.path) }
        if existing.isEmpty { return true }
        for url in existing {
            if (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) != nil {
                return true
            }
        }
        return false
    }
}
