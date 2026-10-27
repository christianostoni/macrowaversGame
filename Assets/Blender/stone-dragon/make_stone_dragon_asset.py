"""Prepares the design team's stone dragon for RealityKit, without opening Blender.

Usage:
    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
        -P Assets/Blender/stone-dragon/make_stone_dragon_asset.py -- \
        Assets/Blender/stone-dragon/cartoon_dragon_rcp.usdz <output folder>

The source (`CartoonDragon12_RCP_v2.usdz`, prepared in Reality Composer Pro from a Sketchfab model) is a dragon made
of separate stones: a head (`Cube_Face_0`, skinned to a two-bone skeleton `JawRig` (`Root`, `Jaw`), `Cube_Horns_0`,
`Cube_Teeth_0`) and a chain of 19 stones (`Block12` meshes) ending in a flat tail stone (`Block12_Tail`), ~13 m
long, with an idle animation on every stone and a jaw animation. What the script does, and why:
- Reads the rest pose (first frame) and drops the animation and the skeleton (the stones' transform caches, the
  face's armature): the game moves every stone along the simulated body and opens the jaw itself.
- Orders the stones from the head to the tail (each is the closest to the previous one) and names them
  `Stone_00` (behind the head) ... `Stone_18` (the tail), each with its origin at its centre, its local +Z along the
  body towards the tail and its +Y up: the game turns them along the simulated curve.
- Scales everything so the chain, from the head's centre to the tail stone's centre, is `SIM_LENGTH` long (the
  simulated body's length); the game still scales the stones' thickness to the simulated body.
- Builds `Head`: origin at the face's centre, snout towards +Z, +Y up, with the face, the horns and the (upper)
  teeth. The face's faces whose vertices all follow the `Jaw` bone are the lower jaw: they become `Jaw`, under
  `JawHinge` (at the head of that bone), so the game opens the mouth by turning the hinge around its +X. Every
  other face, those bridging the two included, stays on the head: none is lost at the seam. `mouth` and `nostrils`
  mark where fire and smoke come out.
- Keeps the design team's materials as they are: `AirbrushGrain_00` (the head) ... `AirbrushGrain_19` (one per
  stone) are Reality Composer Pro shader graphs (unlit: a colour ramp driven by the facing angle and a grain that
  drifts slowly over the surface) that Blender cannot read. Blender exports the geometry only and notes which
  material each mesh had; USD (`pxr`) then copies the material prims from the source and binds each mesh to its
  own, as in the source (the lower jaw keeps the face's). One value changes: the grain is laid out in the mesh's
  own (object) space, and the bake above resizes every mesh's coordinates, so each material's `GrainScale` is
  divided by that resize: the grain keeps the size it had on the source.
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
# Where the source keeps its materials (Reality Composer Pro shader graphs).
MATERIALS = "/Dragon/Materials"
# The face's bone that opens the mouth.
JAW_BONE = "Jaw"
UP = Vector((0, 0, 1))

bpy.ops.wm.read_factory_settings(use_empty=True)
# Materials imported only for their names: Blender cannot read the shader graphs, USD copies them at the end.
bpy.ops.wm.usd_import(filepath=SOURCE, import_materials=True, import_cameras=False, import_lights=False)
scene = bpy.context.scene
scene.frame_set(scene.frame_start)
bpy.context.view_layer.update()

# --- The lower jaw: the face's vertices skinned to the jaw bone, and the point that bone turns around -------------
source_face = next((item for item in scene.objects if item.type == "MESH" and "Face" in item.name), None)
if source_face is None:
    raise SystemExit(f"{SOURCE}: no face mesh: is it the right file?")
jaw_group = source_face.vertex_groups.get(JAW_BONE)
rig = next((item for item in scene.objects if item.type == "ARMATURE" and JAW_BONE in item.data.bones), None)
if jaw_group is None or rig is None:
    raise SystemExit(f"{SOURCE}: the face is not skinned to a '{JAW_BONE}' bone: is it the right file?")
jaw_vertices = {vertex.index for vertex in source_face.data.vertices
                for weight in vertex.groups if weight.group == jaw_group.index and weight.weight > 0.5}
if not jaw_vertices:
    raise SystemExit(f"{SOURCE}: no face vertex follows the '{JAW_BONE}' bone: no jaw to split")
jaw_hinge = rig.matrix_world @ rig.data.bones[JAW_BONE].head_local
print(f"Jaw: {len(jaw_vertices)} of {len(source_face.data.vertices)} face vertices skinned to '{JAW_BONE}'")

# --- Rest pose baked into the vertices (world space), no parents, no animation ---------------------------------
meshes = [item for item in scene.objects if item.type == "MESH"]
# Each mesh's material, by name (the source's material prims have the same names).
materials = {item: item.data.materials[0].name for item in meshes if item.data.materials and item.data.materials[0]}
hinge = jaw_hinge.copy()
# How much the bake resizes each mesh's own coordinates (its world scale; the chain's scale comes later).
bake_scale = {}
for item in meshes:
    matrix = item.matrix_world.copy()
    bake_scale[item] = abs(matrix.to_3x3().determinant()) ** (1 / 3)
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

# The jaw's pieces leave the face for their own object, face by face: a face goes to the jaw when all its vertices
# follow the jaw bone, otherwise it stays on the head (the faces bridging the two too: whole with the mouth closed,
# they stay with the head as it opens). Splitting by vertices instead deleted, from both parts, the faces that
# bridge the two (11 of the face's 185: holes in the head).
def is_jaw(polygon):
    return all(vertex.index in jaw_vertices for vertex in polygon.verts)


jaw_part = face.copy()
jaw_part.data = face.data.copy()
scene.collection.objects.link(jaw_part)
face_count = len(face.data.polygons)
for item, keeps_jaw in ((face, False), (jaw_part, True)):
    mesh = bmesh.new()
    mesh.from_mesh(item.data)
    mesh.verts.ensure_lookup_table()
    bmesh.ops.delete(mesh, geom=[polygon for polygon in mesh.faces if is_jaw(polygon) != keeps_jaw],
                     context="FACES_ONLY")
    bmesh.ops.delete(mesh, geom=[vertex for vertex in mesh.verts if not vertex.link_faces], context="VERTS")
    mesh.to_mesh(item.data)
    mesh.free()
if len(face.data.polygons) + len(jaw_part.data.polygons) != face_count:
    raise SystemExit(f"The face lost faces in the split: {face_count} -> "
                     f"{len(face.data.polygons)} + {len(jaw_part.data.polygons)}")
meshes.append(jaw_part)
bake_scale[jaw_part] = bake_scale[face]
if face in materials:
    materials[jaw_part] = materials[face]
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
# Material -> how much its meshes' own coordinates grew in all (the rotations of `place` below keep sizes).
resize = {}
for item, material in materials.items():
    value = bake_scale[item] * factor
    if material in resize and abs(resize[material] - value) > 1e-3 * value:
        raise SystemExit(f"{material}: its meshes are resized differently ({resize[material]} and {value})")
    resize[material] = value

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
# Mesh name (as exported) -> its material.
bindings = {item.data.name: materials[item] for item in meshes if item in materials}
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
    # A grain laid out in object space keeps its size on the resized meshes (world space would not need it).
    shader = UsdShade.Material(stage.GetPrimAtPath(material.path))
    grain_scale = shader.GetInput("GrainScale")
    position = stage.GetPrimAtPath(material.path.AppendChild("Position"))
    in_object_space = position and position.GetAttribute("inputs:space").Get() == "object"
    if grain_scale and in_object_space and material.name in resize:
        grain_scale.Set(grain_scale.Get() / resize[material.name])
        print(f"Material {material.path} copied, GrainScale {grain_scale.Get():.2f}")
    else:
        print(f"Material {material.path} copied")
for prim in stage.Traverse():
    if not prim.IsA(UsdGeom.Mesh):
        continue
    name = bindings.get(prim.GetName())
    material = UsdShade.Material(stage.GetPrimAtPath(f"{MATERIALS}/{name}")) if name else None
    if not material:
        raise SystemExit(f"No material for {prim.GetPath()} ({name})")
    UsdShade.MaterialBindingAPI.Apply(prim).Bind(material)
    print(f"{prim.GetName()} -> {name}")
stage.GetRootLayer().Save()

destination = os.path.join(OUTPUT, "StoneDragon.usdz")
if not UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(geometry), destination):
    raise SystemExit(f"Could not package {destination}")
os.remove(geometry)
print(f"Stone dragon written to {destination}")
