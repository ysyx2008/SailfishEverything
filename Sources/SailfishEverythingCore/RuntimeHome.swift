import Foundation

public enum RuntimeHome {
    public static func url(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let path = environment["SAILFISH_HOME"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath()
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).resolvingSymlinksInPath()
    }
}
