//
// --------------------------------------------------------------------------
// AppPresetReviewController.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//

import AppKit

/// Sheet that lists the suggested assignments of an app's preset before anything is written.
/// The user can untick a row, change its button, or pick another action for it. Nothing is written until "Add Selected" is clicked.
/// In comparison mode (opened with the tab's rows, from "Recommended setup…"), each row is compared with the tab's rows:
///     new rows are ticked, rows the tab already has can't be ticked, and rows that would replace another action are unticked and show that action.
final class AppPresetReviewController: NSViewController {

    /// Called after the sheet has closed. `rows` are the remap rows to write for the app, empty if the user skipped.
    /// `dontSuggestAgain` is true if the user ticked the checkbox.
    var onFinish: (([[String: Any]], Bool) -> Void)?
    /// Comparison mode only. Called after the sheet has closed instead of `onFinish`. `added` are rows for triggers the tab doesn't use yet,
    ///     `replacing` are rows that take the place of the tab's row with the same trigger and modifiers. Both are empty if the user skipped.
    var onFinishComparison: ((_ added: [[String: Any]], _ replacing: [[String: Any]], _ dontSuggestAgain: Bool) -> Void)?

    private let app: String
    private let preset: AppPreset
    /// Used to warn about buttons that already have a row for all apps
    private let globalRows: [[String: Any]]
    /// The rows of the app's tab in comparison mode. nil when the sheet was opened from the banner.
    private let tabRows: [[String: Any]]?

    /// One entry per suggestion, in the same order
    private var checkboxes: [NSButton] = []
    private var buttonPopups: [NSPopUpButton] = []
    private var actionPopups: [NSPopUpButton] = []
    /// Comparison mode only: how each row compares to the tab's rows, and the note that says so
    private var matches: [AppPresetMatch] = []
    private var matchLabels: [NSTextField] = []

    private let warningLabel = NSTextField(wrappingLabelWithString: "")
    private let noteLabel = NSTextField(wrappingLabelWithString: "")
    private let dontSuggestCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let addButton = NSButton(title: "", target: nil, action: nil)

    init(app: String, preset: AppPreset, globalRows: [[String: Any]], tabRows: [[String: Any]]? = nil) {
        self.app = app
        self.preset = preset
        self.globalRows = globalRows
        self.tabRows = tabRows
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("AppPresetReviewController is only created in code")
    }

    override func loadView() {

        let appName = AppTabs.name(for: app)

        let titleLabel = NSTextField(labelWithString: String(format: MFLocalizedString("app-presets.review.title", comment: ""), appName))
        titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        let introLabel = NSTextField(wrappingLabelWithString: MFLocalizedString("app-presets.review.intro", comment: ""))
        introLabel.textColor = .secondaryLabelColor

        /// Grid with a header row and one row per suggestion
        ///     In comparison mode, a fourth column says what the tab already has for the row
        let comparing = tabRows != nil
        let grid = NSGridView(numberOfColumns: comparing ? 4 : 3, rows: 0)
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        var header = [NSGridCell.emptyContentView, headerLabel(MFLocalizedString("app-presets.review.column.button", comment: "")), headerLabel(MFLocalizedString("app-presets.review.column.action", comment: ""))]
        if comparing { header.append(NSGridCell.emptyContentView) }
        grid.addRow(with: header)

        for suggestion in preset.suggestions {
            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(stateChanged(_:)))
            checkbox.state = .on
            let buttonPopup = makeButtonPopup(selected: suggestion.button)
            let actionPopup = makeActionPopup(for: suggestion)
            /// Only the action column may grow with the sheet. A column with a low-hugging cell grows, which left a gap after the checkboxes.
            checkbox.setContentHuggingPriority(.required, for: .horizontal)
            buttonPopup.setContentHuggingPriority(.required, for: .horizontal)
            checkboxes.append(checkbox)
            buttonPopups.append(buttonPopup)
            actionPopups.append(actionPopup)
            var cells: [NSView] = [checkbox, buttonPopup, actionPopup]
            if comparing {
                let matchLabel = NSTextField(labelWithString: "")
                matchLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
                matchLabel.textColor = .secondaryLabelColor
                matchLabel.lineBreakMode = .byTruncatingTail
                matchLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                matchLabels.append(matchLabel)
                cells.append(matchLabel)
            }
            grid.addRow(with: cells)
        }

        /// The checkbox column is as wide as a checkbox. The grid is as wide as the sheet, and it would otherwise give that column the extra width, leaving a gap after the checkboxes.
        grid.column(at: 0).width = 20

        /// Notes
        warningLabel.textColor = .systemRed
        noteLabel.textColor = .secondaryLabelColor

        /// Bottom row
        dontSuggestCheckbox.title = String(format: MFLocalizedString("app-presets.review.dont-suggest", comment: ""), appName)
        /// The checkbox only hides the banner. If the user already chose it, there's nothing left to choose.
        dontSuggestCheckbox.isHidden = comparing && AppPreset.isDismissed(app)

        let skipButton = NSButton(title: MFLocalizedString("app-presets.review.skip", comment: ""), target: self, action: #selector(skipTapped(_:)))
        skipButton.bezelStyle = .rounded
        skipButton.keyEquivalent = "\u{1b}"

        addButton.title = MFLocalizedString("app-presets.review.add", comment: "")
        addButton.bezelStyle = .rounded
        addButton.keyEquivalent = "\r"
        addButton.target = self
        addButton.action = #selector(addTapped(_:))

        let buttonRow = NSStackView(views: [dontSuggestCheckbox, NSView(), skipButton, addButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 10

        /// Stack everything
        let root = NSStackView(views: [titleLabel, introLabel, grid, noteLabel, warningLabel, buttonRow])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 16, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false
        root.widthAnchor.constraint(equalToConstant: comparing ? 780 : 580).isActive = true
        buttonRow.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40).isActive = true
        /// The action popups would otherwise be as wide as their longest library entry and push the grid past the sheet's edges
        grid.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40).isActive = true
        /// If the sheet is taller than its content, the grid would take the extra height, and it would appear as a gap below the header row
        grid.setContentHuggingPriority(.required, for: .vertical)

        view = root
        preferredContentSize = root.fittingSize

        updateMatches(initial: true)
        updateWarnings()
    }

    //
    // MARK: Building the controls
    //

    private func headerLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeButtonPopup(selected button: Int) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        for number in AppPreset.selectableButtons {
            popup.addItem(withTitle: UIStrings.getButtonString(MFMouseButtonNumber(UInt32(number)), context: kMFButtonStringUsageContextActionTableGroupRow))
            popup.lastItem?.tag = number
        }
        popup.selectItem(withTag: button)
        popup.target = self
        popup.action = #selector(stateChanged(_:))
        popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        return popup
    }

    /// The preset's own action comes first. Then come the other actions the shortcut library knows for this app.
    ///     If the library has the preset's action, its name is used, because the button table shows that name once the row is added.
    private func makeActionPopup(for suggestion: AppPresetSuggestion) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)

        var presetTitle = "\(MFLocalizedString(suggestion.titleKey, comment: ""))  \(suggestion.symbols)"
        var otherEntries: [(title: String, effect: [String: Any])] = []
        for entry in ShortcutLibrary.effectsMenuEntries(forBundleID: app) {
            guard let entry = entry as? [String: Any],
                  let ui = entry["ui"] as? String,
                  let effect = entry["dict"] as? [String: Any] else { continue }
            let title = "\(ui)  \(entry["tool"] as? String ?? "")"
            if (effect as NSDictionary).isEqual(suggestion.effect as NSDictionary) {
                presetTitle = title
                continue
            }
            otherEntries.append((title: title, effect: effect))
        }

        popup.addItem(withTitle: presetTitle)
        popup.lastItem?.representedObject = suggestion.effect
        for entry in otherEntries {
            popup.addItem(withTitle: entry.title)
            popup.lastItem?.representedObject = entry.effect
        }

        popup.target = self
        popup.action = #selector(stateChanged(_:))
        popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        popup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        (popup.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingTail
        return popup
    }

    //
    // MARK: State
    //

    /// The checked rows, with the button and effect the user picked for each, and how they compare to the tab's rows (always `.new` outside comparison mode)
    private func checkedSelections() -> [(button: Int, effect: [String: Any], title: String, match: AppPresetMatch)] {
        var result: [(button: Int, effect: [String: Any], title: String, match: AppPresetMatch)] = []
        for index in checkboxes.indices where checkboxes[index].state == .on && checkboxes[index].isEnabled {
            guard let selection = selection(at: index) else { continue }
            result.append((button: selection.button, effect: selection.effect, title: actionPopups[index].titleOfSelectedItem ?? "", match: index < matches.count ? matches[index] : .new))
        }
        return result
    }

    /// The button and effect currently picked in a row, checked or not
    private func selection(at index: Int) -> (button: Int, effect: [String: Any])? {
        guard let button = buttonPopups[index].selectedItem?.tag,
              let effect = actionPopups[index].selectedItem?.representedObject as? [String: Any] else { return nil }
        return (button: button, effect: effect)
    }

    /// Comparison mode: compares each row, as currently picked, with the tab's rows.
    ///     When a row's kind changes (and when the sheet opens), its checkbox is reset: new rows are ticked, rows that replace an action are not, and rows the tab already has can't be ticked.
    private func updateMatches(initial: Bool) {
        guard let tabRows else { return }
        for index in checkboxes.indices {
            guard let selection = selection(at: index) else { continue }
            let match = AppPreset.classify(AppPreset.remapRow(button: selection.button, effect: selection.effect, app: app), against: tabRows, app: app)
            let oldMatch: AppPresetMatch? = index < matches.count ? matches[index] : nil
            if index < matches.count { matches[index] = match } else { matches.append(match) }

            let label = matchLabels[index]
            switch match {
            case .new:
                label.stringValue = ""
            case .same:
                label.stringValue = MFLocalizedString("app-presets.review.already-set", comment: "")
            case .conflict(let rowIndex):
                label.stringValue = String(format: MFLocalizedString("app-presets.review.currently", comment: ""), AppPresetReviewController.actionName(of: tabRows[rowIndex]))
            }
            label.toolTip = label.stringValue.isEmpty ? nil : label.stringValue

            let kindChanged = initial || !AppPresetReviewController.sameKind(oldMatch, match)
            if kindChanged {
                checkboxes[index].isEnabled = match != .same
                checkboxes[index].state = match == .new ? .on : .off
            }
        }
    }

    private static func sameKind(_ a: AppPresetMatch?, _ b: AppPresetMatch) -> Bool {
        switch (a, b) {
        case (.new?, .new), (.same?, .same), (.conflict?, .conflict): return true
        default: return false
        }
    }

    /// The name of a row's action, as the button table shows it
    static func actionName(of row: [String: Any]) -> String {
        guard let effect = row["effect"] as? NSDictionary else { return "" }
        func find(_ entries: [Any]) -> String? {
            for case let entry as [String: Any] in entries {
                if let dict = entry["dict"] as? NSDictionary, dict.isEqual(effect) {
                    if let ui = entry["ui"] as? String { return ui }
                    if let ui = entry["uiAttributed"] as? NSAttributedString { return ui.stringWithAttachmentDescriptions() }
                }
                if let submenu = entry["submenu"] as? [Any], let name = find(submenu) { return name }
            }
            return nil
        }
        return find(RemapTableTranslator.getEffectsTable(forRemapsTableEntry: row)) ?? (effect["type"] as? String ?? "")
    }

    /// True if a button already has a row for all apps. Such a row has no modifiers.
    private func isSetForAllApps(_ button: Int) -> Bool {
        return globalRows.contains { row in
            let trigger = row["trigger"] as? [String: Any]
            let modifiers = row["modifiers"] as? [String: Any] ?? [:]
            return (trigger?["button"] as? Int) == button && modifiers.isEmpty
        }
    }

    @objc private func stateChanged(_ sender: Any?) {
        /// Ticking a checkbox doesn't change what a row compares to. Changing a popup can.
        if sender is NSPopUpButton { updateMatches(initial: false) }
        updateWarnings()
    }

    private func updateWarnings() {

        let selections = checkedSelections()
        let buttons = selections.map { $0.button }

        /// Two checked rows on the same button can't both be written
        let duplicates = Set(buttons.filter { button in buttons.filter { $0 == button }.count > 1 })
        warningLabel.stringValue = MFLocalizedString("app-presets.review.duplicate", comment: "")
        warningLabel.isHidden = duplicates.isEmpty

        /// Buttons that also have a row for all apps. The rows here take precedence in this app.
        let overlapping = Array(Set(buttons.filter { isSetForAllApps($0) })).sorted()
        let names = overlapping.map { UIStrings.getButtonString(MFMouseButtonNumber(UInt32($0)), context: kMFButtonStringUsageContextActionTableGroupRow) }
        noteLabel.stringValue = String(format: MFLocalizedString("app-presets.review.global-overlap", comment: ""), names.joined(separator: ", "), AppTabs.name(for: app))
        noteLabel.isHidden = overlapping.isEmpty

        addButton.isEnabled = !selections.isEmpty && duplicates.isEmpty
    }

    //
    // MARK: Actions
    //

    @objc private func addTapped(_ sender: NSButton) {
        let selections = checkedSelections()
        let added = selections.filter { $0.match == .new }.map { AppPreset.remapRow(button: $0.button, effect: $0.effect, app: app) }
        let conflicting = selections.filter { if case .conflict = $0.match { return true } else { return false } }

        /// Nothing to replace: just add, as from the banner
        guard tabRows != nil, !conflicting.isEmpty else {
            finish(added: added, replacing: [])
            return
        }

        /// Some ticked rows would replace an action the tab already has. Ask first.
        let replacing = conflicting.map { AppPreset.remapRow(button: $0.button, effect: $0.effect, app: app) }
        confirmOverride(conflicting.map { (button: $0.button, title: $0.title, match: $0.match) }) { [weak self] response in
            switch response {
            case .alertFirstButtonReturn: self?.finish(added: added, replacing: replacing)
            case .alertSecondButtonReturn: self?.finish(added: added, replacing: [])
            default: break /// Cancel: back to the sheet, nothing changes
            }
        }
    }

    /// Asks whether to replace the tab's rows that the ticked rows conflict with. The alert says which rows those are.
    private func confirmOverride(_ conflicts: [(button: Int, title: String, match: AppPresetMatch)], completion: @escaping (NSApplication.ModalResponse) -> Void) {
        guard let tabRows, let window = view.window else { return }

        /// One line per setting that would be replaced: "• Button 4: ⌘S → Toggle mute ⌘⇧M"
        let lines: [String] = conflicts.compactMap { conflict in
            guard case .conflict(let rowIndex) = conflict.match else { return nil }
            let row = tabRows[rowIndex]
            let button = (row["trigger"] as? [String: Any])?["button"] as? Int ?? 0
            let buttonName = UIStrings.getButtonString(MFMouseButtonNumber(UInt32(button)), context: kMFButtonStringUsageContextActionTableGroupRow)
            return "•  \(buttonName): \(AppPresetReviewController.actionName(of: row)) → \(conflict.title)"
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(format: MFLocalizedString("app-presets.review.title", comment: ""), AppTabs.name(for: app))
        alert.informativeText = String(format: MFLocalizedString("app-presets.override.message", comment: ""), lines.joined(separator: "\n"))
        _ = alert.addButton(withTitle: MFLocalizedString("app-presets.override.button", comment: ""))
        _ = alert.addButton(withTitle: MFLocalizedString("app-presets.only-add.button", comment: ""))
        let cancelButton = alert.addButton(withTitle: MFLocalizedString("app-presets.cancel.button", comment: ""))
        cancelButton.keyEquivalent = IBUtility.keyChar(forLiteral: "escape")!

        alert.beginSheetModal(for: window, completionHandler: completion)
    }

    @objc private func skipTapped(_ sender: NSButton) {
        finish(added: [], replacing: [])
    }

    private func finish(added: [[String: Any]], replacing: [[String: Any]]) {
        if let window = view.window, let sheetParent = window.sheetParent {
            sheetParent.endSheet(window)
        }
        let dontSuggestAgain = dontSuggestCheckbox.state == .on
        if tabRows != nil {
            onFinishComparison?(added, replacing, dontSuggestAgain)
        } else {
            onFinish?(added, dontSuggestAgain)
        }
    }
}
