"""Makes the fruit floating in chapter II's sky: light copies of the design team's fruit, with their own materials.

Usage, from the repository's root:
    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
        -P Assets/Blender/sky-fruit/make_sky_fruit.py -- Sources/Macrowavers/Resources

For each fruit `<Name>.usdz` in the folder it writes `Sky<Name>.usdz` next to it (`DragonRideSceneBuilder` loads them).
In the sky the fruit are whole, 1.1 m tall and 5-30 m away, twelve at once; the orchard's models are made to be cut
open in the hand: the apple's flesh, the pomegranate's 40 seeds, the pineapple's flesh are all inside, and the apple's
leaf alone has 23,000 triangles. Drawn as they are, the sky's fruit cost ~275,000 triangles and ~230 draws a frame.
What the script does, and why:
- Opens the fruit with USD (`pxr`), keeps its materials (RealityKit Shader Graphs, which Blender cannot read or
  write) and every prim but its parts; drops the parts hidden inside a whole fruit (`HIDDEN`) and the ingredient gem.
- Joins the parts that share a material (and sidedness) into one mesh, in the fruit's own space: one draw each.
- Simplifies each joined mesh with Blender's Decimate (collapse) to its share of `TRIANGLES`, shared by surface area
  (a big skin needs more than a small leaf), never more than it had nor less than `KEPT` of it.
- Gives it normals again, smooth across edges sharper than `SMOOTH_ANGLE` apart only (the leaves keep their
  creases), and writes it back into the fruit's USD with its material: the materials read only normals and
  positions (no UVs, no colours), so nothing else is needed.
- Checks both from six sides with Workbench: the original with and without its hidden parts, each part its own
  colour (no pixel may change: they are hidden), then the light fruit's outline against the original's.
"""
import math
import os
import sys
import tempfile

import bmesh
import bpy
import numpy
from mathutils import Vector
from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, UsdUtils, Vt

arguments = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(arguments) != 1:
    raise SystemExit("Usage: ... -- <Resources folder>")
FOLDER = os.path.abspath(arguments[0])

FRUIT = ["Apple", "Pineapple", "Banana", "Pomegranate"]
# The parts inside a whole fruit (prim names, or the start of them with "*"): only seen once it is cut open.
HIDDEN = {
    "Apple": ["Flesh"],
    "Pineapple": ["flesh*"],
    "Banana": ["flesh", "pith*"],
    "Pomegranate": ["Seeds", "LeftFlesh", "RightFlesh"],
}
DROPPED = ["gem"]
# Triangles for a whole fruit, shared among its joined meshes by area; no mesh gets fewer than `FEWEST`, nor less than
# `KEPT` of its own (a small but finely cut part, like the apple's leaf, shrinks when cut down further).
TRIANGLES = 3000
FEWEST = 120
KEPT = 0.04
SMOOTH_ANGLE = math.radians(50)
# The checks, from six sides (px): the hidden parts must not show (a share of the fruit's pixels that changes
# colour without them) and the light fruit's outline must stay the original's (a share of it that differs).
CHECK_SIZE = 256
HIDDEN_LIMIT = 0.005
OUTLINE_LIMIT = 0.03


def matches(name, patterns):
    return any(name.startswith(pattern[:-1]) if pattern.endswith("*") else name == pattern for pattern in patterns)


def is_dropped(prim, root, hidden):
    while prim and prim != root:
        if matches(prim.GetName(), hidden + DROPPED):
            return True
        prim = prim.GetParent()
    return False


def gather(stage, root, hidden):
    """The kept parts, in the fruit's space, joined by (material, double sided): points, triangles, area."""
    cache = UsdGeom.XformCache()
    groups = {}
    for prim in Usd.PrimRange(root):
        if prim.GetTypeName() != "Mesh" or is_dropped(prim, root, hidden):
            continue
        mesh = UsdGeom.Mesh(prim)
        material = UsdShade.MaterialBindingAPI(prim).ComputeBoundMaterial()[0]
        key = (material.GetPath() if material else None, bool(mesh.GetDoubleSidedAttr().Get()))
        transform, _ = cache.ComputeRelativeTransform(prim, root)
        group = groups.setdefault(key, {"points": [], "faces": [], "area": 0.0})
        first = len(group["points"])
        group["points"] += [transform.Transform(Gf.Vec3d(point)) for point in mesh.GetPointsAttr().Get()]
        indices = mesh.GetFaceVertexIndicesAttr().Get()
        cursor = 0
        for count in mesh.GetFaceVertexCountsAttr().Get():
            face = [first + index for index in indices[cursor:cursor + count]]
            cursor += count
            # USD's "leftHanded" winds the other way.
            if mesh.GetOrientationAttr().Get() == UsdGeom.Tokens.leftHanded:
                face.reverse()
            group["faces"].append(face)
            corners = [group["points"][index] for index in face]
            for second, third in zip(corners[1:], corners[2:]):
                group["area"] += Gf.Cross(second - corners[0], third - corners[0]).GetLength() / 2
    return groups


def simplify(points, faces, triangles):
    """`faces` decimated to about `triangles`: (points, triangles, normals per corner)."""
    data = bpy.data.meshes.new("Part")
    data.from_pydata([tuple(point) for point in points], [], faces)
    work = bmesh.new()
    work.from_mesh(data)
    corners = numpy.array([tuple(point) for point in points])
    size = float(numpy.linalg.norm(corners.max(axis=0) - corners.min(axis=0)))
    bmesh.ops.remove_doubles(work, verts=work.verts, dist=1e-6 * max(size, 1e-3))
    bmesh.ops.triangulate(work, faces=work.faces)
    work.to_mesh(data)
    work.free()
    entity = bpy.data.objects.new("Part", data)
    bpy.context.scene.collection.objects.link(entity)
    current = len(data.polygons)
    if triangles < current:
        decimate = entity.modifiers.new("Decimate", "DECIMATE")
        decimate.decimate_type = "COLLAPSE"
        decimate.ratio = triangles / current
        decimate.use_collapse_triangulate = True
        bpy.context.view_layer.update()
        evaluated = entity.evaluated_get(bpy.context.evaluated_depsgraph_get())
        result = bpy.data.meshes.new_from_object(evaluated)
    else:
        result = data.copy()
    work = bmesh.new()
    work.from_mesh(result)
    bmesh.ops.triangulate(work, faces=work.faces)
    work.to_mesh(result)
    work.free()

    vertices = [Gf.Vec3f(*vertex.co) for vertex in result.vertices]
    corners = [[result.loops[loop].vertex_index for loop in polygon.loop_indices] for polygon in result.polygons]
    normals = [Gf.Vec3f(*polygon.normal) for polygon in result.polygons]
    areas = [polygon.area for polygon in result.polygons]
    around = {}
    for face, triangle in enumerate(corners):
        for vertex in triangle:
            around.setdefault(vertex, []).append(face)
    threshold = math.cos(SMOOTH_ANGLE)
    corner_normals = []
    for face, triangle in enumerate(corners):
        for vertex in triangle:
            total = Gf.Vec3f(0, 0, 0)
            for other in around[vertex]:
                if Gf.Dot(normals[other], normals[face]) >= threshold:
                    total += normals[other] * areas[other]
            corner_normals.append(total.GetNormalized() if total.GetLength() > 1e-12 else normals[face])
    bpy.data.objects.remove(entity)
    for mesh in (data, result):
        bpy.data.meshes.remove(mesh)
    return vertices, corners, corner_normals


def make(name):
    source = os.path.join(FOLDER, f"{name}.usdz")
    target = os.path.join(FOLDER, f"Sky{name}.usdz")
    stage = Usd.Stage.Open(Usd.Stage.Open(source).Flatten())
    root = stage.GetDefaultPrim()
    groups = gather(stage, root, HIDDEN.get(name, []))
    total_area = sum(group["area"] for group in groups.values())

    # Every part goes (the materials and anything else that is not a part stay); the joined meshes take their place.
    parts = [prim.GetPath() for prim in Usd.PrimRange(root) if prim.GetTypeName() == "Mesh"]
    for path in parts:
        stage.RemovePrim(path)
    for prim in list(root.GetChildren()):
        if prim.GetTypeName() in ("Xform", "Scope", "") and not any(
                child.GetTypeName() in ("Mesh", "Material", "Shader", "NodeGraph") for child in Usd.PrimRange(prim)):
            stage.RemovePrim(prim.GetPath())

    before = sum(len(face) - 2 for group in groups.values() for face in group["faces"])
    after = 0
    for number, ((material, double_sided), group) in enumerate(sorted(groups.items(), key=lambda item: str(item[0]))):
        share = TRIANGLES * group["area"] / max(total_area, 1e-12)
        budget = max(int(share), FEWEST, int(KEPT * len(group["faces"])))
        points, triangles, normals = simplify(group["points"], group["faces"], budget)
        after += len(triangles)
        mesh = UsdGeom.Mesh.Define(stage, root.GetPath().AppendChild(f"Sky{name}_{number}"))
        mesh.CreatePointsAttr(Vt.Vec3fArray(points))
        mesh.CreateFaceVertexCountsAttr(Vt.IntArray([3] * len(triangles)))
        mesh.CreateFaceVertexIndicesAttr(Vt.IntArray([index for triangle in triangles for index in triangle]))
        mesh.CreateNormalsAttr(Vt.Vec3fArray(normals))
        mesh.SetNormalsInterpolation(UsdGeom.Tokens.faceVarying)
        mesh.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
        mesh.CreateDoubleSidedAttr(double_sided)
        mesh.CreateExtentAttr(UsdGeom.Mesh.ComputeExtent(Vt.Vec3fArray(points)))
        if material:
            UsdShade.MaterialBindingAPI.Apply(mesh.GetPrim()).Bind(UsdShade.Material(stage.GetPrimAtPath(material)))

    folder = tempfile.mkdtemp(prefix="sky-fruit-")
    flat = os.path.join(folder, f"Sky{name}.usdc")
    stage.GetRootLayer().Export(flat)
    if os.path.exists(target):
        os.remove(target)
    if not UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(flat), target):
        raise SystemExit(f"Could not write {target}")
    os.remove(flat)
    os.rmdir(folder)
    print(f"{name}: {before} -> {after} triangles (the parts seen), {len(parts)} parts -> {len(groups)} meshes -> "
          f"{os.path.basename(target)}")
    return source, target


# MARK: - The checks


def is_hidden_object(entity, hidden):
    """`entity` or one of its parents is a part in `hidden` (Blender adds ".001" to repeated names)."""
    while entity:
        if matches(entity.name.split(".")[0], hidden):
            return True
        entity = entity.parent
    return False


def views(path, hidden):
    """The fruit from six sides, each part its own colour (RGBA), the parts in `hidden` and the gem not drawn."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.usd_import(filepath=path, import_materials=False)
    meshes = [entity for entity in bpy.data.objects if entity.type == "MESH"]
    for entity in meshes:
        entity.hide_render = is_hidden_object(entity, hidden + DROPPED)
    # Framed on the vertices themselves: a turned part's bound box is wider than the part, so the original and the
    # light fruit (whose parts are no longer turned) would be framed differently.
    corners = [entity.matrix_world @ vertex.co for entity in meshes if not entity.hide_render
               for vertex in entity.data.vertices]
    low = Vector([min(corner[axis] for corner in corners) for axis in range(3)])
    high = Vector([max(corner[axis] for corner in corners) for axis in range(3)])
    centre, reach = (low + high) / 2, max(high - low)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "FLAT"
    scene.display.shading.color_type = "RANDOM"
    scene.display.render_aa = "OFF"
    scene.view_settings.view_transform = "Standard"
    scene.render.film_transparent = True
    scene.render.resolution_x = scene.render.resolution_y = CHECK_SIZE
    scene.render.image_settings.color_mode = "RGBA"
    camera_data = bpy.data.cameras.new("Check")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = reach * 1.2
    camera = bpy.data.objects.new("Check", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    result = []
    folder = tempfile.mkdtemp(prefix="sky-fruit-check-")
    for index, direction in enumerate([(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]):
        position = centre + Vector(direction) * reach * 3
        camera.location = position
        camera.rotation_euler = (centre - position).to_track_quat("-Z", "Y" if direction[2] else "Z").to_euler()
        scene.render.filepath = os.path.join(folder, f"{index}.png")
        bpy.ops.render.render(write_still=True)
        image = bpy.data.images.load(scene.render.filepath)
        result.append(numpy.array(image.pixels[:]).reshape(CHECK_SIZE, CHECK_SIZE, 4))
        bpy.data.images.remove(image)
        os.remove(scene.render.filepath)
    os.rmdir(folder)
    return result


made = [(name, make(name)) for name in FRUIT]
failed = []
for name, (source, target) in made:
    whole = views(source, [])
    shown = views(source, HIDDEN.get(name, []))
    light = views(target, [])
    pixels = sum((view[:, :, 3] > 0.5).sum() for view in whole)
    changed = sum((numpy.abs(a - b).max(axis=2) > 0.02).sum() for a, b in zip(whole, shown)) / max(pixels, 1)
    outline = sum((view[:, :, 3] > 0.5).sum() for view in shown)
    differs = sum(numpy.logical_xor(a[:, :, 3] > 0.5, b[:, :, 3] > 0.5).sum()
                  for a, b in zip(shown, light)) / max(outline, 1)
    print(f"{name}: hidden parts change {100 * changed:.2f}% of the fruit (limit {100 * HIDDEN_LIMIT:.1f}%), "
          f"outline differs by {100 * differs:.2f}% (limit {100 * OUTLINE_LIMIT:.0f}%)")
    if changed > HIDDEN_LIMIT or differs > OUTLINE_LIMIT:
        failed.append(name)
if failed:
    raise SystemExit(f"The light fruit look different: {', '.join(failed)}")
