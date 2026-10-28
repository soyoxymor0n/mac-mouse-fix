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

1. Xcode must be signed in to the Apple ID that owns the signing team: Xcode, Settings, Accounts. Only the owner can do this. Check it with `defaults read com.apple.dt.Xcode DVTDeveloperAccountManagerAppleIDLists`. An empty list means no account, and `xcodebuild -allowProvisioningUpdates` then fails with "No Accounts".
2. A valid `Apple Development` identity must be in the keychain. Check with `security find-identity -v -p codesigning`.

## Steps

1. **Version.** `MARKETING_VERSION` lives in `Mouse Fix.xcodeproj/project.pbxproj` (in two configurations). Change it there before a release build.

2. **Team.** Read the team from the identity name. Its last part is the team ID in parentheses:

       TEAM=$(security find-identity -v -p codesigning | sed -n 's/.*(\([A-Z0-9]\{10\}\)).*/\1/p' | head -1)

3. **Build.** Use a folder outside the repo. The build takes several minutes, so run it in the background and check for `** BUILD SUCCEEDED **`:

       xcodebuild -project "Mouse Fix.xcodeproj" -scheme App -configuration Debug \
         -derivedDataPath "<folder outside the repo>" -allowProvisioningUpdates \
         DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic build

   Manual signing with `CODE_SIGN_IDENTITY` fails on this project. The frameworks ask for a "Mac Development" certificate, and the app needs a provisioning profile for its keychain access group entitlement. Use automatic signing with a signed-in Xcode account.

4. **Check the build.**

       APP=$(ls -d "<folder>/Build/Products/Debug/Mac Mouse Fix NG.app")
       codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "Authority|TeamIdentifier|Identifier"
       /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist"

   The version must match what you expect, and the signature must be `Apple Development` with your team.

5. **Install.** Do this only when the owner asks for it.
   - Quit the app: `osascript -e 'tell application "Mac Mouse Fix NG" to quit'`.
   - Replace the old copy: `rm -rf "/Applications/Mac Mouse Fix NG.app" && ditto "$APP" "/Applications/Mac Mouse Fix NG.app"`. Use `ditto`, so the signature is kept.
   - Open it: `open "/Applications/Mac Mouse Fix NG.app"`.
   - Check that the helper runs from the new location: `launchctl print gui/$(id -u)/com.soyoxymor0n.mac-mouse-fix.helper.ng | grep "program identifier"`. The path should point into `/Applications`. If it still points at an old build, quit the app again and reopen it. This step is not verified yet.

6. **Permissions.** macOS may ask the owner to approve the app and the helper again under System Settings, Privacy & Security, Accessibility. Only the owner can do that.

## Isolated test builds

To test a build without touching the owner's running helper or settings, copy the working tree (`rsync -a --exclude .git`) and change the bundle IDs in the copy only: `kMFBundleIDApp` and `kMFBundleIDHelper` in `Shared/Constants.h`, `kMFLaunchdHelperIdentifierSM`, and `PRODUCT_BUNDLE_IDENTIFIER` in the project file. Never commit those changes. Delete the test's settings folder and its launchd agent afterwards.

## Status

Build and install are blocked until the owner signs Xcode in to the Apple account. Until then, the steps above stop at the build error `No Accounts`.

## Never store

Apple IDs, passwords, app-specific passwords, certificates, private keys, provisioning profiles, team IDs or notarization credentials in this file or anywhere in the repo.
