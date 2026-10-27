#!/bin/zsh
# Compiles the real AppTabs.swift with stubs and runs main.swift.
# Usage: App/UI/Main/Tabs/ButtonTab/AppTabs/Tests/run_tests.sh
set -e
HERE=${0:A:h}
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
swiftc -suppress-warnings \
    "$HERE/../AppTabs.swift" "$HERE/Stubs.swift" "$HERE/main.swift" \
    -o "$OUT/AppTabsTests"
"$OUT/AppTabsTests"
