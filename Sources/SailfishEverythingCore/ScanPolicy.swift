import Foundation

public struct ScanPolicy: Sendable, Equatable {
    public var skipHiddenFolders: Bool
    public var skipNames: Set<String>
    public var skipRelativePrefixes: [String]

    public static let `default` = ScanPolicy.from(.default)

    public init(
        skipHiddenFolders: Bool = true,
        skipNames: Set<String>,
        skipRelativePrefixes: [String]
    ) {
        self.skipHiddenFolders = skipHiddenFolders
        self.skipNames = skipNames
        self.skipRelativePrefixes = skipRelativePrefixes
    }

    public static func from(_ settings: IndexSettings) -> ScanPolicy {
        ScanPolicy(
            skipHiddenFolders: settings.skipHiddenFolders,
            skipNames: settings.activeSkipNames,
            skipRelativePrefixes: settings.activeSkipPrefixes
        )
    }

    public func shouldSkipDescending(relative: String, name: String) -> Bool {
        if skipHiddenFolders, isHidden(name) {
            return true
        }
        if skipNames.contains(name) { return true }
        for prefix in skipRelativePrefixes {
            if matchesPrefix(relative, prefix) { return true }
        }
        return false
    }

    public func shouldOmitEntry(name: String) -> Bool {
        if skipHiddenFolders, isHidden(name) { return true }
        return skipNames.contains(name) && isHidden(name)
    }

    private func isHidden(_ name: String) -> Bool {
        name.hasPrefix(".") && name != "." && name != ".."
    }

    private func matchesPrefix(_ relative: String, _ prefix: String) -> Bool {
        relative == prefix || relative.hasPrefix(prefix + "/")
    }
}
