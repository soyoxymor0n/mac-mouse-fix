#!/bin/zsh
# Compiles the real AppPresets.swift and runs AppPresetsTests.swift.
# AppPresets.swift only needs Foundation, so it is built with swiftc on its own, without the app.
# Usage: App/UI/Main/Tabs/ButtonTab/AppTabs/Tests/run_preset_tests.sh
set -e
HERE=${0:A:h}
ROOT=${HERE:h:h:h:h:h:h:h}
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -parse-as-library -suppress-warnings \
    "$ROOT/App/UI/Main/Tabs/ButtonTab/AppTabs/AppPresets.swift" "$HERE/AppPresetsTests.swift" \
    -o "$OUT/AppPresetsTests"
"$OUT/AppPresetsTests"
