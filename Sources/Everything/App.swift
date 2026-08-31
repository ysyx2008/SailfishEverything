import AppKit

@main
enum EverythingApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        let controller = MainWindowController()
        controller.showWindow(nil)
        windowController = controller
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            windowController?.showWindow(nil)
        }
        return true
    }

    private func buildMenu() {
        let menu = NSMenu()

        let appMenuItem = NSMenuItem()
        menu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Everything", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Everything", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let fileItem = NSMenuItem()
        menu.addItem(fileItem)
        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Open", action: #selector(MainWindowController.openSelected(_:)), keyEquivalent: "\r")
        let openPath = file.addItem(withTitle: "Open Path", action: #selector(MainWindowController.openPath(_:)), keyEquivalent: "\r")
        openPath.keyEquivalentModifierMask = [.command]
        file.addItem(.separator())
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        file.addItem(withTitle: "Exit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        fileItem.submenu = file

        let editItem = NSMenuItem()
        menu.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Copy", action: #selector(MainWindowController.copy(_:)), keyEquivalent: "c")
        let copyFull = edit.addItem(withTitle: "Copy Full Name to Clipboard", action: #selector(MainWindowController.copyFullPath(_:)), keyEquivalent: "c")
        copyFull.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(withTitle: "Copy Path to Clipboard", action: #selector(MainWindowController.copyParentPath(_:)), keyEquivalent: "")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Select All", action: #selector(MainWindowController.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let viewItem = NSMenuItem()
        menu.addItem(viewItem)
        let view = NSMenu(title: "View")
        let refresh = NSMenuItem(title: "Refresh", action: #selector(MainWindowController.refreshView(_:)), keyEquivalent: "")
        refresh.keyEquivalent = String(UnicodeScalar(NSF5FunctionKey)!)
        refresh.keyEquivalentModifierMask = []
        view.addItem(refresh)
        view.addItem(.separator())
        view.addItem(withTitle: "Sort by Name", action: #selector(MainWindowController.sortByName(_:)), keyEquivalent: "1")
        view.addItem(withTitle: "Sort by Path", action: #selector(MainWindowController.sortByPath(_:)), keyEquivalent: "2")
        view.addItem(withTitle: "Sort by Size", action: #selector(MainWindowController.sortBySize(_:)), keyEquivalent: "3")
        view.addItem(withTitle: "Sort by Date Modified", action: #selector(MainWindowController.sortByDate(_:)), keyEquivalent: "6")
        viewItem.submenu = view

        let searchItem = NSMenuItem()
        menu.addItem(searchItem)
        let search = NSMenu(title: "Search")
        search.addItem(withTitle: "Match Case", action: #selector(MainWindowController.toggleMatchCase(_:)), keyEquivalent: "i")
        search.addItem(withTitle: "Match Whole Word", action: #selector(MainWindowController.toggleMatchWholeWord(_:)), keyEquivalent: "b")
        search.addItem(withTitle: "Match Path", action: #selector(MainWindowController.toggleMatchPath(_:)), keyEquivalent: "u")
        searchItem.submenu = search

        let indexItem = NSMenuItem()
        menu.addItem(indexItem)
        let index = NSMenu(title: "Index")
        index.addItem(withTitle: "Rebuild Index", action: #selector(MainWindowController.rebuildIndex(_:)), keyEquivalent: "")
        indexItem.submenu = index

        let helpItem = NSMenuItem()
        menu.addItem(helpItem)
        let help = NSMenu(title: "Help")
        help.addItem(withTitle: "Everything Help", action: #selector(showAbout), keyEquivalent: "?")
        helpItem.submenu = help

        NSApp.mainMenu = menu
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Everything"
        alert.informativeText = "A filename search for Mac.\nHome, iCloud Drive, and OneDrive.\nType to filter. Enter opens."
        alert.alertStyle = .informational
        alert.runModal()
    }
}
