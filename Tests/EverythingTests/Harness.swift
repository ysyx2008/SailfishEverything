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
