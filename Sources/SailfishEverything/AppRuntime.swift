import Foundation
import SailfishEverythingCore

enum AppRuntime {
    static var environment: [String: String] { ProcessInfo.processInfo.environment }
    static var isE2E: Bool { environment["SAILFISH_E2E"] == "1" }
    static var homeURL: URL { RuntimeHome.url(environment: environment) }

    static var windowTitle: String {
        L10n.windowTitle(version: marketingVersion)
    }

    static var marketingVersion: String? {
        if Bundle.main.bundleIdentifier == "com.sailfish.everything",
           let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        var dir = Bundle.main.bundleURL
        for _ in 0..<8 {
            dir.deleteLastPathComponent()
            let candidate = dir.appendingPathComponent("Resources/Info.plist")
            if let version = Self.marketingVersion(fromPlistAt: candidate) {
                return version
            }
        }
        return nil
    }

    static func marketingVersion(fromPlistAt url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let version = plist["CFBundleShortVersionString"] as? String
        else { return nil }
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
