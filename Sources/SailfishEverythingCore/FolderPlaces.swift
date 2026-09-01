import Foundation

public struct FolderPlace: Equatable, Sendable, Identifiable {
    public var title: String
    public var relative: String

    public var id: String { relative.isEmpty ? "all" : relative }

    public init(title: String, relative: String) {
        self.title = title
        self.relative = relative
    }

    public func url(in home: URL) -> URL? {
        if relative.isEmpty { return nil }
        return home.appendingPathComponent(relative)
    }

    public func resolvedPath(in home: URL) -> String {
        if relative.isEmpty { return "" }
        return home.appendingPathComponent(relative).resolvingSymlinksInPath().path
    }
}

public enum FolderPlaces {
    public static let catalog: [FolderPlace] = [
        FolderPlace(title: "All", relative: ""),
        FolderPlace(title: "Desktop", relative: "Desktop"),
        FolderPlace(title: "Documents", relative: "Documents"),
        FolderPlace(title: "Downloads", relative: "Downloads"),
        FolderPlace(title: "Pictures", relative: "Pictures"),
        FolderPlace(title: "Movies", relative: "Movies"),
        FolderPlace(title: "Music", relative: "Music"),
        FolderPlace(title: "iCloud Drive", relative: "Library/Mobile Documents/com~apple~CloudDocs"),
        FolderPlace(title: "OneDrive", relative: "Library/CloudStorage"),
    ]

    public static func existing(in home: URL) -> [FolderPlace] {
        let fm = FileManager.default
        return catalog.filter { place in
            guard let url = place.url(in: home) else { return true }
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
    }
}
