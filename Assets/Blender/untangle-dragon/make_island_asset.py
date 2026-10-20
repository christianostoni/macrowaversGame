"""Prepares the floating island with its tree for RealityKit, without opening Blender.

Usage:
    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
        -P Assets/Blender/untangle-dragon/make_island_asset.py -- <island source .usdc> <output folder>

The source is the design team's raw Blender export (Z-up, ~14 m wide, ~90 loose meshes, a camera, a sun and a
dome light). The app expects the same asset contract as before, so the code needs no magic numbers:
- Keeps only the meshes and joins them into the three parts the code looks for: `Island` (grass, rock, roots,
  stones, bushes, flowers: the collider that spins the island is built from its bounds), `Tree` (trunk, branch
  and canopy) and `FloatingRocks` (the debris and small floating islands, which bob on their own). Fewer
  entities and draw calls than ~90 meshes.
- Moves the origin to the base of the trunk, on the grass: the dragon circles it with no offsets in code.
- Scales it so the tree is `TARGET_TREE_HEIGHT` metres tall, from the bottom of its trunk to the top of its
  canopy (island ~2.5 m wide): the scale of the asset the code is tuned for, so `IslandPlacement.standard`, the
  dragon's orbit, the fruit and the floor occluder stay as they were. The tree alone, not the island's width nor
  the grass: a designer reshaping the rock or the grass must not resize the whole island.
- Adds empty objects `fruit_01` ... `fruit_06` on the outside of the canopy, found by casting rays at the
  foliage: the code hangs the fruit there (designers can move them in Blender).
- Turns inside-out meshes the right way: the source's rock body (`Island_RockBody`) has its faces wound
  inwards. Blender draws both sides so it looks fine there, but RealityKit culls back faces: the rock looked
  hollow, its far inner walls showing through. Any closed mesh (`MAX_OPEN_EDGES`) with a negative signed volume
  gets its faces recalculated outwards. Open meshes (petals, grass) are left alone: their volume's sign only
  depends on where the origin is.
- The colours are plain material colours (no textures, no vertex colours): they are exported as
  UsdPreviewSurface, matte (roughness 0.85), the tree's materials get readable names.
- Exports a Y-up USDZ (rotation on the file root, so the code never overwrites the loaded entity's transform).
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(arguments) != 2:
    raise SystemExit("Usage: ... -- <island source .usdc> <output folder>")
SOURCE, OUTPUT = (os.path.abspath(argument) for argument in arguments)
os.makedirs(OUTPUT, exist_ok=True)

# Height of the tree, bottom of the trunk to top of the canopy, in metres: the scale the code is tuned for
# (island ~2.5 m wide).
TARGET_TREE_HEIGHT = 1.8415
# Fruit hang points: (angle in degrees around the canopy, height as a fraction of the canopy, 0 = its bottom).
FRUIT_SPOTS = [(20, 0.3), (95, 0.42), (160, 0.26), (230, 0.38), (290, 0.32), (340, 0.45)]
# Distance of the fruit centre from the foliage surface (half a fruit on the tree, metres after scaling).
FRUIT_OFFSET = 0.045
# Readable names for the source's anonymous materials.
MATERIAL_NAMES = {"Material_002": "Tree_Bark", "Material_003": "Tree_Leaves"}
ROUGHNESS = 0.85
# Share of open edges (used by one face only) up to which a mesh counts as closed: the rock body has 1.7 %, the
# flowers' petals 40 %.
MAX_OPEN_EDGES = 0.05


def part_of(item):
    """Which of the three parts a source mesh belongs to (by its name and its parent before flattening)."""
    names = [item.name]
    parent = item.parent
    while parent is not None:
        names.append(parent.name)
        parent = parent.parent
    # `Vert` is the tree; `Island_Root_007` is a branch on its trunk (bark material, above the grass).
    if any(name.startswith("Vert") for name in names) or item.name.startswith("Island_Root_007"):
        return "Tree"
    if item.name.startswith(("Island_Debris", "Island_Floater")):
        return "FloatingRocks"
    return "Island"


# Empty scene, then import (Blender converts to Z-up). Camera and lights stay out: the room lights the island.
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(filepath=SOURCE, import_materials=True, import_cameras=False, import_lights=False)

meshes = [item for item in bpy.context.scene.objects if item.type == "MESH" and len(item.data.vertices) > 0]
# Keyed by the object itself: joining renames them.
parts = {item: part_of(item) for item in meshes}
# The grass alone tells where the ground is next to the trunk.
grass = next((item for item in meshes if item.name.startswith("Island_GrassTop")), None)
if grass is None or not any(part == "Tree" for part in parts.values()):
    raise SystemExit(f"{SOURCE} has no Island_GrassTop or no tree (Vert): is it the right file?")

# --- Applied transforms: every mesh in world coordinates, no parents -----------------------------------
for item in meshes:
    matrix = item.matrix_world.copy()
    item.parent = None
    item.matrix_world = matrix
for item in meshes:
    bpy.context.view_layer.objects.active = item
    for other in bpy.context.scene.objects:
        other.select_set(other == item)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for item in list(bpy.context.scene.objects):
    if item not in meshes:
        bpy.data.objects.remove(item)

# --- Faces wound inwards -> outwards ---------------------------------------------------------------------
for item in meshes:
    mesh = bmesh.new()
    mesh.from_mesh(item.data)
    open_edges = sum(1 for edge in mesh.edges if len(edge.link_faces) < 2)
    if open_edges <= MAX_OPEN_EDGES * len(mesh.edges) and mesh.calc_volume(signed=True) < 0:
        # Stray vertices (no face) mislead Blender's guess of where the outside is: `last.usdc` has one in the
        # rock. Then the volume decides: still negative means the guess was wrong, so every face is reversed.
        bmesh.ops.delete(mesh, geom=[vertex for vertex in mesh.verts if not vertex.link_faces], context="VERTS")
        bmesh.ops.recalc_face_normals(mesh, faces=mesh.faces)
        if mesh.calc_volume(signed=True) < 0:
            bmesh.ops.reverse_faces(mesh, faces=mesh.faces)
        mesh.to_mesh(item.data)
        # Imported normals would still point inwards: let Blender compute them from the new winding.
        if item.data.has_custom_normals:
            bpy.context.view_layer.objects.active = item
            bpy.ops.mesh.customdata_custom_splitnormals_clear()
        print(f"Faces turned outwards: {item.name}")
    mesh.free()

# --- Origin at the base of the trunk, on the grass; island at its real size ---------------------------
tree_points = [vertex.co.copy() for item in meshes if parts[item] == "Tree" for vertex in item.data.vertices]
lowest = min(point.z for point in tree_points)
base = [point for point in tree_points if point.z < lowest + 0.3]
center_x = sum(point.x for point in base) / len(base)
center_y = sum(point.y for point in base) / len(base)
nearby = [vertex.co.z for vertex in grass.data.vertices
          if math.hypot(vertex.co.x - center_x, vertex.co.y - center_y) < 1.5]
ground = max(nearby) if nearby else lowest
scale = TARGET_TREE_HEIGHT / (max(point.z for point in tree_points) - lowest)
island_points = [vertex.co for item in meshes if parts[item] == "Island" for vertex in item.data.vertices]
width = max(max(point.x for point in island_points) - min(point.x for point in island_points),
            max(point.y for point in island_points) - min(point.y for point in island_points))
origin = Vector((center_x, center_y, ground))
for item in meshes:
    for vertex in item.data.vertices:
        vertex.co = (vertex.co - origin) * scale
print(f"Origin moved to the trunk {tuple(round(value, 3) for value in origin)}, scale {scale:.4f} "
      f"(tree {TARGET_TREE_HEIGHT} m, island {width * scale:.2f} m wide)")

# --- Materials: readable names, matte -----------------------------------------------------------------
for material in bpy.data.materials:
    material.name = MATERIAL_NAMES.get(material.name, material.name)
    if material.node_tree:
        for node in material.node_tree.nodes:
            if node.type == "BSDF_PRINCIPLED":
                node.inputs["Roughness"].default_value = ROUGHNESS
                node.inputs["Metallic"].default_value = 0.0

# --- Canopy band (before joining: the leaves are the tree's green blobs) ------------------------------
canopy_points = [vertex.co.copy() for item in meshes if parts[item] == "Tree"
                 and any(material and material.name == "Tree_Leaves" for material in item.data.materials)
                 for vertex in item.data.vertices]
if not canopy_points:
    raise SystemExit("No canopy found (meshes with the Tree_Leaves material)")
canopy_center = sum(canopy_points, Vector()) / len(canopy_points)
canopy_bottom = min(point.z for point in canopy_points)
canopy_top = max(point.z for point in canopy_points)
canopy_reach = max(math.hypot(point.x - canopy_center.x, point.y - canopy_center.y) for point in canopy_points)

# --- Three objects: Island, Tree, FloatingRocks --------------------------------------------------------
# Grouped first: joining deletes the other objects of a group.
groups = {name: [item for item in meshes if parts[item] == name] for name in ("Island", "Tree", "FloatingRocks")}
joined = {}
for name, group in groups.items():
    if not group:
        raise SystemExit(f"Nothing for the part '{name}'")
    for other in bpy.context.scene.objects:
        other.select_set(other in group)
    bpy.context.view_layer.objects.active = group[0]
    if len(group) > 1:
        bpy.ops.object.join()
    item = bpy.context.view_layer.objects.active
    item.name = name
    item.data.name = name
    joined[name] = item
    triangles = sum(len(polygon.vertices) - 2 for polygon in item.data.polygons)
    print(f"{name}: {len(group)} meshes, {triangles} triangles, {len(item.data.materials)} materials")

# --- Fruit hang points on the outside of the canopy ----------------------------------------------------
bpy.context.view_layer.update()
tree = joined["Tree"]
fruit_names = []


def foliage_hit(degrees, fraction):
    """First point of the foliage seen from outside the canopy, towards its centre; None between the blobs."""
    angle = math.radians(degrees)
    outward = Vector((math.cos(angle), math.sin(angle), 0))
    height = canopy_bottom + fraction * (canopy_top - canopy_bottom)
    start = Vector((canopy_center.x, canopy_center.y, height)) + outward * (canopy_reach + 0.5)
    hit, location, _, _ = tree.ray_cast(start, -outward)
    return (location, outward) if hit else None


for index, (degrees, fraction) in enumerate(FRUIT_SPOTS, start=1):
    # The canopy is made of separate blobs: a ray may pass between them, so look around the wanted spot.
    tries = [(degrees + turn, fraction + rise) for turn in (0, 8, -8, 16, -16, 24, -24) for rise in (0, 0.08, -0.08)]
    found = next((result for result in (foliage_hit(*spot) for spot in tries) if result), None)
    if found is None:
        print(f"Warning: no foliage around {degrees}° / {fraction:.2f}, fruit_{index:02d} skipped")
        continue
    location, outward = found
    empty = bpy.data.objects.new(f"fruit_{index:02d}", None)
    empty.location = location + outward * FRUIT_OFFSET - Vector((0, 0, 0.02))
    bpy.context.scene.collection.objects.link(empty)
    fruit_names.append(empty.name)
    print(f"Fruit {empty.name} at {tuple(round(value, 3) for value in empty.location)}")

# --- Export -------------------------------------------------------------------------------------------
for item in bpy.context.scene.objects:
    item.select_set(item.name in joined or item.name in fruit_names)
destination = os.path.join(OUTPUT, "FloatingIsland.usdz")
bpy.ops.wm.usd_export(filepath=destination, selected_objects_only=True, export_animation=False,
                      export_materials=True, generate_preview_surface=True, export_mesh_colors=False,
                      export_cameras=False, export_lights=False,
                      convert_orientation=True, export_global_forward_selection="NEGATIVE_Z",
                      export_global_up_selection="Y", root_prim_path="/FloatingIsland")
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUTPUT, "island.blend"))
print(f"Island asset written to {destination}")
