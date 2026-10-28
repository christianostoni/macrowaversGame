#!/bin/sh
# Bakes the hologram hand's skins: see make_snap_hint_hand.swift. Run from the repository's root.
set -e
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
# Top-level code only runs from a main.swift.
cp Assets/SnapHint/make_snap_hint_hand.swift "$build/main.swift"
find Sources/Macrowavers/Model -name '*.swift' -print0 \
    | xargs -0 swiftc -O -o "$build/make_snap_hint_hand" "$build/main.swift"
"$build/make_snap_hint_hand"
