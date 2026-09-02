import Foundation

public final class DiagnosticLog: @unchecked Sendable {
    public static let shared = DiagnosticLog.makeShared()

    public let fileURL: URL
    public let isEnabled: Bool

    private let lock = NSLock()
    private let maxBytes: Int
    private let keepBytes: Int
    private let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.timeZone = .current
        return formatter
    }()

    public static func defaultFileURL() -> URL {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Library")
        return logs.appendingPathComponent("Logs/SailfishEverything/diagnostic.log", isDirectory: false)
    }

    public static func formatDuration(_ milliseconds: Double) -> String {
        if milliseconds < 1000 {
            return String(format: "%.0fms", milliseconds)
        }
        return String(format: "%.1fs", milliseconds / 1000)
    }

    public static func elapsedMilliseconds(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds) / 1_000_000
    }

    public static func clipQuery(_ query: String, limit: Int = 80) -> String {
        let folded = query.replacingOccurrences(of: "\n", with: " ")
        if folded.count <= limit { return folded }
        return String(folded.prefix(limit)) + "…"
    }

    public init(
        fileURL: URL,
        enabled: Bool = true,
        maxBytes: Int = 512_000,
        keepBytes: Int = 256_000
    ) {
        self.fileURL = fileURL
        self.isEnabled = enabled
        self.maxBytes = max(keepBytes + 1, maxBytes)
        self.keepBytes = max(1, keepBytes)
    }

    public func event(_ topic: String, _ detail: String = "") {
        guard isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        let time = stamp.string(from: Date())
        let line = detail.isEmpty ? "\(time)  \(topic)\n" : "\(time)  \(topic)  \(detail)\n"
        writeLocked(line)
    }

    public func readText() -> String {
        lock.lock()
        defer { lock.unlock() }
        return (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    public func ensureFileExists() {
        lock.lock()
        defer { lock.unlock() }
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    private func writeLocked(_ line: String) {
        ensureDirectoryLocked()
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        if let data = line.data(using: .utf8) {
            try? handle.write(contentsOf: data)
            try? handle.synchronize()
        }
        let size = (try? handle.offset()) ?? 0
        if size > maxBytes {
            try? handle.close()
            rotateLocked()
        }
    }

    private func ensureDirectoryLocked() {
        let directory = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func rotateLocked() {
        guard let data = try? Data(contentsOf: fileURL), data.count > keepBytes else { return }
        let start = data.count - keepBytes
        var slice = data.subdata(in: start..<data.count)
        if let newline = slice.firstIndex(of: UInt8(ascii: "\n")), newline + 1 < slice.count {
            slice = slice.subdata(in: (newline + 1)..<slice.count)
        }
        try? slice.write(to: fileURL, options: .atomic)
    }

    private static func makeShared() -> DiagnosticLog {
        let environment = ProcessInfo.processInfo.environment
        if environment["SAILFISH_E2E"] == "1" || environment["SAILFISH_DIAG"] == "0" {
            return DiagnosticLog(fileURL: defaultFileURL(), enabled: false)
        }
        if let path = environment["SAILFISH_DIAG_LOG"], !path.isEmpty {
            return DiagnosticLog(fileURL: URL(fileURLWithPath: path), enabled: true)
        }
        if ProcessInfo.processInfo.processName != "SailfishEverything" {
            return DiagnosticLog(fileURL: defaultFileURL(), enabled: false)
        }
        return DiagnosticLog(fileURL: defaultFileURL(), enabled: true)
    }
}
