import Foundation

public struct ScanPolicy: Sendable, Equatable {
    public var skipNames: Set<String>
    public var skipRelativePrefixes: [String]

    public static let `default` = ScanPolicy(
        skipNames: [
            ".Trash", ".Trashes", "node_modules", ".git", "__pycache__",
            ".venv", "venv", ".npm", ".pnpm-store", ".build", ".gradle",
            ".swiftpm", "DerivedData", "CoreSimulator",
        ],
        skipRelativePrefixes: [
            "Library/Caches",
            "Library/Logs",
            "Library/Developer",
            "Library/Containers",
            "Library/Metadata",
            "Library/Mail",
            "Library/Safari",
            "Library/Mobile Documents/com~apple~CloudDocs/Desktop",
            "Library/Mobile Documents/com~apple~CloudDocs/Documents",
            "Library/Mobile Documents/com~apple~CloudDocs/Downloads",
        ]
    )

    public init(skipNames: Set<String>, skipRelativePrefixes: [String]) {
        self.skipNames = skipNames
        self.skipRelativePrefixes = skipRelativePrefixes
    }

    public func shouldSkipDescending(relative: String, name: String) -> Bool {
        if skipNames.contains(name) { return true }
        for prefix in skipRelativePrefixes {
            if relative == prefix || relative.hasPrefix(prefix + "/") {
                return true
            }
        }
        return false
    }

    public func shouldOmitEntry(name: String) -> Bool {
        skipNames.contains(name) && name.hasPrefix(".")
    }
}
