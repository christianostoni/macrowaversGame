"""Prepares the floating island for RealityKit, without opening Blender.

Usage:
    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
        -P Assets/Blender/untangle-dragon/make_island_asset.py -- <FloatingIsland.usdc> <output folder>

What it does (and why):
- The source file points to external textures (./textures/*_BaseColor.png) that do not exist: the real
  colours are vertex colours (primvar `Col`), which RealityKit does not draw. The script bakes them into one
  texture per mesh using the existing UVs and rebuilds the PBR material (base colour + roughness).
- Moves the origin to the base of the trunk, at ground level: in RealityKit the tree is the anchor of the
  scene and the dragon circles it with no magic offsets in code.
- Adds empty objects `fruit_01` ... `fruit_06` on the outside of the canopy, found by casting rays at the
  foliage: the code hangs the apples and the pomegranate there (designers can move them in Blender).
- Exports a Y-up USDZ with the textures inside (no external files to forget) and without vertex colours
  (useless after baking, only weight).
"""
import math
import os
import sys

import bpy
from mathutils import Vector

arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(arguments) != 2:
    raise SystemExit("Usage: ... -- <FloatingIsland.usdc> <output folder>")
SOURCE, OUTPUT = (os.path.abspath(argument) for argument in arguments)
os.makedirs(OUTPUT, exist_ok=True)
TEXTURE_FOLDER = os.path.join(OUTPUT, "island_textures")
os.makedirs(TEXTURE_FOLDER, exist_ok=True)

# Baked texture resolution per mesh: the island has many more distinct colours than the rocks and the tree.
RESOLUTION = {"Island": 2048, "Tree": 1024, "FloatingRocks": 512}

# Fruit hang points: (angle in degrees around the trunk, height above the ground in metres).
FRUIT_SPOTS = [(20, 0.78), (95, 0.92), (160, 0.74), (230, 0.88), (290, 0.8), (340, 0.95)]
# Distance of the fruit centre from the foliage surface (half a fruit on the tree, asset metres).
FRUIT_OFFSET = 0.045

# Empty scene, then import (Blender converts to Z-up).
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(filepath=SOURCE, import_materials=False, read_mesh_colors=True)

meshes = {item.name: item for item in bpy.context.scene.objects if item.type == "MESH"}
for name in RESOLUTION:
    if name not in meshes:
        raise SystemExit(f"Missing mesh '{name}' in {SOURCE}")

# --- Applied transforms: every mesh in world coordinates, no parents -----------------------------------
for item in meshes.values():
    matrix = item.matrix_world.copy()
    item.parent = None
    item.matrix_world = matrix
    bpy.context.view_layer.objects.active = item
    for other in bpy.context.scene.objects:
        other.select_set(other == item)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for item in list(bpy.context.scene.objects):
    if item.type != "MESH":
        bpy.data.objects.remove(item)

# --- Origin at the base of the trunk, on the ground ----------------------------------------------------
tree_points = [vertex.co.copy() for vertex in meshes["Tree"].data.vertices]
lowest = min(point.z for point in tree_points)
base = [point for point in tree_points if point.z < lowest + 0.04]
center_x = sum(point.x for point in base) / len(base)
center_y = sum(point.y for point in base) / len(base)
# The trunk sinks into the ground: the origin goes on the island's surface next to the trunk.
nearby = [vertex.co.z for vertex in meshes["Island"].data.vertices
          if math.hypot(vertex.co.x - center_x, vertex.co.y - center_y) < 0.2]
ground = max(nearby) if nearby else lowest
for item in meshes.values():
    for vertex in item.data.vertices:
        vertex.co.x -= center_x
        vertex.co.y -= center_y
        vertex.co.z -= ground
print(f"Origin moved to the tree trunk: ({center_x:.3f}, {center_y:.3f}, {ground:.3f}) in the source file")

# --- Fruit hang points on the outside of the canopy ----------------------------------------------------
bpy.context.view_layer.update()
tree = meshes["Tree"]
fruit_names = []
for index, (degrees, height) in enumerate(FRUIT_SPOTS, start=1):
    angle = math.radians(degrees)
    outward = Vector((math.cos(angle), math.sin(angle), 0))
    # From outside the canopy towards the trunk: the first hit is the foliage surface.
    hit, location, _, _ = tree.ray_cast(outward * 2 + Vector((0, 0, height)), -outward)
    if not hit:
        print(f"Warning: no foliage at {degrees}° / {height} m, fruit_{index:02d} skipped")
        continue
    empty = bpy.data.objects.new(f"fruit_{index:02d}", None)
    empty.location = location + outward * FRUIT_OFFSET - Vector((0, 0, 0.02))
    bpy.context.scene.collection.objects.link(empty)
    fruit_names.append(empty.name)
    print(f"Fruit {empty.name} at {tuple(round(value, 3) for value in empty.location)}")

# --- Baking the vertex colours ------------------------------------------------------------------------
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 1
scene.render.bake.margin = 8

for name, resolution in RESOLUTION.items():
    item = meshes[name]
    data = item.data
    colour = data.color_attributes.get("Col") or (data.color_attributes[0] if data.color_attributes else None)
    if colour is None:
        raise SystemExit(f"Mesh '{name}' has no vertex colours to bake")
    uv = data.uv_layers.get("st") or data.uv_layers.get("UVMap") or data.uv_layers[0]
    uv.name = "st"
    data.uv_layers.active = uv

    image = bpy.data.images.new(f"{name}_BaseColor", resolution, resolution, alpha=False)
    image.colorspace_settings.name = "sRGB"

    # Temporary material: vertex colour -> emission, baked into the active texture.
    material = bpy.data.materials.new(f"{name}_Mat")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    emission = nodes.new("ShaderNodeEmission")
    attribute = nodes.new("ShaderNodeVertexColor")
    attribute.layer_name = colour.name
    links.new(attribute.outputs["Color"], emission.inputs["Color"])
    links.new(emission.outputs["Emission"], output.inputs["Surface"])
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = image
    nodes.active = texture
    data.materials.clear()
    data.materials.append(material)

    for other in scene.objects:
        other.select_set(other == item)
    bpy.context.view_layer.objects.active = item
    bpy.ops.object.bake(type="EMIT", margin=8, use_clear=True)
    image.filepath_raw = os.path.join(TEXTURE_FOLDER, f"{name}_BaseColor.png")
    image.file_format = "PNG"
    image.save()

    # Final material: matte PBR (blends with the real light in mixed reality).
    nodes.remove(emission)
    nodes.remove(attribute)
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    shader.inputs["Roughness"].default_value = 0.9
    shader.inputs["Metallic"].default_value = 0.0
    links.new(texture.outputs["Color"], shader.inputs["Base Color"])
    links.new(shader.outputs["BSDF"], output.inputs["Surface"])

    # The vertex colours are no longer needed: only weight in the file.
    data.color_attributes.remove(colour)
    print(f"Baked {name}: {len(data.polygons)} faces, {resolution}px texture")

# --- Export -------------------------------------------------------------------------------------------
for item in scene.objects:
    item.select_set(item.name in meshes or item.name in fruit_names)
destination = os.path.join(OUTPUT, "FloatingIsland.usdz")
bpy.ops.wm.usd_export(filepath=destination, selected_objects_only=True, export_animation=False,
                      export_materials=True, generate_preview_surface=True, export_mesh_colors=False,
                      export_textures_mode="NEW", overwrite_textures=True,
                      convert_orientation=True, export_global_forward_selection="NEGATIVE_Z",
                      export_global_up_selection="Y", root_prim_path="/FloatingIsland")
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUTPUT, "island.blend"))
print(f"Island asset written to {destination}")
