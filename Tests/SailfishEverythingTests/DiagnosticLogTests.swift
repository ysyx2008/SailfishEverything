import Foundation
import SailfishEverythingCore

enum DiagnosticLogTests {
    static var cases: [TestCase] {[
        TestCase(name: "单元.诊断记录写下事件", run: writesEvent),
        TestCase(name: "单元.诊断记录关掉不写", run: disabledWritesNothing),
        TestCase(name: "单元.诊断记录过长会丢掉旧的", run: rotatesOldLines),
        TestCase(name: "单元.诊断记录默认不指向测试进程", run: sharedDisabledInTests),
        TestCase(name: "单元.诊断记录耗时和关键字截断", run: formatsDurationAndQuery),
    ]}

    private static func writesEvent() throws {
        let url = tempLog()
        defer { try? FileManager.default.removeItem(at: url) }
        let log = DiagnosticLog(fileURL: url)
        log.event("search", "start q=\"会议\"")
        log.event("search", "done hits=2 3ms")
        let text = log.readText()
        try expect(text.contains("search  start q=\"会议\""), text)
        try expect(text.contains("search  done hits=2 3ms"), text)
        try expect(text.contains("\n"), text)
    }

    private static func disabledWritesNothing() throws {
        let url = tempLog()
        defer { try? FileManager.default.removeItem(at: url) }
        let log = DiagnosticLog(fileURL: url, enabled: false)
        log.event("scan", "begin")
        try expect(!FileManager.default.fileExists(atPath: url.path))
        try expectEqual(log.readText(), "")
    }

    private static func rotatesOldLines() throws {
        let url = tempLog()
        defer { try? FileManager.default.removeItem(at: url) }
        let log = DiagnosticLog(fileURL: url, maxBytes: 240, keepBytes: 80)
        for index in 0..<40 {
            log.event("scan", String(format: "progress %02d xxxxxxxxxxxxxxxx", index))
        }
        let text = log.readText()
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        try expect(size <= 240, "size \(size)")
        try expect(!text.contains("progress 00"), text)
        try expect(text.contains("progress 39"), text)
    }

    private static func sharedDisabledInTests() throws {
        try expect(!DiagnosticLog.shared.isEnabled)
    }

    private static func formatsDurationAndQuery() throws {
        try expectEqual(DiagnosticLog.formatDuration(12), "12ms")
        try expectEqual(DiagnosticLog.formatDuration(1500), "1.5s")
        try expectEqual(DiagnosticLog.clipQuery("会议"), "会议")
        try expectEqual(DiagnosticLog.clipQuery(String(repeating: "a", count: 90)).count, 81)
        try expect(DiagnosticLog.clipQuery(String(repeating: "a", count: 90)).hasSuffix("…"))
    }

    private static func tempLog() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sailfish-diag-\(UUID().uuidString).log")
    }
}
