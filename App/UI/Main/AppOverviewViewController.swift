//
// --------------------------------------------------------------------------
// AppOverviewViewController.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//

import Cocoa

/// Settings tab with an overview of the apps in the shortcut library and their keyboard shortcuts.
///     Left: the apps. The search field on top filters the list while you type.
///     Right: the shortcuts of the selected app, under group headers. A badge shows whether a shortcut was checked against the vendor's documentation.
///     The plus button adds a shortcut to the app's tab, with the button and click type you pick. Double click and the context menu of a shortcut do the same.
///     A shortcut with a suggested mouse button shows "Suggested: Button N" (the reason is the tooltip), and the add menu offers that button first. Nothing is added automatically.
///     The "Show shortcut library" switch in the Buttons tab hides all of this.
///     See GitHub issue #13 in soyoxymor0n/mac-mouse-fix-ng.
class AppOverviewViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSMenuDelegate {

    // MARK: Model

    private struct AppInfo {
        let name: String
        let bundleIDs: [String]
    }

    /// Rows of the shortcut table: group headers and shortcuts.
    private enum DisplayRow {
        case header(String)
        case entry([String: Any])
    }

    private var allApps: [AppInfo] = []
    private var visibleApps: [AppInfo] = []
    private var displayRows: [DisplayRow] = []
    private var shownBundleID: String?

    // MARK: Views

    private let searchField = NSSearchField()
    private let appTable = NSTableView()
    private let actionTable = NSTableView()
    private var actionScrollView: NSScrollView?
    private let appNameLabel = NSTextField(labelWithString: "")
    private let appInfoLabel = NSTextField(labelWithString: "")

    // MARK: Life cycle

    override func loadView() {

        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        self.view = root

        /// Left column: search field and apps

        let leftColumn = NSView()
        leftColumn.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholderString = NSLocalizedString("apps-tab.search.placeholder", value: "Search apps", comment: "Placeholder of the search field in the apps overview. Filters the list of apps while typing.")
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = self
        leftColumn.addSubview(searchField)

        let appScroll = makeScrollView(for: appTable)
        leftColumn.addSubview(appScroll)

        appTable.headerView = nil
        appTable.rowHeight = 22
        appTable.allowsEmptySelection = true
        appTable.allowsMultipleSelection = false
        let appColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        appColumn.resizingMask = .autoresizingMask
        appTable.addTableColumn(appColumn)
        appTable.dataSource = self
        appTable.delegate = self

        /// Divider

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        /// Right column: header and shortcuts of the selected app

        let rightColumn = NSView()
        rightColumn.translatesAutoresizingMaskIntoConstraints = false

        appNameLabel.font = NSFont.boldSystemFont(ofSize: 15)
        appNameLabel.lineBreakMode = .byTruncatingTail
        appNameLabel.translatesAutoresizingMaskIntoConstraints = false
        rightColumn.addSubview(appNameLabel)

        appInfoLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        appInfoLabel.textColor = NSColor.secondaryLabelColor
        appInfoLabel.lineBreakMode = .byTruncatingTail
        appInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        rightColumn.addSubview(appInfoLabel)

        let actionScroll = makeScrollView(for: actionTable)
        actionScrollView = actionScroll
        actionScroll.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(actionClipViewFrameDidChange(_:)), name: NSView.frameDidChangeNotification, object: actionScroll.contentView)
        rightColumn.addSubview(actionScroll)

        actionTable.rowHeight = 22
        actionTable.allowsEmptySelection = true
        actionTable.columnAutoresizingStyle = .noColumnAutoresizing /// The action column width is set in viewDidLayout(), so the columns fill the table
        let statusColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("status"))
        statusColumn.title = ""
        statusColumn.width = 30
        statusColumn.minWidth = 30
        statusColumn.maxWidth = 30
        statusColumn.resizingMask = []
        let actionColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("action"))
        actionColumn.title = NSLocalizedString("apps-tab.column.action", value: "Action", comment: "Column title in the apps overview")
        actionColumn.resizingMask = .autoresizingMask
        actionColumn.minWidth = 160
        let shortcutColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("shortcut"))
        shortcutColumn.title = NSLocalizedString("apps-tab.column.shortcut", value: "Shortcut", comment: "Column title in the apps overview")
        shortcutColumn.width = 96
        shortcutColumn.minWidth = 80
        shortcutColumn.resizingMask = []
        actionTable.addTableColumn(statusColumn)
        actionTable.addTableColumn(actionColumn)
        actionTable.addTableColumn(shortcutColumn)
        actionTable.dataSource = self
        actionTable.delegate = self
        /// Double click and the context menu of a shortcut add it, like the plus button
        actionTable.target = self
        actionTable.doubleAction = #selector(actionTableDoubleClicked(_:))
        let contextMenu = NSMenu()
        contextMenu.delegate = self
        actionTable.menu = contextMenu
        /// Action names wrap to more lines when the column is narrower. Heights are recalculated when the column is resized.
        NotificationCenter.default.addObserver(self, selector: #selector(actionColumnDidResize(_:)), name: NSTableView.columnDidResizeNotification, object: actionTable)

        /// Assemble
        ///     Everything goes into one wrapper view, like the tabs in the storyboard. The tab switch animation (`TabViewController`) fades and centers `view.subviews[0]`, which used to be only the left column and broke its constraints.

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)
        content.addSubview(leftColumn)
        content.addSubview(divider)
        content.addSubview(rightColumn)

        NSLayoutConstraint.activate([
            /// Fixed size, so the window fits this tab
            root.widthAnchor.constraint(equalToConstant: 680),
            root.heightAnchor.constraint(equalToConstant: 470),

            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.topAnchor.constraint(equalTo: root.topAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            leftColumn.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            leftColumn.topAnchor.constraint(equalTo: content.topAnchor),
            leftColumn.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            leftColumn.widthAnchor.constraint(equalToConstant: 220),

            searchField.topAnchor.constraint(equalTo: leftColumn.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: leftColumn.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: leftColumn.trailingAnchor, constant: -12),

            appScroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            appScroll.leadingAnchor.constraint(equalTo: leftColumn.leadingAnchor),
            appScroll.trailingAnchor.constraint(equalTo: leftColumn.trailingAnchor),
            appScroll.bottomAnchor.constraint(equalTo: leftColumn.bottomAnchor),

            divider.leadingAnchor.constraint(equalTo: leftColumn.trailingAnchor),
            divider.topAnchor.constraint(equalTo: content.topAnchor),
            divider.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            rightColumn.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            rightColumn.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            rightColumn.topAnchor.constraint(equalTo: content.topAnchor),
            rightColumn.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            appNameLabel.topAnchor.constraint(equalTo: rightColumn.topAnchor, constant: 16),
            appNameLabel.leadingAnchor.constraint(equalTo: rightColumn.leadingAnchor, constant: 16),
            appNameLabel.trailingAnchor.constraint(equalTo: rightColumn.trailingAnchor, constant: -16),

            appInfoLabel.topAnchor.constraint(equalTo: appNameLabel.bottomAnchor, constant: 2),
            appInfoLabel.leadingAnchor.constraint(equalTo: rightColumn.leadingAnchor, constant: 16),
            appInfoLabel.trailingAnchor.constraint(equalTo: rightColumn.trailingAnchor, constant: -16),

            actionScroll.topAnchor.constraint(equalTo: appInfoLabel.bottomAnchor, constant: 12),
            actionScroll.leadingAnchor.constraint(equalTo: rightColumn.leadingAnchor),
            actionScroll.trailingAnchor.constraint(equalTo: rightColumn.trailingAnchor, constant: -8), /// Keeps the plus buttons off the window's edge
            actionScroll.bottomAnchor.constraint(equalTo: rightColumn.bottomAnchor),
        ])
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        fitActionColumn()
    }

    /// The scroll view's visible area gets its final width after `viewDidLayout()` (the scroll view lays itself out later), so the column is fitted again when it changes.
    ///     Fitting only in `viewDidLayout()` used a stale width, and the table came out wider than its visible area, which hid the plus buttons at its trailing edge.
    @objc private func actionClipViewFrameDidChange(_ notification: Notification) {
        fitActionColumn()
    }

    private func fitActionColumn() {
        /// The action column takes the width that the other columns leave: it grows or shrinks by the difference between the columns' extent and the visible width.
        ///     Measured on the column rectangles, because the cell spacing (17 pt) and the table style's edge padding come on top of the column widths. Adding up column widths left the table 37 pt too wide.
        ///     Not measured on the table's frame: it lags behind a width change, and this runs several times during one layout.
        guard let scrollView = actionScrollView, actionTable.numberOfColumns == 3,
              let actionColumn = actionTable.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("action")) else { return }
        let edgePadding = actionTable.rect(ofColumn: 0).minX /// The same on both sides
        let overflow = actionTable.rect(ofColumn: 2).maxX + edgePadding - scrollView.contentView.bounds.width
        let target = actionColumn.width - overflow
        if abs(overflow) > 0.5, target > actionColumn.minWidth {
            actionColumn.width = target
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        loadApps()
        NotificationCenter.default.addObserver(self, selector: #selector(libraryVisibilityDidChange(_:)), name: .shortcutLibraryVisibilityDidChange, object: nil)
    }

    /// The apps of the library. None while the library is switched off in the Buttons tab.
    private func loadApps() {
        let libraryApps = ShortcutLibrary.isEnabled() ? ((ShortcutLibrary.apps() as? [[String: Any]]) ?? []) : []
        allApps = libraryApps.compactMap { app -> AppInfo? in
            guard let name = app["name"] as? String else { return nil }
            return AppInfo(name: name, bundleIDs: (app["bundleIDs"] as? [String]) ?? [])
        }
        allApps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        applyFilter()
    }

    @objc private func libraryVisibilityDidChange(_ notification: Notification) {
        loadApps()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Filtering

    /// Keeps the selected app if it still matches. Otherwise selects the first match.
    private func applyFilter() {

        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        let previouslySelected = selectedAppName

        if query.isEmpty {
            visibleApps = allApps
        } else {
            visibleApps = allApps.filter { app in
                app.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    || app.bundleIDs.contains { $0.range(of: query, options: .caseInsensitive) != nil }
            }
        }

        appTable.reloadData()

        if let previousName = previouslySelected, let row = visibleApps.firstIndex(where: { $0.name == previousName }) {
            appTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else if !visibleApps.isEmpty {
            appTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        } else {
            showSelectedApp()
        }
    }

    private var selectedAppName: String? {
        let row = appTable.selectedRow
        guard row >= 0 && row < visibleApps.count else { return nil }
        return visibleApps[row].name
    }

    /// Fills the right column with the shortcuts of the selected app, under their group headers
    private func showSelectedApp() {

        let row = appTable.selectedRow

        if row >= 0 && row < visibleApps.count {
            let app = visibleApps[row]
            shownBundleID = app.bundleIDs.first
            let entries = overviewEntries(forBundleID: shownBundleID)
            displayRows = buildDisplayRows(from: entries)
            appNameLabel.stringValue = app.name
            let verifiedCount = entries.filter { AppOverviewViewController.isVerified($0) }.count
            appInfoLabel.stringValue = String.localizedStringWithFormat(
                NSLocalizedString("apps-tab.shortcut-count", value: "%d shortcuts, %d checked against the vendor's documentation.", comment: "Under the app name in the apps overview. First value: number of shortcuts. Second value: number of shortcuts that were checked."),
                entries.count, verifiedCount)
        } else {
            shownBundleID = nil
            displayRows = []
            if ShortcutLibrary.isEnabled() {
                appNameLabel.stringValue = NSLocalizedString("apps-tab.no-match", value: "No apps match your search", comment: "Shown in the apps overview when the search field matches no app.")
                appInfoLabel.stringValue = ""
            } else {
                appNameLabel.stringValue = NSLocalizedString("apps-tab.library-off", value: "The shortcut library is turned off", comment: "Shown in the apps overview when the user turned off 'Show shortcut library' in the Buttons tab.")
                appInfoLabel.stringValue = NSLocalizedString("apps-tab.library-off.hint", value: "Turn on \"Show shortcut library\" in the Buttons tab to see it.", comment: "Shown under 'The shortcut library is turned off' in the apps overview.")
            }
        }

        actionTable.reloadData()
    }

    /// Shortcuts of the app that work on the active keyboard layout
    private func overviewEntries(forBundleID bundleID: String?) -> [[String: Any]] {
        guard let bundleID = bundleID else { return [] }
        return (ShortcutLibrary.overviewEntries(forBundleID: bundleID) as? [[String: Any]]) ?? []
    }

    /// Group headers in a fixed order: the default groups first, then the app's specific groups in the order they first appear
    private func buildDisplayRows(from entries: [[String: Any]]) -> [DisplayRow] {

        var groupOrder = (ShortcutLibrary.defaultShortcutGroups() as? [String]) ?? []
        for entry in entries {
            let group = (entry["group"] as? String) ?? "Other"
            if !groupOrder.contains(group) { groupOrder.append(group) }
        }

        var rows: [DisplayRow] = []
        for group in groupOrder {
            let members = entries.filter { ($0["group"] as? String) == group }
            if members.isEmpty { continue }
            rows.append(.header(group))
            rows.append(contentsOf: members.map { DisplayRow.entry($0) })
        }
        return rows
    }

    // MARK: Search field

    func controlTextDidChange(_ notification: Notification) {
        applyFilter()
    }

    // MARK: Tables

    @objc private func actionColumnDidResize(_ notification: Notification) {
        guard !displayRows.isEmpty else { return }
        actionTable.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<displayRows.count))
    }

    private func makeScrollView(for table: NSTableView) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = table
        return scrollView
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return tableView === appTable ? visibleApps.count : displayRows.count
    }

    /// Group headers can't be selected
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard tableView === actionTable, row < displayRows.count else { return true }
        if case .header = displayRows[row] { return false }
        return true
    }

    /// Row height: headers have a fixed height. Shortcut rows have as many lines as their name needs in the action column.
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard tableView === actionTable, row < displayRows.count else { return tableView.rowHeight }
        switch displayRows[row] {
        case .header:
            return 26
        case .entry(let entry):
            let columnWidth = actionTable.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("action"))?.width ?? 200
            let text = (entry["label"] as? String) ?? ""
            let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let textRect = (text as NSString).boundingRect(
                with: NSSize(width: columnWidth - 8, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font])
            let suggestionHeight: CGFloat = AppOverviewViewController.suggestionText(entry) == nil ? 0 : ceil(NSFont.systemFont(ofSize: NSFont.smallSystemFontSize).boundingRectForFont.height) + 1
            return max(tableView.rowHeight, ceil(textRect.height) + suggestionHeight + 6)
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {

        if tableView === appTable {
            return textCell(in: tableView, identifier: "appCell", text: visibleApps[row].name, wraps: false)
        }

        let columnID = tableColumn?.identifier.rawValue
        switch displayRows[row] {

        case .header(let title):
            if columnID == "action" {
                return textCell(in: tableView, identifier: "groupCell", text: title, wraps: false, bold: true, secondary: true)
            }
            return emptyCell(in: tableView)

        case .entry(let entry):
            switch columnID {
            case "status":
                return statusCell(in: tableView, entry: entry)
            case "shortcut":
                return shortcutCell(in: tableView, row: row, symbols: (entry["symbols"] as? String) ?? "")
            default:
                let label = (entry["label"] as? String) ?? ""
                let cell = textCell(in: tableView, identifier: "actionCell", text: label, wraps: true)
                /// A suggested mouse button goes on a second line. Its reason is the tooltip.
                if let suggestion = AppOverviewViewController.suggestionText(entry) {
                    let text = NSMutableAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize), .foregroundColor: NSColor.labelColor])
                    text.append(NSAttributedString(string: "\n" + suggestion, attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor]))
                    cell.textField?.attributedStringValue = text
                    let reason = (entry["suggestionReason"] as? String) ?? ""
                    cell.textField?.toolTip = reason.isEmpty ? suggestion : "\(suggestion): \(reason)"
                }
                return cell
            }
        }
    }

    /// Whether the library has checked the shortcut against the vendor's documentation
    private static func isVerified(_ entry: [String: Any]) -> Bool {
        return (entry["verified"] as? NSNumber)?.boolValue ?? false
    }

    /// The suggested mouse button of a shortcut, e.g. "Suggested: Button 4". nil if the library suggests none.
    private static func suggestionText(_ entry: [String: Any]) -> String? {
        guard let button = (entry["suggestedButton"] as? NSNumber)?.intValue, button > 0 else { return nil }
        var buttonName = UIStrings.getButtonString(MFMouseButtonNumber(UInt32(button)), context: kMFButtonStringUsageContextActionTableGroupRow)
        buttonName = buttonName.prefix(1).uppercased() + buttonName.dropFirst()
        let format = NSLocalizedString("apps-tab.suggested-button", value: "Suggested: %@", comment: "Suggested mouse button for a shortcut in the apps overview, and the header of its click types in the add menu. The value is a button name, for example 'Button 4'.")
        return String(format: format, buttonName)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView, table === appTable else { return }
        showSelectedApp()
    }

    private func emptyCell(in tableView: NSTableView) -> NSTableCellView {
        if let reused = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("emptyCell"), owner: self) as? NSTableCellView {
            return reused
        }
        let cell = NSTableCellView()
        cell.identifier = NSUserInterfaceItemIdentifier("emptyCell")
        return cell
    }

    private func statusCell(in tableView: NSTableView, entry: [String: Any]) -> NSTableCellView {

        let isVerified = AppOverviewViewController.isVerified(entry)

        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("statusCell"), owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = NSUserInterfaceItemIdentifier("statusCell")
            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.imageScaling = .scaleProportionallyDown
            cell.addSubview(imageView)
            cell.imageView = imageView
            NSLayoutConstraint.activate([
                imageView.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 14),
                imageView.heightAnchor.constraint(equalToConstant: 14),
            ])
        }

        if #available(macOS 11.0, *) {
            cell.imageView?.image = NSImage(systemSymbolName: isVerified ? "checkmark.seal.fill" : "circle", accessibilityDescription: nil)
        } else {
            cell.imageView?.image = NSImage(named: isVerified ? NSImage.statusAvailableName : NSImage.statusNoneName)
        }
        cell.imageView?.contentTintColor = isVerified ? NSColor.systemGreen : NSColor.secondaryLabelColor

        var tooltip = isVerified
            ? NSLocalizedString("apps-tab.status.verified", value: "Checked against the vendor's documentation", comment: "Tooltip of the badge in the apps overview for a shortcut that was checked.")
            : NSLocalizedString("apps-tab.status.unverified", value: "Not checked yet", comment: "Tooltip of the badge in the apps overview for a shortcut that was not checked.")
        /// The source of a checked shortcut. Same text as in the effect menu (see RemapTableTranslator).
        if isVerified, let sourceURL = entry["sourceURL"] as? String {
            let format = NSLocalizedString("shortcut-library.source.tooltip", value: "Checked against the vendor's documentation on %@: %@", comment: "Tooltip of the check badge of a shortcut library entry. First value: the date of the check (YYYY-MM-DD). Second value: the address of the vendor's page.")
            tooltip = String(format: format, (entry["verifiedOn"] as? String) ?? "", sourceURL)
        }
        cell.toolTip = tooltip
        cell.imageView?.toolTip = tooltip
        return cell
    }

    /// Shortcut keys with the plus button at the trailing edge. The button's tag is the row, so the click knows which shortcut it belongs to.
    private func shortcutCell(in tableView: NSTableView, row: Int, symbols: String) -> NSTableCellView {

        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("shortcutCell"), owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = NSUserInterfaceItemIdentifier("shortcutCell")
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            textField.maximumNumberOfLines = 1
            cell.addSubview(textField)
            cell.textField = textField

            let button = NSButton()
            button.translatesAutoresizingMaskIntoConstraints = false
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(addButtonClicked(_:))
            cell.addSubview(button)

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                textField.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -4),
                button.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                button.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                button.widthAnchor.constraint(equalToConstant: 18),
                button.heightAnchor.constraint(equalToConstant: 18),
            ])
        }

        cell.textField?.stringValue = symbols
        cell.textField?.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        cell.textField?.toolTip = symbols
        if let button = cell.subviews.compactMap({ $0 as? NSButton }).first {
            let tooltip = NSLocalizedString("apps-tab.add.tooltip", value: "Add to this app's tab", comment: "Tooltip of the plus button in the apps overview. Adds the shortcut to the tab of the app.")
            button.tag = row
            button.toolTip = tooltip
            if #available(macOS 11.0, *) {
                button.image = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: tooltip)
            } else {
                button.image = NSImage(named: NSImage.addTemplateName)
            }
        }
        return cell
    }

    /// Plus button clicked: shows the button menu for the shortcut
    @objc private func addButtonClicked(_ sender: NSButton) {
        showAddMenu(forRow: sender.tag, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    /// Double click on a shortcut: shows the same menu as the plus button, at the row
    @objc private func actionTableDoubleClicked(_ sender: NSTableView) {
        let row = sender.clickedRow
        guard row >= 0 else { return }
        let rowRect = sender.rect(ofRow: row)
        showAddMenu(forRow: row, at: NSPoint(x: rowRect.midX, y: rowRect.maxY), in: sender)
    }

    /// The button menu for the shortcut in `row`. Nothing is added until the user picks an item.
    private func addMenu(forRow row: Int) -> (menu: NSMenu, entry: [String: Any])? {
        guard row >= 0 && row < displayRows.count, case .entry(let entry) = displayRows[row], let bundleID = shownBundleID else { return nil }
        return (RemapTableTranslator.addMenu(forBundleID: bundleID, entry: entry, target: self, action: #selector(addMenuItemSelected(_:))), entry)
    }

    private func showAddMenu(forRow row: Int, at point: NSPoint, in view: NSView) {
        guard let (menu, entry) = addMenu(forRow: row) else { return }
        /// With a suggested button, its first free click type is preselected
        let preselected = AppOverviewViewController.suggestionText(entry) == nil ? nil : menu.items.first { $0.isEnabled && $0.action != nil && $0.submenu == nil }
        _ = menu.popUp(positioning: preselected, at: point, in: view)
    }

    /// Right click on a shortcut: "Add to this app's tab" with the button menu as its submenu
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let (addMenu, _) = addMenu(forRow: actionTable.clickedRow) else { return }
        let item = NSMenuItem(title: NSLocalizedString("apps-tab.add.tooltip", value: "Add to this app's tab", comment: "Tooltip of the plus button in the apps overview. Adds the shortcut to the tab of the app."), action: nil, keyEquivalent: "")
        item.submenu = addMenu
        menu.addItem(item)
    }

    /// A button and click type were picked for a shortcut: creates the app's tab if needed, shows it, and adds the row
    @objc private func addMenuItemSelected(_ item: NSMenuItem) {

        guard let payload = item.representedObject as? [String: Any],
              let trigger = payload["trigger"] as? [String: Any],
              let bundleID = payload["bundleID"] as? String,
              let entry = payload["entry"] as? [String: Any],
              let effect = entry["dict"] else { return }

        guard let effectDict = effect as? [AnyHashable: Any] else { return }
        /// The same row as recording the key by hand (see ShortcutLibraryTests)
        let row = ShortcutLibrary.row(withTrigger: trigger, effect: effectDict)

        MainAppState.shared.buttonTabController?.addAppTab(bundleID: bundleID)
        (parent as? TabViewController)?.coolSelectTab(identifier: "buttons")
        MainAppState.shared.remapTableController?.addRow(withHelperPayload: row)
    }

    private func textCell(in tableView: NSTableView, identifier: String, text: String, wraps: Bool, bold: Bool = false, secondary: Bool = false) -> NSTableCellView {

        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(identifier), owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = NSUserInterfaceItemIdentifier(identifier)
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            /// Let the label shrink to the column width, so wrapped text stays inside its column
            textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.topAnchor.constraint(equalTo: cell.topAnchor, constant: 3),
                textField.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -3),
            ])
        }

        cell.textField?.stringValue = text
        cell.textField?.toolTip = text
        cell.textField?.font = bold ? NSFont.boldSystemFont(ofSize: NSFont.systemFontSize) : NSFont.systemFont(ofSize: NSFont.systemFontSize)
        cell.textField?.textColor = secondary ? NSColor.secondaryLabelColor : NSColor.labelColor
        cell.textField?.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
        cell.textField?.maximumNumberOfLines = wraps ? 0 : 1
        return cell
    }
}
