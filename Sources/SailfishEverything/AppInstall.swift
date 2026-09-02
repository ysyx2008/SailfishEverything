import AppKit
import Foundation
import SailfishEverythingCore

enum AppInstall {
    static func offerMoveIfNeeded() {
        guard AppInstallPolicy.shouldOfferMove(
            bundlePath: Bundle.main.bundlePath,
            home: NSHomeDirectory(),
            isE2E: AppRuntime.isE2E
        ) else { return }

        let alert = NSAlert()
        alert.messageText = L10n.t(.moveToApplicationsTitle)
        alert.informativeText = L10n.t(.moveToApplicationsBody)
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.t(.moveToApplications))
        alert.addButton(withTitle: L10n.t(.moveToApplicationsSkip))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            let destination = try copyToApplications(from: Bundle.main.bundleURL)
            NSWorkspace.shared.open(destination)
            NSApp.terminate(nil)
        } catch {
            let failed = NSAlert()
            failed.messageText = L10n.t(.moveToApplicationsFailed)
            failed.informativeText = error.localizedDescription
            failed.alertStyle = .warning
            failed.addButton(withTitle: L10n.t(.ok))
            failed.runModal()
        }
    }

    static func copyToApplications(from source: URL, fileManager: FileManager = .default) throws -> URL {
        let destination = URL(fileURLWithPath: "/Applications", isDirectory: true)
            .appendingPathComponent(source.lastPathComponent, isDirectory: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
        return destination
    }
}
