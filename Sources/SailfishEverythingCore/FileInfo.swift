import Foundation

public enum FileInfo {
    public static func summary(_ entry: FileEntry) -> String {
        var lines = [
            L10n.format(.infoName, entry.name),
            L10n.format(.infoPath, entry.path),
            L10n.format(.infoFolder, PathDisplay.pretty(entry.directory)),
        ]
        let attrs = FileMetadata.resolved(entry)
        if entry.isDirectory {
            lines.append(L10n.format(.infoType, L10n.t(.infoTypeFolder)))
        } else {
            lines.append(L10n.format(.infoSize, PathDisplay.formatSize(attrs.size, isDirectory: false)))
        }
        if let modified = attrs.modified {
            lines.append(L10n.format(.infoModified, PathDisplay.formatDate(modified)))
        }
        if let created = attrs.created {
            lines.append(L10n.format(.infoCreated, PathDisplay.formatDate(created)))
        }
        if entry.isCloudOnly {
            lines.append(L10n.t(.infoCloud))
        }
        return lines.joined(separator: "\n")
    }
}
