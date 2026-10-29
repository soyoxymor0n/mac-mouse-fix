//
//  GeneralTabController.swift
//  tabTestStoryboards
//
//  Created by Noah Nübling on 23.07.21.
//

import Cocoa
import ReactiveSwift
import ReactiveCocoa
import Sparkle
import ServiceManagement

class GeneralTabController: NSViewController {
    
    /// Convenience
//    var enabled: MutableProperty<Bool> { MainAppState.shared.appIsEnabled }
    
    /// Config
    var showInMenuBar = ConfigValue<Bool>(configPath: "General.showMenuBarItem")
    var lockPointer = ConfigValue<Bool>(configPath: "General.lockPointerDuringDrag")
    var checkForUpdates = ConfigValue<Bool>(configPath: "General.checkForUpdates")
    var getBetaVersions = ConfigValue<Bool>(configPath: "General.checkForPrereleases")
    
    /// Outlets
    
    @IBOutlet var mainView: NSView!
    
    @IBOutlet weak var masterStack: CollapsingStackView!
    
    @IBOutlet weak var enableToggle: NSControl!
    
    @IBOutlet weak var menuBarToggle: NSButton!
    
    @IBOutlet weak var updatesToggle: NSButton!
    @IBOutlet weak var betaToggle: NSButton!
    
    @IBOutlet weak var mainHidableSection: CollapsingStackView!
    @IBOutlet weak var updatesExtraSection: NSView!
    
    
    @IBOutlet weak var enabledHint: NSTextField!
    @IBOutlet weak var updatesHint: NSTextField!
    @IBOutlet weak var menuBarHint: NSTextField!
    
    /// Lock pointer during 'Click and Drag' gestures. Was in the Options sheet of the Buttons tab.
    @IBOutlet weak var lockPointerCheckbox: NSButton!
    @IBOutlet weak var lockPointerHint: NSTextField!
    
    /// Init
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        /// Determine width for this tab
        applyHardcodedTabWidth("general", self, widthControllingTextFields: [enabledHint, updatesHint, menuBarHint, lockPointerHint]);
        
        /// Replace enable checkBox with NSSwitch on newer macOS versions
        var usingSwitch = false
        if #available(macOS 10.15, *) {
            
            usingSwitch = true

            let state = enableToggle.value(forKey: "state")

            let switchView = NSSwitcherino()
            
            let superView = enableToggle.superview as! NSStackView
            superView.replaceSubview(enableToggle, with: switchView)
            NSLayoutConstraint.activate(transferredSuperViewConstraints(fromView: enableToggle, toView: switchView, transferSizeConstraints: false)) /// Currently unnecessary because there are no constraints
            transferHuggingAndCompressionResistance(fromView: enableToggle, toView: switchView)
            
            self.enableToggle = switchView

            self.enableToggle.setValue(state, forKey: "state")
        }
        
        /// Add accessibility identifier for NSSwitch
        ///     Note: We use this from the XCUI tests to take localization screenshots.
        self.enableToggle.setAccessibilityIdentifier("axEnableToggle")
        
        /// 
        /// Sync enabledToggle with Helper enabledState
        ///
        
        let enableTimeout = 7.0
        var enableTimeoutDisposable: Disposable? = nil
        var enableTimeoutTimer: Timer? = nil

        let onToggle = { (doEnable: Bool) in
            
            /// Prevent the enable toggle from toggling when it is clicked
            self.enableToggle.intValue = self.enableToggle.intValue == 0 ? 1 : 0
            
            if doEnable {
                
                let userClickTS = CACurrentMediaTime()
                
                EnabledState.shared.enable(onComplete: { error in
                    
                    if error == nil {
                        
                        if #available(macOS 15.0, *) {
                            
                            /// [Jul 2025] The strange issues with enabling have been fixed by Apple since macOS 15.0 Sequoia. (Source: Enabling Guide: https://redirect.macmousefix.com/?target=mmf-ventura-enabling-guide)
                            ///     Due to this, the instructions on the `enable-timeout-toast` and the `is-strange-helper-alert` are outdated.
                            ///     We didn't get around to disabling those alerts during macOS 15's lifecycle, but now we're finally doing it during the macOS 26 Tahoe Beta.
                            ///
                            ///     Reasons for disabling the alerts:
                            ///         - The alerts' instructions were outdated.
                            ///         - The `enable-timeout-toast` would show still show up in weird situations.
                            ///             - Specifically, the `enable-timeout-toast` would show when enabling the helper for the first time, which sometimes took macOS a while. When macOS eventually did enable the helper, the accessibility sheet would show up, but then the  `enable-timeout-toast` would show up *behind* the accessibility sheet, which is janky.
                            ///     On keeping the alerts:
                            ///         - There are still rare situations where the app won't enable
                            ///             - But simply restarting the app always fixes this in my experience.
                            ///             - (I assume this is some quirk of LaunchServices, not a bug in MMF which we can fix.)
                            ///         - The guide that `enable-timeout-toast` linked to had a comment section (https://redirect.macmousefix.com/?target=mmf-ventura-enabling-guide)
                            ///             - But this had no comments In 2025 so far [Jul 2025]
                            ///         - If we ever wanna re-install `enable-timeout-toast` we need to fix the jank first! I added an `if window.attachedSheet == nil` check below to help but it's still kinda janky [Jul 2025]
                        }
                        else if #available(macOS 13.0, *) {
                        
                            /// Notes:
                            /// - Unfortunately there's a whole class of errors with enabling MMF under macOS 13 Ventura and later using the SMAppService API, where the error that the API returns is nil and there seems to be no direct way of finding out that things failed. None of these issues seem to have been fixed currently under macOS 14.2
                            ///     To help the user in these cases:
                            ///     - In the case that the system launches a 'strange' instance of MMF Helper which comes from another version of Mac Mouse Fix. We use `MessagePortUtility.checkHelperStrangenessReact()` to detect that and provide solution steps to the user.
                            ///     - For cases where the system doesn't seem to launch any instance of MMF Helper at all, we set a timout here and then show a toast that refers users to a help page.
                            
                            
                            /// Clean up
                            enableTimeoutDisposable?.dispose()
                            enableTimeoutTimer?.invalidate()

                            /// Create a signal that fires when either the app is enabled or a strange helper is detected.
                            let mergedSignal: Signal<Void, Never> = Signal.merge(
                                EnabledState.shared.signal.filter({ $0 == true }).map({ _ in () }),
                                MessagePortUtility.shared.strangeHelperDetected.map({ _ in () })
                            )
                            
                            /// Observe the signal
                            enableTimeoutDisposable = mergedSignal.observeValues({ _ in
                                
                                ///
                                /// Enabling __has not__ timed out
                                ///
                                
                                /// Clean up
                                enableTimeoutDisposable?.dispose()
                                enableTimeoutTimer?.invalidate()
                            })
                            
                            /// Set up a timer that fires `enableTimeout` seconds after the user clicked
                            let timeSinceUserClick = CACurrentMediaTime() - userClickTS
                            let timerFireDate = Date.init(timeIntervalSinceNow: enableTimeout - timeSinceUserClick)
                            assertRunLoop(CFRunLoopGetMain()) /// Need to be main since we're drawing UI from the callback
                            enableTimeoutTimer = Timer.init(fire: timerFireDate, interval: DBL_MAX, repeats: true, block: { timer in
                                ///
                                /// Enabling __has__ timed out
                                ///
                                
                                /// Extend the enable timeout if the CPU is busy.
                                /// Notes:
                                /// -  We added this so the enableTimeout isn't triggered when the computer is starting up. I think what we really wanna be doing here is wait for all the login items to start before starting the enableTimeout. The login items are only started after most of the windows are restored. The CPU usage is an okay way to detect this startup sequence but far from perfect. The CPU usage will continute to be high during startup after the login items have been started. Also CPU can be high in other circumstances. CPU usage will be high in more cases than the ones we want to detect. But I think it's better to show enable-timeout-toast too little than too much since I don't want to confuse/clutter up normal users with it and users that actually can't enable Mac Mouse Fix are gonna find the toast, even if it doesn't show up 100% consistently.
                                /// - It's conceivable that on weaker machines the CPU usage never goes below our thrwshold and therefore the enable-timeout-message is never shown.
                                
                                if let cpuUsage = Utility_App.cpuUsage(includingNice: false) {
                                    
                                    var mightBeStartingUp = false
                                    
                                    for coreUsage in cpuUsage {
                                        if coreUsage.floatValue >= 0.5 {
                                            mightBeStartingUp = true
                                            break
                                        }
                                    }
                                    
                                    if mightBeStartingUp {
                                        enableTimeoutTimer?.fireDate = (enableTimeoutTimer?.fireDate ?? Date.now).addingTimeInterval(enableTimeout)
                                        DDLogDebug("GeneralTabController - might be starting up - extending enable timeout. CPU usage: \(cpuUsage)")
                                        return
                                    }
                                }

                                /// Invalidate timer
                                enableTimeoutTimer?.invalidate()

                                /// Clean up
                                enableTimeoutDisposable?.dispose()
                                
                                /// Show user feedback
                                if let window = MainAppState.shared.window {
                                    if window.attachedSheet == nil { /// [Jul 2025] Prevent the toast from showing up behind the accessibility sheet. This is still kinda jank but since this code only runs on macOS 13 and 14 (as of [Jul 2025]), it's not worth fixing. A better way would be to have the `mergedSignal` listen to anything that indicates the user no longer waiting for the helper being enabled: window resigning key, sheet being attached, tab being switched, helper sending mainApp any message, perhaps more I can't think of rn. Probably using NSNotificationCenter for this would be good.
                                        Toasts.showSimpleToast(name: "k-enable-timeout-toast")
                                    }
                                }
                            })
                            RunLoop.main.add(enableTimeoutTimer!, forMode: .common);

                        }
                        
                    } else { /// error != nil
                        
                        guard let error = error else { DDLogError("GeneralTabController - enabling the helper failed without an error"); return }
                        
                        
                        if #available(macOS 13.0, *), error.domain == "SMAppServiceErrorDomain", error.code == 1 {
                            
                            Toasts.showSimpleToast(name: "k-is-disabled-toast")
                        }
                        else {
                            /// Any other failure, for example an unsigned build that can't register the helper. Tell the user instead of crashing.
                            DDLogError("GeneralTabController - enabling the helper failed: \(error)")
                            Toasts.showSimpleToast(name: "k-enable-failed-toast")
                        }
                    }
                })
                
            } else { /// !doEnabled
                EnabledState.shared.disable()
            }
        }
        
        if usingSwitch, #available(macOS 10.15, *) {
            (enableToggle as? NSSwitcherino)?.reactive.boolValues.skip(first: 1).startWithValues(onToggle)
        } else {
            enableToggle.reactive.boolValues.observeValues(onToggle) /// Why are we using observe here and startWithValues above?
        }
        
        /// Declare signals
        
        /// UI <-> data bindings
        
        showInMenuBar <~ menuBarToggle.reactive.boolValues
        checkForUpdates <~ updatesToggle.reactive.boolValues
        getBetaVersions <~ betaToggle.reactive.boolValues
        
        if usingSwitch, #available(macOS 10.15, *) {
            (enableToggle as? NSSwitcherino)?.reactive.boolValue <~ EnabledState.shared
        } else {
            enableToggle.reactive.boolValue <~ EnabledState.shared
        }
        menuBarToggle.reactive.boolValue <~ showInMenuBar
        lockPointerCheckbox.reactive.boolValue <~ lockPointer
        lockPointer <~ lockPointerCheckbox.reactive.boolValues
        updatesToggle.reactive.boolValue <~ checkForUpdates
        betaToggle.reactive.boolValue <~ getBetaVersions
        
        addCommunitySection()
        addSettingsTransferButtons()

        mainHidableSection.reactive.isCollapsed <~ EnabledState.shared.producer.negate()
        
        /// Alert on betaToggle
        /// Notes:
        ///     - Disabling this now, because it's kind of unnecessary, and I don't know how this alert will interact, when a beta Version is acutally available and Sparkle wants to present a sheet as well. Ideally, we would want to present this sheet **before** we toggle the betaToggle, but right now we're just toggling it back if the user doesn't want to toggle it, so Sparkle still gets the message that it's been enabled.
        ///     - The alertStyle should maybe be .warning or sth instead of .informational.
        ///     - We could also put this info into a toas instead of an alert
        ///
        
//        betaToggle.reactive.boolValues.observeValues { betaGotEnabled in
//
//            if betaGotEnabled {
//
//                /// Create alert
//
//                let alert = NSAlert()
//                alert.alertStyle = .informational
//                alert.messageText = MFLocalizedString("beta-alert.title", comment: "")
//                alert.informativeText = MFLocalizedString("beta-alert.body", comment: "")
//                alert.addButton(withTitle: MFLocalizedString("beta-alert.confirm", comment: ""))
//                alert.addButton(withTitle: MFLocalizedString("beta-alert.back", comment: ""))
//
//                /// Display alert
//                guard let window = MainAppState.shared.window else { return }
//                alert.beginSheetModal(for: window) { response in
//                    if response != .alertFirstButtonReturn {
//                        /// Toggle back off
//                        self.betaToggle.state = .off
//                    }
//                }
//            }
//        }
        
        /// [Fork] No update section. The fork has no update feed, and these toggles used to point Sparkle at the upstream feed and start a check.
        hideUpdatesSection()
        
    }

    /// Hides the divider above "Check for Updates", the checkbox, and the beta section below it
    private func hideUpdatesSection() {
        let arranged = mainHidableSection.subviews.filter { !$0.isHidden }
        func arrangedAncestor(_ view: NSView) -> NSView? {
            var v: NSView? = view
            while let current = v, current.superview !== mainHidableSection { v = current.superview }
            return v
        }
        guard let toggleRow = arrangedAncestor(updatesToggle), let index = arranged.firstIndex(of: toggleRow) else { return }
        var toHide = [toggleRow]
        if let extra = arrangedAncestor(updatesExtraSection) { toHide.append(extra) }
        if index > 0 { toHide.append(arranged[index - 1]) } /// Divider
        for view in toHide { view.isHidden = true }
    }

    /// Scroll settings
    ///     The Scrolling tab was merged into this tab. Its sections go below "Show in Menu Bar" and collapse together with the rest of the settings when the app is disabled.
    private var scrollTab: NSViewController?
    /// Export and Import buttons. Kept at the end of the section, below the scroll settings.
    private var settingsRow: NSStackView?

    @available(macOS 11.0, *)
    func absorbScrollTab(_ scrollTab: ScrollTabController) {

        /// Load both views so their outlets are connected
        _ = self.view
        _ = scrollTab.view

        self.scrollTab = scrollTab

        /// Move the whole scroll stack in as one section
        ///     Moving its arranged subviews one by one doesn't work, because CollapsingStackView wraps them.
        let scrollStack: NSView = scrollTab.masterStack
        scrollStack.removeFromSuperview()
        
        /// Divider between the General settings and the scroll settings, like the dividers between the scroll groups
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        mainHidableSection.addArrangedSubview(divider)
        divider.leadingAnchor.constraint(equalTo: mainHidableSection.leadingAnchor).isActive = true
        divider.trailingAnchor.constraint(equalTo: mainHidableSection.trailingAnchor).isActive = true
        
        mainHidableSection.addArrangedSubview(scrollStack)
        if let community = communitySection {
            for view in community { mainHidableSection.addArrangedSubview(view) } /// Moves the section below the scroll settings
        }
        if let row = settingsRow {
            mainHidableSection.addArrangedSubview(row) /// Moves the row below the scroll settings
        }
        scrollStack.leadingAnchor.constraint(equalTo: mainHidableSection.leadingAnchor).isActive = true
        scrollStack.trailingAnchor.constraint(equalTo: mainHidableSection.trailingAnchor).isActive = true
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if #available(macOS 11.0, *) {
            (scrollTab as? ScrollTabController)?.tabDidAppear()
        }
    }

    /// The "Community setups" switch and the list of shared setups (divider and section). Kept above the Export and Import buttons.
    private var communitySection: [NSView]?

    private func addCommunitySection() {
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        let section = CommunitySettingsView()
        /// Inside the collapsing section, so it hides together with the other settings while the app is disabled
        mainHidableSection.addArrangedSubview(divider)
        mainHidableSection.addArrangedSubview(section)
        for view in [divider, section] {
            view.leadingAnchor.constraint(equalTo: mainHidableSection.leadingAnchor).isActive = true
            view.trailingAnchor.constraint(equalTo: mainHidableSection.trailingAnchor).isActive = true
        }
        communitySection = [divider, section]
    }

    /// Export and Import buttons at the bottom of the tab. Same actions as in the File menu.
    private func addSettingsTransferButtons() {
        let exportButton = NSButton(title: MFLocalizedString("settings-transfer.button.export", comment: ""), target: ConfigTransfer.self, action: #selector(ConfigTransfer.exportSettings(_:)))
        let importButton = NSButton(title: MFLocalizedString("settings-transfer.button.import", comment: ""), target: ConfigTransfer.self, action: #selector(ConfigTransfer.importSettings(_:)))
        for button in [exportButton, importButton] {
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        }
        let row = NSStackView(views: [exportButton, importButton])
        row.orientation = .horizontal
        row.spacing = 8
        /// Without this the stack's default low hugging lets the window size itself to a huge height
        row.translatesAutoresizingMaskIntoConstraints = false
        row.setHuggingPriority(.required, for: .vertical)
        row.setContentHuggingPriority(.required, for: .vertical)
        row.setContentCompressionResistancePriority(.required, for: .vertical)
        /// Inside the collapsing section, so it hides together with the other settings while the app is disabled
        row.edgeInsets = NSEdgeInsets(top: 12, left: 0, bottom: 0, right: 0)
        settingsRow = row
        mainHidableSection.addArrangedSubview(row)
    }
}

// MARK: NSSwitcherino

@available(macOS 10.15, *)
extension Reactive where Base: NSSwitcherino {
    
    var boolValue: BindingTarget<Bool> {
        /// Difference to default implementation
        /// - This animates the state change
        
        return BindingTarget(lifetime: base.reactive.lifetime) { newValue in
            if (base.state == .on) != newValue {
                base.performClick(nil)
            }
        }
    }
    var boolValues: SignalProducer<Bool, Never> {
        /// Difference to default implementation
        /// - Doesn't animate when the user clicks
        return base.signal.producer.prefix(value: base.state == .on)
    }
}
@available(macOS 10.15, *)
@objc fileprivate class NSSwitcherino: NSSwitch {
    
    var signal: Signal<Bool, Never>
    var observer: Signal<Bool, Never>.Observer
    var eventMonitor: Any?
    
    required init() {
        let (o, i) = Signal<Bool, Never>.pipe()
        signal = o
        observer = i
        eventMonitor = nil
        super.init(frame: NSZeroRect)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func mouseDown(with event: NSEvent) {
        self.isHighlighted = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .leftMouseDragged]) { event in
            if event.type == .leftMouseUp {
                self.isHighlighted = false
                if self == self.window?.contentView?.hitTest(event.locationInWindow) {
                    self.state = self.state == .on ? .off : .on
                    self.observer.send(value: (self.state == .on))
                }
                if let monitor = self.eventMonitor {
                    NSEvent.removeMonitor(monitor)
                    self.eventMonitor = nil
                } else { assert(false) }
            } else { /// mouseDragged event
                if self == self.window?.contentView?.hitTest(event.locationInWindow) {
                    self.isHighlighted = true
                } else {
                    self.isHighlighted = false
                }
            }
            return event
        } as AnyObject?
    }
}
