---
name: build-and-install
description: Build Mac Mouse Fix NG locally with code signing and install it into /Applications. Use when the user asks to build, rebuild, install or run the latest local version of NG, or when local changes are not visible in the app they open.
---

# Build and install Mac Mouse Fix NG locally

This is a local developer build. Nothing here publishes anything. Build outside the repo, so no build products end up in the working tree.

## Facts (checked in this repo)

- Scheme `App` builds the app and its helper. Configuration `Debug` produces `Mac Mouse Fix NG.app`. Locate it with a glob under the build folder, because the name can change. `docs/features/mmf-ng-test-and-install.md` still says `Mac Mouse Fix.app`, which is out of date.
- The helper is `Contents/Library/LoginItems/Mac Mouse Fix NG Helper.app` inside the app. macOS registers it with `SMAppService`, which requires a properly signed app. An unsigned or ad hoc build opens, but the helper can't be registered, so remapping does not work and the Buttons tab stays locked.
- The app and the helper use the bundle ID `com.soyoxymor0n.mac-mouse-fix` (`Shared/Constants.h`). Their settings live in `~/Library/Application Support/com.soyoxymor0n.mac-mouse-fix/`. A new install reuses those settings, so the mappings you have are kept.
- The project's `DEVELOPMENT_TEAM` may not match the signing identity on this Mac. Get the team from the identity, as described below. Don't write the team into any file.
- `CODE_SIGNING_ALLOWED=NO` gives a compile check only. The app can't be installed from that build.

## Prerequisites (owner)

1. Xcode must be signed in to an Apple ID that has a developer team: Xcode, Settings, Accounts. Only the owner can do this. If signing fails with "No Accounts" or "No Account for Team", sign in there. The Apple ID list in the defaults is not a reliable check, so use the team list in step 2.
2. A valid `Apple Development` identity must be in the keychain. Check with `security find-identity -v -p codesigning`.

## Steps

1. **Version.** Follow `docs/standards/versioning.md`. `MARKETING_VERSION` lives in `Mouse Fix.xcodeproj/project.pbxproj` (app and Helper, Debug and Release: four places). Bump it only for a build that is handed out. The build number (30000 + commit count) and the commit are set automatically on every build. The About tab shows them, e.g. `4.2.0 (38720 · 1a2b3c4 · Debug)`, so you can check which build is installed.

2. **Team.** Use a team that Xcode's signed-in account belongs to. Not the team in the keychain identity: the two can differ, and signing then fails with "No Account for Team". List the candidates Xcode knows:

       defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier | grep -oE '[A-Z0-9]{10}' | sort -u

   Try each candidate with the build in step 3. The one that works is the team of the signed-in account. Keep the value in your shell only, never in a file.

3. **Build.** Use a folder outside the repo. The build takes several minutes, so run it in the background and check for `** BUILD SUCCEEDED **`:

       xcodebuild -project "Mouse Fix.xcodeproj" -scheme App -configuration Debug \
         -derivedDataPath "<folder outside the repo>" -allowProvisioningUpdates \
         DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic \
         'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) FORCE_LICENSED' build

   Always pass `FORCE_LICENSED`. The project doesn't set it, and without it the About tab shows the trial section ("free days") again. `$(inherited)` keeps the targets' own conditions (`DEBUG IS_MAIN_APP` for the app). Check with `-showBuildSettings` and the same arguments if in doubt.

   Manual signing with `CODE_SIGN_IDENTITY` fails on this project. The frameworks ask for a "Mac Development" certificate, and the app needs a provisioning profile for its keychain access group entitlement. Use automatic signing with a signed-in Xcode account.

4. **Check the build.**

       APP=$(ls -d "<folder>/Build/Products/Debug/Mac Mouse Fix NG.app")
       codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "Authority|TeamIdentifier|Identifier"
       for p in "$APP/Contents/Info.plist" "$APP/Contents/Library/LoginItems/Mac Mouse Fix NG Helper.app/Contents/Info.plist"; do
         /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" -c "Print :CFBundleVersion" -c "Print :MFGitCommit" "$p"
       done

   The version must match what you expect, the app and the Helper must have the same build number and commit, and the signature must be `Apple Development` with your team.

5. **Install.** Do this only when the owner asks for it.
   - Quit the app: `osascript -e 'tell application "Mac Mouse Fix NG" to quit'`.
   - Back up the settings first: `cp -R ~/Library/Application\ Support/com.soyoxymor0n.mac-mouse-fix "<folder outside the repo>/settings-backup"`. Do not skip this. If the old helper is still running when its bundle disappears, it treats that as an uninstall and moves the whole settings folder to the Trash, and the app then starts with default settings. Restoring from the Trash needs Finder's "Put Back" by the owner, because the Trash is protected from scripts.
   - Replace the old copy: `rm -rf "/Applications/Mac Mouse Fix NG.app" && ditto --noextattr --noacl "$APP" "/Applications/Mac Mouse Fix NG.app"`. Use `ditto`, so the signature is kept. `--noextattr --noacl` avoids `Operation not permitted` errors on the Sparkle files. After the copy, run `codesign --verify --deep --strict` on the new copy and check that the settings folder still exists.
   - Open it: `open "/Applications/Mac Mouse Fix NG.app"`.
   - Check which helper runs. `launchctl print` only shows a path relative to the app, so read the executable path of the running helper: `lsof -a -p <helper pid> -d txt -Fn | grep '^n/'`. It must be under `/Applications`.
   - The helper starts only after the owner approves the new background item: System Settings, General, Login Items and Extensions, Background App Activity, turn on Mac Mouse Fix NG. Only the owner can do that. Until then the app's switch is on, but no helper runs. This was observed on 2026-10-28.
   - If an older copy of the app is still registered (its helper runs from an old build folder), stop its launchd job with `launchctl bootout gui/$(id -u)/com.soyoxymor0n.mac-mouse-fix.helper.ng`, then reopen the new app. Don't run `sfltool resetbtm`, because it resets every login item on the Mac. `sfltool dumpbtm` hung in this session, so don't rely on it.

6. **Permissions.** macOS may ask the owner to approve the app and the helper again under System Settings, Privacy & Security, Accessibility. Only the owner can do that.

## Isolated test builds

To test a build without touching the owner's running helper or settings, copy the working tree (`rsync -a --exclude .git`) and change the bundle IDs in the copy only: `kMFBundleIDApp` and `kMFBundleIDHelper` in `Shared/Constants.h`, `kMFLaunchdHelperIdentifierSM`, and `PRODUCT_BUNDLE_IDENTIFIER` in the project file. Never commit those changes. Delete the test's settings folder and its launchd agent afterwards.

## Status (2026-10-28)

- Build: a signed build of version 4.1.0 succeeded once Xcode had an account, using a team from step 2.
- Install: the app is in `/Applications`, and its signature verifies.
- Helper: set to 4.1.0 as well, in the same two configurations as the app.
- After a new install, the helper may not start from `/Applications` until the owner approves the background item again: System Settings, General, Login Items and Extensions, Background App Activity. Check with `lsof` which helper runs. If it runs from an older build folder, stop its job with `launchctl bootout gui/$(id -u)/com.soyoxymor0n.mac-mouse-fix.helper.ng`, then reopen the app and check again.

## Never store

Apple IDs, passwords, app-specific passwords, certificates, private keys, provisioning profiles, team IDs or notarization credentials in this file or anywhere in the repo.
