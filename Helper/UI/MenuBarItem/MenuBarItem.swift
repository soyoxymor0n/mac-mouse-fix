//
// --------------------------------------------------------------------------
// MenuBarItem.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Created by Noah Nuebling in 2022
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//

/// This uses non-reactive state management. It's so complicated even for this simple example!

/**
 Also see:
 https://github.com/noah-nuebling/mac-mouse-fix/issues/190
 
 */

import Foundation

@objc class MenuBarItem: NSObject {
    
    // MARK: Vars and outlets
    
    var topLevelObjects: NSArray? = []
    static var instance: MenuBarItem? = nil
    
    var statusItem: NSStatusItem? = nil
    @IBOutlet var menu: NSMenu!
    
    @IBOutlet weak var scrollEnabledItem: NSMenuItem!
    @IBOutlet weak var buttonsEnabledItem: NSMenuItem!
    @IBOutlet weak var smoothScrollingItem: NSMenuItem!

    /// The smoothing that 'Smooth Scrolling' restores when it's turned back on. Only accessed on the IO thread.
    private static var smoothnessBeforeOff: String = "high"
    
    @IBOutlet weak var appCompatItem: NSMenuItem!
    @IBOutlet var appCompatView: NSView!
    
    @IBOutlet weak var appCompatHintItem: NSMenuItem!
    @IBOutlet var appCompatHintView: NSView!
    
    // MARK: Init
    
    @objc static func load_Manual() {
        assertRunLoop(CFRunLoopGetMain())
        instance = MenuBarItem()
        Bundle.main.loadNibNamed(NSNib.Name("MenuBarItem"), owner: instance, topLevelObjects: &(instance!.topLevelObjects))
        instance?.load_Manual()
    }
    
    func load_Manual() {
        
        /// Setup statusbar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.autosaveName = "MMFMenuBarItem" /// Probably unnecessary
        statusItem?.button?.title = ""
        let image = NSImage(named: "CoolMenuBarIcon")
        statusItem?.button?.image = image
        statusItem?.menu = menu
        //statusItem?.isVisible = false /// This makes the item forget its position when restarting the computer

        /// Turn off menuItem autoenabling
        ///     So we can control enabling through SwitchMaster
        statusItem?.menu?.autoenablesItems = false
        
        /// Setup group menu item
        /// `.indentationLevel` doesn't work. Do indentation in IB autolayout instead
        appCompatItem.view = appCompatView
        
        /// Turn off group item
        //menu.removeItem(appCompatItem)

        /// Setup hint menu item
        appCompatHintItem.view = appCompatHintView
        
        /// Turn off hint
        menu.removeItem(appCompatHintItem)

        /// Title of the smooth scrolling item. Set in code so it can be localized.
        smoothScrollingItem.title = MFLocalizedString("menu-bar-smooth-scrolling-item", comment: "Menu bar item. Turns smooth scrolling on or off. Shown under 'Scrolling'.")

        /// Load state
        MenuBarItem.reload()
    }
    
    // MARK: SwitchMaster interface
    
    static func enableButtonsItem(_ enable: Bool) { /// Note: [Mar 2025] 'enabled' doesn't mean the item is checked. It means that it's clickable and not grayed-out.
        assertRunLoop(CFRunLoopGetMain())
        instance?.buttonsEnabledItem.isEnabled = enable

    }
    static func enableScrollItem(_ enable: Bool) {
        assertRunLoop(CFRunLoopGetMain())
        instance?.scrollEnabledItem.isEnabled = enable
    }
    
    static func buttonsItemIsEnabled() -> Bool { /// This is for introspection for debugging SwitchMaster
        assertRunLoop(CFRunLoopGetMain())
        return instance?.buttonsEnabledItem.isEnabled ?? false
    }
    static func scrollItemIsEnabled() -> Bool {
        assertRunLoop(CFRunLoopGetMain())
        return instance?.scrollEnabledItem.isEnabled ?? false
    }
    
    // MARK: Reload
    
    @objc static func reload() {

        assertRunLoop(IOThread.runLoop())

        let shouldShow = config("General.showMenuBarItem") as? Bool ?? false
        mfrun(CFRunLoopGetMain()) {
            instance?.statusItem?.isVisible = shouldShow
        }

        let buttonsKilled = config("General.buttonKillSwitch") as? Bool ?? false
        let scrollKilled = config("General.scrollKillSwitch") as? Bool ?? false
        let smoothIsOn = (config("Scroll.smooth") as? String ?? "off") != "off"

        if shouldShow {

            mfrun(CFRunLoopGetMain()) {
                instance?.buttonsEnabledItem.state = !buttonsKilled ? .on : .off
                instance?.scrollEnabledItem.state = !scrollKilled ? .on : .off
                instance?.smoothScrollingItem.state = smoothIsOn ? .on : .off
            }
            
        }
        else {

            /// Disable all settings from the menuItem, if the menuItem is disabled
            /// Need to do the killed check to prevent infinite loops. (Not sure if true anymore). This would be easier if we just used the reactive ConfigValue instead.
            
            if (buttonsKilled || scrollKilled) {
                setConfig("General.scrollKillSwitch", false as NSObject)
                setConfig("General.buttonKillSwitch", false as NSObject)
                commitConfig()
            }
        }
    }
    
    // MARK: IBActions
    
    @IBAction func openMMF(_ sender: Any) {
        assertRunLoop(CFRunLoopGetMain())
        HelperUtility.openMainApp()
    }
    
    @IBAction func disableScroll(_ sender: NSMenuItem) {
        assertRunLoop(CFRunLoopGetMain())
        // TODO: Fix bug where scrolling freezes after turning smooth scroll back on
        
        /// Toggle
        sender.state = sender.state == .on ? .off : .on
        /// Set to config
        let killed = sender.state != .on
        mfrun(IOThread.runLoop()) {
            setConfig("General.scrollKillSwitch", killed as NSObject)
            commitConfig()
        }
    }
    
    @IBAction func toggleSmoothScrolling(_ sender: NSMenuItem) {
        assertRunLoop(CFRunLoopGetMain())
        /// Toggle
        sender.state = sender.state == .on ? .off : .on
        let turnOn = sender.state == .on
        /// Set to config
        ///     Turning it back on restores the smoothing that was active before, so 'Regular' or 'High' isn't lost.
        mfrun(IOThread.runLoop()) {
            if turnOn {
                setConfig("Scroll.smooth", MenuBarItem.smoothnessBeforeOff as NSString)
            } else {
                let current = config("Scroll.smooth") as? String ?? "off"
                if current != "off" {
                    MenuBarItem.smoothnessBeforeOff = current
                }
                setConfig("Scroll.smooth", "off" as NSString)
            }
            commitConfig()
        }
    }

    @IBAction func disableButtons(_ sender: NSMenuItem) {
        assertRunLoop(CFRunLoopGetMain())
        /// Toggle
        sender.state = sender.state == .on ? .off : .on
        /// Set to config
        let killed = sender.state != .on
        mfrun(IOThread.runLoop()) {
            setConfig("General.buttonKillSwitch", killed as NSObject)
            commitConfig()
        }
    }
    
    @IBAction func checkUpdates(_ sender: Any) {
        
        /// Implement?
    }
    
}
