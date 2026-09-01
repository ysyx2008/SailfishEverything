import Foundation

public enum ResultFilter: String, Codable, CaseIterable, Sendable {
    case all
    case audio
    case compressed
    case document
    case executable
    case folder
    case picture
    case video

    public var statusLabel: String {
        switch self {
        case .all: return ""
        case .audio: return "AUDIO"
        case .compressed: return "COMPRESSED"
        case .document: return "DOCUMENT"
        case .executable: return "EXECUTABLE"
        case .folder: return "FOLDER"
        case .picture: return "PICTURE"
        case .video: return "VIDEO"
        }
    }

    public var menuTitle: String {
        L10n.filterMenu(self)
    }

    public func matches(_ entry: FileEntry) -> Bool {
        switch self {
        case .all:
            return true
        case .folder:
            return entry.isDirectory
        case .executable:
            if entry.isDirectory, entry.name.lowercased().hasSuffix(".app") { return true }
            return Self.executableExts.contains(entry.fileExtension)
        default:
            if entry.isDirectory { return false }
            return extensions.contains(entry.fileExtension)
        }
    }

    public var extensions: Set<String> {
        switch self {
        case .all, .folder:
            return []
        case .audio:
            return Self.audioExts
        case .video:
            return Self.videoExts
        case .picture:
            return Self.pictureExts
        case .document:
            return Self.documentExts
        case .compressed:
            return Self.compressedExts
        case .executable:
            return Self.executableExts
        }
    }

    private static let audioExts: Set<String> = [
        "aac", "ac3", "aif", "aiff", "ape", "au", "caf", "flac", "m4a", "mid", "midi",
        "mp3", "oga", "ogg", "ra", "wav", "wma",
    ]
    private static let videoExts: Set<String> = [
        "3g2", "3gp", "asf", "avi", "m2ts", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg",
        "rm", "swf", "ts", "vob", "webm", "wmv",
    ]
    private static let pictureExts: Set<String> = [
        "bmp", "gif", "heic", "heif", "ico", "jpeg", "jpg", "png", "raw", "svg",
        "tif", "tiff", "webp",
    ]
    private static let documentExts: Set<String> = [
        "csv", "doc", "docx", "key", "md", "numbers", "pages", "pdf", "ppt", "pptx",
        "rtf", "txt", "xls", "xlsx",
    ]
    private static let compressedExts: Set<String> = [
        "7z", "bz2", "dmg", "gz", "iso", "rar", "tar", "xz", "zip",
    ]
    private static let executableExts: Set<String> = [
        "app", "bat", "bin", "cmd", "command", "exe", "sh",
    ]
}
