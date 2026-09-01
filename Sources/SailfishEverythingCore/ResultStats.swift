import Foundation

public enum ResultStats {
    public static func totalBytes(_ entries: [FileEntry]) -> Int64 {
        entries.reduce(0) { sum, entry in
            if entry.isDirectory { return sum }
            return sum + (entry.size ?? 0)
        }
    }

    public static func line(objects: Int, selected: Int, bytes: Int64) -> String {
        let count = formatCount(selected > 0 ? selected : objects)
        var text: String
        if selected > 0 {
            text = "\(count) of \(formatCount(objects)) objects selected"
        } else {
            text = "\(count) objects"
        }
        if bytes > 0 {
            text += " (\(PathDisplay.formatSize(bytes, isDirectory: false)))"
        }
        return text
    }

    public static func formatCount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
