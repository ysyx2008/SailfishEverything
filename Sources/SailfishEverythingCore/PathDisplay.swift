import Foundation

public enum PathDisplay {
    public static func pretty(_ directory: String, home: String = NSHomeDirectory()) -> String {
        let cloudDocs = home + "/Library/Mobile Documents/com~apple~CloudDocs"
        let cloudStorage = home + "/Library/CloudStorage"
        let mobileDocuments = home + "/Library/Mobile Documents"

        if directory.hasPrefix(cloudDocs) {
            return "iCloud Drive" + directory.dropFirst(cloudDocs.count)
        }
        if directory.hasPrefix(cloudStorage) {
            let rest = String(directory.dropFirst(cloudStorage.count))
            if rest.isEmpty { return "Cloud Storage" }
            var parts = rest.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            if parts.first == "" { parts.removeFirst() }
            if let first = parts.first {
                parts[0] = prettyCloudProvider(first)
            }
            return parts.joined(separator: "/")
        }
        if directory.hasPrefix(mobileDocuments) {
            return "iCloud" + directory.dropFirst(mobileDocuments.count)
        }
        if directory.hasPrefix(home) {
            return "~" + directory.dropFirst(home.count)
        }
        return directory
    }

    public static func prettyCloudProvider(_ name: String) -> String {
        if name.hasPrefix("OneDrive-") {
            return "OneDrive - " + name.dropFirst("OneDrive-".count)
        }
        if name.hasPrefix("OneDrive") {
            return name.replacingOccurrences(of: "-", with: " - ")
        }
        return name
    }

    public static func formatSize(_ bytes: Int64?, isDirectory: Bool) -> String {
        if isDirectory { return "" }
        guard let bytes else { return "" }
        if bytes < 1024 { return "\(bytes) B" }
        let units = ["KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = -1
        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        if value >= 100 || unitIndex == 0 {
            return "\(Int(value.rounded())) \(units[unitIndex])"
        }
        return String(format: "%.1f %@", value, units[unitIndex])
    }

    public static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }()

    public static func formatDate(_ date: Date?) -> String {
        guard let date else { return "" }
        return dateFormatter.string(from: date)
    }
}
