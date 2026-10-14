# Step 9 of the guide: renames the bone chain spine_00 (neck) ... spine_63 (tail tip).
# Usage: Run Script (no selection needed), with the new armature already subdivided into 64 bones.
import bpy

def notify(text):
    """On Mac prints are not visible: also shows the result in a popup above the mouse."""
    print(text)
    if not bpy.app.background:
        bpy.context.window_manager.popup_menu(lambda menu, _: menu.layout.label(text=text), title="Dragon", icon='INFO')


armatures = [item for item in bpy.data.objects if item.type == 'ARMATURE']
if len(armatures) != 1:
    raise RuntimeError(f"Expected a single armature in the scene, found {len(armatures)}.")
armature = armatures[0]
if bpy.context.object and bpy.context.object.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.select_all(action='DESELECT')
armature.select_set(True)
bpy.context.view_layer.objects.active = armature
bpy.ops.object.mode_set(mode='EDIT')
bones = armature.data.edit_bones
chain = [next(bone for bone in bones if bone.parent is None)]
while chain[-1].children:
    chain.append(chain[-1].children[0])
for index, bone in enumerate(chain):
    bone.name = f"spine_{index:02d}"
bpy.ops.object.mode_set(mode='OBJECT')
notify(f"Renamed {len(chain)} bones: spine_00 ... spine_{len(chain) - 1:02d} (expected 64).")
