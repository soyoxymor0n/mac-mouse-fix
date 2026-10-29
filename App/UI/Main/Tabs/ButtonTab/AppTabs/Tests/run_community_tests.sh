#!/bin/zsh
# Compiles the real CommunitySetups.swift, CommunitySharing.swift and AppPresets.swift and runs CommunitySetupsTests.swift (with CommunitySharingTests.swift)
# against the fixtures in CommunityFixtures.
# Both files only need Foundation, so they are built with swiftc on their own, without the app. Nothing is downloaded or uploaded: a URLProtocol stub answers the uploader.
# Usage: App/UI/Main/Tabs/ButtonTab/AppTabs/Tests/run_community_tests.sh
set -e
HERE=${0:A:h}
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -parse-as-library -suppress-warnings \
    "$HERE/../AppPresets.swift" "$HERE/../CommunitySetups.swift" "$HERE/../CommunitySharing.swift" \
    "$HERE/CommunitySetupsTests.swift" "$HERE/CommunitySharingTests.swift" \
    -o "$OUT/CommunitySetupsTests"
"$OUT/CommunitySetupsTests" "$HERE/CommunityFixtures"
