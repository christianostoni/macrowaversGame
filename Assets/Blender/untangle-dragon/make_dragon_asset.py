# Generates DragonBody.usdz and DragonHead.usdz from Sketchfab's "Chinese dragon" glTF, without opening Blender:
#
#   /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
#       -P Assets/Blender/untangle-dragon/make_dragon_asset.py -- <path/scene.gltf> <output folder>
#
# Runs scripts 1–4 of this folder in order, plus the steps of the guide that used to be manual
# (slimming the body, new skeleton spine_00…spine_63, head with nostrils/mouth, export).
import bpy, os, sys

arguments = sys.argv[sys.argv.index("--") + 1:]
GLTF, OUTPUT = arguments[0], arguments[1]
FOLDER = os.path.dirname(os.path.abspath(__file__))

AXIS_Z = 0.173               # height of the spine after the game scale
NECK_Y, TAIL_Y = -1.225, 0.93
THICKNESS = 0.5              # body cross-section: ~3 cm radius at game size
HEAD_SCALE = 0.6
SPINE_BONES = 64             # more bones = smoother curves (the simulated body has 48 nodes)
NOSTRILS = (0, -0.135, 0.001)  # relative to the head's origin (snout towards -Y in Blender)
MOUTH = (0, -0.125, -0.023)


def run(name):
    exec(open(os.path.join(FOLDER, name)).read(), {"__name__": "__main__"})


def select(objects, active=None):
    bpy.ops.object.select_all(action="DESELECT")
    for item in objects:
        item.select_set(True)
    bpy.context.view_layer.objects.active = active or objects[0]


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLTF, merge_vertices=True)
bpy.ops.object.select_all(action="DESELECT")
run("1_prepare_and_remove_legs.py")
run("2_detach_head_and_clean.py")
body, head = bpy.data.objects["DragonBody"], bpy.data.objects["DragonHead"]

# Thinner body around the spine (width and height, not length).
for vertex in body.data.vertices:
    vertex.co.x *= THICKNESS
    vertex.co.z = AXIS_Z + (vertex.co.z - AXIS_Z) * THICKNESS

# Skeleton: one bone from neck to tail, subdivided into SPINE_BONES.
bpy.context.scene.cursor.location = (0, 0, 0)
bpy.ops.object.armature_add(location=(0, 0, 0))
armature = bpy.context.object
bpy.ops.object.mode_set(mode="EDIT")
bone = armature.data.edit_bones[0]
bone.head, bone.tail, bone.roll = (0, NECK_Y, AXIS_Z), (0, TAIL_Y, AXIS_Z), 0
bpy.ops.armature.select_all(action="SELECT")
bpy.ops.armature.subdivide(number_cuts=SPINE_BONES - 1)
run("3_rename_spine.py")
select([body, armature], active=armature)
bpy.ops.object.parent_set(type="ARMATURE_AUTO")
# Weights blended over several nearby bones: the skin bends in a curve instead of an elbow at every joint.
select([body])
bpy.ops.object.mode_set(mode="WEIGHT_PAINT")
bpy.ops.object.vertex_group_smooth(group_select_mode="ALL", factor=0.5, repeat=6, expand=0.2)
bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
bpy.ops.object.vertex_group_normalize_all(lock_active=False)
bpy.ops.object.mode_set(mode="OBJECT")

# Head: origin at the neck joint, then at the file's origin.
bpy.context.scene.cursor.location = (0, NECK_Y, AXIS_Z)
select([head])
bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
head.scale = (HEAD_SCALE,) * 3
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
head.location = (0, 0, 0)
for name, position in (("nostrils", NOSTRILS), ("mouth", MOUTH)):
    empty = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(empty)
    empty.location = position
    empty.parent = head

run("4_material.py")

os.makedirs(OUTPUT, exist_ok=True)
for name, objects in (("DragonBody", [body, armature]), ("DragonHead", [head, *head.children])):
    select(objects)
    bpy.ops.wm.usd_export(filepath=os.path.join(OUTPUT, f"{name}.usdz"), selected_objects_only=True,
                          export_animation=False, export_armatures=True, convert_orientation=True,
                          export_global_forward_selection="NEGATIVE_Z", export_global_up_selection="Y")
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUTPUT, "dragon.blend"))
print(f"Dragon assets written to {OUTPUT}")
