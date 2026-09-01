import AppKit
import SailfishEverythingCore

final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    var onSave: ((IndexSettings) -> Void)?
    var onHotKey: ((AppHotKey) -> Void)?

    private var settings: IndexSettings
    private var hotKey: AppHotKey
    private var excludeList: [String] = []
    private var extraList: [String] = []
    private var excludeTable: NSTableView!
    private var extraTable: NSTableView!
    private var skipHiddenCheckbox: NSButton!
    private var preferOpenedCheckbox: NSButton!
    private var launchAtLoginCheckbox: NSButton!
    private var hotKeyPopup: NSPopUpButton!

    init(
        settings: IndexSettings,
        hotKey: AppHotKey = AppHotKeyStore.load(),
        onSave: ((IndexSettings) -> Void)? = nil,
        onHotKey: ((AppHotKey) -> Void)? = nil
    ) {
        self.settings = settings
        self.hotKey = hotKey
        self.onSave = onSave
        self.onHotKey = onHotKey
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 700),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t(.settingsTitle)
        window.center()
        super.init(window: window)
        buildUI()
        reloadLists()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI() {
        guard let window else { return }
        let content = NSView(frame: window.contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        window.contentView = content

        skipHiddenCheckbox = NSButton(checkboxWithTitle: L10n.t(.skipHidden), target: self, action: #selector(toggleHidden))
        skipHiddenCheckbox.translatesAutoresizingMaskIntoConstraints = false
        skipHiddenCheckbox.state = settings.skipHiddenFolders ? .on : .off
        content.addSubview(skipHiddenCheckbox)

        preferOpenedCheckbox = NSButton(checkboxWithTitle: L10n.t(.preferOpened), target: self, action: #selector(togglePreferOpened))
        preferOpenedCheckbox.translatesAutoresizingMaskIntoConstraints = false
        preferOpenedCheckbox.state = settings.preferOpened ? .on : .off
        content.addSubview(preferOpenedCheckbox)

        launchAtLoginCheckbox = NSButton(checkboxWithTitle: L10n.t(.launchAtLogin), target: nil, action: nil)
        launchAtLoginCheckbox.translatesAutoresizingMaskIntoConstraints = false
        launchAtLoginCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off
        content.addSubview(launchAtLoginCheckbox)

        let hotKeyLabel = NSTextField(labelWithString: L10n.t(.hotKey))
        hotKeyLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(hotKeyLabel)

        hotKeyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        hotKeyPopup.translatesAutoresizingMaskIntoConstraints = false
        for combo in AppHotKey.allCases {
            hotKeyPopup.addItem(withTitle: combo.title)
            hotKeyPopup.lastItem?.representedObject = combo.rawValue
        }
        if let index = AppHotKey.allCases.firstIndex(of: hotKey) {
            hotKeyPopup.selectItem(at: index)
        }
        hotKeyPopup.target = self
        hotKeyPopup.action = #selector(changeHotKey)
        content.addSubview(hotKeyPopup)

        let diskButton = NSButton(title: L10n.t(.openFullDiskAccess), target: self, action: #selector(openDiskAccess))
        diskButton.translatesAutoresizingMaskIntoConstraints = false
        diskButton.bezelStyle = .rounded
        content.addSubview(diskButton)

        let diskHint = NSTextField(wrappingLabelWithString: DiskAccess.isFullyTrusted(home: AppRuntime.homeURL)
            ? L10n.t(.diskAccessOK)
            : L10n.t(.diskAccessNeeded))
        diskHint.translatesAutoresizingMaskIntoConstraints = false
        diskHint.textColor = .secondaryLabelColor
        diskHint.font = NSFont.systemFont(ofSize: 12)
        content.addSubview(diskHint)

        let hint = NSTextField(wrappingLabelWithString: L10n.t(.scanHint))
        hint.translatesAutoresizingMaskIntoConstraints = false
        hint.textColor = .secondaryLabelColor
        hint.font = NSFont.systemFont(ofSize: 12)
        content.addSubview(hint)

        let extraLabel = NSTextField(labelWithString: L10n.t(.extraFolders))
        extraLabel.translatesAutoresizingMaskIntoConstraints = false
        extraLabel.font = NSFont.boldSystemFont(ofSize: 12)
        content.addSubview(extraLabel)

        extraTable = makePlainTable()
        let extraScroll = wrap(extraTable)
        content.addSubview(extraScroll)

        let addExtra = NSButton(title: L10n.t(.add), target: self, action: #selector(addExtraFolder))
        addExtra.translatesAutoresizingMaskIntoConstraints = false
        addExtra.bezelStyle = .rounded
        content.addSubview(addExtra)

        let removeExtra = NSButton(title: L10n.t(.remove), target: self, action: #selector(removeExtraFolder))
        removeExtra.translatesAutoresizingMaskIntoConstraints = false
        removeExtra.bezelStyle = .rounded
        content.addSubview(removeExtra)

        let excludeLabel = NSTextField(labelWithString: L10n.t(.excludedFolders))
        excludeLabel.translatesAutoresizingMaskIntoConstraints = false
        excludeLabel.font = NSFont.boldSystemFont(ofSize: 12)
        content.addSubview(excludeLabel)

        excludeTable = makePlainTable()
        let excludeScroll = wrap(excludeTable)
        content.addSubview(excludeScroll)

        let addButton = NSButton(title: L10n.t(.add), target: self, action: #selector(addFolder))
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.bezelStyle = .rounded
        content.addSubview(addButton)

        let removeButton = NSButton(title: L10n.t(.remove), target: self, action: #selector(removeSelected))
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.bezelStyle = .rounded
        content.addSubview(removeButton)

        let restoreButton = NSButton(title: L10n.t(.restoreDefaults), target: self, action: #selector(restoreDefaults))
        restoreButton.translatesAutoresizingMaskIntoConstraints = false
        restoreButton.bezelStyle = .rounded
        content.addSubview(restoreButton)

        let doneButton = NSButton(title: L10n.t(.done), target: self, action: #selector(saveAndClose))
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        content.addSubview(doneButton)

        NSLayoutConstraint.activate([
            skipHiddenCheckbox.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            skipHiddenCheckbox.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            skipHiddenCheckbox.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            preferOpenedCheckbox.topAnchor.constraint(equalTo: skipHiddenCheckbox.bottomAnchor, constant: 8),
            preferOpenedCheckbox.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            preferOpenedCheckbox.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            launchAtLoginCheckbox.topAnchor.constraint(equalTo: preferOpenedCheckbox.bottomAnchor, constant: 8),
            launchAtLoginCheckbox.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            launchAtLoginCheckbox.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            hotKeyLabel.topAnchor.constraint(equalTo: launchAtLoginCheckbox.bottomAnchor, constant: 12),
            hotKeyLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            hotKeyPopup.centerYAnchor.constraint(equalTo: hotKeyLabel.centerYAnchor),
            hotKeyPopup.leadingAnchor.constraint(equalTo: hotKeyLabel.trailingAnchor, constant: 8),

            diskButton.topAnchor.constraint(equalTo: hotKeyLabel.bottomAnchor, constant: 12),
            diskButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),

            diskHint.topAnchor.constraint(equalTo: diskButton.bottomAnchor, constant: 4),
            diskHint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            diskHint.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            hint.topAnchor.constraint(equalTo: diskHint.bottomAnchor, constant: 10),
            hint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            hint.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            extraLabel.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 14),
            extraLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),

            extraScroll.topAnchor.constraint(equalTo: extraLabel.bottomAnchor, constant: 6),
            extraScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            extraScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            extraScroll.heightAnchor.constraint(equalToConstant: 90),

            addExtra.topAnchor.constraint(equalTo: extraScroll.bottomAnchor, constant: 8),
            addExtra.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            removeExtra.leadingAnchor.constraint(equalTo: addExtra.trailingAnchor, constant: 8),
            removeExtra.centerYAnchor.constraint(equalTo: addExtra.centerYAnchor),

            excludeLabel.topAnchor.constraint(equalTo: addExtra.bottomAnchor, constant: 16),
            excludeLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),

            excludeScroll.topAnchor.constraint(equalTo: excludeLabel.bottomAnchor, constant: 6),
            excludeScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            excludeScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            excludeScroll.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -12),

            addButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            addButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            removeButton.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: 8),
            removeButton.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),
            restoreButton.leadingAnchor.constraint(equalTo: removeButton.trailingAnchor, constant: 8),
            restoreButton.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),
            doneButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            doneButton.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),
        ])
    }

    private func makePlainTable() -> NSTableView {
        let table = NSTableView()
        table.headerView = nil
        table.rowHeight = 22
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        column.width = 480
        table.addTableColumn(column)
        table.dataSource = self
        table.delegate = self
        return table
    }

    private func wrap(_ table: NSTableView) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = table
        return scroll
    }

    private func reloadLists() {
        excludeList = settings.displayExcludes()
        extraList = settings.extraRoots
        excludeTable?.reloadData()
        extraTable?.reloadData()
    }

    @objc private func toggleHidden() {
        settings.skipHiddenFolders = skipHiddenCheckbox.state == .on
    }

    @objc private func togglePreferOpened() {
        settings.preferOpened = preferOpenedCheckbox.state == .on
    }

    @objc private func changeHotKey() {
        guard let raw = hotKeyPopup.selectedItem?.representedObject as? String,
              let combo = AppHotKey(rawValue: raw) else { return }
        hotKey = combo
    }

    @objc private func openDiskAccess() {
        if let url = DiskAccess.settingsURL {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func addExtraFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = L10n.t(.extraFolderPrompt)
        panel.message = L10n.t(.extraFolderMessage)
        guard panel.runModal() == .OK else { return }
        let home = AppRuntime.homeURL.resolvingSymlinksInPath().path
        for url in panel.urls {
            let path = url.resolvingSymlinksInPath().path
            if path == home || path.hasPrefix(home + "/") { continue }
            if !settings.extraRoots.contains(path) {
                settings.extraRoots.append(path)
            }
        }
        reloadLists()
    }

    @objc private func removeExtraFolder() {
        let row = extraTable.selectedRow
        guard row >= 0, row < extraList.count else { return }
        let path = extraList[row]
        settings.extraRoots.removeAll { $0 == path }
        reloadLists()
    }

    @objc private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = L10n.t(.excludePrompt)
        panel.message = L10n.t(.excludeMessage)
        guard panel.runModal() == .OK else { return }
        let home = AppRuntime.homeURL.path
        for url in panel.urls {
            let path = url.resolvingSymlinksInPath().path
            let relative: String
            if path == home {
                continue
            } else if path.hasPrefix(home + "/") {
                relative = String(path.dropFirst(home.count + 1))
            } else {
                relative = path
            }
            if !settings.extraExcludedRelatives.contains(relative) {
                settings.extraExcludedRelatives.append(relative)
            }
        }
        reloadLists()
    }

    @objc private func removeSelected() {
        let row = excludeTable.selectedRow
        guard row >= 0, row < excludeList.count else { return }
        let item = excludeList[row]
        if IndexSettings.defaultSkipPrefixes.contains(item) {
            if !settings.disabledDefaultPrefixes.contains(item) {
                settings.disabledDefaultPrefixes.append(item)
            }
        } else if IndexSettings.defaultSkipNames.contains(item) {
            if !settings.disabledDefaultNames.contains(item) {
                settings.disabledDefaultNames.append(item)
            }
        } else {
            settings.extraExcludedRelatives.removeAll { $0 == item }
        }
        reloadLists()
    }

    @objc private func restoreDefaults() {
        let extras = settings.extraRoots
        settings = .default
        settings.extraRoots = extras
        skipHiddenCheckbox.state = .on
        preferOpenedCheckbox.state = .on
        reloadLists()
    }

    @objc private func saveAndClose() {
        let wantLogin = launchAtLoginCheckbox.state == .on
        if wantLogin != LaunchAtLogin.isEnabled {
            do {
                try LaunchAtLogin.setEnabled(wantLogin)
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
        onHotKey?(hotKey)
        onSave?(settings)
        window?.close()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === extraTable ? extraList.count : excludeList.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let isExtra = tableView === extraTable
        let id = NSUserInterfaceItemIdentifier(isExtra ? "extra-cell" : "exclude-cell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? {
            let created = NSTableCellView()
            created.identifier = id
            let text = NSTextField(labelWithString: "")
            text.translatesAutoresizingMaskIntoConstraints = false
            text.lineBreakMode = .byTruncatingMiddle
            created.addSubview(text)
            created.textField = text
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: created.leadingAnchor, constant: 4),
                text.trailingAnchor.constraint(equalTo: created.trailingAnchor, constant: -4),
                text.centerYAnchor.constraint(equalTo: created.centerYAnchor),
            ])
            return created
        }()
        if isExtra {
            cell.textField?.stringValue = extraList[row]
        } else {
            cell.textField?.stringValue = L10n.excludeLabel(excludeList[row])
        }
        return cell
    }
}
