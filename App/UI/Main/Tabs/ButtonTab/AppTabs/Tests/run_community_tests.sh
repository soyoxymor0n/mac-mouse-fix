#!/bin/zsh
# Compiles the real CommunitySetups.swift and AppPresets.swift and runs CommunitySetupsTests.swift against the fixtures in CommunityFixtures.
# Both files only need Foundation, so they are built with swiftc on their own, without the app. Nothing is downloaded.
# Usage: App/UI/Main/Tabs/ButtonTab/AppTabs/Tests/run_community_tests.sh
set -e
HERE=${0:A:h}
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -parse-as-library -suppress-warnings \
    "$HERE/../AppPresets.swift" "$HERE/../CommunitySetups.swift" "$HERE/CommunitySetupsTests.swift" \
    -o "$OUT/CommunitySetupsTests"
"$OUT/CommunitySetupsTests" "$HERE/CommunityFixtures"
