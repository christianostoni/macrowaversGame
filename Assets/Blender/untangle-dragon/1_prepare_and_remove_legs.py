# Step 4 of the guide. Prepares the imported "Chinese dragon" and removes its 4 legs:
# 1. joins the eyes to the body; 2. removes the Armature modifier (the body goes back to straight);
# 3. deletes the legs (recognised by the original bones) and closes the 4 holes left behind.
# Usage: Run Script (no selection needed). Run it only once, right after the import.
import bpy, bmesh, math
from mathutils import Vector, geometry


def notify(text):
    """On Mac prints are not visible: also shows the result in a popup above the mouse."""
    print(text)
    if not bpy.app.background:
        bpy.context.window_manager.popup_menu(lambda menu, _: menu.layout.label(text=text), title="Dragon", icon="INFO")


def original_armature():
    armature = next((item for item in bpy.data.objects if item.type == "ARMATURE" and "drgon_025" in item.data.bones), None)
    if armature is None:
        raise RuntimeError("The model's armature was not found: start from a new file and import the glTF again.")
    return armature


def dragon_body():
    """The largest mesh with the vertex groups of the original bones."""
    meshes = [item for item in bpy.data.objects if item.type == "MESH" and "drgon_025" in item.vertex_groups]
    if not meshes:
        raise RuntimeError("The dragon's body was not found: start from a new file and import the glTF again.")
    return max(meshes, key=lambda item: len(item.data.vertices))


def vertices_of_bones(obj, armature, roots):
    """Vertices whose largest weight is on one of the given bones (or their children)."""
    names = set()
    for root in roots:
        bone = armature.data.bones[root]
        names |= {bone.name} | {child.name for child in bone.children_recursive}
    groups = {obj.vertex_groups[name].index for name in names if name in obj.vertex_groups}
    return {vertex.index for vertex in obj.data.vertices
            if vertex.groups and max(vertex.groups, key=lambda group: group.weight).group in groups}


def separate_parts(bm):
    """The mesh is made of many separate parts (body, horns, whiskers...): sets of vertex indices."""
    seen, parts = set(), []
    for start in bm.verts:
        if start.index in seen:
            continue
        stack, part = [start], set()
        while stack:
            vertex = stack.pop()
            if vertex.index not in part:
                part.add(vertex.index)
                stack.extend(edge.other_vert(vertex) for edge in vertex.link_edges)
        seen |= part
        parts.append(part)
    return parts


def clean_selection(bm, chosen):
    """The main body is cut vertex by vertex; small parts (claws, horns) go whole to the side where
    most of their vertices are, so no half pieces are left."""
    parts = separate_parts(bm)
    body = max(parts, key=len)
    result = chosen & body
    for part in parts:
        if part is not body and len(part & chosen) * 2 > len(part):
            result |= part
    return result


def key(co):
    return tuple(round(c, 4) for c in co)


def cut_border(bm, chosen):
    """Positions of the vertices on both sides of the cut (needed to find the holes afterwards)."""
    border = set()
    for i in chosen:
        for edge in bm.verts[i].link_edges:
            other = edge.other_vert(bm.verts[i])
            if other.index not in chosen:
                border |= {key(other.co), key(bm.verts[i].co)}
    return border


def close_holes(bm, border, world=None):
    """Closes every hole along the cut with a face oriented like its neighbours, then splits it into triangles.
    With `world` (the object's matrix) the patch is not flat but follows the body's curve (see `curved_patch`)."""
    remaining = {edge for edge in bm.edges if edge.is_boundary and all(key(v.co) in border for v in edge.verts)}
    flat, closed = [], 0
    while remaining:
        ring, stack = set(), [remaining.pop()]
        while stack:
            edge = stack.pop()
            ring.add(edge)
            for vertex in edge.verts:
                for neighbour in vertex.link_edges:
                    if neighbour in remaining:
                        remaining.discard(neighbour)
                        stack.append(neighbour)
        for face in bmesh.ops.contextual_create(bm, geom=list(ring))["faces"]:
            if not face.edges[0].is_contiguous:
                bmesh.ops.reverse_faces(bm, faces=[face])
            closed += 1
            if world is None:
                flat.append(face)
            else:
                curved_patch(bm, face, world)
    bmesh.ops.triangulate(bm, faces=flat)
    return closed


def curved_patch(bm, face, world, passes=20):
    """Covers the hole with a patch that follows the body's roundness instead of a flat face.
    The body is a straight tube around the spine axis (x = 0, z = SPINE_AXIS, along Y): the hole's border
    is "unrolled" on the cylinder (angle, y), filled with points and triangulated in 2D, then wrapped back. The
    distance from the axis of the new points is blended from the border's, so the patch joins the skin around it."""
    inverse = world.inverted()
    border = list(face.verts)
    world_border = [world @ vertex.co for vertex in border]
    angles = [math.atan2(point.x, point.z - SPINE_AXIS) for point in world_border]
    mean = math.atan2(sum(math.sin(angle) for angle in angles), sum(math.cos(angle) for angle in angles))
    radii = [math.hypot(point.x, point.z - SPINE_AXIS) for point in world_border]
    mean_radius = sum(radii) / len(radii)
    # 2D coordinates on the unrolled cylinder, centred on the hole (no jump at ±180°).
    plane = [Vector((math.remainder(angle - mean, 2 * math.pi) * mean_radius, point.y))
             for angle, point in zip(angles, world_border)]
    step = sum((plane[i] - plane[i - 1]).length for i in range(len(plane))) / len(plane)
    bmesh.ops.delete(bm, geom=[face], context="FACES_ONLY")

    # Inner points on a grid, at least half a step away from the border.
    xs, ys = [point.x for point in plane], [point.y for point in plane]
    inner = []
    x = min(xs) + step
    while x < max(xs):
        y = min(ys) + step
        while y < max(ys):
            candidate = Vector((x, y))
            if inside(candidate, plane) and min(segment_distance(candidate, plane[i - 1], plane[i])
                                                for i in range(len(plane))) > step / 2:
                inner.append(candidate)
            y += step
        x += step
    points = plane + inner
    output = geometry.delaunay_2d_cdt(points, [], [list(range(len(plane)))], 1, 1e-6)
    coordinates, triangles, origins = output[0], output[2], output[3]

    # 3D vertices: the border ones stay, the others are created on the cylinder.
    to_vertex, created, radius_of = {}, [], dict(zip(border, radii))
    for i, origin in enumerate(origins):
        if origin and origin[0] < len(border):
            to_vertex[i] = border[origin[0]]
        else:
            point = coordinates[i]
            angle = mean + point.x / mean_radius
            weights = [1 / max((point - b).length, 1e-6) ** 2 for b in plane]
            radius = sum(w * rb for w, rb in zip(weights, radii)) / sum(weights)
            vertex = bm.verts.new(inverse @ Vector((radius * math.sin(angle), point.y, SPINE_AXIS + radius * math.cos(angle))))
            radius_of[vertex] = radius
            to_vertex[i] = vertex
            created.append((vertex, point))
    faces = []
    for triangle in triangles:
        try:
            faces.append(bm.faces.new([to_vertex[i] for i in triangle]))
        except ValueError:
            pass
    # Blended radius: average of the neighbours (the border stays still), then back on the cylinder.
    for _ in range(passes):
        for vertex, _ in created:
            neighbours = [edge.other_vert(vertex) for edge in vertex.link_edges]
            radius_of[vertex] = sum(radius_of.get(n, radius_of[vertex]) for n in neighbours) / len(neighbours)
    for vertex, point in created:
        angle = mean + point.x / mean_radius
        radius = radius_of[vertex]
        vertex.co = inverse @ Vector((radius * math.sin(angle), point.y, SPINE_AXIS + radius * math.cos(angle)))
    # Same winding as the neighbouring faces: one side of the border must run the other way in the patch.
    if faces:
        edge = next((e for e in border[0].link_edges if border[1] in e.verts), None)
        if edge and len(edge.link_faces) == 2 and not edge.is_contiguous:
            bmesh.ops.reverse_faces(bm, faces=faces)
    # UVs blended from the border's: the scales' normal map continues on the patch.
    uv = bm.loops.layers.uv.active
    if uv:
        border_uv = [next((loop[uv].uv.copy() for loop in v.link_loops if loop.face not in faces), None) for v in border]
        known = [(point, value) for point, value in zip(plane, border_uv) if value is not None]
        position = {vertex: point for vertex, point in created} | dict(zip(border, plane))
        for face in faces:
            for loop in face.loops:
                point = position[loop.vert]
                weights = [1 / max((point - b).length, 1e-6) ** 2 for b, _ in known]
                loop[uv].uv = sum((value * w for (_, value), w in zip(known, weights)), Vector((0, 0))) / sum(weights)
    for face in faces:
        face.smooth = True
    return faces


def inside(point, polygon):
    """Point inside a 2D polygon (even-odd rule)."""
    result = False
    for i in range(len(polygon)):
        a, b = polygon[i - 1], polygon[i]
        if (a.y > point.y) != (b.y > point.y) and point.x < a.x + (point.y - a.y) * (b.x - a.x) / (b.y - a.y):
            result = not result
    return result


def segment_distance(point, a, b):
    ab = b - a
    t = 0 if ab.length_squared == 0 else max(0, min(1, (point - a).dot(ab) / ab.length_squared))
    return (point - (a + ab * t)).length


LEG_BONES = ["drgon_0154", "drgon_0175", "drgon_0234", "drgon_0253"]  # roots of the 4 legs
SPINE_AXIS = 346  # height (original model units) of the body's axis, straight along Y

if bpy.context.object and bpy.context.object.mode != "OBJECT":
    bpy.ops.object.mode_set(mode="OBJECT")
armature = original_armature()
body = dragon_body()

# 1. Eyes (and any other mesh bound to the same armature) into the body.
others = [item for item in bpy.data.objects if item.type == "MESH" and item is not body
          and any(m.type == "ARMATURE" and m.object is armature for m in item.modifiers)]
if others:
    bpy.ops.object.select_all(action="DESELECT")
    for item in others + [body]:
        item.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()

# 2. No more imported animation: the body stays in its straight rest pose.
for modifier in [m for m in body.modifiers if m.type == "ARMATURE"]:
    body.modifiers.remove(modifier)

# 3. Legs.
bm = bmesh.new()
bm.from_mesh(body.data)
bm.verts.ensure_lookup_table()
removed = clean_selection(bm, vertices_of_bones(body, armature, LEG_BONES))
if not removed:
    raise RuntimeError("Legs already removed? No leg vertices found.")
border = cut_border(bm, removed)
bmesh.ops.delete(bm, geom=[bm.verts[i] for i in removed], context="VERTS")
closed = close_holes(bm, border, body.matrix_world)
bm.to_mesh(body.data)
bm.free()
body.data.update()
notify(f"Done: eyes joined, legs removed ({len(removed)} vertices), holes closed: {closed} (expected 4).")
