//
// --------------------------------------------------------------------------
// ForkMenu.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Licensed under the MMF License (https://github.com/noah-nuebling/mac-mouse-fix/blob/master/License)
// --------------------------------------------------------------------------
//

import AppKit

/// Hides app menu items that don't apply to the fork.
///     - "Check for Updates…": the fork has no update feed. Sparkle would fall back to an `SUFeedURL` left in the user defaults by older builds, which is the upstream feed.
///     - "Activate License…" and "Buy Mac Mouse Fix…" in `FORCE_LICENSED` builds, which are licensed regardless of the key.
@objc class ForkMenu: NSObject {

    @objc static func tidyAppMenu() {

        /// Old builds stored the upstream feed here. Without it Sparkle has no feed to check.
        UserDefaults.standard.removeObject(forKey: "SUFeedURL")

        guard let appMenu = NSApp.mainMenu?.items.first?.submenu else { return }

        var hiddenActions: [Selector] = [NSSelectorFromString("checkForUpdates:")]
        #if FORCE_LICENSED
        hiddenActions += [NSSelectorFromString("activateLicense:"), NSSelectorFromString("buyMMF:")]
        #endif

        for item in appMenu.items where item.action.map(hiddenActions.contains) == true {
            item.isHidden = true
        }

        /// Hide separators that now have nothing between them
        var previousVisibleIsSeparator = true
        for item in appMenu.items where !item.isHidden || item.isSeparatorItem {
            if item.isSeparatorItem {
                item.isHidden = previousVisibleIsSeparator
                if !item.isHidden { previousVisibleIsSeparator = true }
            } else {
                previousVisibleIsSeparator = false
            }
        }
    }
}
