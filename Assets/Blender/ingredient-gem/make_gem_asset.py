"""Prepares the ingredient gem for RealityKit, without opening Blender.

Usage:
    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
        -P Assets/Blender/ingredient-gem/make_gem_asset.py -- Assets/Blender/ingredient-gem/ingredient_gem.usdc <output folder>

The source is the design team's Blender export (Z-up): a faceted crystal (a stretched icosphere, 26 flat faces,
~1.9 x 1.8 x 3.3 units) with a pale, mostly transparent material, a camera, two area lights and a dome light that
points to an .exr that is not shipped. What the script does, and why:
- Keeps only the crystal and names it `Gem`. The camera and the lights stay out: the room lights the gem.
- Keeps the crystal upright: the source's object rotation only frames it for the render, while in the game the gem
  spins around its long axis, which must be vertical.
- Centres it and scales it to `HEIGHT` (6 cm tall, ~3.5 cm wide: the size of the old 5 cm orb), origin at its
  centre, so it spins on itself and dives into the flask's neck tip first.
- Flat faces: the facets catch the light one by one as it turns.
- A plain placeholder material: the app gives every gem its ingredient's colour, shine and glow in code.
- Exports a Y-up USDZ (rotation on the file root, so the code never overwrites the loaded entity's transform).
"""
import os
import sys

import bpy
from mathutils import Vector

arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(arguments) != 2:
    raise SystemExit("Usage: ... -- <ingredient_gem.usdc> <output folder>")
SOURCE, OUTPUT = (os.path.abspath(argument) for argument in arguments)
os.makedirs(OUTPUT, exist_ok=True)

# Height of the gem in the game (m), along its long axis.
HEIGHT = 0.06

# Empty scene, then import (Blender converts to Z-up). Camera and lights stay out.
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(filepath=SOURCE, import_materials=False, import_cameras=False, import_lights=False)

meshes = [item for item in bpy.context.scene.objects if item.type == "MESH"]
if len(meshes) != 1:
    raise SystemExit(f"{SOURCE}: expected one crystal mesh, found {len(meshes)}: is it the right file?")
gem = meshes[0]

# --- Upright, no parents: the mesh as modelled, without the object's framing rotation -----------------------
gem.parent = None
gem.matrix_world.identity()
for item in list(bpy.context.scene.objects):
    if item is not gem:
        bpy.data.objects.remove(item)
gem.name = "Gem"
gem.data.name = "Gem"

# --- Centred, scaled to HEIGHT, flat faces ------------------------------------------------------------------
points = [vertex.co.copy() for vertex in gem.data.vertices]
low = Vector([min(point[axis] for point in points) for axis in range(3)])
high = Vector([max(point[axis] for point in points) for axis in range(3)])
centre = (low + high) / 2
factor = HEIGHT / (high.z - low.z)
for vertex in gem.data.vertices:
    vertex.co = (vertex.co - centre) * factor
for polygon in gem.data.polygons:
    polygon.use_smooth = False

# --- Placeholder material -----------------------------------------------------------------------------------
material = bpy.data.materials.new("GemCrystal")
material.use_nodes = True
shader = next(node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
shader.inputs["Base Color"].default_value = (0.9, 0.9, 0.9, 1)
shader.inputs["Roughness"].default_value = 0.1
shader.inputs["Metallic"].default_value = 0
shader.inputs["Alpha"].default_value = 0.6
gem.data.materials.clear()
gem.data.materials.append(material)

size = (high - low) * factor
print(f"Gem: {len(gem.data.polygons)} faces, size {tuple(round(value, 4) for value in size)} m")

# --- Export -------------------------------------------------------------------------------------------------
gem.select_set(True)
destination = os.path.join(OUTPUT, "IngredientGem.usdz")
bpy.ops.wm.usd_export(filepath=destination, selected_objects_only=True, export_animation=False,
                      export_materials=True, generate_preview_surface=True, export_mesh_colors=False,
                      export_cameras=False, export_lights=False, export_subdivision="IGNORE",
                      convert_orientation=True, export_global_forward_selection="NEGATIVE_Z",
                      export_global_up_selection="Y", root_prim_path="/IngredientGem")
print(f"Gem asset written to {destination}")
