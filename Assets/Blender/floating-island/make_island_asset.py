"""Prepares the design team's floating island with its tree for RealityKit, keeping its materials.

Usage (USD's Python API, `pxr`, ships with Blender; Blender itself is not used):
    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
        -P Assets/Blender/floating-island/make_island_asset.py -- \
        Assets/Blender/floating-island/ilha_rcp.usdz <output folder>

The source (`ilha_RCP_v2.usdz`, prepared in Reality Composer Pro) is the island with its tree (Z-up under a root
that turns it Y-up, ~14 m wide, 64 meshes, a sun and a camera), with Reality Composer Pro shader graph materials
(unlit "airbrush" colour ramps), several per mesh through face subsets. Blender cannot read those materials, so
the script edits the USD directly and leaves every mesh, face subset and material as it is. The app expects the
same asset contract as before, so its position, scale, the dragon's orbit, the fruit and the floor occluder stay
as they were:
- Three parts the code looks for: `Island` (grass, rock, roots, stones, bushes, flowers: the collider that spins
  the island is built from its bounds), `Tree` (trunk and canopy, the source's `Vert_001`) and `FloatingRocks`
  (the `Island_Debris_*` and `Island_Floater_*` pieces, which bob on their own). The sun, the camera and an empty
  mesh are removed.
- Origin at the base of the trunk, on the grass, and a scale that makes the tree `TARGET_TREE_HEIGHT` metres tall
  from the bottom of its trunk to the top of its canopy (island ~2.5 m wide): both on the file's root, after its
  Z-up → Y-up turn. The tree alone sets the scale: a designer reshaping the rock or the grass must not resize the
  whole island.
- Empty prims `fruit_01` ... `fruit_15` on the outside of the canopy, found by casting rays at the foliage: the
  code hangs the fruit there, in order (one of each kind, three times over). The first seven are where the design
  team placed them, in front of the player (`FRONT_RAYS`), so one of each kind is in front.
- The source's meshes are already double-sided (RealityKit draws their inner walls), so no faces are turned.
"""
import math
import os
import sys

from pxr import Gf, Sdf, Usd, UsdGeom, UsdUtils

arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(arguments) != 2:
    raise SystemExit("Usage: ... -- <ilha_rcp.usdz> <output folder>")
SOURCE, OUTPUT = (os.path.abspath(argument) for argument in arguments)
os.makedirs(OUTPUT, exist_ok=True)

# Height of the tree, bottom of the trunk to top of the canopy, in metres: the scale the code is tuned for.
TARGET_TREE_HEIGHT = 1.8415
# Fruit hang points. The first ones where the design team circled them on a picture of the tree seen from the
# player's seat (2026-11-06): rays from that viewpoint (`FRONT_VIEW`, game coordinates, metres, from the base of the
# trunk) through each circle (`FRONT_RAYS`, directions), in the fruit's order (`OrchardViewModel.kinds`, one of each
# kind in turn): the first foliage each ray meets. The others out of the player's sight from that seat, among spots
# sampled all round the canopy (angle in
# degrees around it, every `SAMPLE_STEP`; height as a fraction of it, 0 = its bottom), each as far from the ones
# already picked as it can be, never closer than `FRUIT_GAP` (metres, game scale).
FRUIT_COUNT = 15
FRONT_VIEW = (0.574, 0.947, 2.822)
FRONT_RAYS = [
    (-0.2014, 0.1035, -0.974),   # apple: the middle
    (-0.4395, 0.1403, -0.8872),  # pomegranate: left
    (-0.0381, 0.1363, -0.9899),  # banana: right
    (-0.3125, 0.2203, -0.924),   # orange: top left
    (-0.3803, 0.0657, -0.9225),  # pineapple: low on the left
    (-0.0584, 0.2267, -0.9722),  # apple: top right
    (-0.3197, -0.0177, -0.9474),  # pomegranate: bottom
]
SAMPLE_STEP = 6
SAMPLE_HEIGHTS = (0.26, 0.32, 0.38, 0.44, 0.5)
FRUIT_GAP = 0.24
# Distance of the fruit centre from the foliage surface, and how far below the hit it hangs (metres, game scale).
FRUIT_OFFSET = 0.045
FRUIT_DROP = 0.02
ROOT = Sdf.Path("/root")
GRASS_GROUP = ROOT.AppendChild("Island_GrassTop_001")
TREE_GROUP = ROOT.AppendChild("Vert_001")
CANOPY_MATERIAL = "Airbrush_Canopy"

layer = Sdf.Layer.CreateAnonymous(".usdc")
layer.TransferContent(Usd.Stage.Open(SOURCE).Flatten())
stage = Usd.Stage.Open(layer)
for path in (GRASS_GROUP, TREE_GROUP):
    if not stage.GetPrimAtPath(path):
        raise SystemExit(f"{SOURCE}: no {path}: is it the right file?")


def mesh_points(prim):
    """Points of a mesh in the root's own space (Z-up, before the root's Y-up turn)."""
    to_root = UsdGeom.Xformable(prim).ComputeLocalToWorldTransform(Usd.TimeCode.Default()) \
        * UsdGeom.Xformable(stage.GetPrimAtPath(ROOT)).ComputeLocalToWorldTransform(Usd.TimeCode.Default()).GetInverse()
    return [to_root.Transform(Gf.Vec3d(point)) for point in (UsdGeom.Mesh(prim).GetPointsAttr().Get() or [])]


def meshes_under(path):
    return [prim for prim in Usd.PrimRange(stage.GetPrimAtPath(path)) if prim.IsA(UsdGeom.Mesh)]


# --- The parts ------------------------------------------------------------------------------------------------
edit = Sdf.BatchNamespaceEdit()
removed = []
for prim in stage.GetPrimAtPath(ROOT).GetChildren():
    meshes = meshes_under(prim.GetPath())
    has_light_or_camera = any(item.IsA(UsdGeom.Camera) or item.GetTypeName().endswith("Light")
                              for item in Usd.PrimRange(prim))
    if has_light_or_camera or (prim.GetName() != "_materials" and meshes and not any(mesh_points(m) for m in meshes)):
        edit.Add(prim.GetPath(), Sdf.Path.emptyPath)
        removed.append(prim.GetName())
# Floating pieces leave the grass group for their own; loose stones on the ground join the island.
rocks = ROOT.AppendChild("FloatingRocks")
UsdGeom.Xform.Define(stage, rocks)
for prim in stage.GetPrimAtPath(GRASS_GROUP).GetChildren():
    if prim.GetName().startswith(("Island_Debris", "Island_Floater")):
        edit.Add(prim.GetPath(), rocks.AppendChild(prim.GetName()))
for prim in stage.GetPrimAtPath(ROOT).GetChildren():
    if prim.GetName().startswith("Icosphere") and prim.GetName() not in removed:
        edit.Add(prim.GetPath(), GRASS_GROUP.AppendChild(prim.GetName()))
if not layer.Apply(edit):
    raise SystemExit("Could not regroup the island's parts")
rename = Sdf.BatchNamespaceEdit()
rename.Add(GRASS_GROUP, ROOT.AppendChild("Island"))
rename.Add(TREE_GROUP, ROOT.AppendChild("Tree"))
if not layer.Apply(rename):
    raise SystemExit("Could not rename the island's parts")
print(f"Removed: {removed}")
for name in ("Island", "Tree", "FloatingRocks"):
    print(f"{name}: {len(meshes_under(ROOT.AppendChild(name)))} meshes")

# --- Origin at the base of the trunk, on the grass; tree at its real height --------------------------------
tree_points = [point for prim in meshes_under(ROOT.AppendChild("Tree")) for point in mesh_points(prim)]
lowest = min(point[2] for point in tree_points)
base = [point for point in tree_points if point[2] < lowest + 0.3]
centre_x = sum(point[0] for point in base) / len(base)
centre_y = sum(point[1] for point in base) / len(base)
grass = next(prim for prim in meshes_under(ROOT.AppendChild("Island")) if prim.GetName().startswith("Island_GrassTop"))
nearby = [point[2] for point in mesh_points(grass) if math.hypot(point[0] - centre_x, point[1] - centre_y) < 1.5]
ground = max(nearby) if nearby else lowest
scale = TARGET_TREE_HEIGHT / (max(point[2] for point in tree_points) - lowest)
origin = Gf.Vec3d(centre_x, centre_y, ground)
island_points = [point for prim in meshes_under(ROOT.AppendChild("Island")) for point in mesh_points(prim)]
width = max(max(p[axis] for p in island_points) - min(p[axis] for p in island_points) for axis in (0, 1))
print(f"Origin moved to the trunk {tuple(round(value, 3) for value in origin)}, scale {scale:.4f} "
      f"(tree {TARGET_TREE_HEIGHT} m, island {width * scale:.2f} m wide)")

# --- Fruit hang points on the outside of the canopy (before the root moves: same space as the points) -------
canopy = []
for prim in meshes_under(ROOT.AppendChild("Tree")):
    binding = prim.GetRelationship("material:binding")
    if not binding or not any(target.name == CANOPY_MATERIAL for target in binding.GetTargets()):
        continue
    points = mesh_points(prim)
    counts = UsdGeom.Mesh(prim).GetFaceVertexCountsAttr().Get()
    indices = UsdGeom.Mesh(prim).GetFaceVertexIndicesAttr().Get()
    start = 0
    for count in counts:
        face = [points[indices[start + corner]] for corner in range(count)]
        canopy += [(face[0], face[corner], face[corner + 1]) for corner in range(1, count - 1)]
        start += count
if not canopy:
    raise SystemExit(f"No canopy found (meshes with {CANOPY_MATERIAL})")
corners = [corner for triangle in canopy for corner in triangle]
canopy_centre = sum(corners, Gf.Vec3d()) / len(corners)
canopy_bottom = min(point[2] for point in corners)
canopy_top = max(point[2] for point in corners)
canopy_reach = max(math.hypot(point[0] - canopy_centre[0], point[1] - canopy_centre[1]) for point in corners)


def ray_hit(start, direction):
    """Closest triangle of the canopy along the ray (Möller–Trumbore), or None."""
    best = None
    for a, b, c in canopy:
        edge1, edge2 = b - a, c - a
        cross = Gf.Cross(direction, edge2)
        determinant = Gf.Dot(edge1, cross)
        if abs(determinant) < 1e-12:
            continue
        offset = start - a
        u = Gf.Dot(offset, cross) / determinant
        if u < 0 or u > 1:
            continue
        q = Gf.Cross(offset, edge1)
        v = Gf.Dot(direction, q) / determinant
        if v < 0 or u + v > 1:
            continue
        distance = Gf.Dot(edge2, q) / determinant
        if distance > 0 and (best is None or distance < best):
            best = distance
    return None if best is None else start + direction * best


def foliage_hit(degrees, fraction):
    """First point of the foliage seen from outside the canopy, towards its centre; None between the blobs (or deep
    inside them)."""
    angle = math.radians(degrees)
    outward = Gf.Vec3d(math.cos(angle), math.sin(angle), 0)
    height = canopy_bottom + fraction * (canopy_top - canopy_bottom)
    start = Gf.Vec3d(canopy_centre[0], canopy_centre[1], height) + outward * (canopy_reach + 0.5 / scale)
    hit = ray_hit(start, -outward)
    # Through a gap between the blobs, the first foliage is deep inside the canopy, hidden: look elsewhere.
    if hit is None or math.hypot(hit[0] - canopy_centre[0], hit[1] - canopy_centre[1]) < 0.5 * canopy_reach:
        return None
    return hit, outward


def hang_point(found):
    location, outward = found
    return location + outward * (FRUIT_OFFSET / scale) - Gf.Vec3d(0, 0, FRUIT_DROP / scale)


samples = []  # (degrees, height fraction, hang point)
for degrees in range(0, 360, SAMPLE_STEP):
    for fraction in SAMPLE_HEIGHTS:
        found = foliage_hit(degrees, fraction)
        if found:
            samples.append((degrees, fraction, hang_point(found)))


def gap(point, picked):
    return min(((point - other).GetLength() * scale for other in picked), default=math.inf)


def pick(candidates, picked, count, first):
    """`count` more spots from `candidates`: the first by `first` (if nothing is picked yet), then each the farthest
    from all the picked."""
    picked = list(picked)
    start = len(picked)
    for _ in range(count):
        usable = [spot for spot in candidates if gap(spot[2], picked) >= FRUIT_GAP]
        if not usable:
            raise SystemExit(f"Only {len(picked)} fruit spots {FRUIT_GAP} m apart: lower FRUIT_GAP")
        best = min(usable, key=first) if not picked else max(usable, key=lambda spot: gap(spot[2], picked))
        picked.append(best[2])
    return picked[start:]




def to_source(game):
    """A game point (Y-up, metres from the base of the trunk) in the source's Z-up units."""
    return origin + Gf.Vec3d(game[0], -game[2], game[1]) / scale


view = to_source(FRONT_VIEW)
spots = []
for index, ray in enumerate(FRONT_RAYS, start=1):
    aim = (to_source(Gf.Vec3d(*FRONT_VIEW) + Gf.Vec3d(*ray)) - view).GetNormalized()
    # A circle on the canopy's outline may miss it by a hair: nudge the ray, a little more each ring, until it meets
    # the foliage.
    side = Gf.Cross(aim, Gf.Vec3d(0, 0, 1)).GetNormalized()
    up = Gf.Cross(side, aim)
    nudges = [(0, 0)] + [(radius * math.cos(turn * math.pi / 6), radius * math.sin(turn * math.pi / 6))
                         for radius in (0.005, 0.01, 0.02, 0.035) for turn in range(12)]
    hit = None
    for across, rise in nudges:
        direction = (aim + side * across + up * rise).GetNormalized()
        hit = ray_hit(view, direction)
        if hit is not None:
            break
    if hit is None:
        raise SystemExit(f"fruit_{index:02d}: its ray from the player's seat misses the canopy")
    spots.append(hang_point((hit, -direction)))


def seen_from_front(point):
    """Nothing of the canopy between the player's seat and `point`."""
    towards = point - view
    hit = ray_hit(view, towards.GetNormalized())
    return hit is None or (hit - view).GetLength() >= towards.GetLength() - 0.01 / scale


# The others where the player doesn't see them from the seat: the front is as the design team drew it.
hidden = [spot for spot in samples if not seen_from_front(spot[2])]
spots += pick(hidden, spots, FRUIT_COUNT - len(FRONT_RAYS), first=None)
for index, position in enumerate(spots, start=1):
    fruit = UsdGeom.Xform.Define(stage, ROOT.AppendChild(f"fruit_{index:02d}"))
    fruit.AddTranslateOp().Set(position)
    game = (position - origin) * scale
    print(f"fruit_{index:02d} at {tuple(round(value, 3) for value in (game[0], game[2], -game[1]))} (game, Y-up)")

# --- The root: Z-up → Y-up turn, then the island's scale and the trunk at the origin -------------------------
root = UsdGeom.Xformable(stage.GetPrimAtPath(ROOT))
turn = root.GetOrderedXformOps()
root.ClearXformOpOrder()
size = root.AddScaleOp(opSuffix="tree")
size.Set(Gf.Vec3f(scale, scale, scale))
move = root.AddTranslateOp(opSuffix="trunk")
move.Set(-origin)
root.SetXformOpOrder(turn + [size, move])

stage.GetRootLayer().defaultPrim = ROOT.name
geometry = os.path.join(OUTPUT, "FloatingIsland_build.usdc")
stage.GetRootLayer().Export(geometry)
destination = os.path.join(OUTPUT, "FloatingIsland.usdz")
if not UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(geometry), destination):
    raise SystemExit(f"Could not package {destination}")
os.remove(geometry)
print(f"Island asset written to {destination}")
