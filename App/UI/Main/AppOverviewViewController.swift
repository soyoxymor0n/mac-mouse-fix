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
///     Right: the shortcuts of the selected app. A badge shows whether each shortcut was checked against the vendor's documentation.
///     Recommended mouse buttons are not shown yet, because the library has no suggested buttons in this version.
///     See GitHub issue #13 in soyoxymor0n/mac-mouse-fix-ng.
class AppOverviewViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {

    // MARK: Model

    private struct AppInfo {
        let name: String
        let bundleIDs: [String]
        let entries: [[String: Any]]
    }

    /// Date the shortcut library was checked. Every entry in `ShortcutLibrary.m` was checked on this date (see the header of `ShortcutLibrary.h`).
    private static let checkedDate = "2026-10-25"

    private var allApps: [AppInfo] = []
    private var visibleApps: [AppInfo] = []
    private var shownEntries: [[String: Any]] = []

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
        /// Action names wrap to more lines when the column is narrower. Heights are recalculated when the column is resized.
        NotificationCenter.default.addObserver(self, selector: #selector(actionColumnDidResize(_:)), name: NSTableView.columnDidResizeNotification, object: actionTable)

        /// Assemble

        root.addSubview(leftColumn)
        root.addSubview(divider)
        root.addSubview(rightColumn)

        NSLayoutConstraint.activate([
            /// Fixed size, so the window fits this tab
            root.widthAnchor.constraint(equalToConstant: 680),
            root.heightAnchor.constraint(equalToConstant: 470),

            leftColumn.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            leftColumn.topAnchor.constraint(equalTo: root.topAnchor),
            leftColumn.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            leftColumn.widthAnchor.constraint(equalToConstant: 220),

            searchField.topAnchor.constraint(equalTo: leftColumn.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: leftColumn.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: leftColumn.trailingAnchor, constant: -12),

            appScroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            appScroll.leadingAnchor.constraint(equalTo: leftColumn.leadingAnchor),
            appScroll.trailingAnchor.constraint(equalTo: leftColumn.trailingAnchor),
            appScroll.bottomAnchor.constraint(equalTo: leftColumn.bottomAnchor),

            divider.leadingAnchor.constraint(equalTo: leftColumn.trailingAnchor),
            divider.topAnchor.constraint(equalTo: root.topAnchor),
            divider.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            rightColumn.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            rightColumn.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            rightColumn.topAnchor.constraint(equalTo: root.topAnchor),
            rightColumn.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            appNameLabel.topAnchor.constraint(equalTo: rightColumn.topAnchor, constant: 16),
            appNameLabel.leadingAnchor.constraint(equalTo: rightColumn.leadingAnchor, constant: 16),
            appNameLabel.trailingAnchor.constraint(equalTo: rightColumn.trailingAnchor, constant: -16),

            appInfoLabel.topAnchor.constraint(equalTo: appNameLabel.bottomAnchor, constant: 2),
            appInfoLabel.leadingAnchor.constraint(equalTo: rightColumn.leadingAnchor, constant: 16),
            appInfoLabel.trailingAnchor.constraint(equalTo: rightColumn.trailingAnchor, constant: -16),

            actionScroll.topAnchor.constraint(equalTo: appInfoLabel.bottomAnchor, constant: 12),
            actionScroll.leadingAnchor.constraint(equalTo: rightColumn.leadingAnchor),
            actionScroll.trailingAnchor.constraint(equalTo: rightColumn.trailingAnchor),
            actionScroll.bottomAnchor.constraint(equalTo: rightColumn.bottomAnchor),
        ])
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        /// The action column takes the width that the status and shortcut columns leave. Uses their real rectangles, because their rendered width can differ from the requested width.
        guard let scrollView = actionScrollView, actionTable.numberOfColumns == 3 else { return }
        let otherColumnsWidth = actionTable.rect(ofColumn: 0).width + actionTable.rect(ofColumn: 2).width
        let available = scrollView.contentView.bounds.width - otherColumnsWidth
        if let actionColumn = actionTable.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("action")), available > actionColumn.minWidth, abs(actionColumn.width - available) > 0.5 {
            actionColumn.width = available
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        let libraryApps = (ShortcutLibrary.apps() as? [[String: Any]]) ?? []
        allApps = libraryApps.compactMap { app -> AppInfo? in
            guard let name = app["name"] as? String else { return nil }
            return AppInfo(name: name,
                           bundleIDs: (app["bundleIDs"] as? [String]) ?? [],
                           entries: (app["entries"] as? [[String: Any]]) ?? [])
        }
        allApps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        applyFilter()
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

    /// Fills the right column with the shortcuts of the selected app
    private func showSelectedApp() {

        let row = appTable.selectedRow

        if row >= 0 && row < visibleApps.count {
            let app = visibleApps[row]
            shownEntries = app.entries
            appNameLabel.stringValue = app.name
            appInfoLabel.stringValue = String.localizedStringWithFormat(
                NSLocalizedString("apps-tab.shortcut-count", value: "%d shortcuts. Checked %@.", comment: "Under the app name in the apps overview. First value: number of shortcuts. Second value: the date they were checked, as YYYY-MM-DD."),
                app.entries.count, AppOverviewViewController.checkedDate)
        } else {
            shownEntries = []
            appNameLabel.stringValue = NSLocalizedString("apps-tab.no-match", value: "No apps match your search", comment: "Shown in the apps overview when the search field matches no app.")
            appInfoLabel.stringValue = ""
        }

        actionTable.reloadData()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func actionColumnDidResize(_ notification: Notification) {
        guard !shownEntries.isEmpty else { return }
        actionTable.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<shownEntries.count))
    }
    
    /// Row height of an action: as many lines as the label needs in the action column, with a minimum of one line.
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard tableView === actionTable, row < shownEntries.count else { return tableView.rowHeight }
        let columnWidth = actionTable.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("action"))?.width ?? 200
        let text = (shownEntries[row]["label"] as? String) ?? ""
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let textRect = (text as NSString).boundingRect(
            with: NSSize(width: columnWidth - 8, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font])
        return max(tableView.rowHeight, ceil(textRect.height) + 6)
    }
    
    // MARK: Search field

    func controlTextDidChange(_ notification: Notification) {
        applyFilter()
    }

    // MARK: Tables

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
        return tableView === appTable ? visibleApps.count : shownEntries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {

        if tableView === appTable {
            return textCell(in: tableView, identifier: "appCell", text: visibleApps[row].name, wraps: false)
        }

        let entry = shownEntries[row]
        switch tableColumn?.identifier.rawValue {
        case "status":
            return statusCell(in: tableView, isVerified: AppOverviewViewController.isVerified(entry))
        case "shortcut":
            return textCell(in: tableView, identifier: "shortcutCell", text: (entry["symbols"] as? String) ?? "", wraps: false)
        default:
            return textCell(in: tableView, identifier: "actionCell", text: (entry["label"] as? String) ?? "", wraps: true)
        }
    }

    /// Entries are only in the library after they were checked against the vendor's documentation, so an entry without the flag counts as checked.
    private static func isVerified(_ entry: [String: Any]) -> Bool {
        return (entry["verified"] as? Bool) ?? true
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView, table === appTable else { return }
        showSelectedApp()
    }

    private func statusCell(in tableView: NSTableView, isVerified: Bool) -> NSTableCellView {

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

        let tooltip = isVerified
            ? NSLocalizedString("apps-tab.status.verified", value: "Checked against the vendor's documentation", comment: "Tooltip of the badge in the apps overview for a shortcut that was checked.")
            : NSLocalizedString("apps-tab.status.unverified", value: "Not checked yet", comment: "Tooltip of the badge in the apps overview for a shortcut that was not checked.")
        cell.toolTip = tooltip
        cell.imageView?.toolTip = tooltip
        return cell
    }

    /// Wrapped cells show the whole text on several lines. Single-line cells truncate, and their tooltip shows the full text.
    private func textCell(in tableView: NSTableView, identifier: String, text: String, wraps: Bool) -> NSTableCellView {

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
        cell.textField?.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        cell.textField?.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
        cell.textField?.maximumNumberOfLines = wraps ? 0 : 1
        return cell
    }
}
