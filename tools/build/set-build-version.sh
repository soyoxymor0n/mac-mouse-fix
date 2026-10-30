#!/bin/sh
# Sets the build number and the commit in the built Info.plist of the app or the Helper. Run by the "Set Build Number and Commit" build phase of both targets.
#
# Convention (see docs/standards/versioning.md):
#   - Version (CFBundleShortVersionString): MARKETING_VERSION in the Xcode project, e.g. 4.2.0. Bumped by hand for releases.
#   - Build number (CFBundleVersion): 30000 + number of commits in HEAD. Above upstream's build numbers (25324 when the fork started),
#     and the same for the app and the Helper, which the Helper uses to check that it belongs to the running app.
#   - Commit (MFGitCommit): short hash of HEAD, with "-dirty" when tracked files have uncommitted changes. Shown in the About tab.
# Only the built Info.plist changes, never the one in the repo.

set -e

plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
cd "${PROJECT_DIR}"

if count=$(git rev-list --count HEAD 2>/dev/null); then
    build=$((30000 + count))
    commit=$(git rev-parse --short=7 HEAD)
    if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then
        commit="${commit}-dirty"
    fi
else
    # Not a git checkout (e.g. a source archive): keep the build number from the Info.plist
    build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist")
    commit="unknown"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$plist"
/usr/libexec/PlistBuddy -c "Delete :MFGitCommit" "$plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :MFGitCommit string $commit" "$plist"

echo "set-build-version: ${PRODUCT_NAME} build $build, commit $commit"
