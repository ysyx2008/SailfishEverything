import AppKit
import SailfishEverythingCore

@objc private protocol StandardEditingActions {
    func undo(_ sender: Any?)
    func redo(_ sender: Any?)
    func cut(_ sender: Any?)
    func paste(_ sender: Any?)
}

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
        DiagnosticLog.shared.event("session", "start")
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowController?.showMainWindow()
        return true
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.toolTip = L10n.productName
        if let icon = menuBarIcon() {
            item.button?.image = icon
            item.button?.imagePosition = .imageOnly
        } else {
            item.button?.title = L10n.statusItemTitle
        }
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    private func menuBarIcon() -> NSImage? {
        if let image = menuBarIconFromArtwork() {
            return image
        }
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.black.setFill()
            NSColor.black.setStroke()
            let ring = menuBarGlass(
                center: NSPoint(x: rect.midX - 0.2, y: rect.midY + 0.2),
                radius: rect.width * 0.30,
                handle: rect.width * 0.20,
                width: 1.7
            )
            ring.stroke()
            menuBarSailfish(in: rect.insetBy(dx: 0.2, dy: 1.6)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func menuBarIconFromArtwork() -> NSImage? {
        guard let url = menuBarArtworkURL(), let loaded = NSImage(contentsOf: url) else { return nil }
        let image = loaded.copy() as? NSImage ?? loaded
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    private func menuBarArtworkURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png") {
            return bundled
        }
        var dir = Bundle.main.bundleURL
        for _ in 0..<8 {
            dir.deleteLastPathComponent()
            let candidate = dir.appendingPathComponent("Resources/MenuBarIcon.png")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private func statusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: L10n.t(.showApp), action: #selector(showWindow), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.t(.quitApp), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        let type = NSApp.currentEvent?.type
        if type == .rightMouseUp {
            statusItem?.menu = statusMenu()
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
            return
        }
        windowController?.toggleMainWindow()
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
        let services = NSMenuItem(title: L10n.t(.services), action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu()
        services.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(services)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L10n.t(.hideApp), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: L10n.t(.hideOthers), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: L10n.t(.showAll), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
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
        file.addItem(withTitle: L10n.t(.rename), action: #selector(MainWindowController.renameSelected(_:)), keyEquivalent: "")
        let trash = file.addItem(withTitle: L10n.t(.moveToTrash), action: #selector(MainWindowController.deleteSelected(_:)), keyEquivalent: String(UnicodeScalar(NSBackspaceCharacter)!))
        trash.keyEquivalentModifierMask = [.command]
        file.addItem(.separator())
        file.addItem(withTitle: L10n.t(.export), action: #selector(MainWindowController.exportResults(_:)), keyEquivalent: "s")
        file.addItem(.separator())
        file.addItem(withTitle: L10n.t(.close), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        file.addItem(withTitle: L10n.t(.exit), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        fileItem.submenu = file

        let editItem = NSMenuItem()
        menu.addItem(editItem)
        let edit = NSMenu(title: L10n.t(.editMenu))
        edit.addItem(withTitle: L10n.t(.undo), action: #selector(StandardEditingActions.undo(_:)), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: L10n.t(.redo), action: #selector(StandardEditingActions.redo(_:)), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: L10n.t(.cut), action: #selector(StandardEditingActions.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L10n.t(.copy), action: #selector(MainWindowController.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L10n.t(.paste), action: #selector(StandardEditingActions.paste(_:)), keyEquivalent: "v")
        let copyFull = edit.addItem(withTitle: L10n.t(.copyFullName), action: #selector(MainWindowController.copyFullPath(_:)), keyEquivalent: "c")
        copyFull.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(withTitle: L10n.t(.copyPath), action: #selector(MainWindowController.copyParentPath(_:)), keyEquivalent: "")
        edit.addItem(.separator())
        edit.addItem(withTitle: L10n.t(.selectAll), action: #selector(MainWindowController.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(withTitle: L10n.t(.find), action: #selector(MainWindowController.focusSearchFromMenu(_:)), keyEquivalent: "f")
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

        let windowItem = NSMenuItem()
        menu.addItem(windowItem)
        let windowMenu = NSMenu(title: L10n.t(.windowMenu))
        windowMenu.addItem(withTitle: L10n.t(.minimize), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: L10n.t(.zoom), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: L10n.t(.bringAllToFront), action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        let helpItem = NSMenuItem()
        menu.addItem(helpItem)
        let help = NSMenu(title: L10n.t(.helpMenu))
        help.addItem(withTitle: L10n.t(.searchSyntax), action: #selector(showSearchHelp), keyEquivalent: "")
        help.addItem(withTitle: L10n.t(.openDiagnosticLog), action: #selector(openDiagnosticLog), keyEquivalent: "")
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

    @objc private func openDiagnosticLog() {
        let log = DiagnosticLog.shared
        log.ensureFileExists()
        log.event("session", "open log")
        if !NSWorkspace.shared.open(log.fileURL) {
            NSWorkspace.shared.activateFileViewerSelecting([log.fileURL])
        }
    }
}

private func menuBarGlass(center: NSPoint, radius: CGFloat, handle: CGFloat, width: CGFloat) -> NSBezierPath {
    let ring = NSBezierPath(ovalIn: NSRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    ))
    ring.lineWidth = width
    let stem = NSBezierPath()
    let angle: CGFloat = -.pi / 4
    stem.move(to: NSPoint(
        x: center.x + cos(angle) * (radius + width * 0.15),
        y: center.y + sin(angle) * (radius + width * 0.15)
    ))
    stem.line(to: NSPoint(
        x: center.x + cos(angle) * (radius + handle),
        y: center.y + sin(angle) * (radius + handle)
    ))
    stem.lineWidth = width
    stem.lineCapStyle = .round
    ring.append(stem)
    return ring
}

private func menuBarSailfish(in box: NSRect) -> NSBezierPath {
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: box.minX + x * box.width, y: box.minY + y * box.height)
    }
    let fish = NSBezierPath()
    fish.move(to: p(0.97, 0.54))
    fish.line(to: p(0.76, 0.58))
    fish.curve(to: p(0.64, 0.60), controlPoint1: p(0.72, 0.63), controlPoint2: p(0.68, 0.62))
    fish.line(to: p(0.60, 0.94))
    fish.curve(to: p(0.38, 0.62), controlPoint1: p(0.54, 0.90), controlPoint2: p(0.42, 0.74))
    fish.curve(to: p(0.24, 0.58), controlPoint1: p(0.32, 0.60), controlPoint2: p(0.28, 0.60))
    fish.line(to: p(0.03, 0.80))
    fish.curve(to: p(0.17, 0.51), controlPoint1: p(0.10, 0.70), controlPoint2: p(0.17, 0.58))
    fish.curve(to: p(0.04, 0.22), controlPoint1: p(0.17, 0.44), controlPoint2: p(0.10, 0.30))
    fish.line(to: p(0.24, 0.42))
    fish.curve(to: p(0.64, 0.38), controlPoint1: p(0.34, 0.34), controlPoint2: p(0.50, 0.32))
    fish.curve(to: p(0.76, 0.46), controlPoint1: p(0.70, 0.36), controlPoint2: p(0.74, 0.40))
    fish.line(to: p(0.97, 0.54))
    fish.close()
    return fish
}
