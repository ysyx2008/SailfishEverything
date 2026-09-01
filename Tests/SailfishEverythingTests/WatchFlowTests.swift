import Foundation
import SailfishEverythingCore

enum WatchFlowTests {
    static var cases: [TestCase] {[
        TestCase(name: "端到端.磁盘变动后名单跟着变", run: watchAddsAndRemoves),
        TestCase(name: "单元.家目录可被环境变量改掉", run: runtimeHomeOverride),
    ]}

    private static func watchAddsAndRemoves() throws {
        let root = try FixtureHome.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let index = FileIndex()
        let scanner = FileScanner(index: index, root: root, enableWatch: true, notifyOnMain: false)
        scanner.scanSynchronously()
        try expect(index.names(matching: "live-note").isEmpty)

        let live = root.appendingPathComponent("Desktop/live-note.txt")
        try "hello".data(using: .utf8)!.write(to: live)
        try expect(waitUntil(timeout: 6) {
            index.names(matching: "live-note").contains("live-note.txt")
        }, "new file never appeared in the index")

        try FileManager.default.removeItem(at: live)
        let gone = waitUntil(timeout: 6) {
            index.names(matching: "live-note").isEmpty
        }
        if !gone {
            let leftover = index.names(matching: "live-note")
            throw Expectation.failed("deleted file stayed in the index: \(leftover)", #fileID, #line)
        }
        scanner.stop()
    }

    private static func runtimeHomeOverride() throws {
        let url = RuntimeHome.url(environment: ["SAILFISH_HOME": "/tmp/sailfish-e2e-home"])
        try expect(url.path.contains("sailfish-e2e-home"))
        let fallback = RuntimeHome.url(environment: [:])
        try expect(fallback.path == URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path)
    }

    private static func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            Thread.sleep(forTimeInterval: 0.05)
        }
        return condition()
    }
}
