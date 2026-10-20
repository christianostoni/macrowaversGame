"""Prepares the elixir's flask for RealityKit, without opening Blender.

Usage:
    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
        -P Assets/Blender/elixir-flask/make_flask_asset.py -- Assets/Blender/elixir-flask/elixir_flask.usdc <output folder>

The source is the design team's Blender export (Z-up, real size: a round flask ~21 cm wide and ~30 cm tall with
its cork, tilted by 20°). What the script does, and why:
- Keeps the three parts the code animates and names them `Glass`, `Liquid` and `Cork`. Drops the camera, the dome
  light (it points to a 4K .exr that is not shipped) and a stray bubble sphere 69 cm away from the flask.
- Applies the Catmull-Clark subdivision of the glass and the liquid: USD only flags it, RealityKit draws the
  control cage, so the round flask would look faceted.
- Decimates the cork (~5.9k faces for a 6 cm cork) and gives it a plain cork colour: its texture
  (`corkboard3b-albedo.png`) is not shipped.
- Plain placeholder materials: the source's glass and bubble materials are empty (Blender glass nodes do not
  export to USD) and its liquid is fully transparent. The app replaces the glass and the liquid materials in code
  anyway (transparency, colour and glow change while the elixir is brewed).
- Origins: the flask's at the centre of its round body (the file's origin); the liquid's at its bottom, so scaling
  it along the vertical axis raises its level; the cork's at its centre, so it spins on itself when it pops.
- Two empty objects mark the neck: `neck_top` (top of the cork) and `neck_base` (bottom of the cork). The
  ingredients dive in along that axis.
- Exports a Y-up USDZ (rotation on the file root, so the code never overwrites the loaded entity's transform).
"""
import os
import sys

import bpy
from mathutils import Vector

arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(arguments) != 2:
    raise SystemExit("Usage: ... -- <elixir_flask.usdc> <output folder>")
SOURCE, OUTPUT = (os.path.abspath(argument) for argument in arguments)
os.makedirs(OUTPUT, exist_ok=True)

# Source material -> part of the flask.
PARTS = {"glass_outside": "Glass", "liquid": "Liquid", "Material_001": "Cork"}
# Subdivision levels applied (one level is smooth enough at ~15 cm, and keeps the glass light: it is transparent).
SUBDIVISION = {"Glass": 1, "Liquid": 1}
# Faces the cork keeps.
CORK_FACES = 800
# Placeholder materials: base colour, roughness, opacity, emission.
MATERIALS = {
    "Glass": ((0.86, 0.93, 1.0), 0.05, 0.25, None),
    "Liquid": ((0.3, 0.6, 1.0), 0.15, 0.85, (0.25, 0.55, 1.0)),
    "Cork": ((0.72, 0.53, 0.34), 0.9, 1.0, None),
}


def select(objects, active=None):
    bpy.ops.object.select_all(action="DESELECT")
    for item in objects:
        item.select_set(True)
    bpy.context.view_layer.objects.active = active or objects[0]


def bounds(item):
    points = [item.matrix_world @ vertex.co for vertex in item.data.vertices]
    return (Vector([min(point[axis] for point in points) for axis in range(3)]),
            Vector([max(point[axis] for point in points) for axis in range(3)]))


def make_material(name):
    color, roughness, opacity, emission = MATERIALS[name]
    material = bpy.data.materials.new(f"Flask{name}")
    material.use_nodes = True
    shader = next(node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = 0
    shader.inputs["Alpha"].default_value = opacity
    if emission:
        shader.inputs["Emission Color"].default_value = (*emission, 1)
        shader.inputs["Emission Strength"].default_value = 1
    return material


# Empty scene, then import (Blender converts to Z-up). Camera and lights stay out.
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(filepath=SOURCE, import_materials=True, import_cameras=False, import_lights=False)

parts = {}
for item in [item for item in bpy.context.scene.objects if item.type == "MESH"]:
    names = [material.name for material in item.data.materials if material]
    part = next((PARTS[name] for name in names if name in PARTS), None)
    if part is None or part in parts:
        print(f"Dropped: {item.name} ({names})")
        bpy.data.objects.remove(item)
        continue
    parts[part] = item
if set(parts) != set(PARTS.values()):
    raise SystemExit(f"{SOURCE}: expected glass, liquid and cork, found {sorted(parts)}: is it the right file?")

# --- World transforms applied, no parents ----------------------------------------------------------------
for item in parts.values():
    matrix = item.matrix_world.copy()
    item.parent = None
    item.matrix_world = matrix
for item in list(bpy.context.scene.objects):
    if item not in parts.values():
        bpy.data.objects.remove(item)
for name, item in parts.items():
    item.name = name
    item.data.name = name
    select([item])
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# --- Subdivision applied, cork decimated --------------------------------------------------------------
for name, levels in SUBDIVISION.items():
    item = parts[name]
    select([item])
    modifier = item.modifiers.new("Subdivision", "SUBSURF")
    modifier.levels = levels
    modifier.render_levels = levels
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.ops.object.shade_smooth()
cork = parts["Cork"]
select([cork])
modifier = cork.modifiers.new("Decimate", "DECIMATE")
modifier.ratio = min(1, CORK_FACES / max(len(cork.data.polygons), 1))
bpy.ops.object.modifier_apply(modifier=modifier.name)
bpy.ops.object.shade_smooth()

# --- Materials ------------------------------------------------------------------------------------------
for name, item in parts.items():
    item.data.materials.clear()
    item.data.materials.append(make_material(name))

# --- Origins: liquid at its bottom, cork at its centre ----------------------------------------------------
liquid_low, liquid_high = bounds(parts["Liquid"])
cork_low, cork_high = bounds(cork)
pivots = {
    "Liquid": Vector(((liquid_low.x + liquid_high.x) / 2, (liquid_low.y + liquid_high.y) / 2, liquid_low.z)),
    "Cork": (cork_low + cork_high) / 2,
}
for name, pivot in pivots.items():
    item = parts[name]
    for vertex in item.data.vertices:
        vertex.co -= pivot
    item.location = pivot
# The new locations reach `matrix_world` only after an update.
bpy.context.view_layer.update()

# --- Neck axis: along the cork, from its bottom to its top ------------------------------------------------
# The neck grows out of the centre of the round body (the file's origin), tilted: the axis goes from there
# through the cork's centre; the cork's vertices give its two ends along it.
cork_points = [cork.matrix_world @ vertex.co for vertex in cork.data.vertices]
centre = sum(cork_points, Vector()) / len(cork_points)
tilt_axis = centre.normalized()
along = [(point - centre).dot(tilt_axis) for point in cork_points]
for name, offset in (("neck_top", max(along)), ("neck_base", min(along))):
    empty = bpy.data.objects.new(name, None)
    empty.location = centre + tilt_axis * offset
    bpy.context.scene.collection.objects.link(empty)
    print(f"{name} at {tuple(round(value, 4) for value in empty.location)}")

for name, item in parts.items():
    low, high = bounds(item)
    print(f"{name}: {len(item.data.polygons)} faces, size {tuple(round(value, 3) for value in high - low)}, "
          f"from {tuple(round(value, 3) for value in low)} to {tuple(round(value, 3) for value in high)}")

# --- Export -------------------------------------------------------------------------------------------
for item in bpy.context.scene.objects:
    item.select_set(True)
destination = os.path.join(OUTPUT, "ElixirFlask.usdz")
bpy.ops.wm.usd_export(filepath=destination, selected_objects_only=True, export_animation=False,
                      export_materials=True, generate_preview_surface=True, export_mesh_colors=False,
                      export_cameras=False, export_lights=False, export_subdivision="IGNORE",
                      convert_orientation=True, export_global_forward_selection="NEGATIVE_Z",
                      export_global_up_selection="Y", root_prim_path="/ElixirFlask")
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUTPUT, "flask.blend"))
print(f"Flask asset written to {destination}")
