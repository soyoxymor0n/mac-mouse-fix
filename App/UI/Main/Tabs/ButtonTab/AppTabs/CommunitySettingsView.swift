//
// --------------------------------------------------------------------------
// CommunitySettingsView.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//

import AppKit

/// The "Community" section of the General tab: the one "Community setups" switch (off by default), and the list of setups
///     this Mac shared, each with a Delete button. Delete asks the server first and only then removes the local record.
final class CommunitySettingsView: NSStackView {

    private let store: SharedSetupStore
    private let uploader: CommunityUploader
    private let toggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let listStack = NSStackView()
    private var wrappingLabels: [NSTextField] = []
    /// IDs whose delete request is running
    private var deleting: Set<String> = []

    init(store: SharedSetupStore = .shared, uploader: CommunityUploader = CommunityUploader()) {
        self.store = store
        self.uploader = uploader
        super.init(frame: .zero)
        setUp()
    }

    required init?(coder: NSCoder) {
        fatalError("CommunitySettingsView is only created in code")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setUp() {
        orientation = .vertical
        alignment = .leading
        spacing = 6
        translatesAutoresizingMaskIntoConstraints = false
        setHuggingPriority(.required, for: .vertical)

        toggle.title = MFLocalizedString("community-settings.switch", comment: "")
        toggle.target = self
        toggle.action = #selector(toggleChanged(_:))
        toggle.state = CommunityConsent.isEnabled() ? .on : .off
        toggle.setAccessibilityIdentifier("axCommunitySetupsToggle")

        let hint = wrappingLabel(MFLocalizedString("community-settings.switch.hint", comment: ""), secondary: true)

        let header = NSTextField(labelWithString: MFLocalizedString("community-settings.shared.header", comment: ""))
        header.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)

        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 4

        for view in [toggle, hint, header, listStack] { addArrangedSubview(view) }
        setCustomSpacing(10, after: hint)
        for view in [hint, listStack] {
            view.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }

        reloadList()
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged(_:)), name: SharedSetupStore.didChangeNotification, object: nil)
    }

    private func wrappingLabel(_ text: String, secondary: Bool) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        if secondary { label.textColor = .secondaryLabelColor }
        label.preferredMaxLayoutWidth = 350
        wrappingLabels.append(label)
        return label
    }

    override func layout() {
        super.layout()
        /// Wrap the labels at the section's real width
        for label in wrappingLabels where bounds.width > 0 && label.preferredMaxLayoutWidth != bounds.width {
            label.preferredMaxLayoutWidth = bounds.width
            label.invalidateIntrinsicContentSize()
        }
    }

    /// One row per shared setup: "Google Chrome: Tab switching" with its date and ID, and a Delete button
    private func reloadList() {
        for view in listStack.arrangedSubviews { listStack.removeArrangedSubview(view); view.removeFromSuperview() }
        wrappingLabels.removeAll { $0.superview == nil }

        let records = store.records().sorted { $0.sharedAt > $1.sharedAt }
        if records.isEmpty {
            let empty = wrappingLabel(MFLocalizedString("community-settings.shared.empty", comment: ""), secondary: true)
            listStack.addArrangedSubview(empty)
            empty.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
            return
        }

        for record in records {
            let titleKey = CommunitySetupValidator.titleKeys[record.title] ?? "community-setups.title.other"
            let name = String(format: MFLocalizedString("community-settings.shared.row", comment: ""), AppTabs.name(for: record.bundleID), MFLocalizedString(titleKey, comment: ""))
            let date = DateFormatter.localizedString(from: record.sharedAt, dateStyle: .medium, timeStyle: .none)
            let detail = String(format: MFLocalizedString("community-settings.shared.detail", comment: ""), date, record.id)

            let nameLabel = NSTextField(labelWithString: name)
            nameLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            nameLabel.lineBreakMode = .byTruncatingTail
            let detailLabel = NSTextField(labelWithString: detail)
            detailLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize - 1)
            detailLabel.textColor = .secondaryLabelColor
            detailLabel.isSelectable = true
            detailLabel.lineBreakMode = .byTruncatingMiddle
            for label in [nameLabel, detailLabel] { label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal) }
            let texts = NSStackView(views: [nameLabel, detailLabel])
            texts.orientation = .vertical
            texts.alignment = .leading
            texts.spacing = 1

            let delete = NSButton(title: MFLocalizedString("community-settings.shared.delete", comment: ""), target: self, action: #selector(deleteTapped(_:)))
            delete.bezelStyle = .rounded
            delete.controlSize = .small
            delete.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            delete.identifier = NSUserInterfaceItemIdentifier(record.id)
            delete.isEnabled = !deleting.contains(record.id)
            delete.setContentHuggingPriority(.required, for: .horizontal)
            delete.setContentCompressionResistancePriority(.required, for: .horizontal)

            let row = NSStackView(views: [texts, NSView(), delete])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            listStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
        }
    }

    //
    // MARK: Actions
    //

    @objc private func toggleChanged(_ sender: NSButton) {
        CommunityConsent.setEnabled(sender.state == .on)
    }

    @objc private func storeChanged(_ notification: Notification) {
        reloadList()
    }

    @objc private func deleteTapped(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, let record = store.records().first(where: { $0.id == id }), !deleting.contains(id) else { return }
        deleting.insert(id)
        sender.isEnabled = false
        uploader.delete(id: record.id, token: record.deleteToken) { [weak self] result in
            DispatchQueue.main.async { self?.finishDeleting(record, result) }
        }
    }

    private func finishDeleting(_ record: SharedSetupRecord, _ result: Result<Void, CommunityUploader.Failure>) {
        deleting.remove(record.id)
        switch result {
        case .success:
            try? store.remove(id: record.id)
            NotificationCenter.default.post(name: SharedSetupStore.didChangeNotification, object: nil)
        case .failure(let failure):
            /// The local record stays, so the user can try again
            reloadList()
            showDeleteFailure(record, failure)
        }
    }

    private func showDeleteFailure(_ record: SharedSetupRecord, _ failure: CommunityUploader.Failure) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = MFLocalizedString("community-settings.delete-failed.title", comment: "")
        let key: String
        switch failure {
        case .notFound: key = "community-settings.delete-failed.not-found"
        case .notConfigured: key = "community-share.unavailable.no-server"
        case .network: key = "community-settings.delete-failed.network"
        default: key = "community-settings.delete-failed.server"
        }
        alert.informativeText = MFLocalizedString(key, comment: "")
        alert.addButton(withTitle: MFLocalizedString("community-settings.delete-failed.ok", comment: ""))
        /// The server doesn't know the record any more. The user may remove it from this Mac without the server.
        if failure == .notFound {
            alert.addButton(withTitle: MFLocalizedString("community-settings.delete-failed.forget", comment: ""))
        }
        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertSecondButtonReturn, let self else { return }
            try? self.store.remove(id: record.id)
            NotificationCenter.default.post(name: SharedSetupStore.didChangeNotification, object: nil)
        }
        if let window = window {
            alert.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }
}
