# Step 11 of the guide: solid red body material, lit by the room, with no light of its own.
# This model's "emissive" texture is not the dragon's colour (it is pale and greenish):
# exported as is, it would make the dragon glow white. The normal map (scales) and the glossy coat stay.
# Usage: with any object selected, Run Script.
import bpy

def notify(text):
    """On Mac prints are not visible: also shows the result in a popup above the mouse."""
    print(text)
    if not bpy.app.background:
        bpy.context.window_manager.popup_menu(lambda menu, _: menu.layout.label(text=text), title="Dragon", icon='INFO')


RED = (0.45, 0.02, 0.03, 1.0)  # linear values; can be changed later in Material Properties → Base Color

material = bpy.data.materials["MI_b09_00_drg_hair"]
shader = next(node for node in material.node_tree.nodes if node.type == 'BSDF_PRINCIPLED')
for socket in ("Emission Color", "Base Color"):
    for link in list(shader.inputs[socket].links):
        material.node_tree.links.remove(link)
shader.inputs["Emission Strength"].default_value = 0.0
shader.inputs["Base Color"].default_value = RED
notify("Body material updated.")
