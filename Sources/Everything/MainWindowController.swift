import AppKit
import EverythingCore

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
        default:
            super.keyDown(with: event)
        }
    }
}

final class MainWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, FileScannerDelegate {
    private let index = FileIndex()
    private lazy var scanner = FileScanner(index: index)

    private var searchField: SearchField!
    private var tableView: ResultsTableView!
    private var statusLeft: NSTextField!
    private var statusRight: NSTextField!
    private var headerMenu: NSMenu!

    private var options = SearchOptions()
    private var sort = SortState()
    private var query = ""
    private var resultIndices: [Int] = []
    private var lastSearch: (query: String, options: SearchOptions, indices: [Int])?
    private var searchGeneration = 0
    private var isIndexing = true
    private var indexedCount = 0
    private var refreshPending = false

    private let dateFormatter = PathDisplay.dateFormatter
    private var folderIcon: NSImage!
    private var fileIcon: NSImage!
    private var iconByExt: [String: NSImage] = [:]

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Everything"
        window.minSize = NSSize(width: 520, height: 320)
        window.center()
        window.setFrameAutosaveName("EverythingMain")
        self.init(window: window)
        window.delegate = self
        folderIcon = NSWorkspace.shared.icon(forFileType: NSFileTypeForHFSTypeCode(OSType(kGenericFolderIcon)))
        folderIcon.size = NSSize(width: 16, height: 16)
        fileIcon = NSWorkspace.shared.icon(forFileType: "public.data")
        fileIcon.size = NSSize(width: 16, height: 16)
        buildUI()
        scanner.delegate = self
        scanner.start()
        rerunSearch()
    }

    private func buildUI() {
        guard let window else { return }
        let content = NSView(frame: window.contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        window.contentView = content

        searchField = SearchField(string: "")
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = ""
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
        tableView.menu = makeContextMenu()

        addColumn(id: "name", title: "Name", width: 280, min: 80)
        addColumn(id: "path", title: "Path", width: 420, min: 80)
        addColumn(id: "size", title: "Size", width: 90, min: 50)
        addColumn(id: "modified", title: "Date Modified", width: 140, min: 80)
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

        statusLeft = NSTextField(labelWithString: "Indexing...")
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
        menu.addItem(NSMenuItem(title: "Open", action: #selector(openSelected(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open Path", action: #selector(openPath(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Copy", action: #selector(copy(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Copy Full Name to Clipboard", action: #selector(copyFullPath(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Copy Path to Clipboard", action: #selector(copyParentPath(_:)), keyEquivalent: ""))
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
        rerunSearch()
    }

    private func rerunSearch() {
        searchGeneration += 1
        let generation = searchGeneration
        let query = self.query
        let options = self.options
        let sort = self.sort
        let previous = lastSearch
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let indices = self.index.search(query: query, options: options, sort: sort, previous: previous)
            DispatchQueue.main.async {
                guard generation == self.searchGeneration else { return }
                self.lastSearch = (query, options, indices)
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
        let formatted = Self.group(objects)
        if isIndexing {
            statusLeft.stringValue = "Indexing... \(formatted) objects"
        } else {
            statusLeft.stringValue = "\(formatted) objects"
        }

        var flags: [String] = []
        if options.matchCase { flags.append("CASE") }
        if options.matchWholeWord { flags.append("WHOLE WORD") }
        if options.matchPath { flags.append("PATH") }
        statusRight.stringValue = flags.joined(separator: "   ")
    }

    private static func group(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
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

    @objc func rebuildIndex(_ sender: Any?) {
        isIndexing = true
        indexedCount = 0
        resultIndices = []
        lastSearch = nil
        tableView.reloadData()
        updateStatus()
        scanner.rebuild()
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
            cell.textField?.stringValue = entry.name
            cell.textField?.alignment = .left
            cell.imageView?.image = icon(for: entry)
        case "path":
            cell.textField?.stringValue = PathDisplay.pretty(entry.directory)
            cell.textField?.alignment = .left
        case "size":
            cell.textField?.stringValue = PathDisplay.formatSize(entry.size, isDirectory: entry.isDirectory)
            cell.textField?.alignment = .right
        case "modified":
            cell.textField?.stringValue = PathDisplay.formatDate(entry.modified)
            cell.textField?.alignment = .left
        default:
            break
        }
        return cell
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
        switch tableColumn.identifier.rawValue {
        case "name": setSort(.name)
        case "path": setSort(.path)
        case "size": setSort(.size)
        case "modified": setSort(.modified)
        default: break
        }
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
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
    }

    func scannerDidFail(_ scanner: FileScanner, error: Error) {
        isIndexing = false
        statusLeft.stringValue = error.localizedDescription
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if tableView.selectedRow < 0 {
            focusSearch(selectAll: false)
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
        case #selector(openSelected(_:)), #selector(openPath(_:)),
             #selector(copyFullPath(_:)), #selector(copyParentPath(_:)):
            return tableView.selectedRow >= 0
        default:
            return true
        }
    }
}
