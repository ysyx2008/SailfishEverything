import Foundation

struct TestCase {
    var name: String
    var run: () throws -> Void
}

enum Expectation: Error, CustomStringConvertible {
    case failed(String, String, Int)

    var description: String {
        switch self {
        case .failed(let message, let file, let line):
            return "\(file):\(line) \(message)"
        }
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String = "expect failed", file: String = #fileID, line: Int = #line) throws {
    if !condition() {
        throw Expectation.failed(message, file, line)
    }
}

func bench(_ name: String, _ ms: Double) {
    guard ProcessInfo.processInfo.environment["SAILFISH_BENCH"] == "1" else { return }
    print(String(format: "bench %6.2fms  %@", ms, name as NSString))
}

func repoRoot(filePath: String = #filePath) -> URL {
    URL(fileURLWithPath: filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

func packagingMarketingVersion(repo: URL) throws -> String {
    let url = repo.appendingPathComponent("Resources/Info.plist")
    let data = try Data(contentsOf: url)
    guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
          let version = plist["CFBundleShortVersionString"] as? String
    else {
        throw Expectation.failed("missing CFBundleShortVersionString", #fileID, #line)
    }
    let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
    try expect(!trimmed.isEmpty, "empty marketing version")
    return trimmed
}

func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: String = #fileID, line: Int = #line) throws {
    if lhs != rhs {
        throw Expectation.failed("\(lhs) != \(rhs)", file, line)
    }
}

@discardableResult
func runTests(_ cases: [TestCase]) -> Int {
    var failed = 0
    for test in cases {
        do {
            try test.run()
            print("ok   \(test.name)")
        } catch {
            failed += 1
            print("FAIL \(test.name)  \(error)")
        }
    }
    print("—")
    print("\(cases.count - failed) passed, \(failed) failed, \(cases.count) total")
    return failed
}
