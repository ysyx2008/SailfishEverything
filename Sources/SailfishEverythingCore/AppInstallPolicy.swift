import Foundation

public enum AppInstallPolicy: Sendable {
    public static func shouldOfferMove(bundlePath: String, home: String, isE2E: Bool) -> Bool {
        if isE2E { return false }
        if bundlePath.contains("/.build/") { return false }
        if isInApplications(bundlePath, home: home) { return false }
        return isOnDiskImage(bundlePath) || isInDownloads(bundlePath, home: home) || isTranslocated(bundlePath)
    }

    public static func isInApplications(_ path: String, home: String) -> Bool {
        path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/")
    }

    public static func isOnDiskImage(_ path: String) -> Bool {
        path.hasPrefix("/Volumes/")
    }

    public static func isInDownloads(_ path: String, home: String) -> Bool {
        path.hasPrefix(home + "/Downloads/")
    }

    public static func isTranslocated(_ path: String) -> Bool {
        path.contains("/AppTranslocation/")
    }
}
