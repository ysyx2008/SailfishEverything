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
        try write("Desktop/Q3 会议纪要.docx")
        try write("Desktop/run.sh", "#!/bin/sh\necho hi\n")
        try write("Desktop/Archive/archived.txt", "old")
        try write("Documents/季度报告.pdf")
        try write("Documents/公司文件/合同.pdf")
        try write("Documents/README.md", "# readme\n")
        try write("Downloads/photo.jpg")
        try write("Downloads/song.mp3")
        try write("Downloads/clip.mp4")
        try write("Downloads/archive.zip")
        try write("Downloads/Q1, 备份.txt", "backup")
        try writeBytes(root, "Downloads/tiny.dat", count: 3)
        try writeBytes(root, "Downloads/big.bin", count: 1_500_000)
        try write("Library/CloudStorage/OneDrive-个人/公司文件/合同.pdf")
        try write("Library/CloudStorage/OneDrive-个人/备份/notes.txt")
        try write("Library/Mobile Documents/com~apple~CloudDocs/Projects/设计稿.psd")
        try write("Library/Mobile Documents/com~apple~CloudDocs/Desktop/should-not-index.txt")
        try write("Library/Mobile Documents/com~apple~CloudDocs/Documents/dup-report.pdf")
        try write("Library/Caches/should-not-index/secret.bin")
        try write("Work/app/src/main.swift")
        try write("Work/app/node_modules/leftpad/index.js")
        try write("Work/app/.git/objects/pack/data")
        try write(".cache/huggingface/weights.bin")
        try write(".ssh/config")

        return root
    }

    private static func writeBytes(_ root: URL, _ relative: String, count: Int) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: count).write(to: url)
    }
}
