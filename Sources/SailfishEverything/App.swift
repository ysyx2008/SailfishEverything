import AppKit
import SailfishEverythingCore

@main
enum SailfishEverythingApp {
    static func main() {
        L10n.bootstrap()
        if AppRuntime.isE2E {
            runE2E()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate.shared
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }

    private static func runE2E() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let controller = MainWindowController(home: AppRuntime.homeURL, enableWatch: false, startScanning: false)
        controller.scanSynchronouslyForE2E()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let shared = AppDelegate()

    var windowController: MainWindowController?
    private var statusItem: NSStatusItem?
    private let hotKey = ToggleHotKey()
    private var bookmarkMenu: NSMenu?
    private var searchMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        let controller = MainWindowController()
        windowController = controller
        if !AppRuntime.isE2E {
            installStatusItem()
            hotKey.action = { [weak self] in
                self?.windowController?.toggleMainWindow()
            }
            hotKey.register(AppHotKeyStore.load())
        }
        controller.showMainWindow()
        DispatchQueue.main.async { [weak self] in
            self?.windowController?.showMainWindow()
            self?.showOnboardingIfNeeded()
        }
    }

    func applyHotKey(_ combo: AppHotKey) {
        AppHotKeyStore.save(combo)
        hotKey.register(combo)
    }

    private func showOnboardingIfNeeded() {
        let defaults = UserDefaults.standard
        let key = "didShowOnboarding.v1"
        guard !AppRuntime.isE2E, !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        let alert = NSAlert()
        alert.messageText = L10n.productName
        alert.informativeText = L10n.t(.onboardingBody)
        alert.alertStyle = .informational
        if !DiskAccess.isFullyTrusted(home: AppRuntime.homeURL) {
            alert.addButton(withTitle: L10n.t(.onboardingFDA))
            alert.addButton(withTitle: L10n.t(.ok))
            if alert.runModal() == .alertFirstButtonReturn, let url = DiskAccess.settingsURL {
                NSWorkspace.shared.open(url)
            }
        } else {
            alert.addButton(withTitle: L10n.t(.ok))
            alert.runModal()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if windowController?.window?.isVisible != true {
            windowController?.showMainWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowController?.showMainWindow()
        return true
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = L10n.statusItemTitle
        item.button?.toolTip = L10n.productName
        let menu = NSMenu()
        menu.addItem(withTitle: L10n.t(.showApp), action: #selector(showWindow), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.t(.quitApp), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func showWindow() {
        windowController?.showMainWindow()
    }

    private func buildMenu() {
        let menu = NSMenu()

        let appMenuItem = NSMenuItem()
        menu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L10n.t(.aboutApp), action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L10n.t(.settings), action: #selector(MainWindowController.showOptions(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L10n.t(.quitApp), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let fileItem = NSMenuItem()
        menu.addItem(fileItem)
        let file = NSMenu(title: L10n.t(.fileMenu))
        file.addItem(withTitle: L10n.t(.open), action: #selector(MainWindowController.openSelected(_:)), keyEquivalent: "\r")
        let openPath = file.addItem(withTitle: L10n.t(.openPath), action: #selector(MainWindowController.openPath(_:)), keyEquivalent: "\r")
        openPath.keyEquivalentModifierMask = [.command]
        file.addItem(withTitle: L10n.t(.quickLook), action: #selector(MainWindowController.previewSelected(_:)), keyEquivalent: " ")
        let info = file.addItem(withTitle: L10n.t(.getInfo), action: #selector(MainWindowController.showInfo(_:)), keyEquivalent: "i")
        info.keyEquivalentModifierMask = [.command, .option]
        file.addItem(.separator())
        file.addItem(withTitle: L10n.t(.export), action: #selector(MainWindowController.exportResults(_:)), keyEquivalent: "s")
        file.addItem(.separator())
        file.addItem(withTitle: L10n.t(.close), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        file.addItem(withTitle: L10n.t(.exit), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        fileItem.submenu = file

        let editItem = NSMenuItem()
        menu.addItem(editItem)
        let edit = NSMenu(title: L10n.t(.editMenu))
        edit.addItem(withTitle: L10n.t(.copy), action: #selector(MainWindowController.copy(_:)), keyEquivalent: "c")
        let copyFull = edit.addItem(withTitle: L10n.t(.copyFullName), action: #selector(MainWindowController.copyFullPath(_:)), keyEquivalent: "c")
        copyFull.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(withTitle: L10n.t(.copyPath), action: #selector(MainWindowController.copyParentPath(_:)), keyEquivalent: "")
        edit.addItem(.separator())
        edit.addItem(withTitle: L10n.t(.selectAll), action: #selector(MainWindowController.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let viewItem = NSMenuItem()
        menu.addItem(viewItem)
        let view = NSMenu(title: L10n.t(.viewMenu))
        let refresh = NSMenuItem(title: L10n.t(.refresh), action: #selector(MainWindowController.refreshView(_:)), keyEquivalent: "")
        refresh.keyEquivalent = String(UnicodeScalar(NSF5FunctionKey)!)
        refresh.keyEquivalentModifierMask = []
        view.addItem(refresh)
        view.addItem(.separator())
        view.addItem(withTitle: L10n.t(.sortName), action: #selector(MainWindowController.sortByName(_:)), keyEquivalent: "1")
        view.addItem(withTitle: L10n.t(.sortPath), action: #selector(MainWindowController.sortByPath(_:)), keyEquivalent: "2")
        view.addItem(withTitle: L10n.t(.sortSize), action: #selector(MainWindowController.sortBySize(_:)), keyEquivalent: "3")
        view.addItem(withTitle: L10n.t(.sortDate), action: #selector(MainWindowController.sortByDate(_:)), keyEquivalent: "6")
        viewItem.submenu = view

        let searchItem = NSMenuItem()
        menu.addItem(searchItem)
        let search = NSMenu(title: L10n.t(.searchMenu))
        search.addItem(withTitle: L10n.t(.matchCase), action: #selector(MainWindowController.toggleMatchCase(_:)), keyEquivalent: "i")
        search.addItem(withTitle: L10n.t(.matchWholeWord), action: #selector(MainWindowController.toggleMatchWholeWord(_:)), keyEquivalent: "b")
        search.addItem(withTitle: L10n.t(.matchPath), action: #selector(MainWindowController.toggleMatchPath(_:)), keyEquivalent: "u")
        search.addItem(withTitle: L10n.t(.enableRegex), action: #selector(MainWindowController.toggleRegex(_:)), keyEquivalent: "r")
        search.addItem(.separator())
        let lookIn = NSMenuItem(title: L10n.t(.lookIn), action: nil, keyEquivalent: "")
        lookIn.tag = 711
        lookIn.submenu = NSMenu()
        rebuildLookInMenu(lookIn.submenu!)
        search.addItem(lookIn)
        search.addItem(.separator())
        for filter in ResultFilter.allCases {
            let item = NSMenuItem(title: L10n.filterMenu(filter), action: #selector(MainWindowController.setFilter(_:)), keyEquivalent: "")
            item.representedObject = filter.rawValue
            search.addItem(item)
        }
        search.delegate = self
        searchMenu = search
        searchItem.submenu = search

        let bookmarkItem = NSMenuItem()
        menu.addItem(bookmarkItem)
        let bookmarks = NSMenu(title: L10n.t(.bookmarksMenu))
        bookmarks.delegate = self
        bookmarks.addItem(withTitle: L10n.t(.addBookmark), action: #selector(MainWindowController.addBookmark(_:)), keyEquivalent: "d")
        bookmarkMenu = bookmarks
        bookmarkItem.submenu = bookmarks

        let toolsItem = NSMenuItem()
        menu.addItem(toolsItem)
        let tools = NSMenu(title: L10n.t(.toolsMenu))
        tools.addItem(withTitle: L10n.t(.options), action: #selector(MainWindowController.showOptions(_:)), keyEquivalent: "p")
        toolsItem.submenu = tools

        let indexItem = NSMenuItem()
        menu.addItem(indexItem)
        let index = NSMenu(title: L10n.t(.indexMenu))
        index.addItem(withTitle: L10n.t(.rebuildIndex), action: #selector(MainWindowController.rebuildIndex(_:)), keyEquivalent: "")
        index.addItem(withTitle: L10n.t(.fullDiskAccess), action: #selector(MainWindowController.openDiskAccessSettings(_:)), keyEquivalent: "")
        indexItem.submenu = index

        let helpItem = NSMenuItem()
        menu.addItem(helpItem)
        let help = NSMenu(title: L10n.t(.helpMenu))
        help.addItem(withTitle: L10n.t(.searchSyntax), action: #selector(showSearchHelp), keyEquivalent: "")
        help.addItem(withTitle: L10n.t(.helpApp), action: #selector(showAbout), keyEquivalent: "?")
        helpItem.submenu = help

        NSApp.mainMenu = menu
    }

    private func rebuildLookInMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        for place in FolderPlaces.existing(in: AppRuntime.homeURL) {
            let item = NSMenuItem(
                title: L10n.folderPlace(place.relative),
                action: #selector(MainWindowController.setLookIn(_:)),
                keyEquivalent: ""
            )
            item.representedObject = place.relative
            menu.addItem(item)
        }
        let extras = windowController?.extraLookInFolders() ?? []
        if !extras.isEmpty {
            menu.addItem(.separator())
            for url in extras {
                let item = NSMenuItem(
                    title: url.lastPathComponent,
                    action: #selector(MainWindowController.setLookIn(_:)),
                    keyEquivalent: ""
                )
                item.representedObject = url.path
                menu.addItem(item)
            }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === bookmarkMenu {
            menu.removeAllItems()
            menu.addItem(withTitle: L10n.t(.addBookmark), action: #selector(MainWindowController.addBookmark(_:)), keyEquivalent: "d")
            let items = windowController?.bookmarkMenuItems() ?? []
            if !items.isEmpty {
                menu.addItem(.separator())
                for item in items {
                    menu.addItem(item)
                }
                let removals = windowController?.removeBookmarkMenuItems() ?? []
                if !removals.isEmpty {
                    menu.addItem(.separator())
                    let remove = NSMenuItem(title: L10n.t(.removeBookmark), action: nil, keyEquivalent: "")
                    let sub = NSMenu()
                    for item in removals {
                        sub.addItem(item)
                    }
                    remove.submenu = sub
                    menu.addItem(remove)
                }
            }
            return
        }
        if menu === searchMenu {
            if let lookIn = menu.items.first(where: { $0.tag == 711 }), let sub = lookIn.submenu {
                rebuildLookInMenu(sub)
            }
            for item in menu.items.reversed() where item.tag == 710 {
                menu.removeItem(item)
            }
            let recents = windowController?.historyMenuItems() ?? []
            if !recents.isEmpty {
                let separator = NSMenuItem.separator()
                separator.tag = 710
                menu.addItem(separator)
                for item in recents {
                    item.tag = 710
                    menu.addItem(item)
                }
            }
        }
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = L10n.productName
        alert.informativeText = L10n.t(.aboutBody)
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func showSearchHelp() {
        let alert = NSAlert()
        alert.messageText = L10n.t(.syntaxTitle)
        alert.informativeText = L10n.t(.syntaxBody)
        alert.alertStyle = .informational
        alert.runModal()
    }
}
