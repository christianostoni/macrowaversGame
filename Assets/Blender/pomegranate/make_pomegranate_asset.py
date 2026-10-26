"""Prepares the design team's pomegranate for RealityKit, keeping its materials.

Usage:
    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
        -P Assets/Blender/pomegranate/make_pomegranate_asset.py -- \
        Assets/Blender/pomegranate/pomegranate_rcp.usdz <output folder>

The source (`pomegranate_RCP.usdz`, prepared in Reality Composer Pro) is a pomegranate at real size (16 cm wide),
centred on the origin and already cut in two along x = 0: `RightSkin` and `RightFlesh` (x ≥ 0), `LeftSkin` and
`LeftFlesh` (x ≤ 0; the flesh is the cut face), a `Crown` on top and `Seeds`, one mesh with 80 seeds packed
inside. Its materials (`Airbrush_Skin`, `Airbrush_Flesh`, `Airbrush_Seeds`) are Reality Composer Pro shader graphs
that Blender cannot read. What the script does, and why:
- Groups the halves for the code, which opens them like a book: `RightHalf` (right skin and flesh, and the crown)
  and `LeftHalf` (left skin and flesh), both with their origin at the centre of the fruit.
- Splits `Seeds` into one object per seed, `Seed_00` ... `Seed_NN`, each with its origin at its centre: the seeds
  burst out of the open fruit and the player drags them one by one.
- Exports the geometry only (Y-up, under `/root`, the materials' own paths), then USD (`pxr`) copies the
  materials from the source unchanged and binds each mesh to the one it had (every seed to `Airbrush_Seeds`).
"""
import os
import sys

import bpy
from mathutils import Matrix, Vector
from pxr import Sdf, Usd, UsdGeom, UsdShade, UsdUtils

arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(arguments) != 2:
    raise SystemExit("Usage: ... -- <pomegranate_rcp.usdz> <output folder>")
SOURCE, OUTPUT = (os.path.abspath(argument) for argument in arguments)
os.makedirs(OUTPUT, exist_ok=True)

# Where the source keeps its materials (Reality Composer Pro shader graphs).
MATERIALS = Sdf.Path("/root/_materials")
HALVES = {"RightHalf": ("RightSkin", "RightFlesh", "Crown"), "LeftHalf": ("LeftSkin", "LeftFlesh")}

# Materials imported only for their names: Blender cannot read the shader graphs, USD copies them at the end.
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(filepath=SOURCE, import_materials=True, import_cameras=False, import_lights=False)
scene = bpy.context.scene

# --- World transforms baked into the vertices, no parents ---------------------------------------------------
meshes = {item.name: item for item in scene.objects if item.type == "MESH"}
missing = [name for names in HALVES.values() for name in names if name not in meshes] + \
    ([] if "Seeds" in meshes else ["Seeds"])
if missing:
    raise SystemExit(f"{SOURCE}: missing {missing}: is it the right file?")
materials = {name: item.data.materials[0].name for name, item in meshes.items() if item.data.materials}
for item in meshes.values():
    matrix = item.matrix_world.copy()
    source = item.data
    item.data = source.copy()
    item.data.transform(matrix)
    # The source's mesh goes, or it keeps the name and the copy exports as `LeftFlesh_001`.
    if source.users == 0:
        bpy.data.meshes.remove(source)
for item in list(scene.objects):
    if item.type != "MESH":
        bpy.data.objects.remove(item)
for item in meshes.values():
    item.parent = None
    item.matrix_world = Matrix.Identity(4)
    item.data.name = item.name

# --- One object per seed, origin at its centre -----------------------------------------------------------------
seeds_source = meshes["Seeds"]
bpy.ops.object.select_all(action="DESELECT")
seeds_source.select_set(True)
bpy.context.view_layer.objects.active = seeds_source
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.separate(type="LOOSE")
bpy.ops.object.mode_set(mode="OBJECT")
seeds = [item for item in scene.objects if item.type == "MESH" and item.name.startswith("Seeds")]


def centre(item):
    points = [vertex.co for vertex in item.data.vertices]
    return sum(points, Vector()) / len(points)


# Numbered from the top down, so the names do not depend on Blender's separation order.
seeds.sort(key=lambda item: (-round(centre(item).z, 3), round(centre(item).x, 3), round(centre(item).y, 3)))
for index, seed in enumerate(seeds):
    point = centre(seed)
    for vertex in seed.data.vertices:
        vertex.co -= point
    seed.location = point
    seed.name = seed.data.name = f"Seed_{index:02d}"
    materials[seed.name] = materials["Seeds"]
seed_group = bpy.data.objects.new("Seeds", None)
scene.collection.objects.link(seed_group)
for seed in seeds:
    seed.parent = seed_group
print(f"{len(seeds)} seeds")

# --- The two halves, origin at the centre of the fruit -------------------------------------------------------
for name, parts in HALVES.items():
    half = bpy.data.objects.new(name, None)
    scene.collection.objects.link(half)
    for part in parts:
        meshes[part].parent = half
    print(f"{name}: {', '.join(parts)}")

# --- Export: the geometry from Blender, the materials from the source ------------------------------------------
bindings = {item.data.name: materials[item.name] for item in scene.objects if item.type == "MESH"}
for item in scene.objects:
    if item.type == "MESH":
        item.data.materials.clear()
    item.select_set(True)
geometry = os.path.join(OUTPUT, "Pomegranate_geometry.usdc")
bpy.ops.wm.usd_export(filepath=geometry, selected_objects_only=True, export_animation=False,
                      export_materials=False, export_mesh_colors=False,
                      export_cameras=False, export_lights=False, export_subdivision="IGNORE",
                      convert_orientation=True, export_global_forward_selection="NEGATIVE_Z",
                      export_global_up_selection="Y", root_prim_path="/root")
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUTPUT, "pomegranate.blend"))

# The stage is kept: a layer handle from a stage already released is expired.
source_stage = Usd.Stage.Open(SOURCE)
source_layer = source_stage.GetRootLayer()
if not source_layer.GetPrimAtPath(MATERIALS):
    raise SystemExit(f"{SOURCE}: no {MATERIALS}: is it the right file?")
stage = Usd.Stage.Open(geometry)
stage.DefinePrim(MATERIALS, "Scope")
for material in source_layer.GetPrimAtPath(MATERIALS).nameChildren:
    if not Sdf.CopySpec(source_layer, material.path, stage.GetRootLayer(), material.path):
        raise SystemExit(f"Could not copy {material.path}")
bound = {}
for prim in stage.Traverse():
    if not prim.IsA(UsdGeom.Mesh):
        continue
    name = bindings.get(prim.GetName())
    material = UsdShade.Material(stage.GetPrimAtPath(MATERIALS.AppendChild(name))) if name else None
    if not material:
        raise SystemExit(f"No material for {prim.GetPath()} ({name})")
    UsdShade.MaterialBindingAPI.Apply(prim).Bind(material)
    bound[name] = bound.get(name, 0) + 1
stage.GetRootLayer().Save()
print(f"Bound: {bound}")

destination = os.path.join(OUTPUT, "Pomegranate.usdz")
if not UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(geometry), destination):
    raise SystemExit(f"Could not package {destination}")
os.remove(geometry)
print(f"Pomegranate written to {destination}")
