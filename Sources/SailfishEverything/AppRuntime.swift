import Foundation
import SailfishEverythingCore

enum AppRuntime {
    static var environment: [String: String] { ProcessInfo.processInfo.environment }
    static var isE2E: Bool { environment["SAILFISH_E2E"] == "1" }
    static var homeURL: URL { RuntimeHome.url(environment: environment) }
}
