# App presets

Status: proposal. Nothing here is built. No code was changed.

## 1. Summary

Ship a small, reviewed set of built-in button presets for popular apps, starting with Microsoft Teams (button 4 toggles the microphone, button 5 toggles the camera) and Google Chrome (button 4 goes back, button 5 goes forward). A preset is data in the same remap row format the app already stores. It is written into one app tab only when the user clicks Add. Nothing is applied automatically, nothing is sent over the network, and the remap engine does not change. This is the cheapest of the three ideas and the right first step. One open question must be settled first: whether the presets' physical key codes work on your keyboard layout (see decision 5).

## 2. Goals and non-goals

Goals:
- Add a verified preset to an app tab in one click, after an optional preview.
- Store presets in exactly the existing row format, so the helper needs no changes.
- Give every preset a source link and a "verified on" date.
- Work offline, with no account, no analytics and no personal data.

Non-goals:
- Applying presets automatically, or showing presets on the Global tab.
- Delivering presets from a server. That belongs to idea 3.
- Presets for apps without a verified, citable shortcut source.
- Changing remap matching, adding permissions, or changing the helper.

## 3. Research findings

Facts verified in this repository (paths relative to the repo root):
- Remap rows have the keys `trigger`, `modifiers`, `effect` and an optional `app` (`Shared/Constants.h` lines 123-128).
- At load time the helper adds the row's `app` to the modifier precondition (`Helper/Core/Remap/Remap.m` lines 209-221).
- App-specific rows always beat global rows, regardless of how many modifiers each has (`Helper/Core/Remap/RemapSwizzler.m` lines 172-173 and 296-307). Global rows are never disabled by app rows, and app rows are never disabled by global ones.
- Button numbers are 1-based. The helper adds 1 to `kCGMouseEventButtonNumber` (`Helper/Core/Buttons/ButtonInputReceiver.m` lines 98 and 120). So "button 4" in the owner's words is trigger `button: 4`.
- A keyboard-shortcut effect is flat: `{type: keyboardShortcut, keycode, flags}` (`App/UI/Main/Tabs/ButtonTab/RemapTable/RemapTableTranslator.m` lines 655-660).
- MMF already has a named preset mechanism: `Constants.defaultRemaps.threeButtons` in `Shared/Config/default_config.plist`. `configVersion` is 24. `Shared/Config/ConfigReadme.md` says the `Remaps` array in the default config must stay empty.
- The app tab picker lists running regular apps, with a search field and a "Choose Other..." button (`App/UI/Main/Tabs/ButtonTab/AppTabs/AppTabPicker.swift`, lines 60 and 96-107).
- "Restore Defaults" in an app tab deletes that tab's rows and keeps the tab (`App/UI/Main/Tabs/ButtonTab/ButtonTabController.swift`, `confirmDeleteRows`).
- Writing rows already goes through `commitConfig()`, which writes the file and sends `configFileChanged` to the other process (`Shared/Config/Config.m` lines 134-145). The helper then reloads remaps (`Config.m` lines 170-181).
- Modifier flags: Command 1048576, Shift 131072, Control 262144, Option 524288. Command+Shift is 1179648 (checked by arithmetic on this Mac).

Facts verified on the owner's Mac or in vendor and standards sources:
- Microsoft Teams (new) has bundle ID `com.microsoft.teams2`. Checked with `defaults read` on `/Applications/Microsoft Teams.app`. The bundle ID of classic Teams was not verified.
- Google Chrome has bundle ID `com.google.Chrome` (checked on this Mac).
- Teams on Mac: Command+Shift+M toggles the microphone and Command+Shift+O toggles the camera. Both are listed under "Meetings and Calls" for Mac. The Microsoft page has no article date, only a 2026 footer. [Microsoft support](https://support.microsoft.com/en-us/office/keyboard-shortcuts-for-microsoft-teams-2e8e2a70-e8d8-4a19-949b-4c36dd5292d2)
- Chrome on Mac: Command+[ and Command+] go back and forward. Command+Left and Command+Right do the same. [Google Chrome Help](https://support.google.com/chrome/answer/157179)
- Carbon key codes, from the macOS 10.13 SDK header (`HIToolbox/Events.h`): `kVK_ANSI_M` = 46, `kVK_ANSI_O` = 31, `kVK_ANSI_LeftBracket` = 33, `kVK_ANSI_RightBracket` = 30, `kVK_ANSI_Q` = 12. [Events.h mirror](https://raw.githubusercontent.com/phracker/MacOSX-SDKs/master/MacOSX10.13.sdk/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/Headers/Events.h)

Not verified:
- Whether the Teams shortcuts are the same in every Teams build. Check on the Teams version you use.
- Whether a German macOS keyboard layout changes what key code 33 produces. See decision 5.
- Whether Chrome matches key equivalents by key code or by character. This decides whether the layout question matters.

## 4. Data model

Presets are bundled in the app. Recommended file: `Shared/Config/app_presets.plist`. The example is shown as JSON. The plist has the same keys and types (`integer`, `string`, `dict`, `array`).

```json
{
  "schemaVersion": 1,
  "presets": [
    {
      "id": "teams-mic-camera",
      "displayName": "Microsoft Teams: mic and camera",
      "bundleIDs": ["com.microsoft.teams2"],
      "sourceURL": "https://support.microsoft.com/en-us/office/keyboard-shortcuts-for-microsoft-teams-2e8e2a70-e8d8-4a19-949b-4c36dd5292d2",
      "verifiedOn": "2026-10-25",
      "rows": [
        {
          "trigger": { "button": 4, "duration": "click", "level": 1 },
          "modifiers": {},
          "effect": { "type": "keyboardShortcut", "keycode": 46, "flags": 1179648 }
        },
        {
          "trigger": { "button": 5, "duration": "click", "level": 1 },
          "modifiers": {},
          "effect": { "type": "keyboardShortcut", "keycode": 31, "flags": 1179648 }
        }
      ]
    },
    {
      "id": "chrome-back-forward",
      "displayName": "Google Chrome: back and forward",
      "bundleIDs": ["com.google.Chrome"],
      "sourceURL": "https://support.google.com/chrome/answer/157179",
      "verifiedOn": "2026-10-25",
      "rows": [
        {
          "trigger": { "button": 4, "duration": "click", "level": 1 },
          "modifiers": {},
          "effect": { "type": "keyboardShortcut", "keycode": 33, "flags": 1048576 }
        },
        {
          "trigger": { "button": 5, "duration": "click", "level": 1 },
          "modifiers": {},
          "effect": { "type": "keyboardShortcut", "keycode": 30, "flags": 1048576 }
        }
      ]
    }
  ]
}
```

Notes on the format:
- Preset rows have no `app` key. When the user applies a preset, the code copies each row and adds `"app": "<bundle ID of the tab>"`. The saved rows then match the existing shape exactly.
- If an app has several bundle IDs (for example classic and new Teams), the tab uses the bundle ID the user actually has open.
- The `modifiers: {}` dict matches what `default_config.plist` already stores for "no modifiers".

Where the data lives: bundled only, with no server call. Later updates could reuse the repository planned in `community-sharing.md`, but that is not part of this plan.

## 5. User experience

Text flow in the Buttons tab:
1. The user clicks the "+" button at the bottom of the app strip and picks Microsoft Teams from the running-apps list, or uses "Choose Other...". An empty Teams tab opens.
2. Above the empty table, a one-line banner reads: "A preset is available for Microsoft Teams: button 4 mic, button 5 camera." It has two buttons, "Show" and "Add".
3. "Show" opens a popover with one line per row: button number, action name, and the shortcut written with symbols (for example ⌘⇧M). Each line has a checkbox, checked by default. A "Source" link sits at the bottom.
4. "Add" writes the checked rows into the Teams tab and hides the banner. A short confirmation appears with an "Undo" link for the current session.
5. "Undo" restores the table to the exact rows it had before Add. If the tab had no rows, it has none again and the banner returns.
6. If button 4 already has a row in this tab, that line says "Already set" and its checkbox is off. The user can check it to replace the row.
7. Chrome works the same way in the Chrome tab.
8. The Global tab never shows presets.
9. Tabs that already have rows show no banner.
10. "Restore Defaults" keeps its current behavior (see decision 4).

## 6. Technical design

New:
- `Shared/Config/app_presets.plist`: bundled data. Add it to the main app target in Xcode, so it is copied into the bundle.
- `App/UI/Main/Tabs/ButtonTab/AppTabs/AppPresets.swift`: loads the plist, matches bundle IDs, builds rows with the `app` key, and checks for conflicts with existing rows.
- Localized strings under keys `app-presets.*`, used through `MFLocalizedString`.

Changed:
- `App/UI/Main/Tabs/ButtonTab/ButtonTabController.swift`: show the banner for an empty app tab, and call the existing `replaceRows(forScope:with:)` helper (around line 490). That helper only replaces rows of one scope, so global and other app rows are untouched.
- Optional: `AppTabStripView.swift` could show a small dot on tabs that have an available preset.

Unchanged:
- The helper. Preset rows are ordinary rows, and the existing `commitConfig()` path reloads them.
- The config version, as long as presets are only bundled. If you store "banner dismissed" in the config, bump `configVersion` from 24 to 25. Add a migration step in `Config.m`, following the existing 22-to-23 and 23-to-24 steps, and document it in `ConfigReadme.md`.

Risks:
- Key-code mismatch on non-US layouts. This is the biggest risk for you (decision 5).
- Shortcuts change with app updates, so presets go stale. Mitigation: `verifiedOn` dates, and a manual check before each release.
- Bundle ID variants. Classic Teams may use a different ID, not verified here.
- A user who changed an app's own shortcut settings gets a preset that does not match.
- The undo state lives in memory and is lost when the app quits. This is acceptable for v1.
- Checked: `ButtonTabController.swift` calls `RemapScope.rows(forScope:inRemaps:)`. That is how Swift imports the Objective-C method `rowsForScope:inRemaps:` in `RemapScope.h`. The App scheme builds with this code (2026-10-25).

## 7. Privacy and legal

- Data collected: none. No network call, no account, no analytics.
- Personal data: none. Presets contain bundle IDs, key codes and modifier flags only.
- Consent: not needed for bundled data. If "banner dismissed" is stored, it is a local preference.
- Licensing of preset values: which keys an app uses are facts. Write your own label and cite the source. Do not copy help-page text.
- Trademarks: app names are used only to identify the app. Do not ship app logos. The app already shows icons of installed apps at runtime (`AppTabs.swift`, `icon(for:)`).
- MMF License: presets are data inside the app and do not change the monetization or licensing code. Question for you: if you ever charge for the app, do presets count as "Your Source" that must keep the MMF monetization systems? This is not legal advice. Ask a lawyer before any commercial release.

## 8. Phases and acceptance criteria

Phase 1: data and logic, no UI.
- `app_presets.plist` parses and contains exactly the two presets above.
- A validator passes every row: trigger button 1-5, keycode 0-127, flags only in the bits 0x1E0000 (Command, Shift, Control, Option), effect type `keyboardShortcut`.
- Unit test: applying the Teams preset to an empty scope gives two rows, each with `app` = `com.microsoft.teams2`. The global rows are identical before and after (same count and content).
- Unit test: a button that already has a row is skipped by default.

Phase 2: UI.
- The banner appears only for an app tab with zero rows and a matching preset.
- Add writes the rows. Undo restores the exact previous array (an empty diff).
- Manual test on your Mac: in Teams, button 4 toggles the mic and button 5 toggles the camera. In Chrome, button 4 goes back. In Safari, the same button does not trigger the Chrome preset.
- The helper picks up the change without a restart (within 2 seconds, checked by hand).
- English strings exist for every new key.

Phase 3: verification and release.
- Each preset has `verifiedOn` within 30 days of the release date, checked in the real app.
- Both US and German layouts are tested for each preset. The result is recorded in a note in the plist.
- Presets beyond Teams and Chrome wait for the shortcut library plan (`shortcut-library.md`).

## 9. Open decisions for the owner

1. Which presets ship in v1?
   (a) Teams and Chrome only. (b) Teams, Chrome, Slack, Zoom and VS Code. (c) Whatever you use every day.
   Recommendation: (a). Add more from the shortcut library later.
2. How is a preset offered?
   (a) A banner in empty app tabs. (b) Applied automatically when a tab is created. (c) Only inside the "+" picker.
   Recommendation: (a). Never apply automatically.
3. What happens when a button is already set?
   (a) Skip it by default, with a per-row replace option. (b) Replace all. (c) Ask once in a sheet.
   Recommendation: (a).
4. Does "Restore Defaults" bring the preset back?
   (a) No, it only deletes rows, as now. (b) Yes, it restores the preset. (c) Show two buttons.
   Recommendation: (a). The banner comes back on its own, because the tab is empty again.
5. Which keyboard layout do you use, and how should key codes be stored?
   (a) Keep physical key codes and document the layout caveat. (b) Store the character and resolve it to a key code for the current layout at runtime. (c) Ship only presets tested on your layout. (d) Use the arrow keys for Chrome: Command+Left (key code 123) and Command+Right (key code 124). Chrome's help page lists these for back and forward on Mac, and arrow keys are not character keys, so the layout does not change them.
   Recommendation: (d) for Chrome, which needs no layout test. Keep (a) for letter keys such as M (46) and O (31), which sit in the same place on common European layouts. Your Mac uses the Austrian layout (`com.apple.keylayout.Austrian`, read from the system preferences on 2026-10-25), which has the same bracket problem as German. Confirm the letter keys in the layout test before relying on them.

## 10. Sources

- Microsoft, keyboard shortcuts for Teams: https://support.microsoft.com/en-us/office/keyboard-shortcuts-for-microsoft-teams-2e8e2a70-e8d8-4a19-949b-4c36dd5292d2
- Google, Chrome keyboard shortcuts: https://support.google.com/chrome/answer/157179
- Carbon `HIToolbox/Events.h` (mirror of the macOS 10.13 SDK): https://raw.githubusercontent.com/phracker/MacOSX-SDKs/master/MacOSX10.13.sdk/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/Headers/Events.h
- Repository files: `Shared/Constants.h`, `Helper/Core/Remap/Remap.m`, `Helper/Core/Remap/RemapSwizzler.m`, `Helper/Core/Buttons/ButtonInputReceiver.m`, `App/UI/Main/Tabs/ButtonTab/RemapTable/RemapTableTranslator.m`, `App/UI/Main/Tabs/ButtonTab/AppTabs/AppTabs.swift`, `App/UI/Main/Tabs/ButtonTab/AppTabs/AppTabPicker.swift`, `App/UI/Main/Tabs/ButtonTab/ButtonTabController.swift`, `Shared/Config/Config.m`, `Shared/Config/ConfigReadme.md`, `Shared/Config/default_config.plist`, `License`
