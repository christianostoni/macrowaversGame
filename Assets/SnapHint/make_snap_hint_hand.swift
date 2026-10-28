// Bakes the hologram hand's skins (`SnapHintBake`: one `HandSurface` mesh per distinct pose of `SnapHint`'s loop)
// into Sources/Macrowavers/Resources/SnapHintHand.bin, so the app reads them instead of building them: ~0.3 s here,
// optimised, but ~20 s in a Debug build and far longer on the headset's background threads.
//
// Run it again after any change to SnapHint.swift, HandSurface.swift or SnapHintBake.framesPerSecond: the app checks
// the file against the code and, if they differ, builds the skins itself (slowly) and says so in the console.
//
// Usage, from the repository's root: sh Assets/SnapHint/make_snap_hint_hand.sh
// It compiles this file with the app's model (Sources/Macrowavers/Model), optimised, and runs it.
import Foundation

let output = URL(fileURLWithPath: "Sources/Macrowavers/Resources/SnapHintHand.bin")
let start = Date()
let bake = SnapHintBake.bake()
let data = try bake.encoded()
try data.write(to: output)
let vertices = bake.skins.map(\.mesh.positions.count).reduce(0, +)
print("\(bake.skins.count) skins for \(bake.frames.count) frames, \(vertices / bake.skins.count) vertices each, "
    + "\(data.count / 1024) KB, in \(String(format: "%.1f", Date().timeIntervalSince(start))) s -> \(output.path)")
