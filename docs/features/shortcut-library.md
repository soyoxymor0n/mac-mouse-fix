# Shortcut library

Status: v1 implemented on `beta` (2026-10-25). Three apps only: Google Chrome, Microsoft Teams and Finder. Firefox, Safari, VS Code, Zoom and Slack are not in v1: their shortcuts could not be checked against the vendor's page in this session, and Slack's bundle ID could not be verified (Slack is not installed here). Not in v1: the Settings switch, the "Browse shortcuts" entry on Global, and the "Usually button 4" hint. Library entries appear at the top of the effect menu of that app's rows. Choosing one writes the same row as recording the key.

## 1. Summary

Ship a curated, bundled list of keyboard shortcuts for about 6 to 12 apps that people often bind to mouse buttons: browsers, Teams, Slack, Zoom, VS Code and Finder. Each entry has a short label, the key code and modifier flags, a source link and a "verified on" date. When a user adds a button in an app tab, the library appears as a second source next to recording a shortcut by hand, so the user does not have to search for it. The library is data that ships with each app release, and it uses the same effect format as the remap table. It depends on the same keyboard-layout question as the presets, and it is more work to maintain, so it should follow the presets.

## 2. Goals and non-goals

Goals:
- Choose apps on evidence: your own usage first, then public usage data.
- Each entry has a label, a shortcut, a source, a `verifiedOn` date and a suggested button.
- One tap fills the effect. The result must match recording the same key by hand.
- Work offline, with no telemetry and no personal data.

Non-goals:
- Covering every shortcut of an app. Only actions that suit mouse buttons are included: back and forward, tab switching, new and reopen tab, mute and video in calls, Mission Control.
- Scraping help pages, or updating entries from the web automatically.
- Destructive shortcuts. Quit, Log Out, Force Quit and Empty Trash are excluded.
- Supporting every keyboard layout in v1.

## 3. Research findings

Which apps are most used on macOS:
- Homebrew cask install analytics, 365 days to 2026-10-25, 25.4 million events. The top 25 includes Visual Studio Code (rank 5, 478,581 events), Google Chrome (rank 7, 433,905), iTerm2 (rank 15, 305,910), Obsidian (rank 20) and Firefox (rank 23). Bias: the list is heavily developer-focused, it counts install events rather than users, and it covers only apps distributed through Homebrew. Teams, Slack and Zoom are not in the top 25. The cask names for those apps were not checked. [Homebrew analytics](https://formulae.brew.sh/analytics/cask-install/365d/)
- StatCounter desktop browser share, United States, September 2026, all desktop systems (not macOS only): Chrome 60.84%, Edge 14.82%, Safari 14.06%, Firefox 5.57%, Opera 1.71%. [StatCounter](https://gs.statcounter.com/browser-market-share/desktop/united-states-of-america)
- Not verified: a macOS-only browser share. The page exists at https://gs.statcounter.com/browser-market-share/desktop/macos/worldwide, but its chart needs JavaScript and I could not read the figures. Safari is probably a much larger share on macOS than in the all-desktop number, but check the macOS page before relying on that.
- Not verified: a primary ranking of Teams, Slack, Zoom or Figma on macOS. Use your own usage or a short survey (decision 2).

Official shortcut documentation (checked):
- Apple, Mac keyboard shortcuts. Finder: Shift-Command-N creates a new folder, Command-Up Arrow goes to the parent folder, Shift-Command-G opens Go to Folder. Mission Control: Control-Up Arrow. Spotlight: Command-Space. Safari has its own Apple page, linked from this one, which was not read. [Apple](https://support.apple.com/en-us/102650)
- Google Chrome. Command+[ and Command+] go back and forward (Command+Left and Command+Right also work). Option+Command+Right and Option+Command+Left switch tabs. [Google](https://support.google.com/chrome/answer/157179)
- Microsoft Teams. Command+Shift+M toggles the microphone and Command+Shift+O toggles the camera, both listed for Mac. [Microsoft](https://support.microsoft.com/en-us/office/keyboard-shortcuts-for-microsoft-teams-2e8e2a70-e8d8-4a19-949b-4c36dd5292d2)
- Slack. Command+[ and Command+] go back and forward in history. Command+Shift+H starts, joins, leaves or ends a huddle. Command+Shift+Space toggles mute in a huddle. The page lists no mute shortcut for regular calls. [Slack](https://slack.com/help/articles/201374536-Slack-keyboard-shortcuts)
- Zoom (taken from a search summary, the article itself was not fetched, so verify before shipping). Command+Shift+A mutes or unmutes audio, Command+Shift+V starts or stops video, Command+Shift+S shares the screen, Command+Shift+N switches camera, Command+Shift+R records locally. Holding Space gives a temporary unmute. [Zoom KB0067050](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0067050)
- VS Code. The keybindings page only shows `alt+left` and `alt+right` for `workbench.action.navigateBack` and `navigateForward`, without a macOS-specific entry. Reading Alt as Option is an inference. Check the default in VS Code (Keyboard Shortcuts editor, Command+K Command+S). The default keybindings reference was not read. [VS Code](https://code.visualstudio.com/docs/configure/keybindings)

Key codes (Carbon `HIToolbox/Events.h`): M = 46, O = 31, [ = 33, ] = 30, Q = 12. [Events.h mirror](https://raw.githubusercontent.com/phracker/MacOSX-SDKs/master/MacOSX10.13.sdk/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/Headers/Events.h)

Keyboard layout (background knowledge, not verified by a source in this research): key codes name physical key positions, and the character a key produces depends on the active layout. On a German macOS layout, the bracket keys are believed to sit on other keys (Option+8 and Option+9 for [ and ]). If so, a recorded key code 33 may not produce the character that Chrome's Command+[ uses. Test this on your Mac before shipping any character-based entry.

## 4. Data model

Bundled in the app as `Shared/Config/shortcut_library.plist`. The example is shown as JSON. The plist has the same keys.

```json
{
  "schemaVersion": 1,
  "apps": [
    {
      "bundleIDs": ["com.google.Chrome"],
      "name": "Google Chrome",
      "sourceURL": "https://support.google.com/chrome/answer/157179",
      "verifiedOn": "2026-10-25",
      "shortcuts": [
        {
          "id": "chrome.back",
          "labelKey": "shortcut-library.chrome.back",
          "keyLabel": "⌘[",
          "suggestedButton": 4,
          "layoutDependent": true,
          "effect": { "type": "keyboardShortcut", "keycode": 33, "flags": 1048576 }
        },
        {
          "id": "chrome.forward",
          "labelKey": "shortcut-library.chrome.forward",
          "keyLabel": "⌘]",
          "suggestedButton": 5,
          "layoutDependent": true,
          "effect": { "type": "keyboardShortcut", "keycode": 30, "flags": 1048576 }
        }
      ]
    },
    {
      "bundleIDs": ["com.microsoft.teams2"],
      "name": "Microsoft Teams",
      "sourceURL": "https://support.microsoft.com/en-us/office/keyboard-shortcuts-for-microsoft-teams-2e8e2a70-e8d8-4a19-949b-4c36dd5292d2",
      "verifiedOn": "2026-10-25",
      "shortcuts": [
        {
          "id": "teams.mute",
          "labelKey": "shortcut-library.teams.mute",
          "keyLabel": "⌘⇧M",
          "suggestedButton": 4,
          "layoutDependent": true,
          "effect": { "type": "keyboardShortcut", "keycode": 46, "flags": 1179648 }
        }
      ]
    }
  ]
}
```

Notes:
- A library entry is a candidate, not a row. Picking one copies its `effect` into a new row. The user chooses the trigger.
- `keyLabel` is only for display. The app should render labels with the existing `UIStrings getStringForKeyCode:flags:font:`, which `RemapTableTranslator.m` already uses, so the labels match the rest of the UI.
- `layoutDependent` is `true` for every character-based shortcut in v1. It drives the layout test in phase 3.
- A `destructive` flag is not needed. Destructive entries are kept out of the file (see decision 5).

Where the data lives: bundled only. Updates ship with each app release. A later version could fetch the file from the repository described in `community-sharing.md`, but that is not part of this plan.

## 5. User experience

Text flow in the Buttons tab:
1. The user opens an app tab, for example Microsoft Teams, and clicks "Add" in the table. This is the existing add flow. The user presses a mouse button, and the effect list appears.
2. At the top of the effect list, a new section reads "Shortcuts for Microsoft Teams". It appears only when the tab's app is in the library.
3. Each entry shows its label, its key symbols (for example ⌘⇧M), and a small "Source" link. A hint says "Usually button 4" when `suggestedButton` is set.
4. Choosing an entry fills the effect. The button the user pressed becomes the trigger. The row is saved like any other row.
5. The Global tab has a "Browse shortcuts" button. It opens a searchable list of all library apps, like the app picker. Choosing an app opens its entries.
6. Settings has a "Show shortcut library" switch, on by default. Turning it off hides every library entry.

## 6. Technical design

New:
- `Shared/Config/shortcut_library.plist`: bundled data. Add it to the main app target.
- `App/UI/Main/Tabs/ButtonTab/RemapTable/ShortcutLibrary.swift`: loads the file, validates it at load time (known effect type, keycode 0-127, flags in 0x1E0000, non-empty source URL), and looks up entries by bundle ID.
- Localized labels under keys `shortcut-library.*`.

Changed:
- `App/UI/Main/Tabs/ButtonTab/RemapTable/RemapTableTranslator.m` and `RemapTableController.m`: add the library section to the effect popover for the current scope.
- `ButtonTabController.swift`: pass the current app scope to the effect popover, and add the Global "Browse shortcuts" entry point.
- Settings: one switch, stored in the config. Storing it needs a config version bump (see the presets plan, section 6).

Unchanged:
- The helper. Library entries become ordinary rows.
- `RemapScope`, the config format, and the remap matching rules.

Risks:
- Stale entries after app updates. Mitigation: `verifiedOn` dates, and a manual check before each release.
- Wrong bundle IDs (for example classic Teams).
- Layout mismatches for character-based entries (decision 3).
- Maintenance cost grows with each app. Every new app adds an ongoing review task.
- Labels that imply an app endorses the app. Mitigation: a short note that the library is not from the app vendor.
- Localization cost. Every label needs a translation, or falls back to English.

## 7. Privacy and legal

- Personal data: none. The library contains app bundle IDs, key codes and labels.
- Data collected: none. No network call, no telemetry.
- Consent: not needed for bundled data.
- Licensing of shortcut content: key combinations are facts. Write your own short labels, and cite the source for each entry. Do not copy help-page text, and do not copy whole tables from vendor documentation. This is a practical approach, not a legal conclusion. Ask a lawyer if you want certainty, especially for the EU.
- Trademarks: app names are used to identify which app an entry belongs to. Do not ship logos or icons. Add a note that the library is not from the app vendor.
- MMF License: the library is data inside the app. It does not change the monetization or licensing code. Question for you: if the app is ever sold, should the library be covered by the same MMF terms? This is not legal advice.

## 8. Phases and acceptance criteria

Phase 1: content.
- 6 to 12 apps, each with at least one shortcut, a `sourceURL` and a `verifiedOn` date.
- Each source URL returns a page that still shows the shortcut. Checked by hand before release, since this is not automated in the app.
- Every entry has `layoutDependent` set.
- The destructive-shortcut check passes. No entry uses Command+Q, Command+Shift+Q (log out) or Command+Option+Escape (force quit).

Phase 2: integration.
- Choosing an entry creates the same row as recording the same key by hand. An automated test compares the two dictionaries.
- Library entries appear only for matching bundle IDs.
- Turning the switch off hides every entry.
- The helper picks up the new row without a restart.

Phase 3: layout and release.
- Each `layoutDependent` entry is tested on a US layout and on a German layout. The result is recorded in the plist.
- Labels exist in English. German labels exist for at least the five most used entries, if the app is shipped in German. Check the existing `Localization` folder for which languages are supported.

## 9. Open decisions for the owner

1. Which apps are in v1?
   (a) Chrome, Firefox, Safari, Teams, Slack and VS Code (six apps). (b) 10 to 12 apps, adding Zoom, Finder, Obsidian and iTerm2. (c) Only the apps you use.
   Recommendation: (a) first, then extend based on what you use.
2. How are the apps chosen?
   (a) Your own usage only. (b) Homebrew analytics plus the macOS StatCounter page. (c) A short survey of users.
   Recommendation: (a) with (b). A survey needs an audience first.
3. How are key codes stored, given layouts differ?
   (a) Physical key codes only, with a documented caveat. (b) Store the character and resolve it to a key code for the current layout at runtime. (c) Document only, and mark entries as tested or untested.
   (d) For Chrome, use Command+Left and Command+Right (key codes 123 and 124), which Chrome lists for back and forward on Mac. Arrow keys do not change with the layout.
   Recommendation: (d) for Chrome. For other entries, your Mac uses the Austrian layout (`com.apple.keylayout.Austrian`), so test each character-based entry on it before you choose (a) or (b).
4. Who maintains the entries?
   (a) You alone. (b) Pull requests to the repository from `community-sharing.md`, with review. (c) Any user, through the community feature.
   Recommendation: (a) for v1. Move to (b) once the repository exists.
5. Are destructive shortcuts excluded?
   (a) Excluded through a fixed list (Quit, Log Out, Force Quit, Empty Trash). (b) Allowed, with a warning shown when the entry is chosen. (c) Allowed without restriction.
   Recommendation: (a).

## 10. Sources

- Homebrew, cask install analytics (365 days): https://formulae.brew.sh/analytics/cask-install/365d/
- StatCounter, desktop browser share, United States: https://gs.statcounter.com/browser-market-share/desktop/united-states-of-america
- StatCounter, macOS desktop browser share (not read, JavaScript chart): https://gs.statcounter.com/browser-market-share/desktop/macos/worldwide
- Apple, Mac keyboard shortcuts: https://support.apple.com/en-us/102650
- Google, Chrome keyboard shortcuts: https://support.google.com/chrome/answer/157179
- Microsoft, keyboard shortcuts for Teams: https://support.microsoft.com/en-us/office/keyboard-shortcuts-for-microsoft-teams-2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- Slack, keyboard shortcuts: https://slack.com/help/articles/201374536-Slack-keyboard-shortcuts
- Zoom, KB0067050 (search summary only): https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0067050
- VS Code, keybindings: https://code.visualstudio.com/docs/configure/keybindings
- Carbon `HIToolbox/Events.h` (mirror of the macOS 10.13 SDK): https://raw.githubusercontent.com/phracker/MacOSX-SDKs/master/MacOSX10.13.sdk/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/Headers/Events.h
- Repository files: `App/UI/Main/Tabs/ButtonTab/RemapTable/RemapTableTranslator.m`, `App/UI/Main/Tabs/ButtonTab/AppTabs/AppTabs.swift`, `Shared/Config/default_config.plist`, `License`
