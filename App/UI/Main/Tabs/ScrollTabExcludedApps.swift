//
// --------------------------------------------------------------------------
// ScrollTabExcludedApps.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//

import Cocoa

/// The "Don't scroll in these apps" section of the scroll settings.
///     The bundle IDs are stored in `Scroll.excludedApps`. While one of these apps is frontmost, the helper passes scroll events through unaltered (See `Scroll.m`).
@available(macOS 11.0, *)
class ScrollTabExcludedApps: NSObject, NSTableViewDataSource, NSTableViewDelegate {

    private static let configKeyPath = "Scroll.excludedApps"

    private var bundleIDs: [String] = []
    private let table = NSTableView()
    private let removeButton = NSButton()

    /// Creates the section and appends it to the end of `stack`
    func install(in stack: NSStackView) {

        bundleIDs = (config(Self.configKeyPath) as? [String]) ?? []

        let divider = NSBox()
        divider.boxType = .separator

        let title = NSTextField(labelWithString: MFLocalizedString("scroll-excluded-apps.title", comment: "Heading of the list of apps in which scrolling is turned off."))

        let hint = NSTextField(wrappingLabelWithString: MFLocalizedString("scroll-excluded-apps.hint", comment: "Explains the list of apps in which scrolling is turned off. Keep it short."))
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .secondaryLabelColor

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("excludedApp"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.headerView = nil
        table.rowHeight = 28
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.dataSource = self
        table.delegate = self

        let scrollView = NSScrollView()
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let addButton = NSButton(image: NSImage(named: NSImage.addTemplateName) ?? NSImage(), target: self, action: #selector(addApp(_:)))
        addButton.bezelStyle = .smallSquare
        addButton.toolTip = MFLocalizedString("scroll-excluded-apps.add.tooltip", comment: "Tooltip of the + button that adds an app to the list of apps in which scrolling is turned off.")

        removeButton.image = NSImage(named: NSImage.removeTemplateName)
        removeButton.target = self
        removeButton.action = #selector(removeSelectedApps(_:))
        removeButton.bezelStyle = .smallSquare
        removeButton.toolTip = MFLocalizedString("scroll-excluded-apps.remove.tooltip", comment: "Tooltip of the - button that removes the selected apps from the list of apps in which scrolling is turned off.")
        removeButton.isEnabled = false

        let buttons = NSStackView(views: [addButton, removeButton])
        buttons.orientation = .horizontal

        let section = NSStackView(views: [divider, title, hint, scrollView, buttons])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 8
        section.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(section)

        /// Stretch the wide views to the width of the section, and the section to the width of the stack
        section.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        for wide in [divider, hint, scrollView] as [NSView] {
            wide.translatesAutoresizingMaskIntoConstraints = false
            wide.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        }
        scrollView.heightAnchor.constraint(equalToConstant: 120).isActive = true
    }

    // MARK: Actions

    @objc private func addApp(_ sender: NSButton) {
        guard let window = table.window else { return }
        AppTabs.chooseApp(in: window) { [weak self] bundleID in
            self?.add(bundleID: bundleID)
        }
    }

    @objc private func removeSelectedApps(_ sender: Any?) {
        let selected = table.selectedRowIndexes
        guard !selected.isEmpty else { return }
        bundleIDs = bundleIDs.enumerated().filter { !selected.contains($0.offset) }.map { $0.element }
        save()
        table.reloadData()
        removeButton.isEnabled = false
    }

    private func add(bundleID: String) {
        /// Bundle IDs are compared case-insensitively, the same way the helper compares them
        if let existing = bundleIDs.firstIndex(where: { $0.caseInsensitiveCompare(bundleID) == .orderedSame }) {
            table.selectRowIndexes(IndexSet(integer: existing), byExtendingSelection: false)
            table.scrollRowToVisible(existing)
            return
        }
        bundleIDs.append(bundleID)
        save()
        table.reloadData()
    }

    private func save() {
        setConfig(Self.configKeyPath, bundleIDs as NSArray)
        commitConfig()
    }

    // MARK: NSTableViewDataSource, NSTableViewDelegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        return bundleIDs.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {

        let bundleID = bundleIDs[row]

        let cell = NSTableCellView()

        let icon = NSImageView(image: AppTabs.icon(for: bundleID))
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: AppTabs.name(for: bundleID))
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail

        cell.addSubview(icon)
        cell.addSubview(label)
        cell.imageView = icon
        cell.textField = label

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        removeButton.isEnabled = !table.selectedRowIndexes.isEmpty
    }
}
