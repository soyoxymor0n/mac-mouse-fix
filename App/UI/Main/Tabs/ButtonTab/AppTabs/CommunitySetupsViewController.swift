//
// --------------------------------------------------------------------------
// CommunitySetupsViewController.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//

import AppKit

/// The popover of "Community setups" in an app tab. It loads the setups when it opens, lists the titles for the app,
///     and shows the rows of the chosen setup in plain text. "Add to This Tab…" hands the setup to the same review sheet as the presets.
///     Nothing is written from here.
final class CommunitySetupsViewController: NSViewController {

    /// Called when the user clicks "Add to This Tab…" for a setup
    var onAdd: ((CommunitySetup) -> Void)?

    private let app: String
    private let loader: CommunitySetupsLoader
    private let stack = NSStackView()
    private static let width: CGFloat = 360

    /// The loaded setups and how they were loaded, to come back from a setup's rows to the list
    private var list: CommunitySetupList?
    private var index: CommunityIndex?
    private var refreshFailed = false

    init(app: String, loader: CommunitySetupsLoader = .shared) {
        self.app = app
        self.loader = loader
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("CommunitySetupsViewController is only created in code")
    }

    override func loadView() {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: CommunitySetupsViewController.width).isActive = true
        view = stack
        load()
    }

    //
    // MARK: States
    //

    private func load() {
        showLoading()
        loader.load { [weak self] result in
            guard let self else { return }
            switch result {
            case .loaded(let index, let refreshFailed):
                self.index = index
                self.refreshFailed = refreshFailed
                self.list = index.setups(for: self.app)
                self.showList()
            case .failed:
                self.showError()
            }
        }
    }

    private func showLoading() {
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        let row = NSStackView(views: [spinner, label(MFLocalizedString("community-setups.loading", comment: ""), secondary: true)])
        row.spacing = 8
        setContent([titleLabel(), row])
    }

    private func showError() {
        let retry = NSButton(title: MFLocalizedString("community-setups.retry", comment: ""), target: self, action: #selector(retryTapped(_:)))
        retry.bezelStyle = .rounded
        setContent([titleLabel(), label(MFLocalizedString("community-setups.error", comment: ""), secondary: false), retry])
    }

    private func showList() {
        guard let list else { return }
        var views: [NSView] = [titleLabel()]

        if list.setups.isEmpty {
            views.append(label(String(format: MFLocalizedString("community-setups.empty", comment: ""), AppTabs.name(for: app)), secondary: false))
        } else {
            for (i, setup) in list.setups.enumerated() {
                let button = NSButton(title: "\(MFLocalizedString(setup.titleKey, comment: ""))  ›", target: self, action: #selector(setupTapped(_:)))
                button.bezelStyle = .recessed
                button.tag = i
                views.append(button)
            }
        }
        views.append(contentsOf: notes(rejectedRows: list.rejectedRows, newerFormatFiles: list.newerFormatFiles))
        views.append(footer())
        setContent(views)
    }

    private func showSetup(_ setup: CommunitySetup) {
        var views: [NSView] = []
        let title = NSTextField(labelWithString: MFLocalizedString(setup.titleKey, comment: ""))
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        views.append(title)

        /// One line per row: "Button 4: Close Tab ⌘W"
        let lines = setup.rows.map { row -> String in
            let trigger = row["trigger"] as? [String: Any] ?? [:]
            let name = AppPresetReviewController.triggerName(button: trigger["button"] as? Int ?? 0, duration: trigger["duration"] as? String ?? "click", level: trigger["level"] as? Int ?? 1)
            return "\(name): \(CommunitySetupsViewController.actionTitle(of: row))"
        }
        let rowsLabel = label(lines.joined(separator: "\n"), secondary: false)
        views.append(rowsLabel)

        views.append(contentsOf: notes(rejectedRows: setup.rejectedRows, newerFormatFiles: 0))
        views.append(label(MFLocalizedString("community-setups.review-hint", comment: ""), secondary: true))

        let back = NSButton(title: MFLocalizedString("community-setups.back", comment: ""), target: self, action: #selector(backTapped(_:)))
        back.bezelStyle = .rounded
        let add = NSButton(title: MFLocalizedString("community-setups.add", comment: ""), target: self, action: #selector(addTapped(_:)))
        add.bezelStyle = .rounded
        add.keyEquivalent = "\r"
        add.tag = list?.setups.firstIndex { $0.fileName == setup.fileName } ?? -1
        let buttonRow = NSStackView(views: [back, NSView(), add])
        buttonRow.orientation = .horizontal
        views.append(buttonRow)
        setContent(views)
        buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28).isActive = true
    }

    //
    // MARK: Building blocks
    //

    private func titleLabel() -> NSTextField {
        let title = NSTextField(labelWithString: String(format: MFLocalizedString("community-setups.popover.title", comment: ""), AppTabs.name(for: app)))
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        return title
    }

    private func label(_ text: String, secondary: Bool) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: secondary ? NSFont.smallSystemFontSize : NSFont.systemFontSize)
        if secondary { label.textColor = .secondaryLabelColor }
        label.preferredMaxLayoutWidth = CommunitySetupsViewController.width - 28
        return label
    }

    /// How many rows were left out, and how many setups need a newer version of the app
    private func notes(rejectedRows: Int, newerFormatFiles: Int) -> [NSView] {
        var views: [NSView] = []
        if rejectedRows > 0 {
            views.append(label(String(format: MFLocalizedString("community-setups.rejected-rows", comment: ""), rejectedRows), secondary: true))
        }
        if newerFormatFiles > 0 {
            views.append(label(String(format: MFLocalizedString("community-setups.newer-format", comment: ""), newerFormatFiles), secondary: true))
        }
        return views
    }

    /// Where the setups come from and how old the copy is
    private func footer() -> NSView {
        let date = DateFormatter.localizedString(from: index?.fetchedAt ?? Date(), dateStyle: .medium, timeStyle: .short)
        let key = refreshFailed ? "community-setups.footer.offline" : "community-setups.footer"
        let text = label(String(format: MFLocalizedString(key, comment: ""), date), secondary: true)
        let link = NSButton(title: MFLocalizedString("community-setups.repository-link", comment: ""), target: self, action: #selector(repositoryTapped(_:)))
        link.bezelStyle = .inline
        link.controlSize = .small
        let footer = NSStackView(views: [text, link])
        footer.orientation = .vertical
        footer.alignment = .leading
        footer.spacing = 4
        return footer
    }

    private func setContent(_ views: [NSView]) {
        for view in stack.arrangedSubviews { stack.removeArrangedSubview(view); view.removeFromSuperview() }
        for view in views { stack.addArrangedSubview(view) }
        preferredContentSize = stack.fittingSize
    }

    /// The name of a row's action: the name from the shortcut library if it knows the shortcut, and the shortcut's symbols
    static func actionTitle(of row: [String: Any]) -> String {
        guard let effect = row["effect"] as? [String: Any],
              let keycode = effect["keycode"] as? Int, let flags = effect["flags"] as? Int else { return "" }
        let symbols = UIStrings.getStringForKeyCode(CGKeyCode(keycode), flags: CGEventFlags(rawValue: UInt64(flags)), font: .systemFont(ofSize: NSFont.systemFontSize)).stringWithAttachmentDescriptions()
        let name = AppPresetReviewController.actionName(of: row)
        if name.isEmpty || name == "keyboardShortcut" || name == symbols { return symbols }
        return "\(name)  \(symbols)"
    }

    //
    // MARK: Actions
    //

    @objc private func setupTapped(_ sender: NSButton) {
        guard let list, list.setups.indices.contains(sender.tag) else { return }
        showSetup(list.setups[sender.tag])
    }

    @objc private func backTapped(_ sender: NSButton) {
        showList()
    }

    @objc private func retryTapped(_ sender: NSButton) {
        load()
    }

    @objc private func addTapped(_ sender: NSButton) {
        guard let list, list.setups.indices.contains(sender.tag) else { return }
        onAdd?(list.setups[sender.tag])
    }

    @objc private func repositoryTapped(_ sender: NSButton) {
        NSWorkspace.shared.open(CommunitySource.repositoryWebURL)
    }
}
