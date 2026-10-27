"""Makes the ride's cloud from the island's tree: the canopy's low-poly puffs, white instead of green.

Usage (USD's Python API, `pxr`, ships with Blender; Blender itself is not used):
    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
        -P Assets/Blender/ride-sky/make_cloud_asset.py -- \
        Sources/Macrowavers/Resources/FloatingIsland.usdz Sources/Macrowavers/Resources/RideCloud.usdz

The canopy of the island's tree (`Tree/Icosphere_*`, the meshes bound to `Airbrush_Canopy`) is copied as it is,
puff by puff, under one `Cloud` prim: centred on the origin, Y-up, 1 m across at its widest (the app scales each
cloud). Its airbrush material is copied too, as `Airbrush_Cloud`, with a white colour ramp: lilac-grey where a
facet faces the player, white towards the rims, the same grain as the canopy. Re-run it when the tree changes.

The app also takes this material for everything it builds in code (`RideAirbrush`), so it gets translucent
gradients the canopy doesn't have: its opacity runs from `FacingOpacity` (faces seen straight on) to `RimOpacity`
(the rims), by the same grainy factor as the colours, and fades from `BottomOpacity` at `FadeBottom` up to opaque
at `FadeTop` (object space, y), sprayed with the same grain. All opaque by default.
"""
import os
import sys

from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, UsdUtils

arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(arguments) != 2:
    raise SystemExit("Usage: ... -- <FloatingIsland.usdz> <RideCloud.usdz>")
SOURCE, DESTINATION = (os.path.abspath(argument) for argument in arguments)

CANOPY_MATERIAL = "Airbrush_Canopy"
ROOT = Sdf.Path("/root")
MATERIAL = ROOT.AppendChild("_materials").AppendChild("Airbrush_Cloud")
CLOUD = ROOT.AppendChild("Cloud")
# The cloud's ramp (linear sRGB), from the facets facing the player to the rims, and how much the facing facets are
# darkened (the canopy's -1.2 turns them almost black; a cloud keeps them light).
STOPS = [
    ((0.66, 0.68, 0.88), 0.0),
    ((0.84, 0.87, 0.98), 0.3),
    ((0.95, 0.96, 1.00), 0.66),
    ((1.00, 1.00, 1.00), 1.0),
]
EMISSION_BOOST = -0.15

source = Usd.Stage.Open(SOURCE)
source_layer = Sdf.Layer.CreateAnonymous(".usdc")
source_layer.TransferContent(source.Flatten())
source = Usd.Stage.Open(source_layer)

puffs = []
for prim in source.Traverse():
    if not prim.IsA(UsdGeom.Mesh):
        continue
    material = UsdShade.MaterialBindingAPI(prim).GetDirectBinding().GetMaterialPath()
    if material.name == CANOPY_MATERIAL:
        puffs.append(prim)
if not puffs:
    raise SystemExit(f"{SOURCE}: no mesh bound to {CANOPY_MATERIAL}: is it the island?")
canopy_material = UsdShade.MaterialBindingAPI(puffs[0]).GetDirectBinding().GetMaterialPath()

# Where every puff is in the island's (Y-up) space, and the canopy's bounds there.
cache = UsdGeom.XformCache()
worlds = [cache.GetLocalToWorldTransform(prim) for prim in puffs]
corners = [world.Transform(Gf.Vec3d(point)) for prim, world in zip(puffs, worlds)
           for point in UsdGeom.Mesh(prim).GetPointsAttr().Get()]
low = Gf.Vec3d(*(min(corner[axis] for corner in corners) for axis in range(3)))
high = Gf.Vec3d(*(max(corner[axis] for corner in corners) for axis in range(3)))
centre = (low + high) / 2
size = max(high - low)
# Row vectors (USD): island space -> centred on the origin, 1 m wide.
normalise = Gf.Matrix4d().SetTranslate(-centre) * Gf.Matrix4d().SetScale(1 / size)

layer = Sdf.Layer.CreateAnonymous(".usdc")
stage = Usd.Stage.Open(layer)
UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
UsdGeom.SetStageMetersPerUnit(stage, 1)
UsdGeom.Xform.Define(stage, ROOT)
stage.DefinePrim(MATERIAL.GetParentPath(), "Scope")
stage.SetDefaultPrim(stage.GetPrimAtPath(ROOT))

# The material: the canopy's graph (its connections follow it to the new path), recoloured.
if not Sdf.CopySpec(source_layer, canopy_material, layer, MATERIAL):
    raise SystemExit(f"Could not copy {canopy_material}")
material = stage.GetPrimAtPath(MATERIAL)
for index, (colour, position) in enumerate(STOPS):
    material.GetAttribute(f"inputs:Stop{index}Color").Set(Gf.Vec3f(*colour))
    material.GetAttribute(f"inputs:Stop{index}Position").Set(position)
material.GetAttribute("inputs:EmissionBoost").Set(EMISSION_BOOST)


def float_input(name, value):
    attribute = UsdShade.Material(material).CreateInput(name, Sdf.ValueTypeNames.Float)
    attribute.Set(value)
    return attribute


def node(name):
    return UsdShade.Shader(stage.GetPrimAtPath(MATERIAL.AppendChild(name)))


def shader(name, node_id, inputs):
    """A float node of the graph: its inputs are constants, the material's inputs, or other nodes' outputs."""
    new = UsdShade.Shader.Define(stage, MATERIAL.AppendChild(name))
    new.CreateIdAttr(node_id)
    for input_name, (value_type, source) in inputs.items():
        new_input = new.CreateInput(input_name, value_type)
        if isinstance(source, UsdShade.Input):
            new_input.ConnectToSource(source)
        elif isinstance(source, UsdShade.Shader):
            new_input.ConnectToSource(source.ConnectableAPI(), "out")
        else:
            new_input.Set(source)
    new.CreateOutput("out", Sdf.ValueTypeNames.Float)
    return new


FLOAT, FLOAT3, INT = Sdf.ValueTypeNames.Float, Sdf.ValueTypeNames.Float3, Sdf.ValueTypeNames.Int
facing, rim = float_input("FacingOpacity", 1.0), float_input("RimOpacity", 1.0)
bottom = float_input("BottomOpacity", 1.0)
fade_bottom, fade_top = float_input("FadeBottom", 0.0), float_input("FadeTop", 1.0)
by_edge = shader("OpacityByEdge", "ND_mix_float",
                 {"bg": (FLOAT, facing), "fg": (FLOAT, rim), "mix": (FLOAT, node("Factor"))})
height = shader("Height", "ND_extract_vector3", {"in": (FLOAT3, node("Position")), "index": (INT, 1)})
height_t = shader("HeightT", "ND_remap_float",
                  {"in": (FLOAT, height), "inlow": (FLOAT, fade_bottom), "inhigh": (FLOAT, fade_top),
                   "outlow": (FLOAT, 0.0), "outhigh": (FLOAT, 1.0)})
height_grain = shader("HeightPlusGrain", "ND_add_float", {"in1": (FLOAT, height_t), "in2": (FLOAT, node("Grain"))})
height_clamped = shader("HeightClamped", "ND_clamp_float",
                        {"in": (FLOAT, height_grain), "low": (FLOAT, 0.0), "high": (FLOAT, 1.0)})
by_height = shader("OpacityByHeight", "ND_mix_float",
                   {"bg": (FLOAT, bottom), "fg": (FLOAT, 1.0), "mix": (FLOAT, height_clamped)})
opacity = shader("Opacity", "ND_multiply_float", {"in1": (FLOAT, by_edge), "in2": (FLOAT, by_height)})
node("UnlitSurface").GetInput("opacity").ConnectToSource(opacity.ConnectableAPI(), "out")

for prim in Usd.PrimRange(material):
    for attribute in prim.GetAttributes():
        for target in attribute.GetConnections():
            if not target.HasPrefix(MATERIAL):
                raise SystemExit(f"{attribute.GetPath()} still points at {target}")

UsdGeom.Xform.Define(stage, CLOUD)
for index, (prim, world) in enumerate(zip(puffs, worlds)):
    puff = UsdGeom.Xform.Define(stage, CLOUD.AppendChild(f"Puff_{index:02d}"))
    puff.AddTransformOp().Set(world * normalise)
    mesh_path = puff.GetPath().AppendChild("Mesh")
    if not Sdf.CopySpec(source_layer, prim.GetPath(), layer, mesh_path):
        raise SystemExit(f"Could not copy {prim.GetPath()}")
    UsdShade.MaterialBindingAPI.Apply(stage.GetPrimAtPath(mesh_path)).Bind(UsdShade.Material(material))

geometry = os.path.splitext(DESTINATION)[0] + "_build.usdc"
layer.Export(geometry)
if not UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(geometry), DESTINATION):
    raise SystemExit(f"Could not package {DESTINATION}")
os.remove(geometry)
print(f"{len(puffs)} puffs, {tuple(round(value / size, 2) for value in high - low)} m: cloud written to {DESTINATION}")
