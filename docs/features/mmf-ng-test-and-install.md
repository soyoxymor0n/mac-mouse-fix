# Testing and installing Mac Mouse Fix NG

The fork now shows as "Mac Mouse Fix NG" in the menu bar, window titles, dialogs and the Accessibility list. The bundle identifier is unchanged (`com.soyoxymor0n.mac-mouse-fix`), so the settings stay in `~/Library/Application Support/com.soyoxymor0n.mac-mouse-fix/`. The file on disk is still `Mac Mouse Fix.app`, because the product name is tied to the schemes and the licensing code, which I left alone.

## Build

Option A, in Xcode: open `Mouse Fix.xcodeproj`, choose the scheme **App**, and press Run.

Option B, on the command line (keeps the build outside the repo):

    xcodebuild -project "Mouse Fix.xcodeproj" -scheme App -configuration Debug \
      -derivedDataPath <a folder outside the repo> -allowProvisioningUpdates \
      DEVELOPMENT_TEAM=<your team id> CODE_SIGN_STYLE=Automatic build

The app is then at `<folder>/Build/Products/Debug/Mac Mouse Fix NG.app`. The helper sits inside it at `Contents/Library/LoginItems/Mac Mouse Fix NG Helper.app`.

## Install

Nothing is installed into `/Applications` automatically. To keep it, copy `Mac Mouse Fix NG.app` there yourself. To try it first, open it from the build folder.

The official Mac Mouse Fix has its own bundle identifier, so both can be on the Mac. They react to the same mouse buttons, so quit the official app while you test NG.

## First run

1. Open System Settings, Privacy & Security, Accessibility. Turn on **Mac Mouse Fix NG** and, if it is listed, **Mac Mouse Fix NG Helper**. The helper is a new executable, so expect new entries. This step needs you: I don't change system permissions.
2. Open the Buttons tab. The window and the menu bar should say "Mac Mouse Fix NG".

## What to test

- **Library in the effect menu.** Add an app tab for Google Chrome, click "+", and choose the button. The top of the effect menu now lists the library entries for Chrome (Back, Forward, tab switching and more). Pick one. The row should save with the symbols shown.
- **Sequences.** The library has two sequence entries so far, both from Microsoft OneNote (switch between pages: a chord, then an arrow). The table shows the steps joined by "then". Press the button in OneNote. The steps are sent in order with a short gap. Teams meeting reactions are not in the library yet: the research did not find a documented shortcut for them. This is an open research question.
- **Layout.** On the German or Austrian layout, entries that use `[`, `]`, Z or Y pick the matching key. For example, Chrome's Back uses Option+5 on German. Check this in Chrome.
- **Unchanged.** Presets (Teams and Chrome banner), per-app tabs and Restore Defaults work as before.

## What I checked

- The app and the helper build (Debug, App scheme) with the new names.
- The generated library: 48 apps and 1203 entries, all key codes in range, no destructive labels (`tools/check_library.py`).
- The sequence code compiles. It has not run against a real mouse. That needs you.

## Not in this version

- Recording your own sequences in the UI. Sequences come from the library only.
- Entries for apps whose shortcut pages could not be read (see `shortcut-research/README.md`).
