//
// --------------------------------------------------------------------------
// ButtonTabController.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Created by Noah Nuebling in 2022
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//

import Foundation

@objc class ButtonTabController: NSViewController, NSPopoverDelegate {
    
    //
    // MARK: - Outlets
    //
    
    /// AddField
    
    @IBOutlet weak var addField: AddField!
    
    /// TableView
    
    @IBOutlet var tableController: RemapTableController!
    
    @IBOutlet weak var scrollView: MFScrollView!
    @IBOutlet weak var clipView: NSClipView!
    @IBOutlet weak var tableView: RemapTableView!
    
    /// Buttons
    
    @IBOutlet weak var restoreDefaultButton: NSButton!

    /// App tabs

    private var appTabStrip: AppTabStripView?
    private var appPickerPopover: NSPopover?
    /// The app whose tab is selected. nil is the global tab.
    private(set) var scopeApp: String?
    /// Offers a built-in preset in an empty app tab
    private var presetBanner: AppPresetBannerView?
    /// The add field's height in an empty tab, and in a tab with rows
    private static let fullAddFieldHeight: CGFloat = 150
    private static let compactAddFieldHeight: CGFloat = 64
    private var addFieldHeight: NSLayoutConstraint?
    /// The gesture legend and the instruction text under the add field
    private var gestureLegend: NSView?
    private var instructionLabel: NSView?
    /// "Recommended setup…" next to "Restore Defaults…". Shown in every app tab whose app has a preset.
    private var recommendedSetupButton: NSButton?
    /// "Community setups…" before "Recommended setup…". Shown in every app tab. It loads the setups only when clicked.
    private var communitySetupsButton: NSButton?
    /// "Setups ▾" with both of the above, used instead of the two buttons when both are shown
    private var setupsPullDown: NSPopUpButton?
    private var communitySetupsPopover: NSPopover?
    
    //
    // - MARK: IBActions
    //
    
    @IBAction func restoreDefaults(_ sender: Any) {

        /// In an app tab, "Restore Defaults" deletes the buttons of that app. The tab stays.
        if let app = scopeApp {
            confirmDeleteRows(forApp: app)
            return
        }
        
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = MFLocalizedString("restore-buttons-alert.title", comment: ".")
        alert.informativeText = ""
        
        let restoreButton = alert.addButton(withTitle: MFLocalizedString("restore-buttons-alert.commit", comment: ""))
        let cancelButton = alert.addButton(withTitle: MFLocalizedString("restore-buttons-alert.back", comment: ""))
        restoreButton.keyEquivalent = IBUtility.keyChar(forLiteral: "return")!
        cancelButton.keyEquivalent = IBUtility.keyChar(forLiteral: "escape")!
        
        ///
        /// Get device info
        ///
        
        /// Get info
        let (name, nOfButtons, bestPresetMatch) =  MessagePortUtility.shared.getActiveDeviceInfo() ?? (nil, nil, nil)
        /// Process info
        ///     Note: Use non-breaking-space for nicer layout for long mouse names. (E.g. my VXE mouse connected over BT has the name "RivieraWaves SAS VXE R1SE+")
        ///         Update: Actually like the layout less with nbsp.
//        name = name?.replacingOccurrences(of: " ", with: "&nbsp;") as NSString?
        
        ///
        /// Add accessoryView
        ///
        
        let radio1 = NSButton(radioButtonWithTitle: MFLocalizedString("restore-buttons-alert.radio1", comment: ""), target: self, action: #selector(nullAction(sender:)))
        let radio2 = NSButton(radioButtonWithTitle: MFLocalizedString("restore-buttons-alert.radio2", comment: "If '5+' seems unnatural in your language, translate it as something like '5 or more'. Don't translate '5+' as 'more than 5' (common mistake)"), target: self, action: #selector(nullAction(sender:)))
        radio1.setAccessibilityIdentifier("axRestoreButtons3")
        radio2.setAccessibilityIdentifier("axRestoreButtons5")
        
        let radioStack = NSStackView(views: [radio1, radio2])
        
        var hint: CoolNSTextField? = nil
        if let nOfButtons = nOfButtons {
            
            let hintStringRaw = String(format: MFLocalizedString("restore-buttons-alert.hint", comment: "Note: '%1$@' will be the name of the mouse, such as 'Logitech M720 Triathlon'"), name!, nOfButtons)
            
//            let hintString = MarkdownParser.attributedString(withCoolMarkdown: hintStringRaw)?.settingSecondaryLabelColor(forSubstring: nil).settingFontSize(NSFont.smallSystemFontSize).aligningSubstring(nil, alignment: .center).trimmingWhitespace()
            let hintString = MarkdownParser.attributedString(withCoolMarkdown: hintStringRaw, fillOutBase: true)?.adding(.secondaryLabelColor, for: nil).settingFontSize(NSFont.smallSystemFontSize).adding(.center, for: nil).trimmingWhitespace()
            
            if let hintString = hintString {
                hint = CoolNSTextField(labelWithAttributedString: hintString)
                if hint != nil {
                    radioStack.addView(hint!, in: .center)
                }
            }
        }
        
        radioStack.orientation = .vertical
        radioStack.translatesAutoresizingMaskIntoConstraints = true
        
        radioStack.setCustomSpacing(5.0, after: radio1) /// Default is 8.0 (Ventura)
        radioStack.setCustomSpacing(17.0, after: radio2)
        
        let width = max(200.0, max(radio1.fittingSize.width, radio2.fittingSize.width))
        var height = radio1.frame.height + radioStack.customSpacing(after: radio1) + radio2.frame.height
        if let hint = hint {
            let hintHeight = hint.attributedStringValue.size(atMaxWidth: width).height
            height += radioStack.customSpacing(after: radio2) + hintHeight + 5 /// Not sure why `+ 5` is necessary
        } else {
            height += 4.0
        }
        
        radioStack.setFrameSize(NSSize(width: width, height: height))
        
        alert.accessoryView = radioStack
        
        ///  Select the radioButton that best matches the activeDevice
        if bestPresetMatch == 3 {
            radio1.state = .on
        } else {
            radio2.state = .on
        }
        
        /// Display alert
        
        guard let window = MainAppState.shared.window else { return }
        
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                
                /// Get user selection
                
                let selectedPreset = radio1.state == .on ? 3 : 5
                
                /// Check Change
                
                /// Only the global rows are compared and replaced. The app tabs keep their rows.
                let currentMap = RemapScope.rows(forScope: nil, inRemaps: config("Remaps") as? [Any]) as NSArray
                let defaultMap = config(selectedPreset == 3 ? "Constants.defaultRemaps.threeButtons" : "Constants.defaultRemaps.fiveButtons")
                
                if currentMap != defaultMap {
                    
                    /// Update remaps
                    
                    /// Set config
                    ButtonTabController.replaceRows(forScope: nil, with: (defaultMap as? [Any]) ?? [])
                    
                    /// Reload table
                    mfrun(CFRunLoopGetMain()) {
                        self.tableController.reloadAll()
                    }
                } else { /// currentMap == defaultMap
                    
                    /// Display already using notifications
                    
                    if selectedPreset == 3 {    
                        Toasts.showSimpleToast(name: "k-already-using-defaults-toast.3")
                    } else {
                        
                        Toasts.showSimpleToast(name: "k-already-using-defaults-toast.5")
                    }
                    return
                }
            }
        }
    }
    
    @objc func nullAction(sender: AnyObject) {
        /// Need this to make radioButtons to work together (I think)
    }
    
    //
    // - MARK: Init & lifecycle
    //
    
    
    // MARK: Init
    
    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        
        /// This init is never being called
        assert(false)
        
        /// Set garbage values
        pointerIsInsideAddField = false
        trackingArea = NSTrackingArea()
        
        /// Init super
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        
        /// Do actual init
        nonGarbageInit()
    }
    
    required init?(coder: NSCoder) {
        
        /// Set garbage values
        pointerIsInsideAddField = false
        trackingArea = NSTrackingArea()
        
        /// Init super
        super.init(coder: coder)
        
        /// Real init
        nonGarbageInit()
    }
    
    func nonGarbageInit() {
        
        /// Note: Why are we doing some stuff in init and some in viewDidLoad? I don't understand the logic behind that.
        
        /// Validate: Init is not called twice
        assert(MainAppState.shared.buttonTabController == nil)
        
        /// Store self into global state
        ///     Why is this in `initAddFieldStuff`?
        MainAppState.shared.buttonTabController = self
        
        /// Init state
        pointerIsInsideAddField = false
    }
    
    
    override func loadView() {
        super.loadView()
        installAppTabStrip()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        /// Init remaps when the helper becomes (or already is) enabled
        ///     This doesn't really belong here. It just needs to be executed when the app is first enabled.
        ///     TODO: Move this. E.g. to   `AppDelegate - applicationDidFinishLaunching`
        ///
        EnabledState.shared.producer.startWithValues { enabled in
            if enabled { ButtonTabController.initRemaps() }
        }
        /// Add trackingArea
        createTrackingArea()
        
        /// Init AddField visuals
        addField.coolInit()
        installGestureLegend()

        /// Init app tabs
        refreshAppTabStrip()

        /// Init the preset banner and the "Recommended setup…" button
        installPresetBanner()
        installRecommendedSetupButton()
        updateRestoreDefaultsButtonTitle()
        NotificationCenter.default.addObserver(self, selector: #selector(remapTableDidChange(_:)), name: NSNotification.Name(kMFRemapTableDidChangeNotification as String), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(communitySwitchChanged(_:)), name: CommunityConsent.didChangeNotification, object: nil)
    }
    
    func createTrackingArea() {
        trackingArea = NSTrackingArea(rect: self.addField.bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        self.addField.addTrackingArea(trackingArea)
    }
    
    // MARK: Did appear
    
    override func viewWillAppear() {
        super.viewWillAppear()
        /// The strip may have been built before the app's tabs were loaded. Rebuild it whenever this tab appears.
        refreshAppTabStrip()
        /// Pick the full or the compact add field before the tab switch measures this tab (`TabViewController.resizeWindowToFit`). The rows are loaded in `RemapTableController.viewDidLoad`.
        ///     Doing this only in viewDidAppear changed the layout while the switch had pinned the tab's height, which broke the table's height constraint.
        updatePresetBanner()
    }
    override func viewDidAppear() {
        super.viewDidAppear()

        /// The rows are loaded by now, so the gesture hint can tell whether the current tab is empty
        updatePresetBanner()

        /// This is called every time the tab is switched to
        /// This is called twice, awakeFromNib as well. Use init() or viewDidLoad() to do things once (or use a flag to track the duplicate invocation)
        
        /// Display extra UI
        ///     Doing this with a delay because it doesn't work if the tab switch animation is still ongoing
        assertRunLoop(CFRunLoopGetMain());
        Timer.mf_scheduledTimer(withTimeInterval: 0.3, mode: .common) { timer in

            ///
            /// Get info
            ///
            
            /// Only in the global tab
            ///     The popover is about the default global rows, and "Restore Defaults" in an app tab deletes that app's rows instead.
            guard self.scopeApp == nil else { return }
            
            /// Get device info
            guard let (deviceName, nOfButtons, _) = MessagePortUtility.shared.getActiveDeviceInfo() else { return }
            
            /// Get actionTable info
            let usedButtons = RemapTableUtility.getCapturedButtonsAndExcludeButtonsThatAreOnlyCaptured(byModifier: false)

            ///
            /// Show buyMouseAlert
            ///
            /// Notes:
            /// The idea was to show this under the __conditions__ that
            ///     - 1. The user is using a 3 button mouse
            ///     - 2. The alert hasn't been shown before
            ///     - 3. This isn't the first time opening the buttons tab
            ///     But I don't like it in it's current form so we're not showing it at all for now
            ///
            /// In the future we might __extend/improve__ the alert like this:
            ///     - 1. Make it prettier / more readable by using custom layout and markdown formatting
            ///     - 2. Include links to top 3 recommended mice (and maybe a link to a longer list of recommended mice). Maybe get a brand deal with some good mouse manufacturer for promoting their products.
            ///     - 3. Maybe show a small/unbtrustive toast instead of an alert and have it link to the more complex content / recommendations
            ///
            /// Update Summer 2024:
            /// -  If you implement this don't forget to consider making this escape-dismissable, like most other sheets and alerts in the app.
            /// - Also probably move this into ToastAndSheetTests if you implement this.
            
            let showBuyMouseAlert = false
            
            if (showBuyMouseAlert) {
                
                /// Create alert
                
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = MFLocalizedString("buy-mouse-alert.title", comment: "")
                alert.informativeText = MFLocalizedString("buy-mouse-alert.body", comment: "")
//                alert.showsSuppressionButton = true
                alert.addButton(withTitle: MFLocalizedString("buy-mouse-alert.ok", comment: ""))
                
                /// Display alert
                guard let window = MainAppState.shared.window else { return }
                alert.beginSheetModal(for: window) { _ in
                    
                    /// Show restoreDefault Popover
                    ///     after buyMouseAlert is dismissed
                    self.showRestoreDefaultPopover(deviceName: deviceName as String, nOfButtons: nOfButtons, usedButtons: usedButtons)
                    
                }
            } else {
                
                /// Show restoreDefault Popover
                ///     Immediately if buyMouseAlert is not shown at all
                
                self.showRestoreDefaultPopover(deviceName: deviceName as String, nOfButtons: nOfButtons, usedButtons: usedButtons)
            }
            
        }
        
        ///
        /// Turn off killswitch
        ///
        
        /// We do the exact same thing in the scrollTab
        
        let buttonsAreKilled = config("General.buttonKillSwitch") as! Bool
        let scrollIsKilled = config("General.scrollKillSwitch") as! Bool
        
        if buttonsAreKilled || scrollIsKilled {
            
            /// Turn off killSwitch
            ///     NOTE: We also turn off the scrollKillSwitch because otherwise we can't record click and scroll in addMode.
            setConfig("General.buttonKillSwitch", false as NSObject)
            setConfig("General.scrollKillSwitch", false as NSObject)
            commitConfig()
            
            /// Show user feedback
            Toasts.showReviveToast(showButtons: buttonsAreKilled, showScroll: scrollIsKilled)
        }
    }
    
    //
    // MARK: App tabs
    //

    /// Adds the tab strip on the left of the Buttons tab.
    ///     The storyboard pins the content to the root view's leading edge with one constraint. We shift that constraint right by the strip's width.
    ///     The window measures this tab by the root view, so the tab (and the window) grows by exactly the strip's width.
    private func installAppTabStrip() {

        let root = view
        let stripWidth = AppTabStripView.width

        for constraint in root.constraints {
            let pinnedToRootLeading = (constraint.secondItem as AnyObject?) === root && constraint.firstAttribute == .leading && constraint.secondAttribute == .leading
            if pinnedToRootLeading { constraint.constant += stripWidth }
        }

        let strip = AppTabStripView()
        root.addSubview(strip)
        NSLayoutConstraint.activate([
            strip.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            strip.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            strip.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            strip.widthAnchor.constraint(equalToConstant: stripWidth),
            strip.heightAnchor.constraint(greaterThanOrEqualToConstant: AppTabStripView.minimumHeight),
        ])

        strip.onSelectScope = { [weak self] app in self?.selectScope(app) }
        strip.onAddButtonClicked = { [weak self] button in self?.showAppPicker(relativeTo: button) }
        strip.onRemoveAppTab = { [weak self] app in self?.confirmRemoveAppTab(app) }
        strip.onShareAppTab = { [weak self] app in self?.openShareSheet(app) }
        appTabStrip = strip

        installShortcutLibrarySwitch(above: strip)
    }

    /// The "Show shortcut library" switch, above the app list. Everything below moves down by its height, and the tab grows by that much.
    ///     Stored in UserDefaults (not in the config). Off hides every library entry: the effect menu section, the Apps tab and its suggestions. Rows that were already added stay.
    private func installShortcutLibrarySwitch(above strip: NSView) {

        let root = view
        let switchHeight: CGFloat = 26

        /// Move everything that is pinned to the root's top edge down. The strip's constraint is in this list, too.
        for constraint in root.constraints where constraint.firstAttribute == .top && constraint.secondAttribute == .top {
            if (constraint.secondItem as AnyObject?) === root && (constraint.firstItem as AnyObject?) !== root {
                constraint.constant += switchHeight
            } else if (constraint.firstItem as AnyObject?) === root && (constraint.secondItem as AnyObject?) !== root {
                constraint.constant -= switchHeight
            }
        }

        let checkbox = NSButton(checkboxWithTitle: NSLocalizedString("buttons-tab.show-shortcut-library", value: "Show shortcut library", comment: "Switch in the Buttons tab, above the list of apps. When off, the built-in keyboard shortcuts of apps are hidden in the action menu and in the Apps tab. Rows that were already added stay."), target: self, action: #selector(shortcutLibrarySwitchChanged(_:)))
        checkbox.state = ShortcutLibrary.isEnabled() ? .on : .off
        checkbox.toolTip = NSLocalizedString("buttons-tab.show-shortcut-library.hint", value: "Shows the built-in keyboard shortcuts of apps in the action menu and in the Apps tab. Turning it off doesn't remove rows you already added.", comment: "Tooltip of the 'Show shortcut library' switch in the Buttons tab.")
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(checkbox)
        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            checkbox.bottomAnchor.constraint(equalTo: strip.topAnchor, constant: -6),
        ])
    }

    @objc private func shortcutLibrarySwitchChanged(_ sender: NSButton) {
        ShortcutLibrary.setEnabled(sender.state == .on)
        /// Rebuild the effect menus, so the library section appears or disappears
        tableController.reloadAll()
    }

    /// Adds the preset banner at the top of the add field. It is shown only in an empty app tab that has a preset.
    ///     (The area between the add field and the table is too tight for it.)
    private func installPresetBanner() {
        guard let container = addField.contentView else { return }
        let banner = AppPresetBannerView()
        container.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            banner.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            banner.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            banner.heightAnchor.constraint(equalToConstant: 42),
        ])
        banner.onReview = { [weak self] in self?.reviewPreset(comparingWithTab: false) }
        banner.isHidden = true
        presetBanner = banner
    }
    
    /// Adds the gesture legend between the add field and the hint text under it. Hovering one of its gestures plays it in the add field.
    private func installGestureLegend() {
        guard let stack = addField.superview as? NSStackView,
              let index = stack.arrangedSubviews.firstIndex(of: addField) else { return }

        let legend = GestureLegendView()
        legend.onHoverGesture = { [weak self] kind in self?.addField.playGesture(kind) }
        stack.insertArrangedSubview(legend, at: index + 1)
        gestureLegend = legend
        /// The instruction text under the legend is the next item of the stack
        if index + 2 < stack.arrangedSubviews.count {
            instructionLabel = stack.arrangedSubviews[index + 2]
        }
        /// Replace the storyboard's fixed height. Otherwise it conflicts with the compact height and AppKit breaks one of them at random.
        for constraint in addField.constraints where constraint.firstAttribute == .height && constraint.secondItem == nil && (constraint.firstItem as? NSView) === addField {
            constraint.isActive = false
        }
        let heightConstraint = addField.heightAnchor.constraint(equalToConstant: ButtonTabController.fullAddFieldHeight)
        addFieldHeight = heightConstraint
        NSLayoutConstraint.activate([
            legend.widthAnchor.constraint(equalTo: addField.widthAnchor),
            legend.heightAnchor.constraint(equalToConstant: GestureLegendView.height),
            heightConstraint,
        ])
    }

    /// Empty tabs show the full add field with the animated hint, the legend and the instruction text. A tab with rows gets a short add field,
    /// and the legend and the instruction text are hidden, to keep the table near the top. The '?' explains the gestures in both cases.
    func updateAddFieldLayout() {
        let isEmpty = tableController.dataModel.count == 0
        addFieldHeight?.constant = isEmpty ? ButtonTabController.fullAddFieldHeight : ButtonTabController.compactAddFieldHeight
        gestureLegend?.isHidden = !isEmpty
        instructionLabel?.isHidden = !isEmpty
    }

    /// Adds "Recommended setup…" right before "Restore Defaults…".
    ///     The storyboard's button stack spaces its buttons out evenly (Options on the left, Restore Defaults on the right),
    ///     so the two buttons go into a small stack of their own that takes Restore Defaults' place.
    private func installRecommendedSetupButton() {
        guard let buttonsStack = restoreDefaultButton.superview as? NSStackView else { return }

        let button = NSButton(title: MFLocalizedString("app-presets.recommended.button", comment: ""), target: self, action: #selector(openRecommendedSetup(_:)))
        button.bezelStyle = restoreDefaultButton.bezelStyle
        button.font = restoreDefaultButton.font
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .vertical)
        button.setAccessibilityIdentifier("axButtonsRecommendedSetupButton")

        /// Gravity areas don't stretch the row. (Storyboards can't set this distribution.) Everything goes to the leading edge.
        buttonsStack.distribution = .gravityAreas
        /// WORKAROUND, no proper fix found: with only one visible child, this row made the window's height come out negative
        ///     when the tab was measured for the window size (`TabViewController.resizeWindowToFit()`). Then the window is broken and
        ///     switching tabs fails in `NSView.takeScreenshot()`. It happened since "Options…" was removed from the row, and the row now holds
        ///     only the Recommended setup / Restore pair. Things that did NOT help: hiding the removed button instead, a spacer in the parent stack
        ///     (that one is worse, it stretches during the measurement), and changing the row's distribution in the storyboard.
        ///     This zero-size view is the cheapest way to keep a second child in the row. Remove it when the measurement problem is understood.
        ///     [Oct 2026] Probably understood: the row pins all its views to its top and bottom insets, so its views all get the same height, and nothing gave the row the buttons' height.
        ///         The fixed heights below fix that. Try removing the filler again.
        let filler = NSView()
        filler.translatesAutoresizingMaskIntoConstraints = false
        filler.widthAnchor.constraint(equalToConstant: 0).isActive = true
        /// Its height is set to the buttons' height below. The row pins every view to its top and bottom insets, so a 0 pt filler made the buttons 0 pt tall, too
        ///     (squeezed and pushed below the window's edge, so they couldn't be clicked). With no height at all, the filler stretched the row.
        buttonsStack.addView(filler, in: .trailing)
        buttonsStack.removeArrangedSubview(restoreDefaultButton)
        restoreDefaultButton.removeFromSuperview()
        let communityButton = NSButton(title: MFLocalizedString("community-setups.button", comment: ""), target: self, action: #selector(openCommunitySetups(_:)))
        communityButton.bezelStyle = restoreDefaultButton.bezelStyle
        communityButton.font = restoreDefaultButton.font
        communityButton.setContentHuggingPriority(.required, for: .horizontal)
        communityButton.setContentCompressionResistancePriority(.required, for: .vertical)
        communityButton.setAccessibilityIdentifier("axButtonsCommunitySetupsButton")

        /// "Setups ▾" replaces the two buttons above when both are shown. The three buttons together are wider than the row, and "Remove Buttons…" was cut off.
        let setupsPullDown = NSPopUpButton(frame: .zero, pullsDown: true)
        setupsPullDown.font = restoreDefaultButton.font
        setupsPullDown.setContentHuggingPriority(.required, for: .horizontal)
        setupsPullDown.setContentCompressionResistancePriority(.required, for: .vertical)
        setupsPullDown.setAccessibilityIdentifier("axButtonsSetupsPullDown")
        setupsPullDown.addItem(withTitle: MFLocalizedString("buttons.setups.pulldown", comment: "")) /// The first item of a pull-down is its title
        for (title, action) in [(button.title, #selector(openRecommendedSetup(_:))), (communityButton.title, #selector(openCommunitySetups(_:)))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            setupsPullDown.menu?.addItem(item)
        }
        setupsPullDown.isHidden = true

        let pair = NSStackView(views: [setupsPullDown, communityButton, button, restoreDefaultButton])
        pair.orientation = .horizontal
        pair.alignment = .centerY
        pair.spacing = 8
        pair.detachesHiddenViews = true
        buttonsStack.addView(pair, in: .leading) /// The row is laid out in gravity areas, so the pair sits at the leading edge
        /// The row has to be as tall as the buttons, also when the tab is measured for the window size (`TabViewController.resizeWindowToFit`).
        ///     The pair's height comes from "Restore Defaults", which is always shown. (Constraints to the other buttons would get lost while they're hidden, because the pair detaches hidden views.)
        NSLayoutConstraint.activate([
            pair.heightAnchor.constraint(equalToConstant: restoreDefaultButton.intrinsicContentSize.height),
            filler.heightAnchor.constraint(equalTo: pair.heightAnchor),
        ])
        /// The row takes the extra height when the app strip (min height) makes the tab taller than the add field, table and row. The buttons stay at the bottom (the row aligns to its bottom).
        ///     Before, nothing could grow, and the table's height constraint broke. Above 500, so the row doesn't stretch while the tab is measured inside a huge window (the window's size holds at 500).
        buttonsStack.setHuggingPriority(.init(600), for: .vertical)

        recommendedSetupButton = button
        communitySetupsButton = communityButton
        self.setupsPullDown = setupsPullDown
        updateRecommendedSetupButton()
    }

    /// "Restore Button Defaults…" for all buttons. In an app tab the same button removes that app's buttons.
    func updateRestoreDefaultsButtonTitle() {
        let key = scopeApp == nil ? "buttons.restore-defaults.global.title" : "buttons.restore-defaults.app.title"
        restoreDefaultButton.title = MFLocalizedString(key, comment: "")
    }

    /// Shows "Recommended setup…" in an app tab whose app has a preset, with or without rows, and even if the user chose "Don't suggest this again"
    func updateRecommendedSetupButton() {
        guard let button = recommendedSetupButton else { return }
        let showsRecommended = scopeApp.flatMap { AppPreset.preset(for: $0) } != nil
        /// Hidden while the "Community setups" switch is off: then nothing is downloaded
        let showsCommunity = scopeApp != nil && CommunityConsent.isEnabled()
        /// Both together go into the "Setups" pull-down, so the row fits
        let usesPullDown = showsRecommended && showsCommunity
        setupsPullDown?.isHidden = !usesPullDown
        button.isHidden = !showsRecommended || usesPullDown
        communitySetupsButton?.isHidden = !showsCommunity || usesPullDown
    }

    @objc private func communitySwitchChanged(_ notification: Notification) {
        if !CommunityConsent.isEnabled() { communitySetupsPopover?.close() }
        updateRecommendedSetupButton()
    }

    /// "Share this tab…" from the app strip's menu. The sheet shows the exact data first; nothing is sent until the user clicks Share.
    private func openShareSheet(_ app: String) {
        guard CommunityConsent.isEnabled(), let window = MainAppState.shared.window else { return }
        let rows = RemapScope.rows(forScope: app, inRemaps: config("Remaps") as? [Any]) as? [[String: Any]] ?? []
        let controller = CommunityShareViewController(app: app, tabRows: rows)
        window.beginSheet(NSWindow(contentViewController: controller))
    }

    @objc private func openRecommendedSetup(_ sender: Any) {
        reviewPreset(comparingWithTab: true)
    }

    /// Shows the community setups of the current app in a popover. The setups are loaded now, not before.
    @objc private func openCommunitySetups(_ sender: Any) {
        guard let app = scopeApp, CommunityConsent.isEnabled() else { return }
        /// The popover points at the visible control: the button, or the "Setups" pull-down when the menu item was used
        guard let anchor: NSView = [communitySetupsButton, setupsPullDown].compactMap({ $0 }).first(where: { !$0.isHidden }) else { return }
        communitySetupsPopover?.close()

        let controller = CommunitySetupsViewController(app: app)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        controller.onAdd = { [weak self, weak popover] setup in
            popover?.performClose(nil)
            self?.reviewCommunitySetup(setup)
        }
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        communitySetupsPopover = popover
    }

    /// Opens the preset review sheet for a community setup, compared with the tab's rows. Nothing is written until the user confirms there.
    private func reviewCommunitySetup(_ setup: CommunitySetup) {
        guard let app = scopeApp, app == setup.bundleID, let window = MainAppState.shared.window else { return }

        let preset = setup.asPreset { CommunitySetupsViewController.actionTitle(of: $0) }
        let remaps = config("Remaps") as? [Any]
        let controller = AppPresetReviewController(app: app, preset: preset,
                                                   globalRows: RemapScope.rows(forScope: nil, inRemaps: remaps) as? [[String: Any]] ?? [],
                                                   tabRows: RemapScope.rows(forScope: app, inRemaps: remaps) as? [[String: Any]] ?? [],
                                                   communityTitleKey: setup.titleKey)
        controller.onFinishComparison = { [weak self] added, replacing, _ in
            self?.applyPresetRows(app: app, added: added, replacing: replacing, dontSuggestAgain: false)
        }
        window.beginSheet(NSWindow(contentViewController: controller))
    }

    /// Shows the preset offer for an empty app tab that has a preset, and hides it otherwise
    func updatePresetBanner() {
        var bannerShown = false
        if let banner = presetBanner {
            if let app = scopeApp, let preset = AppPreset.preset(for: app), tableController.dataModel.count == 0, !AppPreset.isDismissed(app) {
                banner.setText(String(format: MFLocalizedString("app-presets.banner", comment: ""), AppTabs.name(for: app), MFLocalizedString(preset.summaryKey, comment: "")))
                bannerShown = true
            }
            banner.isHidden = !bannerShown
        }

        /// The gesture hint teaches how to add a button. It is shown in an empty tab, unless the preset banner takes that place. The '?' button can bring it back.
        addField.setGestureHintVisible(tableController.dataModel.count == 0 && !bannerShown)
        updateAddFieldLayout()
    }
    
    /// Opens the review sheet for the current app's preset. Nothing is written until the user confirms there.
    /// From the banner, confirmed rows are added to the tab's rows, which are empty when the banner is shown. Restore Defaults on the tab undoes this.
    /// With `comparingWithTab` ("Recommended setup…"), the sheet compares the preset with the tab's rows, and the user can also replace the tab's rows that conflict with it.
    ///     Only the rows of this app's tab are ever changed.
    private func reviewPreset(comparingWithTab: Bool) {
        guard let app = scopeApp, let preset = AppPreset.preset(for: app), let window = MainAppState.shared.window else { return }

        let tabRows = comparingWithTab ? (RemapScope.rows(forScope: app, inRemaps: config("Remaps") as? [Any]) as? [[String: Any]] ?? []) : nil
        let controller = AppPresetReviewController(app: app, preset: preset, globalRows: RemapScope.rows(forScope: nil, inRemaps: config("Remaps") as? [Any]) as? [[String: Any]] ?? [], tabRows: tabRows)
        controller.onFinish = { [weak self] rows, dontSuggestAgain in
            self?.applyPresetRows(app: app, added: rows, replacing: [], dontSuggestAgain: dontSuggestAgain)
        }
        controller.onFinishComparison = { [weak self] added, replacing, dontSuggestAgain in
            self?.applyPresetRows(app: app, added: added, replacing: replacing, dontSuggestAgain: dontSuggestAgain)
        }

        let sheet = NSWindow(contentViewController: controller)
        window.beginSheet(sheet)
    }
    
    /// Writes the rows the user confirmed in the review sheet to the app's tab.
    ///     `replacing` rows take the place of the tab's row with the same trigger and modifiers; the tab's other rows stay.
    ///     `added` rows are appended, but never replace a row the tab already has: a row whose trigger and modifiers are already used in this tab is left out.
    private func applyPresetRows(app: String, added: [[String: Any]], replacing: [[String: Any]], dontSuggestAgain: Bool) {
        if dontSuggestAgain { AppPreset.setDismissed(app) }
        if !added.isEmpty || !replacing.isEmpty {
            var rows = RemapScope.rows(forScope: app, inRemaps: config("Remaps") as? [Any]) as? [[String: Any]] ?? []
            for row in replacing {
                if let index = rows.firstIndex(where: { AppPreset.rowsHaveSameTrigger($0, row) }) {
                    rows[index] = row
                } else {
                    rows.append(row)
                }
            }
            for row in added where !rows.contains(where: { AppPreset.rowsHaveSameTrigger($0, row) }) {
                rows.append(row)
            }
            ButtonTabController.replaceRows(forScope: app, with: rows)
            tableController.reloadAll()
        }
        updatePresetBanner()
    }

    @objc private func remapTableDidChange(_ notification: Notification) {
        updatePresetBanner()
        updateRecommendedSetupButton()
    }
    
    /// Rebuilds the tab strip from the stored tab list
    func refreshAppTabStrip() {
        appTabStrip?.setTabs(appBundleIDs: AppTabs.allBundleIDs(), selectedScope: scopeApp)
    }

    /// Shows the rows of one scope in the table. nil shows the global rows.
    func selectScope(_ app: String?) {
        scopeApp = app
        tableController.scopeApp = app
        tableController.reloadAll()
        appTabStrip?.setSelectedScope(app)
        updateRecommendedSetupButton()
        updateRestoreDefaultsButtonTitle()
        /// The rows are loaded now, so the banner and the gesture hint can tell whether the tab is empty
        updatePresetBanner()
    }

    /// Adds a tab for the app, unless it already has one, and shows that tab
    func addAppTab(bundleID: String) {
        var bundleIDs = AppTabs.allBundleIDs()
        if !bundleIDs.contains(bundleID) { bundleIDs.append(bundleID) }
        AppTabs.save(bundleIDs)
        refreshAppTabStrip()
        selectScope(bundleID)
    }

    private func showAppPicker(relativeTo button: NSButton) {

        let picker = AppTabPickerViewController()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = picker

        picker.onPickApp = { [weak self, weak popover] bundleID in
            popover?.performClose(nil)
            self?.addAppTab(bundleID: bundleID)
        }
        picker.onChooseOtherApp = { [weak self, weak popover] in
            popover?.performClose(nil)
            guard let self = self, let window = MainAppState.shared.window else { return }
            AppTabs.chooseApp(in: window) { bundleID in self.addAppTab(bundleID: bundleID) }
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxX)
        appPickerPopover = popover
    }

    /// Removes the app's tab and its rows. Asks first if the tab has any rows.
    private func confirmRemoveAppTab(_ app: String) {

        let nOfRows = RemapScope.rows(forScope: app, inRemaps: config("Remaps") as? [Any]).count
        if nOfRows == 0 {
            removeAppTab(app)
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(format: MFLocalizedString("app-tabs.remove.alert.title", comment: ""), AppTabs.name(for: app))
        alert.informativeText = MFLocalizedString("app-tabs.remove.alert.message", comment: "")
        _ = alert.addButton(withTitle: MFLocalizedString("app-tabs.remove.alert.confirm", comment: ""))
        _ = alert.addButton(withTitle: MFLocalizedString("app-tabs.alert.cancel", comment: ""))

        guard let window = MainAppState.shared.window else { return }
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { self.removeAppTab(app) }
        }
    }

    private func removeAppTab(_ app: String) {
        AppTabs.save(AppTabs.allBundleIDs().filter { $0 != app })
        ButtonTabController.replaceRows(forScope: app, with: [])
        refreshAppTabStrip()
        if scopeApp == app {
            selectScope(nil)
        } else {
            tableController.reloadAll()
        }
    }

    /// "Restore Defaults" in an app tab. Deletes the app's rows. The tab stays, so buttons can be assigned again.
    private func confirmDeleteRows(forApp app: String) {

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(format: MFLocalizedString("app-tabs.restore.alert.title", comment: ""), AppTabs.name(for: app))
        alert.informativeText = MFLocalizedString("app-tabs.restore.alert.message", comment: "")
        _ = alert.addButton(withTitle: MFLocalizedString("app-tabs.restore.alert.confirm", comment: ""))
        _ = alert.addButton(withTitle: MFLocalizedString("app-tabs.alert.cancel", comment: ""))

        guard let window = MainAppState.shared.window else { return }
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                ButtonTabController.replaceRows(forScope: app, with: [])
                self.tableController.reloadAll()
            }
        }
    }

    /// Replaces the rows of one scope in config and writes it. nil is the global scope. The other scopes keep their rows.
    private static func replaceRows(forScope app: String?, with rows: [Any]) {
        let remaps = RemapScope.remapsReplacingScope(app, withRows: rows, inRemaps: config("Remaps") as? [Any])
        setConfig("Remaps", remaps as NSArray)
        commitConfig()
    }

    //
    // MARK: Other
    //
    
    @objc static func initRemaps() {
        
        /// This func doesn't clearly belong into `ButtonTabController`
        ///     Is called when the helper is enabled
        
        let hasBeenInited = config("State.remapsAreInitialized") as! Bool? ?? false
        
        if !hasBeenInited {
            
            setConfig("State.remapsAreInitialized", true as NSObject)
            commitConfig()
            
            let (_, _, bestPresetMatch) = MessagePortUtility.shared.getActiveDeviceInfo() ?? (nil, nil, nil)
            
            /// This is copy-pasted from `restoreDefaults()`
            ///     Only the global rows are compared and replaced. Rows of app tabs are kept.
            
            let currentMap = RemapScope.rows(forScope: nil, inRemaps: config("Remaps") as? [Any]) as NSArray
            let defaultMap = config(bestPresetMatch == 3 ? "Constants.defaultRemaps.threeButtons" : "Constants.defaultRemaps.fiveButtons")
            
            if (currentMap != defaultMap) {
                
                /// Set config
                ButtonTabController.replaceRows(forScope: nil, with: (defaultMap as? [Any]) ?? [])
                
                /// Reload table
                /// Note: It feels a bit hacky to call `updateColumnWidths()` here. Maybe this should be handled automatically inside the remapTable code.
                mfrun(CFRunLoopGetMain()) {
                    MainAppState.shared.remapTableController?.reloadAll()
                    MainAppState.shared.buttonTabController?.tableView.updateColumnWidths()
                }
            }
        }
    }
    
    //
    // MARK: - Restore Default Popover
    //
    
    /// Notes:
    ///  - The reason we're monitoring animations is that for some reason the ScrollTab breaks if we're switching from buttonTab to scrollTab while the restoreDefaltPopover is animating in. So we want to disallow tab switches while it's animating as a quick fix. 
    
    /// Outlets
    
    @IBOutlet var restoreDefaultPopover: NSPopover! /// Why is this one not weak and the other outlets are? Why would an outlet need to be not weak?
    @IBOutlet weak var restoreDefaultPopoverLabel: MarkdownTextField!
    @IBOutlet weak var restoreDefaultPopoverDontRemindAgainCheckbox: NSButton!
    
    /// Properties
    
    var restoreDefaultPopoverIsAnimating = false
    private var popoverMonitor: Any? = nil
    
    /// Delegate methods
    
    func popoverWillShow(_ notification: Notification) {
        restoreDefaultPopoverIsAnimating = true
    }
    func popoverDidShow(_ notification: Notification) {
        restoreDefaultPopoverIsAnimating = false
    }
    func popoverWillClose(_ notification: Notification) {
        restoreDefaultPopoverIsAnimating = true
    }
    func popoverDidClose(_ notification: Notification) {
        restoreDefaultPopoverIsAnimating = false
    }
    
    /// Show popover method
    
    private var restoreDefaultPopover_stringAttributesFromIB: [NSAttributedString.Key : Any]? = nil
    
    func showRestoreDefaultPopover(deviceName: String, nOfButtons: Int, usedButtons: Set<NSNumber>) {
        
        /// This is a helper for `viewDidAppear()`
        
        /// Put info together
        
        var show3Button = false
        var show5Button = false
        
        if usedButtons.isEmpty {
            
            /// All actions are disabled. The user probably did this on purpose. Reminding them that they are using the "wrong" layout is probably annoying, so we don't do it.
            
        } else if nOfButtons <= 2 {
            
            /// The current mouse has less than 2 buttons, it can't be used with Mac Mouse Fix, since button 3 is the lowest usable button currently.
            
        } else if 3 == nOfButtons
                    && !usedButtons.contains(3) {
            
            /// The recommended layout for this mouse is the 3 button layout, focused around button 3, but the current settings don't map anything to button 3. Since button 3 is the lowest usable button currently, this means that the current settings can't be doing anything for the currently active device. So we give the user a hint.
            
            show3Button = true
            
        } else if 4 == nOfButtons {
            
            /// Never seen a mouse with 4 buttons. Idk what the "recommended" settings should be here, so we just ignore this case
            
        } else if 5 <= nOfButtons
                    && !usedButtons.contains(4) && !usedButtons.contains(5) {
            
            /// The recommended layout for this mouse is the 5+ button layout, focused around button 4 and button 5, but the current settings don't map anything to button 4 or 5
            
            show5Button = true
        }
        
        if config("Other.dontRemindToRestoreDefault3") as? Bool ?? false {
            show3Button = false
        }
        if config("Other.dontRemindToRestoreDefault5") as? Bool ?? false {
            show5Button = false
        }
        
        assert(!(show3Button && show5Button))
        
        ///
        /// Show popover
        ///
        
        if show3Button || show5Button {
            
            ///
            /// Init popover UI
            ///
            
            /// Assign delegate
            ///     So we can observe animations
            self.restoreDefaultPopover.delegate = self
            
            /// Store attributes from IB
            if restoreDefaultPopover_stringAttributesFromIB == nil {
                restoreDefaultPopover_stringAttributesFromIB = self.restoreDefaultPopoverLabel.attributedStringValue.attributes(at: 0, effectiveRange: nil)
            }
            
            /// Setup body text
            ///     There used to be different text based on whether your were using a 3 button or a 5 button mouse, but we've simplified that now
            /// I wrote this note: "In English, there needs to be a space at the start of this string otherwise the whole string will be bold. This might be a Ventura Bug"
            ///     -> I think this problem will be resolved by us using `**` instead of `__` for emphasis.
            /// TODO: The 'Don't remind me again' checkbox at the bottom of the popover is loaded directly from the nib file. So it's localizable string is in a totally different place. This might be confusing for localizers.
            /// On hardcoding popover width: We considered hardcoding the popover width instead of giving localizers control via the linebreak, just like we did for tabs (See `applyHardcodedTabWidth()`,
            ///     but decided against because:
            ///         - The popover looks fine even if the text is super wide – perhaps the main purpose of the linebreak is semantic not for controlling width. [Sep 2025]
            ///         - All the localizers except Turkish did put a nice-looking linebreak – and even Turkish looks fine.
            ///         - Chinese and Korean didn't put linebreaks at all and are pretty wide, making them wrap seems awkward.
            ///         - There's no big layout that depends on this, just the little popover which contains this text and a little checkbox below. So localizers don't control stuff they don't see (which was the case before `applyHardcodedTabWidth()`)
            
            let message = String(format: MFLocalizedString("restore-default-buttons-popover.body", comment: "Note: There's a linebreak in English so the popover doesn't become too wide and to aid with readability."), deviceName)
            
            if let attributes = restoreDefaultPopover_stringAttributesFromIB,
               let newString = MarkdownParser.attributedString(withCoolMarkdown: message, fillOutBase: false)?.addingAttributes(asBase: attributes)
           {
                self.restoreDefaultPopoverLabel.attributedStringValue = newString
            }
            
            /// Turn checkbox off
            self.restoreDefaultPopoverDontRemindAgainCheckbox.state = .off
            
            /// Show
            self.restoreDefaultPopover.show(relativeTo: NSRect.zero, of: self.restoreDefaultButton, preferredEdge: .minY)
            
            /// Close on click
            ///     By intercepting events
            self.popoverMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { event in
                    
                var shouldClose: Bool
                var shouldPassThroughEvent: Bool = true
                if event.type == .keyDown {
                    /// Handle keydown
                    shouldClose = (event.keyCode == kVK_Escape)
                    shouldPassThroughEvent = false /// Otherwise there's an NSBeep
                } else {
                    /// Handle clicks
                    /// Check click on window
                    let clickedOnWindow = self.view.hitTest(event.locationInWindow) != nil
                    
                    /// Check click on popover
                    let popupView = self.restoreDefaultPopover.contentViewController?.view
                    let locInScreen = NSEvent.mouseLocation
                    let locInPopupWindow = popupView?.window?.convertPoint(fromScreen: locInScreen)
                    var clickedOnPopover = false
                    if let loc = locInPopupWindow {
                        clickedOnPopover = popupView?.hitTest(loc) != nil
                    }
                    
                    /// Set shouldClose
                    shouldClose = clickedOnWindow && !clickedOnPopover
                }

                /// Close popover
                if shouldClose {
                    
                    /// Store user choice about not being reminded again
                    //  TODO: Now that the UI message doesn't contain info about how many buttons the users mouse has and how that doesn't fit the current settings, it's kind of weird to make the don't remind based on button number. Intuitively it should maybe be based on mouse model? Not sure.
                    
                    let dontRemind = self.restoreDefaultPopoverDontRemindAgainCheckbox.state == .on
                    if dontRemind {
                        if show3Button {
                            setConfig("Other.dontRemindToRestoreDefault3", true as NSObject)
                            commitConfig()
                        } else if show5Button {
                            setConfig("Other.dontRemindToRestoreDefault5", true as NSObject)
                            commitConfig()
                        } else {
                            assert(false)
                        }
                    }
                    
                    /// Close popover
                    self.restoreDefaultPopover.close()
                    
                    /// Remove event monitor
                    if self.popoverMonitor != nil {
                        NSEvent.removeMonitor(self.popoverMonitor!)
                        self.popoverMonitor = nil
                    }
                }
                
                /// Return intercepted event
                return shouldPassThroughEvent ? event : nil
            }
        }
    }
    
    //
    // MARK: - AddView
    //
    
    /// Vars
    
    var pointerIsInsideAddField: Bool
    var trackingArea: NSTrackingArea
    
    /// AddField callbacks
    ///     TODO: Maybe think about race condition for the mouseEntered and mouseExited functions

    override func mouseEntered(with event: NSEvent) {
        mfrun(CFRunLoopGetMain()) {
            
            /// Not sure it makes sense to dispatch async for mouseEntered and mouseExited. We added that dispatch when addField.hoverEffect was controlled by messages we received instead of being based on response to the the messages we sent.
            /// Here are some notes we wrote for the old architecture:
            /// \discussion After addMode refactoring around commit 02c9fcc20d3f03d8b0d2db6e25830276ed937107 I saw a deadlock in the animationCode maybe dispatch to main will prevent it. Edit: Nope still happens. Edit2: Could fix the deadlock by not locking the CATransaction in Animate.swift. So dispatching to main here might be unnecessary.
            
            DDLogInfo("trackingg: mouseEntered")
            
            self.pointerIsInsideAddField = true
            let success = MFMessagePort.sendMessage("enableAddMode", withPayload: nil, waitForReply: true)
            if let success = success as? Bool, success == true {
                self.addField.hoverEffect(enable: true)
            }
        }
    }
    override func mouseExited(with event: NSEvent) {
        mfrun(CFRunLoopGetMain()) {
            self.mouseExited_Internal(dueToAddModeFeeback: false)
        }
    }
    
    func mouseExited_Internal(dueToAddModeFeeback: Bool) {
        
        DDLogInfo("trackingg: mouseExited dueToAddMode: \(dueToAddModeFeeback)")
        
        self.pointerIsInsideAddField = false
        MFMessagePort.sendMessage("disableAddMode", withPayload: nil, waitForReply: false)
        self.addField.hoverEffect(enable: false, playAcceptAnimation: dueToAddModeFeeback)
    }

    @objc func handleAddModeFeedback(payload: NSDictionary) {
        
        mfrun(CFRunLoopGetMain()) {
            
            /// Debug
            DDLogDebug("Received AddMode feedback with payload: \(payload)")
            
            /// Send payoad to tableController
            ///     The payload is an almost finished remapsTable (aka RemapTableController.dataModel) entry with the kMFRemapsKeyEffect key missing
            self.tableController.addRow(withHelperPayload: payload as! [AnyHashable : Any])
            
            /// HACK: Force trackingArea to exit
            /// - We need to do this because `addRow()` opens an `NSMenu`. And when an NSMenu is open, `NSTrackingArea` doesn't work properly, leading to weird behaviour.
            ///     (The weird behaviour is that the mouse needs to enter twice before `mouseEntered()` is called again)
            /// - Not totally sure if the + 0.5 delay is necessary or optimal. But I did some testing and it seems to work really well like this.
            
            self.mouseExited_Internal(dueToAddModeFeeback: true)
            self.addField.removeTrackingArea(self.trackingArea)

            assertRunLoop(CFRunLoopGetMain());
            Timer.mf_scheduledTimer(withTimeInterval: 0.5, mode: .common) { timer in
                self.createTrackingArea()
            }
        }
    }
    
    /// Ignore MB1 & MB2
    ///     TODO: Use format strings and shared functions from UIStrings.m to obtain button names

    override func mouseUp(with event: NSEvent) {
        
        if !pointerIsInsideAddField { return }
        
        Toasts.showSimpleToast(name: "k-forbidden-capture-toast.1")
    }
    override func rightMouseUp(with event: NSEvent) {
        
        if !pointerIsInsideAddField { return }
        
        Toasts.showSimpleToast(name: "k-forbidden-capture-toast.2")
    }
}
