import AppKit
import Quartz
import SailfishEverythingCore

final class PreviewController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    var urls: [URL] = []

    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> QLPreviewItem {
        urls[index] as QLPreviewItem
    }

    func show(urls: [URL]) {
        self.urls = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !self.urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.makeKeyAndOrderFront(nil)
    }
}
