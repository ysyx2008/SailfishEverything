import Foundation

enum FixtureHome {
    static func make() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("everything-fixture-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        func write(_ relative: String, _ body: String = "x") throws {
            let url = root.appendingPathComponent(relative)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try body.data(using: .utf8)!.write(to: url)
        }

        try write("Desktop/会议纪要.docx")
        try write("Documents/季度报告.pdf")
        try write("Downloads/photo.jpg")
        try write("Library/CloudStorage/OneDrive-个人/公司文件/合同.pdf")
        try write("Library/CloudStorage/OneDrive-个人/备份/notes.txt")
        try write("Library/Mobile Documents/com~apple~CloudDocs/Projects/设计稿.psd")
        try write("Library/Mobile Documents/com~apple~CloudDocs/Desktop/should-not-index.txt")
        try write("Library/Mobile Documents/com~apple~CloudDocs/Documents/dup-report.pdf")
        try write("Library/Caches/should-not-index/secret.bin")
        try write("Work/app/src/main.swift")
        try write("Work/app/node_modules/leftpad/index.js")
        try write("Work/app/.git/objects/pack/data")

        return root
    }
}
