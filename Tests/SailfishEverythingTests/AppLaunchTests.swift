import Foundation
import SailfishEverythingCore

enum AppLaunchTests {
    static var cases: [TestCase] {[
        TestCase(name: "端到端.真正打开应用对着假家目录搜", run: launchAppAgainstFixture),
    ]}

    private static func launchAppAgainstFixture() throws {
        guard let binary = appBinary() else {
            throw Expectation.failed("missing SailfishEverything binary; build the app first", #fileID, #line)
        }
        let root = try FixtureHome.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let out = root.appendingPathComponent("e2e.json")
        let queries = #"["","合","合同","ext:jpg","会议 !pdf","path:公司文件","path:OneDrive"]"#

        let process = Process()
        process.executableURL = binary
        var environment = ProcessInfo.processInfo.environment
        environment["SAILFISH_E2E"] = "1"
        environment["SAILFISH_HOME"] = root.path
        environment["SAILFISH_E2E_OUT"] = out.path
        environment["SAILFISH_E2E_QUERIES"] = queries
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        let deadline = Date().addingTimeInterval(25)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            throw Expectation.failed("app e2e timed out", #fileID, #line)
        }

        let data = try Data(contentsOf: out)
        let report = try JSONDecoder().decode(Report.self, from: data)
        try expectEqual(report.title, "Sailfish Everything")
        try expect(report.error == nil, report.error ?? "")
        try expect(report.count > 8, "indexed \(report.count)")

        func names(for query: String) throws -> Set<String> {
            guard let row = report.queries.first(where: { $0.query == query }) else {
                throw Expectation.failed("missing query \(query)", #fileID, #line)
            }
            return Set(row.names)
        }

        let contract = try names(for: "合同")
        try expectEqual(contract, Set(["合同.pdf"]))
        let prefix = try names(for: "合")
        try expect(prefix.contains("合同.pdf"))
        let jpgs = try names(for: "ext:jpg")
        try expectEqual(jpgs, Set(["photo.jpg"]))
        let noPdf = try names(for: "会议 !pdf")
        try expect(noPdf.contains("会议纪要.docx"))
        try expect(!noPdf.contains(where: { $0.hasSuffix(".pdf") }))
        let company = try names(for: "path:公司文件")
        try expect(company.contains("合同.pdf"))
        let onedrive = try names(for: "path:OneDrive")
        try expect(onedrive.isEmpty)
    }

    private static func appBinary() -> URL? {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidates = [
            repo.appendingPathComponent(".build/debug/SailfishEverything"),
            repo.appendingPathComponent(".build/release/SailfishEverything"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private struct Report: Codable {
        var title: String
        var count: Int
        var queries: [QueryResult]
        var error: String?
    }

    private struct QueryResult: Codable {
        var query: String
        var names: [String]
    }
}
