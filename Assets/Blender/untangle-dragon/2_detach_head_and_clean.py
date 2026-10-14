# Step 5 of the guide. Detaches the head and tidies up the scene:
# 1. head (horns, whiskers, mane, eyes) into a "DragonHead" object, the rest becomes "DragonBody";
# 2. closes the neck on both pieces;
# 3. deletes the import's armature and empty objects, removes the old vertex groups;
# 4. brings the dragon to game size (scale 0.0005: about 2.3 m) and applies the scale.
# Usage: Run Script (no selection needed), after script 1.
import bpy, bmesh


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


def close_holes(bm, border):
    """Closes every hole along the cut with a face oriented like its neighbours, then splits it into triangles."""
    remaining = {edge for edge in bm.edges if edge.is_boundary and all(key(v.co) in border for v in edge.verts)}
    created = []
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
            created.append(face)
    bmesh.ops.triangulate(bm, faces=created)
    return len(created)


HEAD_BONE = "drgon_025"
SCALE = 0.0005

if bpy.context.object and bpy.context.object.mode != "OBJECT":
    bpy.ops.object.mode_set(mode="OBJECT")
armature = original_armature()
body = dragon_body()
if any(m.type == "ARMATURE" for m in body.modifiers):
    raise RuntimeError("Run script 1_prepare_and_remove_legs.py first.")

# 1. Select the head and separate it (like Edit Mode → P → Selection).
bm = bmesh.new()
bm.from_mesh(body.data)
bm.verts.ensure_lookup_table()
head_vertices = clean_selection(bm, vertices_of_bones(body, armature, [HEAD_BONE]))
border = cut_border(bm, head_vertices)
for element in (*bm.faces, *bm.edges):
    element.select = False
for vertex in bm.verts:
    vertex.select = vertex.index in head_vertices
bm.select_flush(True)
bm.to_mesh(body.data)
bm.free()

bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.separate(type="SELECTED")
bpy.ops.object.mode_set(mode="OBJECT")
head = next(item for item in bpy.context.selected_objects if item is not body)
head.name = head.data.name = "DragonHead"
body.name = body.data.name = "DragonBody"

# 2. Neck closed on both pieces.
closed = []
for obj in (body, head):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    closed.append(close_holes(bm, border))
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()

# 3. Clean-up: only DragonBody and DragonHead remain, with no parents nor old vertex groups.
for obj in (body, head):
    world = obj.matrix_world.copy()
    obj.parent = None
    obj.matrix_world = world
    obj.vertex_groups.clear()
for obj in list(bpy.data.objects):
    if obj not in (body, head):
        bpy.data.objects.remove(obj, do_unlink=True)

# 4. Game size, scale applied.
bpy.ops.object.select_all(action="DESELECT")
for obj in (body, head):
    obj.scale = [s * SCALE for s in obj.scale]
    obj.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.object.select_all(action="DESELECT")
notify(f"Done: head detached, neck closed (body {closed[0]}, head {closed[1]}; expected 1 and 1), scene clean, scale applied.")
