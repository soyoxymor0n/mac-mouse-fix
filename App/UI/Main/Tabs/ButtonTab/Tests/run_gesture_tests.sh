#!/bin/zsh
# Compiles the real GestureHintModel.swift and runs GestureHintTests.swift.
# GestureHintModel.swift only needs Foundation, so it is built with swiftc on its own, without the app.
# Usage: App/UI/Main/Tabs/ButtonTab/Tests/run_gesture_tests.sh
set -e
HERE=${0:A:h}
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -parse-as-library \
    "$HERE/../GestureHintModel.swift" "$HERE/GestureHintTests.swift" \
    -o "$OUT/GestureHintTests"
"$OUT/GestureHintTests"
