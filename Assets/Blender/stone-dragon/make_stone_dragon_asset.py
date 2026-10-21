"""Prepares the design team's stone dragon for RealityKit, without opening Blender.

Usage:
    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
        -P Assets/Blender/stone-dragon/make_stone_dragon_asset.py -- \
        Assets/Blender/stone-dragon/cartoon_dragon_rcp.usdz <output folder>

The source (`CartoonDragon_RCP.usdz`, prepared in Reality Composer Pro from a Sketchfab model) is a dragon made of
separate stones: a head
(`Cube_Face_0`, `Cube_Horns_0`, `Cube_Teeth_0` and an empty `Jaw_Hinge`) and a chain of 19 rounded stones ending
in a flat tail stone, ~13 m long, with an idle animation on every stone and an animated face. What the script
does, and why:
- Reads the rest pose (first frame) and drops the animation (the stones' transform caches and the face's mesh
  sequence cache): the game moves every stone along the simulated body.
- Orders the stones from the head to the tail (each is the closest to the previous one) and names them
  `Stone_00` (behind the head) ... `Stone_19` (the tail), each with its origin at its centre, its local +Z along the
  body towards the tail and its +Y up: the game turns them along the simulated curve.
- Scales everything so the chain, from the head's centre to the tail stone's centre, is `SIM_LENGTH` long (the
  simulated body's length); the game still scales the stones' thickness to the simulated body.
- Builds `Head`: origin at the face's centre, snout towards +Z, +Y up, with the face, the horns and the (upper)
  teeth. The source opens the mouth in the face's animation: the pieces of the face that move in it are the lower
  jaw. They become `Jaw`, under `JawHinge` (at the source's `Jaw_Hinge`), so the game opens the mouth by turning
  the hinge around its +X. `mouth` and `nostrils` mark where fire and smoke come out.
- Keeps the design team's materials exactly as they are: `AirbrushGrain` (and the unused `AirbrushGrain_Eye`) are
  Reality Composer Pro shader graphs (unlit: a colour ramp driven by the facing angle and an animated world-space
  grain) that Blender cannot read. Blender exports the geometry only; USD (`pxr`) then copies the material prims
  from the source unchanged and binds `AirbrushGrain` to every mesh, as in the source.
- Exports a Y-up USDZ under `/Dragon` (the materials' own paths, so their connections stay valid).
"""
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
from pxr import Sdf, Usd, UsdGeom, UsdShade, UsdUtils

arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(arguments) != 2:
    raise SystemExit("Usage: ... -- <cartoon_dragon_rcp.usdz> <output folder>")
SOURCE, OUTPUT = (os.path.abspath(argument) for argument in arguments)
os.makedirs(OUTPUT, exist_ok=True)

# Length of the chain in the game (m): the simulated body (TangleConfig: 63 segments, 2.35 m).
SIM_LENGTH = 2.35
# The source's materials (Reality Composer Pro shader graphs) and the one every mesh uses.
MATERIALS = "/Dragon/Materials"
STONE_MATERIAL = MATERIALS + "/AirbrushGrain"
UP = Vector((0, 0, 1))

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(filepath=SOURCE, import_materials=False, import_cameras=False, import_lights=False)
scene = bpy.context.scene
scene.frame_set(scene.frame_start)
bpy.context.view_layer.update()

# --- The lower jaw: the face's pieces its animation moves -----------------------------------------------------
def face_points(item, frame):
    scene.frame_set(frame)
    evaluated = item.evaluated_get(bpy.context.evaluated_depsgraph_get())
    return [vertex.co.copy() for vertex in evaluated.data.vertices]


source_face = next((item for item in scene.objects if item.type == "MESH" and "Face" in item.name), None)
if source_face is None:
    raise SystemExit(f"{SOURCE}: no face mesh: is it the right file?")
rest_face = face_points(source_face, scene.frame_start)
travel = [0.0] * len(rest_face)
for frame in range(scene.frame_start, scene.frame_end + 1, 5):
    travel = [max(old, (point - rest).length)
              for old, point, rest in zip(travel, face_points(source_face, frame), rest_face)]
scene.frame_set(scene.frame_start)
bpy.context.view_layer.update()
# The face is made of loose pieces: a piece belongs to the jaw when any of its vertices travels far.
mesh = bmesh.new()
mesh.from_mesh(source_face.data)
mesh.verts.ensure_lookup_table()
jaw_vertices = set()
seen = set()
for start in mesh.verts:
    if start.index in seen:
        continue
    piece, stack = [], [start]
    while stack:
        vertex = stack.pop()
        if vertex.index in seen:
            continue
        seen.add(vertex.index)
        piece.append(vertex.index)
        stack += [edge.other_vert(vertex) for edge in vertex.link_edges]
    if max(travel[index] for index in piece) > 0.25 * max(travel):
        jaw_vertices.update(piece)
mesh.free()
if not jaw_vertices:
    raise SystemExit(f"{SOURCE}: the face's animation moves nothing: no jaw to split")
print(f"Jaw: {len(jaw_vertices)} of {len(rest_face)} face vertices")

# --- Rest pose baked into the vertices (world space), no parents, no animation ---------------------------------
meshes = [item for item in scene.objects if item.type == "MESH"]
hinge_source = scene.objects.get("Jaw_Hinge")
if hinge_source is None:
    raise SystemExit(f"{SOURCE}: no Jaw_Hinge: is it the right file?")
hinge = hinge_source.matrix_world.translation.copy()
for item in meshes:
    matrix = item.matrix_world.copy()
    item.data = item.data.copy()
    item.data.transform(matrix)
for item in list(scene.objects):
    if item not in meshes:
        bpy.data.objects.remove(item)
for item in meshes:
    # The face also has a mesh sequence cache (its animated expression): left on, it would overwrite the
    # baked, scaled vertices with the source's at export time.
    item.modifiers.clear()
    item.constraints.clear()
    item.animation_data_clear()
    item.parent = None
    item.matrix_world = Matrix.Identity(4)


def centre(item):
    points = [vertex.co for vertex in item.data.vertices]
    low = Vector([min(point[axis] for point in points) for axis in range(3)])
    high = Vector([max(point[axis] for point in points) for axis in range(3)])
    return (low + high) / 2


def part(keyword):
    found = [item for item in meshes if keyword in item.name]
    if len(found) != 1:
        raise SystemExit(f"{SOURCE}: expected one '{keyword}' mesh, found {len(found)}")
    return found[0]


face, horns, teeth = part("Face"), part("Horns"), part("Teeth")
loose = [item for item in meshes if item not in (face, horns, teeth)]

# The jaw's pieces leave the face for their own object.
jaw_part = face.copy()
jaw_part.data = face.data.copy()
scene.collection.objects.link(jaw_part)
for item, drop in ((face, lambda index: index in jaw_vertices), (jaw_part, lambda index: index not in jaw_vertices)):
    mesh = bmesh.new()
    mesh.from_mesh(item.data)
    mesh.verts.ensure_lookup_table()
    bmesh.ops.delete(mesh, geom=[vertex for vertex in mesh.verts if drop(vertex.index)], context="VERTS")
    mesh.to_mesh(item.data)
    mesh.free()
meshes.append(jaw_part)
head_centre = centre(face)

# --- Stones in order, from the head to the tail ----------------------------------------------------------------
chain = []
current = head_centre
while loose:
    nearest = min(loose, key=lambda item: (centre(item) - current).length)
    chain.append(nearest)
    loose.remove(nearest)
    current = centre(nearest)
if "Tail" not in chain[-1].name:
    raise SystemExit(f"{SOURCE}: the chain ends at {chain[-1].name}, not at the tail")
centres = [centre(item) for item in chain]
length = (centres[0] - head_centre).length + sum((centres[i] - centres[i - 1]).length for i in range(1, len(centres)))
factor = SIM_LENGTH / length
print(f"{len(chain)} stones, chain {length:.3f} units -> {SIM_LENGTH} m (x{factor:.5f})")

# Everything scaled around the head's centre, which becomes the origin.
for item in meshes:
    for vertex in item.data.vertices:
        vertex.co = (vertex.co - head_centre) * factor
hinge = (hinge - head_centre) * factor
centres = [(point - head_centre) * factor for point in centres]
head_centre = Vector((0, 0, 0))


def basis(forward, up=UP):
    """Columns: +X = up × forward (right-handed), +Y = up (made perpendicular), +Z = forward."""
    forward = forward.normalized()
    up = (up - forward * up.dot(forward))
    up = up.normalized() if up.length > 1e-6 else Vector((0, 1, 0))
    right = up.cross(forward)
    return Matrix((right, up, forward)).transposed()


def place(item, origin, rotation):
    """Expresses the mesh in a local frame at `origin` with `rotation`, and gives the object that frame."""
    inverse = rotation.transposed()
    for vertex in item.data.vertices:
        vertex.co = inverse @ (vertex.co - origin)
    item.matrix_world = Matrix.Translation(origin) @ rotation.to_4x4()


for index, item in enumerate(chain):
    previous = centres[index - 1] if index > 0 else head_centre
    following = centres[index + 1] if index + 1 < len(centres) else centres[index] + (centres[index] - previous)
    place(item, centres[index], basis(following - previous))
    item.name = item.data.name = f"Stone_{index:02d}"

# --- Head: snout +Z, jaw on its hinge, fire and smoke markers ---------------------------------------------------
towards_body = centres[0] - head_centre
towards_body.z = 0
head_rotation = basis(-towards_body)
head = bpy.data.objects.new("Head", None)
scene.collection.objects.link(head)
head.matrix_world = head_rotation.to_4x4()
for item, name in ((face, "Face"), (horns, "Horns"), (teeth, "Teeth")):
    place(item, head_centre, head_rotation)
    item.parent = head
    item.matrix_parent_inverse = Matrix.Identity(4)
    item.matrix_basis = Matrix.Identity(4)
    item.name = item.data.name = name
local_hinge = head_rotation.transposed() @ hinge
hinge_entity = bpy.data.objects.new("JawHinge", None)
scene.collection.objects.link(hinge_entity)
hinge_entity.parent = head
hinge_entity.matrix_basis = Matrix.Translation(local_hinge)
place(jaw_part, head_centre, head_rotation)
for vertex in jaw_part.data.vertices:
    vertex.co -= local_hinge
jaw_part.parent = hinge_entity
jaw_part.matrix_parent_inverse = Matrix.Identity(4)
jaw_part.matrix_basis = Matrix.Identity(4)
jaw_part.name = jaw_part.data.name = "Jaw"

upper = [vertex.co for vertex in face.data.vertices] + [vertex.co for vertex in teeth.data.vertices]
lower = [vertex.co + local_hinge for vertex in jaw_part.data.vertices]
tip = max(point.z for point in upper + lower)
jaw_top = max(point.y for point in lower)
snout_top = max(point.y for point in upper if point.z > 0.8 * tip)
for name, position in (("mouth", (0, jaw_top, 0.9 * tip)),
                       ("nostrils", (0, jaw_top + 0.75 * (snout_top - jaw_top), 0.97 * tip))):
    marker = bpy.data.objects.new(name, None)
    scene.collection.objects.link(marker)
    marker.parent = head
    marker.matrix_basis = Matrix.Translation(Vector(position))
    print(f"{name} at {tuple(round(value, 4) for value in position)}")

for item in chain + [face, horns, teeth, jaw_part]:
    points = [vertex.co for vertex in item.data.vertices]
    size = Vector([max(point[axis] for point in points) - min(point[axis] for point in points) for axis in range(3)])
    print(f"{item.name}: {len(item.data.polygons)} faces, size {tuple(round(value, 4) for value in size)} m")

# --- Export: the geometry from Blender, the materials from the source ----------------------------------------
for item in meshes:
    item.data.materials.clear()
for item in scene.objects:
    item.select_set(True)
geometry = os.path.join(OUTPUT, "StoneDragon_geometry.usdc")
bpy.ops.wm.usd_export(filepath=geometry, selected_objects_only=True, export_animation=False,
                      export_materials=False, export_mesh_colors=False,
                      export_cameras=False, export_lights=False, export_subdivision="IGNORE",
                      convert_orientation=True, export_global_forward_selection="NEGATIVE_Z",
                      export_global_up_selection="Y", root_prim_path="/Dragon")
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUTPUT, "stone_dragon.blend"))

source_layer = Usd.Stage.Open(SOURCE).GetRootLayer()
if not source_layer.GetPrimAtPath(STONE_MATERIAL):
    raise SystemExit(f"{SOURCE}: no {STONE_MATERIAL}: is it the right file?")
stage = Usd.Stage.Open(geometry)
stage.DefinePrim(MATERIALS, "Scope")
for material in source_layer.GetPrimAtPath(MATERIALS).nameChildren:
    if not Sdf.CopySpec(source_layer, material.path, stage.GetRootLayer(), material.path):
        raise SystemExit(f"Could not copy {material.path}")
    print(f"Material {material.path} copied")
stone = UsdShade.Material(stage.GetPrimAtPath(STONE_MATERIAL))
bound = 0
for prim in stage.Traverse():
    if prim.IsA(UsdGeom.Mesh):
        UsdShade.MaterialBindingAPI.Apply(prim).Bind(stone)
        bound += 1
stage.GetRootLayer().Save()
print(f"{STONE_MATERIAL} bound to {bound} meshes")

destination = os.path.join(OUTPUT, "StoneDragon.usdz")
if not UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(geometry), destination):
    raise SystemExit(f"Could not package {destination}")
os.remove(geometry)
print(f"Stone dragon written to {destination}")
