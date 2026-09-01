import AppKit
import Quartz
import SailfishEverythingCore

final class SearchField: NSTextField {
    var onMoveToResults: (() -> Void)?
    var onActivate: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown {
            switch event.keyCode {
            case 125:
                onMoveToResults?()
                return true
            case 36, 76:
                onActivate?()
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125:
            onMoveToResults?()
        case 36, 76:
            onActivate?()
        default:
            super.keyDown(with: event)
        }
    }
}

final class ResultsTableView: NSTableView {
    var onOpen: (() -> Void)?
    var onOpenPath: (() -> Void)?
    var onFocusSearch: (() -> Void)?
    var onPreview: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126 where selectedRow <= 0:
            onFocusSearch?()
        case 36, 76:
            if event.modifierFlags.contains(.command) {
                onOpenPath?()
            } else {
                onOpen?()
            }
        case 53:
            onFocusSearch?()
        case 49:
            onPreview?()
        default:
            super.keyDown(with: event)
        }
    }
}

final class MainWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, FileScannerDelegate {
    private let index = FileIndex()
    private var home: URL = AppRuntime.homeURL
    private var settings: IndexSettings = .default
    private var scanner: FileScanner!
    private var settingsWindow: SettingsWindowController?
    private var history: [String] = []

    private var searchField: SearchField!
    private var tableView: ResultsTableView!
    private var statusLeft: NSTextField!
    private var statusRight: NSTextField!
    private var headerMenu: NSMenu!
    private let preview = PreviewController()

    private var options = SearchOptions()
    private var filter: ResultFilter = .all
    private var bookmarks: [Bookmark] = BookmarkStore.load()
    private var sort = SortState()
    private var query = ""
    private var resultIndices: [Int] = []
    private var lastSearch: SearchCursor?
    private var searchGeneration = 0
    private let searchLock = NSLock()
    private let searchQueue = DispatchQueue(label: "sailfish.search", qos: .userInteractive)
    private var isIndexing = true
    private var indexingPhase = L10n.t(.homeFolder)
    private var indexedCount = 0
    private var refreshPending = false

    private let dateFormatter = PathDisplay.dateFormatter
    private var folderIcon: NSImage!
    private var fileIcon: NSImage!
    private var iconByExt: [String: NSImage] = [:]

    init(home: URL = AppRuntime.homeURL, enableWatch: Bool = !AppRuntime.isE2E, startScanning: Bool = true) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.productName
        window.minSize = NSSize(width: 720, height: 360)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.center()
        if !AppRuntime.isE2E {
            window.setFrameAutosaveName("SailfishEverythingMain")
        }
        super.init(window: window)
        self.home = home
        self.settings = AppRuntime.isE2E ? .default : IndexSettingsStore.load()
        self.bookmarks = AppRuntime.isE2E ? [] : BookmarkStore.load()
        self.history = AppRuntime.isE2E ? [] : SearchHistoryStore.load()
        window.delegate = self
        folderIcon = NSWorkspace.shared.icon(forFileType: NSFileTypeForHFSTypeCode(OSType(kGenericFolderIcon)))
        folderIcon.size = NSSize(width: 16, height: 16)
        fileIcon = NSWorkspace.shared.icon(forFileType: "public.data")
        fileIcon.size = NSSize(width: 16, height: 16)
        scanner = FileScanner(index: index, root: home, settings: settings, enableWatch: enableWatch)
        buildUI()
        scanner.delegate = self
        if startScanning {
            scanner.start()
            rerunSearch()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func scanSynchronouslyForE2E() {
        scanner.scanSynchronously()
        E2EDump.write(index: index, title: window?.title ?? L10n.productName)
    }

    private func buildUI() {
        guard let window else { return }
        let content = NSView(frame: window.contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        window.contentView = content

        searchField = SearchField(string: "")
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = L10n.t(.searchPlaceholder)
        searchField.font = NSFont.systemFont(ofSize: 13)
        searchField.focusRingType = .exterior
        searchField.bezelStyle = .squareBezel
        searchField.isBordered = true
        searchField.drawsBackground = true
        searchField.delegate = self
        searchField.onMoveToResults = { [weak self] in self?.focusResults() }
        searchField.onActivate = { [weak self] in self?.activateFromSearch() }
        content.addSubview(searchField)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        content.addSubview(scroll)

        tableView = ResultsTableView()
        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = 18
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.usesAutomaticRowHeights = false
        tableView.rowSizeStyle = .custom
        tableView.intercellSpacing = NSSize(width: 6, height: 1)
        tableView.doubleAction = #selector(openSelected(_:))
        tableView.target = self
        tableView.dataSource = self
        tableView.delegate = self
        tableView.onOpen = { [weak self] in self?.openSelected(nil) }
        tableView.onOpenPath = { [weak self] in self?.openPath(nil) }
        tableView.onFocusSearch = { [weak self] in self?.focusSearch(selectAll: false) }
        tableView.onPreview = { [weak self] in self?.previewSelected(nil) }
        tableView.menu = makeContextMenu()

        addColumn(id: "name", title: L10n.t(.columnName), width: 280, min: 80)
        addColumn(id: "path", title: L10n.t(.columnPath), width: 420, min: 80)
        addColumn(id: "size", title: L10n.t(.columnSize), width: 90, min: 50)
        addColumn(id: "modified", title: L10n.t(.columnModified), width: 140, min: 80)
        tableView.tableColumns[2].headerCell.alignment = .right

        headerMenu = NSMenu()
        for column in tableView.tableColumns {
            let item = NSMenuItem(title: column.title, action: #selector(toggleColumn(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = column.identifier
            item.state = .on
            headerMenu.addItem(item)
        }
        tableView.headerView?.menu = headerMenu

        scroll.documentView = tableView

        let statusBar = NSView()
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(statusBar)

        statusLeft = NSTextField(labelWithString: "")
        statusLeft.translatesAutoresizingMaskIntoConstraints = false
        statusLeft.font = NSFont.systemFont(ofSize: 11)
        statusLeft.textColor = .secondaryLabelColor
        statusBar.addSubview(statusLeft)

        statusRight = NSTextField(labelWithString: "")
        statusRight.translatesAutoresizingMaskIntoConstraints = false
        statusRight.font = NSFont.systemFont(ofSize: 11)
        statusRight.textColor = .secondaryLabelColor
        statusRight.alignment = .right
        statusBar.addSubview(statusRight)

        let click = NSClickGestureRecognizer(target: self, action: #selector(statusRightClicked(_:)))
        statusRight.addGestureRecognizer(click)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 6),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 6),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -6),
            searchField.heightAnchor.constraint(equalToConstant: 22),

            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 22),

            statusLeft.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 8),
            statusLeft.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            statusRight.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -8),
            statusRight.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            statusLeft.trailingAnchor.constraint(lessThanOrEqualTo: statusRight.leadingAnchor, constant: -12),
        ])

        window.makeFirstResponder(searchField)
        updateStatus()
    }

    private func addColumn(id: String, title: String, width: CGFloat, min: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        column.minWidth = min
        column.resizingMask = .userResizingMask
        tableView.addTableColumn(column)
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L10n.t(.open), action: #selector(openSelected(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.t(.openPath), action: #selector(openPath(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.t(.quickLook), action: #selector(previewSelected(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L10n.t(.copy), action: #selector(copy(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.t(.copyFullName), action: #selector(copyFullPath(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.t(.copyPath), action: #selector(copyParentPath(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L10n.t(.getInfo), action: #selector(showInfo(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.t(.rename), action: #selector(renameSelected(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.t(.moveToTrash), action: #selector(deleteSelected(_:)), keyEquivalent: ""))
        return menu
    }

    func focusSearch(selectAll: Bool) {
        window?.makeFirstResponder(searchField)
        if selectAll {
            searchField.currentEditor()?.selectAll(nil)
        }
    }

    private func focusResults() {
        guard tableView.numberOfRows > 0 else { return }
        if tableView.selectedRow < 0 {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        window?.makeFirstResponder(tableView)
        tableView.scrollRowToVisible(max(tableView.selectedRow, 0))
    }

    private func activateFromSearch() {
        if tableView.selectedRow < 0, tableView.numberOfRows > 0 {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        focusResults()
    }

    func controlTextDidChange(_ obj: Notification) {
        query = searchField.stringValue
        if query.count >= 2, !AppRuntime.isE2E {
            history = SearchHistoryStore.record(query)
        }
        rerunSearch()
    }

    private func rerunSearch() {
        searchLock.lock()
        searchGeneration += 1
        let generation = searchGeneration
        searchLock.unlock()
        let query = self.query
        let options = self.options
        let filter = self.filter
        let sort = self.sort
        let previous = lastSearch
        let allowFullSort = !isIndexing
        searchQueue.async { [weak self] in
            guard let self else { return }
            let stillCurrent: () -> Bool = {
                self.searchLock.lock()
                defer { self.searchLock.unlock() }
                return self.searchGeneration == generation
            }
            guard stillCurrent() else { return }
            let indices = self.index.search(
                query: query,
                options: options,
                filter: filter,
                sort: sort,
                previous: previous,
                allowFullSort: allowFullSort,
                shouldContinue: stillCurrent
            )
            DispatchQueue.main.async {
                guard stillCurrent() else { return }
                self.lastSearch = SearchCursor(query: query, options: options, filter: filter, sort: sort, indices: indices)
                self.resultIndices = indices
                self.tableView.reloadData()
                self.updateStatus()
            }
        }
    }

    private func scheduleSearchRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            self.refreshPending = false
            self.lastSearch = nil
            self.rerunSearch()
        }
    }

    private func updateStatus() {
        let objects = resultIndices.count
        let selected = tableView?.selectedRowIndexes.count ?? 0
        let bytes: Int64 = selected > 0
            ? selectedEntries().reduce(0) { $0 + (FileMetadata.size(of: $1) ?? 0) }
            : 0
        var left = L10n.statusLine(objects: objects, selected: selected, bytes: bytes)
        if isIndexing {
            left = L10n.format(.indexing, indexingPhase)
                + L10n.format(.indexedCount, ResultStats.formatCount(indexedCount))
                + left
        } else if options.regex, !Query.isValidRegex(query, matchCase: options.matchCase) {
            left = L10n.t(.invalidRegex) + left
        }
        if !AppRuntime.isE2E, !isIndexing, !DiskAccess.isFullyTrusted(home: home) {
            left += " · " + L10n.t(.needFullDiskAccess)
        }
        statusLeft.stringValue = left

        var flags: [String] = []
        if options.matchCase { flags.append("CASE") }
        if options.matchWholeWord { flags.append("WHOLE WORD") }
        if options.matchPath { flags.append("PATH") }
        if options.regex { flags.append("REGEX") }
        if !filter.statusLabel.isEmpty { flags.append(filter.statusLabel) }
        if !options.inFolder.isEmpty {
            flags.append(URL(fileURLWithPath: options.inFolder).lastPathComponent.uppercased())
        }
        statusRight.stringValue = flags.joined(separator: "   ")
    }

    @objc private func statusRightClicked(_ sender: NSClickGestureRecognizer) {
        let loc = sender.location(in: statusRight)
        let text = statusRight.stringValue as NSString
        let width = statusRight.bounds.width
        let size = text.size(withAttributes: [.font: statusRight.font as Any])
        let startX = width - size.width
        guard loc.x >= startX else { return }
        if text.contains("PATH"), loc.x > startX + size.width * 0.66 {
            toggleMatchPath(nil)
        } else if text.contains("WHOLE WORD"), loc.x > startX + size.width * 0.33 {
            toggleMatchWholeWord(nil)
        } else if text.contains("CASE") {
            toggleMatchCase(nil)
        }
    }

    // MARK: - Actions

    @objc func openSelected(_ sender: Any?) {
        for entry in selectedEntries() {
            NSWorkspace.shared.open(URL(fileURLWithPath: entry.path, isDirectory: entry.isDirectory))
        }
    }

    @objc func openPath(_ sender: Any?) {
        let urls = selectedEntries().map { URL(fileURLWithPath: $0.path) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    @objc func copyFullPath(_ sender: Any?) {
        copyStrings(selectedEntries().map(\.path))
    }

    @objc func copyParentPath(_ sender: Any?) {
        copyStrings(selectedEntries().map(\.directory))
    }

    @objc func copy(_ sender: Any?) {
        if window?.firstResponder === searchField.currentEditor() {
            searchField.currentEditor()?.copy(sender)
            return
        }
        copyStrings(selectedEntries().map(\.name))
    }

    @objc override func selectAll(_ sender: Any?) {
        if window?.firstResponder === searchField.currentEditor() {
            searchField.currentEditor()?.selectAll(sender)
            return
        }
        tableView.selectAll(sender)
    }

    private func copyStrings(_ strings: [String]) {
        guard !strings.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(strings.joined(separator: "\n"), forType: .string)
    }

    private func selectedEntries() -> [FileEntry] {
        index.entries(at: tableView.selectedRowIndexes.compactMap { row in
            row < resultIndices.count ? resultIndices[row] : nil
        })
    }

    @objc func toggleMatchCase(_ sender: Any?) {
        options.matchCase.toggle()
        lastSearch = nil
        rerunSearch()
        updateStatus()
    }

    @objc func toggleMatchWholeWord(_ sender: Any?) {
        options.matchWholeWord.toggle()
        lastSearch = nil
        rerunSearch()
        updateStatus()
    }

    @objc func toggleMatchPath(_ sender: Any?) {
        options.matchPath.toggle()
        lastSearch = nil
        rerunSearch()
        updateStatus()
    }

    @objc func toggleRegex(_ sender: Any?) {
        options.regex.toggle()
        lastSearch = nil
        rerunSearch()
        updateStatus()
    }

    @objc func setFilter(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let next = ResultFilter(rawValue: raw) else { return }
        filter = next
        lastSearch = nil
        rerunSearch()
        updateStatus()
    }

    func extraLookInFolders() -> [URL] {
        settings.extraRootURLs(home: home)
    }

    @objc func setLookIn(_ sender: NSMenuItem) {
        guard let relative = sender.representedObject as? String else { return }
        options.inFolder = IndexSettings.resolvedLookIn(relative, home: home)
        lastSearch = nil
        rerunSearch()
        updateStatus()
    }

    @objc func openHistory(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        query = text
        searchField.stringValue = text
        lastSearch = nil
        rerunSearch()
        updateStatus()
    }

    func historyMenuItems() -> [NSMenuItem] {
        history.prefix(12).map { item in
            let menuItem = NSMenuItem(title: item, action: #selector(openHistory(_:)), keyEquivalent: "")
            menuItem.representedObject = item
            menuItem.target = self
            return menuItem
        }
    }

    @objc func exportResults(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.nameFieldStringValue = L10n.t(.exportFilename) + ".csv"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let selected = tableView.selectedRowIndexes
        let exportIndices: [Int]
        if selected.count > 0 {
            exportIndices = selected.compactMap { row in
                row < resultIndices.count ? resultIndices[row] : nil
            }
        } else {
            exportIndices = resultIndices
        }
        let entries = index.entries(at: exportIndices)
        let body = url.pathExtension.lowercased() == "txt" ? ResultExport.txt(entries) : ResultExport.csv(entries)
        try? body.data(using: .utf8)?.write(to: url)
    }

    @objc func deleteSelected(_ sender: Any?) {
        let entries = selectedEntries()
        guard !entries.isEmpty else { return }
        let urls = entries.map { URL(fileURLWithPath: $0.path) }
        NSWorkspace.shared.recycle(urls) { _, _ in }
        FileMetadata.invalidate(paths: entries.map(\.path))
        index.remove(paths: entries.map(\.path))
        lastSearch = nil
        rerunSearch()
    }

    @objc func renameSelected(_ sender: Any?) {
        guard let entry = selectedEntries().first else { return }
        let alert = NSAlert()
        alert.messageText = L10n.t(.rename)
        alert.informativeText = entry.name
        let field = NSTextField(string: entry.name)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.t(.ok))
        alert.addButton(withTitle: L10n.t(.cancel))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != entry.name else { return }
        let src = URL(fileURLWithPath: entry.path)
        let dest = src.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(at: src, to: dest)
            FileMetadata.invalidate(paths: [entry.path, dest.path])
            index.remove(paths: [entry.path])
            if let updated = FileScanner.makeEntry(for: dest, values: (try? dest.resourceValues(forKeys: [.nameKey, .isDirectoryKey])) ?? URLResourceValues()) {
                index.add([updated])
            }
            lastSearch = nil
            rerunSearch()
        } catch {
            let fail = NSAlert(error: error)
            fail.runModal()
        }
    }

    @objc func addBookmark(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = L10n.t(.addBookmarkTitle)
        let field = NSTextField(string: query.isEmpty ? L10n.t(.untitled) : query)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.t(.ok))
        alert.addButton(withTitle: L10n.t(.cancel))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        bookmarks.append(Bookmark(name: name, query: query, options: options, filter: filter))
        if !AppRuntime.isE2E {
            BookmarkStore.save(bookmarks)
        }
    }

    @objc func openBookmark(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let id = UUID(uuidString: raw),
              let bookmark = bookmarks.first(where: { $0.id == id }) else { return }
        query = bookmark.query
        options = bookmark.options
        filter = bookmark.filter
        searchField.stringValue = query
        lastSearch = nil
        rerunSearch()
        updateStatus()
    }

    func bookmarkMenuItems() -> [NSMenuItem] {
        bookmarks.map { bookmark in
            let item = NSMenuItem(title: bookmark.name, action: #selector(openBookmark(_:)), keyEquivalent: "")
            item.representedObject = bookmark.id.uuidString
            item.target = self
            return item
        }
    }

    func removeBookmarkMenuItems() -> [NSMenuItem] {
        bookmarks.map { bookmark in
            let item = NSMenuItem(title: bookmark.name, action: #selector(removeBookmark(_:)), keyEquivalent: "")
            item.representedObject = bookmark.id.uuidString
            item.target = self
            return item
        }
    }

    @objc func removeBookmark(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let id = UUID(uuidString: raw) else { return }
        bookmarks.removeAll { $0.id == id }
        if !AppRuntime.isE2E {
            BookmarkStore.save(bookmarks)
        }
    }

    @objc func rebuildIndex(_ sender: Any?) {
        isIndexing = true
        indexingPhase = L10n.t(.homeFolder)
        indexedCount = 0
        resultIndices = []
        lastSearch = nil
        tableView.reloadData()
        updateStatus()
        scanner.rebuild()
    }

    @objc func showOptions(_ sender: Any?) {
        settingsWindow = SettingsWindowController(settings: settings, hotKey: AppHotKeyStore.load()) { [weak self] newSettings in
            self?.applySettings(newSettings)
        } onHotKey: { combo in
            AppDelegate.shared.applyHotKey(combo)
        }
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    private func applySettings(_ newSettings: IndexSettings) {
        settings = newSettings
        if !AppRuntime.isE2E {
            IndexSettingsStore.save(newSettings)
        }
        settingsWindow = nil
        isIndexing = true
        indexingPhase = L10n.t(.homeFolder)
        indexedCount = 0
        resultIndices = []
        lastSearch = nil
        tableView.reloadData()
        updateStatus()
        scanner.apply(newSettings)
    }

    @objc func refreshView(_ sender: Any?) {
        lastSearch = nil
        rerunSearch()
    }

    @objc func sortByName(_ sender: Any?) { setSort(.name) }
    @objc func sortByPath(_ sender: Any?) { setSort(.path) }
    @objc func sortBySize(_ sender: Any?) { setSort(.size) }
    @objc func sortByDate(_ sender: Any?) { setSort(.modified) }

    private func setSort(_ column: SortColumn) {
        if sort.column == column {
            sort.ascending.toggle()
        } else {
            sort.column = column
            sort.ascending = column != .size && column != .modified
        }
        updateSortIndicators()
        lastSearch = nil
        rerunSearch()
    }

    private func updateSortIndicators() {
        for (index, column) in tableView.tableColumns.enumerated() {
            if index == sort.column.rawValue {
                tableView.setIndicatorImage(
                    NSImage(named: sort.ascending ? NSImage.Name("NSAscendingSortIndicator") : NSImage.Name("NSDescendingSortIndicator")),
                    in: column
                )
            } else {
                tableView.setIndicatorImage(nil, in: column)
            }
        }
    }

    @objc private func toggleColumn(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? NSUserInterfaceItemIdentifier,
              let column = tableView.tableColumn(withIdentifier: id) else { return }
        column.isHidden.toggle()
        sender.state = column.isHidden ? .off : .on
    }

    @objc func matchCaseState() -> NSControl.StateValue { options.matchCase ? .on : .off }
    @objc func matchWholeWordState() -> NSControl.StateValue { options.matchWholeWord ? .on : .off }
    @objc func matchPathState() -> NSControl.StateValue { options.matchPath ? .on : .off }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        resultIndices.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < resultIndices.count, let entry = index.entry(at: resultIndices[row]),
              let tableColumn else { return nil }
        let id = tableColumn.identifier.rawValue
        let cellID = NSUserInterfaceItemIdentifier("cell-\(id)")
        let cell = tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView ?? {
            let created = NSTableCellView()
            created.identifier = cellID
            let text = NSTextField(labelWithString: "")
            text.translatesAutoresizingMaskIntoConstraints = false
            text.font = NSFont.systemFont(ofSize: 12)
            text.lineBreakMode = .byTruncatingMiddle
            text.drawsBackground = false
            text.isBordered = false
            created.addSubview(text)
            created.textField = text
            if id == "name" {
                let image = NSImageView()
                image.translatesAutoresizingMaskIntoConstraints = false
                image.imageScaling = .scaleProportionallyUpOrDown
                created.addSubview(image)
                created.imageView = image
                NSLayoutConstraint.activate([
                    image.leadingAnchor.constraint(equalTo: created.leadingAnchor, constant: 2),
                    image.centerYAnchor.constraint(equalTo: created.centerYAnchor),
                    image.widthAnchor.constraint(equalToConstant: 16),
                    image.heightAnchor.constraint(equalToConstant: 16),
                    text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 4),
                    text.trailingAnchor.constraint(equalTo: created.trailingAnchor, constant: -2),
                    text.centerYAnchor.constraint(equalTo: created.centerYAnchor),
                ])
            } else {
                NSLayoutConstraint.activate([
                    text.leadingAnchor.constraint(equalTo: created.leadingAnchor, constant: 2),
                    text.trailingAnchor.constraint(equalTo: created.trailingAnchor, constant: -4),
                    text.centerYAnchor.constraint(equalTo: created.centerYAnchor),
                ])
            }
            return created
        }()

        switch id {
        case "name":
            cell.textField?.stringValue = entry.isCloudOnly ? "\(entry.name)\(L10n.t(.cloudSuffix))" : entry.name
            cell.textField?.alignment = .left
            cell.textField?.textColor = entry.isCloudOnly ? .secondaryLabelColor : .labelColor
            cell.imageView?.image = icon(for: entry)
        case "path":
            cell.textField?.stringValue = PathDisplay.pretty(entry.directory)
            cell.textField?.alignment = .left
        case "size":
            cell.textField?.stringValue = PathDisplay.formatSize(FileMetadata.size(of: entry), isDirectory: entry.isDirectory)
            cell.textField?.alignment = .right
        case "modified":
            cell.textField?.stringValue = PathDisplay.formatDate(FileMetadata.modified(of: entry))
            cell.textField?.alignment = .left
        default:
            break
        }
        return cell
    }

    @objc func previewSelected(_ sender: Any?) {
        let urls = selectedEntries().map { URL(fileURLWithPath: $0.path, isDirectory: $0.isDirectory) }
        preview.show(urls: urls)
    }

    @objc func showInfo(_ sender: Any?) {
        let entries = selectedEntries()
        guard !entries.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = entries.count == 1 ? entries[0].name : L10n.format(.infoItems, entries.count)
        alert.informativeText = entries.prefix(8).map(FileInfo.summary).joined(separator: "\n\n")
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc func openDiskAccessSettings(_ sender: Any?) {
        if let url = DiskAccess.settingsURL {
            NSWorkspace.shared.open(url)
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard (notification.object as? NSTableView) === tableView else { return }
        updateStatus()
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptor = tableView.sortDescriptors.first,
              let key = descriptor.key else { return }
        let column: SortColumn
        switch key {
        case "name": column = .name
        case "path": column = .path
        case "size": column = .size
        default: column = .modified
        }
        sort = SortState(column: column, ascending: descriptor.ascending)
        lastSearch = nil
        rerunSearch()
    }

    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        guard tableView === self.tableView else { return }
        switch tableColumn.identifier.rawValue {
        case "name": setSort(.name)
        case "path": setSort(.path)
        case "size": setSort(.size)
        case "modified": setSort(.modified)
        default: break
        }
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard tableView === self.tableView else { return nil }
        guard row < resultIndices.count, let entry = index.entry(at: resultIndices[row]) else { return nil }
        return URL(fileURLWithPath: entry.path) as NSURL
    }

    private func icon(for entry: FileEntry) -> NSImage {
        if entry.isDirectory { return folderIcon }
        let ext = (entry.name as NSString).pathExtension.lowercased()
        if ext.isEmpty { return fileIcon }
        if let cached = iconByExt[ext] { return cached }
        let image = NSWorkspace.shared.icon(forFileType: ext)
        image.size = NSSize(width: 16, height: 16)
        iconByExt[ext] = image
        return image
    }

    // MARK: - Scanner

    func scanner(_ scanner: FileScanner, didBeginPhase title: String) {
        indexingPhase = title
        updateStatus()
    }

    func scanner(_ scanner: FileScanner, didAdd batch: [FileEntry], total: Int) {
        indexedCount = total
        scheduleSearchRefresh()
        updateStatus()
    }

    func scannerDidFinish(_ scanner: FileScanner, total: Int) {
        isIndexing = false
        indexedCount = total
        lastSearch = nil
        rerunSearch()
        updateStatus()
        if E2EDump.write(index: index, title: window?.title ?? "") {
            NSApp.terminate(nil)
        }
    }

    func scannerDidFail(_ scanner: FileScanner, error: Error) {
        isIndexing = false
        statusLeft.stringValue = error.localizedDescription
        if E2EDump.write(index: index, title: window?.title ?? "", error: error.localizedDescription) {
            NSApp.terminate(nil)
        }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = preview
        panel.delegate = preview
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {}

    func windowDidBecomeKey(_ notification: Notification) {
        if tableView.selectedRow < 0 {
            focusSearch(selectAll: false)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func showMainWindow() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        focusSearch(selectAll: false)
    }

    func toggleMainWindow() {
        if let window, window.isVisible, NSApp.isActive {
            window.orderOut(nil)
        } else {
            showMainWindow()
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleMatchCase(_:)):
            menuItem.state = options.matchCase ? .on : .off
            return true
        case #selector(toggleMatchWholeWord(_:)):
            menuItem.state = options.matchWholeWord ? .on : .off
            return true
        case #selector(toggleMatchPath(_:)):
            menuItem.state = options.matchPath ? .on : .off
            return true
        case #selector(toggleRegex(_:)):
            menuItem.state = options.regex ? .on : .off
            return true
        case #selector(setFilter(_:)):
            menuItem.state = (menuItem.representedObject as? String) == filter.rawValue ? .on : .off
            return true
        case #selector(setLookIn(_:)):
            let relative = menuItem.representedObject as? String ?? ""
            menuItem.state = options.inFolder == IndexSettings.resolvedLookIn(relative, home: home) ? .on : .off
            return true
        case #selector(openSelected(_:)), #selector(openPath(_:)),
             #selector(copyFullPath(_:)), #selector(copyParentPath(_:)),
             #selector(deleteSelected(_:)), #selector(renameSelected(_:)),
             #selector(previewSelected(_:)), #selector(showInfo(_:)):
            return tableView.selectedRow >= 0
        default:
            return true
        }
    }
}
