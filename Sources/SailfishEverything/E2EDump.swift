import Foundation
import SailfishEverythingCore

enum E2EDump {
    struct Report: Codable {
        var title: String
        var count: Int
        var queries: [QueryResult]
        var error: String?
    }

    struct QueryResult: Codable {
        var query: String
        var names: [String]
    }

    @discardableResult
    static func write(index: FileIndex, title: String, error: String? = nil) -> Bool {
        guard AppRuntime.isE2E else { return false }
        guard let out = AppRuntime.environment["SAILFISH_E2E_OUT"], !out.isEmpty else { return false }

        let raw = AppRuntime.environment["SAILFISH_E2E_QUERIES"]
            ?? #"["","合","合同","ext:jpg","会议 !pdf"]"#
        let queries = (try? JSONDecoder().decode([String].self, from: Data(raw.utf8))) ?? [""]
        let report = Report(
            title: title,
            count: index.count,
            queries: queries.map { query in
                QueryResult(query: query, names: index.names(matching: query))
            },
            error: error
        )
        if let data = try? JSONEncoder().encode(report) {
            try? data.write(to: URL(fileURLWithPath: out))
        }
        return true
    }
}
