"""Measures the profile of the design team's apple for the spiral cut, without opening Blender.

Usage (USD's Python API, `pxr`, ships with Blender; Blender itself is not used):
    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
        -P Assets/Blender/apple/measure_apple_profile.py -- Sources/Macrowavers/Resources/Apple.usdz

`Apple.usdz` is the design team's `apple_RCP.usdz` as it is: `Skin`, `Flesh` (just inside the skin), `Stem` and
`Leaf`, with Reality Composer Pro airbrush materials. The closed apple is drawn from it; the open one is the
spiral the code builds and deforms (`AppleShape`, `AppleSpiral.metal`), a body of revolution. This script gives that
spiral the asset's silhouette: it prints the skin's height and its radius at evenly spaced heights, from the bottom
to the top, as the Swift to paste into `AppleShape` (`designHeight`, `designProfile`).
- The radius at each height is the 90th percentile of the skin's distance from the apple's axis in that band: the
  outer wall, not the stem's cavity or the dimple underneath, whose vertices share the bands near the poles.
- The two ends are set to `POLE` of the widest radius, as in the earlier procedural apple: the spiral's first and last
  slices end in flat faces drawn with the flesh's material, which must stay small.
"""
import math
import sys

from pxr import Usd, UsdGeom

arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(arguments) != 1:
    raise SystemExit("Usage: ... -- <Apple.usdz>")

# Heights sampled, bottom and top included.
SAMPLES = 25
# Radius of the two ends, as a fraction of the widest radius.
POLE = 0.12

stage = Usd.Stage.Open(arguments[0])
skin = next((prim for prim in stage.Traverse() if prim.GetName() == "Skin" and prim.IsA(UsdGeom.Mesh)), None)
if skin is None:
    raise SystemExit(f"{arguments[0]}: no 'Skin' mesh: is it the right file?")
matrix = UsdGeom.XformCache().GetLocalToWorldTransform(skin)
points = [matrix.Transform(point) for point in UsdGeom.Mesh(skin).GetPointsAttr().Get()]

# The axis goes through the middle of the skin's bounds (as the code centres the asset).
low = [min(point[axis] for point in points) for axis in range(3)]
high = [max(point[axis] for point in points) for axis in range(3)]
centre_x, centre_z = (low[0] + high[0]) / 2, (low[2] + high[2]) / 2
height = high[1] - low[1]
band = height / (SAMPLES - 1)

profile = []
for index in range(SAMPLES):
    level = low[1] + index * band
    radii = sorted(math.hypot(point[0] - centre_x, point[2] - centre_z) for point in points
                   if abs(point[1] - level) <= band / 2)
    if not radii:
        raise SystemExit(f"No skin vertex at {level:.4f} m: fewer samples?")
    profile.append(radii[int(0.9 * (len(radii) - 1))])
profile[0] = profile[-1] = POLE * max(profile)

print(f"    static let designHeight: Float = {height:.4f}")
print("    static let designProfile: [Float] = [")
for start in range(0, SAMPLES, 8):
    print("        " + " ".join(f"{radius:.4f}," for radius in profile[start:start + 8]))
print("    ]")
