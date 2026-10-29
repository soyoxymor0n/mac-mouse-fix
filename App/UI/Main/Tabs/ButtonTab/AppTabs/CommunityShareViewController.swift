//
// --------------------------------------------------------------------------
// CommunityShareViewController.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//

import AppKit

extension SharedSetupStore {
    /// The app's list of shared setups, in its Application Support folder
    static let shared = SharedSetupStore(url: Locator.mfApplicationSupportFolderURL().appendingPathComponent(SharedSetupStore.fileName))
    /// Posted on the main thread when a setup was added to or removed from the list
    static let didChangeNotification = Notification.Name("CommunitySharedSetupsDidChange")
}

/// The sheet of "Share this tab…". It shows the exact JSON that would be sent, says that it is public and under CC0,
///     and how to delete it. "Share" sends it, "Cancel" sends nothing. After sending, it shows the record ID,
///     and the delete token is kept in `SharedSetupStore` (never shown, never logged).
final class CommunityShareViewController: NSViewController {

    private let app: String
    private let tabRows: [[String: Any]]
    private let uploader: CommunityUploader
    private let store: SharedSetupStore

    private var submission: CommunitySubmission?
    private var sending = false

    private let titlePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let jsonView = NSTextView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let cancelButton = NSButton(title: "", target: nil, action: nil)
    private let shareButton = NSButton(title: "", target: nil, action: nil)
    private let spinner = NSProgressIndicator()

    private static let width: CGFloat = 560

    init(app: String, tabRows: [[String: Any]], uploader: CommunityUploader = CommunityUploader(), store: SharedSetupStore = .shared) {
        self.app = app
        self.tabRows = tabRows
        self.uploader = uploader
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("CommunityShareViewController is only created in code")
    }

    override func loadView() {
        let width = CommunityShareViewController.width

        let titleLabel = NSTextField(labelWithString: String(format: MFLocalizedString("community-share.sheet.title", comment: ""), AppTabs.name(for: app)))
        titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        /// Title from the fixed list, as in the repository
        for title in CommunitySubmission.titles {
            titlePopup.addItem(withTitle: MFLocalizedString(CommunitySetupValidator.titleKeys[title] ?? "", comment: ""))
            titlePopup.lastItem?.representedObject = title
        }
        titlePopup.selectItem(at: CommunitySubmission.titles.count - 1) /// "Other"
        titlePopup.target = self
        titlePopup.action = #selector(titleChanged(_:))
        let titleRow = NSStackView(views: [NSTextField(labelWithString: MFLocalizedString("community-share.sheet.topic", comment: "")), titlePopup])
        titleRow.orientation = .horizontal
        titleRow.spacing = 8

        let previewLabel = label(MFLocalizedString("community-share.sheet.preview", comment: ""), secondary: true)

        /// The exact bytes that are sent
        jsonView.isEditable = false
        jsonView.isSelectable = true
        jsonView.isRichText = false
        jsonView.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        jsonView.textContainerInset = NSSize(width: 4, height: 4)
        jsonView.isVerticallyResizable = true
        jsonView.autoresizingMask = [.width]
        jsonView.setAccessibilityIdentifier("axCommunityShareJSON")
        let scroll = NSScrollView()
        scroll.documentView = jsonView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 200).isActive = true

        let publicLabel = label(MFLocalizedString("community-share.sheet.public", comment: ""), secondary: false)
        let licenseLabel = label(MFLocalizedString("community-share.sheet.license", comment: ""), secondary: false)
        licenseLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let deleteLabel = label(MFLocalizedString("community-share.sheet.how-to-delete", comment: ""), secondary: true)

        statusLabel.preferredMaxLayoutWidth = width - 40
        statusLabel.isHidden = true

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        cancelButton.title = MFLocalizedString("community-share.sheet.cancel", comment: "")
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped(_:))

        shareButton.title = MFLocalizedString("community-share.sheet.share", comment: "")
        shareButton.bezelStyle = .rounded
        shareButton.keyEquivalent = "\r"
        shareButton.target = self
        shareButton.action = #selector(shareTapped(_:))

        let buttonRow = NSStackView(views: [spinner, NSView(), cancelButton, shareButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 10

        let root = NSStackView(views: [titleLabel, titleRow, previewLabel, scroll, publicLabel, licenseLabel, deleteLabel, statusLabel, buttonRow])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 16, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false
        root.widthAnchor.constraint(equalToConstant: width).isActive = true
        scroll.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40).isActive = true
        buttonRow.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40).isActive = true
        view = root

        rebuild()
    }

    private func label(_ text: String, secondary: Bool) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.preferredMaxLayoutWidth = CommunityShareViewController.width - 40
        if secondary {
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
        }
        return label
    }

    //
    // MARK: State
    //

    private var selectedTitle: String {
        return titlePopup.selectedItem?.representedObject as? String ?? "Other"
    }

    /// Builds the submission for the chosen title and shows it. Share is only enabled if it can be sent.
    private func rebuild() {
        switch CommunitySubmission.build(bundleID: app, title: selectedTitle, tabRows: tabRows) {
        case .success(let built):
            submission = built
            jsonView.string = built.json
            switch uploader.availability {
            case .available: showStatus(nil)
            case .notConfigured: showStatus(MFLocalizedString("community-share.unavailable.no-server", comment: ""), isError: false)
            case .switchOff: showStatus(MFLocalizedString("community-share.unavailable.switch-off", comment: ""), isError: false)
            }
        case .failure(let problem):
            submission = nil
            jsonView.string = ""
            showStatus(CommunityShareViewController.message(for: problem), isError: true)
        }
        shareButton.isEnabled = submission != nil && uploader.availability == .available && !sending
    }

    private func showStatus(_ text: String?, isError: Bool = false) {
        statusLabel.stringValue = text ?? ""
        statusLabel.textColor = isError ? .systemRed : .labelColor
        statusLabel.isHidden = text == nil
    }

    static func message(for problem: CommunitySubmission.Problem) -> String {
        switch problem {
        case .invalidBundleID: return MFLocalizedString("community-share.problem.bundle-id", comment: "")
        case .sensitiveApp: return MFLocalizedString("community-share.problem.sensitive", comment: "")
        case .invalidTitle: return MFLocalizedString("community-share.problem.title", comment: "")
        case .noRows: return MFLocalizedString("community-share.problem.no-rows", comment: "")
        case .tooManyRows(let count): return String(format: MFLocalizedString("community-share.problem.too-many-rows", comment: ""), count, CommunitySetupValidator.maxRows)
        case .invalidRows(let count): return String(format: MFLocalizedString("community-share.problem.invalid-rows", comment: ""), count)
        case .tooLarge: return MFLocalizedString("community-share.problem.too-large", comment: "")
        }
    }

    static func message(for failure: CommunityUploader.Failure) -> String {
        switch failure {
        case .switchOff: return MFLocalizedString("community-share.unavailable.switch-off", comment: "")
        case .notConfigured: return MFLocalizedString("community-share.unavailable.no-server", comment: "")
        case .network: return MFLocalizedString("community-share.error.network", comment: "")
        case .rejected: return MFLocalizedString("community-share.error.rejected", comment: "")
        case .notFound, .server, .badResponse: return MFLocalizedString("community-share.error.server", comment: "")
        }
    }

    //
    // MARK: Actions
    //

    @objc private func titleChanged(_ sender: NSPopUpButton) {
        rebuild()
    }

    @objc private func cancelTapped(_ sender: NSButton) {
        close()
    }

    @objc private func shareTapped(_ sender: NSButton) {
        guard let submission, !sending else { return }
        sending = true
        shareButton.isEnabled = false
        /// No cancelling once sent: the answer holds the delete token, which must be saved
        cancelButton.isEnabled = false
        titlePopup.isEnabled = false
        spinner.startAnimation(nil)
        showStatus(MFLocalizedString("community-share.sending", comment: ""))

        /// Holds the controller until the answer is handled, so the delete token is always saved
        uploader.submit(submission) { result in
            DispatchQueue.main.async { self.finishSending(submission, result) }
        }
    }

    private func finishSending(_ submission: CommunitySubmission, _ result: Result<CommunityUploader.Receipt, CommunityUploader.Failure>) {
        sending = false
        spinner.stopAnimation(nil)
        cancelButton.isEnabled = true
        switch result {
        case .success(let receipt):
            let record = SharedSetupRecord(id: receipt.id, bundleID: submission.bundleID, title: submission.title, sharedAt: Date(), deleteToken: receipt.deleteToken)
            var text = String(format: MFLocalizedString("community-share.done", comment: ""), receipt.id)
            do {
                try store.add(record)
            } catch {
                text += "\n" + MFLocalizedString("community-share.done.token-not-saved", comment: "")
            }
            NotificationCenter.default.post(name: SharedSetupStore.didChangeNotification, object: nil)
            showStatus(text)
            statusLabel.isSelectable = true /// So the ID can be copied
            shareButton.isHidden = true
            cancelButton.title = MFLocalizedString("community-share.sheet.done", comment: "")
            cancelButton.keyEquivalent = "\r"
        case .failure(let failure):
            titlePopup.isEnabled = true
            showStatus(CommunityShareViewController.message(for: failure), isError: true)
            shareButton.isEnabled = uploader.availability == .available
        }
    }

    private func close() {
        if let window = view.window, let sheetParent = window.sheetParent {
            sheetParent.endSheet(window)
        }
    }
}
